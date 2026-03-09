#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const APP = {
  defaultWeightLb: 170,
  defaultHeightIn: 68,
  strideMultiplier: 0.415,
  netWalkingKcalPerKgPerKm: 0.50,
  runningKcalPerKgPerKm: 1.0,
  fallbackRunningPaceMinPerMile: 10.0,
  walkingEquivalentFallbackFraction: 0.75,
};

const REF = {
  netWalkingKcalPerKgPerKm: 0.50,
  runningKcalPerKgPerKm: 1.0,
};

function lbToKg(lb) { return lb * 0.45359237; }
function inchToM(inches) { return inches * 0.0254; }
function milesToKm(miles) { return miles * 1.609344; }
function roundInt(v) { return Math.max(Math.round(v), 0); }
function mean(arr) { return arr.reduce((a, b) => a + b, 0) / arr.length; }

function pctErr(est, ref) {
  if (ref === 0) return est === 0 ? 0 : 100;
  return ((est - ref) / ref) * 100;
}

function summarizeRows(rows) {
  const absKcal = rows.map((r) => Math.abs(r.deltaKcal));
  const absPct = rows.map((r) => Math.abs(r.deltaPct));
  return {
    count: rows.length,
    maeKcal: mean(absKcal),
    mapePct: mean(absPct),
    minPct: Math.min(...rows.map((r) => r.deltaPct)),
    maxPct: Math.max(...rows.map((r) => r.deltaPct)),
    worst: rows.slice().sort((a, b) => Math.abs(b.deltaPct) - Math.abs(a.deltaPct))[0],
  };
}

function grade(summary, goodThresholdPct = 10, acceptableThresholdPct = 15) {
  if (summary.mapePct <= goodThresholdPct) return 'good';
  if (summary.mapePct <= acceptableThresholdPct) return 'acceptable';
  return 'poor';
}

function mifflinBMR(profile) {
  const weightKg = lbToKg(profile.weightLb);
  const heightCm = profile.heightIn * 2.54;
  const sexConst = profile.sex === 'male' ? 5 : -161;
  const raw = (10 * weightKg) + (6.25 * heightCm) - (5 * profile.age) + sexConst;
  return Math.max(roundInt(raw), 800);
}

function appStepCalories({ steps, distanceMeters, weightLb, heightIn }) {
  if (steps <= 0) return 0;
  const w = weightLb > 0 ? weightLb : APP.defaultWeightLb;
  const h = heightIn > 0 ? heightIn : APP.defaultHeightIn;
  const weightKg = lbToKg(w);
  const distanceKm = distanceMeters > 0
    ? distanceMeters / 1000
    : (steps * (inchToM(h) * APP.strideMultiplier)) / 1000;
  if (distanceKm <= 0) return 0;
  return roundInt(weightKg * distanceKm * APP.netWalkingKcalPerKgPerKm);
}

function refStepCalories({ steps, distanceMeters, weightLb, heightIn }) {
  if (steps <= 0) return 0;
  const w = weightLb > 0 ? weightLb : APP.defaultWeightLb;
  const h = heightIn > 0 ? heightIn : APP.defaultHeightIn;
  const weightKg = lbToKg(w);
  const distanceKm = distanceMeters > 0
    ? distanceMeters / 1000
    : (steps * (inchToM(h) * 0.414)) / 1000;
  if (distanceKm <= 0) return 0;
  return roundInt(weightKg * distanceKm * REF.netWalkingKcalPerKgPerKm);
}

function appRunningCaloriesDistance(distanceMiles, weightLb) {
  return roundInt(lbToKg(weightLb) * milesToKm(distanceMiles) * APP.runningKcalPerKgPerKm);
}

function refRunningCaloriesDistance(distanceMiles, weightLb) {
  return roundInt(lbToKg(weightLb) * milesToKm(distanceMiles) * REF.runningKcalPerKgPerKm);
}

function runningMET(speedMph) {
  if (speedMph < 5.0) return 6.0;
  if (speedMph < 5.5) return 8.3;
  if (speedMph < 6.5) return 9.8;
  if (speedMph < 7.5) return 11.0;
  if (speedMph < 8.5) return 11.8;
  if (speedMph < 9.5) return 12.8;
  return 14.5;
}

