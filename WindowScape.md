---
name: WindowScape
version: 1.0.0
description: |
  Automatic window tiling manager for macOS via Hammerspoon. Arranges all eligible windows
  to fill the screen and keeps them arranged as windows open, close, move, or resize. Three
  layout modes (weighted, dwindle, master) with auto-orientation. Replaces native fullscreen
  and minimize with simulated versions that avoid Space transitions and the Dock. Per-window
  weight control, multi-monitor, multi-Space, trackpad gestures, custom button overlays, and
  snapshot-based minimize with live thumbnails.
---

# WindowScape: Automatic Window Tiling

Tiles windows automatically. Open a window — others shrink to make room. Close one — the rest
expand. Resize a border — the neighbor adjusts. Everything stays tiled, always.

Replaces macOS traffic light buttons, fullscreen, and minimize with its own system.

## Core Patterns

### 1. Get a new app tiling

Open the app. If it's not already tiling (default: everything tiles except Hammerspoon),
focus the window and press `Ctrl+Cmd+,` to toggle it into the tiling list.

### 2. Exclude an app from tiling

Focus the window. `Ctrl+Cmd+,` toggles it out. The outline turns orange to confirm it's
floating. The Pin button (right of traffic lights) also does this on click.

### 3. Adjust how much space a window gets

- `Ctrl+Cmd+=` — give it more space
- `Ctrl+Cmd+-` — give it less space
- Drag a window border — redistributes weight between the resized window and its neighbor
- `Ctrl+Cmd+0` — reset all windows to equal size

### 4. Rearrange window positions

- `Ctrl+Cmd+Left/Right` — swap focused window with its neighbor in the layout
- Drag a window and drop it between others — it reorders to the drop position

### 5. Go fullscreen (without macOS Spaces)

`Ctrl+Cmd+F` or click the green zoom overlay. The window fills the screen, everything
else hides. No Space animation. Exit: press `Ctrl+Cmd+F` again, click zoom again, or
just focus any other window — it auto-exits.

### 6. Minimize a window to a thumbnail

Click the yellow minimize overlay (or use FrameMaster hot corner). The window shrinks
into a live-updating thumbnail at the screen edge. Click the thumbnail to restore it.
Click the red dot on the thumbnail to close it permanently. Right-click for batch actions
(Restore All, Close All).

### 7. Work across monitors

Each screen tiles independently. Move the focused window between screens with
`Ctrl+Cmd+Option+Left/Right`. Dragging a window across screens works too — both screens
retile automatically. Snapshots track their screen and only take space there.

### 8. Switch layout modes

`Ctrl+Cmd+L` cycles: weighted → dwindle → master → weighted.

In master mode, `Ctrl+Cmd+]/[` adjusts the master pane ratio.

### 9. Use trackpad gestures

Place N fingers, let them settle, then tap with one more finger.

- 2+1 — focus previous/next window (left/right side of trackpad)
- 3+1 — move window backward/forward in order
- 4+1 — move window to previous/next screen

### 10. Lock a window's size (pseudo-tile)

`Ctrl+Cmd+P` — the window keeps its current dimensions and floats centered within its
tile slot instead of stretching to fill it. Outline turns purple. Other windows tile
around the slot as if it were full-size. Press again to release.

### 11. Recover from a stuck state

`Ctrl+Cmd+R` — force retile. Resets all internal flags and re-tiles everything. A
watchdog also auto-resets stuck states after 5 seconds.

## Visual States

| State | What you see | Enter | Exit |
|---|---|---|---|
| **Normal tiling** | Windows fill screen edge-to-edge, focused window has colored outline, button overlays on traffic lights | Default state | Enter fullscreen or minimize all |
| **Simulated fullscreen** | One window fills screen, others hidden, outline hidden | `Ctrl+Cmd+F` or zoom overlay | `Ctrl+Cmd+F`, zoom overlay, or focus another window |
| **Snapshots visible** | Thumbnails at screen edge (right column landscape, bottom row portrait), tiling area shrinks | Minimize overlay or hot corner | Click thumbnail to restore, or Restore All |
| **Collapsed windows** | Windows ≤12px tall stacked in strip at bottom of screen | Resize a window to ≤12px | Resize back above 12px |
| **Pseudo-tiled** | Window centered in tile slot at its own size, purple outline | `Ctrl+Cmd+P` | `Ctrl+Cmd+P` again |

## Focus Outline

Thick colored border on the focused window. Tracks the window in real time. Hides during
Space switches.

| Color | Meaning |
|---|---|
| Blue | Normal tiled window |
| Orange | App excluded from tiling (floating) |
| Purple | Pseudo-tiled window |

## Button Overlays

Invisible click targets over the macOS traffic light buttons. Present on every tiled window.
Highlight and show a tooltip on hover.

