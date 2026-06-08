#!/bin/bash

PROJECT_ROOT_PATH="${MELOS_ROOT_PATH:-$1}"
COVERAGE_DIR="$PROJECT_ROOT_PATH/reports/coverage"

cd "$COVERAGE_DIR" || exit 1

declare -a LCOV_ARGS=()
while IFS= read -r FILENAME; do
  [[ "$FILENAME" == combined_lcov.info || "$FILENAME" == clean_combined_lcov.info ]] && continue
  [[ "$FILENAME" == *.info ]] || continue
  LCOV_ARGS+=(-a "$FILENAME")
done < <(ls .)

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