function appRunningCaloriesDuration({ durationMinutes, durationSeconds, paceMinPerMile, distanceMiles, weightLb }) {
  const secs = durationSeconds && durationSeconds > 0 ? durationSeconds : durationMinutes * 60;
  const hrs = secs / 3600;
  if (distanceMiles && distanceMiles > 0) {
    return appRunningCaloriesDistance(distanceMiles, weightLb);
  }
  const speedMph = paceMinPerMile && paceMinPerMile > 0
    ? 60 / paceMinPerMile
    : 60 / APP.fallbackRunningPaceMinPerMile;
  const met = runningMET(speedMph);
  return roundInt(met * lbToKg(weightLb) * hrs);
}

function refRunningCaloriesDuration({ durationMinutes, durationSeconds, paceMinPerMile, distanceMiles, weightLb }) {
  if (distanceMiles && distanceMiles > 0) {
    return refRunningCaloriesDistance(distanceMiles, weightLb);
  }
  const mins = durationSeconds && durationSeconds > 0 ? (durationSeconds / 60) : durationMinutes;
  const pace = paceMinPerMile && paceMinPerMile > 0 ? paceMinPerMile : APP.fallbackRunningPaceMinPerMile;
  const miles = mins / pace;
  return refRunningCaloriesDistance(miles, weightLb);
}

function appWalkingBorrowDistance(distanceMiles, weightLb) {
  return roundInt(lbToKg(weightLb) * milesToKm(distanceMiles) * APP.netWalkingKcalPerKgPerKm);
}

function refWalkingBorrowDistance(distanceMiles, weightLb) {
  return roundInt(lbToKg(weightLb) * milesToKm(distanceMiles) * REF.netWalkingKcalPerKgPerKm);
}

function inferRunningDistanceMiles({ durationMinutes, durationSeconds, paceMinPerMile }) {
  const mins = durationSeconds && durationSeconds > 0 ? durationSeconds / 60 : durationMinutes;
  if (mins <= 0) return null;
  if (paceMinPerMile && paceMinPerMile > 0) return mins / paceMinPerMile;
  return mins / APP.fallbackRunningPaceMinPerMile;
}

function appWalkingBorrowDuration({ durationMinutes, durationSeconds, paceMinPerMile, weightLb }) {
  const miles = inferRunningDistanceMiles({ durationMinutes, durationSeconds, paceMinPerMile });
  if (miles && miles > 0) return appWalkingBorrowDistance(miles, weightLb);
  const runCals = appRunningCaloriesDuration({ durationMinutes, durationSeconds, paceMinPerMile, distanceMiles: null, weightLb });
  return roundInt(runCals * APP.walkingEquivalentFallbackFraction);
}

function refWalkingBorrowDuration({ durationMinutes, durationSeconds, paceMinPerMile, weightLb }) {
  const miles = inferRunningDistanceMiles({ durationMinutes, durationSeconds, paceMinPerMile });
  if (!miles || miles <= 0) return 0;
  return refWalkingBorrowDistance(miles, weightLb);
}

function appTDEE({ profile, steps, distanceMeters, runs, otherExerciseCalories = 0 }) {
  const bmr = mifflinBMR(profile);
  const step = appStepCalories({ steps, distanceMeters, weightLb: profile.weightLb, heightIn: profile.heightIn });
  let runCalories = 0;
  let walkBorrow = 0;
  for (const run of runs) {
    runCalories += appRunningCaloriesDuration({
      durationMinutes: run.durationMinutes,
      durationSeconds: run.durationSeconds,
      paceMinPerMile: run.paceMinPerMile,
      distanceMiles: run.distanceMiles,
      weightLb: profile.weightLb,
    });
    walkBorrow += run.distanceMiles && run.distanceMiles > 0
      ? appWalkingBorrowDistance(run.distanceMiles, profile.weightLb)
      : appWalkingBorrowDuration({
          durationMinutes: run.durationMinutes,
          durationSeconds: run.durationSeconds,
          paceMinPerMile: run.paceMinPerMile,
          weightLb: profile.weightLb,
        });
  }
  const effectiveBorrow = Math.min(walkBorrow, step);
  const effectiveActivity = Math.max(step - effectiveBorrow, 0);
  const burnedBaseline = bmr + effectiveActivity + runCalories + otherExerciseCalories;
  return { bmr, step, walkBorrow, effectiveBorrow, effectiveActivity, runCalories, burnedBaseline };
}

