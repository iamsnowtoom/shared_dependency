#!/bin/bash

PROJECT_ROOT_PATH=$1
# shellcheck disable=SC2162
while read FILENAME; do
  LCOV_INPUT_FILES="$LCOV_INPUT_FILES -a \"$PROJECT_ROOT_PATH/reports/coverage/$FILENAME\""
done < <( ls "$1/reports/coverage/" )

echo "LCOV_INPUT_FILES" "$LCOV_INPUT_FILES"

eval lcov "${LCOV_INPUT_FILES}" -o "$PROJECT_ROOT_PATH"/reports/coverage/combined_lcov.info --ignore-errors unused --ignore-errors empty --ignore-errors format --ignore-errors corrupt

lcov --remove "$PROJECT_ROOT_PATH"/reports/coverage/combined_lcov.info \
  "lib/main_*.dart" \
  "*.gr.dart" \
  "*.g.dart" \
  "*/di/*" \
  "*.freezed.dart" \
  "*di.config.dart" \
  "*.i69n.dart" \
  "*/generated/*" \
  "*.theme_extension.dart" \
  -o "$PROJECT_ROOT_PATH"/reports/coverage/clean_combined_lcov.info\
  --ignore-errors unused
