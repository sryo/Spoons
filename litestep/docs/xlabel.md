# xLabel v4.4

**Author:** The LS-Universe Team
**Source:** `sources/xlabel-4.3-xsc-xpc-src/xLabel.cpp` & `Label.cpp`

## Description

xLabel is a versatile module for displaying text and images on the desktop. It supports advanced features like animations, transparency, docking, scrolling text, input boxes (TextEditBox), overlay labels, and extensive mouse event handling. It uses **xPaintClass** for all rendering, providing support for gradients, shadows, outlines, and various image formats.

## Configuration

xLabel uses a unique configuration style where settings are prefixed with the label's name (e.g., `MyLabelX`, `MyLabelText`). In this documentation, `*Label` defines the label name, and settings use that name as a prefix.

### General Settings

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Label>`X | coord | 0 | X position. |
| `<Label>`Y | coord | 0 | Y position. |
| `<Label>`Width | dim | - | Width (can be `.image` to match image size). |
| `<Label>`Height | dim | - | Height (can be `.image` to match image size). |
| `<Label>`AddToGroup | string | - | Adds the label to a group for shared settings. |
| `<Label>`WindowzOrder | bool | false | Use normal window Z-order. |
| `<Label>`BehindWindow | string | - | HWND_TOP or window class/name to stay behind. |
| `<Label>`AlwaysOnTop | bool | false | Keep label on top of other windows. |
| `<Label>`StartHidden | bool | false | Start the label in hidden state. |
| `<Label>`Ghosted | bool | false | Click-through (input transparent). (XP+) |
| `<Label>`NoMoveCursor | bool | false | Disables the move cursor. |
| `<Label>`Cursor | string | - | Path to a custom cursor file (.cur, .ani). |
| `<Label>`HoverTimeOut | int | 400 | Time in ms before hover state is triggered. |

### Text & Font (xPaintHTMLText)

xLabel supports HTML-like formatting tags. See xPaintClass documentation for full font capabilities (Shadows, Outlines, Gradients).

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Label>`Text | string | - | Text to display. |
| `<Label>`HoverText | string | - | Text to display on hover. |
| `<Label>`Font | string | Arial | Font name. |
| `<Label>`FontHeight | int | 15 | Font size. |
| `<Label>`FontColor | color | 000000 | Font color. |
| `<Label>`FontBold | bool | false | Bold text. |
| `<Label>`FontItalic | bool | false | Italic text. |
| `<Label>`FontUnderline | bool | false | Underlined text. |
| `<Label>`FontLineBreak | bool | false | Enable line breaks in text. |
| `<Label>`HoverFontLineBreak | bool | - | Line break setting for hover state. |
| `<Label>`PressedFontLineBreak | bool | - | Line break setting for pressed state. |
| `<Label>`NoEscapeSequence | bool | false | Disable parsing of escape sequences. |
| `<Label>`NoTextSplit | bool | false | Disable text splitting. |
| `<Label>`HrefHoverConfig | string | - | Configuration for HREF hover states (semicolon separated). |
| `<Label>`UpdateInterval | int | 1000 | Interval in ms for dynamic text updates. |
| `<Label>`UpdateAlways | bool | false | Force update even if not needed. |

### Images & Painting (xPaintTexture)

The label background uses xPaintClass Texture settings.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Label>`Image | string | - | Background image path. |
| `<Label>`HoverImage | string | - | Image for hover state. |
| `<Label>`PressedImage | string | - | Image for pressed state. |
| `<Label>`AlphaMap | bool | false | Use image alpha channel for window shape. |
| `<Label>`AlphaTransparency | int | 255 | Window opacity (0-255). |
| `<Label>`TrueTransparency | bool | false | Enable per-pixel alpha blending (PNG/TGA). |
| `<Label>`TrackingIgnoreTrueTransparency | bool | false | Ignore alpha for mouse tracking. |
| `<Label>`AlphaFade | bool | false | Enable fade effects on show/hide. |
| `<Label>`CustomAlphaFade | string | - | "Step Delay" for fade effect. |

### Animation

Supports separate animations for Normal and Hover states.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Label>`AnimFrameLoops | int | -1 | Number of loops (-1 = infinite). |
| `<Label>`AnimFrameDelay | int | 100 | Delay between frames (ms). |
| `<Label>`AnimFrameCount | int | 0 | Number of frames in strip. |
| `<Label>`AnimFrames | string | - | Explicit list of images for animation frames. |
| `<Label>`HoverAnimFrameLoops | int | -1 | Number of loops for hover animation. |
| `<Label>`HoverAnimFrameDelay | int | 100 | Delay for hover animation. |
| `<Label>`HoverAnimFrameCount | int | 0 | Number of frames in hover strip. |

