import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import admin from "firebase-admin";

admin.initializeApp();

const usdaApiKeySecret = defineSecret("USDA_API_KEY");

type RawMenuItem = {
  id: string;
  name: string;
  calories: number;
  protein: number;
};

type RawMenuLine = {
  id: string;
  name: string;
  items: RawMenuItem[];
};

type WeekMenuResponse = {
  days?: Array<{
    date?: string;
    menu_items?: Array<{
      is_station_header?: boolean;
      text?: string;
      food?: {
        id?: string | number;
        name?: string;
        rounded_nutrition_info?: {
          calories?: number;
          g_protein?: number;
        };
      };
    }>;
  }>;
};

type USDASearchResponse = {
  foods?: USDAFood[];
};

type USDAFood = {
  fdcId?: number;
  description?: string;
  brandOwner?: string;
  brandName?: string;
  servingSize?: number;
  servingSizeUnit?: string;
  householdServingFullText?: string;
  foodNutrients?: USDAFoodNutrient[];
};

type USDAFoodNutrient = {
  nutrientNumber?: string;
  value?: number;
};

const SCHOOL_ID = "four-winds";
const MENU_TYPE = "lunch";
const TIME_ZONE = "America/Los_Angeles";
const TARGET_DOC = "menus/today";
const USDA_SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search";

function slug(input: string): string {
  return input
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

function isValidNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function trimToNull(value: string | undefined): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function datePartsInZone(now: Date, timeZone: string): { isoDate: string; endpointDate: string } {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  });

  const parts = formatter.formatToParts(now);
  const year = parts.find((p) => p.type === "year")?.value;
  const month = parts.find((p) => p.type === "month")?.value;
  const day = parts.find((p) => p.type === "day")?.value;

  if (!year || !month || !day) {
    throw new Error("Could not compute zoned date parts.");
  }

  return {
    isoDate: `${year}-${month}-${day}`,
    endpointDate: `${year}/${month}/${day}`
  };
}

function parseLines(dayItems: NonNullable<WeekMenuResponse["days"]>[number]["menu_items"]): RawMenuLine[] {
  const lines: RawMenuLine[] = [];

  for (const item of dayItems ?? []) {
    if (item?.is_station_header && item.text?.trim()) {
      const header = item.text.trim();
      lines.push({
        id: slug(header) || `line-${lines.length + 1}`,
        name: header,
        items: []
      });
      continue;
    }

    if (!item?.food) {
      continue;
    }

    const name = item.food.name?.trim();
    const caloriesRaw = item.food.rounded_nutrition_info?.calories ?? 0;
    const proteinRaw = item.food.rounded_nutrition_info?.g_protein ?? 0;

    if (!name) {
      continue;
    }
    if (!isValidNumber(caloriesRaw) || !isValidNumber(proteinRaw)) {
      continue;
    }
    if (caloriesRaw < 0 || proteinRaw < 0) {
      continue;
    }

    if (lines.length === 0) {
      lines.push({ id: "menu", name: "Menu", items: [] });
    }

    lines[lines.length - 1].items.push({
      id: String(item.food.id ?? `${slug(name)}-${lines[lines.length - 1].items.length + 1}`),
      name,
      calories: Math.round(caloriesRaw),
      protein: Math.round(proteinRaw)
    });
  }

  return lines.filter((line) => line.items.length > 0);
}

