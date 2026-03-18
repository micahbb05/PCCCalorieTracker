import { onRequest, Request } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import { defineSecret } from "firebase-functions/params";
import admin from "firebase-admin";
import { createHash } from "node:crypto";
import type { Response } from "express";

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
const APP_TIME_ZONE = "America/New_York";
const DAILY_GEMINI_CALL_LIMIT = 50;
const HOURLY_IP_GEMINI_CALL_LIMIT = 150;
const CLIENT_INSTANCE_ID_HEADER = "X-Client-Instance-Id";
const APP_CHECK_HEADER = "X-Firebase-AppCheck";
const ALLOWED_CORS_ORIGINS = new Set([
  "https://calorie-tracker-364e3.web.app",
  "https://calorie-tracker-364e3.firebaseapp.com",
  "http://localhost:5173",
  "http://127.0.0.1:5173"
]);

type HttpRequest = Request;
type HttpResponse = Response;

type VerifiedAIRequestIdentity = {
  appId: string;
  clientInstanceId: string;
  identityHash: string;
  ipAddress: string;
  ipHash: string;
};

function toSha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function getAllowedOrigin(originHeader: string | undefined): string | null {
  if (!originHeader) return null;
  const trimmed = originHeader.trim();
  if (!trimmed) return null;
  let origin: string;
  try {
    origin = new URL(trimmed).origin;
  } catch {
    return null;
  }
  return ALLOWED_CORS_ORIGINS.has(origin) ? origin : null;
}

function applyCors(
  req: HttpRequest,
  res: HttpResponse,
  methods: readonly string[],
  extraAllowedHeaders: readonly string[] = []
): { ok: boolean } {
  const allowedHeaders = ["Content-Type", ...extraAllowedHeaders];
  const originHeader = typeof req.headers.origin === "string" ? req.headers.origin : undefined;
  const allowedOrigin = getAllowedOrigin(originHeader);

  if (originHeader) {
    if (!allowedOrigin) {
      res.status(403).json({ error: "Origin not allowed." });
      return { ok: false };
    }
    res.set("Access-Control-Allow-Origin", allowedOrigin);
    res.set("Vary", "Origin");
  }

  res.set("Access-Control-Allow-Methods", methods.join(", "));
  res.set("Access-Control-Allow-Headers", allowedHeaders.join(", "));

  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return { ok: false };
  }

  return { ok: true };
}

function extractClientIp(req: HttpRequest): string {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim()) {
    const first = forwarded.split(",")[0]?.trim();
    if (first) return first;
  }
  if (Array.isArray(forwarded) && forwarded.length > 0) {
    const first = forwarded[0]?.trim();
    if (first) return first;
  }
  if (typeof req.ip === "string" && req.ip.trim()) return req.ip.trim();
  if (typeof req.socket?.remoteAddress === "string" && req.socket.remoteAddress.trim()) {
    return req.socket.remoteAddress.trim();
  }
  return "unknown";
}

function isValidClientInstanceId(value: string): boolean {
  return /^[a-zA-Z0-9_-]{16,128}$/.test(value);
}

async function verifyAIRequestIdentity(req: HttpRequest): Promise<{
  ok: boolean;
  status?: number;
  error?: string;
  identity?: VerifiedAIRequestIdentity;
}> {
  const appCheckTokenRaw = req.get(APP_CHECK_HEADER) ?? req.get(APP_CHECK_HEADER.toLowerCase()) ?? "";
  const appCheckToken = appCheckTokenRaw.trim();
  if (!appCheckToken) {
    return { ok: false, status: 401, error: "Missing App Check token." };
  }

  let decodedToken: { appId?: string };
  try {
    decodedToken = await admin.appCheck().verifyToken(appCheckToken);
  } catch (error) {
    logger.warn("Rejected request due to invalid App Check token.", { error });
    return { ok: false, status: 401, error: "Invalid App Check token." };
  }

  const appId = typeof decodedToken.appId === "string" ? decodedToken.appId.trim() : "";
  if (!appId) {
    return { ok: false, status: 401, error: "Invalid App Check token payload." };
  }

  const rawClientId = req.get(CLIENT_INSTANCE_ID_HEADER) ?? req.get(CLIENT_INSTANCE_ID_HEADER.toLowerCase()) ?? "";
  const clientInstanceId = rawClientId.trim();
  if (!isValidClientInstanceId(clientInstanceId)) {
    return { ok: false, status: 400, error: `Missing or invalid ${CLIENT_INSTANCE_ID_HEADER}.` };
  }

  const ipAddress = extractClientIp(req);
  const identityHash = toSha256(`${appId}:${clientInstanceId}`);
  const ipHash = toSha256(ipAddress);

  return {
    ok: true,
    identity: {
      appId,
      clientInstanceId,
      identityHash,
      ipAddress,
      ipHash
    }
  };
}

function formatDateKey(now: Date): string {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: APP_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  });
  return formatter.format(now).replace(/-/g, "");
}

function formatHourKey(now: Date): string {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: APP_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hourCycle: "h23"
  });
  const parts = formatter.formatToParts(now);
  const year = parts.find((p) => p.type === "year")?.value ?? "0000";
  const month = parts.find((p) => p.type === "month")?.value ?? "00";
  const day = parts.find((p) => p.type === "day")?.value ?? "00";
  const hour = parts.find((p) => p.type === "hour")?.value ?? "00";
  return `${year}${month}${day}${hour}`;
}

