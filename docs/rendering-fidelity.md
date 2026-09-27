# Rendering fidelity: first reference comparison and HUD repairs

## Transparent-wall draw order correction (2026-09-19)

The near-first geometry pass painted masked middle textures immediately while leaving their portal open. Farther walls and the subsequent plane fill could then replace solid fence pixels and their depth. The renderer now queues visible masked columns, draws opaque scenery first, and composites those columns with depth testing before actors. Texture coordinates, pegging and lighting selection are unchanged. Actors remain visible through holes and are hidden by nearer bars.

`scripts/Test-MaskedWallOrder.ps1` exercises the actual whole-scene rasterizer with authored geometry and colors, without a game session or WAD. All 14 checks pass in `results/masked-wall-order-final.json`: wall/floor visibility, retained depth, actors on both sides, overlapping fences and seven uneven column partitions. The same final test fails against the preserved old renderer (`masked-wall-order-baseline-final.json`, expected fence color 200, actual far-wall color 100). The initial two candidate receipts contain test implementation errors (array typing and a flattened sprite atlas); they are preserved and do not represent renderer failures.

Existing fuzz coverage passes 119 checks (`masked-wall-fuzz-regression.json`). The actual seven-process Matrix/katakana test matches 320,000 pixels and 35 encoded strips, including palettes and invisibility (`masked-wall-workers-matrix-first.json`). These are correctness checks, not new live effect tests.

The offline adopted-reference comparison completes at E1M1 headings 0/90/180 (`masked-wall-reference-second.json`), with 16,789/17,088/16,613 differing scene indices out of 53,760 and no differing HUD indices. This is still substantial disagreement, not original Doom parity; it does not isolate a performance or whole-scene fidelity improvement from this fix. The first comparison invocation failed argument validation because native array argument passing was incorrect; the second uses the script's default headings. No game window or recording was opened. Deferred-column allocation and draw cost have not yet been performance-qualified.

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

Compare additional real gameplay states, moving sectors, sprites, sky, palettes and invisibility against the adopted reference, while pursuing an independently established original-executable reference. The E1M4-to-E1M5 terminal continuation is already recorded in [campaign E1M4](campaign-e1m4.md). Current fixed-camera E1M2/E1M3 diagnostics are summarized below; they do not replace gameplay, acoustic or 35/60 pacing evidence.

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

## Weapon lighting correction

The former numeric weapon pass always selected colormap zero, keeping guns full-bright in dark sectors and ignoring fixed-map power-up coloring. Draw-FastPlayerSprites now uses the player sector's light band plus ExtraLight and the final scale-light bin, recognizes the full-bright frame flag, and gives a nonzero fixed colormap priority. This matches non-invisibility selection in [id Software's R_DrawPSprite/R_DrawPlayerSprites](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_things.c) and the adopted PowerShell reference. No external source body was copied. Invisibility/fuzz rendering remains open.

Player-sector light comes from the simulation endpoint, travels through object/direct snapshots in formerly reserved header slot 43 and is decoded as ConsolePlayer.SectorLight. It stays discrete while positions interpolate. Packet length and all existing field offsets remain unchanged. This internal extension does not promise interchangeability with old workers; the host launches workers from the same source tree.

`results/weapon-lighting-first.json` compares 138 complete isolated weapon images against the adopted ThreeDRenderer. It covers all 16 light bands, fixed maps 16/32, full-bright flags, extra-light/clamp boundaries and ready/flash states for Ultimate Doom's eight weapons. All 64,000 indices per case match, including unchanged background. All cases also match through binary assets, snapshot serialization and seven uneven strips. The former full-bright draw call is a negative control and disagrees in 88 cases. This establishes the tested weapon fixtures against the adopted reference, not whole-scene or original-executable equivalence.

Actual worker tests pass separately for Classic/ColorState, Matrix/katakana and AnsiArt/katakana: each matches 320,000 pixels and 35 encoded strips across five views. Receipts are `results/render-partitions-weapon-lighting-classic.json`, `-matrix.json` and `-ansiart.json`. These are headless correctness checks, not displayed-FPS measurements.

The initial all-map/route snapshot test passed 336 complete byte comparisons but failed historical replay hashes because checkpoints include a render-packet digest. Preserve `results/direct-snapshots-weapon-lighting.json`. Schema1 checkpoint hashing now retains the historical zero-valued reserved header slots, with a separate CurrentRenderSnapshotSha256 outside that legacy digest. Existing sector-array lighting and every previously hashed gameplay field remain in the legacy hash. Six explicit controls prove historical-hash preservation, current-packet hash retention, lighting/health change detection and exact restoration (`results/checkpoint-weapon-lighting-schema.json`). The repeated all-36-map endpoint and E1M2 route test passes 336 comparisons, 3,233 commands and all 13 historical checkpoints (`results/direct-snapshots-weapon-lighting-second.json`). Eight wire/interpolation checks also pass with deliberately different old/current sector light (`results/snapshot-weapon-lighting.json`).

The full Classic E1M2 continuation into E1M3 passes 65 integration checks with all 3,233 commands, 13 historical checkpoints, inventory transitions and 4,073,580 returned audio frames. Mean rates are 34.980 tics/sec and 56.565 console image writes/sec; same-world gap p95/p99/max is 24.258/31.639/199.478 ms. Three queue-empty observations and one interior alignment fill of 1,190 audio frames remain, with no API discontinuity reported. This is one integration capture, not a causal performance comparison or acoustic guarantee. Receipts: `results/weapon-lighting-classic-first-recorded.json`, `-timing.json` and `-route-sources.json`. The full movie is `local/recordings/weapon-lighting-classic-first-av.mp4`; gameplay, intermission, entering-map and final E1M3 frames were inspected. Owned game processes/window closed normally, with PID reuse checked by start times in `results/weapon-lighting-cleanup-and-review.json`.

Texture/projection differences, world/weapon invisibility, palette presentation, physical aspect, campaign completion and acoustic/performance qualification remain release requirements.

## Invisibility and Spectres (September 19)

