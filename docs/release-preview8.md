# Preview.8 release scope

October 4, 2026. This is a playable cumulative community preview, not full
Ultimate Doom certification. It preserves Classic, Matrix and AnsiArt, with
gameplay, rasterization, terminal encoding, music synthesis and audio mixing in
PowerShell. The source package contains no IWAD, soundfont, prepared music,
local files, research PDF or downloaded tools.

## Changes and offline checks

Settings retain eleven gamma choices (off and ten brighter levels), with F11
cycling the selected level. Key remapping now gives feedback for reserved keys
and preserves rapid repeated menu taps. WAD-backed wall spans use Doom's fixed-
angle view-angle table when the required metadata is available; contexts without
that metadata retain the analytic fallback. The renderer accepts both native
`Fixed`/`Angle` camera objects and transported snapshots whose position and view
height are numeric world units and whose angle is radians.

The authored-geometry masked-wall harness passes 24 checks, including full-frame
pixel and depth parity for both camera representations. The synthetic wall-span
harness passes 18 cases at 0°, 90°, 180° and 270°. These tests use no WAD, game
session, display or audio device. Offline package checks also pass 96 settings
assertions, 143 menu assertions with 60 WAD-backed static screen fixtures, and
286 palette checks. The menu fixtures caught two text-fit defects: the key
capture prompt now uses the smaller footer scale, and the Controls help wraps
the final shortcut list across two rows. The test harness copies each frame
before comparing it so later screen draws cannot overwrite earlier results.
No live test was run for this package preparation. The focused checks establish
implementation behavior only; they do not establish map rendering fidelity,
campaign playability or performance.

## Remaining release gates

The complete human Episode 1 route, including E1M3 → E1M9 → E1M4 and the finale,
remains unqualified. The full release also needs independent original-frame
comparisons, sustained simulation/display pacing, physical keyboard and
DPI/window review, acoustic listening, and a second hardware configuration. See
the [roadmap](roadmap.md), [performance findings](performance.md),
[audio findings](audio.md), and [working article](article-draft.md).
