# Hammerspoon test suite

End-to-end tests for the modules in `~/.hammerspoon/`. Each test is a bash script that drives the live Hammerspoon runtime via the `hs` CLI and observes macOS UI via the `steve` Accessibility tool.

## Quick start

```bash
# Run everything
bash tests/run.sh

# Run only one module's tests
bash tests/run.sh -m windowscape

# Run one specific test
bash tests/run.sh tests/cloudpad/health_endpoint.sh

# Print the output of passing tests too
bash tests/run.sh -v
```

## One-time setup

1. Ensure Hammerspoon's IPC is loaded. Your `~/.hammerspoon/init.lua` should already `require("hs.ipc")`.
2. Install the `hs` CLI. In the Hammerspoon console, run:
   ```lua
   hs.ipc.cliInstall()
   ```
3. Install `steve`:
   ```bash
   brew install mikker/tap/steve
   ```
4. Grant your terminal Accessibility permission in System Settings > Privacy & Security > Accessibility.

The runner enforces all four with a preflight check; if anything is missing it prints the fix and exits 2.

## Layout

```
tests/
  run.sh                          # runner: discovers, executes, reports
  _lib.sh                         # shared helpers (hsx, expect_eq, wait_until, ...)
  README.md                       # this file
  <module>/                       # one subdirectory per module under test
    <behavior>.sh                 # one test per behavior
    _<helper>.lua                 # module-local Lua helpers (underscore prefix)
  diagnostic/                     # exploration scripts; skipped by run.sh
```

Files starting with `_` are helpers and are never discovered by `run.sh`. The `diagnostic/` directory is also skipped.

## Writing a test

Save as `tests/<module>/<behavior>.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

# 1. Setup
launch_app "com.apple.TextEdit" TextEdit
seed_single_window_app TextEdit

# 2. Act
hsx "hs.eventtap.keyStroke({'cmd'}, 'w'); return 'ok'" >/dev/null

# 3. Assert
wait_until '[ "$(window_count TextEdit)" = "0" ]' 5 "window closed"

echo "PASS: my_test"
```

Exit code 0 means PASS. Anything else is a FAIL. The runner prints the last 50 lines of a failed test's output.

## Helpers in `_lib.sh`

| Helper | Purpose |
|---|---|
| `hsx <lua>` | Run Lua in Hammerspoon, echo last line of output. |
| `expect_eq <a> <b> <label>` | Assert equality; exit 1 with `label` on mismatch. |
| `wait_until <expr> <timeout> <label> [<interval>]` | Poll until `<expr>` is true or `<timeout>` seconds pass. Default interval 0.1 s. |
| `launch_app <bundle> [<name>]` | `steve launch` and wait for `hs.application.get(name)`. |
| `seed_windows <app> <n>` | Open exactly `n` windows in `app`, closing extras. |
| `seed_single_window_app <app>` | Convenience for `seed_windows app 1`. |
| `window_count <app>` | Echo integer count of windows. |
| `wait_window_count <app> <n> [<timeout>]` | Block until `window_count == n`. |
| `click_with_modifier <mod> <x> <y>` | Hold `mod` (shift/cmd/alt/ctrl), left-click at (x,y), release. |
| `http_get <url>` | curl GET, echo body. For CloudPad tests. |
| `http_post_json <url> <json>` | curl POST application/json, echo body. |
| `windowscape_reset` | Exit fullscreen, clear snapshots, reset weights/focus history. |
| `global_teardown` | `windowscape_reset` + release modifiers + recenter cursor + clear console. Call in `teardown()`. |
| `dump_diagnostics [<label>]` | On failure, dump focused window, cursor, fullscreen state, snapshot count to stderr. |
| `teardown_quit <app>` | `steve quit "$app"`, ignore errors. |

## Common patterns

**Multi-window WindowScape test:**
```bash
launch_app "com.apple.TextEdit" TextEdit
seed_windows TextEdit 2
windowscape_reset
hsx "require('WindowScape.operations').focusAdjacentWindow('forward')"
wait_until '[ "$(hsx "return hs.window.focusedWindow():id()")" = "<winId2>" ]' 2 "focus advanced"
```

**Modifier-click hot-corner test (FrameMaster):**
```bash
seed_single_window_app TextEdit
screen_w=$(hsx "return hs.screen.mainScreen():frame().w")
screen_h=$(hsx "return hs.screen.mainScreen():frame().h")
click_with_modifier shift "$((screen_w - 1))" "$((screen_h - 1))"
wait_until '[ "$(hsx "return hs.application.get(\"TextEdit\"):isHidden() and \"yes\" or \"no\"")" = "yes" ]' 3 "app hidden"
```

**CloudPad endpoint test:**
```bash
URL=$(hsx "return CloudPad.url" || hsx "require('CloudPad').start({port=1984}); return require('CloudPad').url")
body=$(http_post_json "$URL/events" '{"events":[{"t":"text","s":"hello"}]}')
expect_eq "$(printf '%s' "$body" | grep -c '"ok":true')" "1" "events accepted"
```

**Sim-style test with a Lua companion file:**
```bash
SIM="$(dirname "$0")/_my_sim.lua"
result=$(hsx "return dofile('$SIM')")
expect_eq "$result" "13/13" "sim scenarios all pass"
```

## Debugging a failing test

1. Run it in isolation: `bash tests/<module>/<test>.sh`.
2. Add `set -x` at the top of the test to trace bash.
3. Add `dump_diagnostics "after focus"` at the point of confusion.
4. Inspect state by hand: `hs -c "return require('WindowScape.core').windowWeights"`.

## Modules covered

- **windowscape/**: window create/destroy, minimize via snapshots, fullscreen, focus, move-in-order, weights, snapshot screen reassignment, multi-screen move.
- **apptimeout/**: windowless app detection and recovery.
- **autodmg/**: 24-hour `handledFiles` expiry.
- **edgehopper/**: cursor wrap on screen edge.
- **framemaster/**: hot-corner actions.
- **cloudpad/**: HTTP server lifecycle, /health, /events (mouse, key, text).

Diagnostic scripts (not in the suite):

- **diagnostic/_muse_text_cursor_capture.sh** + runner: Muse HUD text-rendering exploration.
