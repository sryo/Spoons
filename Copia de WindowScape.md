# WindowScape - Automatic Window Tiling Manager

A Hammerspoon module that automatically tiles application windows to fill the screen. It manages window ordering, sizing, and layout across multiple screens and macOS Spaces, replacing native fullscreen and minimize with its own simulated versions.

## Overview

WindowScape watches for window events (creation, destruction, movement, focus changes, screen changes) and responds by arranging all eligible windows according to the active layout algorithm. It provides:

- Three layout modes (weighted, dwindle, master) with automatic orientation
- Per-window weight control for proportional sizing
- Simulated fullscreen that avoids macOS Space transitions
- Snapshot-based minimize with live-updating thumbnails
- Custom button overlays replacing the macOS traffic lights
- Multi-monitor and multi-Space support
- Trackpad gesture recognition for hands-free window management

---

## Module Architecture

WindowScape is decomposed into one orchestrator (`WindowScape.lua`) and eight submodules under `WindowScape/`. The orchestrator owns all persistent state (window order, weights, pseudo-windows, focus history, app list), defines the core tiling loop, and wires the submodules together through callback tables. Submodules never `require` each other; all cross-module communication flows through callbacks injected at initialization.

### Module Summary

| Module | File | Purpose |
|---|---|---|
| **config** | `config.lua` | Declares all tunable settings (`cfg`) and numeric constants (`CONST`) |
| **animation** | `animation.lua` | Frame animation with easing; color interpolation utilities |
| **outline** | `outline.lua` | Draws and tracks the colored border around the focused window |
| **layouts** | `layouts.lua` | Pure tiling algorithms: weighted, dwindle, master-stack |
| **fullscreen** | `fullscreen.lua` | Simulated fullscreen mode and all titlebar button overlays |
| **snapshots** | `snapshots.lua` | Minimized-window thumbnail system: capture, layout, restore, tooltip |
| **operations** | `operations.lua` | Window movement/focus commands: reorder, focus adjacent, move to screen |
| **gestures** | `gestures.lua` | N+1 finger trackpad gesture recognition (TTTaps) |

### config

**Owns:** The `cfg` table (user-facing settings) and the `CONST` table (internal numeric constants). Both are plain data with no behavior.

**Key exports:** `cfg`, `CONST` (returned as fields of a single table).

**Dependencies:** None. Leaf module with no callbacks.

### animation

**Owns:** A map of in-flight frame animations keyed by window ID, plus the per-animation timers.

| Function | Description |
|---|---|
| `init(config)` | Stores a reference to `cfg` for duration/FPS settings |
| `animatedSetFrame(win, targetFrame, onComplete)` | Animates a window to `targetFrame` with easeOutCubic; instant if animations disabled or delta negligible |
| `cancelAnimation(winId)` | Stops an in-progress animation for one window |
| `cancelAllAnimations()` | Stops all in-progress animations |
| `isAnimating(winId)` | Returns whether a window is mid-animation |
| `easeOutCubic(t)` / `lerp(a,b,t)` / `lerpColor(c1,c2,t)` | Math utilities consumed by outline's color animation |

**Dependencies:** Receives `cfg` at init. No callbacks.

### outline

**Owns:** A single `hs.drawing.rectangle` for the active outline, a position-refresh timer, and a color-animation timer.

| Function | Description |
|---|---|
| `init(config, constants, anim, colorCallback, logFn, isSnapshottedFn)` | Wires in cfg, CONST, animation module, and two callbacks |
| `draw(win)` | Creates or repositions the outline for `win`; starts the refresh timer |
| `hide()` | Hides the outline rectangle |
| `stopRefresh()` | Stops the periodic position-tracking timer |
| `cleanup()` | Tears down all timers and hides the outline |

**Callbacks:** `getColorForWindow(win)` returns outline color based on pin/pseudo state. `isSnapshotted(winId)` prevents outline on minimized windows.

### layouts

**Owns:** No persistent state. Pure algorithmic module.