async function fetchTodayMenuFromNutrislice(now: Date): Promise<{ sourceDate: string; lines: RawMenuLine[] }> {
  const { isoDate, endpointDate } = datePartsInZone(now, TIME_ZONE);
  const url = `https://pccdining.api.nutrislice.com/menu/api/weeks/school/${SCHOOL_ID}/menu-type/${MENU_TYPE}/${endpointDate}/`;

  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Nutrislice request failed with status ${response.status}`);
  }

  const json = (await response.json()) as WeekMenuResponse;
  const day = json.days?.find((d) => d.date === isoDate);
  if (!day) {
    throw new Error(`No menu day returned for ${isoDate}`);
  }

  return {
    sourceDate: isoDate,
    lines: parseLines(day.menu_items)
  };
}

async function syncMenu(now = new Date()): Promise<{ sourceDate: string; lineCount: number; itemCount: number }> {
  const { sourceDate, lines } = await fetchTodayMenuFromNutrislice(now);
  const itemCount = lines.reduce((sum, line) => sum + line.items.length, 0);

  await admin
    .firestore()
    .doc(TARGET_DOC)
    .set(
      {
        source: "nutrislice",
        sourceDate,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
        lines
      },
      { merge: true }
    );

  logger.info("Menu sync complete", {
    target: TARGET_DOC,
    sourceDate,
    lineCount: lines.length,
    itemCount
  });

  return { sourceDate, lineCount: lines.length, itemCount };
}

function mapUSDANutrients(nutrients: USDAFoodNutrient[]): Record<string, number> {
  const mapped: Record<string, number> = {};

  const set = (key: string, numbers: string[]) => {
    const nutrient = nutrients.find((item) => numbers.includes(item.nutrientNumber ?? ""));
    if (!isValidNumber(nutrient?.value) || nutrient.value < 0) {
      return;
    }
    mapped[key] = Math.round(nutrient.value);
  };

  set("calories", ["208"]);
  set("g_protein", ["203"]);
  set("g_fat", ["204"]);
  set("g_carbs", ["205"]);
  set("g_fiber", ["291"]);
  set("g_sugar", ["269"]);
  set("mg_calcium", ["301"]);
  set("mg_iron", ["303"]);
  set("mg_potassium", ["306"]);
  set("mg_sodium", ["307"]);
  set("iu_vitamin_a", ["318"]);
  set("mcg_vitamin_a", ["320"]);
  set("mg_vitamin_c", ["401"]);
  set("mg_cholesterol", ["601"]);
  set("g_trans_fat", ["605"]);
  set("g_saturated_fat", ["606"]);
  set("mcg_vitamin_d", ["328"]);

  return mapped;
}

function mapUSDAFood(food: USDAFood) {
  if (!isValidNumber(food.fdcId)) {
    return null;
  }

  const name = trimToNull(food.description);
  if (!name) {
    return null;
  }

  const nutrientValues = mapUSDANutrients(food.foodNutrients ?? []);
  const calories = nutrientValues.calories ?? 0;
  const hasUsefulNutrition = calories > 0
    || Object.entries(nutrientValues).some(([key, value]) => key !== "calories" && value > 0);

  if (!hasUsefulNutrition) {
    return null;
  }

  const servingDescription = trimToNull(food.householdServingFullText);
  const servingAmount = isValidNumber(food.servingSize) && food.servingSize > 0
    ? food.servingSize
    : (servingDescription ? 1 : 100);
  const servingUnit = trimToNull(food.servingSizeUnit)?.toLowerCase()
    ?? (servingDescription ? "serving" : "g");
  const brand = trimToNull(food.brandOwner) ?? trimToNull(food.brandName);

  const { calories: _calories, ...remainingNutrients } = nutrientValues;

  return {
    fdcId: Math.round(food.fdcId),
    name,
    brand,
    calories,
    nutrientValues: remainingNutrients,
    servingAmount,
    servingUnit,
    servingDescription
  };
}

async function performUSDASearch(query: string) {
  const trimmedQuery = query.trim();
  if (!trimmedQuery) {
    return { status: 400, body: { error: "Enter a food name to search." } };
  }

  const apiKey = usdaApiKeySecret.value().trim();
  if (!apiKey) {
    logger.error("USDA search requested without USDA_API_KEY configured.");
    return { status: 500, body: { error: "USDA search is not configured on the server." } };
  }

  const url = new URL(USDA_SEARCH_URL);
  url.searchParams.set("api_key", apiKey);
  url.searchParams.set("query", trimmedQuery);
  url.searchParams.set("pageSize", "15");

  const response = await fetch(url);
  if (!response.ok) {
    logger.error("USDA upstream search failed", { status: response.status });
    return { status: 502, body: { error: `USDA search failed (HTTP ${response.status}).` } };
  }

  const json = await response.json() as USDASearchResponse;
  const foods = (json.foods ?? [])
    .map(mapUSDAFood)
    .filter((food): food is NonNullable<typeof food> => food !== null);

  if (foods.length === 0) {
    return { status: 404, body: { error: "No foods matched that search." } };
  }

  return { status: 200, body: { foods } };
}

export const searchUSDAFoods = onRequest({ region: "us-central1", secrets: [usdaApiKeySecret] }, async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed." });
    return;
  }

  try {
    const query = typeof req.query.query === "string" ? req.query.query : "";
    const result = await performUSDASearch(query);
    res.status(result.status).json(result.body);
  } catch (error) {
    logger.error("USDA search proxy failed", error);
    res.status(500).json({
      error: error instanceof Error ? error.message : "Unknown error"
    });
  }
});
