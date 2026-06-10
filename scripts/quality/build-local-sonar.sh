#!/usr/bin/env python3
# build-local-sonar.sh — generates self-contained local-sonar.sh
# Run: python3 scripts/quality/build-local-sonar.sh
# Or:  bash scripts/quality/build-local-sonar.sh  (shebang routes to python3)

import base64
import os
import sys
import tempfile

QUALITY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)))
INTERNAL = os.path.join(QUALITY_DIR, ".internal")
OUTPUT = os.path.join(QUALITY_DIR, "local-sonar.sh")

FILES = {
    "quality_check_sh":          (os.path.join(INTERNAL, "quality-check.sh"),          True),
    "portable_local_sonar_sh":   (os.path.join(INTERNAL, "portable-local-sonar.sh"),   True),
    "generate_report_py":        (os.path.join(INTERNAL, "generate-report.py"),         False),
    "template_html":             (os.path.join(INTERNAL, "template.html"),              False),
    "vendor_jar":                (os.path.join(INTERNAL, "vendor", "sonar-flutter-plugin-0.5.2.jar"), False),
}

print("Reading and encoding internal files...")
encoded = {}
for key, (path, executable) in FILES.items():
    if not os.path.exists(path):
        print(f"ERROR: missing required file: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, "rb") as f:
        raw = f.read()
    encoded[key] = base64.b64encode(raw).decode("ascii")
    size_kb = len(raw) / 1024
    print(f"  {key}: {size_kb:.1f} KB -> {len(encoded[key])} base64 chars")

# Round-trip verify each embedded file
print("Verifying round-trips...")
for key, (path, _) in FILES.items():
    with open(path, "rb") as f:
        original = f.read()
    decoded = base64.b64decode(encoded[key])
    if original != decoded:
        print(f"ERROR: round-trip mismatch for {key}", file=sys.stderr)
        sys.exit(1)
    print(f"  {key}: OK")

PLUGIN_VERSION = "0.5.2"

# The portable base64 decode snippet used in the script (works on macOS + Linux)
DECODE_CMD = "python3 -c 'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read()))'"

SCRIPT = r"""#!/bin/bash
# local-sonar.sh — self-contained Flutter quality check
# Usage: bash scripts/quality/local-sonar.sh 
# Requires: Java 17, Flutter, curl, unzip, python3
#
# Copy this file + flutter-analyze.sh into scripts/quality/ and run:
#   melos run quality:dev
# No other setup needed — all tooling is embedded.

set -euo pipefail
START_TIME=$SECONDS

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_ok()    { echo -e "${GREEN}✓ $*${NC}"; }
log_error() { echo -e "${RED}✗ $*${NC}" >&2; }
log_info()  { echo -e "${CYAN}▸ $*${NC}"; }

show_help() {
  echo ""
  echo "Usage: bash scripts/quality/local-sonar.sh [OPTIONS]"
  echo ""
  echo "Default mode:"
  echo "  Portable local SonarQube from ~/.cache/top-flutter-quality."
  echo "  Default URL: http://localhost:9000 (override with SONAR_LOCAL_PORT)."
  echo "  Requires Java 17; macOS prefers /usr/libexec/java_home -v 17."
  echo "  No Homebrew, Docker, admin, or sudo required."
  echo ""
  echo "First run:"
  echo "  Tooling is embedded — no setup.sh needed."
  echo ""
  echo "Options:"
  echo "  --keep-sonar-local   Keep local SonarQube running after scan"
  echo "  --keep-server        Alias for --keep-sonar-local"
  echo "  -d, --dup-threshold  Max duplication % (default: 6)"
  echo "  -c, --cov-threshold  Min coverage % (default: 80)"
  echo "  --focus AREAS        Focus on: coverage,duplication,smell"
  echo "  --minimal-focus      Shorthand for --focus coverage,duplication,smell"
  echo "  --focus-minimal      Alias for --minimal-focus"
  echo "  --smell-threshold N  Max code smells in focus mode (default: 0)"
  echo "  --legacy-local       Use old Homebrew + Colima/Docker local mode"
  echo "  --portable-local     Backward-compatible alias for the default mode"
  echo "  -h, --help           Show this help (no download)"
  echo ""
  echo "Examples:"
  echo "  bash scripts/quality/local-sonar.sh"
  echo "  bash scripts/quality/local-sonar.sh --keep-sonar-local"
  echo ""
}

# Help is an early exit with no brew/download.
for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    show_help
    exit 0
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPORT_HTML="${QUALITY_REPORT_HTML:-$PROJECT_ROOT/reports/quality/quality-report.html}"

# Cache dir (shared with embedded scripts)
CACHE_DIR="${TOP_FLUTTER_QUALITY_CACHE:-$HOME/.cache/top-flutter-quality}"

# ── Embedded scripts (base64) ─────────────────────────────────────────────────
""".lstrip()

# Inject base64 data variables
for key, b64 in encoded.items():
    SCRIPT += f"_DATA_{key}='{b64}'\n"

SCRIPT += f"PLUGIN_VERSION=\"{PLUGIN_VERSION}\"\n"

SCRIPT += r"""
SONARQUBE_PORTABLE_VERSION="${SONARQUBE_PORTABLE_VERSION:-10.7.0.96327}"
SONAR_SCANNER_PORTABLE_VERSION="${SONAR_SCANNER_PORTABLE_VERSION:-6.2.1.4610}"
SONARQUBE_ZIP_URL="${SONARQUBE_ZIP_URL:-https://binaries.sonarsource.com/Distribution/sonarqube/sonarqube-${SONARQUBE_PORTABLE_VERSION}.zip}"
SONAR_SCANNER_ZIP_URL="${SONAR_SCANNER_ZIP_URL:-https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_PORTABLE_VERSION}.zip}"
"""

SCRIPT += r"""
# Portable base64 decode: works on macOS and Linux
_b64decode() { python3 -c 'import base64,sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read()))'; }

# ── Decode internal scripts to temp dir ──────────────────────────────────────
setup_tmp_scripts() {
  TMP_SCRIPTS="$(mktemp -d /tmp/quality-XXXXXX)"
  trap 'rm -rf "$TMP_SCRIPTS"' EXIT INT TERM

  printf '%s' "$_DATA_quality_check_sh"        | _b64decode > "$TMP_SCRIPTS/quality-check.sh"
  printf '%s' "$_DATA_portable_local_sonar_sh" | _b64decode > "$TMP_SCRIPTS/portable-local-sonar.sh"
  printf '%s' "$_DATA_generate_report_py"      | _b64decode > "$TMP_SCRIPTS/generate-report.py"
  printf '%s' "$_DATA_template_html"           | _b64decode > "$TMP_SCRIPTS/template.html"

  chmod +x "$TMP_SCRIPTS/quality-check.sh" "$TMP_SCRIPTS/portable-local-sonar.sh"

  export TMP_SCRIPTS
}

# ── Java resolution (needed for SonarQube) ───────────────────────────────────
java_line_for_home() {
  "$1/bin/java" -version 2>&1 | python3 -c 'import sys; print(sys.stdin.readline().strip())' 2>/dev/null || true
}

java_major_for_home() {
  "$1/bin/java" -version 2>&1 | python3 -c 'import re,sys
text=sys.stdin.read()
m=re.search(r"version \"([^\"]+)\"", text)
if not m:
    sys.exit(0)
v=m.group(1)
print(v.split(".")[1] if v.startswith("1.") else v.split(".")[0])' 2>/dev/null || true
}

use_java_home() {
  export JAVA_HOME="$1"
  export PATH="$JAVA_HOME/bin:$PATH"
}

resolve_java() {
  local mac_java17=""
  local path_java=""
  local path_home=""
  local path_major=""

  if [[ -n "${PORTABLE_JAVA_HOME:-}" ]]; then
    if [[ ! -x "$PORTABLE_JAVA_HOME/bin/java" ]]; then
      log_error "PORTABLE_JAVA_HOME does not point to an executable JDK: $PORTABLE_JAVA_HOME"
      exit 1
    fi
    local major="$(java_major_for_home "$PORTABLE_JAVA_HOME")"
    if [[ "$major" != "17" ]]; then
      log_error "SonarQube requires Java 17; PORTABLE_JAVA_HOME is ${major:-unknown}."
      exit 1
    fi
    use_java_home "$PORTABLE_JAVA_HOME"
    return 0
  fi

  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    if [[ "$(java_major_for_home "$JAVA_HOME")" == "17" ]]; then
      use_java_home "$JAVA_HOME"
      return 0
    fi
  fi

  if [[ "$(uname -s)" == "Darwin" ]] && [[ -x /usr/libexec/java_home ]]; then
    mac_java17="$(/usr/libexec/java_home -v 17 2>/dev/null || true)"
    if [[ -n "$mac_java17" && -x "$mac_java17/bin/java" ]]; then
      use_java_home "$mac_java17"
      return 0
    fi
  fi

  if command -v java >/dev/null 2>&1; then
    path_java="$(command -v java)"
    path_home="$(cd "$(dirname "$path_java")/.." && pwd)"
    if [[ -x "$path_home/bin/java" ]]; then
      path_major="$(java_major_for_home "$path_home")"
      if [[ "$path_major" == "17" ]]; then
        use_java_home "$path_home"
        return 0
      fi
      log_error "SonarQube requires Java 17; PATH java is ${path_major:-unknown}."
      echo "  Install JDK 17 and set PORTABLE_JAVA_HOME, or on macOS install a JDK 17 visible to /usr/libexec/java_home -v 17."
      exit 1
    fi
  fi

  log_error "Java 17 not found."
  echo ""
  echo "  To fix without admin/Homebrew:"
  echo "    1. Download a JDK 17 archive from https://adoptium.net/temurin/releases/"
  echo "    2. Extract it, e.g.: tar -xzf OpenJDK17*.tar.gz -C ~/.cache/jdk/"
  echo "    3. Re-run with: PORTABLE_JAVA_HOME=~/.cache/jdk/<extracted-dir> bash scripts/quality/local-sonar.sh"
  echo ""
  exit 1
}

validate_flutter_plugin_jar() {
  local jar_path="$1"
  [[ -f "$jar_path" ]] || return 1
  unzip -t "$jar_path" >/dev/null 2>&1
}

download_if_missing() {
  local url="$1" output="$2"
  if [[ ! -f "$output" ]]; then
    curl -fL "$url" -o "$output" 2>/dev/null || { rm -f "$output"; log_error "Download failed: $url"; exit 1; }
    if ! unzip -t "$output" >/dev/null 2>&1; then
      rm -f "$output"
      log_error "Downloaded file is corrupt: $url"
      exit 1
    fi
  fi
}

extract_if_missing() {
  local zip="$1" dest_parent="$2" dest_dir="$3" glob_pattern="$4" label="$5"
  if [[ ! -d "$dest_dir" ]]; then
    unzip -q "$zip" -d "$dest_parent"
    if [[ ! -d "$dest_dir" ]]; then
      local extracted
      extracted="$(find "$dest_parent" -maxdepth 1 -name "$glob_pattern" -type d | head -1)"
      if [[ -z "$extracted" ]]; then
        log_error "Could not find extracted $label directory under $dest_parent."
        exit 1
      fi
      mv "$extracted" "$dest_dir"
    fi
  fi
}

# ── SonarQube failure diagnostics ────────────────────────────────────────────
diagnose_sonar_failure() {
  local log="$1"
  echo -e "${CYAN}  Diagnosing...${NC}"

  # Check Java version using existing helper
  local java_ver
  java_ver="$(java_major_for_home "$JAVA_HOME")"
  if [[ -z "$java_ver" ]]; then
    echo -e "${RED}  ✗ Java not found${NC}"
    echo -e "  → Fix: brew install openjdk@17"
    echo -e "         then re-run: bash scripts/quality/local-sonar.sh"
    return
  elif [[ "$java_ver" -lt 17 ]]; then
    echo -e "${RED}  ✗ Java ${java_ver} found — need Java 17+${NC}"
    echo -e "  → Fix: export JAVA_HOME=\$(/usr/libexec/java_home -v 17)"
    echo -e "         then re-run: bash scripts/quality/local-sonar.sh"
    return
  fi

  # Check log for known patterns
  if [[ -f "$log" ]]; then
    if grep -q "OutOfMemoryError\|Cannot allocate memory" "$log" 2>/dev/null; then
      echo -e "${RED}  ✗ Out of memory${NC}"
      echo -e "  → Fix: Close other apps and re-run"
      echo -e "         bash scripts/quality/local-sonar.sh"
      return
    fi
    if grep -q "Connection refused\|Unable to connect" "$log" 2>/dev/null; then
      echo -e "${RED}  ✗ SonarQube failed to start — try again${NC}"
      echo -e "  → Fix: bash scripts/quality/local-sonar.sh"
      return
    fi
  fi

  # Unknown — show log path
  echo -e "  (cause unknown)"
  [[ -f "$log" ]] && echo -e "  → Log: ${log}"
  echo -e "  → Try: bash scripts/quality/local-sonar.sh"
}

# ── First-run / auto-setup ────────────────────────────────────────────────────
# Decodes vendor JAR to cache so portable-local-sonar.sh can find it.
# Also pre-downloads SonarQube + sonar-scanner so lint/tests don't block on it.
run_setup() {
  echo ""
  echo -e "${CYAN}   /\\_/\\  First run — quality tooling${NC}"
  echo -e "${CYAN}  ( o.o )  This runs once. Grab a coffee ☕${NC}"
  echo -e "${CYAN}   > ^ <${NC}"
  echo ""

  for tool in curl unzip python3; do
    if command -v "$tool" >/dev/null 2>&1; then
      log_ok "$tool: $(command -v "$tool")"
    else
      log_error "$tool is required but not found on PATH."
      exit 1
    fi
  done

  resolve_java
  log_ok "java: $(java_line_for_home "$JAVA_HOME")"

  mkdir -p "$CACHE_DIR/plugins"
  log_ok "Cache directories ready: $CACHE_DIR"

  # Download SonarQube and sonar-scanner
  local sq_zip="$CACHE_DIR/sonarqube/sonarqube-${SONARQUBE_PORTABLE_VERSION}.zip"
  local sq_dir="$CACHE_DIR/sonarqube/sonarqube-${SONARQUBE_PORTABLE_VERSION}"
  local ss_zip="$CACHE_DIR/sonar-scanner/sonar-scanner-cli-${SONAR_SCANNER_PORTABLE_VERSION}.zip"
  local ss_dir="$CACHE_DIR/sonar-scanner/sonar-scanner-${SONAR_SCANNER_PORTABLE_VERSION}"

  mkdir -p "$CACHE_DIR/sonarqube" "$CACHE_DIR/sonar-scanner"
  echo -ne "${CYAN}▸ Downloading quality tools...${NC}"
  (
    download_if_missing "$SONARQUBE_ZIP_URL" "$sq_zip"
    extract_if_missing "$sq_zip" "$CACHE_DIR/sonarqube" "$sq_dir" "sonarqube-*" "SonarQube"
    download_if_missing "$SONAR_SCANNER_ZIP_URL" "$ss_zip"
    extract_if_missing "$ss_zip" "$CACHE_DIR/sonar-scanner" "$ss_dir" "sonar-scanner-*" "sonar-scanner"
  ) &
  _dl_pid=$!
  _sp='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; _si=0
  while kill -0 "$_dl_pid" 2>/dev/null; do
    printf ' %s\b\b' "${_sp:$((_si++ % ${#_sp})):1}"
    sleep 0.1
  done
  if ! wait "$_dl_pid"; then
    echo ""; log_error "Download failed — check network connection"; exit 1
  fi
  printf '  done\n'
  # Remove macOS quarantine from downloaded tools (prevents native library blocks)
  xattr -rd com.apple.quarantine "$CACHE_DIR" 2>/dev/null || true

  # Decode vendor JAR to cache
  local jar_dest="$CACHE_DIR/plugins/sonar-flutter-plugin-${PLUGIN_VERSION}.jar"
  if [[ ! -f "$jar_dest" ]]; then
    printf '%s' "$_DATA_vendor_jar" | _b64decode > "$jar_dest"
    if ! validate_flutter_plugin_jar "$jar_dest"; then
      log_error "Decoded sonar-flutter plugin jar is invalid: $jar_dest"
      rm -f "$jar_dest"
      exit 1
    fi
    log_ok "sonar-flutter plugin decoded: $jar_dest"
  else
    log_ok "sonar-flutter plugin cache: $jar_dest"
  fi
  export SONAR_FLUTTER_PLUGIN_JAR="$jar_dest"

  # ── Elasticsearch warmup (init indices once for fast subsequent starts) ────────
  local sq_dir="$CACHE_DIR/sonarqube/sonarqube-${SONARQUBE_PORTABLE_VERSION}"
  local _wport="${SONAR_LOCAL_PORT:-19102}"
  local _wlog="$CACHE_DIR/runtime/warmup.log"
  local _wmarker="$sq_dir/data/.warmup_done"
  mkdir -p "$CACHE_DIR/runtime"
  if [[ ! -f "$_wmarker" ]]; then
    # Kill any stale SonarQube before fresh warmup (e.g. after --clear-cache)
    lsof -ti :"$_wport" | xargs kill -9 2>/dev/null || true
    sleep 2
    # Estimate warmup time from machine specs
    _arch="$(uname -m)"
    _ram_gb=$(python3 -c "
import subprocess, sys
try:
    if sys.platform=='darwin':
        r=subprocess.run(['sysctl','-n','hw.memsize'],capture_output=True,text=True)
        print(int(r.stdout.strip())//1024//1024//1024)
    else:
        with open('/proc/meminfo') as f:
            for l in f:
                if l.startswith('MemTotal'): print(int(l.split()[1])//1024//1024); break
except: print(0)
" 2>/dev/null || echo "0")
    if [[ "${_ram_gb:-0}" -le 8 ]]; then
      _estimate="~10-15 min"
    else
      _estimate="~5-8 min"
    fi
    [[ ! -f "$_wsq_script" ]] && _wsq_script="$(find "$sq_dir/bin" -name "sonar.sh" | head -1 || true)"
    chmod +x "$_wsq_script" 2>/dev/null || true
    JAVA_HOME="${JAVA_HOME:-}" bash "$_wsq_script" console >> "$_wlog" 2>&1 &
    _wpid=$!
    local _wdeadline=$(( SECONDS + 900 )) _wrestarted=0
    while (( SECONDS < _wdeadline )); do
      if curl -fsS "http://localhost:${_wport}/api/system/status" 2>/dev/null \
           | python3 -c 'import json,sys; exit(0 if json.load(sys.stdin).get("status")=="UP" else 1)' 2>/dev/null; then
        break
      fi
      if ! kill -0 "$_wpid" 2>/dev/null && [[ "$_wrestarted" -eq 0 ]]; then
        _wrestarted=1; sleep 60
        JAVA_HOME="${JAVA_HOME:-}" bash "$_wsq_script" console >> "$_wlog" 2>&1 &
        _wpid=$!
      fi
      sleep 5
    done
    kill "$_wpid" 2>/dev/null || true
    wait "$_wpid" 2>/dev/null || true
    mkdir -p "$(dirname "$_wmarker")" && touch "$_wmarker"
    printf ' done\n'
  fi

  # Install very_good_cli for test coverage
  if ! command -v very_good >/dev/null 2>&1; then
    if command -v dart >/dev/null 2>&1; then
      echo -e "${CYAN}▸ Installing very_good_cli...${NC}"
      dart pub global activate very_good_cli >/dev/null 2>&1
    fi
  fi

  echo ""
  echo -e "${GREEN}   /\\_/\\  Setup complete${NC}"
  echo -e "${GREEN}  ( ^.^ )  starting quality check...${NC}"
  echo -e "${GREEN}   > ^ <${NC}"
  echo ""
}

# Run setup if SonarQube cache is missing (first run)
if [[ ! -d "$CACHE_DIR/sonarqube" ]]; then
  run_setup
else
  # Ensure vendor JAR is always decoded to cache (re-run case)
  SONAR_FLUTTER_PLUGIN_JAR="${SONAR_FLUTTER_PLUGIN_JAR:-$CACHE_DIR/plugins/sonar-flutter-plugin-${PLUGIN_VERSION}.jar}"
  if [[ ! -f "$SONAR_FLUTTER_PLUGIN_JAR" ]]; then
    mkdir -p "$CACHE_DIR/plugins"
    printf '%s' "$_DATA_vendor_jar" | _b64decode > "$SONAR_FLUTTER_PLUGIN_JAR"
    if ! validate_flutter_plugin_jar "$SONAR_FLUTTER_PLUGIN_JAR"; then
      log_error "Decoded sonar-flutter plugin jar is invalid: $SONAR_FLUTTER_PLUGIN_JAR"
      rm -f "$SONAR_FLUTTER_PLUGIN_JAR"
      exit 1
    fi
  fi
  export SONAR_FLUTTER_PLUGIN_JAR
fi

# ── Decode temp scripts ───────────────────────────────────────────────────────
setup_tmp_scripts

# ── Argument parsing ──────────────────────────────────────────────────────────
REMAINING_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clear-cache)
      echo -e "${CYAN}▸ Clearing cache: ${CACHE_DIR}${NC}"
      lsof -ti :"${SONAR_LOCAL_PORT:-19102}" | xargs kill -9 2>/dev/null || true
      rm -rf "$CACHE_DIR"
      echo -e "${GREEN}✓ Cache cleared${NC}"
      exit 0
      ;;
    *)
      REMAINING_ARGS+=("$1")
      shift
      ;;
  esac
done

# ── Export PROJECT_ROOT so embedded scripts resolve paths correctly ────────────
export QUALITY_PROJECT_ROOT="$PROJECT_ROOT"

PROJECT_NAME="$(basename "$PROJECT_ROOT")"
RUN_DATE="$(date '+%Y-%m-%d %H:%M')"
echo ""
echo -e "${CYAN}${PROJECT_NAME}  |  ${RUN_DATE}${NC}"
echo -e "${CYAN}────────────────────────────────────────────────────${NC}"

# Clean previous reports (silent)
rm -rf "$PROJECT_ROOT/reports/quality" "$PROJECT_ROOT/reports/coverage" "$PROJECT_ROOT/reports/lint"
mkdir -p "$PROJECT_ROOT/reports/quality" "$PROJECT_ROOT/reports/coverage" "$PROJECT_ROOT/reports/lint"

# ── Spinner helpers ───────────────────────────────────────────────────────────
_SP='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'; _SPINNER_PID=""
_spin_start() {
  local label="$1" i=0
  while true; do
    printf "\r${CYAN}▸ %-12s${NC}%s " "$label" "${_SP:$((i++ % ${#_SP})):1}"
    sleep 0.08
  done &
  _SPINNER_PID=$!
}
_spin_stop() {
  [[ -n "$_SPINNER_PID" ]] && { kill "$_SPINNER_PID" 2>/dev/null; wait "$_SPINNER_PID" 2>/dev/null || true; }
  printf "\r\033[K"; _SPINNER_PID=""
}

# Step 1 — Analyze
LINT_SCRIPT="$SCRIPT_DIR/flutter-analyze.sh"
if [[ -f "$LINT_SCRIPT" ]]; then
  _spin_start "Analyze"
  LINT_LINE="$(bash "$LINT_SCRIPT" 2>&1 | tail -1 || true)"
  _spin_stop
  echo -e "▸ ${LINT_LINE# }"
else
  echo -e "${YELLOW}▸ Analyze — skipped (flutter-analyze.sh not found)${NC}"
fi

# Step 2 — Test coverage
if command -v very_good >/dev/null 2>&1; then
  TEST_CMD="very_good test --coverage"
elif command -v dart >/dev/null 2>&1; then
  dart pub global activate very_good_cli >/dev/null 2>&1
  TEST_CMD="very_good test --coverage"
else
  TEST_CMD="flutter test --coverage"
fi
COVERAGE_FOUND=false
while IFS= read -r pubspec_dir; do
  pkg_name="$(basename "$pubspec_dir")"
  _spin_start "Tests"
  test_output="$(cd "$pubspec_dir" && $TEST_CMD 2>&1 || true)"
  passed_count="$(echo "$test_output" | grep -oE '\+[0-9]+' | tail -1 | tr -d '+' || true)"
  failed_count="$(echo "$test_output" | grep -oE '\-[0-9]+' | tail -1 | tr -d '-' || true)"
  _spin_stop
  if echo "$test_output" | grep -qE "All tests passed|[0-9]+ passed"; then
    passed_count="$(echo "$test_output" | grep -oE '[0-9]+ passed' | grep -oE '[0-9]+' | tail -1 || echo "${passed_count:-?}")"
    echo -e "${GREEN}▸ Tests   ✓  ${pkg_name}: ${passed_count} passed${NC}"
    LCOV="$pubspec_dir/coverage/lcov.info"
    if [[ -f "$LCOV" ]]; then
      mkdir -p "$PROJECT_ROOT/reports/coverage"
      cp "$LCOV" "$PROJECT_ROOT/reports/coverage/lcov.info"
      COVERAGE_FOUND=true
    fi
  elif echo "$test_output" | grep -qE "No tests ran|no tests"; then
    echo -e "${YELLOW}▸ Tests   —  ${pkg_name}: no tests${NC}"
  else
    echo -e "${RED}▸ Tests   ✗  ${pkg_name}: ${failed_count:-?} failed${NC}"
  fi
done < <(
  _pkg_dirs="$(find "$PROJECT_ROOT" -name "pubspec.yaml" \
    -not -type l \
    -not -path "*/.dart_tool/*" -not -path "*/build/*" -not -path "*/.git/*" \
    -not -path "$PROJECT_ROOT/pubspec.yaml" \
    -not -path "$PROJECT_ROOT/app/*" \
    -exec dirname {} \; | sort)"
  if [[ -n "$_pkg_dirs" ]]; then
    printf '%s\n' "$_pkg_dirs"
  elif [[ -f "$PROJECT_ROOT/pubspec.yaml" ]]; then
    # Single-package mode: PROJECT_ROOT itself is the package
    printf '%s\n' "$PROJECT_ROOT"
  fi
)
if [[ "$COVERAGE_FOUND" == false ]]; then
  echo -e "${YELLOW}▸ Tests   —  no coverage data generated${NC}"
fi

# Step 3 — Sonar scan
# Kill leftover process only if it's NOT a healthy SonarQube instance
_sonar_port="${SONAR_LOCAL_PORT:-19102}"
_sonar_status=$(curl -fsS "http://localhost:${_sonar_port}/api/system/status" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || echo "")
if [[ "$_sonar_status" != "UP" ]]; then
  lsof -ti :"$_sonar_port" | xargs kill -9 2>/dev/null || true
fi
SONAR_LOG="$PROJECT_ROOT/reports/quality/sonar.log"
mkdir -p "$PROJECT_ROOT/reports/quality"
_spin_start "SonarQube"
set +e
if [[ ${#REMAINING_ARGS[@]} -gt 0 ]]; then
  bash "$TMP_SCRIPTS/portable-local-sonar.sh" "${REMAINING_ARGS[@]}" 2>&1 | tee "$SONAR_LOG" | grep -E "^\s*ERROR " || true
  SONAR_EXIT="${PIPESTATUS[0]}"
else
  bash "$TMP_SCRIPTS/portable-local-sonar.sh" 2>&1 | tee "$SONAR_LOG" | grep -E "^\s*ERROR " || true
  SONAR_EXIT="${PIPESTATUS[0]}"
fi
set -e
_spin_stop

# Read gate result and metrics from summary.json
SUMMARY_JSON="${QUALITY_SUMMARY_JSON:-$PROJECT_ROOT/reports/quality/summary.json}"
REPORT_HTML="${QUALITY_REPORT_HTML:-$PROJECT_ROOT/reports/quality/quality-report.html}"
GATE_EXIT=0

if [[ -f "$SUMMARY_JSON" ]]; then
  eval "$(python3 - "$SUMMARY_JSON" << 'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
cov = d.get('coverage',{})
dup = d.get('duplicate',{})
cov_pct = cov.get('percentage'); cov_thr = cov.get('threshold', 80)
dup_pct = dup.get('percentage'); dup_thr = dup.get('threshold', 6)
cov_ok = cov_pct is not None and cov_pct >= cov_thr
dup_ok = dup_pct is not None and dup_pct <= dup_thr
bugs = d.get('bugs'); smells = d.get('smells')
lint = d.get('lint'); lint_passed = lint.get('passed') if lint else None
print(f"GATE='{d.get('gate','unknown')}'")
print(f"COV_DISPLAY='{f'{cov_pct:.1f}%' if cov_pct is not None else 'N/A'}'")
print(f"COV_OK={'1' if cov_ok else '0'}"); print(f"COV_THR='{cov_thr}'")
print(f"DUP_DISPLAY='{f'{dup_pct:.1f}%' if dup_pct is not None else 'N/A'}'")
print(f"DUP_OK={'1' if dup_ok else '0'}"); print(f"DUP_THR='{dup_thr}'")
print(f"BUGS='{bugs if bugs is not None else 'N/A'}'")
print(f"SMELLS='{smells if smells is not None else 'N/A'}'")
print(f"LINT_PASSED='{lint_passed}'")
PYEOF
)"
  [[ "$COV_OK" == "1" ]]  && COV_ICON="${GREEN}✓${NC}" || COV_ICON="${RED}✗${NC}"
  [[ "$DUP_OK" == "1" ]]  && DUP_ICON="${GREEN}✓${NC}" || DUP_ICON="${RED}✗${NC}"
  [[ "$BUGS" == "0" ]]    && BUG_ICON="${GREEN}✓${NC}" || BUG_ICON="${RED}✗${NC}"
  case "$LINT_PASSED" in
    True)  LINT_STATUS="${GREEN}✓ Passed${NC}" ;;
    False) LINT_STATUS="${RED}✗ Failed${NC}" ;;
    *)     LINT_STATUS="— N/A" ;;
  esac

  echo ""
  echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
  echo -e "  Coverage : $(echo -e "$COV_ICON") ${COV_DISPLAY} (need ≥${COV_THR}%)"
  echo -e "  Dup      : $(echo -e "$DUP_ICON") ${DUP_DISPLAY} (need ≤${DUP_THR}%)"
  echo -e "  Bugs     : $(echo -e "$BUG_ICON") ${BUGS}"
  echo -e "  Smells   : ${SMELLS}"
  echo -e "  Lint     : $(echo -e "$LINT_STATUS")"
  _elapsed=$(( SECONDS - START_TIME )); printf -v _elapsed_fmt "%dm %02ds" $((_elapsed/60)) $((_elapsed%60))
  echo -e "  Time     : ${_elapsed_fmt}"
  echo -e "${CYAN}────────────────────────────────────────────────────${NC}"

  if [[ "$GATE" == "passed" ]]; then
    echo -e "${GREEN}   /\\_/\\  ✅ QUALITY GATE PASSED${NC}"
    echo -e "${GREEN}  ( ^.^ )${NC}"
    echo -e "${GREEN}   > ^ <${NC}"
  else
    echo -e "${RED}   /\\_/\\  ❌ QUALITY GATE FAILED${NC}"
    echo -e "${RED}  ( x.x )${NC}"
    echo -e "${RED}   > v <${NC}"
    GATE_EXIT=1
  fi
  echo -e "${CYAN}  Report: ${REPORT_HTML}${NC}"
  echo ""

  # Open report in browser
  [[ -f "$REPORT_HTML" ]] && open "$REPORT_HTML" 2>/dev/null || true
else
  echo -e "${RED}  ✗ SonarQube scan failed${NC}"
  echo ""
  diagnose_sonar_failure "$SONAR_LOG"
  echo ""
  _elapsed=$(( SECONDS - START_TIME )); printf -v _elapsed_fmt "%dm %02ds" $((_elapsed/60)) $((_elapsed%60))
  echo -e "  Time     : ${_elapsed_fmt}"
  GATE_EXIT=1
fi

exit $GATE_EXIT
"""

# Write output
print(f"\nGenerating {OUTPUT}...")
with open(OUTPUT, "w", encoding="utf-8") as f:
    f.write(SCRIPT)

os.chmod(OUTPUT, 0o755)

size_mb = os.path.getsize(OUTPUT) / (1024 * 1024)
print(f"Done: {OUTPUT}")
print(f"Size: {size_mb:.1f} MB")
