# Rendering fidelity: first reference comparison and HUD repairs

2026-09-19. These are offline image fixtures, not live terminal runs or performance measurements. The reference is the adopted, locally adapted PowerShell renderer. It is useful for finding disagreements with our new rasterizer, but it is not independently verified original-executable output.

## What the comparison establishes

`scripts/Compare-RendererReference.ps1` loads a real IWAD map, advances 35 idle updates, and renders the same endpoint at three explicit camera headings. The reference uses its 320x168 scene plus 32-row status bar. The current renderer receives the corresponding fraction-one snapshot. Reference column-major pixels are converted to row-major before comparison. Local PNGs show reference, current, and a white mask of different palette indices; they use the base palette and square pixels. Commercial image content remains under ignored `local/`.

The first E1M1 comparison found 1,511 differing HUD pixels at each heading. Inspection showed missing weapon-ownership digits, ignored patch-origin offsets (including the face), and variable-width digit placement. These are presentation defects, not campaign-bot failures. The new HUD path now respects WAD patch offsets, renders the six ownership indicators, spaces numbers by the zero glyph width, and copies unlit palette indices directly. It also follows the reference's three-digit truncation, negative-number clamp/minus, and 1994 sentinel behavior. The world renderer's patch path is unchanged.

| Heading | Initial scene differences / 53,760 | Final scene differences / 53,760 | Initial HUD differences / 10,240 | Final HUD differences / 10,240 |
| --- | ---: | ---: | ---: | ---: |
| 0 | 42,379 | 42,379 | 1,511 | 0 |
| 90 | 36,380 | 36,380 | 1,511 | 0 |
| 180 | 42,700 | 42,700 | 1,511 | 0 |

Receipts: `results/render-reference-e1m1-first.json` and `results/render-reference-e1m1-hud-final.json`. The scene counts are deliberately retained: a repaired HUD does not imply a faithful 3D scene. Texture sampling, lighting and projected boundaries need separate diagnosis and a trusted external reference. Raw palette-index disagreement is not a perceptual quality score.

An intermediate diagnostic (`render-reference-e1m1-hud.json`) observed 171 remaining HUD differences, leading to the fixed-width number repair. The source file changed around completion of that run, and its end-only hash cannot reliably identify the loaded implementation. Treat that receipt as diagnostic history, not source-qualified evidence. The final comparison and HUD suite record source hashes before work and report any changes at completion; neither final run reports changed sources.

## Broader HUD checks

`scripts/Test-HudReference.ps1` passes 64 synthetic single-player states against the adopted status renderer, comparing all 10,240 HUD indices for each. States cover all 64 weapon/key bit combinations, every face index, ready weapons including no-ammo weapons, and numeric boundaries including negative values and the sentinel. The same states also match after real binary asset serialization and seven uneven drawing strips. This checks the flattened ownership-patch array used by render workers without changing the asset format.

`results/hud-reference-first.json` retains these 64 checks. `results/render-partitions-hud-matrix.json` additionally matches 320,000 complete image pixels across five views and seven actual rendering processes, plus 35 Matrix/katakana encoded-strip comparisons at a fixed frame number and viewport origin. No console is presented by these checks, so these are not recordings or display-FPS evidence. Classic and color-art share the corrected source image; their latest live captures still predate this change.

## Remaining work

Compare additional real gameplay endpoints, moving sectors, sprites, sky, palettes and invisibility against an independently established reference. Diagnose sampling and lighting differences separately before changing 3D algorithms. Measure full-host pacing after presentation changes. Record the next E1M4-to-E1M5 terminal continuation with the completed seven-track catalog, retaining footage and audio evidence. Campaign completion, sound at the speakers and 35/60 pacing remain separate gates.

## Fixed-lighting diagnostic

A subsequent `-FixedColorMap 16` fixture applies the same explicit override to the live reference player and numeric snapshot. Scene disagreement falls to 15,772 / 16,347 / 15,603 pixels for headings 0 / 90 / 180; all three HUDs remain exact. Receipt: `results/render-reference-e1m1-fixed16.json`, with unchanged source pins during the run. Source inspection shows different distance-lighting formulas and missing horizontal/vertical wall contrast in the current renderer. This makes lighting a concrete next investigation. A darker common palette can also merge different texel colors, so the reduced mismatch is not a mathematical partition of all errors into lighting versus geometry. No production lighting algorithm changed in this diagnostic.

The corrected HUD is now exercised in the [recorded E1M4 continuation](campaign-e1m4.md). Its full-host performance and audio limits remain visible there. The next rendering step is to compare the 16-level scale/distance light tables and their wall-orientation, sector, extra-light and fixed-map selection against the adopted reference, then check actual images and cost before adoption. A trusted original-executable reference is still needed for a vanilla-fidelity claim.
## Adopted lighting tables and a reference correction

The numeric renderer now uses 16 sector-light bands, 48 projected-scale bins for walls/actors, and 128 distance bins for planes, instead of the earlier linear distance approximations. The tables hold colormap indices and are regenerated by each context, including readers of binary assets. Wall selection includes horizontal/vertical contrast; actor selection includes the player's extra light. Fixed-colormap overrides remain in place. Weapon lighting, invisibility and original-executable reference validation remain separate work.

All 768 scale bins and 2,048 distance bins select exactly the same 256-byte palettes as the adopted reference's independently constructed tables (`results/render-lighting-tables-first.json`). This table test does not by itself certify every rasterizer distance/scale selection.

