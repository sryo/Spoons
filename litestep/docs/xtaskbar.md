# xTaskbar v2.3.4

**Author:** The LS-Universe Team  
**Requirements:** xPaintClass, xStatsClass (optional)

## Description

xTaskbar is a highly configurable taskbar module for LiteStep. It displays running applications as customizable buttons with multiple visual states (normal, active, minimized, flashing, hover, pressed, grouped). Supports skinning via xPaintClass, task grouping, filtering, drag-and-drop, and extensive event handling.

> [!IMPORTANT]
> Load xPaintClass before xTaskbar!

## Installation

```ini
LoadModule "$LiteStepDir$xPaintClass-1.0.dll"
LoadModule "$LiteStepDir$xTaskbar-2.3.dll"
```

## Creating Taskbars

```ini
*xTaskbar MyTaskbar
```

Multiple taskbars can be created with different configurations.

---

## RC Variables

All settings are prefixed with the taskbar name (e.g., `MyTaskbarX`).

### Position & Size

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>X` | coord | 0 | X position. |
| `<Name>Y` | coord | 0 | Y position. |
| `<Name>Width` | dim | - | Taskbar width. |
| `<Name>Height` | dim | - | Taskbar height. |
| `<Name>LoadInBox` | bool | false | Wait for `!xTaskbarLSBoxHook`. |

### Layout

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>Layout` | enum | horizontal | `horizontal` or `vertical`. |
| `<Name>Direction` | enum | right | Button flow: `right`, `left`, `down`, `up`. |
| `<Name>WrapDirection` | enum | down | Wrap direction: `down`, `up`, `right`, `left`. |
| `<Name>WrapCount` | int | -1 | Buttons per row/column before wrap (-1=auto). |
| `<Name>Lines` | int | 1 | Initial number of rows/columns. |
| `<Name>MaxLines` | int | 100 | Maximum rows/columns. |
| `<Name>MaxButtonCount` | int | 0 | Maximum buttons to display (0=unlimited). |

### Borders & Spacing

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>Borders` | rect | 0 0 0 0 | Padding (Left Top Right Bottom). |
| `<Name>LeftBorder` | int | 0 | Left border. |
| `<Name>TopBorder` | int | 0 | Top border. |
| `<Name>RightBorder` | int | 0 | Right border. |
| `<Name>BottomBorder` | int | 0 | Bottom border. |
| `<Name>xSpacing` | int | 0 | Horizontal spacing between buttons. |
| `<Name>ySpacing` | int | 0 | Vertical spacing between buttons. |

### Button Size

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>MaxTaskWidth` | int | - | Maximum button width. |
| `<Name>MaxTaskHeight` | int | - | Maximum button height. |
| `<Name>UseAdaptiveSize` | bool | false | Auto-size buttons to fit. |

### Auto-Size

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>AutoSize` | bool | false | Auto-resize taskbar based on content. |
| `<Name>MaxTaskbarSize` | int | - | Maximum taskbar size for auto-sizing. |
| `<Name>AutoSizeDelay` | int | - | Animation delay (ms). |
| `<Name>AutoSizeSteps` | int | - | Animation steps. |

### Window Behavior

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>StartHidden` | bool | false | Start hidden. |
| `<Name>AlwaysOnTop` | bool | false | Stay above other windows. |
| `<Name>WindowzOrder` | bool | false | Use normal window Z-order. |
| `<Name>BehindWindow` | string | - | Window class to stay behind. |
| `<Name>FocusOnEnter` | bool | false | Focus taskbar on mouse enter. |
| `<Name>HideIfEmpty` | bool | false | Hide when no tasks. |

### Transparency

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>TrueTransparency` | bool | false | Enable per-pixel alpha. |
| `<Name>AlphaTransparency` | int | 255 | Opacity (0-255). |
| `<Name>AlphaMap` | bool | false | Use image alpha channel. |
| `<Name>AlphaFade` | bool | false | Enable fade effects. |

### Display Options

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>ShowIcon` | bool | true | Show task icons. |
| `<Name>ShowText` | bool | true | Show task titles. |
| `<Name>DisplayButtonType` | enum | all | Filter: `all`, `normal`, `minimized`, `active`. |
| `<Name>NoMinimizeOnClick` | bool | false | Don't minimize active task on click. |

### Button States

Each button has 7 visual states: Normal, Active, Minimized, Flashing, Hover, Pressed, Grouped.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>UseHoverState` | bool | false | Enable hover styling. |
| `<Name>UsePressedState` | bool | false | Enable pressed styling. |
| `<Name>UseFlashingState` | bool | true | Enable flashing for attention. |
| `<Name>UseGrouping` | bool | false | Enable task grouping. |
| `<Name>SpecialHoverState` | int | - | Special hover behavior. |

### Icon Settings (Per State)

Replace `<State>` with: (empty), `Active`, `Minimized`, `Flashing`, `Hover`, `Pressed`, `Grouped`.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name><State>UseBigIcon` | bool | false | Use large (32px) icon. |
| `<Name>Use<State>IconSettings` | bool | false | Use state-specific icon styling. |

