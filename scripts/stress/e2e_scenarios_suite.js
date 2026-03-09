#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const {
  ensureDir,
  pickTier,
  timedFetch,
  writeJson,
} = require('./lib/common');

const ROOT = path.resolve(__dirname, '..', '..');
const BASE_URL = (process.env.BACKEND_BASE_URL || 'https://us-central1-calorie-tracker-364e3.cloudfunctions.net').replace(/\/$/, '');

function pass(name, details = {}) {
  return { name, ok: true, ...details };
}

function fail(name, details = {}) {
  return { name, ok: false, ...details };
}

async function scenarioUSDAPath() {
  const url = `${BASE_URL}/searchUSDAFoods?query=banana`;
  const res = await timedFetch(url, { method: 'GET' });
  if (res.response.status !== 200 || !Array.isArray(res.json?.foods) || !res.json.foods.length) {
    return fail('usda_path', { status: res.response.status, sample: res.text.slice(0, 200) });
  }
  const food = res.json.foods[0];
  if (typeof food.calories !== 'number' || food.calories < 0) {
    return fail('usda_path', { status: res.response.status, reason: 'invalid food payload' });
  }
  return pass('usda_path', { status: 200, selectedFood: food.name, calories: food.calories });
}

async function scenarioMenuImportPath() {
  const url = `${BASE_URL}/proxyNutrislice`;
  const res = await timedFetch(url, { method: 'GET' });

  if (![200, 404].includes(res.response.status) || (res.response.status === 200 && typeof res.json !== 'object')) {
    return fail('menu_import_path', { status: res.response.status, sample: res.text.slice(0, 200) });
  }

  if (res.response.status === 404) {
    return pass('menu_import_path', { status: 404, note: 'proxy reachable; upstream path unavailable in direct function mode' });
  }

  const days = Array.isArray(res.json.days) ? res.json.days : [];
  const hasAnyItems = days.some((day) => Array.isArray(day.menu_items) && day.menu_items.length > 0);
  if (!hasAnyItems) return fail('menu_import_path', { status: 200, reason: 'no menu items returned' });
  return pass('menu_import_path', { status: 200, days: days.length });
}

async function scenarioAITextPath() {
  const url = `${BASE_URL}/analyzeFoodText`;
  const res = await timedFetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ mealText: 'chicken bowl with rice' }),
  });

  if (res.response.status !== 200 || !Array.isArray(res.json?.items) || !res.json.items.length) {
    return fail('ai_text_path', { status: res.response.status, sample: res.text.slice(0, 200) });
  }
  return pass('ai_text_path', { status: 200, itemCount: res.json.items.length });
}

async function scenarioAIFoodPhotoPath() {
  const imagePath = path.join(ROOT, 'output', 'ai-stress', 'ten-food-collage.png');
  if (!fs.existsSync(imagePath)) {
    return fail('ai_food_photo_path', { reason: 'missing image fixture' });
  }

  const url = `${BASE_URL}/analyzeFoodPhoto`;
  const res = await timedFetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      imageBase64: fs.readFileSync(imagePath).toString('base64'),
      mimeType: 'image/png',
    }),
  });

  if (res.response.status !== 200 || !Array.isArray(res.json?.items) || !res.json.items.length) {
    return fail('ai_food_photo_path', { status: res.response.status, sample: res.text.slice(0, 200) });
  }
  return pass('ai_food_photo_path', { status: 200, itemCount: res.json.items.length });
}

async function scenarioPlateEstimatePath() {
  const imagePath = path.join(ROOT, 'output', 'ai-stress', 'ten-food-collage.png');
  if (!fs.existsSync(imagePath)) {
    return fail('plate_estimate_path', { reason: 'missing image fixture' });
  }

  const url = `${BASE_URL}/estimatePlatePortions`;
  const res = await timedFetch(url, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      imageBase64: fs.readFileSync(imagePath).toString('base64'),
      mimeType: 'image/png',
      foodItems: [
        { name: 'Apple', calories: 95, servingAmount: 1, servingUnit: 'each' },
        { name: 'Banana', calories: 105, servingAmount: 1, servingUnit: 'each' },
      ],
    }),
  });

  if (res.response.status !== 200 || typeof res.json?.ozByFoodName !== 'object') {
    return fail('plate_estimate_path', { status: res.response.status, sample: res.text.slice(0, 200) });
  }
  return pass('plate_estimate_path', { status: 200, keys: Object.keys(res.json.ozByFoodName).length });
}

async function main() {
  const tier = pickTier();
  const runId = process.env.STRESS_RUN_ID || 'adhoc';
  const outDir = path.join(ROOT, 'output', 'stress', runId);
  ensureDir(outDir);

  const scenarios = [
    scenarioUSDAPath,
    scenarioMenuImportPath,
    scenarioAITextPath,
    scenarioAIFoodPhotoPath,
    scenarioPlateEstimatePath,
  ];

  const selected = tier === 'pr' ? scenarios.slice(0, 3) : scenarios;

  const results = [];
  for (const scenario of selected) {
    try {
      results.push(await scenario());
    } catch (error) {
      results.push(fail(scenario.name, { reason: error instanceof Error ? error.message : String(error) }));
    }
  }

  const passed = results.every((x) => x.ok);
  const summary = {
    suite: 'e2e_scenarios',
    tier,
    passed,
    metrics: {
      scenarioPassRate: results.filter((x) => x.ok).length / (results.length || 1),
    },
    scenarios: results,
  };

  writeJson(path.join(outDir, 'e2e_scenarios.json'), summary);
  console.log(JSON.stringify(summary, null, 2));
  if (!passed) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