async function enforceGeminiQuota(
  identity: VerifiedAIRequestIdentity,
  geminiUnits: number
): Promise<{ ok: true; remainingDaily: number } | { ok: false; status: number; error: string }> {
  const units = Math.max(1, Math.floor(geminiUnits));
  const now = new Date();
  const dateKey = formatDateKey(now);
  const hourKey = formatHourKey(now);
  const db = admin.firestore();

  const dailyRef = db.collection("securityRateLimits").doc(`gemini_daily_${dateKey}_${identity.identityHash}`);
  const hourlyRef = db.collection("securityRateLimits").doc(`gemini_hourly_${hourKey}_${identity.ipHash}`);

  return db.runTransaction(async (tx) => {
    const [dailySnap, hourlySnap] = await Promise.all([tx.get(dailyRef), tx.get(hourlyRef)]);

    const dailyCountRaw = dailySnap.get("count");
    const hourlyCountRaw = hourlySnap.get("count");
    const dailyCount = typeof dailyCountRaw === "number" && Number.isFinite(dailyCountRaw) ? dailyCountRaw : 0;
    const hourlyCount = typeof hourlyCountRaw === "number" && Number.isFinite(hourlyCountRaw) ? hourlyCountRaw : 0;

    if ((dailyCount + units) > DAILY_GEMINI_CALL_LIMIT) {
      return {
        ok: false as const,
        status: 429,
        error: `Daily Gemini quota exceeded (${DAILY_GEMINI_CALL_LIMIT} calls per day).`
      };
    }

    if ((hourlyCount + units) > HOURLY_IP_GEMINI_CALL_LIMIT) {
      return {
        ok: false as const,
        status: 429,
        error: "Too many requests from this network. Try again later."
      };
    }

    tx.set(dailyRef, {
      type: "gemini_daily",
      quotaDate: dateKey,
      appId: identity.appId,
      identityHash: identity.identityHash,
      count: admin.firestore.FieldValue.increment(units),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    tx.set(hourlyRef, {
      type: "gemini_hourly",
      quotaHour: hourKey,
      ipHash: identity.ipHash,
      count: admin.firestore.FieldValue.increment(units),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return {
      ok: true as const,
      remainingDaily: DAILY_GEMINI_CALL_LIMIT - (dailyCount + units)
    };
  });
}

async function authorizeAIRequest(
  req: HttpRequest,
  res: HttpResponse,
  geminiUnits: number
): Promise<boolean> {
  const identityResult = await verifyAIRequestIdentity(req);
  if (!identityResult.ok || !identityResult.identity) {
    res.status(identityResult.status ?? 401).json({ error: identityResult.error ?? "Unauthorized request." });
    return false;
  }

  const quotaResult = await enforceGeminiQuota(identityResult.identity, geminiUnits);
  if (!quotaResult.ok) {
    res.status(quotaResult.status).json({ error: quotaResult.error });
    return false;
  }

  res.set("X-RateLimit-Limit-Daily-Gemini", String(DAILY_GEMINI_CALL_LIMIT));
  res.set("X-RateLimit-Remaining-Daily-Gemini", String(quotaResult.remainingDaily));
  return true;
}

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
  const cors = applyCors(req, res, ["GET", "OPTIONS"]);
  if (!cors.ok) {
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

const GEMINI_SYSTEM_PROMPT = `You are a portion estimator. You will receive a food photo and a list of food items with context.
The image may be either:
- a single plate of food, or
- a collage/board of multiple foods used for recognition testing.
If a real plate is visible, assume an 11-inch diameter plate for scale. If no plate is visible, estimate portions from typical serving size and visible relative size.
Not every listed item may be present. Only estimate what you actually see.
IMPORTANT: If an item is NOT visible in the image, use exactly "0 oz" (never guess 1 oz or 1).

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
- For oz-based items (entrees, sides, rice, etc.), set "portionOz" to the estimated oz visible in the image (0 if not visible). Omit "portionCount" or set it to 0.
- For count-based items (cookies, chips, pieces), set "portionCount" to the integer count (0 if not visible). Omit "portionOz" or set it to 0.
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

function parsePlateJsonTextFallback(
  text: string,
  foodNames: string[]
): { ozByFoodName: Record<string, number>; countByFoodName: Record<string, number>; baseOzByFoodName: Record<string, number> } | null {
  const ozByFoodName: Record<string, number> = {};
  const countByFoodName: Record<string, number> = {};
  const baseOzByFoodName: Record<string, number> = {};
  let matchedAny = false;

  const escapeRe = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const readNum = (snippet: string, key: string): number | null => {
    const re = new RegExp(`"${key}"\\s*:\\s*(-?\\d+(?:\\.\\d+)?)`, "i");
    const m = snippet.match(re);
    if (!m?.[1]) return null;
    const n = parseFloat(m[1]);
    if (!Number.isFinite(n)) return null;
    return n;
  };

  for (const foodName of foodNames) {
    const nameRe = new RegExp(`"name"\\s*:\\s*"[^"]*${escapeRe(foodName)}[^"]*"([\\s\\S]{0,600})`, "i");
    const match = text.match(nameRe);
    if (!match?.[1]) {
      ozByFoodName[foodName] = 0;
      countByFoodName[foodName] = 0;
      continue;
    }

    matchedAny = true;
    const snippet = match[1];
    const oz = readNum(snippet, "portionOz");
    const count = readNum(snippet, "portionCount");
    const base = readNum(snippet, "baseServingOz");

    ozByFoodName[foodName] = oz !== null && oz > 0 ? Math.min(Math.max(oz, 0), 100) : 0;
    countByFoodName[foodName] = count !== null && count > 0 ? Math.max(0, Math.floor(count)) : 0;
    if (base !== null && base > 0) {
      baseOzByFoodName[foodName] = Math.min(Math.max(base, 0.25), 100);
    }
  }

  return matchedAny ? { ozByFoodName, countByFoodName, baseOzByFoodName } : null;
}

function parsePlateJsonResponse(
  text: string,
  foodNames: string[]
): { ozByFoodName: Record<string, number>; countByFoodName: Record<string, number>; baseOzByFoodName: Record<string, number> } | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return parsePlateJsonTextFallback(text, foodNames);
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

function isExplicitServingUnit(unitRaw: string): boolean {
  const unit = unitRaw.trim().toLowerCase();
  return unit.includes("oz")
    || unit === "g"
    || unit === "gram"
    || unit === "grams"
    || unit.includes("cup")
    || unit.includes("tbsp")
    || unit.includes("tablespoon")
    || unit.includes("tsp")
    || unit.includes("teaspoon");
}

function isCountBasedFoodItem(f: FoodItemContext): boolean {
  const unit = (f.servingUnit || "").trim().toLowerCase();
  const name = f.name.trim().toLowerCase();
  if (["piece", "pieces", "slice", "slices"].includes(unit)) return true;
  if (name.includes("cookie") || name.includes("chips") || name.endsWith(" chip")) return true;
  return false;
}

function normalizePlateEstimates(
  foodItems: FoodItemContext[],
  ozByFoodName: Record<string, number>,
  countByFoodName: Record<string, number>,
  baseOzByFoodName: Record<string, number>
): void {
  for (const f of foodItems) {
    const name = f.name;
    const countBased = isCountBasedFoodItem(f);
    const count = Math.max(0, Math.floor(countByFoodName[name] ?? 0));
    const oz = Math.max(0, ozByFoodName[name] ?? 0);
    const baseOz = baseOzByFoodName[name] ?? baseServingOzFromFoodContext(f);
    const explicitUnit = isExplicitServingUnit(f.servingUnit || "");

    // Client consumes `countByFoodName` only for count-based foods. Convert count -> oz for the rest.
    if (!countBased && count > 0 && oz === 0) {
      ozByFoodName[name] = Math.min(Math.max(baseOz * count, 0), 100);
      countByFoodName[name] = 0;
    }

    // Keep explicit menu base servings authoritative (e.g. 4 oz steak, 0.5 cup rice).
    if (explicitUnit) {
      delete baseOzByFoodName[name];
      continue;
    }

    // If base serving wasn't provided for ambiguous units, infer from calories/context.
    if (baseOzByFoodName[name] === undefined) {
      baseOzByFoodName[name] = Math.min(Math.max(baseOz, 0.25), 100);
    }
  }
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
    }
  }

  return { ozByFoodName, countByFoodName };
}

type FoodItemContext = { name: string; calories: number; servingAmount: number; servingUnit: string };

type AIVisionFoodItem = {
  name?: unknown;
  servingAmount?: unknown;
  servingUnit?: unknown;
  servingItemsCount?: unknown;
  estimatedServings?: unknown;
  estimatedItemCount?: unknown;
  nutritionForServings?: unknown;
  calories?: unknown;
  protein?: unknown;
  sourceType?: unknown;
  nutrients?: unknown;
};

type AIVisionResponse = {
  mode?: unknown;
  items?: unknown;
};

type AITextFoodItem = {
  name?: unknown;
  brand?: unknown;
  servingAmount?: unknown;
  servingUnit?: unknown;
  servingItemsCount?: unknown;
  estimatedServings?: unknown;
  estimatedItemCount?: unknown;
  nutritionForServings?: unknown;
  calories?: unknown;
  protein?: unknown;
  sourceType?: unknown;
  nutrients?: unknown;
};

type AITextResponse = {
  items?: unknown;
};

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
      temperature: 0.2,
      maxOutputTokens: 8192,
      responseMimeType: "application/json",
      responseSchema: {
        type: "OBJECT",
        properties: {
          items: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              properties: {
                name: { type: "STRING" },
                portionOz: { type: "NUMBER" },
                portionCount: { type: "NUMBER" },
                baseServingOz: { type: "NUMBER" }
              },
              required: ["name"]
            }
          }
        },
        required: ["items"]
      }
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
        const explicitUnit = isExplicitServingUnit(unitRaw);
        if (explicitUnit) {
          // Never let Gemini change explicit base servings like "0.5 cups" rice or "4 oz".
          delete baseOzByFoodName[f.name];
          continue;
        }
        const eachServingUnits = ["each", "ea", "serving", "servings", "item"];
        const unit = unitRaw;
        if (eachServingUnits.includes(unit) && baseOzByFoodName[f.name] === undefined) {
          baseOzByFoodName[f.name] = inferBaseOzFromCalories(f.name, f.calories);
        }
      }
    }

    normalizePlateEstimates(foodItems, ozByFoodName, countByFoodName, baseOzByFoodName);

    const rawText = `--- Run 1 ---\n${text1}\n\n--- Run 2 ---\n${text2}`;
    return { status: 200, body: { ozByFoodName, countByFoodName, baseOzByFoodName, rawText } };
  } catch (err) {
    const message = err instanceof Error ? err.message : "Unknown error";
    return { status: 502, body: { error: message } };
  }
}

const AI_VISION_SYSTEM_PROMPT = `You analyze one photo for a calorie tracking app.

First classify the image into exactly one mode:
- "nutrition_label": the image is primarily a nutrition facts label, supplement facts label, package nutrition panel, or similar readable nutrition panel.
- "food_photo": the image is primarily food, a meal, a plate, or one or more foods.

You MUST respond ONLY with valid JSON. No markdown. No explanation. No prose.

Use exactly this JSON shape:
{
  "mode": "food_photo" | "nutrition_label",
  "items": [
    {
      "name": "string",
      "servingAmount": 1,
      "servingUnit": "serving",
      "servingItemsCount": 1,
      "estimatedServings": 1,
      "estimatedItemCount": 1,
      "nutritionForServings": 1,
      "calories": 0,
      "protein": 0,
      "sourceType": "real" | "estimated",
      "nutrients": {
        "g_protein": 0
      }
    }
  ]
}

Rules for food_photo mode:
- Detect one or more foods in the image.
- Return one item per distinct food.
- Classify each food into one source strategy:
  - brand_exact: branded or restaurant-specific item (e.g., "Taco Bell Cheesy Bean and Rice Burrito").
  - generic_stable_density: generic single food with reasonably stable per-mass nutrition (e.g., chicken breast, white rice, salmon).
  - generic_variable_composite: generic mixed dish with high recipe/size variance (e.g., burrito, casserole, stir fry, mixed bowl).
- For brand_exact: use reliable web nutrition for the exact branded/restaurant item.
- For generic_stable_density: use reliable per-oz/per-100g reference nutrition (USDA/FoodData Central style) and scale by visible portion.
- For generic_variable_composite: do not force an exact web item match when no brand/restaurant is identified; estimate from visible portion/composition.
- Prefer official nutrition pages, restaurant nutrition PDFs/pages, USDA/FoodData Central, Open Food Facts, and major manufacturer pages when web lookup is used.
- Include as many reliable nutrients as available in "nutrients" using normalized keys.
- Use "estimatedServings" for how much food is shown in the photo relative to the base serving.
- Choose a practical base serving that a user can adjust later, such as 1 sandwich, 1 slice, 1 cup, 4 oz, 1 bowl, 1 taco, etc.
- Keep servingAmount numeric and servingUnit short.
- For count-based foods (nuggets, tacos, slices, quesadillas, cookies, sandwiches, etc.), do NOT use "serving" as servingUnit. Use the edible count unit.
- For count-based foods, include:
  - servingItemsCount: how many edible units are in one nutrition serving (e.g., 5 for "5 nuggets per serving"; otherwise 1).
  - estimatedItemCount: how many edible units are shown/eaten in the image.
  - nutritionForServings: how many nutrition servings the returned calories/protein/nutrients represent. Usually 1.
- For non-count foods (oz/g/cup/tbsp/tsp), omit servingItemsCount and estimatedItemCount.
- If there are multiple foods, include all clearly visible foods.
- If confidence is poor, make the best reasonable estimate anyway.
- sourceType rules:
  - Use "real" for brand_exact and generic_stable_density items.
  - Use "estimated" for generic_variable_composite items unless a clear branded/restaurant item is identified.

Rules for nutrition_label mode:
- Read the visible nutrition facts from the label as accurately as possible.
- Return exactly one item.
- Use the product name if visible, otherwise use "Nutrition Facts Scan".
- Set estimatedServings to 1.
- Put calories in the top-level "calories" field.
- Put protein in the top-level "protein" field if visible, otherwise 0.
- Put all readable nutrients into "nutrients" using these normalized keys when possible:
  calories, g_protein, g_carbs, g_fat, g_saturated_fat, g_trans_fat, g_fiber, g_sugar, g_added_sugar, mg_sodium, mg_cholesterol, mg_potassium, mg_calcium, mg_iron, mg_vitamin_c, iu_vitamin_a, mcg_vitamin_a, mcg_vitamin_d
- Do not invent nutrients that are not visible.
- If a value is unreadable, omit that nutrient.
- Parse servingAmount and servingUnit from the label when possible.
- Set sourceType to "real" unless the label cannot be read and you must estimate.

General rules:
- JSON only.
- All numeric fields must be numbers, not strings.
- Do not include nulls.
- Do not include keys outside the required shape.`;

const AI_TEXT_SYSTEM_PROMPT = `You are a nutrition lookup assistant for a calorie tracker.

You will receive a short text describing what the user ate.
Goal:
- Use web lookup for every food in the text (branded, restaurant, and basic/generic foods) to find the most accurate nutrition facts per serving.
- Prefer official nutrition pages, restaurant nutrition PDFs/pages, USDA/FoodData Central, Open Food Facts, and major manufacturer pages.
- Only fall back to estimated values if reliable web data cannot be found.

Return ONLY valid JSON in this exact shape:
{
  "items": [
    {
      "name": "string",
      "brand": "string",
      "servingAmount": 1,
      "servingUnit": "serving",
      "servingItemsCount": 1,
      "estimatedServings": 1,
      "estimatedItemCount": 1,
      "nutritionForServings": 1,
      "calories": 0,
      "protein": 0,
      "sourceType": "real" | "estimated",
      "nutrients": {
        "g_protein": 0,
        "g_carbs": 0,
        "g_fat": 0,
        "g_saturated_fat": 0,
        "g_trans_fat": 0,
        "g_fiber": 0,
        "g_sugar": 0,
        "g_added_sugar": 0,
        "mg_sodium": 0,
        "mg_cholesterol": 0,
        "mg_potassium": 0,
        "mg_calcium": 0,
        "mg_iron": 0,
        "mg_vitamin_c": 0,
        "iu_vitamin_a": 0,
        "mcg_vitamin_a": 0,
        "mcg_vitamin_d": 0
      }
    }
  ]
}

Rules:
- JSON only. No markdown.
- Include one item per distinct food in the text.
- Use numbers (not strings) for numeric fields.
- For count-based foods, do NOT use "serving" as servingUnit. Use the edible unit and include:
  - servingItemsCount: edible units in one nutrition serving.
  - estimatedItemCount: edible units consumed.
  - nutritionForServings: how many nutrition servings the returned calories/protein/nutrients represent. Usually 1.
- For non-count foods (oz/g/cup/tbsp/tsp), omit servingItemsCount and estimatedItemCount.
- sourceType must be "real" when values are web-sourced (including basic foods), and "estimated" only when no reliable web source is found.
- If sourceType is "real", include as many known nutrients as available in nutrients.
- If sourceType is "estimated", include at least calories, protein, carbs, and fat when reasonable.
- Omit nutrients you truly do not know; do not invent precision.
- If no foods can be parsed, return {"items":[]}.`;

const WEEKLY_INSIGHT_SYSTEM_PROMPT = `You are an honest nutrition and fitness coach for a calorie tracking app.

You will receive a JSON weekly summary containing these categories:
1) Week Overview
2) Calorie Intake
3) Activity & Calories Burned
4) Calorie Balance
5) Weight Trend
6) Logging & Data Quality
7) Macros / Nutrient Pattern (starting with protein)
Additionally:
- crossWeekPatterns summarizes recent weekly averages so you can compare the current week against prior weeks.
- habitPatterns summarizes meal distribution, exercise consistency, late logging, and repeated over-goal food patterns.

