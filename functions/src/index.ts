import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import admin from "firebase-admin";

admin.initializeApp();

const usdaApiKeySecret = defineSecret("USDA_API_KEY");
const geminiApiKeySecret = defineSecret("GEMINI_API_KEY");

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

// --- Plate portion estimate (Gemini) ---

const GEMINI_SYSTEM_PROMPT = `You are a portion estimator. You will receive a photo of a plate of food and a list of food items with context.
The plate is 11 inches in diameter — use this for scale when estimating portions.
Not every listed item may be on the plate. Only estimate what you actually see.
IMPORTANT: If an item is NOT on the plate or not visible, use exactly "0 oz" (never guess 1 oz or 1).

For each item you receive: name, calories per serving, and serving size (e.g. "1 each", "4 oz", "0.5 cups", "113g").
If the serving is already given in an explicit unit (oz, g/grams, cups, tablespoons, teaspoons), TREAT THAT AS THE BASE SERVING and do NOT change it — just copy it through as the base. Only infer base oz when the serving is ambiguous ("1 each", "1 serving", etc.), using calories and food type: dense protein ~50–60 cal/oz, rice/grains ~35–40 cal/oz, sauces/veg ~15–25 cal/oz. Do not default to 4 oz — infer from calories and the food type.
Then estimate the portion actually on the plate in oz.

You MUST respond ONLY with valid JSON, no extra text, matching this shape:
{
  "items": [
    {
      "name": "Steamed White Rice",
      "portionOz": 3.5,
      "portionCount": 0,
      "baseServingOz": 4.0
    }
  ]
}

Rules for the JSON:
- Use the exact item name from the list for "name".
- For oz-based items (entrees, sides, rice, etc.), set "portionOz" to the estimated oz on the plate (0 if not on plate). Omit "portionCount" or set it to 0.
- For count-based items (cookies, chips, pieces), set "portionCount" to the integer count (0 if not on plate). Omit "portionOz" or set it to 0.
- For "baseServingOz":
  - If the serving is explicit (oz, grams, cups, tbsp/tsp), convert that serving to oz and copy it as "baseServingOz" without changing it.
  - If the serving is ambiguous ("1 each", "1 serving", etc.), infer oz per serving from calories and food type (dense protein ~50–60 cal/oz, rice/grains ~35–40 cal/oz, sauces/veg ~15–25 cal/oz).
  - Use 0 or omit "baseServingOz" for pure count-based snack items where oz base is not meaningful.

Do NOT include any explanations, labels, or markdown. Return only the JSON object.`;

type PlateJsonItem = {
  name?: string;
  portionOz?: unknown;
  portionCount?: unknown;
  baseServingOz?: unknown;
};

function parsePlateJsonResponse(
  text: string,
  foodNames: string[]
): { ozByFoodName: Record<string, number>; countByFoodName: Record<string, number>; baseOzByFoodName: Record<string, number> } | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object" || !Array.isArray((parsed as any).items)) {
    return null;
  }

  const items = (parsed as { items: PlateJsonItem[] }).items;
  const ozByFoodName: Record<string, number> = {};
  const countByFoodName: Record<string, number> = {};
  const baseOzByFoodName: Record<string, number> = {};

  const matchFood = (namePart: string, foodName: string) =>
    namePart.toLowerCase() === foodName.toLowerCase() ||
    namePart.toLowerCase().includes(foodName.toLowerCase()) ||
    foodName.toLowerCase().includes(namePart.toLowerCase());

  for (const item of items) {
    if (!item?.name || typeof item.name !== "string") continue;
    const namePart = item.name.trim();
    let targetName: string | null = null;
    for (const foodName of foodNames) {
      if (matchFood(namePart, foodName)) {
        targetName = foodName;
        break;
      }
    }
    if (!targetName) continue;

    const portionOz = typeof item.portionOz === "number" && Number.isFinite(item.portionOz) ? item.portionOz : 0;
    const portionCount = typeof item.portionCount === "number" && Number.isFinite(item.portionCount) ? item.portionCount : 0;
    const baseServingOz = typeof item.baseServingOz === "number" && Number.isFinite(item.baseServingOz) ? item.baseServingOz : 0;

    if (portionOz > 0) {
      ozByFoodName[targetName] = Math.min(Math.max(portionOz, 0), 100);
    }
    if (portionCount > 0) {
      countByFoodName[targetName] = Math.max(0, Math.floor(portionCount));
    }
    if (baseServingOz > 0) {
      baseOzByFoodName[targetName] = Math.min(Math.max(baseServingOz, 0.25), 100);
    }
  }

  for (const name of foodNames) {
    if (ozByFoodName[name] === undefined) ozByFoodName[name] = 0;
    if (countByFoodName[name] === undefined) countByFoodName[name] = 0;
  }

  return { ozByFoodName, countByFoodName, baseOzByFoodName };
}

