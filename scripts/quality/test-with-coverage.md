# test-with-coverage.sh

**Version:** 1.1.0

Runs tests with coverage for a single Flutter package in a monorepo, generates lcov output for SonarQube, and enforces a ≥ 80% coverage threshold.

## Usage

```bash
bash test-with-coverage.sh <PROJECT_ROOT_PATH> <PACKAGE_PATH> <PACKAGE_NAME>
```

### Arguments

| Argument | Description | Example |
|---|---|---|
| `PROJECT_ROOT_PATH` | Root of the monorepo | `/path/to/flutter_sonar_project` |
| `PACKAGE_PATH` | Absolute path to the package | `/path/to/flutter_sonar_project/create_login` |
| `PACKAGE_NAME` | Package name (used in output filenames) | `create_login` |

## Functions

### `checkCommand()`
Verifies that `very_good_cli` is available via `dart pub global list`. Exits with error if not found.

### `runVeryGoodTest()`
Changes into `$PACKAGE_PATH`, runs `very_good test --coverage --reporter=json 2>&1`, captures full output in global `$TEST_OUTPUT`, then moves the generated `coverage/lcov.info` to the reports directory.

### `parseTestFailures()`
Reads `$TEST_OUTPUT` via Python heredoc. Parses `testStart` and `error` events from the JSON stream and prints each failing test's name and source `file:line`.

### `checkCoverageThreshold()`
Reads `LF` (lines found) and `LH` (lines hit) from the lcov file, computes coverage percentage via `bc`, and exits 1 if coverage < 80%.

## Main Flow

1. Creates `reports/coverage/` and `reports/test/` under `PROJECT_ROOT_PATH` if absent
2. Calls `checkCommand()` — aborts if `very_good_cli` is not installed
3. Calls `runVeryGoodTest()` — runs tests and captures JSON output + exit code
4. **On failure** — calls `parseTestFailures()` to print test name + `file:line` for each error
5. **On success** — prints `✅ All Tests Passed!`
6. Rewrites `SF:lib/` → `SF:<PACKAGE_PATH>/lib/` in the lcov file using `gsed` (macOS) or `sed` (Linux)
7. Calls `checkCoverageThreshold()` — fails build if coverage < 80%

## Output Files

| File | Description |
|---|---|
| `reports/coverage/lcov_<PACKAGE_NAME>.info` | LCOV coverage data with absolute `SF:` paths |
| `reports/test/<PACKAGE_NAME>_test_report.json` | Full test output (JSON reporter) |
| `reports/test/<PACKAGE_NAME>_test_failed_report.json` | Filtered error entries (when tests fail) |

## Requirements

| Tool | Notes |
|---|---|
| `very_good_cli` | `dart pub global activate very_good_cli` |
| `python3` | Pre-installed on macOS / Linux |
| `bc` | Pre-installed on macOS / Linux |
| `gsed` (macOS only) | `brew install gnu-sed` — required for `SF:` path rewrite on macOS |

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | All tests passed and coverage ≥ 80% |
| `1` | `very_good_cli` not found, tests failed, lcov file missing, or coverage < 80% |

---

## Changelog

### v1.1.0

#### Added
- `parseTestFailures()` — Python heredoc that reads `--reporter=json` output and prints failing test name + `file:line` for each error
- `checkCoverageThreshold()` — computes `LH/LF` from lcov file via `bc`, exits 1 if coverage < 80% (hardcoded, no flag)
- Separator comment block before new functions

#### Changed
- `runVeryGoodTest()` — added `--reporter=json 2>&1`, captures output in global `$TEST_OUTPUT`
- Removed redundant inline comment `# Return the test result exit code`

#### Removed
- `jq`-based failure handler (grep + banner) — replaced by `parseTestFailures()`

---

### v1.0.0 — Initial release

#### Functions
- `checkCommand()` — checks `very_good_cli` via `dart pub global list`
- `runVeryGoodTest()` — runs `very_good test --coverage`, moves `coverage/lcov.info` to `reports/coverage/`

#### Main flow
- Auto-creates `reports/coverage/` and `reports/test/` under `PROJECT_ROOT_PATH` if absent
- Sets `PACKAGE_LCOV_INFO_PATH`, `PACKAGE_TEST_REPORT_PATH`, `PACKAGE_TEST_FAILED_LOG` path variables
- On test failure: greps `"error"` entries into `$PACKAGE_TEST_FAILED_LOG`, displays with `jq` (falls back to `cat`)
- On test pass: prints `✅ All Tests Passed!`
- Rewrites `SF:lib/` → `SF:<PACKAGE_PATH>/lib/` in lcov using `gsed` (macOS) or `sed` (Linux)