Output requirements:
- No greetings, no sign-off, no fluff.
- Use only these exact headings, in this order when relevant:
  - Week Overview
  - Calorie Intake
  - Activity & Calories Burned
  - Calorie Balance
  - Weight Trend
  - Logging & Data Quality
  - Macros / Nutrient Pattern
- Include only sections with meaningful signal. Do not force filler bullets just to cover every heading.
- Under each heading, write 1-4 bullet points (Markdown), each starting with "- ".
- Bullets should be practical and decision-oriented: what changed, what likely explains it, and what to do next.
- Be direct and honest, but not rude.
- If a key input is missing (especially weight days or meals), say it in bullets.
- Use crossWeekPatterns to explain whether this week is improving, flat, or slipping relative to recent weeks.
- Explain mixed signals explicitly when intake, net calories, activity, weight, and data quality point in different directions.
- Use habitPatterns to connect meals, activity, and logging behavior into one explanation when possible.
- Do not mention a specific food unless habitPatterns.repeatedOverGoalFoods includes it with overGoalDayCount >= 2. If you do name one, explain why it matters and avoid sounding personal or judgmental.
- In "Calorie Balance", if the contradiction counters are available, explain why intake-over/under-goal days can still land in deficit/surplus using the provided counts.
- Include at least 1 concrete next-step action grounded in the data.
- Prefer pattern-level language over item-level language.
- The AI may add additional insight beyond these fields if it stays grounded in the provided data.
- Treat week-to-date data as normal, not a failure condition:
  - weekOverview.daysInPeriod can be 1-7 because this is a calendar-week view (Sunday-Saturday), often excluding today.
  - Do not frame lower day counts as "hard to see trends", "not enough data", or similar negative disclaimers.
  - Early week (1-3 days): emphasize setup and momentum actions for the next 1-2 days.
  - Mid week (4-5 days): emphasize consistency checks and one tactical adjustment for the remainder of the week.
  - Late week (6-7 days): emphasize finish-strong and weekend execution.
  - If data quality is genuinely poor, describe the specific missing inputs and give a concrete fix without making the week phase itself sound like a problem.

Safety:
- Avoid medical diagnoses, eating-disorder language, and blame.

