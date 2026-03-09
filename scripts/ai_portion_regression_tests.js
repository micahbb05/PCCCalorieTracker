#!/usr/bin/env node

const assert = require('assert/strict');

function isCountBased(name, servingUnit) {
  const u = String(servingUnit || '').trim().toLowerCase();
  const n = String(name || '').trim().toLowerCase();

  if (
    u.includes('cup') ||
    u.includes('oz') ||
    u === 'g' || u === 'gram' || u === 'grams' ||
    u.includes('tbsp') || u.includes('tablespoon') ||
    u.includes('tsp') || u.includes('teaspoon') ||
    u === 'ml' || u === 'l' || u === 'lb' || u === 'lbs'
  ) {
    return false;
  }

  if (['piece', 'pieces', 'slice', 'slices', 'nugget', 'nuggets'].includes(u)) return true;
  if (n.includes('nugget')) return true;
  if (n.includes('cookie') || n.includes('chips') || n.endsWith(' chip')) return true;
  return false;
}

function inferredBaseOzFromCalories(name, calories) {
  if (!(calories > 0)) return 4.0;
  const n = String(name || '').trim().toLowerCase();
  let calPerOz = 40;
  if (n.includes('chicken') || n.includes('beef') || n.includes('pork') || n.includes('meat') || n.includes('fish') || n.includes('protein')) {
    calPerOz = 50;
  } else if (n.includes('rice') || n.includes('pasta') || n.includes('grain') || n.includes('noodle')) {
    calPerOz = 35;
  } else if (n.includes('sauce') || n.includes('gravy') || n.includes('dressing')) {
    calPerOz = 25;
  }
  const oz = calories / calPerOz;
  return Math.max(0.25, Math.min(oz, 20.0));
}

function servingOzForPortions(item) {
  if (isCountBased(item.name, item.servingUnit)) return 1.0;
  const unit = String(item.servingUnit || '').trim().toLowerCase();
  const amount = Math.max(Number(item.servingAmount) || 0, 0);

  if (unit === 'g' || unit === 'gram' || unit === 'grams') return amount / 28.3495;
  if (unit.includes('oz')) return amount > 0 ? amount : 4.0;
  if (unit.includes('cup')) return (amount > 0 ? amount : 1.0) * 8.0;
  if (unit.includes('tbsp') || unit.includes('tablespoon')) return (amount > 0 ? amount : 1.0) * 0.5;
  if (unit.includes('tsp') || unit.includes('teaspoon')) return (amount > 0 ? amount : 1.0) * (1.0 / 6.0);

  if (!unit || ['serving', 'servings', 'each', 'ea', 'piece', 'pieces', 'item', 'slice', 'slices'].includes(unit)) {
    return inferredBaseOzFromCalories(item.name, item.calories);
  }

  return inferredBaseOzFromCalories(item.name, item.calories);
}

function convertedServingAmount(amount, unit) {
  const normalized = String(unit || '').trim().toLowerCase();
  if (normalized === 'g' || normalized === 'gram' || normalized === 'grams') {
    return amount / 28.3495;
  }
  return amount;
}

function inflectedUnit(unit, quantity) {
  const trimmed = String(unit || '').trim();
  if (!trimmed) return quantity === 1 ? 'serving' : 'servings';
  const lower = trimmed.toLowerCase();
  const invariant = ['oz', 'fl oz', 'g', 'mg', 'kg', 'lb', 'lbs', 'ml', 'l', 'tbsp', 'tsp'];
  if (invariant.includes(lower)) return lower;
  if (quantity === 1) {
    if (lower.endsWith('ies') && lower.length > 3) return `${lower.slice(0, -3)}y`;
    if (lower.endsWith('ses') && lower.length > 3) return lower.slice(0, -2);
    if (lower.endsWith('s') && lower.length > 1) return lower.slice(0, -1);
    return lower;
  }
  if (lower.endsWith('s')) return lower;
  if (lower.endsWith('y') && lower.length > 1) return `${lower.slice(0, -1)}ies`;
  if (lower.endsWith('ch') || lower.endsWith('sh') || lower.endsWith('x') || lower.endsWith('z')) return `${lower}es`;
  return `${lower}s`;
}

function formatAmount(amount) {
  return Number.isInteger(amount) ? String(amount) : amount.toFixed(1).replace(/\.0$/, '');
}

