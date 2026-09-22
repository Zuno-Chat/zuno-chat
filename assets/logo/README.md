# Zuno — adaptive app icon

## Android (adaptive icon)
108×108dp canvas · 72dp safe zone · mark drawn at **62dp**, centred — clears every mask (circle, squircle, rounded square, teardrop) with room for the 6dp parallax shift.

| File | Layer |
|---|---|
| `ic_launcher_background.svg` | background — flat amber `#E8A33D` |
| `ic_launcher_foreground.svg` | foreground — ink mark, Z knocked out |
| `ic_launcher_monochrome.svg` | themed-icon layer (Android 13+), solid black on transparent |
| `ic_launcher_foreground_small.svg` | foreground without the Z, for notification/status densities |
| `ic_launcher.xml` / `colors.xml` | drop into `res/mipmap-anydpi-v26/` and `res/values/` |

Convert the SVGs to vector drawables with Android Studio's *Vector Asset* import (or `svg2vectordrawable`), then place in `res/drawable/`.

## iOS
`ios-icon-1024.svg` — full-bleed square, no transparency, no pre-rounded corners (iOS applies the squircle). Mark at 64% so it survives the mask.
`-dark` and `-tinted` cover iOS 18's dark and tinted icon slots; the tinted source is greyscale, as Apple expects.

## Play Store
`play-store-512.svg` — 512×512, full-bleed, no rounding.

## Note
The Z is a knockout, so at very small densities it can thin out. Below ~40px use the `_small` foreground and let the bubble carry the icon.
