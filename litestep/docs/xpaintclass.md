# xPaintClass v1.0 (Update 7)

**Author:** The LS-Universe Team (Andymon)  
**Requirements:** Windows 2000 or newer

## Description

xPaintClass is a powerful graphics rendering library for LiteStep modules. It provides advanced texture painting, icon rendering, text drawing, HTML text rendering, tooltips, and visual effects. This is a shared library used by xLabel, xTray, xPopup, xTaskbar, and other xModules.

> [!IMPORTANT]
> xPaintClass must be loaded **before** any modules that depend on it!

## Installation

```ini
LoadModule "$LiteStepDir$xPaintClass-1.0.dll"
LoadModule "$LiteStepDir$xLabel-4.4.dll"
```

---

## xPaintTexture

Renders backgrounds, images, gradients, and visual styles.

### Position & Size

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>TextureX` | coord | 0 | X position of texture. |
| `<Prefix>TextureY` | coord | 0 | Y position of texture. |
| `<Prefix>TextureWidth` | dim | 100% | Width (pixels or percentage). |
| `<Prefix>TextureHeight` | dim | 100% | Height (pixels or percentage). |
| `<Prefix>TextureRotation` | string | "0" | Rotation in degrees, optionally with width/height: `"90 64 64"`. |

### Painting Mode

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>PaintingMode` | enum | .none | Rendering mode (see below). |

**Painting Modes:**

| Value | Name | Description |
|-------|------|-------------|
| -1 | `.none` | No painting. |
| 0 | `.image` | Render a bitmap image. |
| 1 | `.icon` | Render an icon. |
| 2 | `.multicolor` | Render a gradient. |
| 3 | `.singlecolor` | Render a solid color. |
| 4 | `.borderbutton` | Render a 3D button style. |
| 5 | `.animation` | Render an animation strip. |
| 6 | `.visualstyle` | Render using Windows XP+ Visual Styles. |

### Transparency

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>TextureAlphaTransparency` | int | 255 | Alpha transparency (0-255). |
| `<Prefix>TextureTrueTransparency` | bool | false | Enable per-pixel alpha from image. |
| `<Prefix>TextureAlphaTranslucency` | bool | false | Enable alpha translucency (Update 7). |
| `<Prefix>DisablePerformanceCaching` | bool | false | Disable caching for dynamic content. |

### Image Settings (Mode `.image`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>Image` | path | - | Path to the image file (BMP, PNG, TGA, etc.). |
| `<Prefix>ImageWidth` | int | 64 | Target width for scaling. |
| `<Prefix>ImageHeight` | int | 64 | Target height for scaling. |
| `<Prefix>ImageMode` | enum | .stretch | Scaling mode. |
| `<Prefix>ImageEdges` | rect | 0 0 0 0 | 9-slice scaling edges (Left Top Right Bottom). |
| `<Prefix>ImageCrop` | rect | 0 0 0 0 | Crop source image (Left Top Right Bottom). |

**Image Scaling Modes:**

| Mode | Description |
|------|-------------|
| `.stretch` | Simple stretch (fast). |
| `.tile` | Tile in both directions. |
| `.tile-horizontal` | Tile horizontally, stretch vertically. |
| `.tile-vertical` | Tile vertically, stretch horizontally. |
| `.stretch_bell` | High-quality Bell filter. |
| `.stretch_box` | Box filter. |
| `.stretch_catmullrom` | Catmull-Rom spline. |
| `.stretch_cosine` | Cosine interpolation. |
| `.stretch_cubicconvolution` | Cubic convolution. |
| `.stretch_cubicspline` | Cubic spline. |
| `.stretch_hermite` | Hermite spline. |
| `.stretch_lanczos3` | Lanczos3 (high quality). |
| `.stretch_lanczos8` | Lanczos8 (highest quality). |
| `.stretch_mitchell` | Mitchell-Netravali filter. |
| `.stretch_quadratic` | Quadratic interpolation. |
| `.stretch_quadraticbspline` | Quadratic B-spline. |
| `.stretch_triangle` | Triangle (bilinear). |

> [!TIP]
> The same filter options are available for `.tile-horizontal_*` and `.tile-vertical_*` variants.

### Icon Settings (Mode `.icon`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>IconPath` | path | - | Path to extract icon from. |
| `<Prefix>IconExtractionSize` | int | 32 | Size to extract icon at. |
| `<Prefix>IconMode` | int | 0 | Icon rendering mode (Update 6). |