| Function | Description |
|---|---|
| `tileWeighted(screenFrame, nonCollapsedWins, collapsedWins, horizontal)` | Distributes space proportional to per-window weights; stacks collapsed windows in a strip |
| `tileDwindle(screenFrame, windows, horizontal)` | Binary-split spiral layout |
| `tileMaster(screenFrame, windows, horizontal)` | One master pane + equal-split stack |
| `distributeEven(total, gaps, count)` | Returns base size and remainder for equal-split distribution |

**Callbacks:** `getWindowWeight(win)`, `applyPseudoTiling(win, tileFrame)`, `animatedSetFrame(win, frame)`.

### fullscreen

**Owns:** Fullscreen state (active flag, window, hidden windows, saved weights) and four maps of canvas overlays (zoom, minimize, pin, close) keyed by window ID. Also owns a button tooltip canvas.

| Function | Description |
|---|---|
| `enter(win)` | Enters simulated fullscreen: hides other windows, maximizes `win` |
| `exit()` | Restores hidden windows, weights, retiles, redraws outline |
| `updateButtonOverlays()` | Reconciles overlay canvases against visible windows |
| `updateButtonOverlaysWithRetry()` | Calls update at 100ms, 300ms, 600ms, 1s (for AX element availability) |
| `clearAllOverlays()` | Deletes all overlay canvases |

**Callbacks:** `restoreWeights`, `getWeights`, `tileWindows`, `drawOutline`, `hideOutline`, `createSnapshot`, `isPseudoWindow`, `togglePseudoWindow`, and others.

### snapshots

**Owns:** The snapshot state table (windows map, order array, creation guards), a refresh timer, tooltip canvas. Layout constants: `PADDING=8`, `GAP=4`, `COLUMN_WIDTH=140`.

| Function | Description |
|---|---|
| `getAdjustedScreenFrame(scr)` | Returns screen frame minus area reserved for snapshot thumbnails |
| `restoreFromSnapshot(winId)` | Animates thumbnail back to original position and restores the window |
| `restoreAll()` / `closeAll()` / `clearAll()` | Bulk restore, close, or tear down all snapshots |
| `updateLayout()` | Repositions all thumbnail canvases according to screen geometry |
| `showContextMenu(winId, data)` | Shows a right-click menu on a thumbnail |

Note: `createSnapshot(win)` is defined in the orchestrator, not this module.

**Callbacks:** `safeGetApplication`, `log`, `tileWindows`, `updateWindowOrder`, `updateButtonOverlays`.

### operations

**Owns:** No persistent state. Stateless command module.

| Function | Description |
|---|---|
| `moveWindowInOrder(direction)` | Swaps the focused window forward/backward in the tiling order |
| `focusAdjacentWindow(direction)` | Focuses the next/previous window on the same screen, moves mouse to center |
| `moveWindowToAdjacentScreen(direction)` | Moves focused window to the next/previous screen with proportional frame mapping |
| `calculateDropPosition(droppedWin, screenWindows, screenFrame)` | Determines insertion index for a drag-dropped window |

**Callbacks:** `getCurrentSpace`, `getWindowOrder`, `setWindowOrder`, `tileWindows`, `drawOutline`, `hideOutline`.

### gestures

**Owns:** An `hs.eventtap` for gesture events, plus transient gesture-tracking state (finger count, touch identities, positions, timing, drag detection).

| Function | Description |
|---|---|
| `start()` | Creates and starts the gesture eventtap |
| `stop()` | Stops and nils the eventtap |
| `check()` | Re-starts the eventtap if it stopped unexpectedly |

**Callbacks:** `focusAdjacentWindow`, `moveWindowInOrder`, `moveWindowToAdjacentScreen`.

### Initialization Order

Module initialization happens in two phases because of forward-reference constraints.

**Phase 1 -- require and early init:** All eight modules are `require`d. Only `animation` and `config` are fully initialized here.

**Phase 2 -- deferred init (as definitions become available):**

| Order | Module | Trigger |
|---|---|---|
| 1 | config | At require time (data only) |
| 2 | animation | Immediately after require |
| 3 | layouts | After `getWindowWeight` and `applyPseudoTiling` defined |
| 4 | snapshots | After `safeGetApplication` and `log` defined; remaining callbacks wired after `tileWindows` defined |
| 5 | outline | After `getOutlineColorForWindow` defined |
| 6 | fullscreen | After `safeGetApplication` and `log`; remaining 15+ callbacks wired later |
| 7 | operations | After `tileWindows` and `drawActiveWindowOutline` assigned |
| 8 | gestures | Last; receives functions from operations |