function parseBaseServingBlock(
  text: string,
  foodNames: string[]
): Record<string, number> {
  const baseOzByFoodName: Record<string, number> = {};
  const matchFood = (namePart: string, foodName: string) =>
    namePart.toLowerCase() === foodName.toLowerCase() ||
    namePart.toLowerCase().includes(foodName.toLowerCase()) ||
    foodName.toLowerCase().includes(namePart.toLowerCase());

  const parseLines = (block: string) => {
    const lines = block.split(/\n/).map((s) => s.trim()).filter(Boolean);
    for (const line of lines) {
      if (!line.includes(":")) continue;
      const colonIndex = line.indexOf(":");
      const namePart = line.slice(0, colonIndex).trim();
      const valuePartRaw = line.slice(colonIndex + 1).trim();
      const valuePart = valuePartRaw.replace(/oz/gi, "").trim();
      const num = parseFloat(valuePart);
      if (!Number.isFinite(num) || num < 0) continue;

      const oz = Math.min(Math.max(num, 0.25), 100);
      for (const foodName of foodNames) {
        if (matchFood(namePart, foodName)) {
          baseOzByFoodName[foodName] = oz;
          break;
        }
      }
    }
  };

  // 1) Parse inline "(base N.N oz)" from any line — also match truncated "(base 3." when output is cut off
  const inlineBaseRe = /\(base\s+([\d.]+)(?:\s*oz\)|\s*oz|\)|$)/i;
  const allLines = text.split(/\n/);
  for (const line of allLines) {
    if (!line.includes(":")) continue;
    const baseMatch = line.match(inlineBaseRe);
    if (!baseMatch?.[1]) continue;
    const baseNum = parseFloat(baseMatch[1]);
    if (!Number.isFinite(baseNum) || baseNum < 0) continue;
    const colonIdx = line.indexOf(":");
    const namePart = line.slice(0, colonIdx).trim();
    const oz = Math.min(Math.max(baseNum, 0.25), 100);
    for (const foodName of foodNames) {
      if (matchFood(namePart, foodName)) {
        baseOzByFoodName[foodName] = oz;
        break;
      }
    }
  }

  // 2) Parse Base serving block (if not already found from inline)
  const patterns = [
    /---\s*Base serving\s*\(?oz\)?[^-\n]*---\s*([\s\S]*?)(?=---|$)/i,
    /---\s*Base serving[^-\n]*---\s*([\s\S]*?)(?=---|$)/i,
    /Base serving\s*\(?oz\)?\s*:?\s*([\s\S]*?)(?=---|$)/i,
  ];
  for (const re of patterns) {
    const m = text.match(re);
    if (m?.[1]) {
      parseLines(m[1]);
      break;
    }
  }
  return baseOzByFoodName;
}

function inferBaseOzFromCalories(name: string, calories: number): number {
  if (calories <= 0) return 4.0;
  const n = name.toLowerCase();
  const calPerOz =
    /chicken|beef|pork|meat|fish|protein/.test(n) ? 50 :
    /rice|pasta|grain|noodle/.test(n) ? 35 :
    /sauce|gravy|dressing/.test(n) ? 25 : 40;
  return Math.max(0.25, Math.min(calories / calPerOz, 20));
}

function baseServingOzFromFoodContext(f: FoodItemContext): number {
  const amount = f.servingAmount > 0 ? f.servingAmount : 1;
  const unit = (f.servingUnit || "").trim().toLowerCase();
  if (unit === "g" || unit === "gram" || unit === "grams") return amount / 28.3495;
  if (unit.includes("oz")) return amount;
  if (unit.includes("cup")) return amount * 8.0;
  if (unit.includes("tbsp") || unit.includes("tablespoon")) return amount * 0.5;
  if (unit.includes("tsp") || unit.includes("teaspoon")) return amount * (1.0 / 6.0);
  return inferBaseOzFromCalories(f.name, f.calories);
}