The numeric renderer previously drew every actor and weapon as opaque. It now uses the player's remaining invisibility time and actor Shadow flags to choose background fuzz. The framebuffer operation samples the adjacent row in the same column and applies colormap6, with transparent sprite holes, depth clipping, and protected view borders. Player fuzz wins over full-bright frames and fixed lighting. The final power-up period blinks according to the existing >128 or bit8 condition. Shadow-containing scenes sort actors far to near so a Spectre can distort a previously drawn actor behind it.

The operation was checked against the adopted GPL ThreeDRenderer and source-inspected against [id Software's fuzz column](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_draw.c) and [player-sprite selection](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_things.c). RenderFuzz.ps1 credits the adopted offset table. Original Doom advances one global phase through all fuzz pixels; this renderer seeds each absolute column from game tic instead. This deliberate visual approximation avoids worker-boundary seams and scheduling-dependent images. It does not establish vanilla pixel fidelity.

Evidence: results/fuzz-rendering-first.json passes111 checks of reference column operations, scale/flip/clipping/holes/depth, reversed uneven strips, real power timers, blink edges, fullbright/fixed precedence and animation. results/render-partitions-fuzz-{classic,matrix,ansiart}.json each pass320,000 indexed pixel comparisons and35 encoded strips through actual worker processes, including a visible shadow-actor negative control. results/weapon-lighting-fuzz-regression.json retains138 non-fuzz reference images. These are correctness measurements, not performance trials.

NumericV2 retains the previous position offsets, uses header44 for invisibility and appends one flag value per actor after weapon records. Both producers, decoding, interpolation and endpoint pairing retain these fields as discrete state. results/snapshot-fuzz-second.json passes8 synthetic checks; results/direct-snapshots-fuzz-first.json covers all36 maps and all3233 E1M2 commands with336 exact packet comparisons and13 legacy checkpoints. Its inherited report wording says NumericV1/unchanged serializer; source hashes and version2 bytes establish the actual current-producer comparison, not equality to old packets.

Schema1 replay hashes retain the historical version1 packet shape, zero reserved header, and no appended flags. New checkpoints also tag and compare the full version2 packet hash. Thirteen controls in results/checkpoint-fuzz-third.json show that old evidence still matches, and new recordings detect changed invisibility/actor flags. Old checkpoints never contained those fields and cannot retroactively validate them. The failed camera-actor test is retained in checkpoint-fuzz-first.json.

A dedicated visual fixture grants invisibility, shortens its remaining duration to210tics and spawns a Spectre ahead of the E1M1 camera. It loads via the actual save/replay system and runs350 idle commands, with17 independent checkpoints through expiry. It is not campaign completion or an ordinary pickup route. Local saves stay outside Git. Live recording results follow after validation.

The initial three recorded fixtures matched all17 replay checkpoints, but an independent audit rejected them for expiry coverage: the Spectre killed the idle player, freezing the timer at46. Original movies and their hashes are retained in results/fuzz-first-captures-rejected-for-expiry.json. The corrected fixture explicitly sets player/actor health to999 so the normal timer can expire while damage continues normally. This is test setup, not a gameplay-rule change. Its generator now refuses to publish unless the final player is alive and invisibility is zero. results/fuzz-recording-fixture-third.json records health867 at expiry and727 after350 commands.

Additional focused tests bring coverage to119 checks: actual actor flags survive object/direct transport, reversing thinker order leaves overlapping opaque/shadow actors identical, and removing the actor behind a Spectre changes the result. See results/fuzz-rendering-second.json. This demonstrates background compositing in the tested scene; wider texture/projection and masked-wall fidelity remain separate work.

### Recorded effect validation

The corrected Classic, Matrix and AnsiArt captures each pass 34 checks in scripts/Test-FuzzRecording.ps1: all 350 commands, 17 independent state/full-packet checkpoints, exact save load, presentation during active/blinking/expired phases, pinned sources/media, complete movie decoding, and clean owned-window/process exit. Each returns all 441,000 submitted sound frames. This scene contains sound effects, not a music qualification. The existing replay-format suite also passes all 58 checks.

| Recorded style | Simulation tics/sec | Image writes/sec | Same-world p95 gap | Same-world maximum gap |
| --- | ---: | ---: | ---: | ---: |
| Classic | 34.896 | 23.330 | 54.022 ms | 526.971 ms |
| Matrix | 34.894 | 31.405 | 40.101 ms | 582.696 ms |
| AnsiArt | 34.900 | 30.313 | 44.019 ms | 577.342 ms |

These are loaded, recorded ten-second fixtures with a nearby attacking Spectre and save-load handoff, not isolated comparisons or proof of a causal fuzz slowdown. All-gap maxima including handoff are about 2.9–3.0 seconds. Audio queue-empty observations are 2/2/3; capture alignment inserts 1,157/1,160/1,157 interior audio frames. Neither returned buffers nor mux validation proves acoustic continuity. All figures remain below the intended presentation target; scene/effect cost and pacing require further work.

Portable receipts: results/fuzz-{classic,matrix,ansiart}-second-recorded.json and -second-timing.json. Original recordings: local/recordings/fuzz-{classic,matrix,ansiart}-second-av.mp4. Review initially sampled the loading screen twelve seconds before the end; corrected ten-second samples show active invisibility, and four-second samples show the opaque pistol after expiry. The character modes make the dark distortion less distinct, especially Matrix, and retain the existing readability/physical-size limitations. These frames do not establish exact pixel fidelity or displayed frame rate. results/fuzz-cleanup-and-visual-review.json retains all nine inspected image hashes and verifies cleanup for all six first/corrected captures without terminating anything.

Reproduce the fixture with scripts/New-FuzzRecordingFixture.ps1 using fresh Output and SaveRoot paths. Pass its replay and SaveRoot to scripts/Record-DoomReplay.ps1 with the selected style, RecordInput, CaptureAudio, local capture/media tools, Seconds45, StartupTimeoutSeconds180, Maximized and ExpectedExit ReplayEnd. Then run scripts/Test-FuzzRecording.ps1 with the matching Prefix, Replay and a fresh Output. The save is artificial and private; user-owned assets are required. The exact invocations and file names are retained in the investigation ledger and receipts.

The [fuzz performance follow-up](fuzz-performance.md) preserves the effect's indexed pixels and depth while computing each source row only once per sprite. Thirty paired image/depth comparisons and the 119 focused checks pass. New recordings pass all 34 checks per style and all 17 replay checkpoints, averaging about 34.9 game tics and 41–46 image writes/sec. These retain the original pattern approximation and unresolved pacing/audio/readability limits; they do not establish 60 displayed frames/sec.

## Palette presentation, September 19

The new [palette path](palette-presentation.md) carries damage, pickup bonus, berserk and radiation-suit selections through gameplay snapshots and indexed automap screens. Classic applies selected PLAYPAL RGB; AnsiArt applies its existing mapping to those colors; Matrix remains green while luminance changes. Full-screen menus deliberately use base colors. Selection/encoding/worker and headless-host checks pass; all three styles now pass the55-check recorded palette fixture. This corrects a missing effect without establishing full projection, gamma or original-executable equivalence.

## Additional Episode 1 static views (2026-09-26)

The same pinned engine bundle and Steam IWAD were compared at E1M2 and E1M3 after 35 idle updates, with the camera fixed at 0, 90 and 180 degrees. This exercises two new map-start scenes, not player navigation, moving sectors or map completion. The HUD is exact at every view. Scene disagreement against the adopted PowerShell reference is:

| Map | Baseline scene differences / 53,760 (0°, 90°, 180°) | Fixed-colormap-16 differences / 53,760 (0°, 90°, 180°) | HUD differences |
| --- | --- | --- | ---: |
| E1M2 | 13,377 / 19,024 / 14,238 | 10,326 / 14,553 / 10,514 | 0 |
| E1M3 | 19,434 / 17,458 / 18,440 | 14,134 / 13,068 / 14,125 | 0 |

The fixed-colormap control reduces index disagreement in both maps, but it changes the palette lookup itself; the reduction cannot be assigned mathematically to lighting alone. It leaves 19.2–27.1% of scene indices different. Mean absolute RGB-channel error is much smaller (2.01–3.90 levels), showing that many changed indices are visually near neighbors without proving exact color or texture sampling. Detailed source pins, raw report hashes and limits are in `results/render-reference-e1m2-e1m3-fidelity.json`; individual reports are `render-reference-e1m{2,3}-fidelity-{baseline,fixed16}.json`. PNG comparisons remain under ignored `local/render-reference-e1m{2,3}-fidelity-*`. The reference is not independently verified original-executable output.

The wall and plane sampling follow-up below isolated a horizontal half-pixel offset against Doom's integer-column angle lookup. Other fixed-point projection, vertical sampling, moving-sector, and independent original-executable differences remain open.

## Integer-column sampling correction (2026-09-26)

The previous numeric path sampled wall perspective interpolation, screen rays, and horizontal floor/ceiling coordinates at `x+0.5`. The adopted Doom renderer chooses each ray from its integer `xToAngle[x]` table. For example, column 160 maps to 0 degrees in that table; the former analytic half-pixel ray was about -0.18 degrees. Change those four horizontal sampling expressions to use `x`, leaving raster edge coverage and vertical sampling unchanged.

At the same E1M2/E1M3 map starts after 35 idle updates, compare the old and new renderer against the same adopted reference and IWAD. The HUD remains exact. All six views improve:

| Map | Heading | Scene indices different before / 53,760 | After | Reduction | RGB-channel MAE before → after |
| --- | ---: | ---: | ---: | ---: | ---: |
| E1M2 | 0° | 13,377 | 8,490 | 36.53% | 2.0075 → 1.3813 |
| E1M2 | 90° | 19,024 | 12,695 | 33.27% | 3.8677 → 2.9297 |
| E1M2 | 180° | 14,238 | 10,264 | 27.91% | 2.5775 → 2.0480 |
| E1M3 | 0° | 19,434 | 13,014 | 33.03% | 3.6632 → 2.5512 |
| E1M3 | 90° | 17,458 | 9,564 | 45.22% | 3.9025 → 2.3936 |
| E1M3 | 180° | 18,440 | 11,511 | 37.58% | 3.2431 → 1.9118 |

Across 322,560 scene pixels, differing palette indices fall from 101,971 to 65,538 (35.73% fewer); the new views still differ in 17.8–23.6% of scene indices. The bundle and IWAD hashes are pinned in [the combined receipt](../results/render-column-index-fidelity.json). Raw reports: [E1M2 before](../results/render-reference-e1m2-fidelity-baseline.json), [E1M2 after](../results/render-reference-column-index-e1m2.json), [E1M3 before](../results/render-reference-e1m3-fidelity-baseline.json), and [E1M3 after](../results/render-reference-column-index-e1m3.json). This is a static map-start comparison to the adopted PowerShell reference, not independent original-executable evidence, route completion, or a performance test.

The change preserves exact serial/seven-strip output in five views for Classic, Matrix with Katakana, and AnsiArt with Katakana: 320,000 indexed pixels per style plus 35 encoded strip checks. A stored E1M1 fixed-input replay also passes through the actual headless host with 1,747 commands, eight checkpoints, and E1M2 entry. These verify worker and session integration; the headless frames are not displayed-FPS evidence. Remaining texture and projection differences need separate fixtures before further algorithm changes.

## Integer-row wall texture sampling (2026-09-26)

The adopted renderer's `ThreeDRenderer.DrawColumnData` starts a wall column's texture fraction at `(y1 - centerY) * invScale`, then advances one row at a time. The numeric renderer instead evaluated the wall fraction at `y+0.5`; its deferred masked-wall pass did the same. Change both opaque and masked world-wall samples to integer row `y`. Keep floor and ceiling planes on half-row centers: the reference's `ResetPlaneRendering` explicitly adds one half to its vertical offset, so this is a wall-only correction.

Repeat the same static E1M2/E1M3 map-start comparison against the adopted reference at 0/90/180 degrees. Every view improves over the integer-column version, all HUD indices remain exact, and RGB-channel error decreases in all six views:

| Map | Heading | Scene indices before / 53,760 | After | Further reduction | RGB-channel MAE before → after |
| --- | ---: | ---: | ---: | ---: | ---: |
| E1M2 | 0° | 8,490 | 7,189 | 15.32% | 1.3813 → 1.1657 |
| E1M2 | 90° | 12,695 | 8,343 | 34.28% | 2.9297 → 1.8081 |
| E1M2 | 180° | 10,264 | 6,644 | 35.27% | 2.0480 → 1.2046 |
| E1M3 | 0° | 13,014 | 8,378 | 35.62% | 2.5512 → 1.6357 |
| E1M3 | 90° | 9,564 | 5,153 | 46.12% | 2.3936 → 1.0248 |
| E1M3 | 180° | 11,511 | 7,043 | 38.82% | 1.9118 → 1.1647 |

Across the six views, the combined horizontal and vertical wall corrections reduce disagreement from 101,971 to 42,750 of 322,560 scene pixels (58.08% fewer than the original numeric baseline). The corrected output still differs in 9.59–15.58% of scene indices. This is comparison to the adopted PowerShell renderer, not independently verified original-executable output; it establishes neither gameplay fidelity nor a frame-rate improvement. Raw reports and source/IWAD hashes are in [the combined receipt](../results/render-integer-row-fidelity.json), with [E1M2](../results/render-reference-integer-row-e1m2.json) and [E1M3](../results/render-reference-integer-row-e1m3.json) details.

Seven-process output remains exact in five views for Classic, Matrix/Katakana, and AnsiArt/Katakana: each style matches 320,000 indexed pixels and 35 encoded strips. A fresh skill-3 smoke loads all nine Episode 1 maps, advances 35 idle tics and renders two full frames per map. These checks establish renderer/worker integrity and startup smoke only, not map completion or displayed FPS. Sprite and weapon sampling, fixed-point geometry, moving-world comparisons and an independent original-executable reference remain open.

## Fixed-point plane mapping and strip phase (2026-09-26)

The adopted renderer's `ResetPlaneRendering` builds fixed-point floor/ceiling
distance scales, and its plane drawers start each visible span from the current
column's fine-angle ray before stepping texture coordinates horizontally. The
numeric renderer had mapped floor and ceiling texels with continuous doubles.
The replacement uses the engine's fine-sine table, per-column angle/distance
tables, half-row slopes, and 16.16 span stepping. Gameplay rules, walls, sprites,
weapons, and HUD rendering do not change.

Independent render workers begin their spans at their own left edges. A first
fixed-point candidate restarted its scanline spans at those edges while a
full-frame render restarted at the actual plane-run start, so their flat texel
indices differed near strip boundaries. Recomputing every sample from its
absolute column restored exact output but lost the fidelity gain. The adopted
path records the pool's strip boundaries in the disposable `assets-v4`
transport and makes the serial comparison renderer restart at those same
boundaries. The production workers still render only their assigned strips.

At E1M2 and E1M3 map start after 35 idle updates, with sixteen Classic worker
strips, the six views improve against the adopted PowerShell reference:

| Map | Heading | Scene indices before / 53,760 | After | Reduction | RGB-channel MAE before → after |
| --- | ---: | ---: | ---: | ---: | ---: |
| E1M2 | 0° | 7,189 | 6,389 | 11.13% | 1.1657 → 1.0541 |
| E1M2 | 90° | 8,343 | 7,096 | 14.95% | 1.8081 → 1.6447 |
| E1M2 | 180° | 6,644 | 6,149 | 7.45% | 1.2046 → 1.1427 |
| E1M3 | 0° | 8,378 | 7,630 | 8.93% | 1.6357 → 1.5363 |
| E1M3 | 90° | 5,153 | 3,966 | 23.04% | 1.0248 → 0.8694 |
| E1M3 | 180° | 7,043 | 6,568 | 6.74% | 1.1647 → 1.1054 |

Across 322,560 scene pixels, the prior integer-column plus integer-row result
had 42,750 differing indices; fixed-point plane mapping has 37,798 (11.58%
fewer). All six HUDs remain exact. The remaining scene mismatch is 7.38–14.19%.
This is a static comparison to the adopted PowerShell renderer, not a verified
original-executable image or a campaign-play result. See the [combined
receipt](../results/render-fixed-plane-fidelity.json) and its [E1M2](../results/render-fixed-plane-reference-e1m2-16.json)
and [E1M3](../results/render-fixed-plane-reference-e1m3-16.json) reports.

With sixteen actual worker processes, Classic, Matrix/Katakana, and
AnsiArt/Katakana each match serial output across five E1M1 views: 320,000
palette indices and 80 encoded strips per style. The [worker receipts](../results/render-fixed-plane-fidelity.json)
record the pixel and byte checks. An actual headless E1M1-to-E1M2 host replay
also reloads the v4 assets without restarting workers; all eight available
checkpoints match and the final asset generation is E1M2. The [session
receipt](../results/renderer-assets-map-transition-fixed-plane.json) reports
34.97 simulation tics/sec and 59.18 scheduled render updates/sec, with no
terminal frames written. That does not measure monitor presentation.

The alternating six-round serial-render comparison has 30 samples per map and
different source hashes for baseline and candidate. Median full-frame render
time rises from 46.48 to 51.35 ms on E1M2 and from 43.46 to 46.07 ms on E1M3;
the p95 values are 101.65 to 94.95 ms and 71.46 to 72.01 ms respectively.
These single-process timings are not end-to-end worker or displayed-FPS
measurements. An earlier pair of timing files had identical baseline/candidate
hashes and was rejected; no performance claim relies on them. The accepted
timing receipts are linked from the [combined receipt](../results/render-fixed-plane-fidelity.json).

The current-source Episode 1 smoke passes all nine maps at skill 3 after 35
idle tics, with two rasterizations per map. The [smoke receipt](../results/episode1-render-fixed-plane-smoke-current.json)
is not evidence of exits or human completion. Jason's single full Episode 1
playthrough remains pending.

## Fixed-point sprite column sampling (2026-09-26)

`Draw-FastPatch` had been starting a projected actor or weapon at
`Ceiling(left)` and deriving source columns from the fractional world-space
edge. The adopted `ProjectSprite`/`DrawPlayerSprite` path floors the projected
left edge to its first screen column, then advances the source fraction by a
fixed-point inverse scale for each screen column. The numeric patch drawer now
uses that integer anchor and 16.16 stepping, including mirrored sprites and
worker-strip clipping. Vertical sampling, transparency, lighting, depth tests,
and gameplay are unchanged.

A real E1M1 pistol fixture shifted the active weapon through seven fractional
horizontal offsets and compared its final pixels with and without the weapon
in both renderers. The pre-change source differed in 6,483 pixels within the
union of weapon coverage; the corrected renderer has zero final-pixel
mismatches across all seven offsets. Its [focused receipt](../results/weapon-projection-sampling-final.json)
and [comparison summary](../results/weapon-projection-sampling-comparison.json)
explain why changed-pixel masks alone are ambiguous when a weapon texel equals
the scene color behind it.

The static map-start comparison at five headings each on E1M1 and E1M2 reduces
scene-index disagreement with the adopted PowerShell reference from 40,632 to
39,098 of 537,600 pixels (3.78% fewer); all ten HUDs remain exact. This
reference is not independently verified original-executable output. Actual
sixteen-process output remains pixel- and byte-exact for Classic,
Matrix/Katakana and AnsiArt/Katakana, and the current renderer passes the
36-map, skill-3, 35-idle-tic smoke. The [worker receipts](../results/weapon-projection-sampling-comparison.json),
[smoke receipt](../results/weapon-projection-smoke-current.json), and
[138-case weapon-lighting regression](../results/weapon-projection-lighting-current.json)
are linked with hashes.

Paired serial full-frame measurements retained 20 calls per version and map.
Median time rose from 44.96 to 46.29 ms on E1M1 and from 39.35 to 39.51 ms on
E1M2. This change has a measured fidelity benefit, not a performance claim;
worker end-to-end and displayed frame rate remain open. The exact old and new
source hashes, raw samples, and function-isolation method are recorded in the
[comparison summary](../results/weapon-projection-sampling-comparison.json).

## Weapon vertical-offset control (2026-09-26)

After the horizontal correction, a separate E1M1 pistol fixture shifted the
weapon vertically through seven fractional offsets from -0.75 to +0.75 pixels.
The current renderer matched the adopted reference's final pixels in all seven
cases. This rules out a simple subpixel-Y alignment defect for the scale-1
first-person weapon; it does not test perspective-scaled world sprites, their
individual masked posts, or establish original-executable parity. The
[PowerShell harness](../scripts/Compare-WeaponPatchVerticalSampling.ps1) and
[source-pinned receipt](../results/weapon-projection-vertical-offsets.json)
preserve the exact scope and result.

## Perspective world-sprite post sampling (2026-09-26)

The numeric world-sprite path sampled flattened patches with floating-point
division. Doom's adopted renderer instead advances a 16.16 row fraction from
the projected origin, clips each opaque post at its fixed-point bounds, and
masks the post-local source row to 128 entries. A first comparison on the real
Steam `DOOM.WAD` `TROOA1` patch found 838 differing indices in five of 40
scale/origin cases. Preserving just the fixed-point row step still disagreed at
post boundaries; the final drawer retains each post and matches its clipping,
fraction origin, and 128-entry source-row mask.

The harness covers ten perspective scales (0.18 through 3.875) and four
vertical texture origins (20, 20.125, 50.75, 100) on the 41x57 patch, including
empty and multi-post columns. Both sides use the same fixed projected columns,
screen bounds, and color map to isolate patch sampling. The final result is
zero pixel-index differences in all 40 cases. Before/after raw receipts are
[`world-sprite-vertical-sampling-before.json`](../results/world-sprite-vertical-sampling-before.json)
and [`world-sprite-vertical-sampling-verified.json`](../results/world-sprite-vertical-sampling-verified.json);
the reproducible harness is
[`Compare-WorldSpriteVerticalSampling.ps1`](../scripts/Compare-WorldSpriteVerticalSampling.ps1).

The first 16-process run revealed that the old disposable asset cache flattened
away sprite posts. Asset format v5 now carries the opaque post bounds, each
post's source-buffer reference, and its offset, so workers retain the same
row-wrap behavior without duplicating a 128-byte window per post. A real-IWAD
cache measured 37,924,656 bytes versus 29,222,789 bytes for v4 (29.8% larger);
this is an asset-size observation, not a timing or working-set measurement.
Validation after that change includes the 36-map, skill-3, 35-idle-tic,
two-frame smoke; 320,000 exact serial/worker pixels across five views for
Classic, Matrix/Katakana, and AnsiArt/Katakana; 138 player-weapon lighting
images through the v5 asset round trip; and an E1M1-to-E1M2 reload in sixteen
live workers with 256,000 matching pixels and 64 encoded strips. Receipts:
[`campaign smoke`](../results/campaign-smoke-world-sprite-verified.json),
[`Classic workers`](../results/render-worldsprite-classic-verified.json),
[`Matrix workers`](../results/render-worldsprite-matrix-verified.json),
[`AnsiArt workers`](../results/render-worldsprite-ansiart-verified.json),
[`weapon lighting`](../results/weapon-lighting-assets-v5-verified.json), and
[`E1M2 worker reload`](../results/worker-assets-v5-dedup-map-reload.json).

These checks establish parity with the adopted PowerShell rasterizer's patch
algorithm and exact output across this implementation's worker boundary. They
do not test actor world projection or occlusion against the original
executable, establish whole-game visual parity, certify campaign completion,
or measure performance. No speed claim is made.

## Fixed-point actor projection (2026-09-26)

The numeric world-sprite path now uses the adopted renderer's 16.16 transform
for actor depth, horizontal scale, projected patch bounds, light-table index,
and vertical texture origin. The worker path expresses those operations as
integer PowerShell arithmetic over its transferred lookup tables; it does not
load engine class types into rendering workers. A null rotated patch is skipped
as in the reference. Fixed-point rotated-frame selection is now included; its
focused mathematical scope and remaining visual limits are recorded below.

At three static idle views, the full-scene scene-index differences changed as
follows against the adopted PowerShell reference:

| Map and diagnostic state | Heading 0 | Heading 90 | Heading 180 | Total |
| --- | ---: | ---: | ---: | ---: |
| E1M1, normal colormap | 4,388 → 4,365 | 4,607 → 4,556 | 5,043 → 5,026 | 14,038 → 13,947 |
| E1M2, fixed colormap 1 | 7,012 → 6,997 | 8,087 → 7,838 | 6,534 → 6,351 | 21,633 → 21,186 |

The E1M2 diagnostic reduces total scene differences by 447 (2.07%); the E1M1
set reduces them by 91 (0.65%). These are whole-scene counts, not an
actor-only mask, and they do not prove original-executable pixel parity. The
[portable receipt](../results/actor-projection-fixedpoint-comparison.json)
includes the IWAD, source hashes, worker checks, and paired render measurements.

Classic, Matrix/Katakana, and AnsiArt/Katakana each match their serial output
exactly across 16 process workers and five views (320,000 pixels per style).
The current renderer also passes a 36-map load/35-idle-tic/two-frame smoke.
Neither result is a map completion test. Three-round paired serial timings
show a median paired cost of 0.57 ms (0.78%) on E1M1 and 1.40 ms (3.00%) on
E1M2. The individual samples vary substantially; this is a documented
fidelity tradeoff, not a performance or displayed-FPS claim. Moving actors,
occlusion cases, and independent original-executable comparison remain open.

## Fixed-point rotated actor-frame selection (2026-09-26)

The previous numeric renderer selected rotated sprite frames using floating-
point `Atan2`, angle subtraction, and `Floor`. The adopted renderer uses
`Geometry.PointToAngleData`'s Doom tangent lookup followed by unsigned
32-bit-angle arithmetic and a three-bit frame selection. At exact rotation
boundaries, the former formula selected a different frame in 172,724 of
393,408 synthetic boundary cases.

`Get-FastPointAngleData` and `Get-FastSpriteRotation` now reproduce that lookup
and wrap behavior in PowerShell integer arithmetic. Asset format v6 transports
the 2,049-entry tangent-to-angle lookup to render workers and checks its length
and endpoints when reading it. This extends the prior v5 world-sprite-post
payload; it does not introduce a compiled rendering helper.

[`Test-SpriteRotation.ps1`](../scripts/Test-SpriteRotation.ps1) compares against
the actual adopted `Geometry.PointToAngleData` and `ThreeDRenderer` logic. It
passes 16,392 direction cases, all 393,408 boundary selections, six signed-int
minimum edges, and 100,000 binary-angle round trips, with no candidate
mismatches. The old `Atan2` expression reproduces its 172,724 boundary
mismatches. This is focused math evidence; it is not a moving-monster visual,
animation, occlusion, route, or original-executable test.

Classic, Matrix/Katakana, and AnsiArt/Katakana each match serial output across
16 workers and five views: 320,000 pixels and 80 encoded strips per style, with
zero differences. The current v6 source also passes the 36-map load, 35-idle-
tic, two-frame smoke. These checks prove asset transport and serial/worker
agreement, not map completion or displayed frame rate.

The focused E1M1-to-E1M2 asset-reload fixture rewrites v6 assets under a
sixteen-process Classic render pool. All worker process IDs remain unchanged,
and the post-reload E1M2 frame matches serial output across 256,000 pixels and
64 encoded strips. This directly checks current-format worker refresh; it uses
a synthetic map-change fixture rather than ordinary episode navigation. The
[receipt](../results/session-worker-sprite-rotation-classic.json) records the
scope.

Paired serial renders used three alternating-order rounds at five static
headings per map, retaining first calls and excluding setup from the timed
calls. The median of the 15 paired deltas is -0.2551 ms (-0.40%) on E1M1 and
-0.1845 ms (-0.41%) on E1M2. The separate aggregate medians disagree on E1M2
(50.8199 ms baseline; 54.8397 ms candidate), showing enough sample variation
that the paired statistic cannot support a speedup claim. These are isolated
full-frame render timings, not simulation pacing, worker end-to-end, terminal
output, or visible FPS. The [parity](../results/sprite-rotation-parity.json),
[worker](../results/render-partitions-sprite-rotation-classic.json),
[map-smoke](../results/campaign-smoke-sprite-rotation.json), and
[paired timing](../results/sprite-rotation-performance-e1m1.json) receipts keep
the scope and hashes; the E1M2 timing is in the sibling receipt.

## Moving actors on a recorded E1M1 prefix (2026-09-26)

The static map-start diagnostics did not exercise changing visible actor
positions, so a bounded comparison now reuses the first 280 commands from the
already-qualified [E1M1 route regression](../results/e1m1-route-lineflags.json).
It stops before the route's exit and does not construct a new route. At eight
35-tic endpoints, the adopted PowerShell reference reports five visible world
sprites at tic 35, three at tic 70, one at tic 105, and none at tic 140; at
least one visible sprite changes projected position during the prefix. The
numeric renderer and reference have identical HUD indices at all eight
samples; full-scene disagreement ranges from 742 to 8,917 palette indices out
of 53,760.

The paired images show broad wall and floor differences; no actor-specific
rendering defect is isolated in these frames. This is an inconclusive visual
diagnostic, not proof of sprite parity: the receipt counts full-scene pixels
and does not subtract each renderer's actor-free background. It compares with
the adopted, locally adapted PowerShell renderer, not an independently
validated original executable. Occlusion across more viewpoints, moving
sectors, broader animation states, and independent original-engine comparison
remain open.

The PowerShell comparison harness is
[`Compare-MovingActorReference.ps1`](../scripts/Compare-MovingActorReference.ps1);
the source-pinned receipt is
[`moving-actor-reference-e1m1-prefix-images-20260926.json`](../results/moving-actor-reference-e1m1-prefix-images-20260926.json).
The eight diagnostic PNGs stay in ignored `local/` because they contain
commercial game imagery; their paths and hashes are in the receipt. The
intermediate idle-only attempts are retained under ignored
`local/moving-actor-reference-iterations-20260926/` and are not counted as
moving-actor coverage.

Reproduce with the same Ultimate Doom IWAD and fresh result/image paths:

```powershell
pwsh -NoProfile -File .\scripts\Compare-MovingActorReference.ps1 `
  -Episode 1 -Map 1 -Tics 280 -Interval 35 `
  -InputReplay .\results\e1m1-route-lineflags.json `
  -Images .\local\moving-actor-render-images `
  -Output .\results\my-moving-actor-reference.json
```

## Doom sky-column and vertical-wrap sampling (2026-09-26)

The numeric rasterizer selected sky columns with an analytic `Atan` expression
and clamped vertical coordinates. The adopted renderer instead adds Doom's
32-bit view angle to its per-column angle lookup, takes the high ten angle
bits, wraps the column by sky width, and samples a 128-row texture with a
fixed-point vertical fraction masked by 127. At this 320x200 viewport the
reference uses scale 65536 and texture altitude 6553600, so source row is
`(screenY + 16) & 127`.

`Invoke-FastRender` now uses its existing Doom column-angle table and exact
unsigned angle wrap for sky columns. The sky row wraps vertically instead of
sticking to row 127. Power-of-two sky widths use a mask; other widths use
positive modulo. The scratch column map is initialized in both the host render
context and the deserialized worker context; no asset format change is needed.

[`Test-SkySampling.ps1`](../scripts/Test-SkySampling.ps1) exercises the actual
production sky-column map, then compares all 320 columns and 168 scene rows at
eight headings with `ThreeDRenderer.DrawSkyColumn`. The Doom angle lookup has
zero mismatches, and all 430,080 sampled sky pixels match the adopted renderer
exactly. This directly qualifies the sky sampler against the locally adapted
PowerShell reference; it is not original-executable or whole-engine pixel
parity.

The final source passes exact serial/16-process equivalence across five views
in Classic, Matrix/Katakana, and AnsiArt/Katakana: 320,000 pixels and 80
encoded strips per style. The current-source 36-map smoke also passes at 35
idle tics and two frames per map. The before/after E1M1 map-start whole-frame
comparisons are identical at the eight selected headings (HUD differences
remain zero); those particular scene frames do not demonstrate a whole-frame
sky delta. The isolated sampler receipt is the evidence for this correction.
No 35-tic/60-display or performance claim follows from these checks.

Receipts: [isolated sampling](../results/sky-sampling-20260926-v3.json),
[Classic workers](../results/render-partitions-sky-classic-20260926-v3.json),
[Matrix workers](../results/render-partitions-sky-matrix-20260926-v3.json),
[AnsiArt workers](../results/render-partitions-sky-ansiart-20260926-v3.json),
[36-map smoke](../results/campaign-smoke-sky-20260926.json), and the
[before](../results/render-reference-e1m1-sky-before-20260926.json) / [after](../results/render-reference-e1m1-sky-after-current-20260926.json)
full-frame comparisons. Diagnostic images remain in ignored `local/`.

The first worker check stopped before rendering because the worker does not
load the reference engine's `ThreeDRenderer` class. The production wrap was
rewritten with PowerShell integer masking/modulo and the worker test was
repeated successfully. That attempt found an implementation boundary, not a
gameplay defect.

## E1M1 moving-ceiling scene comparison (2026-09-26)

The existing E1M1 line-flags replay reaches sector 26 at level tic 315 with
the player facing the moving ceiling, 24 units from the sector center. Its
actual six-unit opening differs from the adopted PowerShell reference by one
scene palette index, with an exact HUD. Holding that replay-derived camera,
actors, and all other world state fixed while varying only sector 26's ceiling
to 0, 6, 34, and 68 units yields 8, 1, 390, and 4,259 differing scene
indices. The 68-unit view exposes more of the corridor; both rendered panels
retain the same basic layout. This is renderer disagreement in newly exposed
surfaces, not evidence of a stuck door, blocked route, or session crash.

The sweep isolates a fidelity gap that becomes visible as the ceiling opens,
but does not attribute every changed pixel to a door-specific raster defect.
The comparator is the adopted PowerShell reference, not an independently
verified original executable, and these palette-index counts are not a
perceptual quality or performance score. See the [sweep receipt](../results/moving-sector-e1m1-height-sweep-20260926.json)
and [dynamic comparison receipt](../results/moving-sector-reference-e1m1-prefix-20260927.json).

## Reuse per-context raster scratch (2026-09-27)

`Invoke-FastRender` previously allocated two 320-entry ray arrays and a new
masked-column list on every frame. Each visible deferred masked column also
created a hashtable. Render contexts now own reusable `RaySin` and `RayCos`
arrays plus a high-water list of masked-column records. The host and
deserialized worker contexts initialize the same scratch fields. The renderer
overwrites only records used by the current frame and draws only that prefix;
pixel math, ordering, and texture inputs are unchanged.

The source-pinned differential compares the pre-change renderer from commit
`a8a8b9db0fdc724b19b99d90679238d0bc71570b` with the candidate at four headings
on E1M1–E1M9 after 35 idle tics. All 36 full 320×200 indexed frames match
exactly: 2,304,000 pixels, zero differences. Eight views exercise masked
columns, with at most 91 records; all views confirm ray-array reuse and all
deferred records confirm object reuse on the following render. The tests do
not infer gameplay completion from idle map starts.

The existing 16-process partition check also remains byte-identical to serial
output in Classic, Matrix/Katakana, and AnsiArt/Katakana. Each style checks
320,000 pixels over five headings with zero differences and 80 encoded strips;
the character-based styles also check all 80 character strips. A fresh
headless Ultimate Doom smoke passes all 36 maps at 35 idle tics and two
320×200 renders per map. Its `WorkerStrips` field is configuration metadata;
the smoke itself does not launch workers. These checks establish scratch
reuse correctness and map load/render coverage, not campaign completion or
display pacing.

Six alternating-order rounds compare 30 serial full-frame renders per version
at five static headings on each of E1M1, E1M3, and E1M4. Context and snapshot
setup are outside the timer; first calls are retained. Times are milliseconds
per render:

| Map | Baseline mean / median / p95 / max | Candidate mean / median / p95 / max |
| --- | --- | --- |
| E1M1 | 60.28 / 51.10 / 86.39 / 249.94 | 55.38 / 49.45 / 88.10 / 119.73 |
| E1M3 | 56.93 / 51.32 / 86.25 / 194.69 | 52.73 / 50.01 / 84.25 / 100.57 |
| E1M4 | 61.67 / 47.07 / 108.37 / 328.18 | 51.96 / 45.85 / 87.78 / 136.84 |

Candidate medians are 2.6–3.2% lower in these samples. The tail varies by
map: E1M1 p95 is 2.0% higher, while E1M3/E1M4 p95s are 2.3%/19.0% lower.
This is a modest isolated-render result, not an end-to-end speedup or a
60-display/35-tic qualification: simulation, audio, worker transport,
encoding, terminal writes, and physical presentation are outside the timer.

The [summary receipt](../results/renderer-scratch-reuse-summary-20260927.json)
links the raw differential, worker, smoke, and timing reports. No renderer
golden-image claim against an original executable follows from this change.

## Guard fixed-point plane and wall-light boundaries (2026-09-27)

The retained E1M3 fixed-command host replay exposed a renderer worker failure
at tic 2,680: a plane distance of `3,543,363,520` was cast to signed Int32
instead of wrapping as Doom fixed-point arithmetic requires. The serial plane
sampler now performs an explicit modulo-2^32 wrap. The retained E1M4 replay
then exposed a negative wall-light index at tic 3,663; lookup selection is now
saturated safely before indexing for nonpositive or invalid distances, while
positive distances retain their normal lighting bucket. Both calculations and
all rasterization remain PowerShell.

On the corrected source, the 7,118-command E1M3 replay reaches `ReplayEnd` and
matches all 24 saved checkpoints; the 6,348-command E1M4 replay also reaches
`ReplayEnd` and matches all 22 checkpoints. Each retains the expected three
session transitions. E1M2's 3,233-command host replay reaches `ReplayEnd` and
matches all 13 checkpoints. These are fixed-input regressions, not human
playthroughs or vanilla-demo compatibility claims. The original renderer
failures, later successful replay receipts, map smoke, and source hashes are
indexed in the [Episode 1 readiness evidence](../results/episode1-render-guard-evidence-20260927.json);
large raw session reports remain under ignored `local/episode1-render-guard-raw-20260927/`.

The final guard source passes the 36-map load/simulation/two-frame smoke. The
renderer matches serial output across 320,000 pixels and five views with four
process strips in Classic, Matrix/Katakana, and AnsiArt/Katakana; Classic also
matches across sixteen strips. This confirms output consistency for these
samples. It does not qualify every map's visual fidelity, live-device frame
rate, or sustained 35-tic/60-display pacing.

## Keep background planes out of actor depth (2026-09-27)

The recorded E1M1 actor comparison isolated a second renderer issue. Floor and
ceiling fills were assigned depth values, so later world sprites and masked
walls were rejected when a floor happened to be closer to the viewer than the
sprite. Doom uses those planes to fill the background; opaque walls and
already-composited sprites own occlusion depth. The PowerShell renderer now
writes plane color without claiming depth. Its plane-ID buffer still identifies
the surface for texture mapping.

The focused masked-wall fixture passes 18 checks, including a plane pixel
whose depth remains infinite, a sprite sample composited over that background,
and the sprite taking depth ownership. On the same E1M1 replay states, the
reference-only actor mask shrinks from 247 to 3 pixels at tic 35 and from 344
to 5 pixels at tic 70; the sprite comparison covers eight endpoints through
tic 280. At tic 105 the reference draws no visible actor pixels while the
candidate still affects 17 pixels, so world-sprite visibility is not fully
matched. Whole-scene wall and floor differences also remain. The comparator is
the adopted PowerShell renderer, not an independently verified original
executable. See the [before](../results/actor-occlusion-plane-depth-test-20260927.json)
and [after](../results/actor-occlusion-no-plane-depth-final-20260927.json)
receipts.

All three styles still match serial output across four uneven worker strips at
five headings (320,000 pixels per style), and the 36-map smoke remains
successful. An attempted actor-sector filter reduced stray pixels at one
checkpoint but made output depend on worker strip visibility and failed serial
equivalence; that filter was removed. The passing partition and smoke reports
are linked from the [Episode 1 candidate receipt](../results/episode1-human-playthrough-candidate-20260927.json).
The retained change improves sprite occlusion without claiming full actor
parity or a performance gain.

## Preserve depth for untextured wall bands (2026-09-27)

The renderer's wall texture loop writes both color and depth. When a one-sided
wall has no middle texture, or a two-sided wall has no upper/lower texture,
the BSP still closes that projected wall band but the texture path has no
texel to claim its depth. The sprite pass could then draw an actor through the
untextured solid portion. `FastRenderer` now records depth only for the actual
projected wall band when its matching texture is absent. Textured walls keep
their existing depth path, and this does not assign depth to the full clipped
column, so exposed floor/ceiling pixels remain sprite backgrounds.

The authored whole-scene [masked-wall fixture](../results/masked-wall-order-untextured-wall-20260927.json)
passes 20 checks, including a farther sprite hidden behind an untextured solid
wall. The 36-map load/render smoke passes. Five-view renderer output is exact
over 320,000 pixels in Classic, Matrix/Katakana, and AnsiArt/Katakana with four
uneven strips; Classic also matches with sixteen. Receipts and source pin are
indexed in the [current Episode 1 candidate](../results/episode1-human-playthrough-candidate-20260927-r2.json).

This fix does not resolve the separate recorded E1M1 actor-visibility
difference: the adopted-renderer comparison still has 17 candidate-only actor
pixels at tic 105. The finding is preserved in the [eight-endpoint comparison](../results/actor-occlusion-untextured-wall-20260927.json).
That comparison is not an independently verified original-executable result,
and no renderer-performance gain is claimed.