### Auto-Size & Auto-Animation

Labels can automatically resize based on their content or via animation.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Label>`AutoWidthMode | enum | - | `.left`, `.right`, `.center`. |
| `<Label>`AutoHeightMode | enum | - | `.top`, `.bottom`, `.center`. |
| `<Label>`AutoMinWidth | int | 0 | Minimum width for auto-size. |
| `<Label>`AutoMaxWidth | int | ScreenW | Maximum width for auto-size. |
| `<Label>`AutoMinHeight | int | 0 | Minimum height for auto-size. |
| `<Label>`AutoMaxHeight | int | ScreenH | Maximum height for auto-size. |
| `<Label>`AutoAnimation | string | "0 0" | "Steps Delay" for smooth resizing. |

### Scrolling Text

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Label>`Scroll | enum | - | `.horizontal` (1), `.vertical` (2), `.horizontal-right` (3), `.vertical-down` (4). |
| `<Label>`ScrollSpeed | int | 1 | Pixels per step. |
| `<Label>`ScrollInterval | int | 100 | Delay between steps (ms). |
| `<Label>`ScrollPad | int | 10 | Padding between scrolling text end/start. |
| `<Label>`ScrollPerLine | string | - | "InitialSteps Steps Pause" for line-based scrolling. |

### Docking & Moving

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Label>`DockedTo | list | - | List of labels/groups this label is docked to ("Name Side"). |
| `<Label>`DockOnSnap | enum | - | Actions when snapped: `.moving`, `.snappedto`. |
| `<Label>`SnapTo | string | "0 desktop" | Snap distance and target ("0 desktop"). |
| `<Label>`Moveable | bool | false | Allow dragging the label. |
| `<Label>`MoveModifierKey | enum | .ctrl | Key to hold while moving (.ctrl, .shift). |
| `<Label>`MoveButton | enum | .left | Mouse button to drag with (.left, .right, .middle). |
| `<Label>`MoveArea | rect | - | "Left Top Width Height" defining custom move area. |
| `<Label>`FireOnMoveDuringMove | bool | false | Fire `OnMove` command continuously while dragging. |

### Resizable Borders

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Label>`ResizeBorder | string | -1 | Width of resize borders: "L R T B" or "W H" or "All". |
| `<Label>`ResizeBorderSteps | string | 0 | "StepX StepY" for resize stepping. |
| `<Label>`FireOnResizeDuringResize | bool | false | Fire `OnResize` command continuously while resizing. |

### TextEditBox (Input Field)