Callback tables are passed by reference, so the orchestrator can add entries after `init()` and the module sees them.

---

## User Interface States

### Normal Tiling

The default state. All included windows are arranged automatically according to the active layout mode. Orientation follows the screen's aspect ratio: landscape screens tile side-by-side, portrait screens tile top-to-bottom.

**What the user sees:**

- Windows fill the screen edge-to-edge (minus any snapshot reserved area), separated by a configurable gap (default 0px).
- The focused window has a colored **outline border** (16px thick, rounded corners):
  - **Blue** -- window is included in tiling normally.
  - **Orange** -- window's app is excluded from tiling (floating).
  - **Purple** -- window is pseudo-tiled (keeps its own size, centered in tile slot).
- The outline color animates smoothly (150ms ease-out cubic) on state changes.
- **Button overlays** sit over the native macOS traffic light buttons for every tiled window:
  - **Close** (red position) -- hover highlights red.
  - **Minimize** (yellow position) -- hover highlights amber.
  - **Zoom** (green position) -- hover highlights green.
  - **Pin** (right of traffic lights, focused window only) -- orange when excluded, gray when included.
- Each overlay shows a **tooltip** on hover.

**How to enter:** Default state. Resumes automatically when exiting fullscreen or restoring all snapshots.

### Simulated Fullscreen

A single window fills the entire screen without a macOS Space transition.

**What the user sees:**

- The chosen window occupies the full screen frame.
- All other tiled windows on the same space disappear.
- The focus outline is hidden.
- Only Zoom and Minimize button overlays remain.

**How to enter:** Ctrl+Cmd+F, or click the Zoom button overlay.

**How to exit:** Ctrl+Cmd+F again, click Zoom overlay again, or focus any other window (auto-exits). Hidden windows are restored and re-tiled with their pre-fullscreen weights.

### Snapshots Visible

One or more windows have been custom-minimized to live-updating thumbnails.

**What the user sees:**

- **Landscape screens:** Thumbnails stack vertically in a 140px-wide column on the right edge. Tiling area shrinks accordingly.
- **Portrait screens:** Thumbnails line up horizontally along the bottom edge.
- Each thumbnail shows: dark rounded background, window screenshot (refreshed every 0.5s), red close dot (top-left), app icon (bottom-center).
- On hover: 110% zoom animation + tooltip (app name, window title).

**How to enter:** Click the Minimize button overlay, or use FrameMaster hot corner.

**How to exit:** Click a thumbnail to restore (animated). Context menu "Restore All" restores everything. When empty, the reserved area disappears.

### Collapsed Windows Present

Windows at or below 12px height are pulled out of the main layout.

- **Landscape:** distributed side-by-side in a row at the bottom, each 12px tall.
- **Portrait:** stacked vertically at the bottom, full width, 12px tall each.

**How to enter:** Resize any window's height to 12px or less. **How to exit:** Resize back above 12px.

### Pseudo-Tiled Windows

A window retains its own size and is centered within its tile slot.

- The pseudo-tiled window sits centered in its tile region, surrounded by empty space.
- Focus outline is purple.
- Other windows tile around its slot as if it were full-size.

**How to enter:** Ctrl+Cmd+P. **How to exit:** Ctrl+Cmd+P again.

---

## User Interactions

### Keyboard Shortcuts

All use **Ctrl+Cmd** modifier unless noted.

