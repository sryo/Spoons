# xPopup

**xPopup** is an advanced popup menu module for LiteStep that provides customizable context menus with extensive features including dynamic folders, shell integration, transparency effects, and rich visual customization options.

## Installation

Load the module in your step.rc:
```
*LoadModule xPopup-2.1.dll
```
- **!PopupTasks** - Show running tasks popup
- **!PopupControlPanel** - Show Control Panel items
- **!PopupMyComputer** - Show My Computer contents
- **!PopupNetwork** - Show Network Neighborhood
- **!PopupPrinters** - Show installed printers
- **!PopupRecentDocuments** - Show recent documents
- **!PopupRecycleBin** - Show Recycle Bin contents

### Per-Popup Commands
Each popup also has specific commands:
- **!<PopupName>Reposition** - Reposition the popup
- **!<PopupName>Pin** - Pin popup to desktop
- **!<PopupName>UnPin** - Unpin popup from desktop
- **!<PopupName>TogglePin** - Toggle pin state
- **!<PopupName>ToggleShade** - Toggle shaded state
- **!<PopupName>Toggle** - Toggle popup visibility

## RC Variables

### Position and Size
- **X** (int, default: 0) - X position of the popup
- **Y** (int, default: 0) - Y position of the popup
- **MaxWidth** (int, default: screen width) - Maximum popup width
- **MaxHeight** (int, default: screen height) - Maximum popup height
- **MinWidth** (int, default: 0) - Minimum popup width
- **MinHeight** (int, default: borders) - Minimum popup height
- **MaxEntryWidth** (int, default: screen width) - Maximum entry width
- **MinEntryWidth** (int, default: 0) - Minimum entry width
- **WorkArea** (string, default: "") - Custom work area definition

### Borders and Spacing
- **LeftBorder** (int, default: 0) - Left border width
- **TopBorder** (int, default: 0) - Top border height
- **RightBorder** (int, default: 0) - Right border width
- **BottomBorder** (int, default: 0) - Bottom border height
- **OverlapX** (int, default: 0) - Horizontal overlap for sub-popups
- **OverlapY** (int, default: -TopBorder) - Vertical overlap for sub-popups
- **xSpacing** (int, default: 0) - Horizontal spacing between entries
- **ySpacing** (int, default: 0) - Vertical spacing between entries
- **SeparatorySpacing** (int, default: 0) - Vertical spacing for separators

### Entry Heights
- **EntryHeight** (int, default: 18) - Height of standard entries
- **FolderHeight** (int, default: EntryHeight) - Height of folder entries
- **InfoHeight** (int, default: EntryHeight) - Height of info entries
- **SeparatorHeight** (int, default: 5) - Height of separator lines

### Display Options
- **ShowCaption** (enum, default: 1) - Caption display mode
  - 0: None
  - 1: Top
  - 2: Bottom
  - 3: Full
- **ShowExtensions** (bool/string, default: false) - Show file extensions
- **TooltipMode** (enum, default: 0) - Tooltip behavior
  - 0: No tooltips
  - 1: Caption as tooltip
  - 2: Custom tooltips
- **DropShadow** (bool, default: false) - Enable drop shadow (XP only)
- **RestrictToWorkArea** (bool, default: false) - Keep popup within work area
- **OpenToLeft** (bool, default: false) - Open sub-popups to the left

### Behavior Options
- **AutoHide** (bool, default: false) - Auto-hide when mouse leaves
- **AutoPin** (bool, default: true) - Auto-pin on move
- **Moveable** (bool, default: true) - Allow moving the popup
- **Shadeable** (bool, default: true) - Allow shading the popup
- **MoveAllowed** (alias for Moveable)
- **HideAllowed** (bool, default: true) - Allow manual unpinning
- **ShadeAllowed** (alias for Shadeable)
- **PinnedPopupNotOnTop** (bool, default: false) - Pinned popups not always on top
- **FolderOpenOnClick** (bool, default: false) - Open folders on click vs hover
- **CloseAfterAction** (bool, default: true) - Close popup after executing action
- **EnableDragnDrop** (bool, default: false) - Enable drag-and-drop

