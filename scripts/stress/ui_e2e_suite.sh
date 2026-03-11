#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RUN_ID="${STRESS_RUN_ID:-adhoc}"
OUT_DIR="$ROOT_DIR/output/stress/$RUN_ID"
LOG_DIR="$OUT_DIR/logs/ui"
mkdir -p "$LOG_DIR"

DESTINATION="${STRESS_IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
LOG_FILE="$LOG_DIR/xcodebuild_ui.log"

XCODE_STATUS=0
xcodebuild test \
  -project "$ROOT_DIR/Calorie Tracker.xcodeproj" \
  -scheme "Calorie Tracker" \
  -destination "$DESTINATION" \
  -only-testing:"Calorie TrackerUITests/Calorie_TrackerUITests/testPCCMenuSearchAndScrollStayAnchored" \
  -only-testing:"Calorie TrackerUITests/Calorie_TrackerUITests/testPCCMenuLastCategoryClearsBottomBar" \
  -only-testing:"Calorie TrackerUITests/Calorie_TrackerUITests/testStressRapidTabSwitching" \
  -only-testing:"Calorie TrackerUITests/Calorie_TrackerUITests/testStressExcessiveTextEntry" \
  -only-testing:"Calorie TrackerUITests/Calorie_TrackerUITests/testStressMonkey2000Interactions" \
  -only-testing:"Calorie TrackerUITests/Calorie_TrackerUITests/testE2EHappyPathPCCMenuSearchFlow" \
  > "$LOG_FILE" 2>&1 || XCODE_STATUS=$?

ACTIONS=$(grep -Eo 'STRESS_METRIC actions=[0-9]+' "$LOG_FILE" | tail -n1 | cut -d= -f2 || echo "0")
SUCCESSES=$(grep -Eo 'STRESS_METRIC successes=[0-9]+' "$LOG_FILE" | tail -n1 | cut -d= -f2 || echo "0")
SUCCESS_RATE=$(grep -Eo 'STRESS_METRIC action_success_rate=[0-9.]+' "$LOG_FILE" | tail -n1 | cut -d= -f2 || echo "0")
E2E=$(grep -Eo 'STRESS_METRIC e2e_happy_path=[0-9]+' "$LOG_FILE" | tail -n1 | cut -d= -f2 || echo "0")

PASSED_TESTS=$(grep -c "Test Case '-\\[Calorie_TrackerUITests.*\\]' passed" "$LOG_FILE" || true)
FAILED_TESTS=$(grep -c "Test Case '-\\[Calorie_TrackerUITests.*\\]' failed" "$LOG_FILE" || true)

if [[ "$FAILED_TESTS" -gt 0 || "$XCODE_STATUS" -ne 0 ]]; then
  PASSED=false
else
  PASSED=true
fi

cat > "$OUT_DIR/ui_e2e.json" <<JSON
{
  "suite": "ui_e2e",
  "passed": $PASSED,
  "metrics": {
    "uiActionCount": $ACTIONS,
    "uiActionSuccesses": $SUCCESSES,
    "uiActionSuccessRate": $SUCCESS_RATE,
    "uiCriticalDeadEnds": $FAILED_TESTS,
    "e2eHappyPathPass": $E2E,
    "passedTests": $PASSED_TESTS,
    "failedTests": $FAILED_TESTS
  },
  "logFile": "output/stress/$RUN_ID/logs/ui/xcodebuild_ui.log"
}
JSON

if [[ "$PASSED" != "true" ]]; then
  exit 1
fi
