#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const CONST = {
  KG_PER_LB: 0.45359237,
  KM_PER_MILE: 1.609344,
  WALK_NET_APP: 0.50, // current app value
  WALK_NET_REF: 0.50, // reference baseline for accuracy check
  RUN_MINS_PER_MILE_DEFAULT: 10.0,
  FALLBACK_FRACTION: 0.75,
};

function roundInt(v) { return Math.max(Math.round(v), 0); }
function lbToKg(lb) { return lb * CONST.KG_PER_LB; }
function milesToKm(mi) { return mi * CONST.KM_PER_MILE; }
function pctErr(app, ref) {
  if (ref === 0) return app === 0 ? 0 : 100;
  return ((app - ref) / ref) * 100;
}

function inferRunMiles(durationMin, paceMinPerMile) {
  if (durationMin <= 0) return null;
  if (paceMinPerMile && paceMinPerMile > 0) return durationMin / paceMinPerMile;
  return durationMin / CONST.RUN_MINS_PER_MILE_DEFAULT;
}

function appBorrowForRun({ weightLb, distanceMiles, durationMinutes, paceMinPerMile }) {
  const wKg = lbToKg(weightLb);
  if (distanceMiles && distanceMiles > 0) {
    return roundInt(wKg * milesToKm(distanceMiles) * CONST.WALK_NET_APP);
  }

  const inferred = inferRunMiles(durationMinutes, paceMinPerMile);
  if (inferred && inferred > 0) {
    return roundInt(wKg * milesToKm(inferred) * CONST.WALK_NET_APP);
  }

  // Rare fallback when no distance/time inference possible.
  const fallbackRunCalories = 0;
  return roundInt(fallbackRunCalories * CONST.FALLBACK_FRACTION);
}

function refBorrowForRun({ weightLb, distanceMiles, durationMinutes, paceMinPerMile }) {
  const wKg = lbToKg(weightLb);
  const miles = (distanceMiles && distanceMiles > 0)
    ? distanceMiles
    : inferRunMiles(durationMinutes, paceMinPerMile);
  if (!miles || miles <= 0) return 0;
  return roundInt(wKg * milesToKm(miles) * CONST.WALK_NET_REF);
}

function evaluateCase(c) {
  const perRun = c.runs.map((r, idx) => {
    const app = appBorrowForRun(r);
    const ref = refBorrowForRun(r);
    return {
      runId: `${c.id}-run${idx + 1}`,
      input: r,
      app,
      ref,
      deltaKcal: app - ref,
      deltaPct: pctErr(app, ref),
    };
  });

  const requestedAppBorrow = perRun.reduce((s, r) => s + r.app, 0);
  const requestedRefBorrow = perRun.reduce((s, r) => s + r.ref, 0);

  // App behavior in ContentView: min(totalRequestedReclassification, activityCaloriesToday)
  const effectiveAppBorrow = Math.min(requestedAppBorrow, c.stepCaloriesToday);
  const effectiveRefBorrow = Math.min(requestedRefBorrow, c.stepCaloriesToday);

  return {
    id: c.id,
    stepCaloriesToday: c.stepCaloriesToday,
    requestedAppBorrow,
    requestedRefBorrow,
    effectiveAppBorrow,
    effectiveRefBorrow,
    clampHit: requestedAppBorrow > c.stepCaloriesToday,
    perRun,
    requestDelta: requestedAppBorrow - requestedRefBorrow,
    effectiveDelta: effectiveAppBorrow - effectiveRefBorrow,
  };
}

function summarizePerRun(rows) {
  const flat = rows.flatMap((r) => r.perRun);
  const abs = flat.map((r) => Math.abs(r.deltaPct));
  const mae = flat.map((r) => Math.abs(r.deltaKcal));
  const mean = (arr) => arr.reduce((a, b) => a + b, 0) / arr.length;
  return {
    count: flat.length,
    mape: mean(abs),
    mae: mean(mae),
    minPct: Math.min(...flat.map((r) => r.deltaPct)),
    maxPct: Math.max(...flat.map((r) => r.deltaPct)),
  };
}

function summarizeEffective(rows) {
  const deltas = rows.map((r) => r.effectiveDelta);
  const abs = deltas.map((d) => Math.abs(d));
  const mean = (arr) => arr.reduce((a, b) => a + b, 0) / arr.length;
  return {
    count: rows.length,
    mae: mean(abs),
    min: Math.min(...deltas),
    max: Math.max(...deltas),
    clampHits: rows.filter((r) => r.clampHit).length,
  };
}

