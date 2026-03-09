#!/usr/bin/env node

const path = require('path');
const { readJson, writeJson } = require('./lib/common');

const ROOT = path.resolve(__dirname, '..', '..');

function loadIfExists(filePath) {
  try {
    return readJson(filePath);
  } catch {
    return null;
  }
}

function metric(obj, key, fallback = 0) {
  return obj && obj.metrics && typeof obj.metrics[key] === 'number' ? obj.metrics[key] : fallback;
}

function main() {
  const runId = process.env.STRESS_RUN_ID || 'adhoc';
  const tier = (process.env.STRESS_TIER || 'pr').toLowerCase();
  const outDir = path.join(ROOT, 'output', 'stress', runId);

  const thresholds = readJson(path.join(ROOT, 'scripts', 'stress', 'thresholds.json')).release_gate;

  const formula = loadIfExists(path.join(outDir, 'formula_data.json'));
  const api = loadIfExists(path.join(outDir, 'api_contract_load.json'));
  const ai = loadIfExists(path.join(outDir, 'ai_quality.json'));
  const ui = loadIfExists(path.join(outDir, 'ui_e2e.json'));
  const e2e = loadIfExists(path.join(outDir, 'e2e_scenarios.json'));
  const fixture = loadIfExists(path.join(outDir, 'fixture_validation.json'));

  const strictChecks = [
    {
      key: 'crash_free',
      passed: (ui?.metrics?.uiCriticalDeadEnds ?? 0) === 0,
      actual: ui?.metrics?.uiCriticalDeadEnds ?? null,
      threshold: thresholds.ui_critical_dead_ends_max,
    },
    {
      key: 'api_success_rate',
      passed: metric(api, 'apiSuccessRate') >= thresholds.api_success_rate_min,
      actual: metric(api, 'apiSuccessRate'),
      threshold: thresholds.api_success_rate_min,
    },
    {
      key: 'api_non_ai_p95_latency_ms',
      passed: metric(api, 'apiNonAiP95LatencyMs') <= thresholds.api_non_ai_p95_latency_ms_max,
      actual: metric(api, 'apiNonAiP95LatencyMs'),
      threshold: thresholds.api_non_ai_p95_latency_ms_max,
    },
    {
      key: 'api_ai_p95_latency_ms',
      passed: metric(api, 'apiAiP95LatencyMs') <= thresholds.api_ai_p95_latency_ms_max,
      actual: metric(api, 'apiAiP95LatencyMs'),
      threshold: thresholds.api_ai_p95_latency_ms_max,
    },
    {
      key: 'contract_validity',
      passed: metric(api, 'contractValidity') >= thresholds.contract_validity_min,
      actual: metric(api, 'contractValidity'),
      threshold: thresholds.contract_validity_min,
    },
    {
      key: 'ai_parse_validity',
      passed: metric(ai, 'aiParseValidity') >= thresholds.ai_parse_validity_min,
      actual: metric(ai, 'aiParseValidity'),
      threshold: thresholds.ai_parse_validity_min,
    },
    {
      key: 'ai_malformed_rate',
      passed: metric(ai, 'aiMalformedRate') <= thresholds.ai_malformed_rate_max,
      actual: metric(ai, 'aiMalformedRate'),
      threshold: thresholds.ai_malformed_rate_max,
    },
    {
      key: 'ai_text_mape',
      passed: metric(ai, 'aiTextMAPE') <= thresholds.ai_text_mape_max,
      actual: metric(ai, 'aiTextMAPE'),
      threshold: thresholds.ai_text_mape_max,
    },
    {
      key: 'ai_image_mape',
      passed: metric(ai, 'aiImageMAPE') <= thresholds.ai_image_mape_max,
      actual: metric(ai, 'aiImageMAPE'),
      threshold: thresholds.ai_image_mape_max,
    },
    {
      key: 'math_invariant_pass_rate',
      passed: metric(formula, 'invariantPassRate') >= thresholds.math_invariant_pass_rate_min,
      actual: metric(formula, 'invariantPassRate'),
      threshold: thresholds.math_invariant_pass_rate_min,
    },
    {
      key: 'deterministic_formula_deviation_pct',
      passed: metric(formula, 'deterministicFormulaDeviationPctMax') <= thresholds.deterministic_formula_deviation_pct_max,
      actual: metric(formula, 'deterministicFormulaDeviationPctMax'),
      threshold: thresholds.deterministic_formula_deviation_pct_max,
    },
    {
      key: 'data_integrity_negative_values',
      passed: metric(formula, 'dataIntegrityNegativeValues') <= thresholds.data_integrity_negative_values_max,
      actual: metric(formula, 'dataIntegrityNegativeValues'),
      threshold: thresholds.data_integrity_negative_values_max,
    },
    {
      key: 'data_integrity_unit_errors',
      passed: metric(formula, 'dataIntegrityUnitNormalizationErrors') <= thresholds.data_integrity_unit_normalization_errors_max,
      actual: metric(formula, 'dataIntegrityUnitNormalizationErrors'),
      threshold: thresholds.data_integrity_unit_normalization_errors_max,
    },
    {
      key: 'archive_reconciliation',
      passed: metric(formula, 'dataIntegrityArchiveReconciliationRate') >= thresholds.data_integrity_archive_reconciliation_min,
      actual: metric(formula, 'dataIntegrityArchiveReconciliationRate'),
      threshold: thresholds.data_integrity_archive_reconciliation_min,
    },
    {
      key: 'ui_action_success_rate',
      passed: (ui?.metrics?.uiActionSuccessRate ?? 0) >= thresholds.ui_action_success_rate_min,
      actual: ui?.metrics?.uiActionSuccessRate ?? 0,
      threshold: thresholds.ui_action_success_rate_min,
    },
    {
      key: 'fixture_schema_validation',
      passed: fixture?.passed === true,
      actual: fixture?.passed ?? false,
      threshold: true,
    },
    {
      key: 'e2e_scenarios',
      passed: e2e?.passed === true,
      actual: e2e?.passed ?? false,
      threshold: true,
    },
  ];

  const prChecks = [
    { key: 'fixtures', passed: fixture?.passed === true, actual: fixture?.passed ?? false, threshold: true },
    { key: 'formula_suite_executed', passed: !!formula, actual: !!formula, threshold: true },
    { key: 'api_suite_executed', passed: !!api, actual: !!api, threshold: true },
    { key: 'ai_suite_executed', passed: !!ai, actual: !!ai, threshold: true },
    { key: 'ui_suite_executed', passed: !!ui, actual: !!ui, threshold: true },
    { key: 'e2e_suite_executed', passed: !!e2e, actual: !!e2e, threshold: true },
  ];

  const checks = tier === 'pr' ? prChecks : strictChecks;
  const passed = checks.every((c) => c.passed);

  const report = {
    version: 1,
    generatedAt: new Date().toISOString(),
    runId,
    gate: {
      name: tier === 'pr' ? 'pr_smoke_gate' : 'release_gate',
      passed,
      tier,
      thresholds,
      checks,
    },
    suites: {
      fixture_validation: fixture,
      formula_data: formula,
      api_contract_load: api,
      ai_quality: ai,
      ui_e2e: ui,
      e2e_scenarios: e2e,
    },
  };

  writeJson(path.join(outDir, 'stress_report.json'), report);
  console.log(JSON.stringify(report, null, 2));
  if (!passed) process.exitCode = 1;
}

main();