During image comparison, a remaining wall mismatch exposed a bug in the reference: PowerShell `-eq` compares these distinct Fixed objects unequal even when their Data values match. The explicit equality operator returns true, but the expression does not invoke it. The read-only reproduction is `results/fixed-coordinate-equality-lighting.json`. Correct six comparisons in the reference's three wall-light selection blocks to compare numeric Data. This restores the horizontal decrement and vertical increment specified in [id Software's wall-rendering source](https://raw.githubusercontent.com/id-Software/DOOM/master/linuxdoom-1.10/r_segs.c), including masked walls. No new external code was vendored by this source check. Do not treat the uncorrected reference images as authoritative for wall contrast.

Compare both the old and new numeric rasterizers against that same corrected reference:

| Heading | Previous numeric scene differences / 53,760 | New lighting differences / 53,760 | HUD differences |
| --- | ---: | ---: | ---: |
| 0 | 41,012 | 17,111 | 0 |
| 90 | 36,720 | 17,410 | 0 |
| 180 | 41,823 | 16,935 | 0 |

Receipts are `render-reference-e1m1-old-corrected-reference.json` and `render-reference-e1m1-contrast-corrected.json` under results/. Both pin the corrected engine bundle; the old numeric source is the retained byte-identical local copy from commit 9914b96. The earlier `render-reference-e1m1-lighting.json` compares the candidate against the still-buggy reference and is retained as investigation history. Remaining differences include sampling/projection and other fidelity work; a lower difference count is not a whole-game fidelity certificate.

The fixed-colormap 16 control remains byte-identical in all three views for both renderers across the changes. All 144 discovery cases over 36 maps match the earlier recorded hashes/flags/counters, and discovery leaves pixels untouched. These cross-version comparisons are in `results/render-lighting-controls.json`; the actual sweep is `results/discovery-maps-lighting-reference.json`. Seven actual render workers additionally match all 320,000 image pixels and 35 AnsiArt/katakana encoded strips against serial output (`results/render-partitions-lighting-ansiart.json`).

## Cost of the lighting change

An isolated serial E1M3 comparison alternates baseline/candidate order across four rounds and five static headings, retaining every call, including the first. It uses separate contexts and verifies that shared helper bodies match. Mean times are 59.791 ms before and 57.890 ms after; medians are 54.983/56.241 ms, p95 83.269/93.003 ms and maxima 195.463/101.153 ms. This mixed result does not establish a speedup; the first-call outlier affects the mean. Setup/snapshot work is outside the timed render calls, and no game simulation, audio, encoding or terminal output is included. Raw samples and phase costs: `results/render-lighting-pair-e1m3.json`; harness: `scripts/Measure-RendererPair.ps1`. Full-host pacing must still be measured and reported separately.

The first full-host recording attempt failed before any gameplay because the host imports the asset reader without importing the rasterizer. The worker-only tests did not expose that dependency. Preserve `results/e1m2-lighting-startup-failed-game.json` and `results/e1m2-lighting-startup-failed-capture.json`. Move the unchanged table factory into shared `src/RenderLighting.ps1`, imported independently by both the rasterizer and asset reader. A fresh PowerShell process importing only RenderAssets now reads a real previously generated asset file successfully (`results/render-lighting-standalone-assets.json`), and all 2,816 reference-table bins pass again (`results/render-lighting-tables-shared.json`). The retry uses a fresh recording prefix; the failed footage is retained. The helper move changes dependency loading, not the lighting formulas measured above.

## Classic gameplay verification after the helper fix

The second Classic E1M2-to-E1M3 recording passes all 53 integration checks: 3,233 unchanged commands, all 13 independent state checkpoints, exact campaign/inventory transitions, expected music starts and all 4,073,580 audio frames returned. Source pins include the shared lighting module. The run averages 34.9768 simulation tics/sec and 50.5017 console writes/sec over 92.433 active seconds (95.170 host wall seconds), with two audio-queue-empty observations. Same-world write gaps have p95/p99 28.928/34.923 ms and maximum 193.158 ms. The capture timeline contains one interior zero-filled interval of 1,182 samples (26.80 ms); this is not acoustic continuity evidence. There is no matched earlier Classic run establishing a causal frame-rate change.

Receipts: `results/e1m2-classic-lighting-recorded.json`, `results/e1m2-classic-lighting-timing.json`, and `results/e1m2-classic-lighting-second-route-sources.json`. The full audiovisual recording is `local/recordings/e1m2-classic-lighting-second-av.mp4`; sampled gameplay and E1M3 entry were visually inspected. `e1m2-classic-lighting-preview.mp4` is a separately labeled 20-second cropped excerpt with its full decode and provenance in `results/e1m2-classic-lighting-preview.json`. The failed first window was closed by its recorded owned HWND after checking title/PID; the shared Terminal process was not terminated, and window absence is verified in `results/lighting-owned-window-cleanup.json`.

The Classic recording uses a 688x151 terminal grid with the 320x100 half-block viewport at (184,25). The observed game rectangle is about 1600x900 pixels, illustrating that physical aspect ratio depends on font cells and does not follow automatically from a 320x200 framebuffer. Font sizing/aspect correction, remaining texture/projection differences, weapon lighting and invisibility remain open. The new lighting is adopted with these limits and the measured cost visible.