Length:
- Keep the full output between 170 and 280 words.
`;

function normalizeNutrientKey(key: string): string | null {
  const normalized = key
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");

  const direct = new Set([
    "calories",
    "g_protein",
    "g_carbs",
    "g_fat",
    "g_saturated_fat",
    "g_trans_fat",
    "g_fiber",
    "g_sugar",
    "g_added_sugar",
    "mg_sodium",
    "mg_cholesterol",
    "mg_potassium",
    "mg_calcium",
    "mg_iron",
    "mg_vitamin_c",
    "iu_vitamin_a",
    "mcg_vitamin_a",
    "mcg_vitamin_d"
  ]);
  if (direct.has(normalized)) return normalized;

  const aliases: Record<string, string> = {
    protein: "g_protein",
    carbohydrates: "g_carbs",
    carbohydrate: "g_carbs",
    carbs: "g_carbs",
    fat: "g_fat",
    total_fat: "g_fat",
    saturated_fat: "g_saturated_fat",
    trans_fat: "g_trans_fat",
    fiber: "g_fiber",
    sugar: "g_sugar",
    added_sugar: "g_added_sugar",
    sodium: "mg_sodium",
    cholesterol: "mg_cholesterol",
    potassium: "mg_potassium",
    calcium: "mg_calcium",
    iron: "mg_iron",
    vitamin_c: "mg_vitamin_c",
    vitamin_a_iu: "iu_vitamin_a",
    vitamin_a_mcg: "mcg_vitamin_a",
    vitamin_d: "mcg_vitamin_d"
  };
  return aliases[normalized] ?? null;
}

function parsePositiveNumberLike(value: unknown): number | null {
  if (typeof value === "number") {
    return Number.isFinite(value) && value > 0 ? value : null;
  }
  if (typeof value !== "string") return null;

  const trimmed = value.trim().replace(/,/g, ".");
  if (!trimmed) return null;

  const mixedFraction = trimmed.match(/^(\d+(?:\.\d+)?)\s+(\d+)\s*\/\s*(\d+)\b/);
  if (mixedFraction) {
    const whole = Number(mixedFraction[1]);
    const numerator = Number(mixedFraction[2]);
    const denominator = Number(mixedFraction[3]);
    if (Number.isFinite(whole) && Number.isFinite(numerator) && Number.isFinite(denominator) && denominator > 0) {
      const value = whole + (numerator / denominator);
      return value > 0 ? value : null;
    }
  }

  const fraction = trimmed.match(/^(\d+)\s*\/\s*(\d+)\b/);
  if (fraction) {
    const numerator = Number(fraction[1]);
    const denominator = Number(fraction[2]);
    if (Number.isFinite(numerator) && Number.isFinite(denominator) && denominator > 0) {
      const value = numerator / denominator;
      return value > 0 ? value : null;
    }
  }

  const leading = trimmed.match(/^(\d+(?:\.\d+)?|\.\d+)\b/);
  if (leading) {
    const value = Number(leading[1]);
    return Number.isFinite(value) && value > 0 ? value : null;
  }
  return null;
}

function splitLeadingAmount(text: string): { amount: number; unit: string } | null {
  const trimmed = text.trim();
  if (!trimmed) return null;

  const mixedFraction = trimmed.match(/^(\d+(?:\.\d+)?)\s+(\d+)\s*\/\s*(\d+)\s*(.*)$/);
  if (mixedFraction) {
    const whole = Number(mixedFraction[1]);
    const numerator = Number(mixedFraction[2]);
    const denominator = Number(mixedFraction[3]);
    if (Number.isFinite(whole) && Number.isFinite(numerator) && Number.isFinite(denominator) && denominator > 0) {
      const amount = whole + (numerator / denominator);
      if (amount > 0) {
        return { amount, unit: mixedFraction[4].trim() };
      }
    }
  }

  const fraction = trimmed.match(/^(\d+)\s*\/\s*(\d+)\s*(.*)$/);
  if (fraction) {
    const numerator = Number(fraction[1]);
    const denominator = Number(fraction[2]);
    if (Number.isFinite(numerator) && Number.isFinite(denominator) && denominator > 0) {
      const amount = numerator / denominator;
      if (amount > 0) {
        return { amount, unit: fraction[3].trim() };
      }
    }
  }

  const decimal = trimmed.match(/^(\d+(?:\.\d+)?|\.\d+)\s*(.*)$/);
  if (decimal) {
    const amount = Number(decimal[1]);
    if (Number.isFinite(amount) && amount > 0) {
      return { amount, unit: decimal[2].trim() };
    }
  }

  return null;
}

function parseServingAmountAndUnit(rawAmount: unknown, rawUnit: unknown): { servingAmount: number; servingUnit: string } {
  let servingAmount = parsePositiveNumberLike(rawAmount);
  let servingUnit = typeof rawUnit === "string" ? rawUnit.trim() : "";

  if (typeof rawAmount === "string") {
    const amountWithUnit = splitLeadingAmount(rawAmount);
    if (amountWithUnit) {
      if (servingAmount === null) {
        servingAmount = amountWithUnit.amount;
      }
      if (!servingUnit && amountWithUnit.unit) {
        servingUnit = amountWithUnit.unit;
      }
    }
  }

  if (typeof rawUnit === "string") {
    const unitWithAmount = splitLeadingAmount(rawUnit);
    if (unitWithAmount) {
      if (servingAmount === null) {
        servingAmount = unitWithAmount.amount;
      }
      if (unitWithAmount.unit) {
        servingUnit = unitWithAmount.unit;
      }
    }
  }

  return {
    servingAmount: servingAmount ?? 1,
    servingUnit: servingUnit || "serving"
  };
}

const COUNT_SERVING_UNITS = new Set([
  "piece",
  "pieces",
  "slice",
  "slices",
  "nugget",
  "nuggets",
  "sandwich",
  "sandwiches",
  "burger",
  "burgers",
  "taco",
  "tacos",
  "burrito",
  "burritos",
  "wrap",
  "wraps",
  "cookie",
  "cookies",
  "chip",
  "chips",
  "quesadilla",
  "quesadillas"
]);

function isLikelyCountServing(name: string, servingUnit: string): boolean {
  const unit = servingUnit.trim().toLowerCase();
  const normalizedName = name.trim().toLowerCase();
  if (COUNT_SERVING_UNITS.has(unit)) return true;
  return normalizedName.includes("nugget")
    || normalizedName.includes("quesadilla")
    || normalizedName.includes("sandwich")
    || normalizedName.includes("burger")
    || normalizedName.includes("taco")
    || normalizedName.includes("burrito")
    || normalizedName.includes("wrap")
    || normalizedName.includes("cookie")
    || normalizedName.includes("chips")
    || normalizedName.endsWith(" chip");
}

function normalizeEstimatedServingsForCountItems(
  name: string,
  servingAmount: number,
  servingUnit: string,
  estimatedServings: number
): number {
  const safeEstimated = Number.isFinite(estimatedServings) && estimatedServings > 0
    ? Math.min(Math.max(estimatedServings, 0.01), 100)
    : 1;
  const safeServingAmount = Number.isFinite(servingAmount) && servingAmount > 0 ? servingAmount : 1;
  if (safeServingAmount <= 1) return safeEstimated;
  if (!isLikelyCountServing(name, servingUnit)) return safeEstimated;

  // Guard against AI returning piece-count (e.g. "5 nuggets") as estimated servings.
  const roundedEstimated = Math.round(safeEstimated);
  const looksIntegerCount = Math.abs(safeEstimated - roundedEstimated) <= 0.05;
  if (looksIntegerCount && safeEstimated + 0.05 >= safeServingAmount) {
    return Math.max(safeEstimated / safeServingAmount, 0.01);
  }
  return safeEstimated;
}

function nutritionBasisServingsForItem(
  name: string,
  servingAmount: number,
  servingUnit: string,
  servingItemsCount: number | undefined,
  estimatedServings: number,
  estimatedItemCount: number | undefined,
  explicitNutritionForServings: number | undefined,
  caloriesRaw: number
): number {
  if (explicitNutritionForServings && explicitNutritionForServings > 0) {
    return explicitNutritionForServings;
  }
  if (!isLikelyCountServing(name, servingUnit)) return 1;

  const baseItemsPerNutritionServing =
    (servingItemsCount && servingItemsCount > 0)
      ? servingItemsCount
      : (servingAmount > 0 ? servingAmount : 1);
  if (baseItemsPerNutritionServing <= 0) return 1;

  const consumedItems = estimatedItemCount && estimatedItemCount > 0
    ? estimatedItemCount
    : (estimatedServings > 0 ? estimatedServings * baseItemsPerNutritionServing : 0);
  if (consumedItems <= 0) return 1;

  const inferredServingsFromCount = consumedItems / baseItemsPerNutritionServing;
  // If calories are clearly meal-level for multi-item counts, normalize back to per-serving.
  if (inferredServingsFromCount > 1.5 && caloriesRaw > 1200) {
    return inferredServingsFromCount;
  }

  return 1;
}

function parseAITextResponse(text: string): {
  items: Array<{
    name: string;
    brand: string | null;
    servingAmount: number;
    servingUnit: string;
    servingItemsCount?: number;
    estimatedServings: number;
    estimatedItemCount?: number;
    calories: number;
    protein: number;
    sourceType: "real" | "estimated";
    nutrients: Record<string, number>;
  }>;
} | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }

  if (!parsed || typeof parsed !== "object") return null;
  const response = parsed as AITextResponse;
  if (!Array.isArray(response.items)) return null;

  const items = response.items
    .map((raw) => {
      if (!raw || typeof raw !== "object") return null;
      const item = raw as AITextFoodItem;
      const name = typeof item.name === "string" ? item.name.trim() : "";
      if (!name) return null;

      const brand = typeof item.brand === "string" ? item.brand.trim() : "";
      const { servingAmount, servingUnit } = parseServingAmountAndUnit(item.servingAmount, item.servingUnit);
      const servingItemsCount = parsePositiveNumberLike(item.servingItemsCount) ?? undefined;
      const estimatedServings = parsePositiveNumberLike(item.estimatedServings) ?? 1;
      const estimatedItemCount = parsePositiveNumberLike(item.estimatedItemCount) ?? undefined;
      const explicitNutritionForServings = parsePositiveNumberLike(item.nutritionForServings) ?? undefined;
      const normalizedEstimatedServings = normalizeEstimatedServingsForCountItems(
        name,
        servingAmount,
        servingUnit,
        estimatedServings
      );
      const caloriesRaw = typeof item.calories === "number" && Number.isFinite(item.calories) && item.calories >= 0
        ? item.calories
        : 0;
      const proteinRaw = typeof item.protein === "number" && Number.isFinite(item.protein) && item.protein >= 0
        ? item.protein
        : 0;
      const nutritionForServings = nutritionBasisServingsForItem(
        name,
        servingAmount,
        servingUnit,
        servingItemsCount,
        normalizedEstimatedServings,
        estimatedItemCount,
        explicitNutritionForServings,
        caloriesRaw
      );
      const calories = Math.round(caloriesRaw / nutritionForServings);
      const protein = Math.round(proteinRaw / nutritionForServings);
      const sourceType = item.sourceType === "real" ? "real" : "estimated";

      const nutrientsSource = item.nutrients && typeof item.nutrients === "object" ? item.nutrients as Record<string, unknown> : {};
      const nutrients: Record<string, number> = {};
      for (const [rawKey, value] of Object.entries(nutrientsSource)) {
        if (typeof value !== "number" || !Number.isFinite(value) || value < 0) continue;
        const key = normalizeNutrientKey(rawKey);
        if (!key) continue;
        nutrients[key] = Math.round(value / nutritionForServings);
      }
      if (calories > 0 && nutrients.calories === undefined) nutrients.calories = calories;
      if (protein > 0 && nutrients.g_protein === undefined) nutrients.g_protein = protein;

      const hasUsefulNutrition = calories > 0 || Object.values(nutrients).some((v) => v > 0);
      if (!hasUsefulNutrition) return null;

      return {
        name,
        brand: brand || null,
        servingAmount,
        servingUnit,
        ...(servingItemsCount ? { servingItemsCount } : {}),
        estimatedServings: normalizedEstimatedServings,
        ...(estimatedItemCount ? { estimatedItemCount } : {}),
        calories,
        protein,
        sourceType,
        nutrients
      };
    })
    .filter((item): item is {
      name: string;
      brand: string | null;
      servingAmount: number;
      servingUnit: string;
      servingItemsCount?: number;
      estimatedServings: number;
      estimatedItemCount?: number;
      calories: number;
      protein: number;
      sourceType: "real" | "estimated";
      nutrients: Record<string, number>;
    } => item !== null);

  return { items };
}

function extractFirstJsonObject(text: string): string {
  const fenced = text.match(/```json\s*([\s\S]*?)```/i) ?? text.match(/```\s*([\s\S]*?)```/i);
  if (fenced?.[1]) return fenced[1].trim();

  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start >= 0 && end > start) {
    return text.slice(start, end + 1).trim();
  }
  return text.trim();
}

function parseAIVisionJsonResponse(text: string): {
  mode: "food_photo" | "nutrition_label"; items: Array<{
    name: string;
    servingAmount: number;
    servingUnit: string;
    servingItemsCount?: number;
    estimatedServings: number;
    estimatedItemCount?: number;
    calories: number;
    protein: number;
    sourceType: "real" | "estimated";
    nutrients: Record<string, number>;
  }>
} | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }

  if (!parsed || typeof parsed !== "object") return null;
  const response = parsed as AIVisionResponse;
  const mode = response.mode === "food_photo" || response.mode === "nutrition_label" ? response.mode : null;
  if (!mode || !Array.isArray(response.items)) return null;

  const items = response.items
    .map((raw): {
      name: string;
      servingAmount: number;
      servingUnit: string;
      servingItemsCount?: number;
      estimatedServings: number;
      estimatedItemCount?: number;
      calories: number;
      protein: number;
      sourceType: "real" | "estimated";
      nutrients: Record<string, number>;
    } | null => {
      if (!raw || typeof raw !== "object") return null;
      const item = raw as AIVisionFoodItem;
      const name = typeof item.name === "string" ? item.name.trim() : "";
      if (!name) return null;

      const { servingAmount, servingUnit } = parseServingAmountAndUnit(item.servingAmount, item.servingUnit);
      const servingItemsCount = parsePositiveNumberLike(item.servingItemsCount) ?? undefined;
      const estimatedServings = parsePositiveNumberLike(item.estimatedServings) ?? 1;
      const estimatedItemCount = parsePositiveNumberLike(item.estimatedItemCount) ?? undefined;
      const explicitNutritionForServings = parsePositiveNumberLike(item.nutritionForServings) ?? undefined;
      const normalizedEstimatedServings = normalizeEstimatedServingsForCountItems(
        name,
        servingAmount,
        servingUnit,
        estimatedServings
      );
      const caloriesRaw = typeof item.calories === "number" && Number.isFinite(item.calories) && item.calories >= 0
        ? item.calories
        : 0;
      const proteinRaw = typeof item.protein === "number" && Number.isFinite(item.protein) && item.protein >= 0
        ? item.protein
        : 0;
      const nutritionForServings = nutritionBasisServingsForItem(
        name,
        servingAmount,
        servingUnit,
        servingItemsCount,
        normalizedEstimatedServings,
        estimatedItemCount,
        explicitNutritionForServings,
        caloriesRaw
      );
      const calories = Math.round(caloriesRaw / nutritionForServings);
      const protein = Math.round(proteinRaw / nutritionForServings);
      const sourceType = item.sourceType === "real" ? "real" : "estimated";

      const nutrientsSource = item.nutrients && typeof item.nutrients === "object" ? item.nutrients as Record<string, unknown> : {};
      const nutrients: Record<string, number> = {};
      for (const [rawKey, value] of Object.entries(nutrientsSource)) {
        if (typeof value !== "number" || !Number.isFinite(value) || value < 0) continue;
        const key = normalizeNutrientKey(rawKey);
        if (!key) continue;
        nutrients[key] = Math.round(value / nutritionForServings);
      }
      if (calories > 0 && nutrients.calories === undefined) {
        nutrients.calories = calories;
      }
      if (protein > 0 && nutrients.g_protein === undefined) {
        nutrients.g_protein = protein;
      }

      return {
        name,
        servingAmount,
        servingUnit,
        ...(servingItemsCount ? { servingItemsCount } : {}),
        estimatedServings: normalizedEstimatedServings,
        ...(estimatedItemCount ? { estimatedItemCount } : {}),
        calories,
        protein,
        sourceType,
        nutrients
      };
    })
    .filter((item): item is {
      name: string;
      servingAmount: number;
      servingUnit: string;
      servingItemsCount?: number;
      estimatedServings: number;
      estimatedItemCount?: number;
      calories: number;
      protein: number;
      sourceType: "real" | "estimated";
      nutrients: Record<string, number>;
    } => item !== null);

  if (items.length === 0) return null;
  return { mode, items };
}

const BRAND_OR_RESTAURANT_KEYWORDS = [
  "mcdonald",
  "taco bell",
  "chipotle",
  "chick fil a",
  "chick-fil-a",
  "burger king",
  "wendy",
  "subway",
  "kfc",
  "popeyes",
  "domino",
  "pizza hut",
  "starbucks",
  "panera",
  "panda express",
  "whataburger",
  "in n out",
  "in-n-out",
  "sonic",
  "arbys",
  "arby's",
  "little caesars",
  "five guys",
  "shake shack",
  "zaxby",
  "bojangles",
  "dunkin",
  "restaurant"
];

const GENERIC_VARIABLE_COMPOSITE_KEYWORDS = [
  "burrito",
  "taco",
  "quesadilla",
  "enchilada",
  "sandwich",
  "burger",
  "pizza",
  "pasta",
  "lasagna",
  "casserole",
  "stir fry",
  "stir-fry",
  "fried rice",
  "bowl",
  "wrap",
  "salad",
  "soup",
  "chili",
  "curry",
  "gumbo",
  "stew",
  "plate",
  "combo"
];

const GENERIC_STABLE_DENSITY_KEYWORDS = [
  "chicken breast",
  "chicken thigh",
  "chicken",
  "turkey breast",
  "turkey",
  "salmon",
  "tuna",
  "tilapia",
  "cod",
  "shrimp",
  "egg",
  "eggs",
  "tofu",
  "rice",
  "oatmeal",
  "oats",
  "potato",
  "sweet potato",
  "broccoli",
  "spinach",
  "green beans",
  "asparagus",
  "banana",
  "apple",
  "orange",
  "berries",
  "yogurt",
  "greek yogurt",
  "cottage cheese",
  "milk",
  "black beans",
  "beans"
];

function containsKeyword(text: string, keywords: readonly string[]): boolean {
  return keywords.some((keyword) => text.includes(keyword));
}

function normalizeFoodNameForRules(name: string): string {
  return name.trim().toLowerCase().replace(/[^a-z0-9\s\-']/g, " ");
}

function classifyFoodPhotoSource(name: string): "brand_exact" | "generic_stable_density" | "generic_variable_composite" {
  const normalized = normalizeFoodNameForRules(name);
  if (!normalized) return "generic_variable_composite";
  if (containsKeyword(normalized, BRAND_OR_RESTAURANT_KEYWORDS)) return "brand_exact";
  if (containsKeyword(normalized, GENERIC_VARIABLE_COMPOSITE_KEYWORDS)) return "generic_variable_composite";
  if (containsKeyword(normalized, GENERIC_STABLE_DENSITY_KEYWORDS)) return "generic_stable_density";
  return "generic_variable_composite";
}

function applyFoodPhotoSourceRules(items: Array<{
  name: string;
  servingAmount: number;
  servingUnit: string;
  servingItemsCount?: number;
  estimatedServings: number;
  estimatedItemCount?: number;
  calories: number;
  protein: number;
  sourceType: "real" | "estimated";
  nutrients: Record<string, number>;
}>): Array<{
  name: string;
  servingAmount: number;
  servingUnit: string;
  servingItemsCount?: number;
  estimatedServings: number;
  estimatedItemCount?: number;
  calories: number;
  protein: number;
  sourceType: "real" | "estimated";
  nutrients: Record<string, number>;
}> {
  return items.map((item) => {
    const sourceClass = classifyFoodPhotoSource(item.name);
    if (sourceClass === "generic_variable_composite") {
      return { ...item, sourceType: "estimated" };
    }
    return { ...item, sourceType: "real" };
  });
}

async function performAIVisionAnalysis(
  apiKey: string,
  imageBase64: string,
  mimeType: string
): Promise<{
  status: number;
  body: {
    mode?: "food_photo" | "nutrition_label";
    items?: Array<{
      name: string;
      servingAmount: number;
      servingUnit: string;
      servingItemsCount?: number;
      estimatedServings: number;
      estimatedItemCount?: number;
      calories: number;
      protein: number;
      sourceType: "real" | "estimated";
      nutrients: Record<string, number>;
    }>;
    rawJson?: string;
    error?: string;
  };
}> {
  const trimmedKey = apiKey.trim();
  if (!trimmedKey) {
    logger.error("AI vision requested without GEMINI_API_KEY configured.");
    return { status: 500, body: { error: "AI food analysis is not configured on the server." } };
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${encodeURIComponent(trimmedKey)}`;
  const sanitizedBase64 = imageBase64.replace(/\s/g, "");
  const body = {
    contents: [{
      parts: [
        { inlineData: { mimeType, data: sanitizedBase64 } },
        { text: AI_VISION_SYSTEM_PROMPT }
      ]
    }],
    generationConfig: {
      temperature: 0.2,
      thinkingConfig: { thinkingBudget: 0 },
      maxOutputTokens: 4096
    }
  };

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      const errText = await response.text();
      logger.error("Gemini AI vision upstream failed", { status: response.status, body: errText });
      let message = `Upstream error (HTTP ${response.status}).`;
      try {
        const errJson = JSON.parse(errText) as { error?: { message?: string } };
        if (errJson?.error?.message) message = errJson.error.message;
      } catch {
        // ignore
      }
      return { status: 502, body: { error: message } };
    }

    const data = (await response.json()) as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const text = (data?.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("").trim();
    const jsonText = extractFirstJsonObject(text);
    const parsed = parseAIVisionJsonResponse(jsonText);
    if (!parsed) {
      logger.error("AI vision returned invalid JSON", { rawText: text });
      return { status: 502, body: { error: "AI returned an invalid response.", rawJson: text } };
    }
    const normalizedItems = parsed.mode === "food_photo"
      ? applyFoodPhotoSourceRules(parsed.items)
      : parsed.items;

    return {
      status: 200,
      body: {
        mode: parsed.mode,
        items: normalizedItems,
        rawJson: jsonText
      }
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    logger.error("AI vision analysis failed", error);
    return { status: 502, body: { error: message } };
  }
}