| Position | Click action |
|---|---|
| Red (close) | Closes the window |
| Yellow (minimize) | Creates a snapshot thumbnail |
| Green (zoom) | Toggles simulated fullscreen |
| Pin (focused window only, right of traffic lights) | Toggles app in/out of tiling list. Orange = excluded, gray = included |

## Snapshot Thumbnails

Minimized windows become live-updating thumbnails at the screen edge.

**Placement:** Right column on landscape screens. Bottom row on portrait screens.

**Appearance:** Dark rounded background, window screenshot (refreshes periodically), red
close dot top-left, app icon bottom-center.

| Interaction | Result |
|---|---|
| Click body | Restore window (animated expansion to original position) |
| Click red dot (top-left) | Close window permanently, remove thumbnail |
| Right-click | Context menu: Restore, Close, Restore All, Close All |
| Hover | Slight zoom + tooltip (app name, window title) |
| Drag to another screen | Transfer snapshot and restore target to that screen |
| Mouse exit | Zoom back, tooltip fades out |

Native macOS minimize is intercepted — windows minimized to Dock are automatically
unminimized and handled through snapshots instead.

## Layout Modes

| Mode | Behavior |
|---|---|
| **Weighted** (default) | Each window gets screen space proportional to its weight. All start at 1.0 |
| **Dwindle** | Recursively splits screen in half per window — spiral pattern |
| **Master** | One large master pane + equal-split stack for the rest. Ratio adjustable |

All modes auto-orient: landscape tiles left-to-right, portrait tiles top-to-bottom.

Collapsed windows (≤12px) are always pulled out of the main layout and stacked in a strip
at the bottom regardless of layout mode.

## Keyboard Shortcuts

All use **Ctrl+Cmd** unless noted.

| Key | Action |
|---|---|
| **,** | Toggle focused app in/out of tiling list |
| **Left** / **Right** | Move window backward/forward in tiling order |
| **Option+Left** / **Option+Right** | Move window to previous/next screen |
| **0** | Reset all weights to equal |
| **=** / **-** | Increase/decrease focused window's weight |
| **]** / **[** | Increase/decrease master ratio |
| **F** | Toggle simulated fullscreen |
| **L** | Cycle layout: weighted → dwindle → master |
| **P** | Toggle pseudo-tiling |
| **R** | Force retile (reset stuck state) |
| **A** | Toggle animations |
| **D** | Toggle debug logging |

## Trackpad Gestures

N+1 pattern: hold N fingers, settle briefly, tap with one more. Left/right side of
trackpad determines direction.

| Base fingers | +1 left | +1 right |
|---|---|---|
| 2 | Focus previous window | Focus next window |
| 3 | Move window backward in order | Move window forward |
| 4 | Move window to previous screen | Move to next screen |

Movement beyond a small threshold cancels the gesture (so normal trackpad use is unaffected).

## Mouse Interactions

| Action | System response |
|---|---|
| Drag window border (resize) | Redistributes weight between that window and its neighbor |
| Drag window to new position | After settling, reorders to drop position |
| Drag window to another screen | Retiles both source and destination screens |
| Click button overlay | See Button Overlays section |
| Click/drag/right-click snapshot | See Snapshot Thumbnails section |

## Automatic Behaviors

Things WindowScape does on its own without user input:

| Event | Response |
|---|---|
| Window opened or closed | Retile (debounced to absorb bursts) |
| Tab switch (browser/terminal) | Detected and ignored — no retile |
| Window moved to different screen | Retile both screens immediately |
| Focus changed | Outline follows the new focused window |
| Space switched | Outline hides, layout rebuilds for new Space |
| Screen connected/disconnected/resolution change | Reposition snapshots, retile |
| Stuck state (tiling didn't finish) | Auto-reset after 5 seconds |
| Window minimized to Dock | Unminimized, handled via snapshot system instead |
| Focus lost during simulated fullscreen | Auto-exit fullscreen, restore all hidden windows |

## Multi-Monitor

Each screen tiles independently based on its own active Space. Snapshots are per-screen
and only reserve space on their screen. Moving a window between screens (keyboard or drag)
retiles both screens.

## Multi-Space

Each Space has its own window order. Switching Spaces rebuilds the layout for that Space.
Stale Space data is cleaned up periodically.

## External Integration

WindowScape exposes functions for other Hammerspoon modules:

- Toggle/check simulated fullscreen for a window
- Minimize (snapshot) / check if minimized for a window
- Cycle or set layout mode
- Force retile

FrameMaster uses these to wire hot corner actions to WindowScape's fullscreen and snapshot
minimize instead of the native macOS equivalents.

## App List

Persisted to `WindowScape_apps.json`. By default operates as a **deny list** — listed apps
are excluded from tiling, everything else tiles. Can be flipped to allow list via config.
Hammerspoon itself excluded by default. Standard windows only (no dialogs, system panels).