### Color Effects

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>HueColor` | color | White | Hue tint color. |
| `<Prefix>HueIntensity` | int | 0 | Intensity of hue tint (0-100). |
| `<Prefix>LuminanceIntensity` | int | 0 | Brightness adjustment (-100 to 100). |
| `<Prefix>SaturationIntensity` | int | 100 | Saturation adjustment (0-200). |
| `<Prefix>MixColor` | color | White | Color to blend in. |
| `<Prefix>MixIntensity` | int | 0 | Intensity of mix color (0-100). |

### Solid Color Settings (Mode `.singlecolor`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>Color` | color | White | Background color. |
| `<Prefix>Colors` | string | - | Extended format: `"BgColor LightColor DarkColor"`. |

### Gradient Settings (Mode `.multicolor`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>GradientColors` | list | - | List of colors for the gradient. |
| `<Prefix>GradientRepeatedColors` | list | - | Repeat counts for gradient colors. |
| `<Prefix>GradientType` | enum | .horizontal | Type of gradient. |
| `<Prefix>GradientTransformation` | enum | .none | Distortion effect. |

**Gradient Types:**

| Type | Description |
|------|-------------|
| `.horizontal` | Left to right. |
| `.vertical` | Top to bottom. |
| `.radial` | Center outward (circular). |
| `.diagonal` | Top-left to bottom-right. |
| `.fdiagonal` | Forward diagonal. |
| `.bdiagonal` | Backward diagonal. |
| `.pipecross` | Cross/pipe pattern. |
| `.elliptic` | Elliptical gradient. |
| `.rectangle` | Rectangular gradient. |
| `.pyramid` | Pyramid/4-corner gradient. |

**Gradient Transformations:**

| Transform | Description |
|-----------|-------------|
| `.none` | No transformation. |
| `.caricature` | Caricature distortion. |
| `.fisheye` | Fisheye lens effect. |
| `.swirled` | Swirl distortion. |
| `.cylinder` | Cylindrical projection. |
| `.shift` | Shift transformation. |

### Shape & Border Settings

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>ShapeMode` | enum | .rectangle | Shape: `.rectangle`, `.ellipse`, `.rounded`. |
| `<Prefix>RoundedEdges` | string | "0" | Radius for rounded corners: `"X"` or `"X Y"`. |
| `<Prefix>BorderMethod` | enum | .none | 3D border style. |
| `<Prefix>Bevels` | rect | 0 0 0 0 | Bevel widths (Left Right Top Bottom). |

**Border Methods:**

| Method | Description |
|--------|-------------|
| `.none` | No border. |
| `.raised` | Raised 3D effect. |
| `.sunken` | Sunken 3D effect. |
| `.etched` | Etched border. |
| `.bump` | Bump border. |

### Visual Styles (Mode `.visualstyle`)

Renders using Windows XP+ theme parts.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>MSStyle` | string | - | Shorthand: `"CLASS PART STATE"`. |
| `<Prefix>MSStyle_Class` | string | - | Theme class (e.g., `"BUTTON"`, `"WINDOW"`). |
| `<Prefix>MSStyle_Part` | int | 0 | Part ID or constant name. |
| `<Prefix>MSStyle_State` | int | 0 | State ID or constant name. |

**Common Part Constants:**

| Constant | Class |
|----------|-------|
| `BP_PUSHBUTTON`, `BP_CHECKBOX`, `BP_RADIOBUTTON` | BUTTON |
| `WP_CAPTION`, `WP_CLOSEBUTTON`, `WP_MINBUTTON` | WINDOW |
| `TABP_TABITEM`, `TABP_PANE`, `TABP_BODY` | TAB |
| `EP_EDITTEXT`, `EP_CARET` | EDIT |
| `PP_BAR`, `PP_CHUNK` | PROGRESS |
| `SBP_ARROWBTN`, `SBP_THUMBBTNHORZ` | SCROLLBAR |

### Animation Settings (Mode `.animation`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>AnimFrameWidth` | int | 0 | Width of each frame. |
| `<Prefix>AnimFrameHeight` | int | 0 | Height of each frame. |

---

## xPaintText

Renders styled text with shadows, outlines, and effects.

### Font Settings

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>FontVisible` | bool | true | Show/hide text. |
| `<Prefix>Font` | string | Arial | Font family name. |
| `<Prefix>FontHeight` | int | 15 | Font size in pixels. |
| `<Prefix>FontColor` | color | Black | Text color. |
| `<Prefix>FontCharSet` | int | DEFAULT | Character set. |
| `<Prefix>FontBold` | bool | false | Bold text. |
| `<Prefix>FontItalic` | bool | false | Italic text. |
| `<Prefix>FontUnderline` | bool | false | Underlined text. |
| `<Prefix>FontSmoothing` | bool | true | Enable anti-aliasing. |
| `<Prefix>FontClearType` | bool | true | Use ClearType rendering. |

### Text Transparency

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>FontAlphaTransparency` | int | 255 | Text alpha (0-255). |

