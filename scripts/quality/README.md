# local-sonar.sh

Self-contained local quality gate for Flutter monorepos. Runs lint, tests, and a full SonarQube scan — no Docker, no Homebrew, no admin access required.

## Requirements

| Tool | Notes |
|------|-------|
| `curl` | Pre-installed on macOS/Linux |
| `unzip` | Pre-installed on macOS/Linux |
| `python3` | Pre-installed on macOS/Linux |
| `flutter` / `dart` | Must be on PATH |
| Java 17 | Auto-detected (see [Java detection](#java-detection)); or set `PORTABLE_JAVA_HOME` |

No other external tools needed. SonarQube, sonar-scanner, and the sonar-flutter plugin are all downloaded and cached automatically on first run.

## Quick Start

```bash
# Copy local-sonar.sh and flutter-analyze.sh into your project
cp local-sonar.sh scripts/quality/
cp flutter-analyze.sh  scripts/quality/

# Run
bash scripts/quality/local-sonar.sh
```

First run downloads SonarQube + sonar-scanner (~300 MB) and initialises Elasticsearch indices (~1–5 min). Subsequent runs are fast (~1 min).

## All Flags

| Flag | Description |
|------|-------------|
| `--keep-sonar-local` | Keep SonarQube running after scan (inspect dashboard at `http://localhost:19102`) |
| `--keep-server` | Alias for `--keep-sonar-local` |
| `--stop-sonar-local` | Stop SonarQube on the configured port and exit |
| `--stop-server` | Alias for `--stop-sonar-local` |
| `--clear-cache` | Clear state only (data, temp, tokens) — keeps JDK, zips, extracted tools. Next run skips download. |
| `--clear-cache-all` | Delete entire cache including downloads. Next run re-downloads everything. |
| `-d, --dup-threshold N` | Max duplication % (default: 6) |
| `-c, --cov-threshold N` | Min coverage % (default: 80) |
| `--focus AREAS` | Focus gate on `coverage,duplication,smell` only |
| `--minimal-focus` | Shorthand for `--focus coverage,duplication,smell` |
| `--focus-minimal` | Alias for `--minimal-focus` |
| `--smell-threshold N` | Max code smells in focus mode (default: 0) |
| `-h, --help` | Show help and exit (no download) |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `TOP_FLUTTER_QUALITY_CACHE` | `~/.cache/top-flutter-quality` | Cache root directory |
| `SONAR_LOCAL_PORT` | `19102` | SonarQube web port |
| `SONARQUBE_PORTABLE_VERSION` | `10.7.0.96327` | SonarQube version to use |
| `SONAR_SCANNER_PORTABLE_VERSION` | `6.2.1.4610` | sonar-scanner version |
| `PORTABLE_JAVA_HOME` | — | Explicit JDK 17 path (takes priority over all auto-detection) |
| `JAVA_HOME` | — | Standard JDK home (used if it points to Java 17) |
| `SONAR_TOKEN` | — | Skip auto-token creation; use this token directly |
| `SONAR_LOCAL_ADMIN_PASSWORD` | `admin` | Override default SonarQube admin password |
| `SONAR_LOCAL_PORT` | `19102` | SonarQube HTTP port |

## Cache and Lifecycle

```
~/.cache/top-flutter-quality/
├── jdk/                    ← Temurin JDK 17 (ARM64 auto-download)
├── sonarqube/
│   └── sonarqube-X.Y.Z/
│       ├── data/           ← Elasticsearch indices  ← cleared by --clear-cache
│       └── temp/           ←                        ← cleared by --clear-cache
├── sonar-scanner/          ← sonar-scanner binary
├── plugins/                ← sonar-flutter plugin JAR
└── runtime/                ← logs, PID files        ← cleared by --clear-cache
```

| Flag | Removes | Keeps |
|------|---------|-------|
| `--clear-cache` | `data/`, `temp/`, `runtime/`, tokens | JDK, zips, extracted tools |
| `--clear-cache-all` | Everything | Nothing |

## Quality Gate Logic

The gate passes when **all** of the following hold:

1. SonarQube quality gate = PASSED
2. Coverage ≥ threshold (default 80%)
3. Duplication ≤ threshold (default 6%)
4. Lint = no errors (strict mode)

With `--focus coverage,duplication,smell`, the gate is computed locally from those three thresholds only — SonarQube's configured gate is bypassed.

## Java Detection

`resolve_java()` checks in this order and uses the first Java 17 found:

1. `PORTABLE_JAVA_HOME` env var
2. `JAVA_HOME` env var (if it points to Java 17)
3. macOS `/usr/libexec/java_home -v 17`
4. Homebrew Apple Silicon: `/opt/homebrew/opt/openjdk@17/...`
5. `java` on PATH (if version 17)
6. Cached Temurin JDK in `~/.cache/top-flutter-quality/jdk/`

If none found on macOS ARM64, Temurin 17 is downloaded automatically from Adoptium (fallback: Azul Zulu, Microsoft OpenJDK).

> **Note:** Homebrew's OpenJDK 17.0.16 on Apple Silicon (ARM64) has a known SIGSEGV bug with Elasticsearch. The auto-downloaded Temurin/Zulu JDK avoids this.

## First-Run Warmup

On first run (or after `--clear-cache`), SonarQube initialises Elasticsearch indices. This takes **1–5 minutes** and is a one-time cost. A `.warmup_done` marker prevents it from repeating.

## Embedded Components

`local-sonar.sh` is a self-contained file (~10 MB) that embeds:

| Component | Description |
|-----------|-------------|
| `portable-local-sonar.sh` | Starts/stops portable SonarQube, manages token |
| `quality-check.sh` | Runs sonar-scanner, generates summary.json |
| `generate-report.py` | Reads SonarQube API, writes quality-report.html |
| `template.html` | HTML/CSS/JS template for the report |
| `sonar-flutter-plugin-0.5.2.jar` | Dart/Flutter analyser plugin for SonarQube |

To rebuild after modifying internal scripts:

```bash
# Requires the .internal/ source directory (not distributed)
python3 scripts/quality/build-local-sonar.sh
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Java 17 not found` | No JDK 17 on system | Set `PORTABLE_JAVA_HOME`, or let the script auto-download Temurin |
| `SonarQube is already running` | Stale PID file | The script cleans this automatically; run `--stop-sonar-local` if stuck |
| `high disk watermark exceeded` | Disk >90% full | Free disk space, or disk threshold is auto-disabled in sonar.properties |
| `Address already in use` (port) | Port 19102 or 19103 occupied | Set `SONAR_LOCAL_PORT` to a free port |
| `SIGSEGV` / exit code 132 | Homebrew JDK ARM64 bug | Let the script auto-download Temurin (first run) or set `PORTABLE_JAVA_HOME` |
| Scan stuck at SonarQube spinner | PID file or stale process | Run `bash local-sonar.sh --stop-sonar-local` then retry |
| Quality Gate always fails | Coverage/dup thresholds | Use `--cov-threshold 70 --dup-threshold 10` or `--minimal-focus` |