### Timing Options
- **HideDelay** (int, default: 250, min: 100) - Delay before auto-hide (ms)
- **TrackingDelay** (int, default: 50, min: 10) - Mouse tracking delay (ms)
- **FolderOpenDelay** (int, default: 50, min: 1) - Folder open delay (ms)
- **TasksUpdateInterval** (int, default: 5000, min: 1000) - Tasks refresh interval (ms)
- **MultiPartScrollDelay** (int, default: 2000, min: 250) - Multi-part scroll delay (ms)

### Transparency Options
- **AlphaTransparency** (int, default: 255, range: 0-255) - Overall transparency level
- **AlphaFade** (bool/enum, default: false) - Enable fade effect
- **CustomAlphaFade** (string, default: "") - Custom fade configuration
- **AlphaMap** (bool, default: false) - Use alpha channel from images
- **TrackingIgnoreTrueTransparency** (bool, default: false) - Ignore true transparency in tracking

### Layout Options
- **AutoSeparator** (enum, default: 0) - Automatic separator insertion
  - 0: None
  - 1: Between title and entries
  - 2: Between entries
  - 3: Both
- **AutoMenuBreak** (bool, default: false) - Automatic menu column breaks
- **QuicklaunchMode** (enum, default: 0) - Quicklaunch display mode
- **QuicklaunchItemSize** (int, default: 32, range: 16-64) - Quicklaunch icon size
- **QuicklaunchWrapCount** (int, default: 100, min: 1) - Items before wrap
- **QuicklaunchOpenTo** (enum, default: 1) - Sub-popup open direction

### File Display Options
- **IgnoreHiddenAttribute** (enum, default: 0) - Hidden file handling
  - 0: Respect hidden attribute
  - 1: Show all files
  - 2: Custom filtering
- **LargeIconChangeAt** (int, default: 32, min: 17) - Icon size threshold
- **DefaultIcon** (string, default: "") - Default icon path
- **DefaultFolderIcon** (string, default: "") - Default folder icon path
- **CacheLevel** (int, default: 0, range: 0-2) - Icon cache level

### Sound Options
- **OpenSound** (string, default: "") - Sound on popup open
- **CloseSound** (string, default: "") - Sound on popup close
- **SwitchSound** (string, default: "") - Sound on sub-popup switch
- **ActionSound** (string, default: "") - Sound on action execution

### Event Handlers
- **OnDrop** (string, default: "") - Command on file drop
- **OnOpen** (string, default: "") - Command on popup open
- **OnClose** (string, default: "") - Command on popup close
- **OnShade** (string, default: "") - Command on shade
- **OnUnShade** (string, default: "") - Command on unshade
- **OnFolderDoubleClick** (string, default: "explorer.exe /e,") - Folder double-click action

### Title Click Actions
- **OnTitleLeftClick** (enum/string, default: 6) - Left click on title
- **OnTitleMiddleClick** (enum/string, default: 0) - Middle click on title
- **OnTitleRightClick** (enum/string, default: 4) - Right click on title

### Bottom Click Actions
- **OnBottomLeftClick** (enum/string, default: 0) - Left click on bottom
- **OnBottomMiddleClick** (enum/string, default: 0) - Middle click on bottom
- **OnBottomRightClick** (enum/string, default: 0) - Right click on bottom

**Click Action Values:**
- 0: None
- 1: Close
- 2: Shade
- 3: Move
- 4: Menu
- 5: Pin
- 6: Toggle Shade
- Custom: Bang command

### Visual Customization
- **AlphaMap** (bool, default: false) - Use alpha channel for transparency
- **ActiveFolderUseFolderDefault** (bool, default: false) - Active folders use folder style
- **TitleShowIcon** (bool, default: false) - Show icon in title
- **PinnedShowIcon** (bool, default: false) - Show icon when pinned
- **UseTextArrow** (bool, default: false) - Use text for arrows instead of images
- **ExportHoverState** (bool, default: false) - Export hover state to variables