function refTDEE({ profile, steps, distanceMeters, runs, otherExerciseCalories = 0 }) {
  const bmr = mifflinBMR(profile);
  const step = refStepCalories({ steps, distanceMeters, weightLb: profile.weightLb, heightIn: profile.heightIn });
  let runCalories = 0;
  let walkBorrow = 0;
  for (const run of runs) {
    runCalories += refRunningCaloriesDuration({
      durationMinutes: run.durationMinutes,
      durationSeconds: run.durationSeconds,
      paceMinPerMile: run.paceMinPerMile,
      distanceMiles: run.distanceMiles,
      weightLb: profile.weightLb,
    });
    walkBorrow += run.distanceMiles && run.distanceMiles > 0
      ? refWalkingBorrowDistance(run.distanceMiles, profile.weightLb)
      : refWalkingBorrowDuration({
          durationMinutes: run.durationMinutes,
          durationSeconds: run.durationSeconds,
          paceMinPerMile: run.paceMinPerMile,
          weightLb: profile.weightLb,
        });
  }
  const effectiveBorrow = Math.min(walkBorrow, step);
  const effectiveActivity = Math.max(step - effectiveBorrow, 0);
  const burnedBaseline = bmr + effectiveActivity + runCalories + otherExerciseCalories;
  return { bmr, step, walkBorrow, effectiveBorrow, effectiveActivity, runCalories, burnedBaseline };
}

function buildRunningAutoCases() {
  return [
    { id: 'R1', weightLb: 130, distanceMiles: 2.0, durationMinutes: 18, paceMinPerMile: 9.0 },
    { id: 'R2', weightLb: 160, distanceMiles: 3.1, durationMinutes: 28, paceMinPerMile: 9.0 },
    { id: 'R3', weightLb: 185, distanceMiles: 5.0, durationMinutes: 47, paceMinPerMile: 9.4 },
    { id: 'R4', weightLb: 220, distanceMiles: 7.0, durationMinutes: 70, paceMinPerMile: 10.0 },
  ];
}

function buildHealthKitCases() {
  return [
    { id: 'HK1', weightLb: 145, distanceMiles: 2.5, durationSeconds: 22 * 60 },
    { id: 'HK2', weightLb: 170, distanceMiles: 4.2, durationSeconds: 38 * 60 },
    { id: 'HK3', weightLb: 195, distanceMiles: 6.0, durationSeconds: 58 * 60 },
    { id: 'HK4', weightLb: 210, distanceMiles: null, durationSeconds: 40 * 60, paceMinPerMile: 9.5 },
  ];
}

function buildWalkingBorrowCases() {
  return [
    { id: 'W1', weightLb: 140, distanceMiles: 2.0, durationMinutes: 18, paceMinPerMile: 9.0 },
    { id: 'W2', weightLb: 165, distanceMiles: 3.1, durationMinutes: 30, paceMinPerMile: 9.7 },
    { id: 'W3', weightLb: 190, distanceMiles: 5.0, durationMinutes: 50, paceMinPerMile: 10.0 },
    { id: 'W4', weightLb: 220, distanceMiles: null, durationMinutes: 45, paceMinPerMile: 9.0 },
  ];
}

function buildStepCases() {
  return [
    { id: 'S1', steps: 3000, distanceMeters: 0, weightLb: 120, heightIn: 62 },
    { id: 'S2', steps: 7000, distanceMeters: 0, weightLb: 150, heightIn: 66 },
    { id: 'S3', steps: 10000, distanceMeters: 0, weightLb: 170, heightIn: 68 },
    { id: 'S4', steps: 14000, distanceMeters: 0, weightLb: 200, heightIn: 72 },
    { id: 'S5', steps: 12000, distanceMeters: 8900, weightLb: 190, heightIn: 71 },
    { id: 'S6', steps: 8500, distanceMeters: 6100, weightLb: 155, heightIn: 67 },
  ];
}