function formatPortionSummary(item, currentAmount) {
  const converted = convertedServingAmount(currentAmount, item.servingUnit);
  const unit = inflectedUnit(item.servingUnit, converted);
  return `${formatAmount(converted)} ${unit}`;
}

function draftNutritionCalories(item, currentAmount, baseOz) {
  const multiplier = baseOz > 0 ? (currentAmount / baseOz) : 1.0;
  return Math.max(0, Math.round(item.calories * multiplier));
}

async function analyzeFoodText(mealText) {
  const endpoint = 'https://us-central1-calorie-tracker-364e3.cloudfunctions.net/analyzeFoodText';
  const res = await fetch(endpoint, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ mealText }),
  });

  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new Error(`Non-JSON response (status ${res.status}): ${text.slice(0, 300)}`);
  }

  if (!res.ok) {
    throw new Error(`HTTP ${res.status}: ${json.error || text.slice(0, 300)}`);
  }

  return json;
}

function runCase(name, fn) {
  try {
    fn();
    return { name, ok: true };
  } catch (error) {
    return { name, ok: false, message: error instanceof Error ? error.message : String(error) };
  }
}

async function run() {
  const results = [];

  results.push(runCase('count-based sanity: nuggets should be count-based', () => {
    assert.equal(isCountBased('Chicken nuggets', 'nuggets'), true);
  }));

  results.push(runCase('Chicken Sandwich should remain count-based by serving unit', () => {
    const item = { name: 'Chicken Sandwich', servingUnit: 'sandwich', servingAmount: 1, calories: 420 };
    assert.equal(
      isCountBased(item.name, item.servingUnit),
      true,
      'Expected sandwich unit to be treated as count-based',
    );
  }));

  results.push(runCase('Chicken Sandwich portion summary should be 1 sandwich, not 8.4 sandwiches', () => {
    const item = { name: 'Chicken Sandwich', servingAmount: 1, servingUnit: 'sandwich', calories: 420 };
    const baseOz = servingOzForPortions(item);
    const currentAmount = baseOz * 1.0; // estimatedServings = 1
    const summary = formatPortionSummary(item, currentAmount);
    assert.equal(summary, '1 sandwich');
  }));

  results.push(runCase('Adjuster should not briefly show 50 cal before stabilizing at 420', () => {
    const item = { name: 'Chicken Sandwich', servingAmount: 1, servingUnit: 'sandwich', calories: 420 };
    const baseOz = servingOzForPortions(item);

    // Mirrors first sheet render before prepareServingAdjuster runs (baseline defaults to 1.0)
    const firstFrameCalories = draftNutritionCalories(item, 1.0, baseOz);

    // Mirrors post-prepare state where current amount is set to inferred total/base
    const settledCalories = draftNutritionCalories(item, baseOz, baseOz);

    assert.equal(firstFrameCalories, settledCalories, `First frame ${firstFrameCalories}cal != settled ${settledCalories}cal`);
  }));

  let liveApiNote = null;
  try {
    const live = await analyzeFoodText('cfa sandwich');
    const first = Array.isArray(live.items) ? live.items[0] : null;
    liveApiNote = first
      ? `Live AI sample: name="${first.name}", unit="${first.servingUnit}", servingAmount=${first.servingAmount}, estimatedServings=${first.estimatedServings}, calories=${first.calories}`
      : 'Live AI sample returned no items';
  } catch (error) {
    liveApiNote = `Live AI sample skipped: ${error instanceof Error ? error.message : String(error)}`;
  }

  const passed = results.filter((r) => r.ok);
  const failed = results.filter((r) => !r.ok);

  console.log('AI Portion Regression Tests');
  console.log('==========================');
  for (const r of results) {
    if (r.ok) {
      console.log(`PASS: ${r.name}`);
    } else {
      console.log(`FAIL: ${r.name}`);
      console.log(`  -> ${r.message}`);
    }
  }

  console.log('');
  console.log(liveApiNote);
  console.log('');
  console.log(`Summary: ${passed.length} passed, ${failed.length} failed`);

  if (failed.length > 0) {
    process.exit(1);
  }
}

run().catch((error) => {
  console.error(error instanceof Error ? error.stack || error.message : String(error));
  process.exit(1);
});