### Overlay Extensions
- **OverlayPopup** (multi-line) - Define overlay popup textures
- **OverlayEntry** (multi-line) - Define overlay entry textures

### State Export
- **NoLoadingPopup** (bool, default: false) - Skip loading popup
- **ExportHoverState** (bool, default: false) - Export hover information

When `ExportHoverState` is true, the following variables are exported:
- `<PopupName>ExportedHoverCaption` - Caption of hovered entry
- `<PopupName>ExportedHoverAction` - Action of hovered entry

### Position Export
The popup exports its current position and size:
- `<PopupName>CurrentX` - Current X position
- `<PopupName>CurrentY` - Current Y position
- `<PopupName>CurrentWidth` - Current width
- `<PopupName>CurrentHeight` - Current height

### Snap Behavior
- **SnapTo** (string, default: "10 all") - Snap distance and targets
  - Format: `<distance> <target>`
  - Targets: all, screen, modules, etc.

## Paint Classes Configuration

xPopup uses the xPaintClass system for visual customization. Each popup can define textures, icons, and text for different states:

### Texture Types
- **Popup** - Main popup background
- **Entry** - Normal entry background
- **ActiveEntry** - Active/hovered entry background
- **Folder** - Folder entry background
- **ActiveFolder** - Active folder background
- **Info** - Info entry background
- **ActiveInfo** - Active info background
- **Title** - Title bar background
- **Bottom** - Bottom bar background
- **Separator** - Separator line
- **Arrow** - Sub-menu arrow
- **ActiveArrow** - Active arrow

### Icon Types
Each texture type can have a corresponding icon configuration using `Icon` suffix (e.g., `EntryIcon`, `FolderIcon`).

### Text Types
Each texture type can have corresponding text configuration using `Text` suffix (e.g., `EntryText`, `TitleText`).

## Dynamic Folder Syntax

### Standard Dynamic Folder
```
!PopupDynamicFolder:<folder_path>
```

### Action Folder
```
!PopupDynamicActionFolder:<action>:<folder_path>
```

### Static Folder
```
!PopupFolder:<folder_path>
```

## Popup Definition Format

Create popup entries in RC files:
```
*Popup MyPopup !New
Icon Caption !Action
```

Or manually create folders:
```
*Popup MyPopup Folder FolderName !PopupDynamicFolder:<path> [layout] [default]
```

## Example Configuration

```
*Popup MainMenu
*Popup MainMenuX 100
*Popup MainMenuY 100
*Popup MainMenuAlphaTransparency 220
*Popup MainMenuAlphaFade true
*Popup MainMenuDropShadow true
*Popup MainMenuAutoHide true
*Popup MainMenuHideDelay 500
*Popup MainMenuLeftBorder 5
*Popup MainMenuTopBorder 20
*Popup MainMenuRightBorder 5
*Popup MainMenuBottomBorder 5
*Popup MainMenuEntryHeight 20
*Popup MainMenuOpenSound "C:\Windows\Media\chord.wav"
*Popup MainMenuCloseSound "C:\Windows\Media\ding.wav"

*Popup MainMenu !New
.icon Programs !PopupFolder:$ProgramFiles$
.icon Documents !PopupFolder:$Personal$
.icon Settings !PopupControlPanel
.icon - -
.icon Shutdown !Shutdown
```

## Dependencies

- **xPaintClass** - For texture and visual rendering
- **xIconClass** - For icon handling
- **xTextClass** - For text rendering

## Notes

- On Windows XP, drop shadows are only available when visual styles are enabled
- Dynamic folders monitor for changes and update automatically
- Popup bangs are dynamically registered/unregistered based on popup definitions
- All position and size values are in pixels
- The module supports extensive keyboard navigation with underlined hotkeys
