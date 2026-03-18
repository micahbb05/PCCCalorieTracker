#!/usr/bin/env node

const CALIBRATION_ERROR_WEIGHTS = [0.1, 0.2, 0.3, 0.4];
const MINIMUM_WEEKLY_WEIGH_INS = 3;

function clamp(value, lower, upper) {
  return Math.min(Math.max(value, lower), upper);
}

function average(values) {
  if (!values.length) return null;
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function weightedErrorMean(values) {
  if (!values.length) return 0;
  const trimmed = values.slice(-CALIBRATION_ERROR_WEIGHTS.length);
  const weights = CALIBRATION_ERROR_WEIGHTS.slice(CALIBRATION_ERROR_WEIGHTS.length - trimmed.length);
  const weightedSum = trimmed.reduce((sum, value, idx) => sum + value * weights[idx], 0);
  const totalWeight = weights.reduce((sum, value) => sum + value, 0);
  return totalWeight > 0 ? weightedSum / totalWeight : 0;
}

function spikeExcludedIndices(priorWeights, currentWeights) {
  const combined = priorWeights.concat(currentWeights);
  const excluded = new Set();
  for (let i = 1; i < combined.length; i += 1) {
    const previous = combined[i - 1];
    const current = combined[i];
    if (previous == null || current == null) continue;
    if (Math.abs(current - previous) > 4.0) {
      excluded.add(i);
    }
  }
  return {
    prior: new Set([...excluded].filter((idx) => idx < 7)),
    current: new Set([...excluded].filter((idx) => idx >= 7).map((idx) => idx - 7)),
  };
}

function calibrationConfidence(state) {
  const checks = Math.max(state.dataQualityChecks, 1);
  const passRate = state.dataQualityPasses / checks;
  const recent = state.recentDailyErrors.slice(-4);
  if (!recent.length) return "Low";
  const mean = average(recent);
  const variance = recent.reduce((sum, value) => {
    const delta = value - mean;
    return sum + (delta * delta);
  }, 0) / recent.length;
  const stdDev = Math.sqrt(variance);

  if (passRate >= 0.8 && stdDev <= 20 && recent.length >= 3) return "High";
  if (passRate >= 0.5 && stdDev <= 40) return "Medium";
  return "Low";
}

function calibrationAdjustmentParameters(recentErrors, isFastStart) {
  const defaults = {
    errorClamp: 100,
    alpha: isFastStart ? 0.5 : 0.2,
    maxStep: isFastStart ? 60 : 40,
    offsetLimit: 300,
  };

  const trailing = recentErrors.slice(-3);
  if (trailing.length !== 3) return defaults;

  const signs = trailing.map((value) => (value > 0 ? 1 : (value < 0 ? -1 : 0)));
  const firstSign = signs[0];
  if (firstSign === 0 || !signs.every((sign) => sign === firstSign)) return defaults;

  const absErrors = trailing.map((value) => Math.abs(value));
  if (!absErrors.every((value) => value >= 250)) return defaults;

  const meanAbs = average(absErrors);
  const intensity = clamp(((meanAbs - 250) / 600) + 1, 1, 2);

  return {
    errorClamp: 100 * intensity,
    alpha: (isFastStart ? 0.5 : 0.2) + (isFastStart ? 0.1 : 0.15) * (intensity - 1),
    maxStep: (isFastStart ? 60 : 40) * intensity,
    offsetLimit: 300 + (300 * (intensity - 1)),
  };
}

function evaluateWeek(state, week) {
  const result = {
    status: "applied",
    skipReason: null,
    predictedDeltaKcal: null,
    actualDeltaKcal: null,
    dailyError: null,
    smoothedDailyError: null,
    offsetStep: 0,
    offsetBefore: state.calibrationOffsetCalories,
    offsetAfter: state.calibrationOffsetCalories,
    isFastStart: state.appliedWeekCount < 3,
    confidenceBefore: calibrationConfidence(state),
  };

  const { prior: excludedPrior, current: excludedCurrent } = spikeExcludedIndices(week.priorWeights, week.currentWeights);
  const validPrior = week.priorWeights.filter((value, idx) => value != null && !excludedPrior.has(idx));
  const validCurrent = week.currentWeights.filter((value, idx) => value != null && !excludedCurrent.has(idx));

  if (validPrior.length < MINIMUM_WEEKLY_WEIGH_INS) {
    result.status = "skipped";
    result.skipReason = `Need at least ${MINIMUM_WEEKLY_WEIGH_INS} valid Health weigh-ins in the prior week.`;
  }
  if (result.status === "applied" && validCurrent.length < MINIMUM_WEEKLY_WEIGH_INS) {
    result.status = "skipped";
    result.skipReason = `Need at least ${MINIMUM_WEEKLY_WEIGH_INS} valid Health weigh-ins in the current week.`;
  }

  const intakeLoggedDays = week.intakeByDay.filter((value) => value > 0).length;
  const intakeCompleteness = intakeLoggedDays / 7.0;
  if (result.status === "applied" && intakeCompleteness < 0.85) {
    result.status = "skipped";
    result.skipReason = "Intake logging is below 85% for the week.";
  }

  const missingBurnDays = week.burnBaselineByDay.filter((value) => value == null).length;
  if (result.status === "applied" && missingBurnDays > 2) {
    result.status = "skipped";
    result.skipReason = "Burn baseline is missing for too many days this week.";
  }

  const wPrev = average(validPrior);
  const wCurr = average(validCurrent);
  if (result.status === "applied") {
    const jumpLimit = Math.max(wPrev * 0.025, 0.01);
    if (Math.abs(wCurr - wPrev) > jumpLimit) {
      result.status = "skipped";
      result.skipReason = "Week-over-week average weight jump exceeded 2.5%.";
    }
  }

  if (result.status === "skipped") {
    state.lastRunStatus = "skipped";
    state.lastSkipReason = result.skipReason;
    state.dataQualityChecks += 1;
    result.offsetAfter = state.calibrationOffsetCalories;
    result.confidenceAfter = calibrationConfidence(state);
    return result;
  }

  const availableBurns = week.burnBaselineByDay.filter((value) => value != null);
  const fallbackBurn = availableBurns.length ? Math.max(Math.round(average(availableBurns)), 1) : 1800;

  const predictedDeltaKcal = week.intakeByDay.reduce((sum, intake, idx) => {
    const burned = week.burnBaselineByDay[idx] != null ? week.burnBaselineByDay[idx] : fallbackBurn;
    return sum + (intake - burned);
  }, 0);
  const actualDeltaKcal = (wCurr - wPrev) * 3500.0;
  const dailyError = (actualDeltaKcal - predictedDeltaKcal) / 7.0;

  let recentErrors = state.recentDailyErrors.concat([dailyError]);
  if (recentErrors.length > 4) {
    recentErrors = recentErrors.slice(-4);
  }

  const isFastStart = state.appliedWeekCount < 3;
  const adjustment = calibrationAdjustmentParameters(recentErrors, isFastStart);
  const boundedSmoothedError = clamp(
    weightedErrorMean(recentErrors),
    -adjustment.errorClamp,
    adjustment.errorClamp,
  );
  const offsetStep = clamp(
    (-boundedSmoothedError) * adjustment.alpha,
    -adjustment.maxStep,
    adjustment.maxStep,
  );
  const newOffset = Math.round(clamp(
    state.calibrationOffsetCalories + offsetStep,
    -adjustment.offsetLimit,
    adjustment.offsetLimit,
  ));

  state.calibrationOffsetCalories = newOffset;
  state.recentDailyErrors = recentErrors;
  state.appliedWeekCount += 1;
  state.lastRunStatus = "applied";
  state.lastSkipReason = null;
  state.dataQualityChecks += 1;
  state.dataQualityPasses += 1;

  result.predictedDeltaKcal = predictedDeltaKcal;
  result.actualDeltaKcal = actualDeltaKcal;
  result.dailyError = dailyError;
  result.smoothedDailyError = boundedSmoothedError;
  result.offsetStep = offsetStep;
  result.offsetAfter = newOffset;
  result.isFastStart = isFastStart;
  result.confidenceAfter = calibrationConfidence(state);
  return result;
}

function makeWeek({ priorWeights, currentWeights, intakePerDay, burnPerDay, intakeByDay, burnBaselineByDay }) {
  return {
    priorWeights,
    currentWeights,
    intakeByDay: intakeByDay || Array(7).fill(intakePerDay),
    burnBaselineByDay: burnBaselineByDay || Array(7).fill(burnPerDay),
  };
}

function makeState() {
  return {
    calibrationOffsetCalories: 0,
    recentDailyErrors: [],
    appliedWeekCount: 0,
    lastRunStatus: "never",
    lastSkipReason: null,
    dataQualityPasses: 0,
    dataQualityChecks: 0,
  };
}

const scenarios = [
  {
    name: "deficit-on-target",
    expectation: "Offset should stay near 0 when prediction matches scale trend.",
    weeks: [makeWeek({
      priorWeights: [200.4, 200.1, 199.9, 200.3, 199.8, 200.0, 199.5],
      currentWeights: [199.4, 199.1, 198.9, 199.3, 198.8, 199.0, 198.5],
      intakePerDay: 2000,
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "applied" && Math.abs(runs[0].offsetAfter) <= 1,
  },
  {
    name: "surplus-on-target",
    expectation: "Offset should stay near 0 when surplus and gain align.",
    weeks: [makeWeek({
      priorWeights: [180.2, 180.1, 180.0, 179.9, 180.3, 180.0, 179.8],
      currentWeights: [180.8, 180.7, 180.6, 180.5, 180.9, 180.6, 180.4],
      intakePerDay: 2800,
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "applied" && Math.abs(runs[0].offsetAfter) <= 1,
  },
  {
    name: "surplus-but-losing-weight",
    expectation: "Offset should move positive and adapt faster under persistent mismatch.",
    weeks: Array.from({ length: 8 }, () => makeWeek({
      priorWeights: [200.4, 200.1, 199.9, 200.3, 199.8, 200.0, 199.5],
      currentWeights: [198.8, 198.7, 198.4, 198.6, 198.2, 198.5, 198.3],
      intakePerDay: 2800,
      burnPerDay: 2500,
    })),
    assert: (runs) => runs.every((run) => run.status === "applied") && runs.at(-1).offsetAfter >= 500,
  },
  {
    name: "deficit-goal-but-eating-surplus-and-losing",
    expectation: "Goal type does not alter calibration math.",
    weeks: [makeWeek({
      priorWeights: [210.2, 210.1, 210.0, 209.9, 210.3, 210.0, 209.8],
      currentWeights: [208.7, 208.6, 208.5, 208.4, 208.8, 208.5, 208.3],
      intakePerDay: 2900,
      burnPerDay: 2600,
    })],
    assert: (runs) => runs[0].status === "applied" && runs[0].offsetAfter > 0,
  },
  {
    name: "deficit-but-gaining-weight",
    expectation: "Offset should move negative when actual trend is above prediction.",
    weeks: [makeWeek({
      priorWeights: [190.1, 190.0, 189.8, 190.2, 189.9, 190.0, 189.7],
      currentWeights: [190.6, 190.5, 190.4, 190.7, 190.5, 190.6, 190.3],
      intakePerDay: 2200,
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "applied" && runs[0].offsetAfter < 0,
  },
  {
    name: "incomplete-intake-logging",
    expectation: "Should skip when below 85% of days have intake logged.",
    weeks: [makeWeek({
      priorWeights: [180, 180.1, 180.2, 180.0, 179.9, 180.1, 180.0],
      currentWeights: [179.9, 180.0, 180.1, 179.8, 179.7, 179.9, 179.8],
      intakeByDay: [2500, 2400, 0, 0, 2500, 0, 2450],
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "skipped" && /below 85%/.test(runs[0].skipReason),
  },
  {
    name: "intake-logging-at-threshold",
    expectation: "Should pass at exactly 6/7 logged days (>=85%).",
    weeks: [makeWeek({
      priorWeights: [180, 180.1, 180.2, 180.0, 179.9, 180.1, 180.0],
      currentWeights: [179.9, 180.0, 180.1, 179.8, 179.7, 179.9, 179.8],
      intakeByDay: [2500, 2400, 2300, 2200, 2500, 0, 2450],
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "applied",
  },
  {
    name: "missing-burn-days",
    expectation: "Should skip when more than 2 burn baseline days are missing.",
    weeks: [makeWeek({
      priorWeights: [175, 175.1, 174.9, 175.0, 175.2, 175.1, 175.0],
      currentWeights: [174.8, 174.9, 174.7, 174.8, 174.9, 174.8, 174.7],
      intakePerDay: 2200,
      burnBaselineByDay: [2500, null, null, 2480, null, 2510, 2490],
    })],
    assert: (runs) => runs[0].status === "skipped" && /missing for too many days/.test(runs[0].skipReason),
  },
  {
    name: "missing-burn-days-at-threshold",
    expectation: "Should pass when exactly 2 burn baseline days are missing.",
    weeks: [makeWeek({
      priorWeights: [175, 175.1, 174.9, 175.0, 175.2, 175.1, 175.0],
      currentWeights: [174.8, 174.9, 174.7, 174.8, 174.9, 174.8, 174.7],
      intakePerDay: 2200,
      burnBaselineByDay: [2500, null, null, 2480, 2520, 2510, 2490],
    })],
    assert: (runs) => runs[0].status === "applied",
  },
  {
    name: "large-weekly-jump",
    expectation: "Should skip when week-average jump exceeds 2.5%.",
    weeks: [makeWeek({
      priorWeights: [200, 200, 200, 200, 200, 200, 200],
      currentWeights: [193, 193, 193, 193, 193, 193, 193],
      intakePerDay: 2400,
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "skipped" && /exceeded 2.5%/.test(runs[0].skipReason),
  },
  {
    name: "weekly-jump-at-threshold",
    expectation: "Should pass when week-average jump equals 2.5%.",
    weeks: [makeWeek({
      priorWeights: [200, 200, 200, 200, 200, 200, 200],
      currentWeights: [195, 195, 195, 195, 195, 195, 195],
      intakePerDay: 2500,
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "applied",
  },
  {
    name: "spike-filter-removes-too-many-weighins",
    expectation: "Should skip when spikes leave fewer than 3 valid current-week weigh-ins.",
    weeks: [makeWeek({
      priorWeights: [200, 200.2, 199.8, 200.1, 199.9, 200.0, 200.1],
      currentWeights: [194.0, 200.0, 194.0, 200.0, 194.0, 200.0, 194.0],
      intakePerDay: 2500,
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "skipped" && /current week/.test(runs[0].skipReason),
  },
  {
    name: "exact-4lb-change-not-spike",
    expectation: "A 4.0 lb day-to-day change should not be filtered as spike.",
    weeks: [makeWeek({
      priorWeights: [200, 200.1, 199.9, 200.0, 200.1, 199.9, 200.0],
      currentWeights: [200.0, 196.0, 196.1, 196.0, 196.1, 196.0, 196.1],
      intakePerDay: 2500,
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "applied",
  },
  {
    name: "confidence-can-look-high-with-large-constant-error",
    expectation: "Confidence can reach High even with large absolute error if error is stable.",
    weeks: Array.from({ length: 4 }, () => makeWeek({
      priorWeights: [200.4, 200.1, 199.9, 200.3, 199.8, 200.0, 199.5],
      currentWeights: [198.8, 198.7, 198.4, 198.6, 198.2, 198.5, 198.3],
      intakePerDay: 2800,
      burnPerDay: 2500,
    })),
    assert: (runs) => runs[2].confidenceAfter === "High" && Math.abs(runs[2].dailyError) > 500,
  },
  {
    name: "alternating-large-error-does-not-escalate-range",
    expectation: "Adaptive expansion requires persistent same-sign error, not oscillation.",
    weeks: [
      makeWeek({ priorWeights: [200, 200, 200, 200, 200, 200, 200], currentWeights: [198.4, 198.4, 198.4, 198.4, 198.4, 198.4, 198.4], intakePerDay: 2800, burnPerDay: 2500 }),
      makeWeek({ priorWeights: [198.4, 198.4, 198.4, 198.4, 198.4, 198.4, 198.4], currentWeights: [200.0, 200.0, 200.0, 200.0, 200.0, 200.0, 200.0], intakePerDay: 2800, burnPerDay: 2500 }),
      makeWeek({ priorWeights: [200.0, 200.0, 200.0, 200.0, 200.0, 200.0, 200.0], currentWeights: [198.4, 198.4, 198.4, 198.4, 198.4, 198.4, 198.4], intakePerDay: 2800, burnPerDay: 2500 }),
    ],
    assert: (runs) => runs.every((run) => run.status === "applied")
      && runs.every((run) => Math.abs(run.offsetStep) <= 60)
      && Math.abs(runs.at(-1).offsetAfter) <= 180,
  },
  {
    name: "mild-persistent-error-does-not-escalate",
    expectation: "Persistent errors under 250 cal/day should not trigger adaptive expansion.",
    weeks: Array.from({ length: 14 }, () => makeWeek({
      priorWeights: [200.2, 200.2, 200.1, 200.1, 200.1, 200.2, 200.1],
      currentWeights: [200.0, 200.0, 199.9, 199.9, 199.9, 200.0, 199.9],
      intakePerDay: 2550,
      burnPerDay: 2500,
    })),
    assert: (runs) => runs.every((run) => run.status === "applied") && Math.abs(runs.at(-1).offsetAfter) <= 300,
  },
  {
    name: "persistent-large-negative-error-can-reach-expanded-cap",
    expectation: "Persistent opposite-sign large errors should also expand negative cap.",
    weeks: Array.from({ length: 16 }, () => makeWeek({
      priorWeights: [198.8, 198.7, 198.6, 198.8, 198.7, 198.6, 198.7],
      currentWeights: [200.3, 200.2, 200.1, 200.3, 200.2, 200.1, 200.2],
      intakePerDay: 2200,
      burnPerDay: 2500,
    })),
    assert: (runs) => runs.every((run) => run.status === "applied")
      && runs.at(-1).offsetAfter <= -550
      && runs.at(-1).offsetAfter >= -600,
  },
  {
    name: "persistent-large-error-can-reach-expanded-cap",
    expectation: "Persistent same-sign large errors can move cap beyond +/-300.",
    weeks: Array.from({ length: 16 }, () => makeWeek({
      priorWeights: [200.4, 200.1, 199.9, 200.3, 199.8, 200.0, 199.5],
      currentWeights: [198.8, 198.7, 198.4, 198.6, 198.2, 198.5, 198.3],
      intakePerDay: 2800,
      burnPerDay: 2500,
    })),
    assert: (runs) => runs.every((run) => run.status === "applied")
      && runs.at(-1).offsetAfter >= 550
      && runs.at(-1).offsetAfter <= 600,
  },
  {
    name: "reversal-after-persistent-error",
    expectation: "Offset should reverse after persistent error sign flips.",
    weeks: [
      ...Array.from({ length: 8 }, () => makeWeek({
        priorWeights: [200.4, 200.1, 199.9, 200.3, 199.8, 200.0, 199.5],
        currentWeights: [198.8, 198.7, 198.4, 198.6, 198.2, 198.5, 198.3],
        intakePerDay: 2800,
        burnPerDay: 2500,
      })),
      ...Array.from({ length: 8 }, () => makeWeek({
        priorWeights: [198.8, 198.7, 198.4, 198.6, 198.2, 198.5, 198.3],
        currentWeights: [200.3, 200.2, 199.9, 200.1, 199.7, 200.0, 199.8],
        intakePerDay: 2800,
        burnPerDay: 2500,
      })),
    ],
    assert: (runs) => runs.every((run) => run.status === "applied")
      && runs[7].offsetAfter > 0
      && runs.at(-1).offsetAfter < runs[7].offsetAfter,
  },
  {
    name: "prior-week-weighins-below-minimum",
    expectation: "Should skip when prior week has fewer than 3 valid values.",
    weeks: [makeWeek({
      priorWeights: [200, null, 200, null, null, null, null],
      currentWeights: [199.7, 199.6, 199.5, 199.6, 199.5, 199.4, 199.5],
      intakePerDay: 2300,
      burnPerDay: 2500,
    })],
    assert: (runs) => runs[0].status === "skipped" && /prior week/.test(runs[0].skipReason),
  },
  {
    name: "noise-robustness-small-random-error",
    expectation: "Small noisy trends should keep offset bounded.",
    weeks: [
      makeWeek({ priorWeights: [200.0, 200.2, 199.9, 200.1, 200.0, 200.1, 200.0], currentWeights: [199.9, 200.1, 199.8, 200.0, 199.9, 200.0, 199.9], intakePerDay: 2500, burnPerDay: 2500 }),
      makeWeek({ priorWeights: [199.9, 200.1, 199.8, 200.0, 199.9, 200.0, 199.9], currentWeights: [200.0, 200.2, 199.9, 200.1, 200.0, 200.1, 200.0], intakePerDay: 2500, burnPerDay: 2500 }),
      makeWeek({ priorWeights: [200.0, 200.2, 199.9, 200.1, 200.0, 200.1, 200.0], currentWeights: [199.8, 200.0, 199.7, 199.9, 199.8, 199.9, 199.8], intakePerDay: 2500, burnPerDay: 2500 }),
      makeWeek({ priorWeights: [199.8, 200.0, 199.7, 199.9, 199.8, 199.9, 199.8], currentWeights: [199.9, 200.1, 199.8, 200.0, 199.9, 200.0, 199.9], intakePerDay: 2500, burnPerDay: 2500 }),
      makeWeek({ priorWeights: [199.9, 200.1, 199.8, 200.0, 199.9, 200.0, 199.9], currentWeights: [199.8, 200.0, 199.7, 199.9, 199.8, 199.9, 199.8], intakePerDay: 2500, burnPerDay: 2500 }),
      makeWeek({ priorWeights: [199.8, 200.0, 199.7, 199.9, 199.8, 199.9, 199.8], currentWeights: [199.9, 200.1, 199.8, 200.0, 199.9, 200.0, 199.9], intakePerDay: 2500, burnPerDay: 2500 }),
      makeWeek({ priorWeights: [199.9, 200.1, 199.8, 200.0, 199.9, 200.0, 199.9], currentWeights: [200.0, 200.2, 199.9, 200.1, 200.0, 200.1, 200.0], intakePerDay: 2500, burnPerDay: 2500 }),
      makeWeek({ priorWeights: [200.0, 200.2, 199.9, 200.1, 200.0, 200.1, 200.0], currentWeights: [199.9, 200.1, 199.8, 200.0, 199.9, 200.0, 199.9], intakePerDay: 2500, burnPerDay: 2500 }),
    ],
    assert: (runs) => runs.every((run) => run.status === "applied") && Math.abs(runs.at(-1).offsetAfter) <= 80,
  },
];

function formatNumber(value) {
  if (value == null) return "--";
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function runAll() {
  let passed = 0;
  let failed = 0;

  console.log("Calibration scenario tests\\n");

  scenarios.forEach((scenario, index) => {
    const state = makeState();
    const runs = scenario.weeks.map((week) => evaluateWeek(state, week));
    const ok = scenario.assert(runs);

    if (ok) {
      passed += 1;
    } else {
      failed += 1;
    }

    const latest = runs.at(-1);
    const appliedRuns = runs.filter((run) => run.status === "applied");
    const meanAbsError = appliedRuns.length
      ? appliedRuns.reduce((sum, run) => sum + Math.abs(run.dailyError), 0) / appliedRuns.length
      : null;

    console.log(`${index + 1}. ${scenario.name} => ${ok ? "PASS" : "FAIL"}`);
    console.log(`   Expectation: ${scenario.expectation}`);
    console.log(`   Runs: ${runs.length}, applied: ${appliedRuns.length}, skipped: ${runs.length - appliedRuns.length}`);
    console.log(`   Final offset: ${formatNumber(latest.offsetAfter)} cal/day`);
    console.log(`   Final status: ${latest.status}${latest.skipReason ? ` (${latest.skipReason})` : ""}`);
    console.log(`   Last dailyError: ${formatNumber(latest.dailyError)} cal/day`);
    console.log(`   Mean |dailyError| (applied): ${formatNumber(meanAbsError)} cal/day`);
    console.log(`   Final confidence: ${latest.confidenceAfter || calibrationConfidence(state)}`);

    if (scenario.name === "surplus-but-losing-weight") {
      const neededOffset = -latest.dailyError;
      const gap = neededOffset - latest.offsetAfter;
      console.log(`   Needed burn offset to fully reconcile: ${formatNumber(neededOffset)} cal/day`);
      console.log(`   Residual offset gap after ${runs.length} weeks: ${formatNumber(gap)} cal/day`);
    }

    console.log("");
  });

  console.log(`Summary: ${passed} passed, ${failed} failed, ${scenarios.length} total`);
  if (failed > 0) {
    process.exitCode = 1;
  }
}

runAll();
