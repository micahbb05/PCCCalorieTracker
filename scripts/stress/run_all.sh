#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUN_ID="${STRESS_RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
export STRESS_RUN_ID="$RUN_ID"
TIER="${STRESS_TIER:-pr}"
OUT_DIR="$ROOT_DIR/output/stress/$RUN_ID"
LOG_DIR="$OUT_DIR/logs"
mkdir -p "$LOG_DIR"

SUMMARY_FILE="$OUT_DIR/summary.md"

run_step() {
  local name="$1"
  shift
  local log_file="$LOG_DIR/${name}.log"
  echo "==> [$name]" | tee -a "$SUMMARY_FILE"
  if "$@" >"$log_file" 2>&1; then
    echo "PASS $name" | tee -a "$SUMMARY_FILE"
  else
    echo "FAIL $name (see $log_file)" | tee -a "$SUMMARY_FILE"
    return 1
  fi
}

echo "# Stress Run" > "$SUMMARY_FILE"
echo "- Run ID: $RUN_ID" >> "$SUMMARY_FILE"
echo "- Tier: $TIER" >> "$SUMMARY_FILE"
echo "- Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"

FAILED=0
PR_MODE=0
if [[ "$TIER" == "pr" ]]; then
  PR_MODE=1
fi

run_optional_step() {
  local name="$1"
  shift
  if run_step "$name" "$@"; then
    return 0
  fi
  if [[ "$PR_MODE" -eq 1 ]]; then
    echo "WARN $name failed in PR mode; continuing for smoke signal" | tee -a "$SUMMARY_FILE"
    return 0
  fi
  return 1
}

run_step "fixtures" node "$ROOT_DIR/scripts/stress/validate_fixtures.js" || FAILED=1
run_optional_step "formula_data" node "$ROOT_DIR/scripts/stress/formula_data_suite.js" || FAILED=1
run_optional_step "api_contract_load" node "$ROOT_DIR/scripts/stress/api_contract_load_suite.js" || FAILED=1
run_optional_step "ai_quality" node "$ROOT_DIR/scripts/stress/ai_quality_suite.js" || FAILED=1
run_optional_step "ui_e2e" "$ROOT_DIR/scripts/stress/ui_e2e_suite.sh" || FAILED=1
run_optional_step "e2e_scenarios" node "$ROOT_DIR/scripts/stress/e2e_scenarios_suite.js" || FAILED=1
run_step "report" node "$ROOT_DIR/scripts/stress/generate_report.js" || FAILED=1

echo "" >> "$SUMMARY_FILE"
echo "- Completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SUMMARY_FILE"
if [[ "$FAILED" -eq 0 ]]; then
  echo "- Gate: PASS" >> "$SUMMARY_FILE"
else
  echo "- Gate: FAIL" >> "$SUMMARY_FILE"
fi

echo "Run output: $OUT_DIR"
if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