function buildTDEECases() {
  return [
    {
      id: 'T1',
      profile: { sex: 'male', age: 24, heightIn: 70, weightLb: 175 },
      steps: 9000,
      distanceMeters: 6800,
      runs: [{ distanceMiles: 3.0, durationMinutes: 27, durationSeconds: 27 * 60, paceMinPerMile: 9.0 }],
      otherExerciseCalories: 120,
    },
    {
      id: 'T2',
      profile: { sex: 'female', age: 29, heightIn: 64, weightLb: 140 },
      steps: 7000,
      distanceMeters: 5100,
      runs: [{ distanceMiles: 2.0, durationMinutes: 20, durationSeconds: 20 * 60, paceMinPerMile: 10.0 }],
      otherExerciseCalories: 80,
    },
    {
      id: 'T3',
      profile: { sex: 'male', age: 37, heightIn: 72, weightLb: 205 },
      steps: 12000,
      distanceMeters: 9300,
      runs: [{ distanceMiles: 4.0, durationMinutes: 38, durationSeconds: 38 * 60, paceMinPerMile: 9.5 }],
      otherExerciseCalories: 0,
    },
    {
      id: 'T4',
      profile: { sex: 'female', age: 45, heightIn: 66, weightLb: 165 },
      steps: 6000,
      distanceMeters: 0,
      runs: [{ distanceMiles: null, durationMinutes: 35, durationSeconds: 35 * 60, paceMinPerMile: 9.5 }],
      otherExerciseCalories: 150,
    },
    {
      id: 'T5',
      profile: { sex: 'male', age: 31, heightIn: 68, weightLb: 180 },
      steps: 15000,
      distanceMeters: 11200,
      runs: [{ distanceMiles: 5.0, durationMinutes: 48, durationSeconds: 48 * 60, paceMinPerMile: 9.6 }],
      otherExerciseCalories: 90,
    },
  ];
}

function runningAutoRows() {
  return buildRunningAutoCases().map((c) => {
    const app = appRunningCaloriesDuration({ ...c, durationSeconds: c.durationMinutes * 60 });
    const ref = refRunningCaloriesDuration({ ...c, durationSeconds: c.durationMinutes * 60 });
    return {
      id: c.id,
      input: c,
      app,
      ref,
      deltaKcal: app - ref,
      deltaPct: pctErr(app, ref),
    };
  });
}

function runningHealthKitRows() {
  return buildHealthKitCases().map((c) => {
    const durationMinutes = Math.max(Math.round(c.durationSeconds / 60), 1);
    const app = appRunningCaloriesDuration({
      durationMinutes,
      durationSeconds: c.durationSeconds,
      paceMinPerMile: c.paceMinPerMile,
      distanceMiles: c.distanceMiles,
      weightLb: c.weightLb,
    });
    const ref = refRunningCaloriesDuration({
      durationMinutes,
      durationSeconds: c.durationSeconds,
      paceMinPerMile: c.paceMinPerMile,
      distanceMiles: c.distanceMiles,
      weightLb: c.weightLb,
    });
    return {
      id: c.id,
      input: { ...c, durationMinutes },
      app,
      ref,
      deltaKcal: app - ref,
      deltaPct: pctErr(app, ref),
    };
  });
}

function walkingBorrowRows() {
  return buildWalkingBorrowCases().map((c) => {
    const app = c.distanceMiles
      ? appWalkingBorrowDistance(c.distanceMiles, c.weightLb)
      : appWalkingBorrowDuration({
          durationMinutes: c.durationMinutes,
          durationSeconds: c.durationMinutes * 60,
          paceMinPerMile: c.paceMinPerMile,
          weightLb: c.weightLb,
        });
    const ref = c.distanceMiles
      ? refWalkingBorrowDistance(c.distanceMiles, c.weightLb)
      : refWalkingBorrowDuration({
          durationMinutes: c.durationMinutes,
          durationSeconds: c.durationMinutes * 60,
          paceMinPerMile: c.paceMinPerMile,
          weightLb: c.weightLb,
        });
    return {
      id: c.id,
      input: c,
      app,
      ref,
      deltaKcal: app - ref,
      deltaPct: pctErr(app, ref),
    };
  });
}

function stepRows() {
  return buildStepCases().map((c) => {
    const app = appStepCalories(c);
    const ref = refStepCalories(c);
    return {
      id: c.id,
      input: c,
      app,
      ref,
      deltaKcal: app - ref,
      deltaPct: pctErr(app, ref),
    };
  });
}

function tdeeRows() {
  return buildTDEECases().map((c) => {
    const app = appTDEE(c);
    const ref = refTDEE(c);
    return {
      id: c.id,
      input: c,
      app,
      ref,
      deltaKcal: app.burnedBaseline - ref.burnedBaseline,
      deltaPct: pctErr(app.burnedBaseline, ref.burnedBaseline),
    };
  });
}

