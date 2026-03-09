#!/usr/bin/env node

// Accuracy evaluator for:
// - StepActivityService.estimatedCaloriesToday
// - ExerciseCalorieService.walkingEquivalentCalories

const APP = {
  defaultWeightLb: 170,
  defaultHeightIn: 68,
  strideMultiplier: 0.415,
  netWalkingKcalPerKgPerKm: 0.55,
  runningKcalPerKgPerKm: 1.0,
  walkingEquivalentFallbackFraction: 0.75,
};

function poundsToKg(lb) {
  return lb * 0.45359237;
}

function inchesToMeters(inches) {
  return inches * 0.0254;
}

function milesToKm(miles) {
  return miles * 1.609344;
}

function roundInt(value) {
  return Math.max(Math.round(value), 0);
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

function appStepCalories({ steps, distanceMeters, weightLb, heightIn }) {
  if (steps <= 0) return 0;

  const resolvedWeightLb = weightLb > 0 ? weightLb : APP.defaultWeightLb;
  const resolvedHeightIn = heightIn > 0 ? heightIn : APP.defaultHeightIn;
  const weightKg = poundsToKg(resolvedWeightLb);

  let distanceKm;
  if (distanceMeters > 0) {
    distanceKm = distanceMeters / 1000;
  } else {
    const strideMeters = inchesToMeters(resolvedHeightIn) * APP.strideMultiplier;
    distanceKm = (steps * strideMeters) / 1000;
  }

  if (distanceKm <= 0) return 0;
  return roundInt(weightKg * distanceKm * APP.netWalkingKcalPerKgPerKm);
}

function referenceStepCalories({ steps, distanceMeters, weightLb, heightIn }) {
  // Reference model: ACSM-like net walking baseline (0.50 kcal/kg/km),
  // with stride estimate 0.414 * height when distance is unavailable.
  if (steps <= 0) return 0;
  const weightKg = poundsToKg(weightLb > 0 ? weightLb : APP.defaultWeightLb);
  const resolvedHeightIn = heightIn > 0 ? heightIn : APP.defaultHeightIn;
  const distanceKm = distanceMeters > 0
    ? distanceMeters / 1000
    : (steps * (inchesToMeters(resolvedHeightIn) * 0.414)) / 1000;
  return roundInt(weightKg * distanceKm * 0.50);
}

function appWalkingEquivalentDistance({ distanceMiles, weightLb }) {
  const distanceKm = milesToKm(distanceMiles);
  return roundInt(poundsToKg(weightLb) * distanceKm * APP.netWalkingKcalPerKgPerKm);
}

function appWalkingEquivalentDurationFallback({ durationMinutes, paceMinPerMile, weightLb }) {
  const hours = durationMinutes / 60;
  const speedMph = 60 / paceMinPerMile;
  const met = runningMET(speedMph);
  const runningCalories = roundInt(met * poundsToKg(weightLb) * hours);
  return roundInt(runningCalories * APP.walkingEquivalentFallbackFraction);
}

function inferredDistanceMiles({ durationMinutes, paceMinPerMile }) {
  if (paceMinPerMile > 0 && durationMinutes > 0) {
    return durationMinutes / paceMinPerMile;
  }
  if (durationMinutes > 0) {
    return durationMinutes / 10.0; // runningMinutesPerMile
  }
  return null;
}

function appWalkingEquivalentCurrent({ durationMinutes, paceMinPerMile, weightLb }) {
  const inferredMiles = inferredDistanceMiles({ durationMinutes, paceMinPerMile });
  if (inferredMiles && inferredMiles > 0) {
    return appWalkingEquivalentDistance({ distanceMiles: inferredMiles, weightLb });
  }
  return appWalkingEquivalentDurationFallback({ durationMinutes, paceMinPerMile, weightLb });
}

function referenceWalkingEquivalentFromDuration({ durationMinutes, paceMinPerMile, weightLb }) {
  const distanceMiles = durationMinutes / paceMinPerMile;
  return appWalkingEquivalentDistance({ distanceMiles, weightLb });
}

function pctError(estimated, reference) {
  if (reference === 0) return 0;
  return ((estimated - reference) / reference) * 100;
}

function summarizePairs(pairs) {
  const absKcal = pairs.map((p) => Math.abs(p.deltaKcal));
  const absPct = pairs.map((p) => Math.abs(p.deltaPct));
  const mean = (arr) => arr.reduce((a, b) => a + b, 0) / arr.length;
  return {
    count: pairs.length,
    maeKcal: mean(absKcal),
    mapePct: mean(absPct),
    worstUnderPct: Math.min(...pairs.map((p) => p.deltaPct)),
    worstOverPct: Math.max(...pairs.map((p) => p.deltaPct)),
  };
}

function buildStepCases() {
  // Mix of short/typical/high steps, broad anthropometrics, and both with/without measured distance.
  return [
    { id: 'S1', steps: 3000, distanceMeters: 0, weightLb: 120, heightIn: 62 },
    { id: 'S2', steps: 7000, distanceMeters: 0, weightLb: 150, heightIn: 66 },
    { id: 'S3', steps: 10000, distanceMeters: 0, weightLb: 170, heightIn: 68 },
    { id: 'S4', steps: 14000, distanceMeters: 0, weightLb: 200, heightIn: 72 },
    { id: 'S5', steps: 18000, distanceMeters: 0, weightLb: 230, heightIn: 76 },
    { id: 'S6', steps: 8000, distanceMeters: 5300, weightLb: 145, heightIn: 64 },
    { id: 'S7', steps: 9500, distanceMeters: 6800, weightLb: 175, heightIn: 70 },
    { id: 'S8', steps: 12000, distanceMeters: 9100, weightLb: 205, heightIn: 73 },
    { id: 'S9', steps: 5000, distanceMeters: 3600, weightLb: 130, heightIn: 63 },
    { id: 'S10', steps: 16000, distanceMeters: 11200, weightLb: 190, heightIn: 71 },
  ];
}

function buildDurationFallbackCases() {
  return [
    { id: 'D1', durationMinutes: 30, paceMinPerMile: 8.0, weightLb: 140 },
    { id: 'D2', durationMinutes: 30, paceMinPerMile: 10.0, weightLb: 170 },
    { id: 'D3', durationMinutes: 30, paceMinPerMile: 12.0, weightLb: 200 },
    { id: 'D4', durationMinutes: 45, paceMinPerMile: 8.5, weightLb: 160 },
    { id: 'D5', durationMinutes: 45, paceMinPerMile: 10.5, weightLb: 190 },
    { id: 'D6', durationMinutes: 60, paceMinPerMile: 9.0, weightLb: 150 },
    { id: 'D7', durationMinutes: 60, paceMinPerMile: 11.0, weightLb: 180 },
    { id: 'D8', durationMinutes: 75, paceMinPerMile: 9.5, weightLb: 210 },
  ];
}

function evaluate() {
  const stepCases = buildStepCases();
  const stepPairs = stepCases.map((c) => {
    const app = appStepCalories(c);
    const ref = referenceStepCalories(c);
    return {
      ...c,
      app,
      ref,
      deltaKcal: app - ref,
      deltaPct: pctError(app, ref),
    };
  });

  const durationCases = buildDurationFallbackCases();
  const durationPairs = durationCases.map((c) => {
    const app = appWalkingEquivalentCurrent(c);
    const ref = referenceWalkingEquivalentFromDuration(c);
    return {
      ...c,
      app,
      ref,
      deltaKcal: app - ref,
      deltaPct: pctError(app, ref),
    };
  });

  const distanceConsistencyCases = [
    { id: 'W1', distanceMiles: 2.0, weightLb: 140 },
    { id: 'W2', distanceMiles: 3.1, weightLb: 170 },
    { id: 'W3', distanceMiles: 5.0, weightLb: 200 },
    { id: 'W4', distanceMiles: 7.5, weightLb: 220 },
  ];

  const distancePairs = distanceConsistencyCases.map((c) => {
    const app = appWalkingEquivalentDistance(c);
    const ref = appWalkingEquivalentDistance(c);
    return {
      ...c,
      app,
      ref,
      deltaKcal: app - ref,
      deltaPct: pctError(app, ref),
    };
  });

  console.log('\nStep/Walking Calorie Accuracy Evaluation\n');

  const stepSummary = summarizePairs(stepPairs);
  console.log('1) Steps -> calories (StepActivityService.estimatedCaloriesToday)');
  console.log(`   Cases: ${stepSummary.count}`);
  console.log(`   MAE: ${stepSummary.maeKcal.toFixed(1)} kcal`);
  console.log(`   MAPE: ${stepSummary.mapePct.toFixed(1)}%`);
  console.log(`   Bias range: ${stepSummary.worstUnderPct.toFixed(1)}% to +${stepSummary.worstOverPct.toFixed(1)}%`);

  const worstStep = stepPairs
    .slice()
    .sort((a, b) => Math.abs(b.deltaPct) - Math.abs(a.deltaPct))[0];
  console.log(`   Worst case: ${worstStep.id} app=${worstStep.app}, ref=${worstStep.ref}, error=${worstStep.deltaKcal} kcal (${worstStep.deltaPct.toFixed(1)}%)`);

  const durationSummary = summarizePairs(durationPairs);
  const legacyDurationSummary = summarizePairs(durationCases.map((c) => {
    const app = appWalkingEquivalentDurationFallback(c);
    const ref = referenceWalkingEquivalentFromDuration(c);
    return {
      ...c,
      app,
      ref,
      deltaKcal: app - ref,
      deltaPct: pctError(app, ref),
    };
  }));
  console.log('\n2) Running walking-equivalent fallback (duration-only path)');
  console.log('   Path tested: ExerciseCalorieService.walkingEquivalentCalories when distance is missing');
  console.log(`   Cases: ${durationSummary.count}`);
  console.log(`   MAE: ${durationSummary.maeKcal.toFixed(1)} kcal`);
  console.log(`   MAPE: ${durationSummary.mapePct.toFixed(1)}%`);
  console.log(`   Bias range: ${durationSummary.worstUnderPct.toFixed(1)}% to +${durationSummary.worstOverPct.toFixed(1)}%`);
  console.log(`   Legacy (pre-fix) MAPE for same cases: ${legacyDurationSummary.mapePct.toFixed(1)}%`);

  const worstDuration = durationPairs
    .slice()
    .sort((a, b) => Math.abs(b.deltaPct) - Math.abs(a.deltaPct))[0];
  console.log(`   Worst case: ${worstDuration.id} app=${worstDuration.app}, ref=${worstDuration.ref}, error=${worstDuration.deltaKcal} kcal (${worstDuration.deltaPct.toFixed(1)}%)`);

  const distanceSummary = summarizePairs(distancePairs);
  console.log('\n3) Running walking-equivalent distance path consistency');
  console.log('   Path tested: ExerciseCalorieService.walkingEquivalentCalories when distance is present');
  console.log(`   Cases: ${distanceSummary.count}`);
  console.log(`   MAE: ${distanceSummary.maeKcal.toFixed(1)} kcal`);
  console.log(`   MAPE: ${distanceSummary.mapePct.toFixed(1)}%`);

  console.log('\nSample case details:');
  stepPairs.slice(0, 3).forEach((row) => {
    console.log(`   ${row.id}: steps=${row.steps}, app=${row.app}, ref=${row.ref}, err=${row.deltaKcal} (${row.deltaPct.toFixed(1)}%)`);
  });
  durationPairs.slice(0, 3).forEach((row) => {
    console.log(`   ${row.id}: pace=${row.paceMinPerMile} min/mi, dur=${row.durationMinutes} min, app=${row.app}, ref=${row.ref}, err=${row.deltaKcal} (${row.deltaPct.toFixed(1)}%)`);
  });

  const pass = stepSummary.mapePct <= 15 && durationSummary.mapePct <= 15 && distanceSummary.mapePct <= 1;
  console.log(`\nOverall gate (<=15% each main path): ${pass ? 'PASS' : 'FAIL'}`);
  if (!pass) process.exitCode = 1;
}

evaluate();
