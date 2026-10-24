# AppIcon

UpTil's app icon is `⟩⧗⟨`: an amber hourglass between two narrow brackets on a
deep teal tile. The brackets echo the menu-bar countdown (`⟩42m⟨`); the
hourglass carries the countdown meaning at Finder sizes.

## Sources

Both parts are stock MIT-licensed glyphs, only scaled, placed, and recolored.

| Part | Glyph | License |
|---|---|---|
| Brackets | Tabler Icons `chevron-compact-right` and `chevron-compact-left` | [`licenses/tabler-icons.txt`](licenses/tabler-icons.txt) |
| Hourglass | Phosphor Icons `hourglass-fill` | [`licenses/phosphor-icons.txt`](licenses/phosphor-icons.txt) |

SF Symbols are not usable here: Apple's license forbids them in app icons.

## Files

| File | Role |
|---|---|
| `Design/AppIcon/layers.swift` | Places the glyphs and writes both layer SVGs |
| `Resources/AppIcon.icon/Assets/brackets.svg` | Generated: brackets as filled outlines |
| `Resources/AppIcon.icon/Assets/hourglass.svg` | Generated: Phosphor path verbatim, one transform |
| `Resources/AppIcon.icon/icon.json` | Icon Composer document: tile fill, layers, effects, platforms |

Layers are drawn on a transparent 1024×1024 canvas with no background, mask,
shadow, text, or raster content; Icon Composer owns those.

Tabler glyphs are strokes. `layers.swift` strokes them with CoreGraphics and
writes filled outlines, because Icon Composer repaints layer geometry for the
Dark, Tinted, and Clear renditions: an open stroked path would be filled into a
wedge. Do not hand-edit the generated SVGs back to strokes.

## Geometry

- Brackets: Tabler grid scaled ×26 (416 units tall), stroke 38 units with round
  caps and joins (lighter than Tabler's default 2-unit stroke, which would be 52).
- Hourglass: Phosphor grid scaled ×1.29 (330 units), centered.
- 42 units of clear space between the hourglass and each bracket tip.

## Colors and appearances

| Element | Default | Dark |
|---|---|---|
| Tile | linear gradient `#247B84` → `#165862` | system dark tile |
| Brackets | `#EAFBFF` | `#9CD6DB` (layer `fill-specializations`) |
| Hourglass | `#F7A93E` | `#F7A93E` (unchanged) |

- Group `01 Mark`: neutral shadow 0.5; translucency off so the amber stays
  saturated and the brackets stay crisp.
- Tinted and Clear are system-derived from the same layers.
- `supported-platforms` is macOS only.
- The app's AccentColor matches the tile family: `#1F7F89`, with `#3FA9B3` in
  dark appearance (`Resources/Assets.xcassets/AccentColor.colorset`). Change the
  two together.

The teal was chosen after comparing 14 keep-awake apps on the Mac App Store
and GitHub. Their icons cluster in bright system blue, red or coral, white or
light gray, and purple or indigo, mostly drawn as coffee cups. None uses teal.

## Regenerating

```sh
swift Design/AppIcon/layers.swift Resources/AppIcon.icon/Assets

ictool="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
for rendition in Default Dark TintedLight ClearDark; do
  for generation in 26 27; do
    "$ictool" Resources/AppIcon.icon --export-image \
      --output-file "/tmp/uptil-icon-$rendition-$generation.png" \
      --platform macOS --rendition "$rendition" \
      --width 128 --height 128 --scale 2 --design-generation "$generation"
  done
done

mise run app:build
```

Inspect the renders at 16, 32, and 128 points in both generations: both
brackets and the hourglass must stay separate in every rendition.

## Toolchain

CI compiles with Xcode 26.6. `icon.json` uses only keys Icon Composer 26
writes. If the document is re-saved from a newer Icon Composer, check the diff
for new keys and let CI confirm Xcode 26.6 still compiles it.

With the macOS 14.0 deployment target, Xcode 27 emits a minimal
`AppIcon.icns` (16, 32, 128, and 256 pixels). The full 16–1024 fallback set
and the live Default, Dark, and Tintable stacks live in `Assets.car` under
`CFBundleIconName = AppIcon`, which macOS 14+ uses.
