#!/bin/bash

PROJECT_ROOT_PATH="${MELOS_ROOT_PATH:-$1}"
COVERAGE_DIR="$PROJECT_ROOT_PATH/reports/coverage"

mkdir -p "$COVERAGE_DIR"
cd "$COVERAGE_DIR" || exit 1

# lcov 2.x splits -a values on whitespace, so pass paths relative to
# reports/coverage (cwd) to keep them space-free even when the project
# root contains spaces.
declare -a LCOV_ARGS=()
for LCOV_FILE in "$PROJECT_ROOT_PATH"/reports/*/coverage/lcov.info; do
  [[ -f "$LCOV_FILE" ]] || continue
  PKG_NAME="$(basename "$(dirname "$(dirname "$LCOV_FILE")")")"
  LCOV_ARGS+=(-a "../$PKG_NAME/coverage/lcov.info")
done

echo "LCOV_INPUT_FILES: ${LCOV_ARGS[*]}"

lcov "${LCOV_ARGS[@]}" \
  -o combined_lcov.info \
  --ignore-errors unused --ignore-errors empty --ignore-errors format --ignore-errors corrupt

lcov --remove combined_lcov.info \
  "lib/main_*.dart" \
  "*.gr.dart" \
  "*.g.dart" \
  "*/di/*" \
  "*.freezed.dart" \
  "*di.config.dart" \
  "*.i69n.dart" \
  "*/generated/*" \
  "*.theme_extension.dart" \
  -o clean_combined_lcov.info \
  --ignore-errors unused
