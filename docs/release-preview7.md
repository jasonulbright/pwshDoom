# Preview.7 release scope

October 2, 2026. This is a playable cumulative community preview, not full
Ultimate Doom certification. It preserves Classic, Matrix and AnsiArt, with
gameplay, rasterization, terminal encoding, music synthesis and audio mixing in
PowerShell. The package contains source and documentation, but no IWAD,
soundfont, prepared music, local recordings, research PDF or downloaded tools.

## Changes and checks

F1 opens controls, F2 opens the six-slot save screen, F3 opens load, and F10
opens the existing quit confirmation from gameplay or pause. Canceling F10
returns to play. Existing overwrite/load confirmation and custom-key reservation
remain in use. Existing menu checks pass 139 assertions and 59 screen fixtures;
the input checks pass 10. Focused direct checks cover the new key flows.

The renderer now reuses fixed-point wall-parameter buffers and map-context
copies of WAD wall inputs. The existing wall-U comparison passes 20,049 cases
(including 11 matching overflow cases). A fixed E1M2 view has the same complete
image hash before and after these changes, with an exact HUD.

These changes remove repeated allocations and conversions by construction.
They have no valid paired timing result: the existing paired benchmark stopped
before timing because its isolated PowerShell module could not resolve
`[Patches]`. Preview.7 therefore makes no renderer-speedup, 35-tic or
60-displayed-frame claim. The historical Preview.6 performance comparison
remains scoped to its own source and fixed workload.

## Remaining release gates

The complete human Episode 1 route, including E1M3 → E1M9 → E1M4 and the finale,
remains unqualified. Do not infer it from map-start smoke or static views. The
full release also needs independent original-frame comparisons, sustained
simulation/display pacing, physical keyboard and DPI/window review, acoustic
listening, and a second hardware configuration. See the [roadmap](roadmap.md),
[performance findings](performance.md), [audio findings](audio.md), and the
[working article and alternatives](article-draft.md).
