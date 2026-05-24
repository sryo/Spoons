---
name: FrameMaster
version: 1.0.0
description: |
  Hot corners, menu bar blocking, and dock blocking for macOS via Hammerspoon. Move the mouse
  to any screen corner to close/quit windows, toggle fullscreen, minimize, or launch apps.
  Blocks menu bar and dock from appearing on mouse hover. Shift-modifies every corner action
  for an alternate behavior. Integrates with WindowScape for simulated fullscreen and snapshot
  minimize when available.
---

# FrameMaster: Hot Corners & Screen Edge Control

Mouse to a corner, click. That's it. Each corner does something different. Hold Shift for
the alternate action. Menu bar and dock are blocked from appearing unless you hold Shift.

## Corner Map

```
┌─────────────────────────────────────────────────┐
│  TOP-LEFT                           TOP-RIGHT   │
│  Click: Close window                Click: Fullscreen
│  Shift+Click: Force-kill app        Shift+Click: Zoom
│                                                  │
│  (menu bar blocked along top edge)               │
│                                                  │
│                                                  │
│  (dock blocked along configured edge)            │
│                                                  │
│  BOTTOM-LEFT                      BOTTOM-RIGHT   │
│  Click: Open Finder               Click: Minimize │
│  Shift+Click: System Preferences  Shift+Click: Hide app
└─────────────────────────────────────────────────┘
```

## Corner Actions

### Top-Left: Close / Quit / Kill

| Modifier | Behavior |
|----------|----------|
| Click | Sends Cmd+W to close the focused window. If it was the app's last visible window, quits the app and focuses the next window. |
| Shift+Click | Force-kills the app (kill9). Shows a 5-second reopen dialog: "You just killed [App]. Would you like to reopen it?" Auto-dismisses if ignored. |

### Top-Right: Fullscreen / Zoom

| Modifier | Behavior |
|----------|----------|
| Click | Toggles fullscreen. With WindowScape enabled: simulated fullscreen (no Space transition). Without: sends Ctrl+Cmd+F. |
| Shift+Click | Toggles macOS window zoom (fills screen without entering fullscreen). |

### Bottom-Right: Minimize / Hide

| Modifier | Behavior |
|----------|----------|
| Click | Minimizes the focused window. With WindowScape enabled: snapshot minimize (live thumbnail at screen edge). Without: native minimize to Dock. |
| Shift+Click | Hides the entire app (all windows). |

### Bottom-Left: Finder / System Preferences

| Modifier | Behavior |
|----------|----------|
| Click | Opens or focuses Finder. |
| Shift+Click | Opens or focuses System Preferences. |

## Tooltips

When the mouse enters a corner, a tooltip appears showing what will happen on click.
The tooltip updates live when you press or release Shift. Fades out after 0.75 seconds
or when the mouse leaves the corner.

- Tooltips are positioned at the corner's edge of the screen.
- Long messages are truncated with middle ellipsis at 50 characters.

No action fires on corners when the Desktop is focused (no accidental triggers).

## Menu Bar Blocking

Mouse movement toward the top edge of the screen is consumed, preventing the menu bar
from appearing. The blocking zone is the top edge minus the corner areas.

- Hold **Shift** to temporarily allow menu bar access.
- Corners are excluded so hot corner actions still work.

## Dock Blocking

Mouse movement toward the dock's edge is consumed, preventing the dock from appearing.
The dock position (bottom, left, or right) is auto-detected at startup.

- Hold **Shift** to temporarily allow dock access.
- Corners are excluded so hot corner actions still work.

## WindowScape Integration

When `useWindowScape = true` (default) and WindowScape is loaded:

| Action | Without WindowScape | With WindowScape |
|--------|--------------------|--------------------|
| Top-right click (fullscreen) | Sends Ctrl+Cmd+F | Calls simulated fullscreen (no Space transition, auto-exits on focus change) |
| Bottom-right click (minimize) | Native minimize to Dock | Snapshot minimize (live thumbnail at screen edge, click to restore) |
| Top-right tooltip | Always "Toggle Fullscreen" | Shows "Exit Fullscreen" when already in simulated fullscreen |

If WindowScape is not loaded, falls back to native behavior automatically.

## Configuration

All settings are variables at the top of the file.

| Setting | Default | Description |
|---------|---------|-------------|
| `killMenu` | `true` | Block menu bar from appearing on mouse hover |
| `killDock` | `true` | Block dock from appearing on mouse hover |
| `onlyFullscreen` | `false` | Only block menu/dock when a fullscreen window is focused |
| `buffer` | `4` | Pixel size of corner detection zone and edge blocking zone. Increase if corners or edges are hard to trigger. |
| `showTooltips` | `true` | Show corner action tooltips on hover |
| `tooltipMaxLength` | `50` | Maximum tooltip text length before middle-truncation |
| `reopenAfterKill` | `true` | Show reopen dialog after force-killing an app |
| `tooltipMargin` | `0` | Extra spacing between tooltip and screen edge |
| `useWindowScape` | `true` | Use WindowScape's simulated fullscreen and snapshot minimize |

## Edge Cases

- **Desktop focused:** All corner actions return "No action" — no accidental closes or minimizes.
- **Fullscreen window + bottom-right:** Minimize is blocked (returns "No action").
- **No focused window + top-left:** Falls through to quit the frontmost app.
- **Shift held:** Menu bar and dock blocking are temporarily disabled.
- **After force-kill:** Focus automatically moves to the next window in the stack.
- **After close with no remaining windows:** App quits and focus moves to the next window after 0.5 seconds.