function parsePlateResponse(
  text: string,
  foodNames: string[],
  foodItems: FoodItemContext[],
  baseOzByFoodName: Record<string, number>
): { ozByFoodName: Record<string, number>; countByFoodName: Record<string, number> } {
  const ozByFoodName: Record<string, number> = {};
  const countByFoodName: Record<string, number> = {};
  // Parse only the Portions block (before --- Base serving ---) to avoid base block overwriting portions
  const parts = text.split(/---\s*Base serving/i);
  const portionsBlock = parts.length > 1 ? parts[0] : text;
  const portionsMatch = portionsBlock.match(/---\s*Portions[^---]*---\s*([\s\S]*)/i);
  const linesText = portionsMatch ? portionsMatch[1] : portionsBlock;
  const lines = linesText.split(/\n/).map((s) => s.trim()).filter(Boolean);

  for (const line of lines) {
    if (!line.includes(":")) continue;
    const colonIndex = line.indexOf(":");
    const namePart = line.slice(0, colonIndex).trim();
    const valuePartRaw = line.slice(colonIndex + 1).trim();
    const hasOz = /oz/i.test(valuePartRaw);
    const valuePart = valuePartRaw.replace(/oz/gi, "").trim();
    const num = parseFloat(valuePart);
    if (!Number.isFinite(num) || num < 0) continue;

    // "9." or "9.0" without "oz" is almost certainly oz (entrees), not count. Treat decimals or >5 as oz.
    const likelyOz = hasOz || num % 1 !== 0 || num > 5;

    const matchFood = (foodName: string) =>
      namePart.toLowerCase() === foodName.toLowerCase() ||
      namePart.toLowerCase().includes(foodName.toLowerCase()) ||
      foodName.toLowerCase().includes(namePart.toLowerCase());

    if (likelyOz) {
      // 0 = not on plate. 1 oz often means Gemini guessed for absent items — treat as not on plate; user can "Add to plate".
      const rawOz = num === 0 ? 0 : Math.min(Math.max(num, 0.25), 100);
      const oz = rawOz === 1 ? 0 : rawOz;
      for (const foodName of foodNames) {
        if (matchFood(foodName)) {
          ozByFoodName[foodName] = oz;
          break;
        }
      }
    } else {
      const count = Math.floor(num);
      for (const foodName of foodNames) {
        if (matchFood(foodName)) {
          countByFoodName[foodName] = count;
          break;
        }
      }
    }
  }

  for (const name of foodNames) {
    if (ozByFoodName[name] === undefined) ozByFoodName[name] = 0;
    if (countByFoodName[name] === undefined) countByFoodName[name] = 0;
  }

  // When Gemini returns "1 each" or "1" for oz-based items (e.g. Orange Chicken), we parsed as count=1
  // but the item uses oz. Treat "1" as "1 serving" = base oz.
  const eachServingUnits = ["each", "ea", "serving", "servings", "item"];
  for (const f of foodItems) {
    const unit = (f.servingUnit || "").trim().toLowerCase();
    if (!eachServingUnits.includes(unit)) continue;
    const count = countByFoodName[f.name] ?? 0;
    const oz = ozByFoodName[f.name] ?? 0;
    const baseOz = baseOzByFoodName[f.name] ?? inferBaseOzFromCalories(f.name, f.calories);
    if (count >= 1 && oz === 0) {
      ozByFoodName[f.name] = baseOz * count;
    } else if (count === 0 && oz === 0) {
      // Gemini returned nothing parseable (e.g. name only, or "0 oz" when item is on plate).
      // Default to 1 serving on plate so user can adjust.
      ozByFoodName[f.name] = baseOz;
    }
  }

  return { ozByFoodName, countByFoodName };
}

type FoodItemContext = { name: string; calories: number; servingAmount: number; servingUnit: string };

