#!/bin/bash
# Run Flutter tests with coverage for all packages in the project.
# Usage: bash scripts/quality/flutter-test.sh
#
# Environment:
#   PROJECT_ROOT / QUALITY_PROJECT_ROOT — project root (default: 2 levels up from script)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-${QUALITY_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if command -v very_good >/dev/null 2>&1; then
  TEST_CMD="very_good test --coverage"
elif command -v dart >/dev/null 2>&1; then
  dart pub global activate very_good_cli >/dev/null 2>&1
  TEST_CMD="very_good test --coverage"
else
  TEST_CMD="flutter test --coverage"
fi

COVERAGE_FOUND=false
FAILED=false

while IFS= read -r pubspec_dir; do
  pkg_name="$(basename "$pubspec_dir")"
  test_output="$(cd "$pubspec_dir" && $TEST_CMD 2>&1 || true)"
  passed_count="$(echo "$test_output" | grep -oE '\+[0-9]+' | tail -1 | tr -d '+' || true)"
  failed_count="$(echo "$test_output" | grep -oE '\-[0-9]+' | tail -1 | tr -d '-' || true)"

  if echo "$test_output" | grep -qE "All tests passed|[0-9]+ passed"; then
    passed_count="$(echo "$test_output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "${passed_count:-?}")"
    echo -e "${GREEN}✓ Tests  ${pkg_name}: ${passed_count} passed${NC}"
    LCOV="$pubspec_dir/coverage/lcov.info"
    if [[ -f "$LCOV" ]]; then
      mkdir -p "$PROJECT_ROOT/reports/coverage"
      cp "$LCOV" "$PROJECT_ROOT/reports/coverage/lcov.info"
      COVERAGE_FOUND=true
    fi
  elif echo "$test_output" | grep -qE "No tests ran|no tests"; then
    echo -e "${YELLOW}— Tests  ${pkg_name}: no tests${NC}"
  else
    echo -e "${RED}✗ Tests  ${pkg_name}: ${failed_count:-?} failed${NC}"
    FAILED=true
  fi
done < <(find "$PROJECT_ROOT" -name "pubspec.yaml" \
  -not -type l \
  -not -path "*/.dart_tool/*" -not -path "*/build/*" -not -path "*/.git/*" \
  -not -path "$PROJECT_ROOT/pubspec.yaml" \
  -not -path "$PROJECT_ROOT/app/*" \
  -exec dirname {} \; | sort)

if [[ "$COVERAGE_FOUND" == false ]]; then
  echo -e "${YELLOW}— Tests  no coverage data generated${NC}"
fi

[[ "$FAILED" == true ]] && exit 1 || exit 0