async function performAITextAnalysis(
  apiKey: string,
  mealText: string
): Promise<{
  status: number;
  body: {
    items?: Array<{
      name: string;
      brand: string | null;
      servingAmount: number;
      servingUnit: string;
      servingItemsCount?: number;
      estimatedServings: number;
      estimatedItemCount?: number;
      calories: number;
      protein: number;
      sourceType: "real" | "estimated";
      nutrients: Record<string, number>;
    }>;
    rawJson?: string;
    error?: string;
  };
}> {
  const trimmedKey = apiKey.trim();
  if (!trimmedKey) {
    logger.error("AI text analysis requested without GEMINI_API_KEY configured.");
    return { status: 500, body: { error: "AI text analysis is not configured on the server." } };
  }

  const trimmedMealText = mealText.trim();
  if (!trimmedMealText) {
    return { status: 400, body: { error: "Enter what you ate." } };
  }

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${encodeURIComponent(trimmedKey)}`;
  const body = {
    systemInstruction: {
      parts: [{ text: AI_TEXT_SYSTEM_PROMPT }]
    },
    contents: [{
      parts: [{ text: `User meal text: ${trimmedMealText}` }]
    }],
    tools: [{ googleSearch: {} }],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 4096
    }
  };

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      const errText = await response.text();
      logger.error("Gemini AI text upstream failed", { status: response.status, body: errText });
      let message = `Upstream error (HTTP ${response.status}).`;
      try {
        const errJson = JSON.parse(errText) as { error?: { message?: string } };
        if (errJson?.error?.message) message = errJson.error.message;
      } catch {
        // ignore
      }
      return { status: 502, body: { error: message } };
    }

    const data = (await response.json()) as {
      candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
    };
    const text = (data?.candidates?.[0]?.content?.parts ?? []).map((p) => p.text ?? "").join("").trim();
    const jsonText = extractFirstJsonObject(text);
    const parsed = parseAITextResponse(jsonText);
    if (!parsed) {
      logger.error("AI text analysis returned invalid JSON", { rawText: text });
      return { status: 502, body: { error: "AI returned an invalid response.", rawJson: text } };
    }

    return {
      status: 200,
      body: {
        items: parsed.items,
        rawJson: jsonText
      }
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    logger.error("AI text analysis failed", error);
    return { status: 502, body: { error: message } };
  }
}

type WeeklyInsightDay = {
  dayIdentifier?: string;
  date?: string;
  caloriesIn?: number;
  caloriesBurned?: number;
  weightPounds?: number;
  netCalories?: number;
};

type WeeklyInsightLoggedFoodEntry = {
  dayIdentifier?: string;
  createdAt?: string;
  mealGroup?: string;
  name?: string;
  calories?: number;
  protein?: number;
  loggedCount?: number;
};

type WeeklyInsightSummaryPayload = {
  days?: WeeklyInsightDay[];
  weekOverview?: {
    daysInPeriod?: number;
    mealLoggedDays?: number;
    weightLoggedDays?: number;
  };
  intake?: {
    averageCaloriesIn?: number;
    minCaloriesIn?: number;
    maxCaloriesIn?: number;
    averageGoalCalories?: number;
    overGoalDays?: number;
    underGoalDays?: number;
    biggestOverage?: number;
    biggestUnderage?: number;
    averageOverageOnOverGoalDays?: number;
    topFoodsOnOverGoalDays?: Array<{ name?: string; calories?: number }>;
    topMealGroupsOnOverGoalDays?: Array<{ mealGroup?: string; calories?: number }>;
  };
  activity?: {
    averageCaloriesBurned?: number;
    minCaloriesBurned?: number;
    maxCaloriesBurned?: number;
    burnedReliability?: {
      reliableBurnedDays?: number;
      compatibilityFallbackDays?: number;
      bmrFallbackDays?: number;
    };
  };
  balance?: {
    averageNetCalories?: number;
    netDeficitDays?: number;
    netSurplusDays?: number;
    minNetCalories?: number;
    maxNetCalories?: number;
    deficitDaysWhereIntakeWasOverGoal?: number;
    surplusDaysWhereIntakeWasUnderGoal?: number;
  };
  weightTrend?: {
    weightDaysUsed?: number;
    startWeightPounds?: number;
    endWeightPounds?: number;
    weightChangePounds?: number;
  };
  dataQuality?: {
    missingMealDays?: number;
    missingWeightDays?: number;
    estimatedBurnedDays?: number;
  };
  macros?: {
    proteinGoalGrams?: number;
    proteinDaysLogged?: number;
    proteinDaysHitGoal?: number;
    averageProteinGrams?: number;
    minProteinGrams?: number;
    maxProteinGrams?: number;
  };
  crossWeekPatterns?: {
    recentWeeks?: Array<{
      label?: string;
      startDayIdentifier?: string;
      endDayIdentifier?: string;
      averageCaloriesIn?: number;
      averageCaloriesBurned?: number;
      averageNetCalories?: number;
      overGoalDays?: number;
      underGoalDays?: number;
      mealLoggedDays?: number;
      exerciseDays?: number;
      averageExerciseMinutes?: number;
      averageProteinGrams?: number;
      weightLoggedDays?: number;
      weightChangePounds?: number;
    }>;
    currentVsPreviousCaloriesDelta?: number;
    currentVsPreviousNetDelta?: number;
    currentVsPreviousProteinDelta?: number;
    currentVsPreviousOverGoalDayDelta?: number;
    currentVsPreviousExerciseDayDelta?: number;
  };
  habitPatterns?: {
    averageEveningCalories?: number;
    averageEveningSharePercent?: number;
    breakfastLoggedDays?: number;
    lunchLoggedDays?: number;
    dinnerLoggedDays?: number;
    snackLoggedDays?: number;
    lateLogDays?: number;
    exerciseDays?: number;
    averageExerciseMinutesOnExerciseDays?: number;
    mealPatterns?: Array<{
      mealGroup?: string;
      averageCaloriesPerLoggedDay?: number;
      loggedDays?: number;
      totalCalories?: number;
    }>;
    exercisePatterns?: Array<{
      exerciseType?: string;
      days?: number;
      sessions?: number;
      averageDurationMinutes?: number;
      totalCalories?: number;
    }>;
    repeatedOverGoalFoods?: Array<{
      name?: string;
      overGoalDayCount?: number;
      totalCalories?: number;
      dominantMealGroup?: string;
    }>;
  };
  loggedFoods?: WeeklyInsightLoggedFoodEntry[];
};

async function performWeeklyInsightAnalysis(
  apiKey: string,
  summary: WeeklyInsightSummaryPayload
): Promise<{ status: number; body: { insight?: string; error?: string } }> {
  const trimmedKey = apiKey.trim();
  if (!trimmedKey) {
    logger.error("Weekly insight requested without GEMINI_API_KEY configured.");
    return { status: 500, body: { error: "Weekly insight is not configured on the server." } };
  }

  if (!summary?.days || summary.days.length === 0) {
    return { status: 400, body: { error: "Missing weekly summary data." } };
  }

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/` +
    `gemini-2.5-flash:generateContent?key=${encodeURIComponent(trimmedKey)}`;

  const safeSummary: WeeklyInsightSummaryPayload = {
    days: summary.days.map((d) => ({
      dayIdentifier: d.dayIdentifier,
      date: d.date,
      caloriesIn: Number.isFinite(d.caloriesIn ?? NaN) ? d.caloriesIn : undefined,
      caloriesBurned: Number.isFinite(d.caloriesBurned ?? NaN) ? d.caloriesBurned : undefined,
      weightPounds: Number.isFinite(d.weightPounds ?? NaN) ? d.weightPounds : undefined,
      netCalories: Number.isFinite(d.netCalories ?? NaN) ? d.netCalories : undefined
    })),
    weekOverview: summary.weekOverview,
    intake: summary.intake,
    activity: summary.activity,
    balance: summary.balance,
    weightTrend: summary.weightTrend,
    dataQuality: summary.dataQuality,
    macros: summary.macros,
    crossWeekPatterns: summary.crossWeekPatterns
      ? {
          recentWeeks: (summary.crossWeekPatterns.recentWeeks ?? []).map((week) => ({
            label: week.label,
            startDayIdentifier: week.startDayIdentifier,
            endDayIdentifier: week.endDayIdentifier,
            averageCaloriesIn: Number.isFinite(week.averageCaloriesIn ?? NaN) ? week.averageCaloriesIn : undefined,
            averageCaloriesBurned: Number.isFinite(week.averageCaloriesBurned ?? NaN) ? week.averageCaloriesBurned : undefined,
            averageNetCalories: Number.isFinite(week.averageNetCalories ?? NaN) ? week.averageNetCalories : undefined,
            overGoalDays: Number.isFinite(week.overGoalDays ?? NaN) ? week.overGoalDays : undefined,
            underGoalDays: Number.isFinite(week.underGoalDays ?? NaN) ? week.underGoalDays : undefined,
            mealLoggedDays: Number.isFinite(week.mealLoggedDays ?? NaN) ? week.mealLoggedDays : undefined,
            exerciseDays: Number.isFinite(week.exerciseDays ?? NaN) ? week.exerciseDays : undefined,
            averageExerciseMinutes: Number.isFinite(week.averageExerciseMinutes ?? NaN) ? week.averageExerciseMinutes : undefined,
            averageProteinGrams: Number.isFinite(week.averageProteinGrams ?? NaN) ? week.averageProteinGrams : undefined,
            weightLoggedDays: Number.isFinite(week.weightLoggedDays ?? NaN) ? week.weightLoggedDays : undefined,
            weightChangePounds: Number.isFinite(week.weightChangePounds ?? NaN) ? week.weightChangePounds : undefined
          })),
          currentVsPreviousCaloriesDelta: Number.isFinite(summary.crossWeekPatterns.currentVsPreviousCaloriesDelta ?? NaN)
            ? summary.crossWeekPatterns.currentVsPreviousCaloriesDelta
            : undefined,
          currentVsPreviousNetDelta: Number.isFinite(summary.crossWeekPatterns.currentVsPreviousNetDelta ?? NaN)
            ? summary.crossWeekPatterns.currentVsPreviousNetDelta
            : undefined,
          currentVsPreviousProteinDelta: Number.isFinite(summary.crossWeekPatterns.currentVsPreviousProteinDelta ?? NaN)
            ? summary.crossWeekPatterns.currentVsPreviousProteinDelta
            : undefined,
          currentVsPreviousOverGoalDayDelta: Number.isFinite(summary.crossWeekPatterns.currentVsPreviousOverGoalDayDelta ?? NaN)
            ? summary.crossWeekPatterns.currentVsPreviousOverGoalDayDelta
            : undefined,
          currentVsPreviousExerciseDayDelta: Number.isFinite(summary.crossWeekPatterns.currentVsPreviousExerciseDayDelta ?? NaN)
            ? summary.crossWeekPatterns.currentVsPreviousExerciseDayDelta
            : undefined
        }
      : undefined,
    habitPatterns: summary.habitPatterns
      ? {
          averageEveningCalories: Number.isFinite(summary.habitPatterns.averageEveningCalories ?? NaN)
            ? summary.habitPatterns.averageEveningCalories
            : undefined,
          averageEveningSharePercent: Number.isFinite(summary.habitPatterns.averageEveningSharePercent ?? NaN)
            ? summary.habitPatterns.averageEveningSharePercent
            : undefined,
          breakfastLoggedDays: Number.isFinite(summary.habitPatterns.breakfastLoggedDays ?? NaN)
            ? summary.habitPatterns.breakfastLoggedDays
            : undefined,
          lunchLoggedDays: Number.isFinite(summary.habitPatterns.lunchLoggedDays ?? NaN)
            ? summary.habitPatterns.lunchLoggedDays
            : undefined,
          dinnerLoggedDays: Number.isFinite(summary.habitPatterns.dinnerLoggedDays ?? NaN)
            ? summary.habitPatterns.dinnerLoggedDays
            : undefined,
          snackLoggedDays: Number.isFinite(summary.habitPatterns.snackLoggedDays ?? NaN)
            ? summary.habitPatterns.snackLoggedDays
            : undefined,
          lateLogDays: Number.isFinite(summary.habitPatterns.lateLogDays ?? NaN)
            ? summary.habitPatterns.lateLogDays
            : undefined,
          exerciseDays: Number.isFinite(summary.habitPatterns.exerciseDays ?? NaN)
            ? summary.habitPatterns.exerciseDays
            : undefined,
          averageExerciseMinutesOnExerciseDays: Number.isFinite(summary.habitPatterns.averageExerciseMinutesOnExerciseDays ?? NaN)
            ? summary.habitPatterns.averageExerciseMinutesOnExerciseDays
            : undefined,
          mealPatterns: (summary.habitPatterns.mealPatterns ?? []).map((meal) => ({
            mealGroup: meal.mealGroup,
            averageCaloriesPerLoggedDay: Number.isFinite(meal.averageCaloriesPerLoggedDay ?? NaN)
              ? meal.averageCaloriesPerLoggedDay
              : undefined,
            loggedDays: Number.isFinite(meal.loggedDays ?? NaN) ? meal.loggedDays : undefined,
            totalCalories: Number.isFinite(meal.totalCalories ?? NaN) ? meal.totalCalories : undefined
          })),
          exercisePatterns: (summary.habitPatterns.exercisePatterns ?? []).map((exercise) => ({
            exerciseType: exercise.exerciseType,
            days: Number.isFinite(exercise.days ?? NaN) ? exercise.days : undefined,
            sessions: Number.isFinite(exercise.sessions ?? NaN) ? exercise.sessions : undefined,
            averageDurationMinutes: Number.isFinite(exercise.averageDurationMinutes ?? NaN)
              ? exercise.averageDurationMinutes
              : undefined,
            totalCalories: Number.isFinite(exercise.totalCalories ?? NaN) ? exercise.totalCalories : undefined
          })),
          repeatedOverGoalFoods: (summary.habitPatterns.repeatedOverGoalFoods ?? []).map((food) => ({
            name: food.name,
            overGoalDayCount: Number.isFinite(food.overGoalDayCount ?? NaN) ? food.overGoalDayCount : undefined,
            totalCalories: Number.isFinite(food.totalCalories ?? NaN) ? food.totalCalories : undefined,
            dominantMealGroup: food.dominantMealGroup
          }))
        }
      : undefined,
    loggedFoods: (summary.loggedFoods ?? []).map((f) => ({
      dayIdentifier: f.dayIdentifier,
      createdAt: f.createdAt,
      mealGroup: f.mealGroup,
      name: typeof f.name === "string" ? f.name : undefined,
      calories: Number.isFinite(f.calories ?? NaN) ? f.calories : undefined,
      protein: Number.isFinite(f.protein ?? NaN) ? f.protein : undefined,
      loggedCount: Number.isFinite(f.loggedCount ?? NaN) ? f.loggedCount : undefined
    }))
  };

  function normalizeWeeklyInsightText(raw: string): string {
    return raw.trim();
  }

  async function callGemini(promptText: string): Promise<
    | { ok: true; text: string; finishReason?: string; safetyBlocked?: boolean }
    | { ok: false; status: number; error: string }
  > {
    const body = {
      systemInstruction: {
        parts: [{ text: WEEKLY_INSIGHT_SYSTEM_PROMPT }]
      },
      contents: [
        {
          parts: [{ text: promptText }]
        }
      ],
      generationConfig: {
        temperature: 0.35,
        // Disable internal reasoning/thinking so output tokens are available for the actual insight.
        // Gemini 2.5 models can otherwise spend most of the budget on hidden "thoughts".
        thinkingConfig: { thinkingBudget: 0 },
        maxOutputTokens: 1024
      }
    };

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });

    if (!response.ok) {
      const errText = await response.text();
      logger.error("Gemini weekly insight upstream failed", {
        status: response.status,
        body: errText
      });
      let message = `Upstream error (HTTP ${response.status}).`;
      try {
        const errJson = JSON.parse(errText) as { error?: { message?: string } };
        if (errJson?.error?.message) message = errJson.error.message;
      } catch {
        // ignore
      }
      return { ok: false, status: 502, error: message };
    }

    const data = (await response.json()) as {
      candidates?: Array<{
        finishReason?: string;
        content?: { parts?: Array<{ text?: string }> };
        safetyRatings?: Array<{ category?: string; probability?: string }>;
      }>;
      promptFeedback?: { blockReason?: string };
    };

    const finishReason = data?.candidates?.[0]?.finishReason;
    const safetyBlocked = Boolean(data?.promptFeedback?.blockReason);
    const text = (data?.candidates?.[0]?.content?.parts ?? [])
      .map((p) => p.text ?? "")
      .join("")
      .trim();

    if (!text) {
      return { ok: false, status: 502, error: "AI returned an empty response." };
    }

    return { ok: true, text: normalizeWeeklyInsightText(text), finishReason, safetyBlocked };
  }

  try {
    const prompt = [
      "Here is a calendar-week nutrition summary as JSON (Sunday-Saturday; week-to-date excluding today, except Sunday uses the previous full week).",
      "Use the system instruction to write a brief weekly reflection and coaching for the user.",
      "JSON:",
      JSON.stringify(safeSummary)
    ].join("\n");

    const result = await callGemini(prompt);
    if (!result.ok) {
      return { status: result.status, body: { error: result.error } };
    }

    return { status: 200, body: { insight: result.text } };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    logger.error("Weekly insight analysis failed", error);
    return { status: 502, body: { error: message } };
  }
}

