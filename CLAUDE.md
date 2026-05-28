# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Hammerspoon configuration directory containing Lua scripts for macOS automation and desktop customization. Hammerspoon is a macOS automation tool that uses Lua for scripting.

## Commands

Reload Hammerspoon configuration after making changes:
- Use the Hammerspoon menubar icon → "Reload Config"
- Or run in Hammerspoon console: `hs.reload()`

Test Lua syntax before reloading:
```bash
/opt/homebrew/bin/lua -e "loadfile('/Users/mateoyadarola/.hammerspoon/ScriptName.lua')"
```

## Architecture

### Entry Point
`init.lua` - Loads enabled modules via `require`. Comment/uncomment lines to enable/disable modules.

### Core Modules

**WindowScape.lua** - Automatic window tiling manager
- Manages window ordering per space in `windowOrderBySpace`
- Supports multiple layout modes: weighted, dwindle, master
- Uses `hs.spaces` for multi-space support (gracefully degrades if Dock is disabled)
- Persists app list to `WindowScape_apps.json`
- Integrates with FrameMaster for simulated fullscreen

**FrameMaster.lua** - Hot corners and screen edge control
- Implements hot corner actions (close/quit/minimize/fullscreen)
- Blocks menu bar and dock from appearing (configurable)
- Uses AppleScript via `hs.task` for reopen dialogs
- Has a `useWindowScape` flag for WindowScape integration

**Palette/** - Quicksilver-style command palette
- Two-stage selection (noun → verb): pick an item, then Tab for a verb or Enter for the default
- Sources: frontmost-app menu items (with shortcut glyphs, ✓ / • marks, disabled state), running apps with per-app verbs (Activate / Hide / Quit / Ask Muse)
- Bare digits 1–9 quick-pick visible rows; ⌘1–⌘9 fire non-default verbs; ⌘⌫ forgets history
- Empty-result Enter ships the query to Muse via `Muse.openWithContext`
- Trigger: `Ctrl+Cmd+Space` or 5-finger trackpad tap; card anchors at the mouse

**CloudPad.lua** - Phone as keyboard/trackpad
- Runs local HTTP server on port 1984
- Serves web interface for touch input from phone

**ZXNav.lua** - Spacebar-chord navigation
- Spacebar + bottom row = cursor movement (ZXCVBNM)
- Spacebar + home row = editing commands (ASDFGHJKL)
- Returns module table; call `ZXNav:start()` to activate

### Module Patterns

Most modules follow this structure:
1. Load hs.* dependencies at top
2. Define local `cfg` or `config` table for settings
3. Use `hs.eventtap` for keyboard/mouse input
4. Use `hs.canvas` for custom UI elements
5. Use `hs.hotkey.bind()` for keyboard shortcuts
6. Common modifier convention: `{ "ctrl", "cmd" }` for window operations

### Key Hammerspoon APIs Used
- `hs.window` / `hs.application` - Window and app management
- `hs.eventtap` - Low-level keyboard/mouse events
- `hs.canvas` - Custom drawing and overlays
- `hs.hotkey` - Keyboard shortcuts
- `hs.axuielement` - Accessibility API access
- `hs.spaces` - macOS Spaces integration (requires Dock running)
- `hs.settings` - Persistent storage
- `hs.json` - JSON serialization for config files

### Configuration Files
- `WindowScape_apps.json` - App whitelist/blacklist for tiling
- `whitelist.txt` - Legacy app list (unused by WindowScape)

## Testing

End-to-end tests live in `tests/`. They drive the live Hammerspoon runtime via the `hs` CLI and observe macOS UI via `steve`. See `tests/README.md` for setup, helpers, and the list of covered modules.

- Run all: `bash tests/run.sh`
- Run one module: `bash tests/run.sh -m <module>`
- Run one test: `bash tests/run.sh tests/<module>/<behavior>.sh`

When adding, changing, or removing a feature, check whether `tests/<module>/` covers it. Add a new test for new behavior, update the existing test for changed behavior, or remove the test alongside the feature.

## Commits

- Keep messages short and general (e.g., "fix tiling bug", "add hotkey")
- No Claude co-authorship or AI attribution
