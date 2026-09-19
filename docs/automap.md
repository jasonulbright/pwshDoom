# Automap investigation

2026-09-11. Automap controls, discovery, rendering, save/load and replay are now
integrated. Performance and broader compatibility remain unqualified; the full
release goal remains active.

The September 19 [moving-route discovery profile](automap-discovery-performance.md)
preserves all 1,200 per-command mapping hashes and original gameplay checkpoints.
It measures the remaining discovery cost without changing production behavior.

The adopted gameplay model already has discovery flags, follow/pan/zoom state,
markers, all-map power handling, and an automap renderer. The fast game renderer
does not itself update the adopted line-discovery flags. The simulation now
owns a separate discovery pass and publishes map frames to the existing workers.

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

That first optimization demonstrated no general speedup. Even the fastest combined map/HUD median
is far above both the 28.57 ms simulation period and 16.67 ms presentation
period. This renderer should not be inserted into the simulation's per-tic
path at its measured cost. Separately measure map and HUD work before choosing
caching, reuse of the fast HUD, or distribution across presentation workers.

## Integrated path and current limits

Separating costs identified the HUD as the dominant inherited operation:
map-only medians were 2.8–7.9 ms, versus 144–165 ms for HUD drawing. Unit-scale
DrawColumnExact now uses the existing clipped bulk post copy. All sixteen
baseline images remain identical; HUD medians fall to 18–23 ms in
[the follow-up](../results/automap-foundation-hud-blit.json).

`AutomapSession.ps1` caches the HUD by all values read by the inherited renderer,
then restores its bottom 32 rows after map drawing. It does not cache game state.
The simulation applies a 10-bit map mask before each gameplay update and performs
discovery afterward at the simulation endpoint. Bitmap screen kind 3 travels
through the existing worker transport. Character styles use the menu encoder's
brightest-sample half blocks to preserve thin lines, with normal gameplay HUD
sampling below row 168. Applying brightest-region reduction to the HUD blurred
its numbers in the initial live footage; the dedicated automap worker job fixes
that sampling difference. Map screens do not pause
the simulation. Map images update on simulation snapshots, without map-view
interpolation. HUD cache misses and discovery remain pacing risks.

Controls: Tab toggles the map; +/- zoom; F toggles follow; arrows pan with follow
off; M adds one of ten numbered marks; C clears them. WASD, firing and use still
operate during map display. Menus cover the map and resume it afterward. Native
held-key suppression still applies after menu actions. The first command after
load supplies current held map state, releasing any saved held controls.

The [session checks](../results/automap-session-wad-settings.json) pass 43 cases,
including fourteen HUD-state invalidations, map/cheat/all-map composition,
pan/zoom/follow, marker wrap/clear, saved map state and synthetic key routing.
The [worker checks](../results/automap-worker-first.json) pass eight actual IPC
save/load/menu/new-game boundaries. Two earlier session fixtures are retained:
one omitted save metadata, the other did not initialize all IWAD settings.
These failures came from the harness; candidate validation rejected them.

Replay version 4 retains four-integer gameplay commands and adds ordered sparse
`AutomapCommands` (`Tic`, `Mask`). Bits are toggle 1, follow 2, mark 4, clear 8,
zoom-in 16, zoom-out 32, left 64, right 128, up 256, down 512. Omitted tics carry
zero. Optional `AutomapSha256` checkpoints cover flags, view, markers and held
state independently of the existing gameplay checkpoint. This preserves older
checkpoint comparisons while detecting map-only divergence. The format suite
passes [58 checks](../results/automap-replay-v4.json).

The [first full-host run](../results/automap-host-first.json) displays map frames
and consumes the 350-command synthetic control fixture, but takes **13.48 s**
for 10 s of simulation: the 35 Hz target is not met. Discovery averages 25.61 ms
with active workers, versus 4.52 ms gameplay and 7.88 ms snapshot publication
(including map drawing on 245 snapshots). A separate replay takes 13.04 s and
matches both gameplay and automap checkpoints. These are headless functional
runs with instrumentation, not unique displayed-FPS measurements.

Next: reduce discovery cost without changing discovered-line semantics, broaden
moving-world/door/secret/DontDraw and occlusion comparisons, and qualify map
presentation, input and pacing during campaign routes. Spawn-view matches do
not establish campaign-wide or vanilla automap compatibility. Additional
recording results are tracked in the ledger as they are verified.

## Actual window recordings

The accepted viewing copies are under ignored `local/recordings/`:

| Style | Viewing copy | Duration / decoded frames |
| --- | --- | --- |
| Classic | `automap-classic-view.mp4` | 14.10 s / 846 |
| Matrix | `automap-matrix-hud-view.mp4` | 15.00 s / 900 |
| AnsiArt | `automap-ansiart-hud-view.mp4` | 16.05 s / 963 |

[Recording metadata](../results/automap-recordings.json) retains original and
viewing-copy hashes, crop/trim settings, capture sources, later source changes
and checkpoint comparisons. The copies remove startup and fixed empty margins;
there is no speed change or rescaling. All three run the same 350 commands and
map masks, with both checkpoints matching the independently replayed headless
fixture. They were not separately replayed again merely to repeat that check.