function printSummarySection(lines, title, rows) {
  const summary = summarizeRows(rows);
  lines.push(title);
  lines.push(`  Cases: ${summary.count}`);
  lines.push(`  MAE: ${summary.maeKcal.toFixed(1)} kcal`);
  lines.push(`  MAPE: ${summary.mapePct.toFixed(1)}% (${grade(summary)})`);
  lines.push(`  Bias range: ${summary.minPct.toFixed(1)}% to +${summary.maxPct.toFixed(1)}%`);
  lines.push(`  Worst case: ${summary.worst.id} (app=${summary.worst.app}, ref=${summary.worst.ref}, err=${summary.worst.deltaKcal} kcal, ${summary.worst.deltaPct.toFixed(1)}%)`);
  lines.push('');
  return summary;
}

function printRowDetails(lines, heading, rows, valueKey = null) {
  lines.push(heading);
  rows.forEach((r) => {
    lines.push(`  ${r.id}`);
    lines.push(`    input: ${JSON.stringify(r.input)}`);
    if (valueKey) {
      lines.push(`    app_${valueKey}: ${r.app[valueKey]}`);
      lines.push(`    ref_${valueKey}: ${r.ref[valueKey]}`);
    } else {
      lines.push(`    app: ${r.app}`);
      lines.push(`    ref: ${r.ref}`);
    }
    lines.push(`    deltaKcal: ${r.deltaKcal}`);
    lines.push(`    deltaPct: ${r.deltaPct.toFixed(2)}%`);
  });
  lines.push('');
}

function run() {
  const runningAuto = runningAutoRows();
  const runningHK = runningHealthKitRows();
  const walking = walkingBorrowRows();
  const steps = stepRows();
  const tdee = tdeeRows();

  const lines = [];
  lines.push('Energy Accuracy Audit');
  lines.push(`Generated: ${new Date().toISOString()}`);
  lines.push('');
  lines.push('Reference assumptions: running 1.00 kcal/kg/km net, walking 0.50 kcal/kg/km net, BMR = Mifflin-St Jeor.');
  lines.push('App assumptions under test: walking 0.55 kcal/kg/km net, running distance 1.00 kcal/kg/km net.');
  lines.push('');

  const s1 = printSummarySection(lines, '1) Running calories (manual/auto path)', runningAuto);
  const s2 = printSummarySection(lines, '2) Running calories (HealthKit import path)', runningHK);
  const s3 = printSummarySection(lines, '3) Walking-equivalent borrowed from steps', walking);
  const s4 = printSummarySection(lines, '4) Step calories', steps);
  const s5 = printSummarySection(lines, '5) Daily burned/TDEE baseline (BMR + activity + exercise)', tdee.map((r) => ({ ...r, app: r.app.burnedBaseline, ref: r.ref.burnedBaseline })));

  const pass = s1.mapePct <= 10 && s2.mapePct <= 10 && s3.mapePct <= 15 && s4.mapePct <= 15 && s5.mapePct <= 10;
  lines.push(`Overall gate: ${pass ? 'PASS' : 'FAIL'}`);
  lines.push('');

  lines.push('--- Detailed Inputs/Outputs ---');
  lines.push('');
  printRowDetails(lines, 'Category 1 details: Running calories (manual/auto)', runningAuto);
  printRowDetails(lines, 'Category 2 details: Running calories (HealthKit path)', runningHK);
  printRowDetails(lines, 'Category 3 details: Walking-equivalent borrowed', walking);
  printRowDetails(lines, 'Category 4 details: Step calories', steps);

  lines.push('Category 5 details: TDEE baseline');
  tdee.forEach((r) => {
    lines.push(`  ${r.id}`);
    lines.push(`    input: ${JSON.stringify(r.input)}`);
    lines.push(`    app_components: ${JSON.stringify(r.app)}`);
    lines.push(`    ref_components: ${JSON.stringify(r.ref)}`);
    lines.push(`    app_burnedBaseline: ${r.app.burnedBaseline}`);
    lines.push(`    ref_burnedBaseline: ${r.ref.burnedBaseline}`);
    lines.push(`    deltaKcal: ${r.deltaKcal}`);
    lines.push(`    deltaPct: ${r.deltaPct.toFixed(2)}%`);
  });
  lines.push('');

  const text = lines.join('\n');

  const outputDir = path.resolve(process.cwd(), 'output');
  if (!fs.existsSync(outputDir)) fs.mkdirSync(outputDir, { recursive: true });
  const outFile = path.join(outputDir, 'energy_accuracy_audit_report.txt');
  fs.writeFileSync(outFile, text, 'utf8');

  console.log(text);
  console.log(`Report written: ${outFile}`);

  if (!pass) process.exitCode = 1;
}

run();
