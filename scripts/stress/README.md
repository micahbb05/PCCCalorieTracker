# Stress Test Framework

This folder contains a release-gate stress framework for the iOS app + backend.

## Runner

```bash
STRESS_TIER=pr ./scripts/stress/run_all.sh
STRESS_TIER=nightly ./scripts/stress/run_all.sh
STRESS_TIER=pre-release ./scripts/stress/run_all.sh
```

Optional environment variables:

- `BACKEND_BASE_URL` (default: production cloud functions URL)
- `STRESS_IOS_DESTINATION` (default: `platform=iOS Simulator,name=iPhone 16`)
- `STRESS_RUN_ID` (default: UTC timestamp)

## Tiers

- `pr`: fast subset of AI/API workloads and short soak windows.
- `nightly`: full profile including 60-minute soak settings in fixtures.
- `pre-release`: same as nightly (can be expanded per release checklist).

## Artifacts

All artifacts are written to:

- `output/stress/<run-id>/summary.md`
- `output/stress/<run-id>/stress_report.json`
- `output/stress/<run-id>/*.json` (suite outputs)
- `output/stress/<run-id>/logs/` (raw logs)

## Suites

1. `validate_fixtures.js` - validates fixture datasets against local schemas.
2. `formula_data_suite.js` - formula regressions, existing script integration, data integrity checks.
3. `api_contract_load_suite.js` - endpoint contract tests + steady/burst/soak + failure injection.
4. `ai_quality_suite.js` - text/image AI quality checks and robustness metrics.
5. `ui_e2e_suite.sh` - XCUITest stress + monkey run + UI/E2E metrics extraction.
6. `e2e_scenarios_suite.js` - cross-path backend scenario checks.
7. `generate_report.js` - final gate evaluation and `stress_report.json` generation.