### Text Alignment

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>FontAlign` | enum | .left | Horizontal: `.left`, `.center`, `.right`. |
| `<Prefix>FontVertAlign` | enum | .center | Vertical: `.top`, `.center`, `.bottom`. |
| `<Prefix>FontNoEllipsis` | bool | false | Don't show "..." for truncated text. |

### Text Borders (Padding)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>FontBorders` | rect | 0 0 0 0 | Padding (Left Top Right Bottom). |
| `<Prefix>FontLeftBorder` | int | 0 | Left padding. |
| `<Prefix>FontTopBorder` | int | 0 | Top padding. |
| `<Prefix>FontRightBorder` | int | 0 | Right padding. |
| `<Prefix>FontBottomBorder` | int | 0 | Bottom padding. |

### Text Shadow

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>FontShadow` | bool | false | Enable shadow. |
| `<Prefix>FontShadowColor` | color | Gray | Shadow color. |
| `<Prefix>FontShadowX` | int | 1 | Shadow X offset. |
| `<Prefix>FontShadowY` | int | 1 | Shadow Y offset. |
| `<Prefix>FontBlockedShadow` | int | 0 | Blocked shadow size (0 = normal). |

### Text Outline

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>FontOutline` | bool | false | Enable outline. |
| `<Prefix>FontOutlineColor` | color | Gray | Outline color. |
| `<Prefix>FontOutlineExtra` | bool | false | Thicker outline. |

### Text Emboss

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>FontEmbossColor1` | color | - | First emboss color. |
| `<Prefix>FontEmbossColor2` | color | - | Second emboss color. |

### Text Fade

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>FontFade` | rect | 0 0 0 0 | Fade edges (Left Right Top Bottom). |
| `<Prefix>FontLeftFade` | int | 0 | Left fade distance. |
| `<Prefix>FontRightFade` | int | 0 | Right fade distance. |
| `<Prefix>FontTopFade` | int | 0 | Top fade distance. |
| `<Prefix>FontBottomFade` | int | 0 | Bottom fade distance. |

### Text Rotation

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>FontRotation` | int | 0 | Rotation in degrees. |

---

## xPaintIcon

Renders icons with effects.

### Position & Size

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>IconVisible` | bool | true | Show/hide icon. |
| `<Prefix>IconX` | coord | - | X position. |
| `<Prefix>IconY` | coord | - | Y position. |
| `<Prefix>IconSize` | int | 16 | Icon size in pixels. |

### Icon Transparency

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>IconAlphaTransparency` | int | 255 | Icon alpha (0-255). |

### Icon Color Effects

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>IconHueColor` | color | White | Hue tint color. |
| `<Prefix>IconHueIntensity` | int | 0 | Hue intensity (0-100). |
| `<Prefix>IconLuminanceIntensity` | int | 0 | Brightness (-100 to 100). |
| `<Prefix>IconSaturationIntensity` | int | 100 | Saturation (0-200). |
| `<Prefix>IconMixColor` | color | White | Mix color. |
| `<Prefix>IconMixIntensity` | int | 0 | Mix intensity (0-100). |

### Icon Rotation

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>IconRotation` | int | 0 | Rotation in degrees. |
| `<Prefix>IconMode` | int | 0 | Icon rendering mode. |

---

## xPaintHTMLText

Renders HTML-formatted text with links and styling.

Supports HTML tags:
- `<b>`, `<i>`, `<u>` - Bold, italic, underline
- `<font color="..." size="..." face="...">` - Font styling
- `<br>` - Line break
- `<a href="...">` - Hyperlinks (execute bangs or URLs)

---

## xPaintTooltip

Configures tooltip appearance.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `<Prefix>TooltipLabel` | string | - | Use an xLabel for tooltip instead of native. |
| `<Prefix>TooltipLabelFixed` | bool | false | Fixed position tooltip. |
| `<Prefix>TooltipLabelTimeout` | int | - | Tooltip timeout in ms. |

---

## Color Format

Colors can be specified as:
- **RGB triplet**: `255 128 0`
- **Hex (6-digit)**: `FF8000` or `#FF8000`
- **Hex (3-digit)**: `F80` (expands to `FF8800`)

---

## Changelog

- **Update 7** (2009) - Alpha translucency, opaque BG ClearType
- **Update 6** (2007) - High-quality resample filters, new gradient types, icon mode
- **Update 5** (2007) - Visual Styles support, tooltip labels
- **Update 4** (2007) - Rotation support for textures, text, and icons
- **Update 3** - Tab support in tooltips
- **Update 2** - Shape modes, rounded edges
- **1.0** (2007-01-25) - Initial release by Andymon

## Notes

- xPaintClass is a library, not a standalone module
- Must be loaded before xLabel, xTray, xPopup, xTaskbar
- All settings use a prefix determined by the parent module
- PNG and TGA images support alpha channels
- Icon extraction supports shell icons from files/folders
