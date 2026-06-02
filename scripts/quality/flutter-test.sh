#!/bin/bash
# Run Flutter tests with coverage, detailed failure output, and coverage threshold check.
# Usage: bash scripts/quality/flutter-test.sh [--cov-threshold N]
#
# Environment:
#   PROJECT_ROOT / QUALITY_PROJECT_ROOT — project root

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-${QUALITY_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

COV_THRESHOLD=95

for arg in "$@"; do
  case "$arg" in
    --cov-threshold) shift; COV_THRESHOLD="${1:-95}" ;;
    --cov-threshold=*) COV_THRESHOLD="${arg#*=}" ;;
  esac
done

if command -v very_good >/dev/null 2>&1; then
  TEST_CMD="very_good test --coverage"
elif command -v dart >/dev/null 2>&1; then
  dart pub global activate very_good_cli >/dev/null 2>&1
  TEST_CMD="very_good test --coverage"
else
  TEST_CMD="flutter test --coverage"
fi

COVERAGE_FOUND=false
OVERALL_FAILED=false
START=$(date +%s)

while IFS= read -r pubspec_dir; do
  pkg_name="$(basename "$pubspec_dir")"
  t0=$(date +%s)
  test_output="$(cd "$pubspec_dir" && $TEST_CMD 2>&1 || true)"
  elapsed=$(( $(date +%s) - t0 ))

  passed="$(echo "$test_output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "$(echo "$test_output" | grep -oE '\+[0-9]+' | tail -1 | tr -d '+' || true)")"
  failed="$(echo "$test_output" | grep -oE '\+[0-9]+ -[0-9]+:' | tail -1 | grep -oE '\-[0-9]+' | tr -d '-' || true)"

  if echo "$test_output" | grep -qE "All tests passed|[0-9]+ passed" && [[ -z "$failed" ]]; then
    echo -e "${GREEN}✓  ${pkg_name}  ${passed:-?} passed  (${elapsed}s)${NC}"
    LCOV="$pubspec_dir/coverage/lcov.info"
    if [[ -f "$LCOV" ]]; then
      mkdir -p "$PROJECT_ROOT/reports/coverage"
      cp "$LCOV" "$PROJECT_ROOT/reports/coverage/lcov.info"
      COVERAGE_FOUND=true
    fi
  elif echo "$test_output" | grep -qE "No tests ran|no tests"; then
    echo -e "${DIM}—  ${pkg_name}  no tests${NC}"
  else
    echo -e "${RED}✗  ${pkg_name}  ${failed:-?} failed  (${elapsed}s)${NC}"
    OVERALL_FAILED=true

    # Show failed test details from 'Failing Tests:' section
    python3 - "$test_output" <<'PYEOF'
import sys, re
output = sys.argv[1]
RED='\033[0;31m'; DIM='\033[2m'; CYAN='\033[0;36m'; NC='\033[0m'

# Extract error details per test: look for '(FAILED)' lines
failed_pat = re.compile(r'^(.+?)\s+\S+\s+\(FAILED\)', re.MULTILINE)
file_pat = re.compile(r'(test/[\w/.-]+_test\.dart)\s+(\d+):(\d+)')
err_pat = re.compile(r'Expected:|Error:|Exception:|package:matcher')

# Also parse 'Failing Tests:' section
failing_section = re.search(r'Failing Tests:(.*)', output, re.DOTALL)
if failing_section:
    for line in failing_section.group(1).splitlines():
        m = re.match(r'\s+-\s+\[FAILED\]\s+(.*)', line)
        if m:
            test_name = m.group(1).strip()
            # find error for this test in the output before (FAILED)
            test_block_m = re.search(re.escape(test_name) + r'.+?\(FAILED\)', output, re.DOTALL)
            err = ''
            file_ref = ''
            if test_block_m:
                block = output[:test_block_m.start()]
                # get last error block before this test
                blocks = block.split('\n\n')
                last = blocks[-2] if len(blocks) >= 2 else ''
                fm = file_pat.search(last)
                if fm: file_ref = f'{fm.group(1)}:{fm.group(2)}'
                em = re.search(r"Expected: (.+)", last)
                if em: err = f"Expected: {em.group(1)[:60]}"
            print(f'   {RED}✗{NC} {test_name}')
            if file_ref: print(f'     {DIM}{file_ref}{NC}')
            if err: print(f'     {CYAN}{err}{NC}')
PYEOF
  fi
done < <(find "$PROJECT_ROOT" -name "pubspec.yaml" \
  -not -type l \
  -not -path "*/.dart_tool/*" -not -path "*/build/*" -not -path "*/.git/*" \
  -not -path "$PROJECT_ROOT/pubspec.yaml" \
  -not -path "$PROJECT_ROOT/app/*" \
  -exec dirname {} \; | sort)

ELAPSED=$(( $(date +%s) - START ))
echo -e "${DIM}────────────────────────────────────────${NC}"

# Coverage threshold check
COV_OK=true
if [[ "$COVERAGE_FOUND" == true ]]; then
  LCOV_FILE="$PROJECT_ROOT/reports/coverage/lcov.info"
  COV_PCT="$(python3 -c "
import sys
lines = open(sys.argv[1]).read().splitlines()
da = [l for l in lines if l.startswith('DA:')]
total = len(da); covered = sum(1 for l in da if int(l.split(',')[1]) > 0)
print(f'{(covered/total*100):.1f}' if total > 0 else '0.0')
" "$LCOV_FILE" 2>/dev/null || echo "0.0")"

  if python3 -c "import sys; exit(0 if float('$COV_PCT') >= float('$COV_THRESHOLD') else 1)" 2>/dev/null; then
    echo -e "Coverage: ${GREEN}${COV_PCT}%  ✓  (need ≥${COV_THRESHOLD}%)${NC}"
  else
    echo -e "Coverage: ${RED}${COV_PCT}%  ✗  (need ≥${COV_THRESHOLD}%)${NC}"
    COV_OK=false
  fi
else
  echo -e "${YELLOW}Coverage: no data${NC}"
fi

echo -e "Time:     ${ELAPSED}s"

[[ "$OVERALL_FAILED" == true || "$COV_OK" == false ]] && exit 1 || exit 0
