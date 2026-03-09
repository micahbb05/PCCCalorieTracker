#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const {
  ensureDir,
  mean,
  pickTier,
  readJson,
  safeNumber,
  timedFetch,
  writeJson,
} = require('./lib/common');

const ROOT = path.resolve(__dirname, '..', '..');
const BASE_URL = (process.env.BACKEND_BASE_URL || 'https://us-central1-calorie-tracker-364e3.cloudfunctions.net').replace(/\/$/, '');

const NUTRIENT_KEYS = new Set([
  'calories', 'g_protein', 'g_carbs', 'g_fat', 'g_saturated_fat', 'g_trans_fat', 'g_fiber', 'g_sugar', 'g_added_sugar',
  'mg_sodium', 'mg_cholesterol', 'mg_potassium', 'mg_calcium', 'mg_iron', 'mg_vitamin_c', 'iu_vitamin_a', 'mcg_vitamin_a', 'mcg_vitamin_d',
]);

function totalCaloriesFromItems(items) {
  return items.reduce((sum, item) => {
    const calories = safeNumber(item.calories, 0);
    const servings = safeNumber(item.estimatedServings, 1);
    return sum + Math.max(0, calories) * Math.max(0, servings || 1);
  }, 0);
}

function calorieErrorPct(actual, min, max) {
  const midpoint = (min + max) / 2;
  if (actual >= min && actual <= max) return 0;
  if (midpoint <= 0) return 100;
  return (Math.abs(actual - midpoint) / midpoint) * 100;
}

function containsKeyword(items, keyword) {
  const k = keyword.toLowerCase();
  return items.some((item) => String(item.name || '').toLowerCase().includes(k));
}

function validateItemShape(item) {
  if (!item || typeof item !== 'object') return false;
  if (typeof item.name !== 'string' || !item.name.trim()) return false;
  if (typeof item.calories !== 'number' || !Number.isFinite(item.calories) || item.calories < 0) return false;
  if (typeof item.servingAmount !== 'number' || !Number.isFinite(item.servingAmount) || item.servingAmount <= 0) return false;
  if (typeof item.servingUnit !== 'string' || !item.servingUnit.trim()) return false;
  if (typeof item.estimatedServings !== 'number' || !Number.isFinite(item.estimatedServings) || item.estimatedServings <= 0) return false;
  if (item.nutrients && typeof item.nutrients === 'object') {
    for (const [key, value] of Object.entries(item.nutrients)) {
      if (!NUTRIENT_KEYS.has(key)) return false;
      if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) return false;
    }
  }
  return true;
}

async function analyzeText(mealText) {
  const url = `${BASE_URL}/analyzeFoodText`;
  return timedFetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ mealText }),
  });
}

async function analyzeImage(imagePath, mimeType) {
  const url = `${BASE_URL}/analyzeFoodPhoto`;
  const abs = path.resolve(ROOT, imagePath);
  if (!fs.existsSync(abs)) {
    throw new Error(`Missing image fixture: ${imagePath}`);
  }

  const imageBase64 = fs.readFileSync(abs).toString('base64');
  return timedFetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ imageBase64, mimeType }),
  });
}

async function main() {
  const tier = pickTier();
  const runId = process.env.STRESS_RUN_ID || 'adhoc';
  const outDir = path.join(ROOT, 'output', 'stress', runId);
  ensureDir(outDir);

  const allCases = readJson(path.join(ROOT, 'scripts', 'stress', 'fixtures', 'ai_eval_cases.v1.json'));
  const cases = tier === 'pr' ? allCases.slice(0, 2) : allCases;

  const results = [];
  for (const testCase of cases) {
    let call;
    try {
      call = testCase.kind === 'text'
        ? await analyzeText(testCase.input.mealText)
        : await analyzeImage(testCase.input.imagePath, testCase.input.mimeType || 'image/jpeg');
    } catch (error) {
      results.push({
        id: testCase.id,
        kind: testCase.kind,
        ok: false,
        parseValid: false,
        malformed: true,
        calorieErrorPct: 100,
        hallucination: true,
        error: error instanceof Error ? error.message : String(error),
      });
      continue;
    }

    const statusOk = call.response.status >= 200 && call.response.status < 300;
    const items = Array.isArray(call.json?.items) ? call.json.items : [];
    const shapeValid = statusOk && items.length > 0 && items.every(validateItemShape);
    const totalCalories = totalCaloriesFromItems(items);
    const errPct = calorieErrorPct(totalCalories, testCase.expected.totalCaloriesMin, testCase.expected.totalCaloriesMax);
    const expectedKeywords = testCase.expected.expectedFoodKeywords || [];
    const keywordMatches = expectedKeywords.filter((k) => containsKeyword(items, k));
    const hallucination = testCase.expected.allowExtraItems
      ? false
      : keywordMatches.length < expectedKeywords.length;

    results.push({
      id: testCase.id,
      kind: testCase.kind,
      status: call.response.status,
      latencyMs: call.durationMs,
      ok: statusOk && shapeValid,
      parseValid: shapeValid,
      malformed: !shapeValid,
      calorieErrorPct: errPct,
      hallucination,
      totalCalories,
      expectedRange: [testCase.expected.totalCaloriesMin, testCase.expected.totalCaloriesMax],
      matchedKeywords: keywordMatches,
      itemCount: items.length,
    });
  }

  const total = results.length || 1;
  const parseValidity = results.filter((r) => r.parseValid).length / total;
  const malformedRate = results.filter((r) => r.malformed).length / total;

  const textRows = results.filter((r) => r.kind === 'text');
  const imageRows = results.filter((r) => r.kind === 'image');

  const textMAPE = mean(textRows.map((r) => r.calorieErrorPct));
  const imageMAPE = mean(imageRows.map((r) => r.calorieErrorPct));
  const hallucinationRate = results.filter((r) => r.hallucination).length / total;

  const summary = {
    suite: 'ai_quality',
    tier,
    passed: parseValidity >= 0.99
      && malformedRate <= 0.01
      && textMAPE <= 20
      && (imageRows.length === 0 || imageMAPE <= 25),
    metrics: {
      aiParseValidity: parseValidity,
      aiMalformedRate: malformedRate,
      aiTextMAPE: textMAPE,
      aiImageMAPE: imageMAPE,
      aiHallucinationRate: hallucinationRate,
    },
    cases: results,
  };

  writeJson(path.join(outDir, 'ai_quality.json'), summary);
  console.log(JSON.stringify(summary, null, 2));
  if (!summary.passed) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
