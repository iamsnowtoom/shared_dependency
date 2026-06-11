#!/bin/bash
# test-with-coverage.sh v1.1.0
export PATH="$PATH":"$HOME/.pub-cache/bin"

checkCommand() {
  if dart pub global list | grep -q "very_good_cli"; then
    echo "very_good_cli already installed..."
    return 0
  fi
}

runVeryGoodTest() {
  cd "$PACKAGE_PATH" || exit 1
  
  TEST_OUTPUT=$(very_good test --coverage 2>&1)
  TEST_RESULT=$?

  DEFAULT_LCOV="coverage/lcov.info"

  if [ -f "$DEFAULT_LCOV" ]; then
    echo "▶ Moving coverage to: $PACKAGE_LCOV_INFO_PATH"
    mv "$DEFAULT_LCOV" "$PACKAGE_LCOV_INFO_PATH"
  else
    echo "❌ very_good test did not generate coverage file"
    exit 1
  fi

  return $TEST_RESULT
}

# ──────────────────────────────────────────────────────
# Added: detailed failure output + coverage check
# ──────────────────────────────────────────────────────

parseTestFailures() {
  echo "$TEST_OUTPUT" | python3 - <<'PYEOF'
import sys, json
tests = {}
for line in sys.stdin:
    try:
        e = json.loads(line)
        if e.get('type') == 'testStart':
            t = e['test']
            tests[t['id']] = {
                'name': t['name'],
                'url': t.get('url', ''),
                'line': t.get('line', '')
            }
        elif e.get('type') == 'error':
            t = tests.get(e.get('testID'), {})
            loc = f"{t.get('url','?')}:{t.get('line','?')}"
            print(f"  ✗ {t.get('name','unknown')}  [{loc}]")
            print(f"    {e.get('error','')}")
    except: pass
PYEOF
}

checkCoverageThreshold() {
  local lf lh coverage
  lf=$(awk -F: '/^LF:/{s+=$2} END{print s+0}' "$PACKAGE_LCOV_INFO_PATH")
  lh=$(awk -F: '/^LH:/{s+=$2} END{print s+0}' "$PACKAGE_LCOV_INFO_PATH")

  if [ -z "$lf" ] || [ "$lf" -eq 0 ]; then
    echo "⚠️  No coverage data found"
    exit 1
  fi

  coverage=$(echo "scale=1; $lh * 100 / $lf" | bc)
  echo "📊 Coverage: ${coverage}% (threshold: 80%)"

  if (( $(echo "$coverage < 80" | bc -l) )); then
    echo "❌ Coverage ${coverage}% is below threshold 80%"
    exit 1
  else
    echo "✅ Coverage threshold met: ${coverage}% >= 80%"
  fi
}

## Generate coverage report
PROJECT_ROOT_PATH="${MELOS_ROOT_PATH:-$1}"
PACKAGE_PATH="${MELOS_PACKAGE_PATH:-$2}"
PACKAGE_NAME="${MELOS_PACKAGE_NAME:-$3}"

PKG_REPORT_DIR="$PROJECT_ROOT_PATH/reports/$PACKAGE_NAME"
mkdir -p "$PKG_REPORT_DIR/coverage" "$PKG_REPORT_DIR/test"
echo "🚀::Report directory ready: $PKG_REPORT_DIR ✅  "

PACKAGE_LCOV_INFO_PATH=$PKG_REPORT_DIR/coverage/lcov.info
PACKAGE_TEST_REPORT_PATH=$PKG_REPORT_DIR/test/test_report.json
PACKAGE_TEST_FAILED_LOG=$PKG_REPORT_DIR/test/test_failed_report.json

echo "PACKAGE_LCOV_INFO_PATH: " "$PACKAGE_LCOV_INFO_PATH"
echo "PACKAGE_TEST_REPORT_PATH: " "$PACKAGE_TEST_REPORT_PATH"

# Run checkCommand, then runTest only if successful
if ! checkCommand; then
  echo "❌ Cannot run very_good tests because very_good_cli is not installed."
  exit 1
fi

runVeryGoodTest

if [ $? -ne 0 ]; then
  echo "❌  Tests Failed in $PACKAGE_PATH. Quality Checking Failed ❌  "
  parseTestFailures
  exit 1
else
  echo "✅  All Tests Passed! ✅  "
fi

# Rewrite SF:lib/... to absolute package paths. python3 keeps a single
# cross-platform code path (BSD vs GNU sed differ on -i) and needs no escaping.
PKG_PATH="$PACKAGE_PATH" LCOV_FILE="$PACKAGE_LCOV_INFO_PATH" python3 - <<'PYEOF'
import os
path, pkg = os.environ['LCOV_FILE'], os.environ['PKG_PATH']
with open(path) as f:
    lines = f.readlines()
with open(path, 'w') as f:
    f.writelines(
        f"SF:{pkg}/lib{l[len('SF:lib'):]}" if l.startswith('SF:lib') else l
        for l in lines
    )
PYEOF

checkCoverageThreshold
