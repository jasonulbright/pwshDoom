# Numeric div-line calculations

The [gameplay profile](simulation-profiling.md) identified sight checks as the principal measured E1M3 simulation cost. `Geometry.DivLineSide` had been allocating Fixed wrappers for coordinate differences and cross-product intermediates in both its `DivLine` and BSP `Node` overloads.

The replacement keeps the same PowerShell methods and branches. Diagonal coordinate differences use signed 64-bit intermediates, explicitly wrap to signed 32-bit, then use the original arithmetic right shifts before multiplying. Each shifted factor is between -32,768 and 32,767, so its product fits the original signed 32-bit result. Axis cases and the three front/back/on-line return values are unchanged. This is integer arithmetic, not a floating-point approximation. Traversal order, sight-check frequency, sector heights, slope clipping and actors are unchanged.

`scripts/fixtures/DivLineSideReference.ps1` retains both pre-change methods from commit `6bdc5a1`, with their GPL attribution. `scripts/Test-NumericDivLineSide.ps1` invokes both actual production overloads against that reference. The first run passes 44,424 comparisons and thirty analytic assertions across axes, diagonal and on-line points, zero-length lines, int32 extremes, fractional/wrapping boundaries and 20,000 seeded random cases. The observed return counts are 22,042 front, 16,862 back and 5,520 on-line. See `results/numeric-divlineside-first.json`.

The same fixture measures 32 alternating warm batches per path, each containing 2,048 calls on identical preconstructed inputs. Every batch remains in the report. Reference/numeric mean batch times are 42.653/12.600 ms, medians 40.180/12.061 ms and p95 54.961/16.746 ms. Answer hashes match. Input construction and output hashing are excluded; validation preceded timing, so these are warm microbenchmarks, not startup or displayed FPS.

The actual 1,200-command E1M3 deep-profiled replay also preserves all four original checkpoints and the independent final selected-state hash. Inclusive sight mean falls from 13.902 to 6.219 ms per tick; total instrumented update mean falls from 23.111 to 15.284 ms. The earlier profile predates the separate numeric Mobj movement fix, so this is a before/after build comparison; the paired method benchmark above isolates the geometry change. Inclusive actor and sight timings overlap and must not be added. Raw receipts and comparison are `results/simulation-numeric-divlineside-profile.json` and `numeric-divlineside-profile-comparison.json`.

The full original E1M3 replay passes all 7,118 commands and 24 checkpoints through E1M4 entry: `results/e1m3-numeric-divlineside-regression.json`. This establishes sampled gameplay/state preservation for that route. Complete host pacing, live capture and other campaign coverage remain separate gates.

The existing `VisibilityCheck.InterceptVector` denominator identity comparison remains outside this optimization. It needs a separate correctness investigation; silently changing it here would mix a behavior change with the measured side-calculation replacement.

## Loaded host prefix

The same 1,200-command headless Matrix workload, sixteen render workers, effects and six-track music catalog now completes in 40.464 seconds: **29.656 ticks/sec**, compared with 23.765 for the previous shared-snapshot build. All commands, four original checkpoints and 1,512,000 returned audio frames pass the thirteen-check audit. Pre-run source pins remain unchanged. The original replay source mismatch is declared; its checkpoints still match.

Mean gameplay update is 18.589 ms, snapshot publication 8.082 ms, and automap discovery 6.158 ms. These stages still exceed the 28.571 ms tick budget when combined. The result is an improvement, not sustained 35-tic/60-display qualification. Headless completed-image throughput is not terminal or monitor FPS. Receipts: `results/e1m3-host-numeric-side.json`, `e1m3-host-numeric-side-sources.json`, `e1m3-numeric-side-recorded.json`, and `e1m3-host-numeric-side-audit.json`.

Full recorded playback uses a five-minute safety bound. Recorder validation ceilings were extended to 600 seconds for the game and 660 for scoped audio (which also covers the existing tail); their defaults and capture-rate limit are unchanged. Allowing an entire slower replay to complete does not change the performance target or exclude slowdown from its timings.

## Recorded route: gameplay passes, audio tail fails

`local/recordings/e1m3-matrix-second` reaches replay end with all 7,118 commands and 24 original checkpoints matching through E1M4. It takes 233.697 active seconds and 236.211 wall seconds, averaging 30.458 ticks/sec. The host completes 14,022 console writes: 60.001 per active second and 59.362 per wall second. Those are writes, not independently measured displayed frames. Map loading/handoff accounts for 2.514 paused seconds.

The recording does **not** pass full audio qualification. Only 7,095 packets are consumed; 23 remain queued at shutdown. Of 8,939,700 submitted frames, 8,934,660 return and 5,040 are cancelled. The generic campaign audit correctly fails its all-audio-consumed assertion. The existing shutdown sets the audio worker's stop flag immediately; the earlier short prefix happened to empty its queue before close. A successful prefix therefore did not establish that full-route shutdown drains queued audio.

The original movie, scoped PCM and separate transition excerpt remain local. Portable game/capture/mux/input/source receipts and the failed audit are retained under `results/e1m3-matrix-second-*`. Fix bounded replay-end audio draining and repeat recorded qualification before promoting this to a successful audiovisual campaign result.

## Third recording and pacing variation

After the [bounded shutdown repair](audio-shutdown.md), the third recording passes all 47 integration checks, including every original checkpoint and all 8,968,680 returned audio frames. Gameplay averages 29.983 tics/sec; console writes average 47.965 per active second, versus 60.001 in the second recording. Both use sixteen workers and a 184×60 terminal with no viewport pause. This is a meaningful variation, not a sustained-60 result.

`scripts/Compare-RecordedRoutePacing.ps1` derives `results/e1m3-matrix-repeat-pacing.json` from the retained reports without rerunning gameplay. Mean time inside console output increases from 6.61 to 13.08 ms; mean dispatch-to-last-worker completion increases from 14.07 to 18.06 ms. The difference appears in every sampled 1,200-tic band. Mean gameplay update changes less (16.90 to 17.21 ms); snapshot publication changes 9.14 to 9.34 ms and automap discovery 5.05 to 5.51 ms. Rendering overlaps output, so these times must not be added. Different interpolated output samples, runtime scheduling and recording/environment effects remain possible factors; these two recordings do not establish a cause. The drain itself runs after gameplay clocks stop. Investigate output/worker variation separately while reducing the measured simulation-side discovery cost.
