#!/bin/bash
# Analyze runner for the Flutter monorepo.
# Uses melos analyze (per-package, ordered) if melos is bootstrapped,
# otherwise falls back to flutter analyze at project root.
#
# Usage: bash scripts/quality/flutter-analyze.sh [mode]
#   mode: dev | sit  → only errors cause failure (warnings/info ignored)
#   mode: (empty)    → strict, fail on any issue

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-${QUALITY_PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

MODE=""

show_help() {
  echo ""
  echo "Usage: bash scripts/quality/flutter-analyze.sh [MODE]"
  echo ""
  echo "  --dev | dev  — only errors cause failure (warnings and info ignored)"
  echo "  --sit | sit  — same as dev"
  echo "  (empty)      — strict, fail on any issue"
  echo ""
}

for arg in "$@"; do
  case "$arg" in
    -h|--help|help) show_help; exit 0 ;;
    --dev|dev) MODE="dev" ;;
    --sit|sit) MODE="sit" ;;
    *) echo -e "${RED}✗ Unknown option: $arg${NC}"; show_help; exit 2 ;;
  esac
done

cd "$PROJECT_ROOT"

# Discover packages: all dirs with pubspec.yaml, excluding root
PACKAGES=()
while IFS= read -r pubspec; do
  dir="$(dirname "$pubspec")"
  [[ "$dir" == "." || "$dir" == "$PROJECT_ROOT" ]] && continue
  PACKAGES+=("$dir")
done < <(find "$PROJECT_ROOT" -name "pubspec.yaml" \
    -not -type l \
    -not -path "*/.dart_tool/*" \
    -not -path "*/build/*" \
    -not -path "*/.git/*" \
    -not -path "$PROJECT_ROOT/app/*" \
    | sort)