export const estimatePlatePortions = onRequest(
  { region: "us-central1", secrets: [geminiApiKeySecret] },
  async (req, res) => {
    const cors = applyCors(req, res, ["POST", "OPTIONS"], [APP_CHECK_HEADER, CLIENT_INSTANCE_ID_HEADER]);
    if (!cors.ok) {
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed." });
      return;
    }

    try {
      const authorized = await authorizeAIRequest(req, res, 2);
      if (!authorized) return;

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

export const analyzeFoodPhoto = onRequest(
  { region: "us-central1", secrets: [geminiApiKeySecret] },
  async (req, res) => {
    const cors = applyCors(req, res, ["POST", "OPTIONS"], [APP_CHECK_HEADER, CLIENT_INSTANCE_ID_HEADER]);
    if (!cors.ok) {
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed." });
      return;
    }

    try {
      const authorized = await authorizeAIRequest(req, res, 1);
      if (!authorized) return;

      const body = req.body as {
        imageBase64?: string;
        mimeType?: string;
      };

      const imageBase64 = typeof body.imageBase64 === "string" ? body.imageBase64 : "";
      const mimeType = typeof body.mimeType === "string" ? body.mimeType : "image/jpeg";

      if (!imageBase64) {
        res.status(400).json({ error: "Missing imageBase64." });
        return;
      }

      const apiKey = geminiApiKeySecret.value();
      const result = await performAIVisionAnalysis(apiKey, imageBase64, mimeType);
      res.status(result.status).json(result.body);
    } catch (error) {
      logger.error("AI food photo analysis failed", error);
      res.status(500).json({
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
  }
);

export const analyzeFoodText = onRequest(
  { region: "us-central1", secrets: [geminiApiKeySecret] },
  async (req, res) => {
    const cors = applyCors(req, res, ["POST", "OPTIONS"], [APP_CHECK_HEADER, CLIENT_INSTANCE_ID_HEADER]);
    if (!cors.ok) {
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed." });
      return;
    }

    try {
      const authorized = await authorizeAIRequest(req, res, 1);
      if (!authorized) return;

      const body = req.body as { mealText?: string };
      const mealText = typeof body.mealText === "string" ? body.mealText : "";
      if (!mealText.trim()) {
        res.status(400).json({ error: "Missing mealText." });
        return;
      }

      const apiKey = geminiApiKeySecret.value();
      const result = await performAITextAnalysis(apiKey, mealText);
      res.status(result.status).json(result.body);
    } catch (error) {
      logger.error("AI food text analysis failed", error);
      res.status(500).json({
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
  }
);

export const generateWeeklyInsight = onRequest(
  { region: "us-central1", secrets: [geminiApiKeySecret] },
  async (req, res) => {
    const cors = applyCors(req, res, ["POST", "OPTIONS"], [APP_CHECK_HEADER, CLIENT_INSTANCE_ID_HEADER]);
    if (!cors.ok) {
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed." });
      return;
    }

    try {
      const authorized = await authorizeAIRequest(req, res, 1);
      if (!authorized) return;

      const body = req.body as WeeklyInsightSummaryPayload;
      if (!body || !Array.isArray(body.days) || body.days.length === 0) {
        res.status(400).json({ error: "Missing days in summary." });
        return;
      }

      const apiKey = geminiApiKeySecret.value();
      const result = await performWeeklyInsightAnalysis(apiKey, body);
      res.status(result.status).json(result.body);
    } catch (error) {
      logger.error("Weekly insight generation failed", error);
      res.status(500).json({
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
  }
);

export const proxyNutrislice = onRequest({ region: "us-central1" }, async (req, res) => {
  const cors = applyCors(req, res, ["GET", "OPTIONS"]);
  if (!cors.ok) {
    return;
  }

  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed." });
    return;
  }

  try {
    const targetPath = req.url.replace(/^\/api\/nutrislice/, "");
    const targetUrl = `https://pccdining.api.nutrislice.com${targetPath}`;

    // Nutrislice API blocks exact matches of our referrer/origin
    const response = await fetch(targetUrl, {
      headers: {
        "Accept": "application/json",
        "User-Agent": "Mozilla/5.0 (compatible; NutrisliceProxy/1.0)"
      }
    });

    if (!response.ok) {
      logger.error("Nutrislice proxy failed", { status: response.status });
      res.status(response.status).send(await response.text());
      return;
    }

    const data = await response.json();
    res.status(200).json(data);
  } catch (error) {
    logger.error("Nutrislice proxy exception", error);
    res.status(500).json({
      error: error instanceof Error ? error.message : "Unknown error"
    });
  }
});