| Shortcut | Action |
|---|---|
| **,** | Toggle focused app in/out of tiling list |
| **Left** / **Right** | Move focused window backward/forward in tiling order |
| **Ctrl+Cmd+Option Left** / **Right** | Move focused window to previous/next screen |
| **0** | Reset all window weights to equal |
| **=** / **-** | Increase/decrease focused window's weight by 0.1 |
| **]** / **[** | Increase/decrease master ratio by 5% (master layout) |
| **F** | Toggle simulated fullscreen |
| **L** | Cycle layout: weighted -> dwindle -> master |
| **P** | Toggle pseudo-tiling for focused window |
| **R** | Force retile (resets stuck flags) |
| **A** | Toggle animations on/off |
| **D** | Toggle debug logging |

### Trackpad Gestures

"N+1" pattern: place N fingers, let them settle (150ms), then tap with one additional finger. The +1 finger's horizontal position (left/right half) determines direction. 500ms cooldown between gestures. Fingers moving beyond 15% of trackpad surface cancel the gesture.

| Base Fingers | +1 Left | +1 Right |
|---|---|---|
| 2 | Focus previous window | Focus next window |
| 3 | Move window backward in order | Move window forward |
| 4 | Move window to previous screen | Move to next screen |

### Mouse Interactions

#### Button Overlays

| Button | Hover | Click |
|---|---|---|
| **Close** (red position) | Red highlight + tooltip | Closes the window |
| **Minimize** (yellow position) | Amber highlight + tooltip | Creates a snapshot (custom minimize) |
| **Zoom** (green position) | Green highlight + tooltip | Toggles simulated fullscreen |
| **Pin** (focused window only) | Orange highlight + tooltip | Toggles app in/out of tiling list |

#### Snapshot Thumbnails

| Interaction | Behavior |
|---|---|
| **Hover** | 110% zoom animation + tooltip (app name, window title) |
| **Click body** | Restore window with animated expansion to original frame |
| **Click red dot** (top-left 20x20px) | Close window permanently, remove thumbnail |
| **Right-click** | Context menu: Restore, Close, Restore All, Close All |
| **Drag** (after 5px threshold) | Move thumbnail; if dropped on different screen, transfers snapshot there |
| **Mouse exit** | Zoom back to 100%, tooltip fades out (125ms) |

#### Window Border Dragging

| Interaction | Behavior |
|---|---|
| **Drag edge** (resize) | Size change > 20px triggers weight redistribution between resized window and its neighbor |
| **Drag to reposition** | After 0.3s settle, calculates drop position and reorders |
| **Cross-screen drag** | Detected via screen ID change; retiles both screens |

---

## State Management

All state is in-memory except for the app list, which is serialized to `WindowScape_apps.json`.

### Tiling State

| Variable | Type | Description |
|---|---|---|
| `windowOrderBySpace` | spaceId -> [windows] | Tiling order per Space. Preserved across retiles; newcomers appended. |
| `windowWeights` | winId -> float | Proportional size multiplier. Default 1.0, minimum 0.1. |
| `pseudoWindows` | winId -> {preferredW, preferredH} | Windows that maintain fixed preferred size. |
| `windowLastScreen` | winId -> screenId | Tracks which screen each window was last on (for cross-screen detection). |

### Focus and History

| Variable | Type | Description |
|---|---|---|
| `focusHistory` | [winIds] | Most-recent-first, capped at 10. Used to find focus target after minimize. |
| `lastKnownFocusedId` | winId | Deduplicates between focus handler and 0.1s backup poll. |

### Window Change Detection

| Variable | Type | Description |
|---|---|---|
| `lastKnownWindowIds` | set of winIds | Diffed against current set to identify new/removed windows. |
| `lastKnownWindowFrames` | winId -> {app, frame} | Used for tab switch detection (same app + similar frame = no retile). |

### Guard Flags

| Variable | Type | Description |
|---|---|---|
| `tilingCount` | 0 or 1 | While nonzero, same-screen windowMoved events are suppressed. Cross-screen moves bypass this. |
| `tilingStartTime` | timestamp | Watchdog resets `tilingCount` if stuck > 5s. |
| `windowSnapshots.isCreating` | bool | Blocks tiling and re-entrant snapshot creation. Watchdog resets after 5s. |

### App List Logic

`listedApps` maps bundleID or app name to `true`. Controlled by `cfg.exclusionMode`:

- **Exclusion mode** (default, `true`): Listed apps are **denied** tiling. All other standard windows are tiled.
- **Inclusion mode** (`false`): Only listed apps are **allowed** to tile.

A window must also pass `win:isStandard()` and must not be currently snapshotted.

---

## Event Handling Rules

1. **Window created / hidden / unhidden / minimized / unminimized.** Debounced at 0.2s. All events within the window collapse into a single retile. `windowsChanged` is deliberately excluded (fires on title changes like terminal tab switches).

2. **Tab switch detection.** If a new window and a removed window share the same app and their frame positions differ by less than 50 pixels total, the event is classified as a tab switch. No retile occurs.

3. **Window resize (same screen).** If actual size differs from expected size by > 20px, weight is redistributed between the resized window and its immediate neighbor on the dragged side. Both weights clamped to min 0.2.

4. **Window reposition (same screen).** If size difference is <= 20px, treated as a drag. A 0.3s timer fires, calculates drop index, and reorders if changed.

5. **Deferred events during tiling.** If `tilingCount > 0`, a deferred retry timer is set for after animation completion. Only one deferred event is tracked at a time.

6. **Cross-screen move.** Detected when `windowLastScreen[winId]` differs from current screen. Bypasses `tilingCount` guard. Resets tiling flags and schedules two retiles (20ms and 150ms) for both screens.

7. **Focus change.** Debounced at 0.05s. Updates `focusHistory`, redraws outline, refreshes overlays. Backup 0.1s poll catches missed events.

8. **Space switch.** Outline hidden immediately. `handleWindowEvent` called (not debounced) to rebuild window order for the new space.

9. **Screen configuration change.** Repositions all snapshot thumbnails, retiles, refreshes overlays.

10. **Watchdog (every 10s).** Resets `tilingCount` if stuck > 5s. Resets `isCreating` if stuck > 5s. Restarts focus poll and gesture eventtap if stopped. Prunes stale space entries and closed-window state.

11. **Native minimize interception.** Windows minimized to Dock are unminimized after 0.1s: focused, then retiled 0.2s later.

12. **Simulated fullscreen focus guard.** Focus on a different window auto-exits fullscreen.

13. **Window destroyed.** Prunes stale state immediately. Relies on natural `windowFocused` subscription for refocus (no manual focus to avoid flickering).

14. **Snapshot re-entrancy guard.** If `createSnapshot` called while `isCreating` is true, the call returns immediately. Watchdog provides 5s safety net.

---

## Configuration Reference

### Appearance

| Key | Default | Description |
|---|---|---|
| `outlineColor` | `{red=.1, green=.3, blue=.9, alpha=0.8}` | Focused tiled window border |
| `outlineColorPinned` | `{red=.9, green=.6, blue=.1, alpha=0.8}` | Excluded/floating window border |
| `outlineColorPseudo` | `{red=.6, green=.1, blue=.9, alpha=0.8}` | Pseudo-tiled window border |
| `outlineThickness` | `16` | Border width in pixels |
| `tileGap` | `0` | Gap between tiled windows in pixels |
| `collapsedWindowHeight` | `12` | Height threshold for collapsed windows |

### Layout

| Key | Default | Description |
|---|---|---|
| `layoutMode` | `"weighted"` | Active algorithm: `"weighted"`, `"dwindle"`, or `"master"` |
| `masterRatio` | `0.55` | Master pane fraction (0.1--0.9) |
| `masterPosition` | `"left"` | Master edge: `"left"`, `"right"`, `"top"`, `"bottom"` |
| `exclusionMode` | `true` | `true` = deny list, `false` = allow list |

### Animation

| Key | Default | Description |
|---|---|---|
| `enableAnimations` | `true` | Eased window transitions |
| `animationDuration` | `0.15` | Seconds per animation |
| `animationFPS` | `60` | Target frame rate |

### Input

| Key | Default | Description |
|---|---|---|
| `mods` | `{"ctrl", "cmd"}` | Modifier keys for window hotkeys |
| `screenMods` | `{"ctrl", "cmd", "option"}` | Modifier keys for cross-screen moves |
| `enableTTTaps` | `true` | Trackpad gesture recognition |

### Timing

| Key | Default | Description |
|---|---|---|
| `eventDebounceSeconds` | `0.2` | Debounce interval for window events |

### Debug

| Key | Default | Description |
|---|---|---|
| `debugLogging` | `true` | Print timestamped logs to console |

### Internal Constants (CONST)

| Key | Default | Description |
|---|---|---|
| `ANIMATION_STEPS` | `12` | Frames per snapshot animation |
| `ANIMATION_INTERVAL` | `0.016` | Seconds between animation frames |
| `OUTLINE_REFRESH_INTERVAL` | `0.016` | Outline position update frequency |
| `SNAPSHOT_ZOOM_SCALE` | `1.1` | Hover zoom multiplier |
| `SNAPSHOT_DRAG_THRESHOLD` | `5` | Pixels before drag starts |
| `SNAPSHOT_CLOSE_SIZE` | `20` | Close button hit area |
| `OVERLAY_PADDING` | `4` | Button overlay padding |

---

## Public API

All functions are on the returned module table unless marked **[global]**.

| Function | Returns | Description |
|---|---|---|
| `cleanup()` | -- | Stop all timers, clear overlays, stop gestures |
| `tileWindows()` | -- | Force immediate retile |
| `toggleFullscreen()` | `string` | Toggle simulated fullscreen; returns status message |
| `isFullscreen(win)` | `bool` | Test if window is in simulated fullscreen |
| `minimize()` | `string` | Snapshot focused window; returns status message |
| `isMinimized(win)` | `bool` | Test if window is snapshot-minimized |
| `cycleLayout()` | `string` | Cycle layout modes; returns new mode name |
| `getLayoutMode()` | `string` | Current layout mode |
| `setLayoutMode(mode)` | `bool` | Set layout mode by name |
| `getConfig()` | `table` | Reference to `cfg` table |
| `restartTTTaps()` | -- | Restart gesture recognizer |

### Global Shims (for FrameMaster)

| Global Function | Delegates To |
|---|---|
| `windowScapeToggleFullscreen()` | `toggleFullscreen()` |
| `windowScapeIsFullscreen(win)` | `isFullscreen(win)` |
| `windowScapeMinimize()` | `minimize()` |
| `windowScapeIsMinimized(win)` | `isMinimized(win)` |
| `cycleWindowScapeLayout()` | `cycleLayout()` |
| `restartWindowScapeTTTaps()` | `restartTTTaps()` |

---

## Integration Points

### FrameMaster

FrameMaster's `useWindowScape` flag redirects hot corner actions to WindowScape globals:
- Fullscreen hot corner calls `windowScapeToggleFullscreen()` instead of native fullscreen.
- Minimize hot corner calls `windowScapeMinimize()` instead of native minimize.
- Guard checks use `windowScapeIsFullscreen(win)` and `windowScapeIsMinimized(win)`.

Coupling is one-directional: FrameMaster depends on WindowScape globals; WindowScape has no knowledge of FrameMaster.

### macOS (via Hammerspoon)

| Mechanism | Purpose |
|---|---|
| `hs.window.filter` subscriptions | React to window creation, destruction, focus, movement, resize |
| `hs.spaces` watcher | Detect space changes; retile for new space |
| `hs.screen.watcher` | Detect display changes; reposition snapshots, retile |
| `hs.eventtap` (right-click) | Intercept right-clicks for snapshot context menus |
| `hs.eventtap` (gestures) | N+1 finger trackpad recognition |
| `hs.axuielement` | Query window button positions for overlays |

---

## Lifecycle

### Initialization (on `require`)

1. Sub-modules loaded: config, animation, outline, snapshots, layouts, fullscreen, gestures, operations.
2. Callback tables wired in two phases (early init + deferred after all functions defined).
3. App list read from `WindowScape_apps.json`.
4. Window filter subscriptions set up (with retry on failure).
5. Space watcher, screen watcher, right-click eventtap started.
6. Initial focus outline drawn; focus poll timer started.
7. Current window set recorded; first `tileWindows()` call.
8. Hotkeys bound; button overlays created.

### Runtime Timers

| Timer | Interval | Purpose |
|---|---|---|
| Overlay refresh | 0.5s | Redraw button overlays to track window changes |
| Focus poll | 0.1s | Catch focus changes missed by window filter |
| Watchdog | 10s | Reset stuck flags, restart stopped timers, prune stale state |

### Cleanup (on Hammerspoon reload)

1. Stop all periodic timers.
2. Delete all canvas overlays.
3. Stop eventtaps and gesture recognizer.
4. No state flush needed -- `WindowScape_apps.json` is written synchronously on every toggle.
