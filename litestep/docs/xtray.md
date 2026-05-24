# xTray v2.4.1

**Author:** The LS-Universe Team
**Source:** `sources/xtray-2.2.2-xsc-xpc-src/xTray.cpp` & `Tray.cpp`

## Description

Replacement system tray with xPaintClass skinning, per-icon overlays, alpha/transparency, custom ordering/hiding, and animation support. It supports conditional painting features via integration with xStatsClass.

## Configuration

Settings are generally prefixed with `<Tray>`.

### General Settings

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Tray>`X | coord | 0 | X position. |
| `<Tray>`Y | coord | 0 | Y position. |
| `<Tray>`Width | dim | - | Width. |
| `<Tray>`Height | dim | - | Height. |
| `<Tray>`LoadInBox | bool | false | If true, waits for `!xTrayLSBoxHook`. |
| `<Tray>`Layout | enum | horizontal | `horizontal`, `vertical`. |
| `<Tray>`Direction | enum | right | `right`, `left`, `bottom`, `top`. |
| `<Tray>`WrapDirection | enum | bottom | `bottom`, `top`, `right`, `left`. |
| `<Tray>`WrapCount | int | -1 | Icons per row/col before wrapping. |
| `<Tray>`Lines | int | 1 | Initial lines/rows. |
| `<Tray>`MaxLines | int | 100 | Maximum lines/rows. |
| `<Tray>`xSpacing | int | 0 | Horizontal spacing between icons. |
| `<Tray>`ySpacing | int | 0 | Vertical spacing between icons. |
| `<Tray>`Borders | int(s) | - | Borders (Left Top Right Bottom). |
| `<Tray>`LeftBorder | int | 0 | Left border. |
| `<Tray>`TopBorder | int | 0 | Top border. |
| `<Tray>`RightBorder | int | 0 | Right border. |
| `<Tray>`BottomBorder | int | 0 | Bottom border. |
| `<Tray>`Moveable | bool | false | Allow dragging. |
| `<Tray>`DisableDragnDrop | bool | false | Disable dragging icons out. |
| `<Tray>`HideIfEmpty | bool | false | Hide tray if no icons. |
| `<Tray>`LoopIcons | bool | false | Loop icons when scrolling. |
| `<Tray>`StartHidden | bool | false | Start hidden. |
| `<Tray>`FocusOnEnter | bool | false | Focus on mouse enter. |
| `<Tray>`CleanUpInterval | int | 10000 | Cleanup interval in ms. |
| `<Tray>`AlwaysFireClickEvents | bool | false | Fire click events even if handled. |
| `<Tray>`TrueTransparency | bool | false | Use background copying. |
| `<Tray>`AlphaTransparency | int | 255 | Alpha value (0-255). |
| `<Tray>`AlphaMap | bool | false | Use per-pixel alpha (xPaintClass). |
| `<Tray>`AlphaFade | bool | false | Enable alpha fading. |
| `<Tray>`CustomAlphaFade | string | - | "Step Delay" for fade. |
| `<Tray>`WindowzOrder | bool | false | Use normal window Z-order. |
| `<Tray>`BehindWindow | string | - | Window to stay behind. |
| `<Tray>`AlwaysOnTop | bool | false | Always on top. |
| `<Tray>`ShowTooltip | bool | true | Show tooltips. |
| `<Tray>`ToolTipColor | color | - | Tooltip background color. |
| `<Tray>`ToolTipTextColor | color | - | Tooltip text color. |
| `<Tray>`ShowInfoTip | bool | false | Show balloon tips. |
| `<Tray>`OnInfoTip | command | - | Command on info tip combined with balloon tip click. |
| `<Tray>`AutoSize | string | "0 0" | "Steps Delay" for auto-size animation. |
| `<Tray>`ButtonSize | int | (icon size) | Force specific button/icon size (default is max icon size). |

### Events

| Variable | Type | Description |
|----------|------|-------------|
| `<Tray>`OnLeftClickUp | command | Left click up. |
| `<Tray>`OnLeftClickDown | command | Left click down. |
| `<Tray>`OnMiddleClickUp | command | Middle click up. |
| `<Tray>`OnMiddleClickDown | command | Middle click down. |
| `<Tray>`OnRightClickUp | command | Right click up. |
| `<Tray>`OnRightClickDown | command | Right click down. |
| `<Tray>`OnWheelUp | command | Mouse wheel up. |
| `<Tray>`OnWheelDown | command | Mouse wheel down. |
| `<Tray>`OnEnter | command | Mouse enter. |
| `<Tray>`OnLeave | command | Mouse leave. |
| `<Tray>`OnMove | command | Window moved. |
| `<Tray>`OnResize | command | Window resized. |
| `<Tray>`OnAdd | command | Icon added. |
| `<Tray>`OnRemove | command | Icon removed. |
| `<Tray>`OnShow | command | Window shown. |
| `<Tray>`OnHide | command | Window hidden. |
| `<Tray>`OnLineAdd | command | Line added. |
| `<Tray>`OnLineRemove | command | Line removed. |
| `<Tray>`OnIconHide | command | Icon hidden. |
| `<Tray>`OnIconUnHide | command | Icon unhidden. |

### Directives

| Directive | Format | Description |
|-----------|--------|-------------|
| `*xTrayHide` | `<class> [title]` | Hide matching icons. |
| `*xTrayNoDragNDrop` | `<class> [title]` | Disable drag/drop for matching icons. |
| `*xTrayPosition` | `<slot> <class> [title]` | Force icon position (Slot 0 is first). |
| `*xTrayOverlayTray` | `X Y W H Name [Mode] [Cond]` | Add overlay to the tray background. |
| `*xTrayOverlayButton` | `X Y W H Name [Mode] [Cond]` | Add overlay to **each icon/button**. |

**Overlay Details:**
*   `Name`: Valid xPaintClass config name.
*   `Mode`: Combination of `a` (alpha map), `t` (always on top).
*   `Cond`: Optional conditional string (needs xStatsClass).
*   For `*xTrayOverlayButton`, the code looks for textures named: `NameNormalButton`, `NameHoverButton`, `NameHiddenButton`.

## Bang Commands

| Command | Description |
|---------|-------------|
| `!xTrayAlwaysOnTop <on/off/toggle>` | Set always on top. |
| `!xTrayHide` | Hide tray. |
| `!xTrayLSBoxHook <hwnd>` | Hook into LSBox. |
| `!xTrayMove <x> <y> [steps] [time]` | Move tray. |
| `!xTrayMoveBy <dx> <dy> [steps] [time]` | Move tray relative. |
| `!xTrayRefresh <setting> <value>` | Refresh setting. |
| `!xTrayReposition <x> <y> <w> <h> [steps] [time]` | Reposition tray. |
| `!xTrayRepositionBy <dx> <dy> <dw> <dh> [steps] [time]` | Reposition tray relative. |
| `!xTrayResize <w> <h> [steps] [time]` | Resize tray. |
| `!xTrayResizeBy <dw> <dh> [steps] [time]` | Resize tray relative. |
| `!xTrayScrollIcons <next/prev> [amount]` | Scroll icons. |
| `!xTraySetAlpha <value> [step] [delay]` | Set alpha transparency. |
| `!xTrayShow` | Show tray. |
| `!xTrayToggle` | Toggle visibility. |
| `!xTrayToggleHiddenIcons` | Toggle hidden icons. |