All xPaintIcon settings apply with prefix `<Name><State>Icon`:
- `<Name>IconSize`, `<Name>IconX`, `<Name>IconY`
- `<Name>IconAlphaTransparency`, `<Name>IconHueColor`, etc.

### Text Settings (Per State)

All xPaintText settings apply with prefix `<Name><State>Font`:
- `<Name>Font`, `<Name>FontHeight`, `<Name>FontColor`
- `<Name>FontShadow`, `<Name>FontOutline`, etc.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>Use<State>FontSettings` | bool | false | Use state-specific text styling. |
| `<Name><State>Text` | string | - | Custom text format for state. |
| `<Name>MultiLineUsed` | bool | false | Enable multi-line text. |

### Texture Settings (Per State)

All xPaintTexture settings apply with prefix `<Name><State>`:
- `<Name>PaintingMode`, `<Name>Image`
- `<Name>TextureX`, `<Name>TextureWidth`, etc.

For button textures, use: `<Name><State>Button` prefix (e.g., `MyTaskbarActiveButtonImage`).

### Scrolling

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>Scroll` | bool | false | Enable text scrolling. |
| `<Name>ScrollSpeed` | int | 1 | Scroll pixels per step. |
| `<Name>ScrollRefresh` | int | 100 | Scroll interval (ms). |
| `<Name>ScrollPadLength` | int | - | Padding at scroll ends. |

### Sorting

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>AutoSort` | enum | 0 | Sort mode. |

**Sort Modes:**
| Value | Description |
|-------|-------------|
| 0 | No sorting (order of creation). |
| 1 | Sort by executable name + title. |
| 2 | Sort by window class + title. |
| 3 | Sort by title only. |

### Timers & Refresh

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>TimerRefresh` | int | 250 | Update interval (ms). |
| `<Name>TrackingRefresh` | int | 50 | Mouse tracking interval (ms). |
| `<Name>FlashRefresh` | int | 500 | Flash toggle interval (ms). |
| `<Name>DropTimeOut` | int | - | Drag-drop timeout (ms). |

### Tooltips

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>ShowToolTip` | bool | true | Enable tooltips. |
| `<Name>TooltipMode` | int | 0 | Tooltip style (0=native, 1+=custom). |

All xPaintTooltip settings apply.

### VWM Integration

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>VWMCurrentDesktopOnly` | bool | false | Show only current desktop tasks. |
| `<Name>VWMSpecifiedDesktopOnly` | int | -1 | Show only tasks from specific desktop. |

