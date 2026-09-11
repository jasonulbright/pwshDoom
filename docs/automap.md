# Automap investigation

2026-09-11. This is an experimental foundation, not a playable automap feature.
The release goal remains active.

The adopted gameplay model already has discovery flags, follow/pan/zoom state,
markers, all-map power handling, and an automap renderer. The fast game renderer
does not update the adopted line-discovery flags, and the current host does not
route automap controls or publish automap frames.

`ThreeDRenderer.DiscoverMap` reuses the inherited BSP traversal, angular tests
and horizontal occlusion ranges at the current simulation endpoint. It sets
mapped-line flags without rasterizing another 3D frame, visiting sprites or
changing world/sector renderer validity counters. It intentionally bypasses the
reference renderer's visible-wall and pixel-clip buffer limits; matching that
renderer under those limits has not been established.

The map renderer now clears its map area using per-column `Array.Clear` and
avoids transforming undiscovered lines unless the all-map power or cheat state
can expose them. Gameplay and rendering algorithms remain PowerShell.

## Evidence

`scripts/Test-AutomapFoundation.ps1` loads the installed Steam Ultimate Doom
IWAD (SHA256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`).
It compares four headings at each of E1M1, E2M7, E3M8 and E4M1's initial spawn.
Each case resets mapped flags, compares discovered line indices against an
inherited full render, checks framebuffer/counter preservation, and draws the
map plus HUD at 320×200. Raw indexed images stay in ignored `local/`.

- [Initial report](../results/automap-foundation-first.json): 48 checks passed.
- [First bulk-clear attempt](../results/automap-foundation-bulk.json): harness
  failed when strict mode read a missing `Heading` field in a timing summary.
  The retained error is not a renderer failure or a passing comparison.
- [Corrected report](../results/automap-foundation-bulk-fixed.json): all 64
  checks passed, including identical map/HUD pixel hashes for all 16 images.

Ten repeated stationary samples at each final heading yielded these medians
in milliseconds. These are operation timings, not live or displayed FPS.
The runs were sequential experiments, not controlled paired performance trials.

| Map | Initial discovery | Current discovery | Initial map + HUD | Current map + HUD |
| --- | ---: | ---: | ---: | ---: |
| E1M1 | 14.00 | 14.56 | 157.26 | 157.90 |
| E2M7 | 11.85 | 12.77 | 183.88 | 172.79 |
| E3M8 | 1.44 | 1.41 | 146.30 | 154.24 |
| E4M1 | 4.12 | 5.28 | 159.23 | 182.87 |

No general speedup is demonstrated. Even the fastest combined map/HUD median
is far above both the 28.57 ms simulation period and 16.67 ms presentation
period. This renderer should not be inserted into the simulation's per-tic
path at its measured cost. Separately measure map and HUD work before choosing
caching, reuse of the fast HUD, or distribution across presentation workers.

## Remaining integration

Implement discovery ownership and scheduling, map controls, host/worker
transport, and readable map presentation for all three styles. Preserve the
existing replay format's readability while recording any new controls; test
save/load of discovery and marker state. Add moving-world, doors, occlusion,
zoom/pan/markers, secret/DontDraw/all-map and cheat fixtures. Spawn-view matches
do not establish campaign-wide or vanilla automap compatibility.

No live automap recording has been made because the playable host does not yet
display this path. The existing menu/session recordings remain the live evidence.

To repeat the comparison from PowerShell 7, choose a fresh output path:

```powershell
.\scripts\Test-AutomapFoundation.ps1 -Output .\local\automap-repeat.json `
    -ReferenceReport .\results\automap-foundation-first.json
```