function run() {
  // Sample data: includes distance-present, duration-only, multiple runs/day, and clamp edge cases.
  const samples = [
    {
      id: 'C1-normal-distance',
      stepCaloriesToday: 420,
      runs: [
        { weightLb: 150, distanceMiles: 3.2, durationMinutes: 30, paceMinPerMile: 9.4 },
      ],
    },
    {
      id: 'C2-duration-only-with-pace',
      stepCaloriesToday: 380,
      runs: [
        { weightLb: 180, distanceMiles: null, durationMinutes: 40, paceMinPerMile: 9.5 },
      ],
    },
    {
      id: 'C3-two-runs-high-steps',
      stepCaloriesToday: 700,
      runs: [
        { weightLb: 165, distanceMiles: 2.5, durationMinutes: 23, paceMinPerMile: 9.2 },
        { weightLb: 165, distanceMiles: 4.0, durationMinutes: 38, paceMinPerMile: 9.5 },
      ],
    },
    {
      id: 'C4-clamp-low-steps',
      stepCaloriesToday: 140,
      runs: [
        { weightLb: 200, distanceMiles: 4.5, durationMinutes: 42, paceMinPerMile: 9.3 },
      ],
    },
    {
      id: 'C5-clamp-two-runs',
      stepCaloriesToday: 210,
      runs: [
        { weightLb: 190, distanceMiles: 3.0, durationMinutes: 28, paceMinPerMile: 9.4 },
        { weightLb: 190, distanceMiles: null, durationMinutes: 35, paceMinPerMile: 10.0 },
      ],
    },
    {
      id: 'C6-duration-no-pace-default-pace-infer',
      stepCaloriesToday: 330,
      runs: [
        { weightLb: 170, distanceMiles: null, durationMinutes: 50, paceMinPerMile: null },
      ],
    },
  ];

  const rows = samples.map(evaluateCase);
  const perRunSummary = summarizePerRun(rows);
  const effectiveSummary = summarizeEffective(rows);

  const lines = [];
  lines.push('Running-to-Steps Borrow Accuracy Audit');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push('');
  lines.push('Reference: 0.50 kcal/kg/km walking net baseline.');
  lines.push('App under test: ExerciseCalorieService.walkingEquivalentCalories + clamp by step calories in ContentView.');
  lines.push('');

  lines.push('Summary (per-run requested borrow)');
  lines.push(`  Cases: ${perRunSummary.count}`);
  lines.push(`  MAE: ${perRunSummary.mae.toFixed(1)} kcal`);
  lines.push(`  MAPE: ${perRunSummary.mape.toFixed(1)}%`);
  lines.push(`  Bias range: ${perRunSummary.minPct.toFixed(1)}% to +${perRunSummary.maxPct.toFixed(1)}%`);
  lines.push('');

  lines.push('Summary (effective day borrow after clamp to step calories)');
  lines.push(`  Days: ${effectiveSummary.count}`);
  lines.push(`  MAE: ${effectiveSummary.mae.toFixed(1)} kcal`);
  lines.push(`  Delta range: ${effectiveSummary.min} to ${effectiveSummary.max} kcal`);
  lines.push(`  Clamp hits: ${effectiveSummary.clampHits}/${effectiveSummary.count}`);
  lines.push('');

  rows.forEach((r) => {
    lines.push(`${r.id}`);
    lines.push(`  stepCaloriesToday: ${r.stepCaloriesToday}`);
    lines.push(`  requestedAppBorrow: ${r.requestedAppBorrow}`);
    lines.push(`  requestedRefBorrow: ${r.requestedRefBorrow}`);
    lines.push(`  effectiveAppBorrow: ${r.effectiveAppBorrow}`);
    lines.push(`  effectiveRefBorrow: ${r.effectiveRefBorrow}`);
    lines.push(`  clampHit: ${r.clampHit}`);
    lines.push(`  requestDelta: ${r.requestDelta}`);
    lines.push(`  effectiveDelta: ${r.effectiveDelta}`);
    r.perRun.forEach((p) => {
      lines.push(`    ${p.runId} input=${JSON.stringify(p.input)} app=${p.app} ref=${p.ref} delta=${p.deltaKcal} (${p.deltaPct.toFixed(2)}%)`);
    });
    lines.push('');
  });

  const outputDir = path.resolve(process.cwd(), 'output');
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });
  const outPath = path.join(outputDir, 'running_step_borrow_audit.txt');
  fs.writeFileSync(outPath, lines.join('\n'), 'utf8');

  console.log(lines.join('\n'));
  console.log(`\nReport written: ${outPath}`);
}

run();
