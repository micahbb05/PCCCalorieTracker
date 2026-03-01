import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import admin from "firebase-admin";

admin.initializeApp();

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

const SCHOOL_ID = "four-winds";
const MENU_TYPE = "lunch";
const TIME_ZONE = "America/Los_Angeles";
const TARGET_DOC = "menus/today";

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

export const syncTodayMenuDaily = onSchedule(
  {
    schedule: "0 6 * * *",
    timeZone: TIME_ZONE,
    region: "us-central1"
  },
  async () => {
    await syncMenu(new Date());
  }
);

// Manual trigger endpoint for testing after deploy.
export const syncTodayMenuNow = onRequest({ region: "us-central1" }, async (_req, res) => {
  try {
    const result = await syncMenu(new Date());
    res.status(200).json({ ok: true, ...result });
  } catch (error) {
    logger.error("Manual menu sync failed", error);
    res.status(500).json({
      ok: false,
      error: error instanceof Error ? error.message : "Unknown error"
    });
  }
});