### Multi-Monitor

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Name>ThisMultiMonitorOnly` | int | -1 | Show tasks from specific monitor only. |

---

## Task Filtering

### Add/Remove Tasks

| Directive | Description |
|-----------|-------------|
| `*<Name>Add "text"` | Add tasks matching text. |
| `*<Name>Remove "text"` | Remove/hide tasks matching text. |
| `*<Name>AddMatching "pattern"` | Add tasks matching pattern. |
| `*<Name>RemoveMatching "pattern"` | Remove tasks matching pattern. |

### Custom Icons

| Directive | Description |
|-----------|-------------|
| `*<Name>CustomIcon "text" "iconpath" [index]` | Custom icon for matching tasks. |
| `*<Name>ChangingIcon "text" "iconpath" [index]` | Dynamic icon replacement. |

---

## Overlays

Both taskbar and button overlays are supported using xPaintClass.

```ini
*MyTaskbarOverlayTaskbar X Y W H ...   ; Overlay on taskbar
*MyTaskbarOverlayButton X Y W H ...    ; Overlay on each button
```

---

## Events

| Variable | Type | Description |
|----------|------|-------------|
| `<Name>OnLeftClickDown` | action | Left mouse down on taskbar. |
| `<Name>OnLeftClickUp` | action | Left mouse up on taskbar. |
| `<Name>OnRightClickDown` | action | Right mouse down. |
| `<Name>OnRightClickUp` | action | Right mouse up. |
| `<Name>OnMiddleClickDown` | action | Middle mouse down. |
| `<Name>OnMiddleClickUp` | action | Middle mouse up. |
| `<Name>OnWheelUp` | action | Mouse wheel up. |
| `<Name>OnWheelDown` | action | Mouse wheel down. |
| `<Name>OnEnter` | action | Mouse enters taskbar. |
| `<Name>OnLeave` | action | Mouse leaves taskbar. |
| `<Name>OnAdd` | action | Task added. |
| `<Name>OnRemove` | action | Task removed. |
| `<Name>OnMove` | action | Taskbar moved. |
| `<Name>OnResize` | action | Taskbar resized. |
| `<Name>OnFlash` | action | Task flashes. |
| `<Name>OnSelect` | action | Task selected. |
| `<Name>OnLineAdd` | action | Row/column added. |
| `<Name>OnLineRemove` | action | Row/column removed. |
| `<Name>OnEmpty` | action | Last task removed. |
| `<Name>OnFilled` | action | First task added. |

---

## Bang Commands

| Command | Parameters | Description |
|---------|------------|-------------|
| `!xTaskbarShow` | `"Name"` | Show taskbar. |
| `!xTaskbarHide` | `"Name"` | Hide taskbar. |
| `!xTaskbarToggle` | `"Name"` | Toggle visibility. |
| `!xTaskbarDisplay` | `"Name"` | Show taskbar (alias). |
| `!xTaskbarAlwaysOnTop` | `"Name" bool` | Set always-on-top. |
| `!xTaskbarMove` | `"Name" x y [steps] [time]` | Move to position. |
| `!xTaskbarMoveBy` | `"Name" dx dy [steps] [time]` | Move by offset. |
| `!xTaskbarResize` | `"Name" w h [steps] [time]` | Resize. |
| `!xTaskbarResizeBy` | `"Name" dw dh [steps] [time]` | Resize by offset. |
| `!xTaskbarReposition` | `"Name" x y w h [steps] [time]` | Move and resize. |
| `!xTaskbarRepositionBy` | `"Name" dx dy dw dh [steps] [time]` | Move and resize by offset. |
| `!xTaskbarRefresh` | `"Name" [setting] [value]` | Refresh or update setting. |
| `!xTaskbarSetAlpha` | `"Name" value [step] [delay]` | Set transparency. |
| `!xTaskbarCreate` | `"Name"` | Create taskbar dynamically. |
| `!xTaskbarDestroy` | `"Name"` | Destroy taskbar. |
| `!xTaskbarLSBoxHook` | `"Name" hwnd` | Hook into LSBox. |
| `!xTaskbarSwitchTo` | `"Name" next\|prev` | Switch to next/previous task. |
| `!xTaskbarScrollButtons` | `"Name" next\|prev [amount]` | Scroll button list. |
| `!xTaskbarMinimizeAll` | - | Minimize all windows. |
| `!xTaskbarRestoreAll` | - | Restore all windows. |
| `!xTaskbarCascadeAll` | - | Cascade all windows. |
| `!xTaskbarTileAll` | - | Tile all windows. |

---

## Evars

| Variable | Description |
|----------|-------------|
| `$xTaskbarCurrentHWND$` | HWND of taskbar window. |
| `$xTaskbarCurrentButtonCount$` | Number of buttons. |
| `$xTaskbarCurrentLines$` | Number of rows/columns. |
| `$xTaskbarHoverTask$` | Caption of hovered task. |
| `$xTaskbarCurrentX$` | Current X position. |
| `$xTaskbarCurrentY$` | Current Y position. |
| `$xTaskbarCurrentWidth$` | Current width. |
| `$xTaskbarCurrentHeight$` | Current height. |
| `$xTaskbarCurrentButtonWidth$` | Button width. |
| `$xTaskbarCurrentButtonHeight$` | Button height. |

---

## Example Configuration

```ini
LoadModule "$LiteStepDir$xPaintClass-1.0.dll"
LoadModule "$LiteStepDir$xTaskbar-2.3.dll"

*xTaskbar MainTasks

; Position & Size
MainTasksX 0
MainTasksY -32
MainTasksWidth 100%
MainTasksHeight 32

; Layout
MainTasksLayout horizontal
MainTasksDirection right
MainTasksBorders 4 2 4 2
MainTasksxSpacing 2

; Button Appearance
MainTasksMaxTaskWidth 150
MainTasksMaxTaskHeight 28
MainTasksShowIcon true
MainTasksShowText true

; Background
MainTasksPaintingMode .image
MainTasksImage "$ThemeDir$taskbar_bg.png"

; Button States
MainTasksUseHoverState true
MainTasksUsePressedState true

; Normal Button
MainTasksButtonPaintingMode .image
MainTasksButtonImage "$ThemeDir$button_normal.png"
MainTasksFont "Segoe UI"
MainTasksFontHeight 12
MainTasksFontColor FFFFFF

; Active Button
MainTasksActiveButtonImage "$ThemeDir$button_active.png"
MainTasksActiveFontColor 00AAFF

; Hover Button
MainTasksHoverButtonImage "$ThemeDir$button_hover.png"

; Icon Settings
MainTasksIconSize 16
MainTasksIconX 4
MainTasksIconY 6

; Tooltip
MainTasksShowToolTip true

; Filtering
*MainTasksRemove "Program Manager"
*MainTasksRemove "LiteStep"

; Events
MainTasksOnEnter !xTaskbarSetAlpha "MainTasks" 255
MainTasksOnLeave !xTaskbarSetAlpha "MainTasks" 200
```

---

## Notes

- Multiple taskbars can coexist with different configurations
- All xPaintClass settings (texture, text, icon) are supported per state
- Overlay conditionals require xStatsClass
- Supports drag-and-drop for task reordering
- VWM integration for virtual desktop filtering
