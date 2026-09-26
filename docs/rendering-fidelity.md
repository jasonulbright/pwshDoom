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