Full-resolution map samples and video contact sheets show gameplay, map lines,
pan/follow views and HUDs. Character modes lose small label and marker detail;
Matrix is dim. The Classic sheet includes the end-of-game clear. Earlier
Matrix/AnsiArt originals remain as evidence of the corrected HUD sampling issue.
The movies are 60 CFR with possible duplicates. Their 14.08–15.16 s active game
durations for ten simulation seconds do not meet the simulation pacing target.

The [milestone audit](../results/automap-validation.json) records 301 accepted
named checks, worker pixel/strip comparisons, 87 standalone parses plus the
aggregate engine parse, 293 source hashes and zero remaining owned game or
recorder processes. The established 1,747-command E1M1/intermission/E1M2 route
still matches all eight legacy checkpoints, taking 52.51 active seconds for
49.91 seconds of simulation. This is progress toward the release, not completion.

To repeat the comparison from PowerShell 7, choose a fresh output path:

```powershell
.\scripts\Test-AutomapFoundation.ps1 -Output .\local\automap-repeat.json `
    -ReferenceReport .\results\automap-foundation-first.json
```

## Numeric discovery and encoder follow-up

The discovery pass now projects numeric fixed-point coordinates into binary
angles with the same slope lookup, octant offsets and wrapping as the retained
renderer. It avoids repeated Fixed/Angle wrapper allocation. It still runs on
every simulation tic, reads current sector heights at the simulation endpoint,
and preserves discovered-line semantics rather than using a reduced update rate.

[Foundation comparisons](../results/automap-numeric-foundation.json) pass 64
checks and retain all sixteen map/HUD hashes. The
[moving-route comparison](../results/automap-numeric-route.json) matches 2,139
point-angle cases (including ten matching exceptional cases), 48 sampled poses
on E1M1/intermission/E1M2, and all eight legacy campaign checkpoints. This is
broader coverage, not a proof for all maps or the inherited clipping-buffer limits.

Menu and map encoding now uses a sized string array and direct luminance
comparisons, eliminating temporary candidate arrays inside each character cell.
Strict greater-than comparisons preserve the first pixel on brightness ties;
HUD sampling remains unchanged. The independent encoder/navigation suite passes
[118 checks and 39 screen fixtures](../results/automap-numeric-menu.json).
Actual Matrix and AnsiArt workers compare 512,000 pixels and 56 encoded strips
across screen/menu/map transport and E1M2 asset reload.

All following headless tests consume the same 350 gameplay commands and automap
masks. The initial integration run records the two gameplay/map checkpoints;
each numeric follow-up matches them. Tests ran sequentially; these are individual
instrumented observations, not repeated paired trials.

| Build / report | Workers | Active seconds | Completed frames | Completed updates/s |
| --- | ---: | ---: | ---: | ---: |
| [Initial integration](../results/automap-host-first.json) | 7 | 13.4845 | 498 | 36.93 |
| [Numeric discovery](../results/automap-numeric-host.json) | 7 | 10.0293 | 326 | 32.50 |
| [Numeric discovery](../results/automap-numeric-host-16.json) | 16 | 10.0343 | 452 | 45.05 |
| [Numeric discovery + encoder](../results/automap-numeric-codec-host-16.json) | 16 | 10.0341 | 600 | 59.80 |

The final row recovers approximately 35 tics and 60 completed updates per second
for this bounded workload. It does **not** establish uniform pacing: tic lateness
is 6.31 ms median, 143.21 ms p95 and 224.11 ms maximum; the first uncached map/HUD
draw reaches 190.77 ms. Render-to-completion latency is 17.05 ms median, 33.36 ms
p95 and 42.82 ms maximum. These latencies are not frame presentation intervals.
Headless frames do not measure visible output. Recorded/live presentation and
longer combat/door/moving-sector routes remain separate qualification work.

To repeat the moving comparison from PowerShell 7:

```powershell
.\scripts\Test-NumericDiscovery.ps1 -Output .\local\numeric-discovery-repeat.json
```

The optimized Matrix [recorded run](../results/automap-numeric-recorded-matrix-game.json)
finishes 350 tics in 10.0315 s and writes 599 frames (59.71/s). Its input/mask stream
matches the replay fixture and both checkpoints match. The actual window-capture
viewing copy is `local/recordings/automap-numeric-matrix-view.mp4`: 10.0667 s,
604 fully decoded 60-CFR frames. The original remains alongside it. A contact
sheet confirms map/pan/HUD and return to katakana gameplay; an unused tile is black.
Small-label loss and dimness remain. This measures completed writes and provides
visual evidence; it does not identify unique game frames at every monitor refresh.

The [longer Classic regression](../results/automap-numeric-campaign-host.json)
matches all eight E1M1/intermission/E1M2 checkpoints, but 1,747 tics take 51.3342
active seconds instead of 49.9143 scheduled seconds. Wall time is 52.3448 s,
including 1.0097 s asset handoff. Discovery averages 4.344 ms, with 11.287 ms p95;
maximum tic lateness remains 1.378 s. Its 59.16 completed updates/sec does not
remove that simulation pacing limitation. The
[final audit](../results/automap-numeric-validation.json) preserves source hashes,
checks, host summaries, recording hashes and zero owned processes.
