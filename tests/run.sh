#!/usr/bin/env bash
# Test runner for ~/.hammerspoon/tests.
# Usage:
#   bash tests/run.sh                          # all modules' tests
#   bash tests/run.sh -m windowscape           # only tests in tests/windowscape/
#   bash tests/run.sh -v                       # print passing test output too
#   bash tests/run.sh -v -m cloudpad           # combine flags
#   bash tests/run.sh tests/cloudpad/foo.sh    # specific test file(s)
#
# Tests:
#   - .sh files at tests/<module>/<name>.sh
#   - files starting with '_' are helpers, never discovered
#   - tests/diagnostic/ is skipped (exploration scripts, not part of the suite)
#
# Exit:
#   0  all passed (skips count as pass)
#   1  one or more tests failed
#   2  preflight failed

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
HS_BIN="${HS_BIN:-/usr/local/bin/hs}"

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

preflight() {
  if ! command -v steve >/dev/null 2>&1; then
    echo "steve not installed. Run: brew install mikker/tap/steve" >&2
    exit 2
  fi
  if ! command -v "$HS_BIN" >/dev/null 2>&1 && ! command -v hs >/dev/null 2>&1; then
    echo "hs CLI not on PATH. In the Hammerspoon console run: hs.ipc.cliInstall()" >&2
    exit 2
  fi
  if ! "$HS_BIN" -c "return 'ok'" 2>/dev/null | grep -q '^ok$'; then
    echo "Hammerspoon not running or IPC not loaded. Open Hammerspoon and ensure require(\"hs.ipc\") is in init.lua" >&2
    exit 2
  fi
  steve apps >/dev/null 2>&1
  local rc=$?
  if [ "$rc" -eq 4 ]; then
    echo "steve has no Accessibility permission. Grant it to your terminal in System Settings > Privacy & Security > Accessibility" >&2
    exit 2
  fi
}

module_filter=""
verbose=0
while getopts "m:vh" opt; do
  case "$opt" in
    m) module_filter="$OPTARG" ;;
    v) verbose=1 ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

preflight

# Collect test files
files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  search_root="$TESTS_DIR"
  if [ -n "$module_filter" ]; then
    if [ ! -d "$TESTS_DIR/$module_filter" ]; then
      echo "no tests directory: $TESTS_DIR/$module_filter" >&2
      exit 2
    fi
    search_root="$TESTS_DIR/$module_filter"
  fi
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$search_root" -type f -name '*.sh' \
      -not -path "$TESTS_DIR/run.sh" \
      -not -path "$TESTS_DIR/diagnostic/*" \
      -not -name '_*' -print0 | LC_ALL=C sort -z)
fi

if [ "${#files[@]}" -eq 0 ]; then
  echo "no tests to run"
  exit 0
fi

passed=0
failed=0
fail_names=()
start_t=$(date +%s)

for f in "${files[@]}"; do
  rel="${f#$TESTS_DIR/}"
  echo "> $rel"
  out="$(bash "$f" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    passed=$((passed + 1))
    echo "  PASS"
    if [ "$verbose" = "1" ] && [ -n "$out" ]; then
      echo "$out" | sed 's/^/    /'
    fi
  else
    failed=$((failed + 1))
    fail_names+=("$rel")
    echo "  FAIL (exit $rc)"
    echo "$out" | tail -n 50 | sed 's/^/    /'
  fi
done

elapsed=$(( $(date +%s) - start_t ))
echo
echo "$passed passed, $failed failed (${elapsed}s)"
if [ "$failed" -gt 0 ]; then
  echo "failed: ${fail_names[*]}"
  exit 1
fi
