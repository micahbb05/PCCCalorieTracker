#!/usr/bin/env node

/*
Stress test for PCC Smart Log (`estimatePlatePortions`) using a 10-food image.

Usage:
  node scripts/gemini_plate_stress_test.js \
    --image output/ai-stress/ten-food-collage.png \
    --runs 12 \
    --endpoint https://us-central1-calorie-tracker-364e3.cloudfunctions.net/estimatePlatePortions
*/

const fs = require('fs');
const path = require('path');

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (!token.startsWith('--')) continue;
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next && !next.startsWith('--')) {
      out[key] = next;
      i += 1;
    } else {
      out[key] = 'true';
    }
  }
  return out;
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

const FOOD_ITEMS = [
  { name: 'Apple', calories: 95, servingAmount: 1, servingUnit: 'each' },
  { name: 'Banana', calories: 105, servingAmount: 1, servingUnit: 'each' },
  { name: 'Broccoli', calories: 55, servingAmount: 1, servingUnit: 'cup' },
  { name: 'Pizza', calories: 285, servingAmount: 1, servingUnit: 'slice' },
  { name: 'Hamburger', calories: 354, servingAmount: 1, servingUnit: 'each' },
  { name: 'Sushi', calories: 45, servingAmount: 1, servingUnit: 'piece' },
  { name: 'French Fries', calories: 365, servingAmount: 1, servingUnit: 'cup' },
  { name: 'Salad', calories: 33, servingAmount: 1, servingUnit: 'cup' },
  { name: 'Doughnut', calories: 195, servingAmount: 1, servingUnit: 'each' },
  { name: 'Steak', calories: 271, servingAmount: 4, servingUnit: 'oz' },
];

const EXPLICIT_BASE_ITEMS = new Set(['Broccoli', 'French Fries', 'Salad', 'Steak']);

async function run() {
  const args = parseArgs(process.argv);
  const endpoint = args.endpoint || 'https://us-central1-calorie-tracker-364e3.cloudfunctions.net/estimatePlatePortions';
  const imagePath = path.resolve(args.image || 'output/ai-stress/ten-food-collage.png');
  const runs = Number.parseInt(args.runs || '12', 10);
  const delayMs = Number.parseInt(args.delayMs || '700', 10);

  if (!fs.existsSync(imagePath)) {
    console.error(`Image not found: ${imagePath}`);
    process.exit(1);
  }

  const imageBase64 = fs.readFileSync(imagePath).toString('base64');
  const foodNames = FOOD_ITEMS.map((f) => f.name);

  const runResults = [];

  console.log(`Endpoint: ${endpoint}`);
  console.log(`Image: ${imagePath}`);
  console.log(`Runs: ${runs}`);
  console.log('');

  for (let i = 0; i < runs; i += 1) {
    const started = Date.now();
    let status = 0;
    let body = null;
    let err = null;

    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          imageBase64,
          mimeType: 'image/png',
          foodItems: FOOD_ITEMS,
        }),
      });
      status = res.status;
      body = await res.json();
    } catch (e) {
      err = e instanceof Error ? e.message : String(e);
    }

    const durationMs = Date.now() - started;

    if (err || status !== 200 || !body) {
      runResults.push({ ok: false, detected: 0, recall: 0, durationMs, baseExplicitViolations: 0 });
      console.log(`#${String(i + 1).padStart(2, '0')} FAIL status=${status || 'ERR'} duration=${durationMs}ms error=${err || body?.error || 'unknown'}`);
      await sleep(delayMs);
      continue;
    }

    const oz = body.ozByFoodName || {};
    const count = body.countByFoodName || {};
    const base = body.baseOzByFoodName || {};

    const presentNames = foodNames.filter((name) => (Number(oz[name] || 0) > 0) || (Number(count[name] || 0) > 0));
    const detected = presentNames.length;
    const recall = detected / foodNames.length;
    const missing = foodNames.filter((name) => !presentNames.includes(name));

    const explicitViolations = [...EXPLICIT_BASE_ITEMS].filter((name) => Number(base[name] || 0) > 0);

    runResults.push({
      ok: true,
      detected,
      recall,
      durationMs,
      baseExplicitViolations: explicitViolations.length,
    });

    console.log(`#${String(i + 1).padStart(2, '0')} OK detected=${detected}/10 recall=${round2(recall)} duration=${durationMs}ms`);
    if (missing.length > 0) console.log(`   missing: ${missing.join(', ')}`);
    if (explicitViolations.length > 0) console.log(`   explicit-base violations: ${explicitViolations.join(', ')}`);

    await sleep(delayMs);
  }

  const completed = runResults.filter((r) => r.ok);
  const avgRecall = completed.length
    ? completed.reduce((s, r) => s + r.recall, 0) / completed.length
    : 0;
  const minRecall = completed.length
    ? completed.reduce((m, r) => Math.min(m, r.recall), 1)
    : 0;
  const avgDuration = completed.length
    ? completed.reduce((s, r) => s + r.durationMs, 0) / completed.length
    : 0;
  const totalExplicitViolations = completed.reduce((s, r) => s + r.baseExplicitViolations, 0);
  const failedCalls = runResults.length - completed.length;

  console.log('\n=== Summary ===');
  console.log(`Successful calls: ${completed.length}/${runResults.length}`);
  console.log(`Failed calls: ${failedCalls}`);
  console.log(`Average recall: ${round2(avgRecall)}`);
  console.log(`Minimum recall: ${round2(minRecall)}`);
  console.log(`Average latency: ${Math.round(avgDuration)}ms`);
  console.log(`Explicit base-serving violations: ${totalExplicitViolations}`);

  const strictPass = failedCalls === 0
    && avgRecall >= 0.9
    && minRecall >= 0.8
    && totalExplicitViolations === 0;

  if (!strictPass) {
    console.error('\nResult: FAIL (does not meet strict reliability threshold)');
    process.exit(1);
  }

  console.log('\nResult: PASS');
}

run().catch((err) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(1);
});