async function performPlatePortionEstimate(
  apiKey: string,
  imageBase64: string,
  mimeType: string,
  foodItems: FoodItemContext[]
): Promise<{
  status: number;
  body: { ozByFoodName?: Record<string, number>; countByFoodName?: Record<string, number>; baseOzByFoodName?: Record<string, number>; rawText?: string; error?: string };
}> {
  const trimmedKey = apiKey.trim();
  if (!trimmedKey) {
    logger.error("Plate estimate requested without GEMINI_API_KEY configured.");
    return { status: 500, body: { error: "Plate portion estimation is not configured on the server." } };
  }

  const foodNames = foodItems.map((f) => f.name);
  const foodList = foodItems
    .map((f) => {
      const amount = f.servingAmount > 0 ? f.servingAmount : 1;
      const unit = (f.servingUnit || "serving").trim() || "serving";
      const serving = `${amount} ${unit}`.trim();
      return `${f.name}: ${serving}, ${f.calories} cal per serving`;
    })
    .join("\n");
  const userPrompt = `${GEMINI_SYSTEM_PROMPT}

Photo of the plate attached. Food items with context (use exact names in your response):
${foodList}`;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${encodeURIComponent(trimmedKey)}`;
  const sanitizedBase64 = imageBase64.replace(/\s/g, "");
  const body = {
    contents: [{
      parts: [
        { inlineData: { mimeType, data: sanitizedBase64 } },
        { text: userPrompt }
      ]
    }],
    generationConfig: {
      temperature: 2.0,
      maxOutputTokens: 2048,
      responseMimeType: "application/json"
    }
  };

  const callGemini = async (): Promise<string> => {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });
    if (!response.ok) {
      const errText = await response.text();
      logger.error("Gemini plate estimate upstream failed", { status: response.status, body: errText });
      let message = `Upstream error (HTTP ${response.status}).`;
      try {
        const errJson = JSON.parse(errText) as { error?: { message?: string } };
        if (errJson?.error?.message) message = errJson.error.message;
      } catch {
        // ignore
      }
      throw new Error(message);
    }
    const data = (await response.json()) as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const parts = data?.candidates?.[0]?.content?.parts ?? [];
    return parts.map((p) => p.text ?? "").join("").trim();
  };

  try {
    // Call Gemini twice and average the results for more stable portions and base servings.
    const [text1, text2] = await Promise.all([callGemini(), callGemini()]);

    const j1 = parsePlateJsonResponse(text1, foodNames);
    const j2 = parsePlateJsonResponse(text2, foodNames);

    let ozByFoodName: Record<string, number> = {};
    let countByFoodName: Record<string, number> = {};
    let baseOzByFoodName: Record<string, number> = {};

    if (j1 || j2) {
      // Preferred path: structured JSON from Gemini for one or both runs.
      for (const name of foodNames) {
        const p1Oz = j1?.ozByFoodName[name] ?? 0;
        const p2Oz = j2?.ozByFoodName[name] ?? 0;
        const p1Count = j1?.countByFoodName[name] ?? 0;
        const p2Count = j2?.countByFoodName[name] ?? 0;
        const b1 = j1?.baseOzByFoodName[name];
        const b2 = j2?.baseOzByFoodName[name];

        const ozValues = [p1Oz, p2Oz].filter((v) => Number.isFinite(v) && v > 0);
        const countValues = [p1Count, p2Count].filter((v) => Number.isFinite(v) && v > 0);

        ozByFoodName[name] = ozValues.length === 0 ? 0 : ozValues.reduce((a, b) => a + b, 0) / ozValues.length;
        countByFoodName[name] =
          countValues.length === 0 ? 0 : Math.round(countValues.reduce((a, b) => a + b, 0) / countValues.length);

        if (b1 !== undefined && b2 !== undefined) {
          baseOzByFoodName[name] = (b1 + b2) / 2;
        } else if (b1 !== undefined) {
          baseOzByFoodName[name] = b1;
        } else if (b2 !== undefined) {
          baseOzByFoodName[name] = b2;
        }
      }
    } else {
      // Fallback: old text-parsing path for robustness if JSON isn't valid on either run.
      const b1 = parseBaseServingBlock(text1, foodNames);
      const b2 = parseBaseServingBlock(text2, foodNames);
      const r1 = parsePlateResponse(text1, foodNames, foodItems, b1);
      const r2 = parsePlateResponse(text2, foodNames, foodItems, b2);

      const eachServingUnits = ["each", "ea", "serving", "servings", "item"];

      for (const name of foodNames) {
        ozByFoodName[name] = (r1.ozByFoodName[name] + r2.ozByFoodName[name]) / 2;
        countByFoodName[name] = Math.round((r1.countByFoodName[name] + r2.countByFoodName[name]) / 2);
        const base1 = b1[name];
        const base2 = b2[name];
        if (base1 !== undefined && base2 !== undefined) {
          baseOzByFoodName[name] = (base1 + base2) / 2;
        } else if (base1 !== undefined) {
          baseOzByFoodName[name] = base1;
        } else if (base2 !== undefined) {
          baseOzByFoodName[name] = base2;
        }
      }

      // Fallback: when Gemini doesn't return base for "1 each" items, infer from calories.
      // Also: do NOT override explicit serving units (oz, g/grams, cups, tbsp, tsp) — for those we keep the menu base.
      for (const f of foodItems) {
        const unitRaw = (f.servingUnit || "").trim().toLowerCase();
        const explicitUnit =
          unitRaw.includes("oz") ||
          unitRaw === "g" ||
          unitRaw === "gram" ||
          unitRaw === "grams" ||
          unitRaw.includes("cup") ||
          unitRaw.includes("tbsp") ||
          unitRaw.includes("tablespoon") ||
          unitRaw.includes("tsp") ||
          unitRaw.includes("teaspoon");
        if (explicitUnit) {
          // Never let Gemini change explicit base servings like "0.5 cups" rice or "4 oz".
          delete baseOzByFoodName[f.name];
          continue;
        }
        const unit = unitRaw;
        if (eachServingUnits.includes(unit) && baseOzByFoodName[f.name] === undefined) {
          baseOzByFoodName[f.name] = inferBaseOzFromCalories(f.name, f.calories);
        }
      }
    }

    const rawText = `--- Run 1 ---\n${text1}\n\n--- Run 2 ---\n${text2}`;
    return { status: 200, body: { ozByFoodName, countByFoodName, baseOzByFoodName, rawText } };
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return { status: 502, body: { error: message } };
  }
}

export const estimatePlatePortions = onRequest(
  { region: "us-central1", secrets: [geminiApiKeySecret] },
  async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed." });
      return;
    }

    try {
      const body = req.body as {
        imageBase64?: string;
        mimeType?: string;
        foodNames?: string[];
        foodItems?: Array<{ name?: string; calories?: number; servingAmount?: number; servingUnit?: string }>;
      };
      const imageBase64 = typeof body.imageBase64 === "string" ? body.imageBase64 : "";
      const mimeType = typeof body.mimeType === "string" ? body.mimeType : "image/jpeg";

      let foodItems: FoodItemContext[] = [];
      if (Array.isArray(body.foodItems) && body.foodItems.length > 0) {
        foodItems = body.foodItems
          .filter((x): x is { name: string; calories: number; servingAmount: number; servingUnit: string } =>
            typeof x?.name === "string" && x.name.trim().length > 0
          )
          .map((x) => ({
            name: (x.name ?? "").trim(),
            calories: typeof x.calories === "number" && Number.isFinite(x.calories) ? x.calories : 0,
            servingAmount: typeof x.servingAmount === "number" && Number.isFinite(x.servingAmount) ? x.servingAmount : 1,
            servingUnit: typeof x.servingUnit === "string" ? x.servingUnit.trim() || "serving" : "serving"
          }));
      }
      if (foodItems.length === 0 && Array.isArray(body.foodNames) && body.foodNames.length > 0) {
        const names = (body.foodNames as unknown[]).filter((x): x is string => typeof x === "string");
        foodItems = names.map((name) => ({ name, calories: 0, servingAmount: 1, servingUnit: "serving" }));
      }

      if (!imageBase64 || foodItems.length === 0) {
        res.status(400).json({ error: "Missing imageBase64 or foodItems/foodNames." });
        return;
      }

      const apiKey = geminiApiKeySecret.value();
      const result = await performPlatePortionEstimate(apiKey, imageBase64, mimeType, foodItems);
      res.status(result.status).json(result.body);
    } catch (error) {
      logger.error("Plate portion estimate failed", error);
      res.status(500).json({
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
  }
);