Turns the label into an editable text box.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Label>`TextEditBox | string | - | "X Y Width [Options] [MaxChars]". Options: `h` (hidden), `p` (password), `n` (number), `r`/`c` (align). |
| `<Label>`TextEditBoxPadding | int | 0 | "L R T B" padding inside the box. |
| `<Label>`TextEditBoxCursor | string | - | Path to cursor file for the edit box. |
| `<Label>`TextEditBoxEnterAction | string | .execute | Command behavior on Enter: `.execute` triggers `OnEnter`. |
| `<Label>`TextEditBoxOnFocus | command | - | Command when box gains focus. |
| `<Label>`TextEditBoxOnUnFocus | command | - | Command when box loses focus. |
| `<Label>`TextEditBoxOnSuccess | command | - | Command on successful input. |
| `<Label>`TextEditBoxOnFail | command | - | Command on failed input (e.g. number validation). |

### Overlay Labels

Allows creating sub-labels relative to the main label.

| User Variable | Description |
|---------------|-------------|
| `<Label>`OverlayLabel | List of overlay configurations: `X Y W H Name [RenderMode] [Condition]` |

### Events & Actions

Supports Left, Right, Middle, X1, X2 buttons and modifiers (Ctrl, Shift).

| Variable | Type | Description |
|----------|------|-------------|
| `<Label>`OnLeftClick | command | Command on left click. |
| `<Label>`OnLeftClickDown | command | Command on left button down. |
| `<Label>`OnLeftClickUp | command | Command on left button up. |
| `<Label>`OnLeftDoubleClick | command | Command on left double click. |
| `<Label>`OnRightClick... | command | (Right button variants) |
| `<Label>`OnMiddleClick... | command | (Middle button variants) |
| `<Label>`OnX1Click... | command | (X1 button variants) |
| `<Label>`OnX2Click... | command | (X2 button variants) |
| `<Label>`OnWheelUp | command | Command on mouse wheel up. |
| `<Label>`OnWheelDown | command | Command on mouse wheel down. |
| `<Label>`OnEnter | command | Command when mouse enters label. |
| `<Label>`OnLeave | command | Command when mouse leaves label. |
| `<Label>`OnDrop | command | Command when file is dropped on label (%1 = file path). |
| `<Label>`OnShow | command | Command when label is shown. |
| `<Label>`OnHide | command | Command when label is hidden. |
| `<Label>`OnMove | command | Command when label moves. |
| `<Label>`OnResize | command | Command when label resizes. |
| `<Label>`OnTextChange | command | Command when text changes. |
| `<Label>`OnFocusGained | command | Command when label definition gains focus. |
| `<Label>`OnFocusLost | command | Command when label definition loses focus. |
| `<Label>`OnAnimLoopStart | command | Command when animation loop starts. |
| `<Label>`OnKeyDown | command | Command when a key is pressed (requires focus). |
| `<Label>`OnKeyUp | command | Command when a key is released. |

**Regions:** You can define specific click regions using `<Label>On[Button]ClickRegion`.
Format: `X Y Width Height "Command"`

## Bang Commands

| Command | Description |
|---------|-------------|
| `!LabelCreate <Name>` | Creates a new label. |
| `!LabelDestroy <Name>` | Destroys a label. |
| `!LabelShow <Name> [.editbox / overlay]` | Shows a label, its editbox, or an overlay. |
| `!LabelHide <Name> [.editbox / overlay]` | Hides a label, its editbox, or an overlay. |
| `!LabelShowHide <Name> <Timeout>` | Shows label, then hides it after timeout (ms). |
| `!LabelToggle <Name> [.editbox / overlay]` | Toggles visibility. |
| `!LabelRefresh <Name> [Setting Value]` | Reloads config. Optionally updates a specific setting first. |
| `!LabelUpdate <Name>` | Forces a repaint/update of the label. |
| `!LabelSetText <Name> [.editbox / overlay] <Text>` | Updates text. |
| `!LabelSetAnimation <Name> <on/off> [loops]` | Controls animation. |
| `!LabelSetAlpha <Name> <Val> [Step Delay]` | Sets transparency (0-255). Optional fade. |
| `!LabelGhosted <Name> <on/off/toggle>` | Sets ghosted (click-through) state. |
| `!LabelAlwaysOnTop <Name> <on/off/toggle>` | Sets always on top state. |
| `!LabelFocus <Name> [.editbox]` | Sets focus to label or its editbox. |
| `!LabelMove <Name> <X> <Y> [Steps Time]` | Moves label. |
| `!LabelMoveBy <Name> <X> <Y> [Steps Time]` | Moves label by offset. |
| `!LabelResize <Name> <W> <H> [Steps Time]` | Resizes label. |
| `!LabelResizeBy <Name> <W> <H> [Steps Time]` | Resizes label by offset. |
| `!LabelReposition <Name> <X> <Y> <W> <H> [Steps Time]` | Moves and resizes in one command. |
| `!LabelDock <Name> <Target> <true/false> [Side]` | Docks label to another. |
| `!LabelScroll <Name> <on/off/change> [Mode]` | Controls text scrolling. |
| `!LabelClipboardCopy <Name> [Prefix]` | Copies text to clipboard. |
| `!LabelClipboardPaste <Name> [Prefix]` | Pastes text from clipboard. |
| `!LabelInfoExport <Name> <Output> <Text>` | Exports text. Output can be `clipboard`, `%#Var%#` (evar), or `%%Var%%`. |
| `!LabelCreateOverlay <Name> <X> <Y> <W> <H> <OvName> [Mode] [Cond]` | Creates a new overlay dynamically. |
| `!LabelModifyOverlay <Name> <OvName> <Config>` | Modifies an existing overlay. |
| `!LabelDestroyOverlay <Name> <OvName>` | Destroys an overlay. |
| `!LabelModuleHook <Name> <Config>` | Hooks an external module to the label (for alpha/z-order). |
| `!ParseEvars <Command>` | Parses evars in the command string (supports `%[LabelName]%` and `%[LabelText]%`). |
| `!SetEvar <Var> <Value>` | Sets an environment variable. |
| `!PlaySound <File>` | Plays a sound file. |
| `!TexteditBoxExecute <Args>` | Internal command for text edit box execution. |