# Single-package mode: PROJECT_ROOT itself is a package (no sub-packages found)
if [[ ${#PACKAGES[@]} -eq 0 && -f "$PROJECT_ROOT/pubspec.yaml" ]]; then
  PACKAGES=("$PROJECT_ROOT")
fi

_format_pkg_result() {
  local pkg_name="$1"
  local output="$2"
  python3 - "$pkg_name" "$output" <<PYEOF
import sys, re

RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[2m'; NC='\033[0m'
pkg_name = sys.argv[1]
lines = sys.argv[2].splitlines()

pat = re.compile(r'^\s*(error|warning|info)\s+•\s+(.*?)\s+•\s+(.+?:\d+:\d+)\s+•\s+(.+)$')
issues = {'error': [], 'warning': [], 'info': []}
for line in lines:
    m = pat.match(line)
    if m:
        sev, msg, loc, rule = m.group(1), m.group(2).strip(), m.group(3).strip(), m.group(4).strip()
        issues[sev].append((loc, msg, rule))

total = sum(len(v) for v in issues.values())
if total == 0:
    print(f'{DIM}── {pkg_name} — clean{NC}')
    sys.exit(0)

print(f'\n{DIM}── {pkg_name} {"─"*max(0,46-len(pkg_name))}{NC}')
for sev, icon, color in [('info','ℹ',CYAN),('warning','⚠',YELLOW),('error','✗',RED)]:
    for loc, msg, rule in issues[sev]:
        print(f'  {color}{icon}{NC}  {loc}')
        print(f'     {DIM}{msg} ({rule}){NC}')
e=len(issues['error']); w=len(issues['warning']); i=len(issues['info'])
parts=[]
if e: parts.append(f'{RED}{e} error{"s" if e>1 else ""}{NC}')
if w: parts.append(f'{YELLOW}{w} warning{"s" if w>1 else ""}{NC}')
if i: parts.append(f'{CYAN}{i} info{NC}')
print(f'\n  {" · ".join(parts)}')
print(f'{DIM}{"─"*50}{NC}')
PYEOF
}

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}⚠ Analyze — no Flutter packages found under $PROJECT_ROOT${NC}"
  mkdir -p "$PROJECT_ROOT/reports/analyze"
  echo '{"errors":0,"warnings":0,"info":0,"mode":"strict","passed":true,"elapsed":0,"files":[]}' > "$PROJECT_ROOT/reports/analyze/analyze-results.json"
  exit 0
fi

START_TIME=$(date +%s)
RESULT=""
for pkg in "${PACKAGES[@]}"; do
  pkg_result=$(cd "$pkg" && flutter analyze --no-pub 2>&1)
  pkg_name="$(basename "$pkg")"
  _format_pkg_result "$pkg_name" "$pkg_result"
  RESULT="$RESULT"$'\n'"$pkg_result"
done
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

ERROR_COUNT=$(echo "$RESULT" | grep -cE "^\s*error\s*•" || true)
WARNING_COUNT=$(echo "$RESULT" | grep -cE "^\s*warning\s*•" || true)
INFO_COUNT=$(echo "$RESULT" | grep -cE "^\s*info\s*•" || true)

write_analyze_json() {
  local passed_bool
  [[ "$1" == "true" ]] && passed_bool="true" || passed_bool="false"
  mkdir -p "$PROJECT_ROOT/reports/analyze"
  local tmp_result="$PROJECT_ROOT/reports/analyze/.result.tmp"
  trap "rm -f '$tmp_result'" INT TERM
  printf '%s' "$RESULT" > "$tmp_result"
  python3 - "$tmp_result" "$PROJECT_ROOT" "${MODE:-strict}" "$passed_bool" \
      "$ERROR_COUNT" "$WARNING_COUNT" "$INFO_COUNT" "$ELAPSED" \
      > "$PROJECT_ROOT/reports/analyze/analyze-results.json" <<'PYEOF'
import json, re, sys

result_file, project_root, mode, passed_s, errors_s, warnings_s, info_s, elapsed_s = sys.argv[1:]
with open(result_file, encoding='utf-8', errors='replace') as f:
    result = f.read()

files = {}
SEV_KEY = {'error': 'errors', 'warning': 'warnings', 'info': 'info'}
pat = re.compile(r'^\s*(error|warning|info)\s+•\s+(.*?)\s+•\s+(.+?):(\d+):\d+\s+•\s+(.+)$')
for line in result.splitlines():
    m = pat.match(line)
    if not m:
        continue
    sev, msg, path, lineno, rule = m.group(1), m.group(2).strip(), m.group(3).strip(), m.group(4), m.group(5).strip()
    if path.startswith(project_root + '/'):
        path = path[len(project_root)+1:]
    if path not in files:
        files[path] = {'errors': 0, 'warnings': 0, 'info': 0, 'issues': []}
    files[path][SEV_KEY.get(sev, 'info')] += 1
    files[path]['issues'].append({'line': int(lineno), 'message': msg, 'severity': sev, 'rule': rule})

files_list = sorted(files.items(), key=lambda x: (-x[1].get('errors',0), -x[1].get('warnings',0)))[:500]
print(json.dumps({
    'errors': int(errors_s), 'warnings': int(warnings_s), 'info': int(info_s),
    'mode': mode, 'passed': passed_s == 'true', 'elapsed': int(elapsed_s),
    'files': [{'path': p, **v} for p, v in files_list]
}))
PYEOF
  rm -f "$tmp_result"
  trap - INT TERM
}

if [[ "$MODE" == "dev" || "$MODE" == "sit" ]]; then
  if [[ "$ERROR_COUNT" -gt 0 ]]; then
    write_analyze_json "false"
    echo -e "  ${RED}✗ Analyze  — $ERROR_COUNT errors, $WARNING_COUNT warnings, $INFO_COUNT info  [${ELAPSED}s]${NC}"
  else
    write_analyze_json "true"
    if [[ "$WARNING_COUNT" -gt 0 || "$INFO_COUNT" -gt 0 ]]; then
      echo -e "  ${YELLOW}⚠ Analyze  — no errors  ($WARNING_COUNT warnings, $INFO_COUNT info)  [${ELAPSED}s]${NC}"
    else
      echo -e "  ${GREEN}✓ Analyze  — clean  [${ELAPSED}s]${NC}"
    fi
  fi
  exit 0
fi

# Strict mode
TOTAL=$((ERROR_COUNT + WARNING_COUNT + INFO_COUNT))
if [[ "$TOTAL" -gt 0 ]]; then
  write_analyze_json "false"
  echo -e "  ${RED}✗ Analyze  — $ERROR_COUNT errors, $WARNING_COUNT warnings, $INFO_COUNT info  [${ELAPSED}s]${NC}"
  exit 1
else
  write_analyze_json "true"
  echo -e "  ${GREEN}✓ Analyze  — clean  [${ELAPSED}s]${NC}"
fi
