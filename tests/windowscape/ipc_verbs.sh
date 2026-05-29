#!/usr/bin/env bash
# WindowScape: ipc(verbName) dispatches to verbs table and produces the same
# observable state change as the hotkey path. Spot-checks grow / shrink /
# cycleWidth / resetWeights against the live tiler state.
set -euo pipefail
source "$(dirname "$0")/../_lib.sh"

APP="com.apple.TextEdit"

teardown() {
  steve quit "$APP" >/dev/null 2>&1 || true
  global_teardown
}
trap teardown EXIT

windowscape_reset
launch_app "$APP"
seed_single_window_app "$APP"

winId="$(hsx "return hs.application.get('$APP'):mainWindow():id()")"
hsx "require('WindowScape.core').windowWeights = {}; return 'ok'" >/dev/null

# verbs table is exposed.
expect_eq "$(hsx "return type(require('WindowScape').verbs.grow)")" "function" "verbs.grow is a function"
expect_eq "$(hsx "return type(require('WindowScape').ipc)")" "function" "ipc dispatcher is a function"

# ipc('grow') equals operations.grow().
hsx "require('WindowScape').ipc('grow'); return 'ok'" >/dev/null
expect_eq "$(hsx "return string.format('%.2f', require('WindowScape.tiler').getWindowWeight(hs.window.get($winId)))")" "1.25" "ipc('grow') stepped weight to 1.25"

# ipc('cycleWidth') resets focused weight.
hsx "require('WindowScape').ipc('cycleWidth'); return 'ok'" >/dev/null
expect_eq "$(hsx "return string.format('%.2f', require('WindowScape.tiler').getWindowWeight(hs.window.get($winId)))")" "1.00" "ipc('cycleWidth') reset weight to 1.00"

# ipc('resetWeights') clears the table entirely.
hsx "require('WindowScape').ipc('grow'); return 'ok'" >/dev/null
hsx "require('WindowScape').ipc('resetWeights'); return 'ok'" >/dev/null
expect_eq "$(hsx "local t=require('WindowScape.core').windowWeights; local n=0; for _ in pairs(t) do n=n+1 end; return tostring(n)")" "0" "resetWeights cleared windowWeights table"

# Unknown verb returns nil without crashing; warns to log.
expect_eq "$(hsx "local r = require('WindowScape').ipc('nopeNope'); return r == nil and 'nil' or tostring(r)")" "nil" "unknown verb returns nil"

echo "PASS: windowscape_ipc_verbs"
