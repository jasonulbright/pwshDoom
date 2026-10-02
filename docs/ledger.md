# Investigation ledger

## 2026-09-29 — Focused Ultimate Doom skill behavior matrix

The roadmap requires difficulty-dependent gameplay behavior to be separately qualified, while existing campaign and transition coverage primarily exercises Medium. Added a real-IWAD check for all five settings and separate Medium-skill Fast Monsters / Respawn Monsters options. On the installed Steam DOOM.WAD (SHA-256 6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F), all 37 checks pass under PowerShell 7.6.5 at source commit 14feeab05c09cec4315f8060d2852b42008b2356. E1M1 kill counts are 4/4/6/29/29 from Baby through Nightmare; the expected counts are computed from the IWAD THINGS flags and monster kill flags. Ten damage costs five health only on Baby. One shell pickup gives eight shells on Baby/Nightmare and four on other skills. Demon run-state duration is one tic on Nightmare or Fast Monsters, otherwise two; Imp fireball speed doubles from 10 to 20 map units/tic under Nightmare or Fast Monsters. Imp startup reaction delay is zero on Nightmare and its normal eight tics otherwise. The 420-tic respawn boundary passes on Nightmare and with Respawn Monsters; Fast Monsters alone does not enable respawning.

The first respawn fixture incorrectly made a still-solid living actor eligible, then treated the removed thinker as active until the next thinker-list cleanup. The final check kills a real spawned actor at a clear IWAD spawn location and asserts the engine's Removed state, which is the expected deferred-unlink behavior. This was a fixture correction, not an engine defect. The [portable receipt](../results/difficulty-behavior-r1-20260929.json) records all actual/expected values; [test source](../scripts/Test-DifficultyBehavior.ps1) reproduces them. Scope is focused E1M1 mechanics only; no map routes, every skill/map combination, or human playthrough are claimed.

## 2026-09-29 — Verify one complete E1M1 music loop on the actual worker

Ran the current R14 game source headless for 100 seconds on HMP E1M1 with 16 render workers, the Steam Ultimate Doom IWAD, the eleven-track local Episode 1 catalog, and realtime audio. The actual Windows device worker selected D_E1M1 and mixed 4,418,820 frames (100.2 seconds), beyond its qualified 4,233,600-frame / 96-second loop period. It returned 4,413,780 frames; the 5,040-frame tail is the shutdown-cancellation upper bound. Queue-starvation observations, rebuffer count, clipped samples, simulation/audio/cleanup errors were all zero; the device closed. The run advanced 3,499 tics at 34.987/sec and completed 4,029 headless render updates at 40.287/sec. This is one idle map and not acoustic, visible-presentation, full-campaign, or human-route evidence. The [portable receipt](../results/audio-e1m1-realtime-loop-boundary-r15-20260929.json) hashes the ignored raw report, IWAD, catalog, and qualification.

## 2026-09-29 — Reject masked-sprite post property caching

Tested a PowerShell candidate that moved each masked sprite post's data and offset property reads outside its inner vertical pixel loop. At a fixed HMP E3M6 state, two 20-frame samples per variant covered 640 serial production-equivalent stripe renders. The exact frame and per-worker pixel hashes matched. Pooled actor medians were 1.950 ms baseline and 1.971 ms candidate; total stripe medians were 7.145 and 7.130 ms, with no p95 improvement. This is within timing noise, not an optimization; the candidate was reverted. The [portable receipt](../results/renderer-post-properties-hoist-rejected-20260929.json) pins parameters, hashes, and local raw-profile hashes. No route or FPS claim follows.

## 2026-09-29 — Reject translated-flat color caching

Tested a lazy cache of flat texels translated through the selected colormap, keyed by flat and light. Two fixed HMP E3M6 samples per variant covered 640 serial stripe renders and produced identical full-frame and per-worker hashes. Geometry median/p95 changed from 3.8148/5.3055 ms to 3.927/5.4123 ms; total median/p95 changed from 7.0278/9.2991 ms to 7.0181/9.3107 ms. The 0.14% total-median difference is timing noise, with slower geometry and worse candidate p95. The source was restored; cache construction cost and memory growth were not measured. The [portable receipt](../results/rejected-flat-color-cache-20260929.json) records source/frame hashes, parameters, and ignored raw-profile hashes.

## 2026-09-10 — Study established

User authorized a feasibility study, documentation as work proceeds, and rendering experiments in `C:\projects\pwshDoom`. The earlier workspace was an empty Git repository under OneDrive. A new repository was initialized at the requested location; no existing project files were moved or deleted.

### Prior evidence

- **Source-inspected:** substantial PowerShell Doom implementations exist. See [the comparison](existing-implementations.md). Do not claim that Doom in PowerShell or terminal Doom is novel.
- **Author-reported:** ManagedDoomPowershell has working gameplay with poor performance and known bugs. It uses a graphical window.
- **Author-reported and source-inspected:** nick0451/doom-powershell implements a terminal renderer and simplified gameplay in one script; its documented missing sector actions and audio prevent treating it as a complete faithful port.
- **Source-inspected:** Windows Terminal 1.24 supports Sixel and synchronized output. Its Atlas presentation path uses display synchronization rather than a fixed universal 60 FPS limit. This does not predict application FPS.

### Baseline observed

Windows reports a Core Ultra 7 265K (20 cores/20 logical processors), 32 GiB RAM configured at DDR5-7200, RTX 4070 Ti SUPER plus Intel Graphics, Samsung 9100 PRO 2TB SSD, and an active NVIDIA display at 3440x1440/165 Hz. These are inventory readings, not hardware performance measurements. DDR5-7200 is a data-rate designation, not a measured 7200 MHz memory clock. The reported CPU base/max field is not a measurement of sustained turbo frequency.

Windows 11 Pro build 26200 and Windows Terminal 1.24.11911.0 were detected. **Correction:** the previous conversation's PowerShell 7.6.5 reading refers to the bundled task runtime. Each experiment will record the actual executable and version, rather than assuming that the user's normal Terminal profile uses it.

The registered Steam library initially contained Quake and Steamworks manifests; no `.wad` files were found in its `steamapps` tree. Synthetic indexed frames can exercise the display path without waiting for Doom installation.

### Questions being tested

1. What does PowerShell spend on frame construction and ANSI/Sixel encoding?
2. How much does the terminal transport slow down pre-encoded frames?
3. Does synchronized output change throughput or presentation behavior?
4. Can a 165 Hz desktop actually present these updates above 60 Hz?
5. What bottleneck should a future Doom experiment address first?

### Initial hypotheses

Once frames and WAD data are resident in memory, SSD read speed should have little influence on sustained animation. Script execution, encoding, communication, and presentation are more plausible bottlenecks. This is an engineering hypothesis to test, not a benchmark conclusion.

Further entries will append measured results and limitations below.

## 2026-09-10 — Initial encoders and first terminal run

Implemented synthetic indexed image generation, ANSI half-block and Sixel encoders using PowerShell and standard .NET APIs. Golden-fixture checks passed for pixel pairing, odd heights, Sixel color masks, repeat encoding, partial six-row bands, and buffer length validation.

Headless baseline is saved in `results/encoding.json`. At 320x200 with the 256-entry synthetic palette, median coherent-image ANSI encoding was about 73.8 ms and Sixel about 30.9 ms; the difficult texture was much slower. These timings exclude game simulation and are not FPS measurements.

Replaced per-character StringBuilder calls in the ANSI encoder with cached strings and a final bulk concatenation. The output was checked for exact equality. In this run coherent-image encoding decreased from 74.8 ms to 6.6 ms; the entropy case decreased from 316.2 ms to 109.5 ms. See `results/ansi-optimization.json`. This is evidence for one optimization on these workloads, not a universal speedup.

A dedicated temporary Terminal fragment profile uses Cascadia Mono 7pt, aliased text, opaque background, and no acrylic. It does not edit the user's settings file. The resulting terminal reported 589x128 cells, which accommodates the 320x200 half-block case. A 3-second Sixel smoke test completed about 34.9 writes/second at a target of 35, with median write time about 0.76 ms. This measures write completion only.

PresentMon 2.5.1 was downloaded from its official GitHub release into ignored `local/`, and its hash recorded. **Blocked measurement:** its ETW probe returned access denied: administrative rights or Performance Log Users membership is required. No elevation or group/security changes were attempted. Consequently independent presentation-rate and latency measurements remain unverified.

**Visual verification limitation:** the available computer-use window inventory did not expose the benchmark Terminal window, although its process and result files were present. No guessed window handles or synthetic screenshots are used as evidence.

The initial sources are [PresentMon](https://github.com/GameTechDev/PresentMon), its [console reference](https://github.com/GameTechDev/PresentMon/blob/v2.5.1/README-ConsoleApplication.md), and Microsoft's [fragment profile documentation](https://learn.microsoft.com/en-us/windows/terminal/json-fragment-extensions).

## 2026-09-10 — Replay, live encoding, and real Doom assets

Completed 32 synthetic replay cases: two repetitions, two image patterns, 16/256-entry palettes, ANSI/Sixel, synchronized output on/off, 320x200, four seconds each, paced to 165 writes/second. Pre-encoded Sixel reached approximately 164.5–165.0 completed writes/second in every case. Difficult ANSI images reached about 49–55 writes/second; coherent ANSI reached approximately 165. These finite runs neither establish a maximum throughput nor prove the monitor displayed every update. Raw samples are retained in `results/pre-utf8-fix/terminal-replay.json` (superseded; see the correction below).

An alternative Sixel encoder removes the PowerShell per-character RLE scan and converts ASCII mask arrays in bulk. Independent round-trip decoding verified all pixel indices in 24 cases across both Sixel encoders, palette sizes, patterns, and image sizes. The optimization is workload dependent: for 320x200/256-color entropy, encoding fell from 610.4 to 294.9 ms while bytes rose from 341,354 to 2,456,543. For 16-color coherent images it was slower. Keep both implementations and record this negative result; do not label the alternative universally faster.

Twelve five-second live synthetic cases measured generation, encoding, and console writes together, with two repetitions and synchronized output. At 320x200/256 colors, coherent ANSI completed 37.9–45.1 writes/second; original Sixel 21.3–24.2; alternative Sixel 20.6–23.8. On the entropy pattern these fell to 8.9–9.1, 1.4–1.5, and 3.2 respectively. `results/pre-utf8-fix/terminal-live.json` preserves the individual component timings (superseded; see below). This is ordinary desktop testing, with other applications and occasional study control commands active, not an isolated laboratory run. Repetition differences should remain visible.

Steam installation subsequently completed far enough to expose original Doom, Doom II, TNT, and Plutonia IWADs, alongside rerelease assets. The earlier missing-WAD finding was a temporary installation state. The first real-scene experiment reads the user's original `Ultimate Doom/base/DOOM.WAD`; no WAD is copied into the repository.

**Measured external renderer:** `scripts/Measure-DoomScene.ps1` imports 13 inspected function definitions from a user-local copy of nick0451/doom-powershell commit `6b0072973cd08fb83edc521e834e4070cda4b0a5`. It checks the source file SHA-256 and never executes the script's top-level interactive or network code. No upstream implementation is committed: the inspected tree had no explicit license. This is a runtime adapter for evaluation, not an adoption or relicensing decision.

Rendered eight headings at the E1M1 player start, twice, after three warmup frames. At 147x92, median rendering was 9.8 ms and ANSI encoding 4.4 ms; at 320x200 these were 37.8 and 13.8 ms. Original Sixel encoding took 24.0/72.8 ms; the bulk alternative 12.3/33.1 ms. Asset loading, palette setup, file output, and image verification were outside timed rendering. No sprites, weapon, HUD, AI, physics, input, or audio were exercised. Do not convert these separate medians into claimed game FPS.

**Offline visual verification:** inspected the locally generated 320x200 PNG and observed recognizable textured E1M1 geometry. This verifies the renderer buffer at one camera, not Terminal rendering or general Doom correctness. Copyrighted extracted imagery remains under ignored `local/`.

Twelve additional real-scene replay cases completed at approximately 164.5–165.0 writes/second for both Sixel encoders and low-resolution ANSI. At 320x200, ANSI completed 123.6–124.8 writes/second. `results/pre-utf8-fix/doom-replay.json` has the superseded raw measurements. A finite live renderer–encoder–write experiment follows to measure the combined path directly.

## 2026-09-10 — Code-page defect discovered; initial terminal runs superseded

The first combined real-scene loop finished, but a subsequent probe of a fresh Terminal window using the same profile/runtime reported output code page **437**, not UTF-8 (`results/terminal-probe.json`). The encoders write raw UTF-8 bytes to the console stream, so the ANSI half-block glyph cannot be assumed to decode correctly in that environment. The initial harness failed to select the matching console output code page. This is a study defect, discovered before finalizing the findings.

**Correction:** withdraw the initial ANSI terminal/live rates as evidence about correctly encoded output. Preserve all initial terminal batches, including their Sixel cases, under `results/pre-utf8-fix/` with a warning. The earlier ledger numbers remain historical observations and are superseded. Headless renderer/encoder timings and offline buffer verification are unaffected. Sixel payloads use ASCII, but the whole terminal batch will be repeated for a consistent setup.

All three terminal harnesses now explicitly select UTF-8 (code page 65001), record both original and active code pages, and restore the original output encoding on exit. Repeating the finite replay and live experiments with the same case plans. This fixes the encoding precondition; it does not substitute for the still-unavailable direct Terminal visual check.

## 2026-09-10 — Corrected batch complete

Completed all four reruns sequentially, each recording active code page 65001 and inherited code page 437: 32 synthetic replay cases, 12 synthetic live cases, 12 real-scene replay cases, and 12 real-scene live cases. Reports include `FinishedUtc` markers. No terminal benchmarks ran concurrently with each other.

**Measured current results:** difficult synthetic ANSI replay completed approximately 72–78 writes/second; coherent ANSI and all synthetic Sixel cases reached approximately 165. All real-scene replay cases completed 164.5–165.0 writes/second. The combined real-scene loop produced 75.4–76.4 writes/second at 147x92 with ANSI, and 21.9–22.3 at 320x200. The bulk Sixel variant produced 64.9–65.1 and 19.0–19.2 respectively; original RLE Sixel 33.8–34.1 and 11.2–11.3. These are geometry/encode/write measurements, not full-game or displayed FPS.

The corrected synthetic live cases produced 51.0–51.5 writes/second for coherent ANSI, 26.3–26.5 for original Sixel, and 25.7–26.2 for bulk Sixel. The entropy pattern produced about 9.3–9.5, 1.7, and 3.4 respectively. Raw reports at the parent `results/` paths now refer to these corrected runs. The [findings](findings-2026-09-10.md) use only corrected terminal rates.

The pinned external renderer was downloaded again by exact commit and its SHA-256 matched the originally inspected file, validating the reproduction URL. All current scripts parsed, the codec golden checks passed, and all 24 independent Sixel pixel-index round trips passed. No claim of exact Terminal visual correctness, monitor-visible refresh rate, or campaign completion is added.

The batch coordinator completed and removed the study profile. A final finite console glyph-width probe then compared the same three raw UTF-8 bytes for U+2580 under inherited code page 437 and explicit UTF-8. It measured cursor advances of three columns and one column, respectively (`results/terminal-utf8-check.json`). This independently confirms the decoding/cell-width consequence of the configuration error without claiming monitor-visible pixel inspection. The probe completed and its temporary profile was removed as well.

Downloaded tools, caches, and extracted images remain in ignored `local/` for repeatability. No service, scheduled job, or security change was created. First-batch documentation, raw measurements, reproduction instructions, and the known limitations are complete; a full Doom engine implementation remains outside this batch.

## 2026-09-10 — User confirms Steam installation activity, then completion

The user reported substantial Steam installation activity and requested a roughly ten-minute pause. They subsequently reported that all installations had finished, ending the pause early. Earlier measurements remain valid observations of an active desktop, but are provisional for estimating performance with installation work absent. Do not attribute timing differences solely to Steam without a controlled comparison.

Running the same finite E1M1 live-scene harness again, with no algorithm or protocol changes, into `results/doom-live-post-install.json`. Preserve the previous report. Record the user-reported installation state and a lightweight pre-run system CPU snapshot separately. This is a post-installation comparison, not proof that the entire machine is idle. The requested delayed follow-up was not created; both scheduling attempts returned errors before the user reported completion, so no timer remains to cancel.

**Measured follow-up:** all 12 cases completed with UTF-8 and the same WAD hash, external source hash, and terminal grid as before. System CPU was 4% in one snapshot before the run; there was no continuous load measurement. At 320x200, ANSI produced 20.7–22.2 completed writes/second, original Sixel 10.9–11.0, and bulk Sixel 17.9–18.6. This does not show a clear improvement over the earlier 21.9–22.3 / 11.2–11.3 / 19.0–19.2 ranges.

At 147x92 the repeat was substantially more variable: ANSI 50.9–76.9, original Sixel 15.0–33.9, and bulk Sixel 35.6–44.1. Keep these slower observations; no further runs were selected to obtain a preferred outcome. Installation completion is user-reported, and background activity, scheduling, clock behavior, and runtime effects were not controlled. The cause of the variation remains unestablished. A future performance investigation should correlate per-frame timing with continuous CPU/process and presentation telemetry.

Saved the post-installation context and report separately, updated the findings, validated report completion and matching inputs, and removed the study profile again. No benchmark code changed in this follow-up.

## 2026-09-10 — Pursuing 320x200 at 60 FPS in PowerShell

The user set a 320x200/60 FPS requirement and explicitly clarified that engine and rendering algorithms must remain in PowerShell. This rules out satisfying the target by launching a native engine, compiling C# hot loops, or putting the rasterizer in a GPU shader. Standard .NET bulk data movement and synchronization remain primitives used by the PowerShell implementation.

The previous replay tests suggest adequate terminal write throughput for representative Doom frames. Therefore test frame construction first: persistent workers each render and encode disjoint vertical strips, and the parent writes the completed frame. This keeps the full 320x200 logical image and avoids creating jobs every frame. No gameplay or presentation-rate claim follows from the experiment alone.

The initial persistent-runspace version did not meet the 16.7 ms budget: 1/2/4/6/8 workers gave median frame-construction times of 82.9/61.0/55.6/55.9/55.9 ms. Its partitioned viewport also exposed a dependency in the upstream incremental texture-coordinate calculation: skipped closed columns advanced depth but not texture coordinates. A candidate adaptation computes both interpolants from the absolute column. It changes some pixels compared with the original renderer, so do not call it byte-identical to upstream. After the adaptation, parallel output matches the adapted full-width serial renderer across all eight tested headings. The corrected four-runspace attempt was still about 57.8 ms median. See `results/parallel-scene*.json`.

Testing separate persistent PowerShell processes next, communicating through named memory mappings and events. Workers have independent runtimes and data; no compiled rendering helper is used. The first process test scaled from 94.4 ms with one worker to 35.3 ms with eight, still inadequate. Inspection found a harness defect: returning an unprotected byte array enumerated its bytes through the PowerShell pipeline, adding substantial cost. The encoder now returns the byte array as one object. Original measurements remain in `results/process-scene.json`; a corrected run is saved separately in `results/process-scene-bytearray.json`.

All worker experiments have finite sample counts, startup/frame timeouts, and explicit shutdown. Separate processes are hidden and only their own process handles are used for cleanup. Other user workloads were observed, including a compiler process; they were not stopped. Do not interpret these as isolated machine measurements.

With the byte-array return fixed, headless process construction scaled to 15.5 ms median at eight workers, 12.9 ms at twelve, and 11.0 ms at sixteen. Eight-heading pixel comparisons passed against the adapted serial renderer. This is before terminal writes and before gameplay.

**Live result:** sixteen PowerShell processes rendering fresh, continuously changing E1M1 camera angles and sending truecolor ANSI strips to Windows Terminal completed 98.5 updates/second in an initial 12-second uncapped run. A 30-second uncapped run covering more than one full rotation completed 97.4 updates/second, with median construction+write work 9.8 ms and p95 12.9 ms. This is full 320x200 geometry, not resolution reduction or replaying cached frames. The workload differs from the discontinuous eight-heading headless benchmark, so do not compare their medians as identical work.

The first average-60 pacing results hid substantial interval jitter. In the 30-second run, coarse Sleep-based pacing gave a p95 frame-start interval of 27.4 ms and 461 late completion deadlines despite all individual frame-work durations being below 16.7 ms. Replaced only frame pacing with Stopwatch/SpinWait, explicitly spending coordinator CPU to avoid timer-quantum oversleep.

The first precise-paced run completed 1800 writes in 30 seconds, with median interval 16.6666 ms and p95 16.6728 ms. Frame work was median 10.2 ms / p95 13.1 ms. It still had 23 frame-work overruns and 52 completion-deadline misses; preserve these rather than claiming perfectly steady presentation. Worker working sets summed to approximately 2.55 GiB at the end. The monitor-visible frame rate remains unmeasured, and no game simulation was included.

Independent ANSI decoding passed 12 strip tests covering truecolor and approximate fixed-palette output, odd dimensions, and uneven partitions. The test explicitly rejects byte-array pipeline enumeration. A runspace recheck after that array fix follows, because the earlier allocation-heavy encoder could also have inflated the renderer's time through shared garbage collection; this is a hypothesis, not an established cause.

The corrected runspace recheck remained slower: eight workers gave 22.4 ms median and sixteen 26.3 ms on the discontinuous headless workload. All pixels matched the adapted serial renderer. Separate processes remain the strongest tested configuration; no causal claim about PowerShell runtime internals is established.

The optional fixed-palette live run completed 1800 updates in 30 seconds, with median frame work 9.1 ms, p95 12.0 ms, 15 work overruns, and 35 late completion deadlines. Its p95 frame-start interval was 16.6715 ms. It approximates colors and therefore remains optional; full-color ANSI is the recommended default. No alternative terminal or compiled graphics library was installed or used.

Recorded the tested architecture, complete timing limitations, reproduction commands, and unimplemented alternatives in [the 60 FPS investigation](sixty-fps-investigation.md). The next integration concerns are PowerShell simulation at Doom's 35-tic rate, actors/HUD, consistent mutable-world snapshots, more demanding maps, and independent physical presentation measurement. The current demonstration is not an interactive game and does not establish full-game or displayed 60 FPS.

## 2026-09-10 — User-supplied Matrix transforms lead

The user supplied StartAutomating's Reddit post about the Matrix PowerShell module. **Source-inspected:** [PoshWeb/Matrix](https://github.com/PoshWeb/Matrix/tree/66e39e634548aaeca2c775a80c92a04b5ea3275f), inspected at commit `66e39e634548aaeca2c775a80c92a04b5ea3275f`, has an MIT license. Its aliases select .NET matrix constructors and transformations. The [implementation](https://github.com/PoshWeb/Matrix/blob/66e39e634548aaeca2c775a80c92a04b5ea3275f/Matrix.ps1) collects pipeline inputs and invokes their static Transform methods. The CSS/HTML representations are useful for browser demonstrations; this code supplies no Terminal GPU rendering path. The public website could not be opened by the web tool; the repository was inspected instead. The module was neither installed nor executed, and no module performance measurement is claimed.

**Relevance:** the inspected Doom renderer already performs a two-dimensional world-to-camera rotation and translation for segment endpoints, after back-face rejection. A Matrix3x2 can represent that operation; a general Matrix4x4 is unnecessary for this stage. Microsoft's [Matrix3x2 documentation](https://learn.microsoft.com/en-us/dotnet/api/system.numerics.matrix3x2?view=net-10.0) specifies row-vector convention and single-precision components. The current scalar camera arithmetic uses doubles. The [.NET Vector2 implementation](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Private.CoreLib/src/System/Numerics/Vector2.cs) is CPU numerical code, not a GPU submission API; this inspection does not establish which instructions the current JIT emitted.

**Measured:** added `scripts/Measure-CameraTransforms.ps1`. It transforms all 470 E1M1 vertices at the player start using eight non-cardinal headings, with preallocated double output arrays. Each method receives 64 warmup batches and 64 measured samples of 16 batches. Method order rotates between samples. Timings include camera setup and coordinate storage, but exclude loading, visibility tests, projection, rasterization, encoding, IPC, Terminal output, and gameplay. These are coordinate-only microbenchmarks, not renderer frame times.

| Method | Initial median ms/map | Typed-variant follow-up median ms/map |
| --- | ---: | ---: |
| Scalar relative-coordinate arithmetic | about 0.04 | 0.0279 |
| Scalar affine coefficients | about 0.04 | 0.0391 |
| Matrix3x2, cached Vector2 inputs | 2.15 | 2.1284 |
| Matrix3x2, construct Vector2 per point | 3.31 | 3.2924 |
| Matrix3x2, cached inputs and explicitly typed matrix/result locals | untested | 2.2314 |

All outputs were checked against the scalar calculation for every vertex at every heading. Maximum absolute coordinate difference was approximately `9.1e-13` map units for scalar affine arithmetic and `0.000464` for the matrix variants, within the declared `1e-8` and `0.01` tolerances respectively. This is not a pixel-equivalence test: small coordinate differences can change rasterization at boundaries. Exact scalar agreement is expected for the reference method itself.

The initial attempt stopped before timing because a temporary variable collided with PowerShell's reserved `$Error` variable; it was renamed. The successful four-method run is retained in `results/camera-transforms.json`. A console summary formatting defect omitted labels but did not affect the JSON; it was fixed before the five-method follow-up in `results/camera-transforms-typed.json`. The latter specifically tested whether explicit struct typing reversed the outcome; it did not. Runs used PowerShell 7.6.5 / .NET 10.0.11 on the same active desktop, without system tuning.

**Decision:** keep the existing scalar renderer math. Direct per-point System.Numerics calls, in these tested forms, were substantially slower. This does not rule out other data layouts, bulk SIMD algorithms, or .NET numerics generally, and does not establish the exact cause of the overhead. Matrix composition remains useful for designing camera/automap transforms and authoring tools. **Untested hypothesis:** reusing transformed vertices within a frame could avoid repeated endpoint work. Its benefit must account for visibility rejection, cache lookup/storage, and worker communication; transforming the whole map upfront may also do unnecessary work. No renderer or encoder implementation changed in this follow-up.

Reproduce after the existing [WAD/source setup](reproduce.md), writing a fresh local report:

```powershell
$wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD'
.\scripts\Measure-CameraTransforms.ps1 -Wad $wad -Output .\local\my-camera-transforms.json
```

## 2026-09-10 — Feasibility verdict and a meaningful product target

The user asked whether the evidence supports a better playable PowerShell terminal engine, original Doom tick timing, and a distinct offering. **Assessment:** there is enough measured evidence to justify a playable prototype. There is not yet proof of a complete engine's performance, a superior full game, or worldwide uniqueness. This verdict does not turn the feasibility repository into a claim that a port has shipped.

The strongest evidence remains fresh 320x200 full-color scene construction, encoding, IPC, and completed Terminal writes: 97.4 updates/second uncapped and 1,800 updates in a 30-second precisely paced run. The latter had 52 late completion deadlines. The measured configuration uses 16 worker processes with approximately 2.55 GiB summed working sets. It measures one stationary rotating E1M1 camera with static geometry, and omits gameplay, actor/HUD rendering, and physical presentation telemetry. These costs and limits prevent a claim of a lightweight or universally steady 60 FPS game.

**35-tic feasibility is a reasoned expectation, not a benchmark result.** [Original Doom defines TICRATE as 35](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/doomdef.h), giving approximately 28.57 ms between simulation ticks. A proposed PowerShell simulation process would advance fixed game tics and publish consistent world snapshots. Rendering can interpolate selected visual state at 60 updates/second without changing gameplay speed. The simulation and rendering processes still compete for the same machine's resources; the renderer's measured time must not be subtracted from 28.57 ms and presented as a measured simulation allowance. A successful empty tick scheduler would also not establish engine throughput.

**Prior-art gap, rechecked:** [nick0451/doom-powershell](https://github.com/nick0451/doom-powershell) already provides PowerShell terminal gameplay; its inspected README still identifies missing lifts, moving floors, walk-over triggers, and sound. [ManagedDoomPowershell](https://github.com/oleyska/ManagedDoomPowershell) has a broader translated engine with graphical-window presentation and author-reported poor performance. Neither source establishes the complete combination we would target: faithful vanilla campaign behavior, PowerShell engine/rendering algorithms, 320x200 terminal output, 35-tic simulation, a measured 60-update rendering option, and reproducible compatibility/performance reports. This is an opportunity identified among inspected offerings, not proof that nobody has attempted it.

The recommended next milestone is one playable E1M1 session with input, collision, actors, combat, pickups, doors, HUD, and an exit, while recording actual simulation-tick and rendering costs together. Then exercise lifts, moving sectors, walk-over triggers, and denser combat on other original maps. Deterministic recorded inputs and reference-engine comparisons should test gameplay behavior separately from throughput; vanilla demo synchronization is a stronger eventual compatibility test, not an existing feature. Independent presentation and input-latency measurements remain necessary before advertising displayed 60 FPS. Faithful campaign completion and timing are the proposed distinction. The renderer's current unlicensed local dependency still needs an appropriately licensed replacement or permission before its implementation can be distributed. No new benchmark or engine implementation was performed for this verdict.

## 2026-09-10 — Implementation authorized; licensed foundation

The user approved implementation of the playable milestone. Adopted the 206 PowerShell files outside the Silk/windowing and launcher directories from ManagedDoomPowershell commit `e8440ae2f33f190318ebde4ef20ffec3bc804244`. Their GPL-2.0-or-later notices are preserved under `src/ManagedDoom`, with origin attribution and a repository LICENSE. No upstream assemblies, soundfont, native libraries, or game assets are adopted. The original checkout remains ignored. The previous unlicensed renderer is retained only as the historical experiment, not as a distributable engine foundation.

The new loader bundles circularly referring PowerShell classes and orders files by inheritance dependencies. The compiled BufferHelper dependency in the optional RGBA conversion was replaced with PowerShell; the terminal backend can consume indexed framebuffer data directly. Engine initialization, simulation, drawing, and terminal encoding remain PowerShell algorithms. The null audio backends are used for the initial playable milestone.

Integration checks exposed upstream problems: reserved `$args` method parameters discarded arguments; GameContent reparsed an already-parsed argument object; status strings referenced unset variables and a nonexistent Message property; animation definitions mixed static and instance access; sprite lookup included the Count sentinel; flat marker counting assumed an array; one-sided linedefs accessed null back sidedefs; the blockmap constant referenced an unset local; HUD construction accessed a player before assignment; hitscan read the sky-flat identifier from the wrong object. Fixes are being checked through startup and real gameplay actions, with failures preserved here instead of disabling validation.

The translation also represented C# value types Fixed/Angle as PowerShell reference classes without initializing 126 instance fields across 26 files. Those fields now receive zero defaults, restoring the original struct initialization behavior and preventing null momentum/view coordinates. Static defaults are not automatically rewritten. `local/engine-default-initialization.json` records the affected fields per file. This is a functional correction, not a claim of vanilla demo compatibility.

The first integrated baseline exercises actual E1M1 movement and intermittent pistol fire, then draws geometry, sprites, weapon, and HUD. It is finite and excludes terminal output. A successful baseline is required before adopting the licensed renderer's partitioning and interactive loop.

## 2026-09-10 — Playable E1M1, integration failures and corrections

**Measured:** the fixed GPL engine initializes the user's classic Steam Ultimate Doom IWAD and advances actual movement/combat. The retained reference renderer was about 406 ms median per full frame in the initial baseline, with simulation around 7.35 ms median. A 20-column reference strip still cost about 52.7 ms. These baselines were too slow for the integrated target; merely dividing its columns was insufficient. Reports: `engine-baseline.json`, `engine-profile.json`, `engine-strip-profile.json`.

Implemented an original PowerShell rasterizer against the adopted GPL data model: BSP visibility, scalar projection, upper/lower/solid/masked walls, horizontal floor and ceiling spans, actor/weapon sprites, depth testing, and HUD. Static geometry/texture metadata is cached. Dynamic sectors/sides/actors/player state use snapshots. All algorithms remain PowerShell; no code from the unlicensed renderer was adopted. Floor V coordinates were corrected to the reference world's negative-Y convention. Lighting and several visual effects remain approximate, documented in `implementation.md`.

**Measured failure:** placing the real engine and renderer workers in shared-process runspaces yielded 78 simulation tics and 29 renders in 10.08 seconds, roughly 7.7 tics/sec and 2.9 updates/sec. Separate processes restored roughly 35 tics/sec and 18–20 updates/sec. This establishes the comparative result, not a proven diagnosis of PowerShell runtime internals. The abandoned runspace implementation is retained in `scripts/RunspaceGameExperiment.ps1`, outside the game path. The former single-host coordinator is retained as `scripts/Invoke-DoomSingleHost.ps1`.

The first 30-second Terminal integration completed 1,048 tics and 602 writes: 34.9 tics/sec and 20.1 image updates/sec. It included actors, weapon, HUD, simulation, encoding, IPC, and actual console writes, unlike the earlier scene-only demonstration. That early result is retained in `results/game-terminal-30s.json`; it is superseded by the pipelined results below.

**Correctness:** component checks cover spawn, movement/collision, ammunition, a door, armor, and exit. HMP E1M1 has six difficulty-filtered monsters in this IWAD: four former humans and two imps. The independent THINGS count resolves the initial suspicion that monster loading was incomplete; 29 belongs to a different difficulty. Door/pickup/exit fixtures explicitly reposition the player and are not presented as proof of walking the level.

Added a complete deterministic route using only TicCmd movement, turn, fire, and use. Its first attempt hit a solid courtyard window (`e1m1-route-window-blocked.json`); collision was functioning. Another attempt used the door every 14 tics and repeatedly reversed it (`e1m1-route-door-toggle.json`). The route now uses less frequently and follows passable geometry; no engine collision/door rule was weakened. The successful recording has 1,560 simulation commands, 1,575 driver iterations, five kills, and a real exit. Waypoint-only driver iterations do not advance simulation. There are no cheats, teleports, direct damage, or direct special activations in this route.

The first full Terminal replay exposed a bright-sector gunflash error at command 414: PowerShell's Math.Clamp overload selection attempted an unsigned conversion of a negative lighting index. Explicit signed integer arguments fixed it; the bright-sector/ExtraLight=2 case became a partition regression fixture. The failed report is preserved as `game-terminal-e1m1-lighting-failure.json`. The next full single-host replay completed the route with five kills and 75 health, at about 19.8 completed updates/sec.

**Attribution correction:** the 126 Fixed/Angle default initializations are now recorded portably in `docs/engine-defaults.json`, in addition to the original ignored local report. All adopted notices are preserved and modifications are listed in `src/ManagedDoom/ORIGIN.md`.

## 2026-09-10 — Removing dispatch and transport overhead

The plain-data rasterizer's representative 20-column strip fell from about 29.6 ms to 24.5 ms with horizontal spans, then about 22.1 ms with numeric snapshot fields. More worker processes alone did not solve the integrated limit: a 20-worker test still produced only about 20.4 headless updates/sec.

**Measured:** a per-pixel Math.Floor call was expensive in the tested PowerShell loop. Conversion to an integer followed by a downward correction preserves floor semantics for finite coordinates safely inside Int32 range, including negative coordinates. In the saved isolated 3,360-pixel benchmark, Math.Floor had a 12.320 ms median and cast/correction 0.637 ms, with 99 signed boundary cases and identical nonuniform pixels (`results/pixel-floor.json`). This is a microbenchmark, not a claimed 19× full-game speedup. The representative strip dropped to about 9.95 ms median. Explicit double arguments to Math.Floor did not remove the observed cost. Its exact runtime cause is not established.

The optimized renderer was compared with the pre-cast implementation over five angles and seven uneven worker partitions: 320,000 exact pixels, including the gunflash case. The baseline hash is retained in `results/render-partitions.json`. This checks our optimization and worker transport, not vanilla Doom pixel equivalence.

Replaced per-frame JSON with NumericV1 arrays packed through standard Buffer.BlockCopy. On a real E1M1 snapshot, saved median encode/decode times were 3.249/2.408 ms for JSON and 0.546/0.271 ms for numeric transport. Every field survived an exact pack/decode/repack comparison (`results/snapshot-transport.json`). Avoided an additional PowerShell pipeline-array enumeration by assigning byte arrays within an if statement and returning them with unary comma. Runtime workers reuse private decoded arrays, and the host reads raw pixels only for captures/final output.

Short Sleep(1) calls also overslept under the original conditions (about 5.65 ms average in a local exploratory measurement). A paired process-local timeBeginPeriod request reduced the observed short-wait overhead. The saved host-profile run records `Requested1msTimer`; no power plan, security setting, or persistent/global timer policy was changed. Microsoft's [timeBeginPeriod contract](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod) describes current process-specific behavior and occlusion caveats. These local wait observations do not establish timing guarantees. With numeric transport and coordinator profiling, a short headless run reached about 43.9 updates/sec (`game-host-profile.json`).

## 2026-09-10 — Separate simulation and overlapping terminal writes

Moved the live gameplay engine into a dedicated persistent PowerShell process. Commands enter a bounded shared-memory ring at the original 35 Hz rate; the simulation publishes paired old/current numeric states through double-buffered slots with version checks. The coordinator interpolates them while renderer workers run. This removes simulation work from the frame collection/input loop. A short headless run completed 478 images in 8.005 seconds, about 59.7/sec, with 279 tics.

The first full Terminal replay with separate simulation reached 48.77 completed image updates/sec and completed the same 1,560-command route (`game-terminal-independent-e1m1.json`). Console output was still serial with the next render. The next change dispatches a new render before writing the already-harvested image, so render work overlaps console I/O. Worker results are copied out before their shared buffers are reused.

**Measured success:** `game-terminal-pipelined-e1m1.json` records 2,681 completed image writes and 1,560 tics in 44.679 seconds: 60.006 updates/sec and 34.916 tics/sec. The route exited with five kills, 75 health, and no error. It rendered 320×200, full color, with 16 PowerShell renderer processes plus a PowerShell simulation process and coordinator. Renderer working sets totaled 2.99 GiB, simulation 0.30 GiB, excluding host/Terminal.

**Cadence qualification:** completed-write intervals were median 16.290 ms, p95 22.738 ms, maximum 74.010 ms, with 27 intervals above 33.333 ms. Simulation work reached 109.890 ms and simulation-start lateness 214.240 ms. The anchored schedule catches up after stalls. FrameMs is render-to-write latency, which overlaps other frames, not a frame interval. Analysis uses consecutive EndQpc timestamps and the measured 10 MHz QPC frequency. See `game-terminal-pipelined-cadence.json`. Neither averages nor console writes establish monitor presentation rate; the earlier PresentMon access limitation remains.

## 2026-09-10 — Final QA and implementation checkpoint

Corrected the snapshot's initial camera-height rule to match the GPL reference: do not interpolate old view height in the first level tic. Added a corresponding component check. Snapshot checks now cover all-field numeric round trips, interpolation endpoints/midpoint, state reuse, actor removal, and malformed packets. The latest seven-worker partition check still matches all 320,000 pixels against the pre-cast renderer through NumericV1 transport.

Input tests pass native INPUT_RECORD size/offsets, simultaneous keys, independent releases, short use taps, weapon selection, and focus-loss clearing using synthetic records. No desktop keys were injected. The actual runtime ANSI encoder passed 12 independently decoded strip cases; codec goldens and 24 Sixel round trips also pass. Sixel is not the runtime backend. Physical keyboard play and input-to-display latency remain unobserved.

Added parent-death checks to owned workers and simulation asset cleanup. `results/game-lifecycle.json` passes both a finite headless session and deliberate termination of its owned coordinator: all three child processes exit and the owned asset cache disappears. This test does not close unrelated processes or prove terminal restoration after an abrupt crash. Session measurement now counts simulation tics at clock stop rather than including a queued tic potentially drained during cleanup.

The final full Terminal replay after these changes again completed **2,681 writes and 1,560 tics in 44.680 seconds**, 60.004 updates/sec and 34.915 tics/sec, with five kills, 75 health, a real exit, and no error (`game-terminal-final-e1m1.json`). Write intervals were median 16.244 ms, p95 22.869 ms, maximum 76.951 ms; 30 exceeded 33.333 ms. This reproduces the average-throughput result while retaining its stutter evidence. Runtime source hashes are in `results/implementation-sources.json`; cadence analysis retains its source report hash.

Offline indexed framebuffer captures at commands 350, 700, 1050, and 1400 were converted to an ignored contact sheet and inspected: actual rooms, enemies, weapon, and HUD are visible. `scripts/Save-FramePreview.ps1` uses System.Drawing only for offline inspection, never in gameplay rendering. These are framebuffer previews, not Terminal screenshots. Commercial assets remain ignored and user supplied.

The engine bundle and all 49 remaining PowerShell files parse successfully. The executable milestone is complete, with documented limits: E1M1 only, no audio/menu/save/automap/multiplayer interface, incomplete visual effects/HUD details, approximate lighting, and no vanilla demo or full-campaign qualification. README and `implementation.md` describe the current separate-simulation pipeline; earlier documents/results remain historical evidence. This is a measured playable prototype, not a worldwide-first claim or proof of campaign superiority.

Final launch QA recorded a window-height failure at 589×98 against the 102-row guard (`game-terminal-input-window-too-short.json`). **Subsequent user clarification: they resized that window. The original attribution to fresh-window sizing was incorrect.** At this stage the launcher added Terminal's documented `--maximized` option for the new game window, without changing any default setting. [Microsoft command-line reference](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments). A repeat non-scripted five-second session opened at 688×119, exercised the real console-input open/read/restore path, and ended normally with 174 tics and 228 image updates. It is an input-path startup smoke test, not proof of physical key handling or sustained 60 FPS. No keys were injected.

The adopted-source audit found 206 GPL-noticed PowerShell files, 42 modified relative to the pinned checkout. Added dated modification notices to seven changed files where the portable ORIGIN description alone had not put a notice in the file. No algorithm changed in this attribution pass. Trimmed trailing blank lines in authored scripts. `implementation-release-sources.json` records the subsequent worktree hashes, including launcher maximization and these cosmetic changes; earlier benchmark source hashes remain preserved. Staging contains no IWAD, extracted frame, native game binary, or ignored local cache.

**Release-window confirmation:** the maximized launcher completed a third full route at 688×123: 2,681 writes, 1,560 tics, 44.685 seconds, 59.998 completed updates/sec, 34.911 tics/sec, five kills, 75 health, successful exit, no error. Write intervals were median 16.162 ms, p95 24.406 ms, maximum 64.507 ms, with 28 above 33.333 ms. Reports: `game-terminal-maximized-e1m1.json` and `game-terminal-maximized-cadence.json`. All 220 release source hashes still matched; the engine bundle and 49 other scripts parsed; no game coordinator/simulation/render worker remained active. Authored files pass the whitespace check; upstream formatting and GPL notices are retained in adopted files. The three complete runs support average throughput on this hardware, while leaving frame pacing and broader compatibility as explicit next work.

## 2026-09-10 — Installed PresentMon service resolves presentation access

The user reported installing PresentMon. Found Intel PresentMon 2.5.1, its SDK, and a running PresentMonSharedService. Direct creation of the installed capture application returned a Windows elevation requirement even for help; it did not run. The earlier standalone console tool's ETW denial was not evidence that this newly installed service was inaccessible. Intel's [documented service API](https://github.com/GameTechDev/PresentMon/blob/v2.5.1/README-Service.md) connected from the existing non-elevated PowerShell process and reported API 3.3.0. No elevation, security/group change, service reconfiguration, or GUI overlay was used. `results/presentmon-service-probe.json` records success and the installed DLL hash.

Added optional measurement scripts using P/Invoke declarations for the installed API. They are never loaded by the game, and contain no custom compiled algorithm bodies. Runtime introspection supplies metric types; registered field offsets/sizes are checked before reading. The collector requires an isolated new Terminal process, runs the finite E1M1 replay, and drains events after completion. It frees only its own tracking/query/session resources, leaving the user's installed service running.

**Measured:** captured 2,714 events from Windows Terminal PID 11480, one swapchain, with no capture error. The simultaneous game again completed E1M1 with five kills and 75 health: 2,681 writes and 1,560 tics in 44.679 seconds, 60.005 writes/sec and 34.915 tics/sec. Raw evidence is in `results/presentmon-e1m1-frames.csv`, `-capture.json`, and `-game.json`.

Analysis clips to the exact first/last completed-write timestamps, a 44.6127496-second window, and treats present and display events separately. It finds 2,678 Present calls (60.028/sec) and 2,675 ETW-reported display transitions (**59.960/sec**). Three in-window submitted presents were marked dropped; every non-dropped submission had a display timestamp. Display intervals were median 18.174 ms, p95 24.279 ms, maximum 60.616 ms, with 27 above 33.333 ms and one above 50 ms. These results independently support approximately 60 displayed Terminal updates/sec while confirming remaining cadence spikes.

**Analysis correction:** the first native interval spanned a 12.7-second startup pause. Consecutive in-window QPC timestamps exclude that boundary-crossing interval rather than silently counting it as a gameplay stall. Derived present/display intervals match the native fields to within `7.2e-15` ms, verifying units and decoding. `results/presentmon-e1m1-summary.json` retains the method and raw evidence hashes. Mode 8 accounted for 2,576 in-window presents and mode 4 for 102. Windows reported the active NVIDIA display at 3440×1440/165 Hz; the 18.174 ms median is consistent with roughly three refresh periods (inference, not a 55 FPS engine cap).

Present-to-display latency was median 5.450 ms and p95 9.530 ms. Its starting point is Terminal's graphics Present call, not game input or PowerShell rendering, so it is not input-to-photon latency. The capture supplies ETW-based presentation evidence, not optical measurement or identification of each Doom framebuffer. Current README/implementation findings now reflect this resolved access limitation; older denied probes remain historical facts. See `docs/presentmon-validation.md` for reproduction and qualifications.

## 2026-09-10 — Resize correction and viewport handling

The user clarified that they resized the earlier failed window to 98 rows and reported excess space below/right of the image. Corrected the earlier ledger attribution: the saved dimensions are valid, but they do not show that Terminal opened at an unsuitable size. The old host placed the image at the upper left and rejected grids shorter than 102 rows, including two debug rows. Monitor resolution was never a measured requirement.

**Implemented:** the full 320×200 image now needs 320×100 cells by default, with two additional rows only under `-Diagnostics`. The launcher uses a configurable 6-point font, and maximization is optional. The host centers the image, polls grid size every 100 ms, discards frames encoded for old placement, clears after resize, and pauses the active clock/new command issuance when the image does not fit. Restoring the grid resumes without adding paused time to the simulation queue. Finite experiments use wall time; reports preserve active/wall rates and resize history. No game or encoder algorithms moved outside PowerShell.

**Verified:** 24 ANSI pixel round trips across two origins; 320,000 unchanged E1M1 pixels across five views and seven process strips, including actual worker cursor-origin checks. Nine layout and three bounded-message cases pass. A five-second real-engine headless run with synthetic dimensions starts at 589×98, resumes at 320×100, enlarges, shrinks below the minimum, then resumes. Both pauses preserve issued-command count and active time. It records 1.856 paused seconds, 3.150 active seconds, 109 simulation tics, and 88 headless images with four workers. This correctness run is not a 60 FPS benchmark or a physical resize test. Evidence: `viewport-tests.json`, `viewport-resize-session.json`, and `render-partitions.json`.

**Live measurement:** the new 6-point/windowed launch reported a stable actual grid of 582×156, with the image origin at zero-based column 131/row 28. It completed the full input-only E1M1 route: 1,560 tics, 2,681 writes, 44.685 seconds, 59.997 writes/sec, 34.911 tics/sec, five kills, 75 health, no error or viewport pauses. The actual grid differs from the CLI size request; no cause is established here. The runtime measures it instead of assuming the request determines the final grid.

PresentMon captured 2,701 events. Within the 44.597-second write window it reports 2,670 submissions (59.869/sec), 2,569 display transitions (**57.604/sec**), and 101 dropped submissions. All 101 drops occur in the first three seconds; the maximum display interval is 2,751.539 ms. Display interval p95 is 24.274 ms. The reason for this initial display gap is not established. Preserve the full window, including the gap, rather than removing it to improve the headline. Raw capture, game report, CSV, and analysis are `results/presentmon-viewport-e1m1-*`.

**Repeat:** `results/presentmon-viewport-repeat-*` again completes the route at 582×156 with no resize pause: 2,681 writes, 1,560 tics, 44.676 seconds, 60.010 writes/sec, 34.918 tics/sec. PresentMon records 2,572 display transitions (**57.664/sec**) in 44.603 seconds. All 102 dropped presents fall within the first three seconds and use composed-flip mode 4. The maximum interval between displayed events is 42.428 ms, which does not account for the initial interval before the first displayed event; the full-window rate retains that lost time.

**Maximized comparison:** added explicit font/maximization options to the measurement harness and recorded those parameters in its capture metadata. With the same runtime/6-point font and `-Maximized`, the game completes at 688×151 with 2,680 writes, 1,560 tics, 44.669 seconds, 59.997 writes/sec, 34.924 tics/sec, the same kills/health, no error or resize pauses. PresentMon records 2,663 display transitions (**59.733/sec**) in 44.582 seconds and six dropped presents. Display intervals: median 18.176 ms, p95 24.266 ms, maximum 54.552 ms, 26 above 33.333 ms. Raw evidence: `results/presentmon-viewport-maximized-*`. The windowed presentation difference is reproducible in two observations and reduced under maximization in one; its cause remains unproven. Both launch modes remain available. Current docs show all results rather than promoting the earlier 59.96 figure as a measurement of the updated default.

**1080p status:** no physical 1080p display was tested. Font size is in points, and font metrics, DPI, zoom, and window chrome determine how many cells fit. A smaller font can fit the 100 required rows into less physical height; the design does not impose a greater-than-1080p resolution requirement. This is a layout explanation, not hardware qualification. See `docs/viewport.md` and the linked Microsoft references. The current image remains full resolution and fixed in cell dimensions; extra window space becomes centered margins.

**Final checks:** the engine bundle and other scripts passed 55 parse checks; the 24 ANSI cases pass; all 221 runtime worktree hashes match `results/viewport-sources.json`; all three live reports finish the level with no error; no owned coordinator/simulation/render process remains. `results/viewport-validation.json` records these checks. Runtime algorithms were unchanged between the three live captures. No user assets or compiled game binaries are added.

## 2026-09-10 — Completion roadmap and campaign smoke coverage

The user requested a complete game plus a substantial science/entertainment write-up comparing alternatives. They confirmed the order **Ultimate Doom → Doom II → MyHouse-based audit**, and approved PowerShell sound decoding/mixing with standard Windows/.NET device playback. Created `docs/roadmap.md` with milestone dependencies, acceptance criteria, a current work queue, alternatives, article structure, and collaboration expectations. Updated AGENTS/README to make it the continuation point. No public publishing or scheduled background work was performed.

The MyHouse follow-on starts with exact package/version and required-feature inventory. A [first-hand inspection/editing guide](https://www.speedrun.com/myhouse_wad/guides/y43o3) identifies a PK3 with ZSCRIPT/MAPINFO and distinguishes 2023/2025 releases. The original release forum and ZDoom wiki could not be retrieved through the initial web lookup; direct package inspection remains pending. Unsupported extension features must be distinguished from bugs in claimed support. The user asked for an audit; this does not yet establish feasibility or a promise of full GZDoom compatibility in PowerShell.

**Implemented first qualification step:** `scripts/Test-CampaignSmoke.ps1` discovers Ultimate Doom episode/map markers from the user's IWAD, creates a fresh game per map at skill 3, advances 35 idle tics, and performs two full 320×200 serial rasterizations at the resulting position with two camera headings. It checkpoints map/stage, retains failures, records exact source/IWAD hashes, and refuses to overwrite an existing report. These are load/simulation/render smoke checks, not playthroughs, visual-reference comparisons, or FPS measurements.

**Baseline failure:** all 36 map markers were discovered; 35 passed and E2M7 failed while loading. The WAD's line-flag value was interpreted as signed `-511` (`0xFE01`), which PowerShell rejected when converting to the named `LineFlags` enum. `results/campaign-smoke-baseline.json` preserves the failure. Nine synthetic LINEDEFS cases reproduced four failures involving bits outside the named flags; five cases passed. Evidence: `results/line-flags-before.json`.

**Fix and targeted checks:** changed only LineDef's stored/constructor flag type and removed its checked enum conversion. Flags retain the signed WAD bitfield in an integer; named enum constants continue to serve as masks. Unknown bits are preserved, including when setting the automap Mapped flag. All nine synthetic cases now pass (`line-flags-after.json`). This follows the bitfield treatment in the original [map loader](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/p_setup.c); it does not reinterpret reserved bits as supported new features.

**Repeat outcome:** all 36 maps pass the same sweep (`campaign-smoke-lineflags-fixed.json`), including E2M7. All 70 frame hashes from the previously passing 35 maps are unchanged. The existing E1M1 route generator also passes after the change: 1,560 simulation commands, five kills, actual intermission reached (`e1m1-route-lineflags.json`). This is a correctness regression check, not a new Terminal/PresentMon performance run. The per-map `docs/campaign-matrix.md` is generated by `scripts/Update-CampaignMatrix.ps1` and explicitly leaves other map completions and all terminal-host transitions unqualified.

**Separate source-inspected gaps:** the adopted game controller's episode-map-8 completion path does not select the finale, and its episode-4 secret-map return falls through to map 9 instead of map 3. The original [G_DoCompleted routing](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/g_game.c) establishes the intended outcomes. Finale content also needs episode-specific validation. These are queued for isolated reproductions and state-transition work; no campaign-transition success is claimed by the smoke harness. The current terminal host still stops at level completion.

**Final foundation validation:** all 217 source hashes recorded by the successful sweep still match. The bundle and other scripts pass 58 parse checks. The newly generated E1M1 input stream is identical to the baseline's 1,560 commands, and no experiment processes remain. `results/campaign-foundation-validation.json` records source/check counts, unchanged image/input evidence, raw-result hashes, and cleanup. The next implementation milestone is real session progression through intermission and map changes, with episode/secret routing reproductions first.

## 2026-09-10 — Matrix and character-art display discussion

The user asked about an expressive truecolor ANSI/Matrix aesthetic and whether it needs a separate project or could generalize as a shader. Source inspection confirms the current build already emits truecolor ANSI using upper-half-block cells; the pixel-like appearance comes from glyph choice. Added a visual-style exploration to the roadmap covering startup green palette mapping, a new PowerShell character encoder, temporal Matrix effects, an optional Terminal HLSL effect, and a separate general-game post-processing route. No runtime code, Terminal settings, or project priority changed in this discussion.

Microsoft's [shader documentation/sample](https://github.com/microsoft/terminal/blob/main/samples/PixelShaders/README.md) confirms an experimental per-profile HLSL shader receives the terminal image, time, scale, resolution, and background color. It has no Doom scene metadata in that documented interface. ReShade's [upstream project](https://github.com/crosire/reshade) describes generic game post-processing from color/depth inputs. These establish possible integration points, not a tested Matrix implementation or universal game compatibility. A GPU style effect would be explicitly separate from the user's PowerShell algorithm constraint. Character output can be implemented in PowerShell, with its intentional loss of pixel detail and actual performance measured against the existing mode.

## 2026-09-10 — Playable PowerShell character modes

The user authorized the prototype. Implemented `-Style Classic|AnsiArt|Matrix` through the launcher, host, worker pool, worker encoder, viewport, and measurement harness. Classic remains the default. Character modes keep the 320×200 rasterizer/simulation and encode a deliberately lossy 160×50 character view. The default font is 12 pt for character modes and 6 pt for Classic; explicit font size wins. Each worker owns pairs of source columns, shares the active-clock animation time at transport offset 72, and uses absolute image coordinates. No game algorithms moved to C#/native code or GPU shaders.

`src/CharacterCodec.ps1` samples eight indexed pixels per world cell. AnsiArt selects brightness/edge glyphs and a bright source color. Matrix uses a green contrast curve, stable spatially hashed glyphs, and sparse moving bright heads/fades. The bottom 32 source rows become eight rows of sampled half-block HUD cells; rain does not affect them. This loses HUD detail and is not a claim of full-resolution visual equivalence. There is no previous-frame ghosting buffer or geometry-attached code. See `docs/character-modes.md` for the exact boundary and alternatives.

**Offline visual iteration:** encoded the real local E1M1 tic-350 capture and painted the actual ANSI glyphs/colors into an ignored PNG. The first green view had weak scene contrast and a visibly repetitive linear character pattern. Expanded the green contrast curve and replaced the linear symbol choice with a fixed spatial hash. The preview uses GDI+ only for offline verification and is not a Terminal screenshot or game backend. WAD-derived preview files remain ignored. No visual preview alone establishes motion readability or frame rate.

**Correctness:** the character suite passes 72 serial/partition cell comparisons spanning both styles, two patterns, two origins, three times, and three worker counts. Its independent ANSI decoder checks coverage, bounds, duplicate writes and RGB ranges. Full-frame checks cover deterministic time, frozen AnsiArt, animated Matrix, green dominance, unchanged source buffers, and stable block HUD. Four hand-defined contrast/edge probes, six invalid-dimension cases, and ten character viewport layouts pass. Classic's 24 ANSI pixel round trips pass. Actual worker tests for each character mode compare 320,000 source pixels over five views with seven uneven processes, plus 35 encoded strip comparisons against the serial reference. Evidence: `character-codec-tests.json`, `character-matrix-partitions.json`, `character-ansiart-partitions.json`.

**Resize:** a real-engine headless Matrix run with synthetic grids pauses twice, resumes at exactly 160×50, recenters at 300×90, and preserves the active clock and issued-command count across pauses. It completes 110 simulation tics and 87 renders in 3.183 active seconds with four workers. This is a correctness run rather than a 60 FPS benchmark; no physical desktop resize was injected. Evidence: `character-matrix-viewport-tests.json` and `character-matrix-viewport-resize-session.json`.

**Live Matrix measurement:** the first maximized 12-pt capture reports 382×71 actual Terminal cells, no pause/error, and E1M1 completion after 1,560 tics with five kills and 75 health. It produces 2,682 writes in 44.694 active seconds: **60.008 writes/sec, 34.904 tics/sec**. Within the full first-to-last write window, PresentMon records 2,617 submissions, 2,615 display transitions (**58.593/sec**), and two dropped submissions. Display gaps: median 18.176 ms, p95 24.254 ms, max 66.648 ms; 31 exceed 33.333 ms. Fewer Terminal submissions than completed game writes remain an observed gap; its cause has not been isolated. Preserve it rather than calling the write rate displayed FPS. Raw evidence: `presentmon-matrix-prototype-*`; source worktree bytes: `character-sources.json`.

**Color-art measurement and repeats:** AnsiArt's first run completes at 60.001 writes/sec and 34.913 tics/sec, but PresentMon records 56.582 display transitions/sec, 128 dropped submissions, and a 612.121 ms maximum display gap. Drops occur from 0.124 through 5.995 seconds after the first write; 77 are in the first three seconds. A repeat produces 60.014 writes/sec, 34.920 tics/sec, 57.518 display transitions/sec, 101 dropped submissions, and a 1078.798 ms maximum display gap. Both raw observations are retained as `presentmon-ansiart-prototype-*` and `presentmon-ansiart-repeat-*`; no "best run only" substitution.

**Classic control and Matrix repeat:** with the same runtime source and a maximized window, Classic's 6-pt control reports 688×151 cells, 60.009 writes/sec, 34.918 tics/sec, 59.765 display transitions/sec, three dropped submissions, and a 66.673 ms maximum gap (`presentmon-character-classic-control-*`). The second Matrix run uses 12 pt / 382×71, produces 60.000 writes/sec, 34.925 tics/sec, 59.738 display transitions/sec, three dropped submissions, and a 60.607 ms maximum gap (`presentmon-matrix-repeat-*`). Every one of the five runs finishes the same 1,560-tic route with five kills, 75 health, no error, and no resize pause. Source files were unchanged throughout the five captures; no other study benchmark ran concurrently.

`scripts/Analyze-CharacterPresentation.ps1` checks the raw input hashes and builds `character-presentation-comparison.json`. Per-frame slowest-worker encode p95 is 3.31–3.40 ms for Matrix, 4.45–4.86 ms for AnsiArt, and 3.74 ms for the Classic control. This is not a same-output encoder speed contest: the source scene is shared but output cell count, glyphs, fonts, and physical image size differ. Stage timings overlap with rendering/output. Presentation remains variable and the observed gaps are not attributed to a specific cause. These results support a playable optional style prototype, not a universal 60 FPS or competitor-superiority claim.

**Visual limits:** inspected the final encoded tic-350 Matrix room and both styles at the dark tic-700 corridor. The spatial hash removes the earlier repeated rows; broad scene shapes are visible. Dark surfaces and small enemies remain harder to distinguish, and downsampled HUD labels lose detail. Both ignored previews are explicitly labeled offline cell renderings. Human motion/readability and keyboard play remain unobserved; a successful predetermined route is not evidence that a person can comfortably read every fight.

**Final validation:** the current character codec passes its 72 cases after the final spatial-hash change. Classic's real worker regression also passes, bringing serial/process pixel comparisons to 960,000 across all three modes, with 70 character strip-byte comparisons. All 224 recorded source hashes match; 62 script/bundle parse checks report no errors, and no owned game process remains. `results/character-validation.json` records the checks and result hashes. Only authored code, documentation, and measurements are included; user game assets and previews remain local. Campaign progression, audio, menus, and broader fidelity qualification remain on the existing release roadmap.

## 2026-09-10 — Katakana glyphs and screen recording

The user requested Japanese characters for both effects and actual screen recordings. Added the shared `Ascii|Katakana` alphabet option through launcher, host, render pool, workers, tests, and measurement metadata. Katakana is the new launcher default for character modes, with MS Gothic at 12 pt; ASCII retains the earlier Cascadia Mono behavior. Classic remains the overall default. Only glyph choice changes inside the encoder; the source scene and simulation are shared.

**Width evidence:** Unicode 17 marks the selected half-width punctuation/kana range U+FF61–FF9D as H. The alphabet excludes FF9E/FF9F and full-width code points and avoids compatibility normalization. In live Terminal, all 61 distinct combined alphabet/HUD symbols individually advanced one column. The maximized MS Gothic profile reports 430×85 cells. A cheaper aggregate 61-symbol check now runs at ordinary startup. `results/katakana-gdi-probe.json` retains the individual width results. These are console cursor measurements; a successful WGC image also verifies visible katakana rather than missing-glyph boxes.

**Capture investigation:** downloaded the GPLv3 FFmpeg 9.0.1 essentials build from Gyan's upstream-listed distribution, verified the archive checksum, and retained it under ignored `local/tools`. No OBS/user profile settings were changed. The first finite eight-second game test completed 279 tics and 480 writes, but its GDI window recording was visually black at both sampled timestamps. Kept it as a failed capture. The next WGC attempt failed in `scale_d3d11` with texture allocation error `80070057`; removing that conversion and passing captured D3D11 frames directly to NVENC produced an actual visible game-window recording. Video capture/encoding is an external measurement/presentation tool, never a compiled Doom renderer or encoder substitution.

The successful short WGC probe is a 3440×1392 H.264/yuv420p movie containing startup and eight seconds of gameplay; the recorded frame shows katakana, the scene and HUD at the expected centered location. The probe used a 60-arrival cap and its output includes many duplicated startup frames. Full recordings use a higher 240-arrival ceiling and resample to 60 FPS to reduce potential capture-rate aliasing. The cap and encoder duplication/drop logs remain explicit. Neither the encoded video rate nor a still frame proves 60 unique displayed game images.

**Two full recordings:** Matrix and AnsiArt both complete E1M1 with 1,560 tics, 2,681 completed writes, five kills and 75 health, no errors and no viewport pauses. Matrix takes 44.6766 active seconds (34.918 tics/sec, 60.009 writes/sec); AnsiArt takes 44.6731 (34.920 tics/sec, 60.014 writes/sec). Both use maximized MS Gothic 12 pt, 430×85 cells, and a successful 61-symbol/61-column startup probe. Captures ran sequentially with unchanged runtime bytes and no concurrent study benchmark or export. These are recorded-run game timings, not new PresentMon measurements. Full reports are `results/recorded-{matrix,ansiart}-katakana-game.json`.

**Viewing copies:** retained untrimmed originals, capture logs and metadata under ignored `local/recordings`. Added `Export-DoomRecording.ps1` to verify originals, scan the inspected game rectangle, check visible duration against the game report and make separate trimmed/cropped copies. Matrix keeps 25.0–69.8 seconds; AnsiArt keeps 24.0–69.0. The 1280×800 crop at (1080,304) matches the observed 160×50 game cells and removes fixed margins/window chrome. Both H.264 copies preserve playback speed and have no added shader, tint or rescaling. Full decoding counts 2,688 / 2,700 frames at encoded 60 FPS (44.8 / 45.0 seconds), including any capture duplicates. Inspected actual captured frames at 10, 23 and 43 seconds in each copy: Japanese characters visible, game/HUD inside crop, no missing-glyph squares or outside windows in these samples. Matrix's dark scenes and green HUD still lose readability. `results/katakana-recordings.json` retains hashes, parameters and inspection scope; user-derived footage remains local.

**Correctness and final audit:** 144 character serial/partition cases pass across both alphabets/styles, plus eight independent brightness/edge probes, six dimension guards and ten viewport cases. Each katakana style passes five real worker views (320,000 source pixels and 35 strip-byte comparisons); Classic's 24 ANSI round trips also pass. All 223 runtime/capture source hashes match, 64 script/bundle parses have no errors, four original/viewing-copy video hashes match, and no owned game/recorder process remains. The audit is recorded in `results/katakana-validation.json`. The requested two visual demonstrations are complete; campaign progression remains the next main release milestone.

## 2026-09-11 — Active release goal: campaign session progression

The user activated the full Ultimate Doom release goal. The existing worktree was clean at `e95fee8`. Work resumes with M1; the original release gates and later work remain intact. No repeating schedule or separate task was created.

**Controller reproductions:** added `Test-CampaignTransitions.ps1`. Its routing/controller fixtures reproduce 13 failures in 54 checks: all four map-8 endings enter intermission, episodes 2–4 select episode-1 finale flat/text, E4M9 returns to map 9, par seconds are passed where tics are required, and prior secret-visit history is lost. `campaign-transitions-before.json` retains failures. Targeted fixes now pass all 54 checks (`campaign-transitions-fixed.json`). These are isolated routing/inventory/exit fixtures, not map playthroughs. The original [game controller](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/g_game.c) and [finale implementation](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/f_finale.c) establish the routing, units, and episode content. The adopted episode-4 par table is retained; it is not claimed to reproduce the original out-of-bounds episode-4 behavior.

**Ordinary-input continuation:** `Test-SessionProgression.ps1` replays the existing 1,560-command E1M1 route, then uses three spaced use-button presses and idle commands. All 1,747 commands pass through `TicCmd`: E1M1 completes, intermission advances, E1M2 loads, inventory matches the E1M1 exit, and E1M2 advances 71 level tics. `e1m1-e1m2-session-route.json` records the inputs and transitions. It does not claim E1M2 completion.

**Session screens:** the adopted PowerShell intermission renderer draws native WAD graphics. The first finale probe failed because the renderer treated the instance `TextSpeed` as static and divided by zero. The original 320×200 flat-fill path took 655 ms in that probe. Fixed the field access, cached immutable background pixels, and retained already-revealed finale text so normal ticks only draw newly revealed characters. All 24 episode/stats/next-map/text/art snapshots render, and their indexed hashes remain identical across the cache change. The E1 blank-text background also matches the pre-fix reference flat fill exactly. `session-screen-before.json`, `session-screens-first.json`, and `session-screens-cached.json` retain evidence. These are functional probes with cold work included, not paired performance benchmarks; the first screen sweep overlapped the unpaced route check.

**Host integration in progress:** simulation snapshots now carry state, episode/map and world generation. Session screens cross as indexed column-major pixels and the existing PowerShell workers transpose/encode their strips. A map handoff drains old jobs, reloads assets in the same renderer processes, checks generation, then acknowledges simulation continuation. Handoff pauses and discarded obsolete frames are reported explicitly. Existing single-map replays retain their first-exit stop; session replays declare `ContinueCampaign=true`. Live verification follows the headless lifecycle checks.

**Host failure and correction:** the first headless run reached command 1,560 and failed converting the intermission framebuffer because an `if` expression enumerated its bytes into an object array. The host now declares the payload `byte[]`. `session-host-first.json` preserves the failure. The corrected full host consumes all 1,747 commands, renders E1M2, and ends `ReplayEnd` without errors (`session-host-buffer-fixed.json`): 50.219 active seconds, 51.130 wall seconds, one 0.909-second asset handoff. Map-load work inside the simulation tick remains in its measured cost; the explicit asset handoff is separately paused/reported.

**Visual correction:** inspecting the actual indexed 2D screens showed leading spaces embedded in the translated finale here-strings. Episode-4 text was clipped on the right. Removed source indentation/trailing padding and normalized line endings for the four Ultimate Doom finale texts. All episode line widths now fit the WAD font within 310 pixels; the corrected offline contact sheet shows complete text. `session-screens-text-fixed.json` retains the new hashes. No full-frame pixel equivalence is claimed across this intentional text fix. Text-reveal time no longer counts accidental indentation.

**Worker and controller validation:** extended controller coverage to lethal engine damage, use-button respawn, fresh same-map world and reset pistol inventory: 57 checks pass (`campaign-transitions-session.json`). Seven actual workers in each of Classic/Matrix/AnsiArt pass independently constructed column/row-major screen equivalence and E1M2 asset reload with unchanged process IDs: 384,000 pixels and 42 strip-byte comparisons in total (`session-worker-*.json`). The first Classic worker harness omitted a codec import; its harness failure is preserved separately. Existing 24 ANSI round trips and 144 character-codec cases pass. These are functional checks, not live performance comparisons.

**Three live session recordings:** Classic, Matrix and AnsiArt consume all 1,747 ordinary-input commands, advance intermission, carry inventory into E1M2, and render generation 2 without error or viewport pauses. Captures run serially against unchanged runtime bytes. Active tics/sec are 34.712 / 34.718 / 34.706; completed writes/sec are 58.217 / 59.421 / 58.307. Explicit asset handoffs take 0.910 / 0.938 / 0.887 seconds and remain in wall timing and video. Slower output rates are retained as an open M6 issue; this is recorded-run evidence, with no new PresentMon/displayed-FPS claim. `results/session-recorded-*-game.json` retains full reports.

**Recording export and review:** all three original window captures remain local alongside separate viewing copies. Full decoding verifies 3,090 / 3,096 / 3,102 encoded frames at 60 FPS and 51.5 / 51.6 / 51.7 seconds. Export now compares wall duration so map handoff is not removed. Actual captured samples at 45.5, 47.5 and 50.5 seconds show the stats, next-map and E1M2 screens. Classic's crop includes one pixel above/below for even H.264 coordinates; no game clipping is observed. Katakana is visible, but small intermission text is difficult to read, especially Matrix. Preserve this observation for the M2 menu design. No added visual effect, rescaling or speed change is used in the lossy viewing copies. `session-recordings.json` records hashes and exact parameters.

**M1 final audit:** all 224 frozen runtime/capture hashes match, 69 script/bundle parses pass, all six original/viewing video hashes match, and no owned game/recorder process remains. `session-validation.json` pins the evidence set. M1 foundation is verified; wider campaign completion, menus/save/load/automap, audio, final fidelity/pacing and release/article gates remain active. The goal continues into M2 without requiring another user prompt.

## 2026-09-11 — M2 input recording

Committed M1 as `99a5c13`. Added opt-in `-RecordInput`, versioned data-only replay files, IWAD/settings validation, source fingerprints, and selected-state checkpoints. Recordings use commands consumed by the simulation and preserve initial settings; new filenames and non-overwriting temporary-file publication protect prior play evidence. Checkpoints sample RNG/player/session/render data, not the complete hidden world graph. They do not constitute save states or vanilla demo compatibility. Normal recording writes at orderly exit; crash journaling is still pending.

**Failures retained:** the first short no-replay host attempt failed on an optional field under strict mode before gameplay (`input-recording-short-game.json`). The first format sweep found an incompatible `Contains` call on PowerShell's bound-parameter dictionary (`input-replay-format.json`). Optional fields are normalized, no-replay accesses are guarded, and explicit binding uses key membership. The corrected skill-2/E1M2 host records 139 scripted commands; playback chooses those settings and matches both checkpoints (`input-recording-short-fixed-game.json`, `input-recording-short-replay-game.json`). A source warning correctly identifies the intervening dictionary fix. The current format suite passes 35 checks (`input-replay-format-final.json`). Full session replay verification is in progress.

**Full recording and negative verification:** the actual headless host records the established 1,747-command E1M1/intermission/E1M2 route, then a separate host instance replays the versioned file. All eight start/350-tic/transition/final checkpoints match with unchanged simulation source, and both instances render E1M2 generation 2. The portable `input-session-replay.json` retains commands and checkpoints with `Origin=Replay`; this is not human-play evidence. Changing just the first turn command in the short fixture preserves the initial checkpoint but diverges at tic 139, producing `ReplayDiverged` and process exit 1. Raw reports and the altered input remain in `results/`.

**Recording audit:** `input-recording-validation.json` records format checks, command equality against the established route, checkpoint outcomes, source/result hashes, 71 successful script/bundle parses and zero remaining owned game processes. The full-run checkpoint median is 3.618 ms and maximum 66.506 ms (initial checkpoint before the active clock); this is opt-in functional-test overhead, not a clean pacing comparison. No rendering algorithm changed and no live effect run was needed for this input-only increment. Menus/pause, save/load and automap remain the next M2 work; the release goal stays active.

## 2026-09-11 — M2 menus and pause

The previous goal turn made progress: commits `99a5c13` and `1183d6f` implement and verify campaign session handoff and versioned input recording. The worktree is clean at this continuation's start. Source inspection shows the inherited `DoomMenu` depends on the separate `Doom` wrapper and video/input settings interfaces; the current host owns its own simulation/render processes. A small PowerShell session controller will use native WAD menu patches and the adopted `DrawScreen`, with an acknowledged control request after issued gameplay commands have drained. Menu/pause wall time will stop scheduling without discarding commands. New-game actions will enter a versioned replay control stream. Character styles will use readable block menu graphics within their existing 160×50 grid; gameplay effects remain intact. These are implementation decisions; live verification follows.

**Menu implementation/checks:** added resume/new-game/episode/difficulty/control/quit menus, pause/resume, acknowledged command-boundary control requests, separate menu representation/revision metadata, compact text menus for undersized viewports, and replay version 2 new-game events. The first Matrix host probe failed on arithmetic/comma precedence in the menu encoder's index list; parenthesized expressions fix it (`menu-probe-game.json` versus `menu-probe-fixed-game.json`). Independent menu-color reduction, navigation, screen/compact-layout and worker tests pass: 70 checks/19 screen fixtures, 576,000 worker pixels and 63 strips across all styles, plus 144 existing character cases. A new-game replay matches three checkpoints and preserves all 199 consumed commands, including one completed during the original host's shutdown. Resize at 98 rows while paused preserves tic 34 until explicit resume; the full E1M1/E1M2 route still matches eight checkpoints.

**Capture/input failures:** the first Classic and Matrix menu captures complete, while the AnsiArt game completes but external FFmpeg exits with `-1073741819` (0xC0000005) immediately after receiving `q`. No final encoder summary is written. Preserve that capture as failed; it is not a verified demonstration, and the precise native crash cause is undetermined. Separately, `Test-MenuInput.ps1` reproduces three failures in eight synthetic native-key checks: clearing physical held state on menu actions makes auto-repeat look like new P/movement/Enter presses. Menu reset now preserves physical down/up state and masks gameplay keys until release. This is a concrete input fix, not a claim that physical play has been observed. Final recordings follow the correction.

**Readability review:** all three captures after the key-state fix complete successfully, and their Classic input file replays with matching source and three matching checkpoints over 120 commands. Sampled video inspection then rejects the small control/help text as too difficult to read after character-mode reduction. Custom menu text now draws at 2× scale, with shorter lines and centered prompts. An offline reduced-pixel preview catches a clipped footer; shortening that footer and checking each glyph's bounds fixes it. All 70 checks and 19 native screens pass again (`menu-unit-readable-fit.json`). A further three live captures record this corrected layout; earlier originals and viewing copies are retained. An initial ignored preview harness passed flat palette bytes to an RGB-array API and was corrected before creating the previews; that was a harness issue.

**Final review fixes:** source review catches an accepted negative new-game boundary (`-1`) and a missing redraw when restoring a resized static menu. The reader now rejects negative boundaries, with 42 format checks passing (`menu-replay-format-bounds.json`). The host redraws a dirty viewport even when the menu revision and active clock are unchanged. Repeating the seven-second resize probe produces two paused-menu frames instead of the earlier one, both at tic 34 and the same active time/revision, then finishes with 139 commands (`menu-resize-redraw-game.json`). An exploratory assertion incorrectly expected at least 1.5 seconds between those frames; measured spacing is 1.255 seconds because the first menu is published after lazy graphics initialization. The relevant checks are unchanged paused state and the added redraw, not that arbitrary threshold.

**Capture lifecycle:** the first enlarged-text Classic capture succeeds, but the next launch starts before its Terminal process has finished its configured exit delay. The isolation guard refuses the second launch and leaves the existing window alone. The local batch now waits for that owned Terminal to exit before the next capture. Three subsequent `menu-verified-*-full` captures all succeed against `menu-verified-sources.json`, including the final redraw and bounds fixes. No user Terminal profiles or unrelated processes are changed.

**Menu milestone audit:** the final viewing copies fully decode to 1,134 / 1,152 / 1,194 frames at 60 CFR, lasting 18.9 / 19.2 / 19.9 seconds for Classic / Matrix / AnsiArt. Six actual-video samples per style verify menus, gameplay, enlarged control text and pause guidance inside the crops. Matrix is still fairly dim, retained as a tuning limitation. No audio, added effect, rescaling or speed change is present. The final Classic input file replays all 122 commands with matching source and all three selected-state checkpoints. `menu-recordings.json` and `menu-validation.json` pin the results: 226 matching runtime/capture source hashes, 74 successful parses, six matching video hashes and zero owned game/recorder processes. The release goal remains active; save/load, automap and settings are the next M2 work.

## 2026-09-11 — M2 save/load

The previous goal turn made progress and committed menu/pause work as `722b5a8`; this continuation begins with a clean worktree. The inherited serializer writes a 25,682-byte file after 350 ordinary E1M1 commands, but loading it changes both the render checkpoint and RNG (177 to 144). A one-byte invalid save replaces the world before rejection. Source inspection identifies other omissions and reordered thinkers. `Test-InheritedSave.ps1` and `save-inherited.json` retain the probe. The next design is a bounded data-only graph with explicit source/IWAD bindings and a separate candidate session; validate continuation before exposing save slots. See [save/load investigation](save-load.md).

**Core implementation and qualification:** `SaveState.ps1` uses a fixed data-type catalog, graph IDs, exact IWAD bindings, bounded JSON/checksums, atomic replacement with a retained backup, and reconstruction into a separate game with null devices. Runtime callbacks stay attached to constructor-created candidate components. The corrected ordinary-input matrix passes 48 checks at commands 700/1550/1600/1700 plus 140 commands each. Twelve special-object checks cover pending switches, fire flicker, a crusher, a stasis platform and cyclic target/tracer/sector-sound references. Twenty session-edge checks cover death/use/respawn and text/end-art continuation for all four episode finales. These are explicit fixtures, not new campaign playthroughs.

**Failures and repairs:** early graph probes exposed generic type-key collisions, PowerShell dictionary indexing of array keys, and the boss-action scratch line's missing binding; these were corrected before the formal matrix. The first same-process report passed 22 checks but used the wrong button property under non-strict mode. The first multi-point matrix then revealed command carryover between independent fresh games and a real stale-map reference: `Player.Attacker` retained an E1M1 actor after entry into E1M2. An isolated probe reported old-world identity true, current-world identity false, an unbound Subsector error before clearing the attacker, and no graph error afterward. `SpawnPlayer` now clears this reference with the damage counter; actor targets within the current world remain in saves. The fixed matrix passes. All early reports remain as limited/failed evidence.

**Independent process proof:** an intermission save at command 1600 is loaded in PID 4772 while PID 17252 plays the original full prefix. After 147 more commands, all five sampled checkpoints and the final canonical graph hash agree. The uninterrupted reference also matches all eight original recorded checkpoints; the loaded suffix matches both original checkpoints it encounters. Both processes run PowerShell 7.6.5. This verifies the lifecycle fix against the preexisting selected-state/render-snapshot baseline. The overlapping process run is correctness evidence, not a clean timing experiment.

**Corruption checks:** ten additional named validation checks pass, including actual content IWAD mismatch, truncation, file size cap, duplicate bindings, invalid collision grid/RNG/fixed values and header/graph disagreement. Null thinker-ring rejection originally surfaced through a property exception; an explicit guard now provides a defined error. Two follow-up failures were case-sensitive property lookup errors in the test fixture, corrected to match PowerShell property semantics. The final report requires the intended rejection message and an unchanged live checkpoint; arbitrary harness errors do not count as passes.

**Milestone scope:** 90 named checks and the separate-process comparisons establish the tested core. Save slots, menu decisions, source-version policy, live device/asset installation, replayed loads and live recordings remain next. Single observed saves take 1.33–2.50 seconds and candidate loads 1.03–1.96 seconds in the corrected matrix; these are operation latencies, not FPS. No live display algorithm changed in this milestone. The release goal remains active. Workflow state was checked directly: this task already has the durable Ultimate Doom goal, so no duplicate scheduled automation was created.

**Core commit audit:** `save-core-validation.json` records 285 current PowerShell source hashes, 79 successful standalone parses plus the aggregate adopted-engine parse, all 90 accepted named checks, and zero observed study game/test/recorder processes. The positive matrices precede the final null-ownership/ring guard; their original source hashes are retained, while final validation and separate-process tests cover the guarded implementation. `save-process-comparison.json` records five matching sampled checkpoints, an identical final graph, distinct PIDs and the original 8/2 checkpoint matches. `save-old-world-probe.json` retains the raw stale-attacker observation. The work remains local and the release goal remains active.

## 2026-09-11 — M2 save slots and host integration

The previous goal turn made progress and committed the save core as `2adc601`; this continuation started from a clean worktree. The host now exposes six IWAD-specific save slots, default-no overwrite/load confirmations, visible source-version differences, and busy/error screens. The simulation receives bounded JSON session payloads at its existing exact command boundary. Candidate reconstruction and immutable replay archival finish before the live game is replaced; the renderer then acknowledges a new asset generation. Rejected loads remain paused in a recoverable menu and preserve the current world. Save metadata and its confirmation hash now come from the same byte buffer, closing a mismatch between parsed content and a later file hash.

The new replay version 3 records hash-only load controls and requires the exact archived save under the matching SaveRoot. Archives survive later slot overwrites. Source fingerprints now include both save implementation files. The initial checks pass: 46 replay-format cases, 15 save-menu navigation/metadata cases, 12 actual simulation-worker save/restore/backup/archive cases, and 90 menu/encoder checks across 39 native screen fixtures. Initial headless host save/load succeeds; its version-3 recording replays all 530 consumed commands with the same source and four matching checkpoints. The original host reports 529 measured tics because one queued command is drained during shutdown, preserved in the final recording as designed.

Offline reduced-menu previews show the new slot and changed-version confirmation text fitting. The main logo touched the first item, so the six-item layout gained a small gap and the 90 menu checks were repeated successfully. Review also found that taps queued during a long action could leak into gameplay; action completion now drains pending console records before clearing presses/masking held keys. Ten synthetic native-input checks pass, including the queued-tap and release cases. These are not physical keyboard observations. A further headless test is checking intermission/finale save loads through the full renderer handoff before live footage is recorded.

**Full host session coverage:** the intermission/finale test completes two confirmed older-source loads. It installs the intermission save as generation 2 at command 34, advances to E1M2 as generation 3 at command 53, then installs the E3M8 finale as generation 4 at command 158. Frames are emitted for Level, Intermission and Finale states. Its version-3 replay consumes all 448 commands with unchanged current source and all six checkpoints matching. Original game-clock values are restored independently of the monotonically increasing input index.

**Capture failure retained:** the Classic save/load/overwrite capture succeeds. The first Matrix game also confirms quit after two successful saves and one successful load, but external FFmpeg exits with `-1073741819` after its `q` shutdown request. Windows Application Error records `0xc0000005` in `graphicscapture.dll_unloaded`. `save-menu-capture-failure.json` retains the metadata and event; this does not prove a root cause or implicate the engine. The Matrix recording is not accepted as verified footage. The next bounded capture attempt uses a 120-frame/s ceiling instead of 240 and a fresh output/save root; this is a changed capture workload, not a demonstrated fix for the native teardown failure.

**Capture lifetime experiment:** lowering the Matrix capture ceiling to 120 still ends in the same external encoder failure; the game again completes. `save-menu-capture-failure-120.json` retains it. The recorder now exposes the game's post-report exit delay and records nonzero encoder exits as errors in its metadata. A subsequent Matrix capture at the same 120 ceiling and a 15-second window-close delay succeeds. This supports using a longer target lifetime for these recordings, but is not proof of the underlying Windows/FFmpeg fault's cause. GDI window capture and an installed OBS executable were inspected as possible fallbacks; neither was used for accepted footage. The FFmpeg [GDI device documentation](https://ffmpeg.org/ffmpeg-devices.html#gdigrab) was consulted during that investigation. Classic retains the original capture manifest; delayed-close runs use `save-menu-capture-sources-held.json`.

**Lifetime hypothesis limited:** the following AnsiArt capture still crashes in external FFmpeg with the same 15-second window delay. The successful Matrix run is not a reliable workaround; the failed AnsiArt metadata/event and successful game operations are retained in save-menu-capture-failure-held.json. Added an explicit GDI game-window capture option, sampled at 60 Hz, as a separate recorder workload. Its actual output must be inspected before accepting footage. Game algorithms and source fingerprint are unchanged; save-menu-capture-sources-gdi.json pins the recorder change.

**GDI visual rejection:** the bounded GDI color-art run exits FFmpeg 0 and all three game operations succeed. However, the actual video sample at game wall time 1.5 seconds is black. This recording is rejected despite its clean encoder exit; save-menu-gdi-black.json retains the metadata and inspected image hash. One further bounded Graphics Capture color-art attempt follows, with the 15-second hold and a fresh root/output. GDI remains an explicitly selectable experimental recorder backend, not an accepted Terminal capture path on this machine.

**Recorded-menu review and timestamp correction:** Classic, Matrix and AnsiArt Graphics Capture viewing copies fully decode to 1,908 / 1,902 / 1,914 frames (31.8 / 31.7 / 31.9 seconds at 60 CFR). Their recorded inputs replay 493 / 479 / 493 commands with matching source and four matching checkpoints each. Sampled menu review shows readable default-no decisions and returned gameplay; Matrix remains dim, and a sampled cancellation footer is partially drawn but complete 0.2 seconds later. Capture/scheduling timestamps are only approximate alignment, so follow-up frames verify Classic confirmations rather than assuming scheduled labels identify the footage.

The review also catches UTC-looking slot times. ConvertFrom-Json already returns a UTC DateTime; passing it through Parse(string) drops its Kind. A fixed UTC fixture reproduces the failure (save-menu-time-before.json). Preserving the typed value fixes local conversion; all 16 metadata/navigation checks pass (save-menu-time-fixed.json). Existing footage retains the earlier time labels. This display-metadata change alters the source fingerprint; a post-fix replay checks observed compatibility. Additional corruption checks still pass all ten cases. An overlapping final host/worker launch collides on the existing shared engine-bundle cache (save-worker-final.json); that worker check must run serially. Concurrent startup remains a known limitation to address in startup qualification, not evidence of corrupted saves.

**Save-menu milestone audit:** save-menu-validation.json records 184 accepted named checks in the integrated suite, 83 successful standalone parses plus the aggregate engine parse, 289 current source hashes, three accepted original/viewing-copy hash pairs and zero owned game/recorder processes. Capture-source comparisons explicitly list the later recorder and local-time changes. The serial worker rerun passes all 12 checks, and the post-time-fix Classic replay preserves all 493 commands and four checkpoints despite its expected source warning. The full release goal remains active; automap and settings are next. No audio, whole-campaign completion or unique displayed-FPS claim is added by this milestone.

## 2026-09-11 — Private GitHub backup

The user explicitly requested a private GitHub repository because no remote backup existed. The local checkout had no remotes, and the authenticated account had no repository named pwshDoom. Created [jasonulbright/pwshDoom](https://github.com/jasonulbright/pwshDoom), verified GitHub reports it private, and configured it as `origin`. The existing branch is `codex/feasibility-study`; preserve its history without rewriting it. Future reviewed milestone commits should be pushed and checked against the remote branch as part of this authorized backup workflow.

The Git backup covers committed source, documentation and portable result records. History inspection found no ignored local assets, WADs, videos or downloaded binaries; the largest committed blob was approximately 6.9 MB. The ignored `local/` directory, including screen recordings and save fixtures, remains local and is not backed up by Git. Public publication remains a separate decision.

## 2026-09-11 — Automap foundation checkpoint

The private backup was verified at commit `46f272a`; the full release goal remains active. Source inspection identified existing automap state/rendering but no discovery updates or map controls in the fast host. Added an experimental inherited-BSP discovery pass and a finite comparison harness using unique bundle/output paths. At four headings each in E1M1, E2M7, E3M8 and E4M1, all 48 initial checks pass: mapped lines match the full reference renderer, frame bytes remain untouched, and world/sector validity counters remain unchanged. This does not qualify reference buffer limits, moving scenes or campaign-wide discovery.

The inherited map/HUD combination costs roughly 146–184 ms at the initial stationary medians. Bulk clearing of the map area and skipping undiscovered-line transforms retain all 16 baseline pixel hashes but do not demonstrate a general speedup: corrected medians are 154–183 ms. The first comparison attempt fails in the harness because strict mode rejects a missing Heading property on a summary case. Explicit property membership fixes it, and the corrected report passes 64 checks; both failed and successful reports are retained. Discovery medians are about 1.4–14.6 ms in the corrected run. These are operation costs, not displayed FPS.

See [automap investigation](automap.md) for exact reports, reproduction and remaining work. The map is not yet wired into gameplay, so there is no new live effect recording. Map/HUD costs must be separated before selecting an integration path. This checkpoint preserves tested foundation work for private backup and does not declare M2 or the release complete.

## 2026-09-11 — Automap host implementation

The previous turn made progress: `e979b58` preserved the discovery experiments and was verified against the private remote. This continuation starts from that clean checkpoint. Separating the inherited draw cost shows map-only medians of 2.8–7.9 ms and HUD medians of 144–165 ms (`automap-foundation-split.json`). The HUD uses DrawColumnExact, whose unit-scale branch still performs fixed-point work per pixel. Routing unit-scale columns through the existing clipped post blitter preserves all 16 baseline map/HUD hashes and reduces observed HUD medians to 18–23 ms (`automap-foundation-hud-blit.json`). These sequential operation samples are not displayed-FPS measurements.

Added simulation-owned map commands/discovery, map bitmap publication, readable menu-style encoding for thin map lines, and a presentation-only HUD cache keyed by every HUD input. New replay version 4 retains four-integer gameplay commands and adds an ordered sparse automap mask stream plus optional map-state checkpoint hashes; older files remain readable. The simulation bundle now uses a PID-specific filename to avoid the previously observed concurrent startup collision. Real-host qualification is in progress.

The first session fixture passes composition/control checks but omits the required IWAD hash when saving. The next fixture supplies the hash but leaves GameVersion/MissionPack at defaults, so candidate validation correctly rejects the inconsistent saved header. Both reports are retained as harness failures. Supplying all content settings yields 43 passing session checks, including map modes, all-map power, fourteen HUD cache invalidation states, marker wrap/clear, held-state release, saved map restoration, and synthetic arrow capture. The expanded replay suite passes 58 checks, including map-only divergence. The actual simulation worker passes eight checks covering bitmap publication, map-preserving save/load/menu transitions, asset generation and new-game visibility reset. These are not human keyboard observations or whole-campaign qualification.

**Full-host pacing failure:** a seven-worker Matrix host consumes all 350 commands and produces map frames, but takes 13.4845 active seconds for ten seconds of simulation. Discovery averages 25.613 ms under the active workload, compared with 4.522 ms gameplay and 7.884 ms snapshot publication. The latter includes map drawing on 245 snapshots (9.068 ms mean, 175.544 ms maximum). The separate replay takes 13.0364 seconds and matches both recorded gameplay/map checkpoints. This establishes a functional path and a pacing regression, not the 35 Hz target. README now distinguishes historical near-target measurements from this build.

**Presentation and evidence preservation:** frame captures now use a unique directory per host run instead of overwriting shared tic filenames. The first expanded controls screen fails the existing text-bounds guard; shorter labels pass all 90 menu checks/39 screens. Classic, Matrix and color-art live window captures complete successfully at all 350 commands. Actual Matrix footage exposes HUD blurring from applying brightest-region reduction to the entire map bitmap. Added a distinct automap worker job: map lines retain that reduction, while HUD rows use the established gameplay samples. Independent reference comparisons pass 118 menu/map codec checks; seven uneven workers in each of the three styles compare 768,000 pixels and 84 encoded strips across screens, menus, automap and asset reload. Ten existing native-key menu checks also pass. Earlier captures remain as pre-correction evidence; new character-mode captures are in progress.

**Automap checkpoint audit:** corrected Matrix and AnsiArt window recordings finish successfully. The accepted Classic/Matrix/AnsiArt viewing copies decode to 846/900/963 frames, lasting 14.10/15.00/16.05 seconds at 60 CFR. Their 350 commands, map masks and both gameplay/map checkpoints match the independently replayed headless fixture. Full-resolution map images and four-sample video sheets verify visible gameplay/map/HUD content; Matrix remains dim and character-grid labels/markers lose detail. The Classic sheet includes the end-of-game clear. All originals remain local, including pre-HUD-correction captures. Recorded active durations are 14.08–15.16 seconds for ten seconds of simulation; no unique displayed-FPS claim is made.

The original 1,747-command campaign session still matches all eight legacy checkpoints through E1M1/intermission/E1M2. It takes 52.5108 active seconds for 49.9143 seconds of simulation. Discovery costs vary by viewpoint (12.45 ms mean, 32.46 ms p95 in that run). The report assembler initially assumes every check report has an Error field; the native-key report omits it. Explicit property membership corrects this assembly error. `automap-validation.json` pins 293 source hashes, 87 successful standalone parses plus the aggregate bundle, 301 named checks, transport comparisons, recording metadata and zero observed owned game/recorder processes. Discovery optimization and broader moving-scene qualification are next; audio, settings, campaign completion and the release/write-up gates remain open. The full goal remains active.

## 2026-09-11 — Numeric automap discovery

The previous turn made progress and privately backed up `bff89b9`. The worktree is clean at this continuation's start. The user clarified that their usage-reset message was a notice of an action already taken; it was incorrectly treated as a request to redeem a credit. No redemption was applied. The active release goal remains authorized and work resumes without another permission step.

The discovery-only projection now uses integer binary-angle arithmetic instead of repeatedly allocating Fixed/Angle wrappers. `Geometry.PointToAngleData` preserves the adopted slope lookup table, octant offsets, wrapping and slope rounding, including a fallback to preserve the retained implementation's edge behavior at signed-minimum deltas. Segment visibility reads current sector heights at the already-selected simulation endpoint. The full reference renderer retains its existing path and provides the comparison.

`automap-numeric-foundation.json` passes all 64 original checks, including sixteen unchanged map/HUD pixel hashes. Repeated stationary discovery medians are 6.282 / 3.370 / 0.569 / 1.367 ms for E1M1/E2M7/E3M8/E4M1. `automap-numeric-route.json` compares 2,139 random and boundary point-angle cases and 48 sampled viewpoints along the established moving E1M1/intermission/E1M2 route. All 50 named checks pass, including all eight original gameplay checkpoints after restoring reference-only flags/counters. This broadens moving-scene evidence but does not establish every-map discovery or reference-buffer-limit parity. Full-host timing follows; these isolated operation samples are not displayed FPS.

The seven-worker numeric-discovery host finishes 350 tics in 10.0293 s and matches both gameplay/map checkpoints; discovery averages 8.856 ms, versus 25.613 ms in the earlier seven-worker run. The default sixteen-worker run finishes in 10.0343 s with both checkpoints matching and 452 completed frames (45.05/s). These restore approximately 35-tic scheduling for this bounded workload, while the 60-update target is still missed. Headless completion counts do not measure display presentation.

A subsequent menu/map encoder change replaces per-cell temporary index arrays and a growing string list with direct comparisons and a sized string array, preserving first-wins luminance ties and gameplay HUD samples. Its first test fails because PowerShell treats a new local `rowOffset` as the existing `RowOffset` parameter; the test's finally block then masks the failure with an uninitialized `directory` variable, so no JSON report is produced. Renaming the local `sourceRow` and initializing the harness directory fixes both issues. The corrected run passes all 118 independent menu/map checks and 39 screen fixtures. This failed attempt is retained here because it produced no report file.

The final sixteen-worker headless control run completes 600 frames and all 350 tics in 10.0341 s, matching both checkpoints. Matrix/AnsiArt transport checks compare 512,000 pixels and 56 strips. The near-60/35 aggregate result is not uniform pacing: tic lateness reaches 224.11 ms, and an uncached map/HUD draw reaches 190.77 ms. The recorded Matrix Terminal run consumes the identical gameplay/map commands and matches both checkpoints, with 599 writes in 10.0315 s. Its viewing copy fully decodes to 604 frames over 10.0667 s; originals and crop/trim metadata remain local. A six-position contact sheet shows map/pan/HUD and the return to katakana gameplay, with one unused black tile. No tint or speed change was applied. Dim Matrix values and small map-label/marker detail remain known limitations, and 60 CFR footage can contain duplicates.

The longer sixteen-worker Classic E1M1/intermission/E1M2 host regression matches all eight checkpoints: 1,747 tics in 51.3342 active seconds (52.3448 wall, including 1.0097 s asset handoff), with 3,037 completed frames / 59.16 updates per active second. Discovery averages 4.344 ms with 11.287 ms p95. Total active time still exceeds the 49.9143 s simulation schedule; maximum gameplay update is 1.013 s and maximum tic lateness 1.378 s around the broader workload. This remains a pacing limitation, not a fully qualified campaign or steady display rate.

`automap-numeric-validation.json` pins 294 source hashes, 88 standalone parses plus aggregate engine parse, 232 named foundation/route/menu checks, eight transport cases, five matching full-host reports and the actual Matrix recording. No owned game or recorder processes remain at audit. The first two numeric-only host reports use the previous codec; the audit explicitly distinguishes that from the final encoder measurements. Settings/audio and broader discovery/campaign/display qualification remain open. This checkpoint is progress toward the release.

The app still reports the persistent goal as `usageLimited` even though this user-triggered turn can execute work. Its tools expose completion/blocking but cannot resume a usage-limited goal. Official long-running-work documentation identifies Resume on the goal progress row as the user control; this was explained without trying another usage reset or altering the goal's completion status.

## 2026-09-11 — Persistent input settings

The previous goal turn made progress: numeric discovery/encoding was committed as `b71ca60` and verified against the private remote. This continuation starts from a clean checkout. Added a settings model separate from saved game state and recorded tic commands, with always-run and 50/100/150 percent keyboard turn speed. Shift reverses the run preference. Interactive sessions use a per-user JSON file; replay/scripted/headless tests use defaults unless given an explicit isolated settings path. Unknown versions/fields, wrong types, malformed or oversized files are rejected; failed reads use defaults and preserve the source file. Saves validate typed values, detect observed stale writers, publish a complete temporary file and clean up owned temporary files. This does not claim compare-and-swap protection against all concurrent filesystem races.

The settings screen is implemented with immediate input preference updates, reset defaults and back navigation. Persistence failures roll back the attempted preference and show a recoverable message. The initial isolated suite passes 46 checks covering storage, menus and synthetic command generation. Full-host, rendering and recorded interaction qualification are in progress. Audio controls will accompany the audio backend; graphics options remain launch parameters.

The first IPC-object conversion adjustment misclassified PowerShell's wrapped ordered dictionary and broke reads after the first successful write. `settings-unit-ipc.json` retains that failure. Restricting object conversion to non-dictionaries corrects it; `settings-unit-dictionary.json` passes 47 checks, including the serialized menu payload. The first actual host, already running the defective function, saves the first always-run toggle and rejects subsequent writes. Its schedule then remains in an error/menu path. The fixture omitted a wall deadline, so the observed owned simulation channel was explicitly signaled into host shutdown to preserve its report. `settings-host-first.json` is a failed run, not a compatibility pass; its final harness hash reflects edits made while it ran. The corrected fixture passes a 35-second wall limit for each replay and sends child stdout to the host display instead of mixing it into returned test data. The corrected full-host rerun is in progress.

The corrected full-host fixture passes all nine checks: five edits (including reset), persisted final always-run/150% preferences, a fresh host loading them, and malformed-file/save-failure recovery. Both gameplay/map checkpoints match on the successful edit route and on recovery. The 123-check menu suite renders 44 nonblank bounded screens. Ten native-record menu checks and sixteen save-menu regression checks pass. A Matrix recording confirms visible settings changes and return to map/gameplay; full-resolution review finds readable labels but retains the existing dim green palette. Classic/color-art recordings are in progress. These UI runs are not gameplay/display-rate benchmarks because static menu holds pause the active clock.

The settings audit preserves 297 source hashes, 91 successful standalone parses plus the aggregate engine parse, 205 accepted named checks, three headless host lifecycles and three recorded terminal runs. Classic/Matrix/AnsiArt viewing copies fully decode to 900/910/944 frames over 15.00/15.17/15.73 seconds. All three perform five successful persisted edits and preserve the 350-command/map stream and both checkpoints. Full-size settings samples and contact sheets confirm readable labels and gameplay return; Matrix remains dim. The Classic capture retains an early stale game image through several reported menu writes, then displays settings. The sampled video/host time origins differ, so this is a presentation/capture discrepancy to investigate, not a quantified latency claim. Preserve originals and this limitation. No owned game or recorder processes remain. Input settings are implemented; broader menu presentation/physical play, audio, rendering fidelity and campaign qualification keep the full release goal open.

## 2026-09-11 — PowerShell sound foundation and device queue

The preceding settings milestone was committed as `43311d2` and verified against the private remote. The full release goal is active; the user's reset notification requires no further credit action. This turn implements sound callback capture, validated DMX decoding, linear resampling, stereo gains, bounded voice replacement and saturating PCM mixing in PowerShell. Only Windows ABI declarations are compiled for device playback. The normal game host remains silent; this is an offline/device foundation, not completed audio integration.

The first mixer suite passes 21 checks. The initial real-route harness fails on a null legacy `ControlEvents.Count` access before opening the IWAD; `audio-replay-first.json` retains the failure. A null guard and ten-minute fixture bound correct the harness. The accepted 1,747-command E1M1/intermission/E1M2 route emits 75 events and matches all eight original checkpoints. Its 49.914286-second stereo PCM output has five maximum concurrent voices, sixteen clipped channel samples and 29 voice replacements. The first audible-data event is near 8.89 seconds. ffprobe confirms 44.1 kHz stereo signed 16-bit PCM; the WAD and derived WAV remain ignored locally. No game-window effect run occurred here, so no new screen recording is claimed.

The Windows waveOut experiment passes eleven checks: native ABI layout, hash-verified input, queued-buffer overwrite rejection, complete return of 352,937 frames including a 137-frame tail, pause/restart, idempotent cleanup and early reset with an outstanding buffer. Four 882-frame buffers give 80 ms nominal capacity. Playback of the segment beginning at nine seconds takes 8.229 wall seconds, including a 204 ms deliberate pause. Zero polls see all buffers empty while more input remains. This does not establish audibility, hardware underruns, latency or audio/video synchronization; it verifies the standard playback API lifecycle.

Initial real-route mix cost averages 11.088 ms with 21.963 ms p95 and 41.793 ms maximum per 28.571 ms block. Synthetic sustained 0/1/5/16-voice trials average 4.80/10.99/27.83/78.50 ms. Skipping silent blocks, caching bounds and using checked PowerShell numeric casts for ties-to-even PCM conversion reduces those means to 0.04/2.80/11.19/32.88 ms. All four synthetic PCM hashes are unchanged. An added independent fractional saturation/rounding check brings the suite to 22 passes. Every sixteen-voice block still exceeds its duration; renderer contention and music will need their own budget.

The optimized real replay retains the full WAV hash and all eight checkpoints. Mix cost averages 2.137 ms, p95 6.608 ms, maximum 12.271 ms; event processing averages 0.147 ms with a 20.634 ms maximum. These isolated measurements exclude renderer/device load. `docs/audio.md` declares the approximate panning/channel rules, unresolved source lifetime, missing randomized pitch/music, and next worker/host synchronization work. All release gates remain open.

The first evidence audit incorrectly compares serialized JSON property order between separate PowerShell processes and reports an event-stream mismatch. `audio-validation.json` preserves this harness failure. Canonicalizing each event's property names while preserving event order corrects the comparison; `audio-validation-canonical.json` passes 26 checks, including current accepted source hashes, seven standalone parses, all four synthetic PCM hashes and full-route WAV/event identity. The class-based sound adapter is exercised by the actual engine replay. The normal game remains unchanged by this foundation; live worker integration is the next audio step.

## 2026-09-11 — Audio worker and live host integration

The preceding audio foundation is committed and privately backed up as `a1c7f98`; this continuation starts clean and classifies the previous turn as progress. Added a dedicated PowerShell audio runspace, a bounded 32-packet queue, numeric event/gain packets and immutable decoded sample sharing. Game objects and class methods stay on the simulation thread. Emitter references expire conservatively after their longest pending sound plus two tics; a later sound gets a new identity if the old one has expired. No gameplay RNG is consumed.

The initial runspace/device fixture passes six lifecycle checks with a quiet generated tone: 105 packets over three seconds, a deliberate pause, an epoch reset, bounded queueing and clean shutdown. Seven old-epoch packets are explicitly discarded by reset, leaving 98 mixed packets. The packet-based offline E1M1/intermission/E1M2 route retains the full PCM SHA-256 and all eight checkpoints, with a peak of four retained sources. Event identity numbers can change after expiry; output identity is verified directly.

Added opt-in `-Sound` from launcher through simulation, with playback startup after silent engine warmup. Host-clock pause state has a dedicated shared-memory field; menu actions also pause the device. Map/new-game/load changes advance an audio epoch and reset queued old-world audio. Successful load explicitly resets the former sound implementation before assigning the reconstructed listener. Reports expose packet/mix timings, queue age at submission, polling starvation observations, stale packets, reset/cancel counts and cleanup. Music, volume settings, exact audible latency and wider campaign/audio fidelity remain incomplete. The first full sixteen-render-worker host qualification is in progress.

The first Classic headless host finishes all 1,747 tics and eight checkpoints in 50.887 active seconds, with 3,017 completed renders (59.29/sec). All 2,201,220 audio frames are submitted and returned completed. Mixing averages 3.141 ms with 31.580 ms maximum; packet construction averages 0.216 ms. Queue age at submission averages 91.843 ms and reaches 226.301 ms. Four queue-starvation observations precede the final packet; a fifth follows completion. Keep these latency/pacing limitations visible; none is direct hardware-underrun or acoustic-latency telemetry. The audio worker's longer wall duration includes renderer startup.

Code review finds a race where a future-epoch packet could be mistaken for an obsolete packet if control changes between worker loop checks. The corrected worker holds it until the shared epoch catches up; a deterministic early-publication fixture passes. Packet source expiry now advances only on active audio tics, preserving references through an encoded pause. Added six independent packet tests and submission-PCM digest telemetry. An explicit loading hold prevents snapshot publication from prematurely undoing the audio pause during asset handoff.

The corrected host plays the complete route with a one-second menu pause and a synthetic one-second 98-row resize pause. All eight checkpoints match; two audio pause transitions and one epoch reset are observed. All 1,747 packets/2,201,220 stereo frames are consumed/submitted/returned, with no stale or unconsumed packets. Submitted PCM SHA-256 exactly matches the offline WAV payload. The actual Matrix terminal recording with playback enabled is in progress; the recorder still uses `-an`, explicitly records `AudioCaptured=false`, and does not claim to capture playback sound.

The actual Matrix terminal recording completes the route with all eight checkpoints and the same submitted PCM hash. It records one menu pause and clean audio shutdown. The host reports 3,002 writes over 51.665 active seconds; that is not unique displayed FPS. The original 1472×1006 video has 5,129 encoded frames. The separately retained X=96/Y=120, 1280×800 crop fully decodes to 3,269 frames over 54.483 seconds, with unchanged timing/tint and no audio stream. Full-size and five populated contact-sheet samples show katakana gameplay/HUD; the sixth tile is unused, and dim scene values remain. `audio-live-recording.json` preserves media/export hashes and these limits.

The paced audio-enabled save-process fixture passes fourteen checks, including candidate failure isolation, new-game, exact loaded state, immutable save archives, three audio epoch resets and clean shutdown. It is short session-lifetime coverage, not combat-transition listening evidence. `audio-integration-validation.json` passes 27 checks, pins sixteen current source files, verifies fifteen standalone parses and compares full submitted PCM plus eight gameplay checkpoints for both corrected headless controls and the actual Matrix run. No owned game/recorder processes remain. Opt-in sound effects are implemented; music, volume, queue-delay improvement, acoustic timing/loopback capture and full campaign/fidelity qualification keep the release goal open.

## 2026-09-11 — Persistent sound volume and mute

The preceding live-audio milestone was committed as `735d6b0` and verified against the private remote. This continuation starts clean and classifies it as progress. Settings version two adds a 0–100 sound-effect volume and independent mute flag. Version-one files migrate in memory without being rewritten; the next successful edit saves version two. The menu expands to six choices, retaining input controls and adding volume/mute before reset/back. Invalid/stale file writes retain the prior behavior.

The first unit run passes sixty settings checks. Expanded menu rendering initially fails on the width of `SOUND VOLUME: 100%`; `sound-settings-menus.json` preserves this failure. The shorter `SOUND: 100%` label passes 125 menu checks and 46 fixtures. Effective gain reaches the mixer through a dedicated shared-memory field and is applied in PowerShell. A gain change clears queued PCM at the previous volume, which can cut a short tail; voice positions are retained so mute/unmute does not restart sounds. This is a declared buffer-boundary behavior, not zero acoustic latency.

An independent quiet-ramp fixture passes four actual runspace/device checks. Every submitted PCM byte matches a direct numerical vector for full volume, three muted blocks, and quarter volume; the unmuted segment resumes at the expected source position. Reports record volume changes, cancelled queued frames and muted packet counts. Integrated gameplay/persistence qualification is in progress. Music, loopback capture, queue latency and all wider release gates remain open.

The two-host sound settings fixture passes seven checks. Its full campaign route keeps all eight checkpoints while applying six effective-gain changes: 90/80/70 percent, mute, unmute at 70 percent, and mute again. All 1,747 packets are consumed; 1,164 are muted. The next process loads 70 percent/muted and starts muted. Gain changes cancel an upper bound of 10,080 queued frames in total, with 3,780 maximum per change. The worker's actual gain boundaries, replayed through the direct offline mixer, preserve every submitted PCM byte and all eight gameplay checkpoints. The WAV is a submitted-stream reconstruction, not captured acoustic/device-loopback output. A color-art terminal recording of the controls is in progress.

The audio-enabled settings regression passes eleven checks across three hosts: input edits/reset, process restart and malformed-file/save-failure recovery. Both replay runs preserve their two game/map checkpoints; sound gain remains at its defaults after reset and recovery, with clean device shutdown. The color-art recording completes all six sound edits and all eight campaign checkpoints. Full-size samples verify the six settings rows, 70% volume, mute Off/On, and gameplay. The original is retained; its 1280×800 viewing copy decodes to 3,668 frames over 61.133 seconds. It is silent video, not an audio capture. Recorder process QPC and encoded first-frame timestamps are not treated as interchangeable; sampled views are not a latency measurement.

`sound-settings-validation.json` passes 26 evidence checks and preserves fourteen source hashes, fourteen parses and 207 accepted named checks. The failed overwide first label remains in the ledger/results. No owned game or recorder processes remain. Persistent volume/mute are implemented and qualified within the declared submitted-PCM/device boundary; music, loopback recording, latency, physical play and the full campaign/fidelity/performance release gates remain open.

## 2026-09-11 — Music decoding, scheduling and instrument-bank foundation

The preceding settings milestone is privately backed up as `5ff4195`. The user corrected the handling of a usage-reset notification; no further reset was requested or redeemed in this continuation. The existing release goal is active, with no user decision blocking work. Resumed the unfinished music files in the requested project directory.

Added original PowerShell MUS decoding and absolute sample scheduling. The first unit fixture failed because `CopyTo` ran before the intended byte-array cast; the corrected fixture passed 23 checks. The initial IWAD inventory failed on comma/multiplication precedence in its independent expected vector. The next attempt reached a report serialization failure because event-kind dictionary keys were integers; this process error is preserved separately because the serializer could not write a report. String keys corrected it. All 32 IWAD music tracks then matched full independent tick-to-sample projections, and 36 retained map music references resolved.

Pinned Chocolate Doom source inspection caught a decoder compatibility difference: out-of-range program changes mask high bits, while valued controllers clamp. Corrected this and added independent normalization/end-flag cases, giving 25 passing MUS checks. Reran the whole IWAD inventory; every actual event hash remains identical. At 44.1 kHz, music ticks are exactly 315 frames. Loop tests at 22.05 kHz verify no accumulated rounded-cycle drift. These are event-timeline results, not synthesized sound.

Added a structural PowerShell SF2 reader and independent signed PCM/header fixtures. The first malformed-overflow test supplied hexadecimal `0xffffffff`, interpreted as signed `-1`, to an unsigned parameter; using `UInt32.MaxValue` fixes the harness. All 21 checks pass. The local TimGM bank parses: 136 presets, 210 instruments, 520 mono samples, 2,893,608 sample frames, and 455 explicit instrument modulators, excluding terminal records. All 52 observed melodic program headers exist; percussion headers also exist, but note/velocity-zone coverage is not yet verified. The bank's metadata lacks a copyright entry; retained upstream documentation attributes it to Tim Brechbill under GPLv2. Assets stay ignored, with independent provenance qualification still pending.

The bank's generator inventory exposes envelopes, looping, filters and modulation work still needed. The observed maximum of fifteen distinct depressed keys is not a voice limit or synthesis budget: release tails and layering can increase polyphony. The retained upstream compiled MeltySynth bridge is not adopted. `docs/music.md` records alternatives, implementation boundaries, exact asset/reference hashes, reproduction and next synthesis steps.

`music-foundation-validation.json` passes 28 evidence checks with seven current source hashes/parses and 46 accepted named format/timeline checks. No live visual/device test occurred, and no new recording is claimed. Normal host behavior remains effects-only with `-Sound`; music synthesis, score/session integration, acoustic capture and the broader release gates remain open. This is progress, not completion of the release goal.

## 2026-09-11 — Instrument regions, note coverage and oscillator cost

The preceding music foundation is committed and privately backed up as `a63198d`; this continuation starts clean and classifies it as progress. Implemented original PowerShell SoundFont region resolution with default/global/local precedence, key/velocity intersection, layers, effective sample/loop bounds, and retained explicit modulator overrides. Sixteen synthetic checks pass. All 2,063 regions in the local bank expand without an ignored zone. Every positive-velocity note-on in all 32 IWAD scores resolves: 71,681 events, 5,020 unique lookup combinations, 133 samples used. Some notes have six sample layers; this increases the synthesis budget beyond the previously observed depressed-key count. Modulator evaluation and release-tail polyphony remain work.

Added the PowerShell sample oscillator with linear interpolation, tuning, pause and continuous/sustain-release loops. The first fixture miscalculated a loop phase at output frame 99; corrected the expected value from 3,500 to 3,000 after direct phase calculation, leaving the implementation unchanged. Eleven final checks pass, including an independent piecewise waveform at a fractional source step.

The first cost trial overlapped the separate note-inventory process, so retained it and repeated after that process exited. The repeat uses ten warmup plus forty measured 1,260-frame blocks at 44.1 kHz. Means for 1/8/16 oscillators are 3.53/26.09/50.91 ms against a 28.571 ms block duration. All forty sixteen-voice blocks exceed the duration, before envelopes, filters or final mixing. No live music deadline claim is supported. A segmented-loop candidate preserves all output hashes but gives 3.42/24.98/54.02 ms means, without a consistent gain. Review also identifies a floating-point boundary guard needed for that candidate. Reverted to the simple per-sample boundary checks; candidate source and raw measurements remain local/results respectively.

These results change the next implementation decision: build complete PowerShell synthesis and investigate render-ahead/cache scheduling, measuring startup, invalidation, memory/storage and transitions, rather than assuming an unbuffered audio worker will absorb the music load. No rendering resolution, game tic rate, instrument layers or sample fidelity were reduced to hide the cost. The oscillator alone is not a completed music renderer.

`music-voice-validation.json` passes 34 evidence checks, pins seven current source files/parses and verifies 27 named region/oscillator checks plus full-score coverage. `docs/music.md` records the measurements and limitations. No live terminal or device test occurred; no recording is claimed. Music playback and the full Ultimate Doom release remain incomplete; the goal stays active.

## 2026-09-11 — First dry PowerShell music render

The preceding region/oscillator milestone is privately backed up as `3ca0207`; this continuation starts clean and classifies it as progress. Added original PowerShell controller/modulator math, volume/modulation envelopes, triangular LFOs, low-pass filtering, stereo mixing and note/pedal/session state. Controls run on a per-note 32-frame grid with interpolated gains and immediate channel-revision invalidation. Events are applied at scheduled sample positions. Reverb/chorus sends are evaluated but not mixed; this remains a dry offline renderer outside the normal host.

The first test fixture flattened a single modulator row; corrected the fixture. Further tests exposed a reserved-variable name in the impulse test and a bipolar-switch center edge case. Corrected these; 29 checks now pass, including independent envelope/controller/filter values, the actual filter impulse response, block partition identity, pedal release and pause. The layered-note voice-limit failure path still needs transactional admission before live integration.

The first eight seconds of E1M1 produce 352,800 stereo frames with 71 note-ons, nine peak voices, no clipped samples, peak PCM 7,107 and RMS 370.787 at volume 0.2. Rendering takes 14.756 seconds, excluding preparation and output file work. A separate compiled MeltySynth 2.4.1.0 reference uses the same score/bank/rate/volume and 32-frame dry setting. Its first segment also peaks at nine voices, with RMS 483.629. Direct PCM comparison gives a -2.308 dB relative level and 0.6914 zero-lag correlation. These are diagnostic differences, not a fidelity certification. Reference code/binary/license boundaries are explicit in `docs/music-synthesis.md`.

Started a finite 98-second PowerShell render covering the 96-second E1M1 score and two seconds beyond its loop boundary, plus a separate full compiled reference. Short independent unit/reference diagnostics overlap the long run, so its elapsed time is not an isolated performance trial. Both process handles are tracked until completion; no live terminal or device test has occurred. Full-loop findings will be appended after inspecting the actual outputs.

Both full renders complete. PowerShell emits 4,321,800 frames, processes 2,351 note-ons, peaks at 46 voices and records 108 exclusive-class cuts, without clipping. Its first eight seconds exactly preserve the original PCM; the post-loop window is nonzero with new note-ons. Rendering costs 664.386 seconds for 98 seconds of audio (0.148x real time), excluding preparation/output work but with the declared overlapping diagnostics. The compiled full reference peaks at 39 voices without clipping. These different models/voice lifetimes do not support an equal-fidelity speed ratio. The naive PowerShell cost is an unacceptable first-use experience to hide behind a cache; profile repeated controls and quiet tails before selecting a scheduling/cache policy.

Expanded lifetime/mute/reset/exclusive-layer tests bring the suite to 34 passes. `music-dry-validation.json` passes forty evidence checks, pins seven current source files/parses and verifies the full output, exact opening identity and post-loop continuation. Independent ffprobe results for all four WAVs are retained. No worker or reference process remains. Known pre-integration work includes transactional layered-note admission, the unused negative bipolar-switch center edge, filter/controller/reference fidelity, reverb/chorus, synthesis cost, cache/loop state, music host integration and acoustic capture. The full release goal remains active.

## 2026-09-11 — Music control caching, fused samples and safe note admission

Continued the existing release work after the user clarified that their usage reset was already applied. The goal tool reports the saved goal as paused; no reset was redeemed and no goal status was changed. User-controlled Resume restores automatic continuation; implementation continues in the current turn. The preceding dry renderer is privately backed up as `23e8ebb`.

Fixed the negative bipolar-switch center and staged complete layered notes before publishing cuts/voices/counters. Capacity rejection and an invalid later sample layer now preserve the existing note. Thirty-eight checks pass after those fixes. Added source-before-load hashes, source-drift reporting and optional timestamp profiling to the offline renderer.

The eight-second profile attributes about 6.803 seconds to controls, 4.278 to oscillator calls, 0.255 to the inner filter/mix loop and 1.890 to PCM conversion, out of 13.958 seconds overall. Caching note/channel constants reduces observed control time to 3.273 seconds and total to 10.765 seconds. Caching the PCM volume and typing locals produces no meaningful improvement (10.773 seconds). Fusing oscillator interpolation and filtering removes 50,129 calls/buffers and reduces the next observed total to 9.861 seconds. These are individual instrumented trials with different profiling boundaries for the fused section, not paired live-performance qualifications. Every entire eight-second WAV is byte-identical to the original.

Added thirteen focused oscillator comparisons/pause checks, bringing the synthesis suite to 51 passes. A PowerShell class-method PCM probe shows no consistent warm benefit and is not adopted; its rounded raw console output and source hash are retained. No compiled custom synthesis or reduced layer/tail fidelity was substituted. A finite uninstrumented 98-second render is in progress to check exact complete-score/loop identity before accepting the milestone. No live terminal or playback device test occurred.

The full optimized render completes in 380.828 seconds for 98 seconds of audio (0.257x real time). No other study synthesis/reference/test workload overlaps this run; documentation/read-only repository work and uncontrolled system activity remain. The prior 664.386-second run had declared overlapping diagnostics, so do not present a controlled speed ratio. The entire WAV is byte-identical to the original, SHA-256 `989CBD3C9E16782088EB4EF558477AC7A18602897D9390B1E148314B0D2FC530`, with all 4,321,800 frames, 2,351 notes, 46 peak voices, 108 exclusive cuts and the post-restart section preserved. Zero samples clip.

`music-optimization-validation.json` passes 60 evidence checks, including the 51 synthesis checks, every retained short-stage WAV, complete-score equality, current source hashes/parses and absence of render-time source edits. All finite render/probe processes have exited. The result is a preserved-model optimization, not reference-fidelity or live-audio qualification. More than six minutes of first-use rendering remains unsuitable as a default experience; continue numerical-kernel/control profiling and then bounded render-ahead/cache design, effects and host integration. No release-complete claim is made.

## 2026-09-12 — Remove per-sample method-dispatch overhead

The preceding optimization milestone is committed and privately backed up as `1ffcde9`; this goal continuation begins clean and classifies it as progress. A bounded numerical probe identifies standard static-method dispatch as a major cost in the current PowerShell runtime. Across three alternating-order trials, 200,000 floor calls take 329–338 ms versus 17–25 ms for round-to-integer followed by downward correction. The correction is valid for the synthesizer's nonnegative sample positions, bounded by the bank well below Int32 maximum. Finite checks take 373–375 ms versus 13–37 ms for comparisons with the finite double limits. The probe includes NaN, both infinities, finite extrema and subnormals; all results match.

Applied those two substitutions to the fused voice loop and final PCM conversion. Fifty-five tests pass, including actual rejection of nonfinite PCM and saturation/rounding of finite extrema/subnormals. The eight-second E1M1 profile drops from the previous 9.861-second observation to 4.396 seconds. Fused voice work drops from 4.101 to 0.592 seconds and PCM from 1.907 to 0.068 seconds; controls remain 3.123 seconds. The complete eight-second WAV hash is unchanged. Individual profiles are diagnostic, not controlled hardware-wide speed claims.

A separate Math.Pow dispatch experiment preserves every value but shows an ordinary .NET delegate is substantially slower than direct static calls (roughly 1,380–1,499 ms versus 178–190 ms for 100,000 calls); it is not adopted. A temporal envelope-endpoint cache also preserves the eight-second WAV but gives no measured improvement (4.697 seconds versus 4.396 seconds), so it is reverted. Its source remains local at `local/music-references/MusicSynth-envelope-endpoint-candidate.ps1`, SHA-256 `173B850C175C77BB049E26D4EB8C24EA0BEBC97892A7E5D57A37CB765EC55DF4`. Raw trials and candidate test/profile reports are retained.

The finite uninstrumented 98-second score/loop render is now running with only the successful numeric changes. Source edits and other synthesis/test workloads are held until it completes. No live terminal or playback device test occurred. Full results and exact-wave preservation will determine acceptance.

The full render completes in 143.484 seconds for 98 seconds of audio (0.683x real time), versus the preceding 380.828-second observation. No other study synthesis/test workload overlaps this run. The entire canonical WAV is byte-identical to all preceding full versions, SHA-256 `989CBD3C9E16782088EB4EF558477AC7A18602897D9390B1E148314B0D2FC530`, including 2,351 notes, 46 peak voices, 108 exclusive cuts and post-loop frames, with no clipping. `music-numeric-validation.json` passes 68 evidence checks including all 55 current synthesis checks, full/short waveform identity and current source hashes/parses. All owned finite processes have exited.

This makes a bounded parallel synthesis experiment reasonable, without yet proving live music deadlines. Next compare grouped serial versus PowerShell runspace rendering while preserving every MUS event boundary; quantify any changed floating-point accumulation order, startup/memory and sustained throughput before integration. The single-thread full score is still slower than playback. Audio effects/music integration, reference fidelity and broader release work remain unfinished; the goal stays active.

## 2026-09-12 — Bounded music groups and runspace lifecycle

The numeric optimization is privately backed up as `16256a6`; this continuation starts clean and classifies it as progress. Added experimental channel-group rendering, with the standard 1,260-frame subblocks and every original MUS event boundary retained in each group. Two-chunk blocking queues bound producer output, the bank and score are shared read-only, and each worker owns its channel/voice/timeline state. The normal host is unchanged.

The one-group serial opening is byte-identical to the original. Two groups with even/odd channel assignment also preserve the WAV, but place 67 of the first 71 notes on one worker. The first parallel run finishes synthesis but fails while reading an already-unwrapped result object's nonexistent BaseObject property; its report is retained. Removing that extra unwrap fixes reporting. The corrected two-group opening takes 7.727 seconds versus 5.913 seconds for the same groups serially; this assignment is not a useful speedup.

A deterministic greedy assignment based on whole-score note counts splits the opening into groups with 59 and 12 notes. Serial/parallel observed times are 5.602/4.556 seconds with identical WAVs. The full two-group run, however, still takes 140.587 seconds for 98 seconds of music. It preserves the entire original WAV byte for byte but exposes a large voice-lifetime imbalance: group peaks are 9 and 39. Its recorded unpaced schedule would require at least 43.074 seconds of startup delay to avoid late chunks retrospectively; this is not an actual device-underrun test. Full-process peak working set is about 316 MB, including the entire harness and prepared bank/engine definitions.

Fifteen synthetic and actual runspace checks pass: channel selection/ownership, manually scheduled event-boundary output, exact-double batching across loops, bounded-queue backpressure, cancellation while the producer is blocked, and propagation of a bad preset without a partial chunk. A finite four-group full-score experiment is running to separate the active channels. No device or live terminal run occurred, and no live-music deadline is claimed.

The four-channel-group run completes in 146.408 seconds, also byte-identical. It isolates percussion as the dominant channel with 34 peak voices; the remaining groups peak at 8, 7 and 2. Channel partitioning is insufficient for this fixture. An isolated state-access probe shows lower overhead for typed PowerShell fields than hashtable properties, but no runtime state representation is changed on that evidence alone.

Added complete-note partitioning as a second experimental policy. Every worker applies every note/controller/release event so foreign notes still trigger local exclusive/mono cuts; after full admission, only the selected worker retains the new note and all its layers. This duplicates note setup but divides sustained percussion voices. Nineteen group checks now pass, including cross-worker exclusive and mono cuts and layered-note ownership. Serial/parallel eight-second runs remain byte-identical. The full two-note-group run takes 113.354 seconds, with worker peaks 23/24 and 1,176/1,175 owned note-ons; the aggregate 108 exclusive cuts and complete WAV are preserved. Its retrospective minimum startup delay is still 16.109 seconds. A four-note-group full run is now measuring whether the balanced partition can cross playback speed. These experimental per-worker voice caps do not yet enforce a shared global admission cap for arbitrary scores; the tested stock fixture remains well below 256 total voices.

Four note groups complete the 98-second fixture in 102.723 seconds, preserving the entire original WAV. Their peak voices are 12/12/13/13, so the note policy corrects the percussion imbalance. Parent merge/PCM work costs 14.337 seconds, overlapping producers. Moving only the addition loop into a small PowerShell function yields 0.206 seconds of merge/PCM on the short run versus 2.033 for a same-source inline control. The full function-merge run takes 98.512 seconds, with 2.003 seconds of merge/PCM, 0.106-second initialization and first chunk at 0.610 seconds. It remains byte-identical. The retrospective startup requirement is 3.043 seconds; peak whole-process working set is 329,515,008 bytes. The function change improves that loop without claiming a specific compiler mechanism from timing alone.

`music-group-validation.json` passes 164 evidence checks covering nineteen group/lifecycle checks, all successful short/full WAVs, aggregate notes/cuts, exact sample comparisons, chunk sequences, fixture voice bounds and current source hashes/parses. The original reporting failure remains preserved. All finite experiment/test pipelines have completed and their owned queues/pools are disposed. No terminal/device playback was run. The best pipeline is near playback speed but lacks demonstrated gameplay headroom; next investigate the remaining state/control overhead and qualify a paced bounded consumer before host integration. The full release remains incomplete and the goal stays active.

## 2026-09-12 — State representation probes and paced music consumption

The bounded-worker milestone is privately backed up as `faf0170`; this continuation starts clean and classifies it as progress. Tested data-only classes declared in PowerShell for voice and envelope state. Both typed-state suites pass all 55 synthesis checks, and typed voice, combined voice/envelope, envelope-only and restored baseline opening WAVs are byte-identical. Their individual instrumented times are 5.747, 5.415, 5.722 and 6.452 seconds, respectively. The fresh baseline is also substantially slower than the older 4.396-second observation, so these runs do not establish a reliable state-representation winner or a cause for the variability. The small state-access benchmark does not justify adopting this change. Both runtime files are restored to the existing hashtable representation.

Candidate files remain local: `MusicSynth-typed-voice.ps1` SHA-256 `72D0FA052B757D1AA60A56B1F858E0C4B97D7835C4AC771A96163038B439F97C`, and `MusicControls-typed-envelope.ps1` SHA-256 `9070374376D2F4C660267FA05E6FC9393ECFC7786E7CEF96E30B95F51985F7F6`, under `local/music-references`. All raw tests/profiles are retained. Git's restore normalizes working-file line endings; new reports pin the exact restored bytes rather than relabeling old hashes as current.

Added a paced-consumer option to the group experiment. It pre-fills an explicit audio-frame capacity, establishes a monotonic virtual playback clock, waits for capacity before accepting further mixed chunks, and records lateness against each chunk's start deadline. The producer queues remain bounded. A separate complete PCM archive is retained for exact output comparison; no device is played or drained. The current finite 98-second test uses four note workers, function merging and eight 25,200-frame chunks of capacity (4.571 seconds of audio). It will measure actual backpressure and virtual deadlines rather than infer success from the unpaced average.

The user clarified that their usage reset was already applied and requested continued goal work. No reset credit was redeemed during this continuation; the full release goal was verified active. The four-worker experiment completed with the exact canonical full WAV but 38 late chunks, maximum lateness 2,021.414 ms. Prefill took 2.756 seconds, production 99.888 seconds, consumer waits 10.425 seconds; ready-audio capacity never exceeded 201,600 frames. The first miss is at audio time 59.429 seconds. This is failed virtual deadline qualification despite correct output.

A finite same-capacity eight-worker experiment likewise preserved every sample but performed worse in this observation: 118 late chunks, maximum 10,320.270 ms, first miss at audio time 30.857 seconds. Prefill took 2.735 seconds, production 108.845 seconds, consumer waits 11.010 seconds. Peak process memory was 376,602,624 bytes versus four workers' 334,430,208. No other study synthesis/test workload overlapped either full render; documentation/read-only work and ordinary system activity were uncontrolled. Do not generalize a universal worker-count optimum from these sequential runs.

Added an independent retained-evidence audit: the four/eight reports pass 543/547 integrity checks respectively, both explicitly `MeetsVirtualDeadlines=false`. It re-derives deadlines, chunk continuity and the ready-audio bound, verifies source and asset identity, whole WAV hashes on disk, notes/cuts and fixture voice bounds. All nineteen group/lifecycle checks pass again on the current sources. Sources remained unchanged during both renders. No live terminal or audio device ran, and all owned finite pipelines exited. Next implement bounded cache/render-ahead semantics with explicit first-use cost, versioned input identity, partial-file recovery and loop-tail state; more workers have not qualified this pipeline for gameplay. Music integration and the broader release remain open; the goal stays active.

## 2026-09-12 — Exact finite music cache

The paced-deadline milestone is privately backed up as `ea2d8bf`; this continuation starts clean and classifies it as progress. Implemented float64 stereo chunk storage before master volume/saturation, an ordered source/bank/score/runtime identity, exclusive writer handles, flushed payload publication followed by atomic manifest replacement, and exact checksum validation on read. A bounded reader retains one chunk plus its requested output, supports pause without advancing time, and throws explicitly at prefix exhaustion. It does not repeat the opening WAV at score end.

Twenty-two synthetic checks pass, including reader boundaries, pause/resume, unchanged frame on exhaustion/corruption, writer exclusion, partial/orphan recovery, snapshot isolation and malformed identifiers. The first eight-second build stores fourteen chunks (5,644,800 bytes). Build time is 5.393 seconds after 0.351-second identity preparation; reading/PCM conversion/hash takes 0.095 seconds, with a maximum observed block cost of 19.017 ms. Every PCM byte matches the original reference. These are unpaced offline costs, not device or gameplay measurements.

Started a finite 172-chunk extension beyond E1M1's first score restart. It reconstructs synthesis from the beginning, verifies all fourteen existing chunks before appending, and preserves the continuous synthesizer's loop-tail and controller state. Replaying the prefix is a deliberate first recovery implementation; state checkpoints and indefinitely repeatable loop qualification remain open. The normal game host still uses sound effects only.

The extension completes in 148.463 seconds after 0.396-second identity/setup preparation, storing 4,334,400 frames (98.286 seconds) in 69,350,400 payload bytes. It verifies all fourteen opening chunks before adding 158 more. Reading/PCM conversion/hash of the entire 98-second reference takes 1.059 seconds; the raw PCM hash is exactly `E5C7539145FD3005C0BEBF10EF96C7EA5851231B73AD97C65536CE62AC02F03B`, including post-restart frames. The extra stored 0.286 seconds has no independent reference comparison here. No other synthesis/test workload overlaps the build.

A fresh-process warm run reuses the same key and all 172 chunks without synthesis replay. Its identity/setup preparation takes 0.422 seconds, excluding earlier script/engine loading; the empty build branch is 0.000009 seconds. Complete cached reading/PCM/hash takes 1.354 seconds and remains exact, but its maximum block cost is 37.240 ms, longer than a 28.571 ms audio block. Retain this spike: aggregate speed is not a playback guarantee and a prefetch buffer still needs qualification. The extension-run maximum is 19.948 ms. Ordinary system activity remains uncontrolled.

`music-cache-validation.json` passes 391 checks against the current sources, the 22 synthetic storage checks, cold/extension/warm identities, complete reference PCM digests and all 172 published payload hashes/sizes. The source files remain unchanged during the measured builds; all owned finite processes exited and writer handles closed. No device/terminal test occurred. Next qualify repeatable synthesis state at cycle boundaries for indefinite cached music, then integrate prefetched cached samples with the effects worker and session controls. Cache prefix exhaustion currently fails explicitly; the full release is not complete and the goal stays active.

## 2026-09-12 — Music loop state and reusable playback

The finite-cache milestone is privately backed up as `220c844`; this continuation starts clean and classifies it as progress. Added a bit-preserving state fingerprint for the inspected single-group dry synthesizer. It retains all voice/channel state, normalizes clock/cycle translation and relative note/revision counters, excludes explicitly reviewed diagnostics, and rejects unsupported top-level state or scheduling modes. Twenty-three synthetic checks pass, including recurring live release tails, complete repeated float output, bit-sensitive oscillator/filter/control fields, controller invalidation and unchanged live state after fingerprinting.

Started three continuous E1M1 periods (288 seconds), storing complete float output and comparing the canonical first-98-second PCM. The first two boundaries retain 35 live voices and have the same normalized state hash, `0E6D546145CACE2EE20EB43451881B30F63351CF50F8B1CFEAEF33463C1F88AB`. The third period is still running to verify the predicted entire next waveform and another state boundary. No loop success is inferred from a short seam.

Implemented a reader for locally trusted successful qualification reports, with full payload/source checks, read-locked playback files, one bounded decoded page, integer intro/loop mapping, pause and cleanup. Added an optional unquantized music layer to the existing effects mixer so combined samples undergo one PCM conversion; the effects-only API remains compatible. Reader and mixing tests are prepared and will run after the long synthesis workload. The host is not yet connected to music.

The three-period E1M1 run completes in 432.134 seconds, including file writes, state snapshots and canonical-prefix PCM conversion but excluding initial asset preparation. The third boundary matches the prior two exactly, with 35 live voices. Entire second/third float files are byte-identical, SHA-256 `4C068351C46CD40E5FF90DE7B79680C0C5CDA91F4BF59F0AB1947B10F7F12A86`; the first is different (`B2B9EF7E205C89DC3391F7C7D0DD8F5A7BFC354BC1CA1D119EBD4246778F033B`). Each period is 67,737,600 bytes. The original first-98-second PCM also remains exact. This qualifies a reusable second period for the pinned dry model under the documented clock/counter normalizations, not for arbitrary other engines or music assets.

Fifteen loop-reader, nine combined-mixer, twenty-two existing effects and four volume checks pass after the long synthesis process exits. The 23-check real evidence audit reads four periods and matches every float byte against the intro and qualified period, including the independently synthesized third. Its first 98 seconds also pass through the combined effects mixer with the exact original PCM hash `E5C7539145FD3005C0BEBF10EF96C7EA5851231B73AD97C65536CE62AC02F03B`. The fourth period is derived from state recurrence, not claimed as independently synthesized evidence.

The four-period read/hash plus first-98-second PCM audit takes 2.737 seconds, excluding startup verification, but records a maximum 50.112 ms block cost. Preserve the spike; playback prefetch and real device/load qualification still matter. All owned finite processes exited and file handles closed. No live terminal/device test ran. Next integrate qualified music with the persistent audio worker and session events, qualify other required tracks and one-shot opening behavior, then record audiovisual playback with the existing game route. The full release remains unfinished and the goal stays active.

## 2026-09-12 — Persistent music and host integration

The reusable-loop milestone is privately backed up as `0927db3`; this continuation starts clean and classifies it as progress. Added persistent qualified-track ownership to the audio worker and atomic start/stop/gain packet handling, with epoch resets, master mute and pause coordinated with effects. Thirteen catalog/lifecycle checks and ten actual device-worker checks pass. The complete four-second submitted PCM matches an independently scheduled offline fixture across the real loop boundary, effect overlay, pauses, gain, mute, future epoch, stop and restart. All 140 packets/176,400 frames are accounted for, and music advances 161,280 frames including its muted interval. The effects-only runspace's six checks also pass.

Added engine IMusic callbacks and explicit catalog/IWAD score matching. Two adapter tests fail because a `Volume` backing property routes calls through its generated accessor instead of the intended method; a debug probe observes volume -5 with no events. A first arithmetic-order correction alone does not resolve this dispatch problem. Renaming the backing field to `StoredVolume` fixes it; eleven adapter/catalog tests pass. Both failures are retained. Successful Ultimate Doom save loads synchronize the score for the restored state/stage; one-shot opening music and Doom II finale restoration remain open.

The first six-second headless Matrix host run succeeds with actual music/effects playback and concurrent render workers. The final simulation consumes 209 tics/packets and returns every one of 263,340 submitted frames; the host's preceding snapshot reports 206 tics. Maximum mix block is 54.041 ms. Its one starvation poll is after packet 208, the final packet, during shutdown; this is not hardware telemetry or an acoustic test. Fifteen save-worker checks pass with E1M1 music and same-episode new game, preserving numeric state, failed-candidate isolation, backups/replay archives, three epoch resets and clean music/device closure.

The initial visible-recording attempt stops before launch because the old recorder requires no existing Terminal process. An unrelated Terminal is present, so it is left untouched. Replaced that restriction with enumeration of visible Terminal window handles before launch, selecting only a newly created `pwshDoom` window afterward. The helper contains Windows ABI declarations only; selection remains PowerShell. A finite eight-second actual Matrix recording is now running with music enabled. Its video path still captures no audio and must remain labeled silent footage.

The visible run completes with 279 simulation/audio packets, all 351,540 submitted frames returned, one initial music callback and clean music/device shutdown. It records a maximum 35.086 ms mix block; its only starvation poll is after the final packet. The host completes 480 writes, not independently measured unique displayed frames. Capture metadata confirms one preexisting Terminal window and a newly selected game handle; after game shutdown the original Terminal remains.

The original 1472×1006 video has 2,266 frames and a 37.766-second container duration including startup; SHA-256 is `69E7B38F716745547A737721633482DAE1E8F4CE3BDCB4E6E84BD66983C378DC`. It fully decodes. An extracted actual gameplay frame shows the katakana scene and HUD inside the expected game window, with the known dark-green presentation; a sampled frame does not certify all footage. A six-second/360-frame viewing copy at the same size also fully decodes. Both are explicitly silent video. `music-live-recording.json` preserves paths, hashes and extraction timing, with original media retained under ignored `local/recordings`.

The effects-only volume test passes all four checks on the expanded worker. `music-integration-validation-final.json` passes 51 evidence checks spanning current catalog/callback/worker sources, independent submitted-PCM controls, save/new-game behavior, headless and visible host accounting, media hashes and newly selected window ownership. All owned study pipelines exited and readers/devices closed. Next prepare/qualify the other required scores, add one-shot opening behavior and acoustic loopback capture, then run the complete intermission/map route with music. The full release goal remains active and unfinished.

## 2026-09-12 — Longer soundtrack qualification and scoped audio capture

The host-music milestone is privately backed up as `03e20b2`. The full release goal remains active. The user has already applied their usage reset; no additional reset is requested or redeemed. Continuation needs no further user instruction.

The fixed 300-second synthesis bound excluded stock scores once their lengths were aligned to the 1,260-frame scheduling grid and three complete periods. Expanded the finite synthesis horizon to 3,600 seconds and the reader period limit to 1,200 seconds. This changes bounds, not synthesis algorithms or page memory. Twenty-two group tests, twenty-three loop-state tests and fifteen reader tests pass, including exact final-frame bounds without allocating an hour of samples. Historical receipts remain preserved; their source identities intentionally do not qualify the modified source.

Independent eight-second original-renderer references for E1M2 and intermission are retained. Three finite continuous renders are running: E1M1 requalification (288 seconds of audio), E1M2 (1,864.371 seconds) and intermission (2,416.371 seconds). They run concurrently for correctness, so overlapping wall times are not performance benchmarks. E1M1's first two boundaries retain the historical matching state fingerprint. No success is inferred before complete output/state/reference checks finish.

While these renders run with pinned synthesis source files, investigate Windows process-specific audio loopback for audiovisual recordings. The existing footage remains silent; submitted or returned waveOut buffers do not establish acoustic output. Target the owned simulation process and its audio runspace, preserving unrelated application audio and Terminal windows.

E1M1 requalification completes successfully. All three float period hashes, the recurring 35-voice state and the original 98-second PCM match the previous run exactly; no source drift occurs. Its 441.085-second elapsed time overlaps other renders and is not a performance comparison. Updated the local playback catalog to the new qualification only after this success. Playback, event/catalog and actual device-worker tests pass 13, 11 and 10 checks respectively. Tests now accept a qualification parameter, and the catalog unit test writes a separate test file instead of replacing the user's playback catalog.

The first updated loop-evidence audit fails on the historical state-unit source hash, correctly exposing a stale receipt. Preserved that failure as `music-loop-evidence-hour-bound.json`; explicit current state/reader report parameters resolve the selection. The new audit passes all 23 checks, including complete four-period float data and canonical PCM. Its maximum observed block cost is 48.433 ms, still longer than an audio block; no playback deadline guarantee is inferred.

Implemented process-tree WASAPI recording instrumentation using original PowerShell packet/WAV logic plus explicitly identified compiled COM declarations, forwarding and the asynchronous activation callback. Windows build 26200 opens/closes it successfully. The ten-check two-sibling fixture then passes: selected 350 Hz amplitude 999.806 PCM units, concurrent sibling 700 Hz amplitude 0.001015, and selected-silence RMS 0.480 while the sibling continues. Both source devices return all 264,600 frames and close. No capture discontinuity/timestamp-error flags occur. This is digital scope evidence, not acoustic measurement or synchronized game video. Raw audio and complete packet metadata are retained. No visible game/effect test ran in this continuation.

E1M2 and intermission finite renders remain active with their pinned synthesis files unchanged. Last observed progress: E1M2 731.17/1,864.371 audio seconds, including its first complete aligned period with 14 voices and state F80B55073C21202481E89236461DCA33FDB0E3398F24FAC9B1B3D8AD4BADDB66; intermission 514.29/2,416.371 seconds. Continue those same jobs; do not restart on an observation timeout. Next connect scoped capture with the simulation readiness handshake, verify audio/video timestamps, and qualify the full E1M1/intermission/E1M2 route with music after both soundtrack jobs succeed. The release goal remains active.

The final timing audit finds a limitation that the scope fixture did not claim to test: all 698 device positions are zero, and packet QPC has excess intervals of 10 ms and 25.188 ms at packets 1 and 609 despite no API error flags. The initial continuity assertion fails and remains recorded in `music-capture-milestone-validation.json`. Cause is unclassified. The updated evidence audit separates sample/file/scope integrity from timing qualification, retains both gaps, and explicitly sets `ContinuousTimelineQualified=false`. It passes 64 integrity checks in `music-capture-milestone-integrity.json`. Accurate synchronized movie capture still requires clock/timeline handling; no silent concatenation is presented as that solution.

## 2026-09-12 — Audio/video clock integration

The prior longer-score/capture milestone is privately backed up as `fc55d3d` and is classified as progress. The current worktree starts clean. Both long soundtrack jobs are confirmed live and continue on their existing handles. Work now addresses capture clock alignment: the inspected FFmpeg 9.0.1 gfxcapture source subtracts its first Windows Graphics Capture timestamp, hiding the absolute origin. The existing GDI alternative stamps frames using av_gettime before BitBlt and exposes a microsecond time base. Investigate that route with explicit QPC/wall-clock anchors and retained packet-gap placement; no clock success is assumed from API descriptions or absent error flags.

Implemented recorder-only UTC/QPC anchors and explicit PCM timestamp placement. Thirteen synthetic checks pass, including actual stereo WAV bytes around a two-frame clock gap, boundary trimming, documented one-sample jitter tolerance, larger-overlap rejection, timestamp-error rejection and exact epoch conversion. A fresh live two-sibling audio capture still passes ten scope checks with periodic clock anchors. Its observed offset spread is 0.0006 ms, maximum sampling bracket 0.0297 ms, and maximum ordinary-versus-precise wall-clock difference 0.7519 ms; these exclude video-copy latency and are not physical sync measurements.

Added an optional game startup gate before simulation timing begins. The recorder first starts video, obtains the owned simulation PID, opens scoped audio capture, and only then releases the first-tic gate. Its finite timeout allows normal host cleanup if capture cannot start. The new audiovisual path uses GDI's original packet clock, preserves the silent/raw inputs, and will produce a separate timestamp-placed WAV and AAC/H.264 viewing movie. An actual eight-second Matrix run with E1M1 music and effects is now being recorded; its result remains unproven until it exits and the retained media and clocks are inspected.

The GDI run completes 279 game/audio packets and returns all 351,540 submitted frames, but visual review rejects it: the entire 42.8-second captured window is black. Both an extracted frame and FFmpeg blackdetect confirm the failure. No audiovisual gameplay success is claimed. The initial mux also loses four final video frames with `-shortest`; removing it preserves all 2,569 compressed frames byte-for-byte, while the MP4 duration changes by ten 1/15,360-second ticks. A stricter container-duration assertion rejects that difference; subsequent validation will distinguish actual frame timestamps/bytes from container final-duration metadata. All versions remain retained under local recordings.

Returning to Windows Graphics Capture. The existing Visual Studio 18 C++ toolchain and Windows SDK are available. Built GNU Make 4.4.1 locally and downloaded pinned FFmpeg 9.0.1 plus NVIDIA codec headers after inspecting licenses. An attempted MSI administrative extraction for pkgconf was rejected by tool policy before execution; instead extracted a hash-verified portable PyPI wheel, with no installer or system PATH changes. A minimal external FFmpeg build is now running. Its sole capture-source change logs the original first WGC QPC timestamp before upstream normalization; no capture/render algorithm is replaced, and no compiled code enters the game. This build remains an experiment until compilation and actual capture succeed.

E1M2 continuous qualification passes: 1,864.371 seconds synthesized over twelve original score cycles, with four cycles per aligned period. Its recurrent boundaries retain 14 voices and state F80B55073C21202481E89236461DCA33FDB0E3398F24FAC9B1B3D8AD4BADDB66. The complete second/third float files match SHA-256 89F9FA1444D4ACF67F427426404431C06C8086D24FBE55BAECEB4B81B0C9FEF7, each 438,500,160 bytes. The independent opening eight-second PCM matches exactly, and no source drift occurs. Elapsed 2,290.433 seconds overlaps other work and is not a performance comparison. A separate two-map local catalog is prepared; intermission remains required before the full route can use music.

The minimal FFmpeg build succeeds after resolving a native GNU Make/Git Bash quoting failure in generated dependency-scanning commands. The original inline AWK expression is moved into a file without changing its dependency extraction logic; the failed build logs are retained. The source capture change only emits PWSHDOOM_GFX_ORIGIN_QPC100NS once, before the original first-frame subtraction. The corrected recorder now uses this same QPC domain directly, while standard unmodified FFmpeg performs media validation/muxing. An actual eight-second Matrix WGC/audio run is in progress. The GDI black-video fixture is now automatically rejected before muxing.

The first WGC run captures the actual Matrix scene and all expected game/audio packets. Post-processing initially fails because an empty black-interval list has no Sum property under strict mode; the raw movie/audio remain intact. The empty-list case is fixed and the retained inputs merge successfully. The recovered Matrix movie keeps all 2,373 compressed video frames and every PTS/DTS; only container final-duration metadata may normalize. Its original WGC timestamp is 879695319333 in 100 ns QPC units, directly shared with WASAPI. The 1,121 zero-filled postgame frames are explicitly recorded, along with startup padding; no timestamp adjustments occur.

Color-art and Classic then complete the full recorded pipeline successfully on current capture sources. Each consumes 279 simulation/audio packets, returns all 351,540 submitted frames and closes its device. Matrix/color/Classic complete 432/389/410 console writes in their eight-second game intervals, respectively; these instrumented observations overlap the intermission synthesis job and are not clean display-rate benchmarks. Their only audio starvation observations occur after final packet 278 at shutdown. Inspected extracted frames show the katakana scene, color-art scene and Classic scene/HUD in the owned Terminal windows. The Classic capture is 2912 by 1452 and includes substantial viewport margins; it does not qualify 1080p sizing. Six-second audiovisual viewing copies preserve the full window; original captures and all failed exports remain local.

The checked-in diagnostic recorder recipe also succeeds from a fresh FFmpeg source tree in 118.610 seconds. Its patched capture-source hash matches the actual recording build; binary hashes differ, so bit-reproducible compilation is not claimed. The recipe build itself is not substituted for the binary that produced the movies.

The independent audiovisual evidence audit first fails on a test-code decimal literal parsed as property access. That failed report remains. Correcting the literal and making array concatenation explicit produces 88 passing checks: current targeted sources, owned process/window selection, original QPC origin, complete independently reconstructed timestamp-placed PCM, no zero-filled gaps inside the observed gameplay interval, unchanged media hashes and full movie/clip decode. Portable raw reports are copied byte-for-byte into results/av-*.json; WADs, audio, video and tools remain local. Detailed clock/build/failure/reproduction documentation is now in docs/audiovisual-recording.md. This milestone remains progress toward the active release goal.

All eleven new/modified PowerShell sources parse. A separate four-second headless run without any capture gate exits normally with 139 simulation tics, confirming that ordinary startup still proceeds after readiness publication moves. This single-renderer overlapping workload is a startup regression check, not a performance trial. The remaining intermission render continues on its original process handle with synthesis sources unchanged.
The nongated headless prefix matches its one available replay checkpoint and closes audio without error. It submits 175,140 frames and returns 171,360 as completed; the 3,780-frame queued tail is not counted as played. This startup regression does not inherit the all-frames-returned result of the three audiovisual runs.

## 2026-09-12 — Resumable music preparation and campaign music route

The previous goal turn is progress: audiovisual milestone 9a05153714935e91055c73d5fd2e34305ad012ed is confirmed on the private remote, and this continuation starts clean. The original intermission job is confirmed live and continues; its synthesis source files remain pinned. No observation timeout causes a restart.

Added Prepare-DoomMusic.ps1 to replace manual per-track reference/qualification/catalog steps. It checks requested IWAD lumps before rendering, verifies supplied or resumed tracks through the real source/runtime/payload reader plus bank identity, serializes owners with an exclusive file handle, and publishes a fresh catalog atomically only when every requested track succeeds. Successful newly prepared track receipts survive an interrupted batch. Initial parsing caught an unbraced variable before a colon; the corrected script then verifies both existing E1M1/E1M2 payloads. Seven separate child-process control checks pass for real reuse/resume, overwrite protection, absent lump, changed bank, live lock exclusion and stale-lock recovery. These controls do not claim the new-synthesis path works.

Started a finite E1M3 preparation through that new-synthesis path. It runs the original dry opening renderer followed by continuous three-period qualification, with existing musical algorithms unchanged. E1M3 and the already-running intermission job overlap for correctness; wall times are not paired performance measurements. The next live route will use the existing eight-checkpoint E1M1/intermission/E1M2 replay after intermission fully qualifies.

Intermission completes successfully on the original process: 106,561,980 frames / 2,416.371 seconds synthesized continuously. Every aligned boundary has ten voices and normalized state 82C3B623331343525501F216ECEA726CFD33BB65D896C1B0EE1BA1266E97A9B9. Second/third files are each 568,330,560 bytes with SHA CC8D23E90098758FC3FE22C22275B89504303A55ECF07FF307321CF1BFF2BE73. Original opening PCM remains exactly 3E5C985530423907A1DDA1D839F08B7B79ECBF0648C226D4072CC4AE9498EFCA; no source drift. The 4,505.390-second elapsed duration overlaps multiple jobs and recordings, not a performance comparison. Six actual long-reader checks pass. The preparation command then verifies E1M1, INTER and E1M2 and publishes local/music-prepared-session.json. An actual Matrix audiovisual session using the full 1,747-command/eight-checkpoint replay is now running. E1M3 preparation remains separately active.

The first full Matrix music route completes all 1,747 commands and matches all eight legacy checkpoints. All 2,201,220 submitted audio frames return. The first audit incorrectly expects only three events and intermission music on the entry tick; its failed receipt is retained. Source inspection confirms Intermission.Update starts its score at bgCount=1, the tick after entry, while Publish-SimulationMapChange resets the audio epoch before the new-map score is consumed. The corrected audit explicitly verifies three starts plus that reset, with frame positions 0, 1,965,600 and 2,110,500; all 34 checks pass. The original pre-run auditor hash/failure remain retained, and the corrected auditor is hashed separately from runtime code.

This route exposes three pre-shutdown queue-starvation observations (after packets 310, 1674 and 1677), a 39.643 ms maximum mix block and 234.945 ms maximum submission age. The 3,027 writes over 52.107 wall seconds, including a 1.011-second asset handoff, do not qualify 60 displayed frames/sec. E1M3 synthesis overlaps the recording. Functional music transitions pass; continuous audio/performance qualification remains open.

Visual review of the actual intermission and E1M2 footage confirms a usability defect: intermission labels are rendered as katakana and are unreadable. Route intermission/finale screen jobs through the existing block-based menu encoder, preserving the 160x50 character-mode viewport and gameplay's katakana encoding. This is an intentional presentation change, to be re-recorded and checked. The character-codec check passes 144 partitions, four style/alphabet full-frame cases, eight independent probes, six guards and ten viewport cases. Its old harness accepts -Report rather than -Output: the initial invocation touched its default tracked report; the new result was moved to results/character-codec-session-ui.json and the historical report restored exactly from HEAD. No historical result change is retained.

The intermission/finale block path passes the existing 125 menu checks and 46 screen fixtures. Matrix and AnsiArt each pass the actual seven-worker screen/menu/automap/map-reload fixture: 256,000 pixels and 28 strips compared, persistent workers preserved. Revised full audiovisual Matrix and color-art routes both complete all 1,747 commands, match eight checkpoints and return all 2,201,220 submitted audio frames. Their route audits pass 36 checks each. Sampled revised Matrix/AnsiArt intermission frames show recognizable labels; E1M2 remains katakana gameplay. Matrix retains lower contrast and downsampling remains visible. Original unreadable footage and all revised full-window movies remain local; hashes, full portable game/audio/capture/merge receipts and real-time viewing-copy timings are retained.

The revised Matrix/color runs respectively record four/four pre-shutdown starvation observations, at packets 313, 316, 1674 and 1684 in both. Maximum mix blocks are 78.929/69.278 ms; maximum submission ages are 320.166/293.072 ms. They complete 3,009/2,970 writes over 52.313/52.527 wall seconds. E1M3 preparation overlaps both. No clean paired timing or acoustic-continuity conclusion follows from the UI improvement. A subsequent isolated route should separate preparation contention from repeatable queue/tic timing stalls before changing the playback buffers or scheduler.

The new E1M3 preparation path completes end to end and publishes its catalog after successful real-reader verification. Its three 272-second periods retain 31-voice state 666EDE7B8AE847BFE081843E6CF22A5750FA5B03B288F82DC782F0958EC6E5DE. Second/third payloads each have 191,923,200 bytes and SHA 2023A8A7F910D93391EAE82EC706443B62F8C007EDED22E0403728275E473D00; the original opening PCM remains exact. No source drift. A separate reader test passes six checks, and byte-identical reference/qualification receipts are preserved in results. The 1,152.693-second continuous render overlaps recordings. All synthesis and recording processes from this continuation have now completed; no live job is being inferred from a leftover lock file.
The preparation command also publishes a verified four-track catalog (E1M1, INTER, E1M2, E1M3) in 19.844 seconds including asset/source/full-payload validation and bundle loading. A finite headless launch is checking the existing startup deadline with that larger catalog; a successful warmed run would not qualify cold-cache startup for a complete soundtrack. All PIDs from the three completed recorded sessions are absent.
The four-track headless host succeeds under the existing startup deadline: 139 commands, the one available checkpoint matched, and normal device/reader closure. Its queued tail is reported separately from completed frames. Six new/modified source files parse, and current preparation/reader source identities match the retained successful reports. The milestone remains progress; next run the existing music route with no synthesis/build/test contention to investigate repeatable early-game and map-handoff starvation, then continue soundtrack/campaign/fidelity work.

## 2026-09-12 — Isolated audio route and buffer recovery

Previous turn is progress, privately backed up at 6221faab0e10b74f8c4403a0187169341dc7cfd8; this worktree starts clean. The first process preflight matches its own inspection command and rejects before launching anything. Restricting detection to direct -File study launches and excluding the inspector resolves the false positive. The isolated Matrix route runs without another study synthesis/build/test workload; ordinary system activity, recording and source inspection remain uncontrolled.

All 1,747 commands/eight checkpoints match, and every submitted audio frame returns. Unlike the concurrent runs, no early-game starvation occurs. Pre-shutdown starvation remains after packets 1558, 1674, 1678 and 1680. At packet 1559, intermission entry takes 99.87 ms and snapshot publication 131.29 ms. At 1675, map loading takes 936.16 ms before the later asset handoff. These exceed queued audio coverage. Snapshot, simulation and audio samples each have 1,747 entries, permitting sequence-aligned analysis. This single trial supports transition-cost attribution; it does not prove the earlier stalls were exclusively contention.

The audio worker currently resumes after an empty queue with the first arriving packet, without restoring its normal two-packet starting reserve. Implement and test bounded rebuffering after starvation: preserve every PCM sample, pause the empty device, restart with two packets, or release a final single packet after 100 ms. This addresses recovery after a stall; it does not remove the initial blocking map/UI work or qualify acoustic continuity.

Initial rebuffer implementation passes seven actual device checks, ten music/control/PCM checks, six effects-runspace checks and four volume checks. A second isolated Matrix route is recording with this single runtime change. During static review, the recovery deadline is found to begin at queue exhaustion rather than the first queued recovery packet; a producer stall longer than 100 ms can therefore expire it before any reserve is possible. Added a delayed-producer case to the finite test driver. It will run after the recorded route completes, preserving isolation and the current runtime source snapshot.

The delayed-producer case fails as predicted and is retained alongside the exact first worker source. Correcting the deadline to begin after observing the first nonempty recovery batch makes both zero-gap and 180 ms-gap device tests pass seven checks each. Ten music/control/independent-PCM, six effects-runspace and four volume checks also pass. The final isolated Matrix recording completes on its original process handle, with 36 evidence checks and all commands/checkpoints/audio frames intact. No usage-reset credit is requested or consumed during this continuation.

All three isolated routes submit identical PCM SHA DB35F5D34C9206B8D47126FEF57070EB6D10BD0D3D3A302BC11269666288AD63. The baseline, first recovery and corrected recovery observe four, two and three pre-shutdown empty queues respectively; single trials do not establish a performance ranking. The corrected run has observations after 1558, 1674 and 1737, plus final 1746; it restarts two recoveries with four/two queued packets, while map epoch reset clears another. Maximum mix is 43.590 ms and submission age 276.127 ms; 3,023 console writes over 51.865 wall seconds do not qualify 60 displayed FPS. Full raw receipts are copied byte-identically into results. Full movies remain local; corrected movie and real-time transition excerpt decode, and sampled actual intermission/E1M2 images retain readable low-contrast block UI and katakana gameplay. No listening or acoustic-continuity claim follows.

Detailed mechanism, retained failure, three-trial table, reproduction and limitations are in docs/audio-recovery.md. The roadmap now targets blocking map/UI work before audio publication: the existing map-loading pause occurs only after DoomGame.Update constructs the world. The recovery fix is progress toward the active release goal, not completion of audio or campaign qualification.

## 2026-09-12 — Loading boundary before world construction

The previous goal turn made progress, committed and privately verified as ec7ca14bd48ffc0bb0d818ed0a3f9e7fedaae0f6. This continuation begins clean. Source inspection confirms that the host already stops its active clock for loading status 5, but the simulation publishes that status only after the new World constructor returns. A host-only BeforeLevelLoad scriptblock now notifies before construction. It is excluded by the existing data-only save schema and installed again after a saved candidate becomes the live game.

The host publishes loading status before waiting for an acknowledged audio drain through the last produced packet. The audio worker plays the complete old tail, including a lone startup/final packet, then holds later packets and pauses through world construction and renderer asset refresh. It reports intentional drains separately from unexpected empty queues. No PCM is invented, no simulation tics are omitted, and the loading interval remains in wall-time reports and footage. This creates an explicit loading pause; it does not claim continuous sound or faster construction. Nine actual-device checks and six actual-engine/callback/save-data checks pass before broader regressions and the recorded route.

Ten music/control checks, seven delayed-producer recovery checks, 57 controller checks and 24 save-state continuation/corruption checks pass. The isolated recorded Matrix route completes with all 1,747 commands/eight checkpoints, all 2,201,220 audio frames returned and zero canceled frames. Submitted PCM remains DB35F5D34C9206B8D47126FEF57070EB6D10BD0D3D3A302BC11269666288AD63. The original 37-check audit passes; an expanded 42-check audit additionally confirms old audio completion, matching producer/device acknowledgement and QPC ordering inside the loading boundary. Both audit receipts remain.

The drain through packet 1674 returns 2,110,500 frames before construction, taking 272.370 ms producer wait. Before-assets time is 1,138.589 ms and full boundary 2,167.431 ms; the host records 2,163.484 ms of loading. The route takes 52.374 wall / 50.211 active seconds with 2,978 writes. Unexpected starvation remains after 1684 and 1692, plus final shutdown at 1746. This is an explicit loading interval, not faster world construction or continuous sound. Actual full movie/excerpt decode and sampled intermission/E1M2 visual checks pass. Complete raw JSON receipts are copied byte-identically; movie/audio assets remain ignored. Details and reproduction context are in docs/loading-boundary.md. A real simulation-worker save/new-game/load fixture with music is checking callback rebinding and the menu path before committing this milestone.

The real simulation-worker fixture passes 15 checks with music: numeric restored state, immutable replay archive, new game, two successful loads, three audio epochs and clean device closure. It records drains through 69/69/76. This covers those menu operations, not an ordinary exit after restoring a save. Six changed standalone PowerShell files parse, engine bundle compilation succeeds in controller/save tests, and diff checks pass. Every PID from the completed recorded route is absent. No live job remains from this continuation. This milestone is progress; remaining post-load empty queues and UI work before audio publication are the next bounded implementation targets.

## 2026-09-12 — Audio publication before presentation work

The previous goal turn made progress and is privately backed up at e205d140bee03d3eddb462ba67fd52e3ce0bef6e. This continuation starts clean. After a simulation tic completes, ordinary audio packets currently wait for automap discovery, checkpoints and UI/snapshot publication. Move their construction/enqueue ahead of that independent presentation work, while retaining the existing new-world epoch/asset handoff before its first audio packet. Volume and pause state are refreshed at publication. No mixer, score, rendering or gameplay algorithm changes.

Add per-tic QPC timestamps for update completion, packet enqueue and presentation start/end. A finite analyzer will require all 1,747 entries, prove ordering for 1,746 early packets plus the single map-handoff packet, and compare actual commands/checkpoints/submitted PCM against the retained prior route. The same simulation-worker save/menu/new-game/load fixture runs first; the next full Matrix route will be recorded in isolation from study synthesis/build/test work.

The simulation-worker fixture passes 15 checks. The isolated Matrix recording completes on its original handle and passes 42 campaign evidence checks. Six publication checks prove early ordering on all 1,746 ordinary packets, including 116 intermission packets; sequence 1675 alone waits for the map handoff. All commands/eight checkpoints and the 2,201,220-frame PCM digest remain exact. Every submitted frame returns, none are canceled, and only the final shutdown empty queue at 1746 is observed. This single trial has no unexpected pre-shutdown starvation; it is not a repeatability or acoustic-continuity guarantee.

Update-to-enqueue mean/p95/max is 0.298/0.421/31.208 ms. Presentation work after enqueue averages 9.413 ms overall and 15.491 ms for intermission, with 131.494 ms maximum. These are observed overlaps, not measured physical latency savings. The intentional loading boundary remains 2,236.881 ms, with 247.991 ms producer drain wait. The route makes 2,966 console writes over 52.231 wall / 49.996 active seconds; mix maximum is 67.954 ms and submission age maximum 180.915 ms. The full movie/excerpt decode, sampled actual UI/game images remain consistent, raw receipts are copied byte-identically, and every recorded-session PID is absent. Details are in docs/audio-publication.md. Next broaden ordinary-input campaign completion to E1M2 and soundtrack coverage while preserving this regression; the release goal remains active.

## 2026-09-12 — E1M2 ordinary-input campaign route

Previous turn made progress and is privately verified at fbbca7004960c1264d7bc6a8098167f97127601f. This continuation starts clean. Export-CampaignMap.ps1 loads the user's installed map and writes a local geometry/thing diagram plus JSON for route planning. Standard System.Drawing is used only for this documentation diagram, not gameplay rendering. Extracted map artifacts stay under ignored local/. E1M2's red door is special 28 at lines 527/528; normal exit special 11 is line 873. The candidate route visits the shotgun lift, red key, locked door and exit via ordinary commands.

Added an authored route fixture and finite Test-CampaignRoute.ps1, adapted from the established E1M1 waypoint/combat driver. It records exact inputs, periodic position/inventory, waypoint arrivals and failures, with IWAD/plan/driver hashes. The initial candidate starts from a fresh HMP pistol start and is running without terminal rendering. No direct damage, teleport, god mode or direct special activation is used. Completion and recorded host playback are still unproven.

Five retained candidates stall at actual geometry: before the shotgun lift, at the shotgun alcove's north wall, on the lower stair corridor edge, inside a pillar, and beside the upper switch alcove. Positions, inventories and input streams are retained in e1m2-route-first through fifth.json; the original driver source is also retained before adding timed facing/use holds. The sixth candidate completes E1M2 normally in 3,046 commands with 82 health, 21 kills and the red key acquired en route. No engine fix was needed for these waypoint errors.

Qualify-CampaignRoute.ps1 independently replays the fixed successful commands in a fresh engine instance, without navigation or targeting queries. All 87 sampled position/inventory/combat states match. Ordinary use presses then advance intermission and reach E1M3 for 71 tics, preserving 82 health, zero armor, 122 bullets and 13 shells at spawn. The resulting 3,233-command replay has 13 selected-state checkpoints. This proves headless input continuation, not yet terminal playback or E1M3 completion.

The recorder's finite duration limit is extended from 90 to 240 seconds (still within scoped audio capture's existing 300-second limit including its 35-second allowance), and explicitly requested ReplayEnd runs now check transitions beyond the old 90-second special case. A 150-second-bounded AnsiArt recording of the qualified E1M2/intermission/E1M3 route is running with the verified four-track catalog and input recording. No competing study synthesis/build/test workload runs during capture. The clip exporter now selects the final recorded destination generation rather than hard-coding E1M2.

The first recording fails at the recorder's actual 35-second startup deadline: its host-ready file arrives just after that deadline. The game subsequently times out awaiting capture release, with zero simulation tics and clean worker/audio shutdown. All owned game PIDs are confirmed absent before a new attempt. The failed 48-byte movie/log and portable receipts are retained; the exact intermediate recorder source is preserved. This is an actual terminal failed attempt, not an observation timeout used to restart a live job.

Give the recorder an explicit bounded StartupTimeoutSeconds (60 by default), and include it plus 15 seconds of closing time in the video/report budget. Scoped audio still starts only after readiness and keeps its gameplay-plus-35-second bound. No gameplay timeout or test result is silently extended. The second isolated AnsiArt capture successfully reaches scoped audio readiness and begins the same qualified replay. Its original session handle remains authoritative until completion.

The second recording terminates at tic 2238 with the actual 32-packet audio overflow guard. Seven checkpoints match before failure. Retain its raw game/audio/capture receipts and manually mux its valid video with the scoped audio as failure footage. Do not count that mux as a passed game run. The simulation now checks queue pressure before executing the next command and waits at 31 packets, leaving one capacity slot for consumer semaphore bookkeeping. It returns through the session-control loop and retains finite owner/stop handling. No queue capacity increase, sample drop or gameplay substitution is used; completed waits and any unfinished interval are reported, and time remains in the active pacing budget.

The third isolated AnsiArt capture completes on its original handle. Its new generic Test-CampaignRecording audit passes 42 checks: all 3,233 commands, 13 independent checkpoints, E1M2/intermission/E1M3 transitions, three music starts and all 4,073,580 submitted audio frames returned without cancellation or unconsumed packets. Actual capture source hashes remain unchanged. ReplaySourceMatches is false because the independently generated reference predates the host transport change; direct input/state comparisons pass. Full audiovisual footage and the 9.512-second transition excerpt decode. Actual sampled images show the block intermission and katakana E1M3 scene/HUD; UI contrast and lossy detail remain visible. This is not acoustic or physical-play verification.

This longer run has 161 completed audio-pressure waits totaling 2,407.099 ms (maximum 29.097), queue high-water 31, no unfinished interval, and 17 unexpected pre-final empty queues plus the final shutdown observation. It runs 95.490 active / 98.279 wall seconds, 33.857 active tics/sec, 59.074 active console writes/sec and 57.398 wall writes/sec. The loading boundary is 2,798.440 ms including 955.680 ms draining prior audio. It does not certify 35-tic/60-display performance or uninterrupted sound. Exact hashes, reports and limits are in docs/campaign-e1m2.md; portable receipts were copied byte-identically into results/, while all media/assets remain ignored local files.

Test-AudioBackpressure passes eight real-process/device checks with two unpaced 150-command batches and menu/resume at command 150. It exercises 123 completed waits totaling 2,108.139 ms, maximum 35.835 ms, and all 378,000 audio frames return. Menu acknowledgement waits for the deliberately queued first batch; resume takes 15.517 ms. The existing save-worker fixture also passes 15 checks after the runtime change. No live effect window is rendered by these headless worker tests. Next extend E1M3 normal/secret route coverage and soundtrack preparation; full release goal remains active, with no necessary user input or usage-reset action.

## 2026-09-12 — E1M3 normal and secret route investigation

The previous goal turn made progress: E1M2 and the audio-pressure fix are committed and privately verified at 8e87dcbbdc44f63b7728bfefb413991bc5cdcd50. This continuation starts from a clean worktree. The installed E1M3 map is exported into ignored local/e1m3-plan.json/png for route planning. Its ordinary exit is switch special 11 at line 982; secret exit is special 51 at line 785. The blue key is at (-2688,-1728), yellow at (-160,-864). A first authored HMP pistol-start candidate visits the western weapon/key route before the normal exit. No completion is inferred from geometry inspection.

The first six candidates are retained with exact commands and traces. They stop at starting-room walls, the stairwell window, an inaccessible approach from the shotgun platform, and a diagonal corridor wall. Raw installed linedefs 96/97 have flag value 29, including Blocking; the two-sided window is correctly impassable. Extend Export-CampaignMap with raw flags and initial sector heights, and draw blocking two-sided lines as walls. No gameplay engine change is justified by these fixture failures.

Add a finite PowerShell A* planar planning tool, Find-CampaignPath.ps1, using 16-unit grid points/midpoints and 16.1-unit distance from solid or explicitly blocking walls. It deliberately does not model actor collisions, floor steps, keys, moving sectors or timed triggers, so all output remains provisional guidance. The first attempt finds a route but fails while constructing output because comma/array arithmetic was not parenthesized; retain that failure and its exact hash-verified original source. The corrected maze query visits 616 points in 0.383 seconds. Geometry stays local; portable path receipts contain only proposed waypoints, parameters and hashes. The seventh ordinary-input candidate uses this guidance and a six-unit waypoint arrival tolerance, now recorded explicitly by the driver. Independent qualification still replays fixed commands without planning/targeting queries.

Qualify-CampaignRoute now accepts an explicit expected destination and secret-exit flag. It checks the actual exit kind and advertised intermission destination, then the entered map and retained secret history. The default normal-route behavior remains next numbered map. New secret-route qualification is pending actual input completion. Music preparation for the four existing tracks plus D_E1M4 and D_E1M9 runs on original session handle 41253, with finite continuous-loop qualification and catalog publication only after success. Do not infer liveness from this ledger: poll that same handle or inspect its process. No synthesis source changes or live recordings run during that preparation.

The seventh candidate exposes a second planning bug: integer Clamp bounds round a wall projection, allowing a route too close to a diagonal wall. Preserve that source and receipt, then replace the clearance calculation with explicit-double segment clipping against the axis-aligned player square. A later eight-unit grid resolves an offset narrow corridor missed by the sixteen-unit search; the old corrected source is also retained with its exact receipt hash. These remain provisional planar paths, not navigation guarantees.

Correction to the initial annotation above and earlier commentary: the western thing type 6 is the YELLOW key, not blue. Type 5 in the northeast is BLUE. The source CardType/MobjInfos mapping and actual card index agree. Ninth through eleventh candidates collect yellow; ninth dies returning, tenth is stopped by an actual barrel near (-1280,-3024), and eleventh correctly cannot use the blue-locked door. Eighth first required the maze door's tag-10 switch; no engine mutation bypasses it. Two secret candidates fail at the initial raised/closed corridor and western pit-door combat respectively. The corrected twelfth normal route reaches the upper horseshoe room but dies before blue; thirteenth adds two medkits with ordinary pickups. All failures remain in results/; detailed scope and exact iteration/tolerance parameters are in docs/campaign-routing.md.

The overload review also reproduces a camera interpolation defect in GameHost.ps1 and the older single-host clock call: .25 and .5 round to zero, .75 to one. Explicit double Clamp bounds fix both. A real 35-command E1M1 fixture fails 12 of 28 camera position/angle/view-height checks before the change and passes all 28 afterward. The main persistent-process path already interpolates endpoint snapshots with explicit doubles, so no new displayed-rate claim follows. See docs/snapshot-fractions.md. The updated independent destination checker also passes all 87 E1M2 samples, 3,233 commands and 13 checkpoints into E1M3; secret-route validation remains pending actual completion.

Thirteenth stops near (-1792,-1048), eight units short of a waypoint. Initial sector queries agree on floor 96/ceiling 232 throughout the nearby corridor; the actual obstacle is solid decoration type 48 at (-1760,-1056). Export initial solid non-CountKill/non-player actors with radii, and let the planar planner avoid their squares. Fourteenth runs on handle 60001 with that medkit detour correction, six-unit tolerance and 15,000-iteration bound. Its completion must be inspected, not inferred from this entry. No live effect window is rendered by these fixtures.

D_E1M4 preparation completes: 30,105,180-frame repeating period, three full periods synthesized, 27 live voices with identical normalized state, identical second/third float payloads and an exact independent eight-second opening. Six real-reader checks pass; raw qualification/opening receipts are copied byte-identically to results/. A separate reuse-only preparation validates the five completed tracks and publishes local/music-prepared-five.json, without prematurely publishing the still-running six-track request. E1M9 synthesis continues on original handle 41253. Details and hashes are in docs/music-preparation.md; no sources pinned by that active synthesis were edited.

Fourteenth terminates in combat after reaching both northern medkits, with later health falling from 67 to zero while stationary in the horseshoe room. Its completed failure is retained. Add optional CombatStrafe to the route driver: ordinary +24/-24 sidemove every 70 commands while facing a target, no direct state edits. Preserve the previous driver with its exact fourteenth-report hash. The report now includes armor samples, option state and explicit iteration bound; the qualifier compares armor when a newer trace includes it. Fifteenth uses the same route with six-unit tolerance/15,000 iterations and strafing enabled, on original handle 22097. Its result and the continuing E1M9 batch must be checked on their existing handles. E1M3 is still unqualified; these driver experiments do not change the game's difficulty or engine algorithms.

Fifteenth terminates with an earlier death at waypoint 8 near (-2014,-2481); general alternating strafing is not an improvement and remains opt-in. All current route handles are terminal. Further combat/approach investigation is needed; no campaign row is promoted. The only continuing study job is the original E1M9 music batch, session 41253, last verified producing successive sample-progress messages. Preserve that same handle across continuation. The current checkpoint contains the measured interpolation fix, passing E1M2 continuation regression, fifth music qualification and retained E1M3 investigation failures, not a completed E1M3 milestone.

## 2026-09-12 — Resume correction and damaging-floor investigation

The user had already applied a usage reset; their message was informational, not authorization to redeem another credit. Resume the active Ultimate Doom goal without a reset call or another continue request. The worktree began clean at 81ad23dd9212f8507de5c1929a3fb9dd2f62fb78. E1M9 synthesis is still producing output on its original session 41253; its pinned sources remain unchanged.

Reinspection corrects the earlier fourteenth-route interpretation: the last 70 inputs are forward 25 with tiny turns/use, not stationary firing, and the player is at Z=-32 near (-912,-768). A fixed-command diagnostic now records floor height, sector special and last damage source to distinguish environmental damage from combat. Do not infer the final cause until its original trace matches.

Source inspection finds an independent adopted gameplay defect: PlayerInSpecialSector has an empty case 16 followed by case 4. Unlike C, PowerShell switch does not fall through. Original id Software p_spec.c lines 944-1004 require both hazards to share 20 damage on each 32-tic boundary, including the same radiation-suit leak RNG ordering. The authored repair shares the existing adopted branch between 16 and 4. A real E1M1 world fixture tests four hazard types, grounded/airborne state, suit protection/leaks and adjacent tic boundaries. Its initial RNG oracle omitted DamageMobj's living-actor pain draw: retain that 40-failure receipt and exact harness source. The corrected unchanged-engine baseline has 30 failures out of 512, all type 16. Post-repair tests and campaign regressions are pending; old evidence is not automatically promoted to the new source.

The fixed-command fourteenth diagnostic completes: 3,392 commands and all 96 original position/health/height samples reproduce. It falls into sector 48 at command 2,740, then becomes grounded at -32, with a surrounding walkway at 88. The later repeated null-source type-7 damage is every 32 commands; five base damage costs four health and one armor. Correct the earlier stationary-combat diagnosis: the final cause is environmental damage after an unsafe pit route, not proof that combat strafing is needed. Last-source end-of-tic recording cannot separate multiple sources within one tic.

All 512 post-repair sector checks pass. Existing fixed E1M1 completion still advances into E1M2 with preserved inventory (1,747 commands); E1M2 retains all 87 trace matches, 3,233 commands, 13 checkpoints and inventory-preserving E1M3 entry. See docs/sector-damage.md. No full-campaign or display-rate claim follows.

Add optional AvoidDamagingFloors to the provisional planner, conservatively treating initial type 4/5/7/11/16 sector boundaries as walls. It does not model dynamic floors or establish that endpoints are safe. A found upper-route path omits the pit medkit and guides around the horseshoe walkway. Sixteenth uses that route with the repaired engine, six-unit arrival distance, 15,000 iterations and strafing off; original handle 4121 must be observed to completion. E1M9 music remains live on 41253, now into the second continuous period. Its sources remain unchanged.

The sixteenth candidate avoids the pit, collects the blue card and reaches the exit-area approach with 58 health and 43 kills. It then throws inside BuildStairs after 6,261 recorded commands; the failed Update itself is not included in that command log. Retain the exception/stack/trace in results/e1m3-route-sixteenth.json. This is a real engine failure, not completion.

The stair handler's unparenthesized bitwise test evaluates the equality before the bit mask in PowerShell. One-sided boundaries therefore fail to skip, and the traversal accesses a missing sector. The direct actual E1M3 stair fixture reproduces the same Number exception for both Build8 and Turbo16. The authored repair adds parentheses around the bitwise result; it does not bypass stairs or suppress an exception. Original id Software p_floor.c EV_BuildStairs explicitly skips non-two-sided boundaries. Post-repair destination/speed/retrigger/actual floor-completion checks are running before another ordinary route attempt.

Both stair variants pass all 86 focused checks after the parenthesis correction. Repeat the same ordinary route as seventeenth (session 75363), unchanged route/driver settings, with this engine fix. Post-stair E1M2 independent regression uses original session 93802; E1M1 continuation uses 52027. All are finite headless fixtures. Original music session 41253 remains the only synthesis batch. Do not duplicate any of these jobs when continuing.

Seventeenth passes: 6,931 ordinary commands reach E1M3 normal intermission with 66 health; final periodic sample has 48 kills, 80 armor, 82 bullets and four shells. Both post-stair E1M1/E1M2 continuations also pass, and the E1M1 commands/transition fields match the earlier receipt. Independent E1M3 fixed-command qualification runs on original handle 80139, comparing 198 periodic samples including armor and checking normal continuation into E1M4. Until it completes, do not infer independent qualification or terminal playback.

For the next campaign step, initial E1M4 geometry is exported only under ignored local/e1m4-plan.json/png. Player start is (2032,1120), shotgun (1312,800), blue key type 5 (160,800), yellow type 6 (-1248,1280), ordinary exit line 554 at x=-1600 between y=1856/1920. These are planning observations, not a route or completion. E1M3 secret coverage remains required. E1M9 music continues on its original 41253 handle; no synthesis sources were changed.

Independent E1M3 qualification completes successfully: all 198 recorded samples including armor match; 7,118 fixed ordinary commands, 24 checkpoints, normal exit/destination checks and preserved inventory pass. Intermission starts at 6,931; E1M4 at 7,047; 71 destination tics follow. E1M4 spawn retains 66 health, 80 armor, 82 bullets and four shells. Replay SHA-256 A9E3E3E48DF5A483D904A412E3AF7A872ED5B5862713A331DC3310007AA09970. This is HMP pistol-start E1M3 qualification, not continuous E1M1-through-E1M3 or terminal/audio/display qualification. Campaign matrix and current roadmap are updated accordingly. All route/regression handles from this continuation are now terminal; only the existing music job 41253 remains active. Next record E1M3 after that preparation finishes and continue secret/E1M4 route coverage. The Ultimate Doom release goal remains active; no user decision blocks progress.

## 2026-09-12 — E1M4 development and pending E1M3 recording

The previous goal turn is progress: hazard and stair corrections, 598 focused checks, two existing-route regressions and independent E1M3 normal qualification are committed and privately verified at 3c18d1cc2027d1b095091d03076de1e759f030b8. This continuation begins clean. The existing E1M9 music job is confirmed live on session 41253, now approaching the second full continuous-period boundary; do not restart it. Develop E1M4 ordinary-input guidance while synthesis finishes. E1M3 recorded host playback waits for that competing preparation to complete, with no synthesis source edits.

Initial E1M4 static paths are retained in results/e1m4-initial-path-*.json. The direct blue-to-yellow query would approach the yellow door before obtaining yellow, so it is rejected as progression guidance before a live input trial. Instead require the western blue door first, with new blue-door and door-yellow planning receipts. The first candidate uses shotgun, blue key, blue door, yellow key, yellow door and normal exit, six-unit arrival tolerance, 18,000-iteration bound and strafing off. It runs on original headless handle 58983. The static planner still does not prove step/lift/key behavior.

Correction after rereading the driver: the sixteenth E1M3 receipt includes the throwing update's input. Test-CampaignRoute appends to commandsLog before Game.Update, so 6,261 is attempted commands, not 6,261 completed updates followed by an unrecorded failure. The earlier ledger and stair write-up described that order incorrectly. Correct current docs and retain the historical correction here. A future driver diagnostic should distinguish attempted and completed updates and include the sector/floor at failure, without changing input choices. Do not edit the driver while the current E1M4 attempt still fingerprints it at exit.

First E1M4 candidate dies after 3,292 ordinary updates near (-1016,969), before yellow. Periodic samples show ammunition exhausted repeatedly in the western maze; no engine defect is inferred from that death. Add ordinary starting-room shells/medkit, an eastern bullet box and western armor/medkit detours to the second candidate. All planning receipts remain portable coordinates/hashes; full map geometry stays local.

After the first route terminates, improve Test-CampaignRoute diagnostics without changing input selection: pin initial plan/driver/bundle hashes; distinguish attempted commands from completed Game.Update calls; report the throwing update index if applicable; add sector/special/floor samples and final player position/last attacker. Preserve existing pre-update trace X/Y semantics and label them. The qualifier compares the added sector/floor fields when present. The original driver is preserved in commit 3c18d1c; existing first-route receipt still pins it. Second uses the same six-unit tolerance, 18,000-iteration bound and no strafing, with the revised pickup plan.

Second E1M4 attempt terminates at 2,021 attempted/completed updates with 91 health and no throwing update. Its new final diagnostic identifies sector 71, floor/Z 0, stopped at x=1424 beside the eastern window. Initial adjacent sector 83 is floor 136; the box is beyond it in sector 82 at 128. The static planner omitted this 136-unit step. Remove that detour; third retains the starting supplies and western armor/health, and adds a central chaingun pickup with ordinary movement. Original handle 16915, same tolerance/bound/no-strafe. No engine movement rule is relaxed.

A limited source scan for similar empty switch cases finds MapInteraction's monster-use allowlist (1/32/33/34). Those empty matches intentionally bypass the default rejection and then enter a separate action switch, so no fallthrough defect is inferred there. The scan finds no further exact unparenthesized enum-bitmask comparison pattern; that narrow result is not a general translation-correctness audit.

Third dies at 3,333 attempted/completed commands in the western maze (final attacker Sergeant), with the last sampled inventory still holding 20 shells but no bullets. Recheck raw thing flags: the apparent eastern shotgun at (1312,800) is flags 1 (easy only); the southwestern placed shotgun is flags 23 including multiplayer-only. Neither is an HMP single-player map pickup. The earlier plan descriptions claiming a shotgun pickup were wrong; periodic Pistol/Fist states and unused shells support this. The route did collect the chaingun. Fourth adds the northern blue armor and nearby shotgun-enemy area before the central route; a dropped weapon still must be collected through actual movement. No spawn rules or skill are altered. Source flag filtering is inspected directly in ThingAllocation.SpawnMapThing.

An independent asset-provenance investigation downloads two exact MuseScore history SoundFonts into ignored local/music-provenance. The current 5,994,284-byte bank exactly matches commit 930dbaf23b8432d897c3127a0ad1be176f7f1ebe (SHA 82475B91A76DE15CB28A104707D3247BA932E228BADA3F47BBA63C6B31AAF7A1). Its child 90c33ef9d87b3f5ff92efd3b07d89eb455fb1fef is the Alto Sax correction referenced by Debian's copyright record: 5,969,788 bytes, SHA C5378B62028C920CB11E4803327983FEE2F2CDFF5DC89C708E39DA417E51C854. The active research bank is unchanged. Document the exact variants, stated credits/license and distinction between region coverage and sound correctness in docs/music-bank-provenance.md. A bank change would need fresh qualification; no acoustic effect on Doom music is inferred yet. This closes the file-identity uncertainty more precisely without claiming finished redistribution or audio fidelity.

Fourth terminates at a northern rim step with 88 health, a legitimately collected shotgun and 19 shells. Final sector 77 is floor 0; the armor sits on sector 81's 104-unit rim. Initial line 382 (special 5, tag 4) raises sector 79 from floor 0; crossing line 383 (special 2, tag 7) opens the adjacent door. Fifth guides through that platform and waits 140 ordinary commands on it before crossing north to the armor rim. This is authored trigger sequencing, not direct activation. Fourth used a 22,000-iteration bound; fifth retains it, six-unit arrival and no strafing. The known failed pickup/height assumptions remain in the earlier receipts.

## 2026-09-19 — Revalidate completed jobs and resume terminal qualification

The preceding work is progress: E1M4 route failures changed pickup/height/trigger planning, source-backed SoundFont identity was established, and route diagnostics were improved. Original handles 71902 (fifth E1M4) and 41253 (music) are now absent; no matching study process remains. Inspect completed receipts rather than restarting either job. Fifth E1M4 ends at 2,978 attempted/completed updates, killed by an imp at the central approach with 180 armor remaining. The armor platform/pickup worked, but health and weapon collection/combat remain inadequate; no E1M4 completion is claimed.

The original music batch completed on September 12 with no error and atomically published local/music-prepared-six.json. On September 19 its catalog hash and all pinned preparation sources still match; preserved PowerShell runtime is still 7.6.5. Copy E1M9 qualification/opening receipts byte-identically to results/ and run the actual long-track reader check before recorded host playback. Do not claim live-job progress from old ledger messages.

E1M9 passes all six actual-reader checks on September 19, including source/payload validation, independent opening PCM and repeat-boundary bytes. Its 24,231,060-frame period has matching second/third float64 payload SHA 710B259BD2A681C5E80BDABF34F8854ABCCD26F1BA8B37ECAC57D5057BAF5818 and recurring 26-voice state D246B31648F6D92D475EDD05A0C55B80A8E08DF7A782C47F146866D6A4A95761. Record the completed six-track catalog and exact old-bank provenance; no bank replacement occurred.

Start actual Matrix E1M3 capture with the independent 7,118-command replay and six-track catalog, 240-second gameplay bound and 90-second startup allowance, original recorder session 43201, prefix local/recordings/e1m3-matrix-first. The diagnostic WGC recorder binary hash matches its pinned build. No simultaneous headless route, synthesis or benchmark workload runs during capture. The startup gate exists; outcome must be observed on this same handle. Source/game/audio/capture/checkpoint and movie verification follow completion.

The actual E1M3 Matrix run fails after about 59.782 active seconds with Simulation command ring overflow. Host issued 2,091 commands; 1,067 were consumed in the measured interval, 1,072 including orderly shutdown work. Four available independent checkpoints match that prefix. Mean game.Update is 30.552 ms, snapshot publication 17.083 ms, and observed tick lateness grows to 29,357.891 ms. Audio consumes all 1,072 packets without its own error; the bottleneck is not an overflowing audio queue in this run. These are recorded-run stage measurements, not isolated costs or a 35/60 pass. All completed console writes average 57.258/sec; those are not displayed FPS.

The failed run's scoped audio and WGC timestamps remain valid. Create a separately named failure-av movie with the existing alignment/mux verifier, preserving the original footage and failure metadata. Copy game/capture/audio/clock/input/readiness/mux receipts byte-identically into results/. The recorder pins its eight source files and the game report compares the gameplay source fingerprint. An additional route-sources snapshot was not created before this attempt; the copy operation exposed that missing artifact. Do not fabricate a retrospective pre-run source snapshot. This movie documents a failure, not campaign playback completion.

Implement host-side command admission before input sampling and replay/automap index advancement: allow at most two outstanding simulation commands, preserving the transport's existing hard 1,024-slot guard. The active clock keeps running while admission waits, so slower simulation and lateness stay visible; no replay commands or tics are skipped, and the ring is not enlarged. Completed pressure intervals and an incomplete interval marker are reported. Run a bounded 1,200-command headless E1M3 prefix through the actual 16-worker host, effects/music and fixed replay (original session 1178). This checks state/input preservation under pressure; it does not qualify full playback or remove the underlying performance deficit.

The user again clarified that a usage reset had already been applied. No reset tool was called; the existing Ultimate Doom goal remains active. Current files and receipts were inspected before resuming. The admission transport fixture's first attempt failed before assertions because a null map name bound as empty text; its exact source and failure are retained. A uniquely named memory map fixes the fixture, and all five checks pass across 1,200 commands/automap masks and physical ring wrap. The completed real-host prefix preserves all 1,200 commands, four checkpoints and 1,512,000 returned audio frames in 61.780 active seconds (19.424 tics/sec). An independent 13-check audit passes. This repairs overflow, not underlying throughput.

One frame at 60 seconds from the muxed failed Matrix movie was decoded and inspected: katakana and HUD are present, but the scene is dark. This is a sampled visual check, not complete movie or acoustic review. Correct another ledger transcription: third E1M4 attempted/completed count is 3,347, not 3,333; fourth is 2,117. Raw reports remain unchanged. Current campaign/audio docs now distinguish completed six-track preparation from open campaign/pacing work.

Implement an experimental direct numeric snapshot packer in GameHost, preserving the object-based snapshot and serializer as an independent byte oracle. It removes intermediate per-sector/side/actor hashtables without suppressing fields. Before adopting it in the simulation worker, compare complete bytes across all 36 maps, interpolation fractions/clamps, and the full independently qualified E1M3 replay with original checkpoints. Original finite validation handle 59100 must be observed; no competing study workload runs during its paired measurements. This is a snapshot microbenchmark, not a host/display performance claim.

Direct snapshot validation on original handle 59100 completes: 1,152 exact complete packet comparisons, all 36 maps at declared sampled states/fractions, and the full 7,118-command E1M3 replay with all 24 original checkpoints. Mean object/direct costs are 5.849/4.772 ms across all samples; replay endpoints alone 5.912/4.983 ms. Order alternates, cold observations remain included, and no other study benchmark ran concurrently. This measured improvement is modest; the worker still uses the old path. Next test shared endpoint packing, then actual host behavior. See docs/direct-snapshots.md. No milestone completes the Ultimate Doom release goal.

The coherent backlog/music/campaign-investigation checkpoint is committed and backed up privately at 28efb2b50c632361e631df392908043fc6b1f694; local and remote hashes match. Shared endpoint packing then passes 558 complete packet comparisons at 279 states and all 24 original checkpoints through 7,118 E1M3 commands (original validation handle 39154, now terminal). Paired mean cost falls from 10.212 to 5.823 ms; median 10.056 to 5.914. These isolated costs retain cold calls and alternating order. Adopt the pair in normal world snapshot publication, retaining object snapshots/checkpoints and all other screen paths. Start a finite real-host 1,200-command prefix with 16 Matrix workers, effects and the unchanged six-track music catalog; original handle 31275. Its pre-run sources/catalog/replay hashes are retained. Original replay fingerprint is deliberately not rewritten: a source mismatch is expected, and original checkpoints must still match. Do not run another study workload during this measurement.

The real-host shared-pair prefix on original handle 31275 completes normally with all 1,200 commands and four original checkpoints; all pre-run host source pins and catalog remain unchanged, and the recorded current implementation fingerprint matches. Its intentionally preserved old replay source warning remains visible. Thirteen independent evidence checks pass using an explicit ExpectSourceChange flag, which requires the mismatch rather than hiding it. All 1,512,000 audio frames return without cancellation or error. Active duration is 50.4945271 seconds, 23.76495 tics/sec, versus earlier 61.77960 seconds/19.42389. Mean snapshot publication falls 15.67423 to 8.27017 ms; mean game update 28.00283 to 26.92924 ms. The same-scene microbenchmarks and one before/after host pair support this bounded improvement, not sustained 35/60 or displayed FPS. All current study handles are terminal. Next profile gameplay-stage costs before another full E1M3 capture; preserve the three qualified route regressions and keep campaign/music/packaging acceptance open.

## 2026-09-19 — Gameplay profiling and numeric movement gates

The previous turn made verified progress, committed/backed up at 8e66dafeb5c99f8c16b0bac69a46e5d46a4a1ccb; this continuation began clean. Create a finite simulation-only stage profiler using a unique owned bundle, leaving production gameplay uninstrumented. The 1,200-command original E1M3 prefix matches all four recorded checkpoints and its final selected-state hash in uninstrumented, stage-profiled and actor-profiled runs. First stage profile averages 21.372 ms per update, 18.316 in Thinkers.Run; baseline averages 21.217 ms. Retain all cold samples and original harness versions. Finer inclusive timers put state actions at 16.190 ms and CheckSight at 13.902 ms per update; these overlap and must not be summed. Actor-profiled total is 23.111 ms, showing measurement overhead. Visibility is the next performance target. No loaded-host/display result follows from these simulation-only measurements.

Source inspection independently finds Mobj.Run comparing Fixed object identity in its momentum/floor tests. Two separately allocated Fixed(0) objects compare unequal with PowerShell -ne even though the class's explicit numeric op_Equality returns true. Original id Software P_MobjThinker uses numeric momentum and z/floor comparisons. The focused real-world fixture exposes an actual consequence: six allocation-identity variants of a stationary grounded missile spuriously explode/change RNG, failing 18 of 27 assertions. Change only Mobj.Run's four numeric comparisons to inspect Data. All 27 assertions pass afterward, including nonzero upward/downward momentum and zero-momentum skull charging. This is a correctness fix, not the main measured bottleneck: only 13 of 637 ZMovement calls in the profiled prefix were numerically unnecessary. Full original E1M3 replay regression is running on finite original handle 24134; do not infer its result yet. Additional Fixed identity comparisons elsewhere remain outside this narrow fix and need a separate semantic audit.

The movement-gate repair preserves all three existing ordinary-input routes: E1M3 completes all 7,118 commands and 24 original checkpoints into E1M4 at 66 health; E1M2 completes all 3,233 commands and 13 checkpoints into E1M3; E1M1 retains its 1,747-command intermission/E1M2 session with inventory preserved. Original regression handles 24134 and 23510 are terminal. Remove trailing whitespace from the edited guard; no further logic changed. Because this defect concerns allocation identity, also run the existing save/restore continuation fixture at command 700 with 140 subsequent commands (original finite handle 51147), rather than assuming ordinary fresh-start replays cover restored objects. Next performance work is numeric DivLineSide/visibility with preserved wrapping and exact side results; the production sight code is unchanged in this turn.

The save/restore continuation on original handle 51147 is terminal and passes all 24 existing checks, including 140 post-load commands after saving at 700. All study handles in this continuation are now terminal. The checkpoint consists of reproducible profiling, the narrow numeric movement repair, 27 focused assertions, three normal-route regressions and save continuation. It is not a new FPS claim or a completed release. Keep the full Ultimate Doom goal active and proceed to the measured visibility bottleneck.

## 2026-09-19 — Numeric div-line visibility calculations

The prior goal turn made verified progress: profiling identified sight checks, the numeric movement guard was repaired with 27 focused assertions, three normal-route regressions and 24 save checks; commit 6bdc5a1baabdcc458d8e503b7076856a7fb07c5f was privately backed up and this turn began clean. Retain both original Geometry.DivLineSide overloads from that commit in a licensed test fixture. Replace only their diagonal Fixed wrapper arithmetic with signed numeric differences, explicit 32-bit wrapping and the same integer shifts/products. Axis branches, on-line return values, signatures and all other geometry methods remain unchanged. No ray, actor or sight check is skipped.

The new actual-method fixture passes 44,424 complete side comparisons and 30 analytic axis/diagonal assertions, including all three return values, int32 extremes, fractional boundaries, zero-length lines and seeded random coordinates. Thirty-two alternating warm batches of 2,048 calls average 42.65266 ms for retained methods and 12.60013 ms for numeric methods; all answer hashes agree. Input construction and hashing are outside timing, all batches are retained. These are microbenchmarks, not loaded-host or display rates. Next replay the original E1M3 prefix with the same deep profiler; finite original handle 24354 must be observed to completion.

The full numeric-side E1M3 replay terminates successfully on original handle 62710: all 7,118 commands and 24 original checkpoints match through E1M4 entry. The subsequent uninstrumented 16-worker headless host prefix on original handle 89640 also completes; thirteen admission/input/audio evidence checks pass, source pins remain unchanged, and all 1,512,000 audio frames return. Active duration 40.4642684 seconds gives 29.65579 tics/sec. Mean update is 18.58920 ms, snapshot publication 8.08200 ms and automap discovery 6.15810 ms. This is a measured improvement over the prior 23.76495-tic build, still short of sustained 35/60.

Begin full Matrix E1M3/intermission/E1M4 capture on original handle 66459 with the unchanged 7,118-command qualified replay, six-track catalog, process-scoped sound capture and 90-second startup allowance. Retain a pre-run route-source snapshot including numeric geometry, Mobj, snapshots and host/audio paths; verify the diagnostic WGC binary hash before launch. Use a 300-second gameplay limit because the current prefix throughput would exceed the former 240-second limit after recording overhead/loading. Extend only recorder validation ceilings (game 600 seconds, scoped audio 660) to support this finite run plus audio tail; defaults and capture frame-rate limit remain unchanged. A longer safety deadline is not an FPS optimization or relaxation of the release's 35/60 target. No other study benchmark or route runs during capture.

The second Matrix recorder on original handle 66459 completes its video/scoped-audio merge, and all recorder/capture sources still match their pre-run pins. Gameplay reaches E1M4 normally with 7,118 commands and all 24 original checkpoints; 233.69677 active / 236.21075 wall seconds, 30.45827 tics/sec, 14,022 writes (60.00083 active / 59.36224 wall writes/sec), 2.51406 loading/handoff seconds. These are not displayed FPS. The audiovisual audit correctly fails: only 7,095 audio packets were consumed, 23 remain queued, and 5,040 of 8,939,700 submitted frames were cancelled (8,934,660 returned). Worker shutdown currently stops immediately, so completed gameplay can outlast its audio consumer. Preserve this partial-success recording rather than promoting it to full audio qualification.

Original and combined footage/PCM remain local; portable receipts and failed audit are copied unchanged to results/e1m3-matrix-second-*. The entire combined movie decodes; its hash and preserved compressed frames/timestamps match. A transition excerpt was exported and actual intermission/E1M4 frames inspected: both transitions are visible, katakana remains present, and Matrix intermission lettering remains dark. No acoustic review is claimed. Original media-review handle 31734 is terminal. Implement bounded draining only for successful replay-end shutdown, test an actually saturated real audio queue without the old artificial two-second tail sleep, then retry the recorded qualification.

The numeric-visibility/partial-recording checkpoint is committed and privately backed up at 57f05b82ff30edc3b7a886c2d681939cba6d45d8; local and remote match. Implement successful replay-end stop code 2 through the existing simulation IPC. It requests the existing three-second audio drain through the final produced packet before stopping the worker; quit/error cleanup remains immediate. The process close allowance is ten seconds only for this path, and ShutdownAudioDrain records pending packets, target sequence, wait and completed frames. Drain failure becomes a simulation/host error. Add a strict returned-frame/no-cancellation requirement to the campaign recording auditor.

The real saturated-queue test with DrainOnClose passes nine checks, with no artificial tail sleep: 31 packets are pending, drain waits 974.9695 ms through sequence 299, and all 378,000 frames return with zero cancelled or unconsumed data. Original handle 23020 is terminal. Repeat the full same Matrix E1M3 replay/music capture at prefix local/recordings/e1m3-matrix-third, 300-second safety bound, pre-run source snapshot, original live recorder handle 87861. No other study benchmark runs during capture. Observe this handle and do not infer audiovisual success from the focused queue check.

The third full Matrix capture completes on original handle 87861; its independent campaign audit on original handle 81791 passes all 47 checks. All 7,118 commands and 24 original checkpoints match, with normal intermission and inventory-preserving E1M4 entry. All 8,968,680 audio frames return; no packets remain and no queued frames are cancelled. Shutdown drains 14 pending packets through sequence 7,117 in 482.7021 ms. Pre-run source pins and current/recorded-input fingerprints match. Raw JSON receipts are copied byte-identically into results/e1m3-matrix-third-*. Full movie decode passes; transition excerpt decodes and actual intermission/E1M4 images were inspected. Katakana/world/HUD are visible, while dark intermission text remains a usability issue. No acoustic listening is claimed.

Performance remains below target: 237.40294 active / 240.00707 wall seconds, 29.98278 tics/sec, 11,387 writes (47.96486 active / 47.44444 wall writes/sec), 2.60434 seconds of loading pause. There are 77 pre-final queue-empty observations, not hardware/acoustic underrun measurements. Preserve the regression/variation from the second run's 60.00083 active writes/sec. The new reproducible comparison of retained reports finds mean console-output time 6.61 -> 13.08 ms and dispatch-to-last-worker completion 14.07 -> 18.06 ms, across every tic band, with unchanged 184x60 viewport and sixteen workers. Game update changes only 16.90 -> 17.21 ms. These overlapped intervals are not additive; the reports do not identify the underlying cause. No repeat capture is warranted merely to chase a better number. All study handles are terminal. Next investigate discovery cost and output variation; the full Ultimate Doom goal remains active.

The audio-drain/third-recording milestone is committed as e7b38fa and privately backed up; local/remote match and GitHub visibility is PRIVATE. Start a bounded 1,200-command automap-discovery baseline on original handle 44685. The new diagnostic harness times actual endpoint discovery, retains a per-command hash of every mapped-line bit, and verifies original gameplay checkpoints. Optional instrumentation exists only in a unique owned bundle; no production algorithm is changed. A subsequent instrumented run must match every baseline mapping hash. Inclusive method timings overlap and carry profiling overhead. Do not run another study workload during these measurements.

Both discovery runs are terminal: baseline original handle 44685 and instrumented original handle 58906 complete 1,200 commands with four original gameplay checkpoints. All 1,200 complete mapped-line hashes and the final selected-state hash agree; five additional receipt/source/state checks pass. Baseline discovery mean is 7.16597 ms; instrumented mean is 9.83914 ms. Inclusive per-command means are PointOnSide 0.79551, PointToAngleData 1.68674, DiscoverSeg 4.63806, ProjectDiscoveryAngles 0.34355, IsPotentiallyVisible 2.20506, solid wall 0.43054, pass wall 0.25363 ms. Nested intervals overlap, and profiler overhead is substantial. Raw source-pinned samples and sum derivation are retained in results/automap-discovery-*. No production algorithm or performance claim changes. Next test within-pass shared vertex angle reuse or a dedicated numeric traversal against this baseline, then broaden mapping parity before adoption. Full campaign, audio pacing, presentation variation, fidelity and packaging gates remain active.

## 2026-09-19 — Within-pass discovery angle reuse

The previous goal turn made verified progress: replay-end audio drains completely, the third recorded E1M3 route passes 47 integration checks, timing variation is retained, and the discovery profiler preserves 1,200 mapping hashes. Commits e7b38fa and 6677a6c are privately backed up; this continuation begins with a clean worktree. Create an experimental owned-bundle vertex-angle cache, cleared on every discovery pass. Production sources remain unchanged. The paired harness alternates reference/candidate call order at each real E1M3 state, clears mapped flags before each pass to compare fresh visibility, then restores cumulative discovery. It also compares every cumulative hash against the prior uninstrumented baseline and checks original gameplay checkpoints. Begin finite 1,200-command test on original handle 50927. No other study workload runs concurrently; do not infer speedup until it finishes.

Original cache handle 50927 exits successfully: 1,200 fresh visibility comparisons, 1,200 prior cumulative mappings and four original gameplay checkpoints pass. The dictionary candidate is substantially slower: baseline/cache mean 7.35265/11.00820 ms, p95 13.3718/19.7646. It loses in both alternating order groups. Preserve the failed performance experiment; do not adopt it. Next test numeric array indexing instead of per-vertex dictionary lookups, keeping lookup/index construction outside the hot path and included in map setup measurements.

The indexed builder initially refuses an ambiguous inherited DrawSeg text marker before gameplay; the exact failed builder/source hash and failure stage are preserved in results/discovery-angle-indexed-build-failure.json. Restrict the edit to the unique discovery-only subsector block. Original indexed handle 81781 then exits successfully: all 1,200 fresh and cumulative mappings and four original checkpoints agree. Paired baseline/cache mean 4.80312/3.89512 ms, median 4.8484/3.8637, p95 8.5869/7.0759. Lazy map indexing costs 16.2763 ms and remains included in the first timed call. Both order groups improve (baseline-first 4.88/3.82; cache-first 4.72/3.97). The baseline differs from the earlier experiment, so only this paired result supports a bounded improvement. Candidate remains outside production pending full-route and all-map-start checks.

Start the full 7,118-command indexed-cache replay on original handle 19310, preserving original checkpoints and fresh per-view mapping comparisons through the intermission and map change. Prepare a separate all-36-map/four-heading fixture while that finite run executes; do not overlap benchmark processes. The second fixture compares every mapped bit and verifies no framebuffer, validity-counter or other line-flag changes while reusing one renderer across map identities. No production source has changed.

Full indexed handle 19310 completes all 7,118 commands into E1M4 with 7,002 fresh discovery comparisons and all 24 original checkpoints. Mean reference/candidate discovery is 3.37867/2.72643 ms, p95 7.3827/5.7174; two lazy index builds take 20.0197 and 7.232 ms, included in timing. The all-map fixture on original handle 31599 then exits successfully with all 144 heading cases over 36 maps, exact mapping parity and unchanged pixels/counters/other flags; the reused candidate renderer rebuilds indices all 36 times. All experiment handles are terminal. Adopt the tested indexed implementation as the default discovery path, retain a diagnostic reference switch for paired measurements, and verify actual host/save behavior before a loaded-performance claim.

Adopt the tested indexed renderer class with CacheDiscoveryAngles defaulting to true; retain false for diagnostic reference comparisons. Diff review catches and restores the source file's trailing helper classes before any production test. The generated production bundle parses and its complete ThreeDRenderer class is byte-identical after newline/default-switch normalization to the already-tested candidate. Paired harnesses now explicitly disable caching on their reference instance, and the indexed builder copies an already-adopted bundle unchanged. Start the real 16-worker headless Matrix/music 1,200-command prefix on original handle 14595, 100-second gameplay safety bound, with pinned sources/catalog/replay and separately recorded input. The original source warning is expected; checkpoints must still match. No other study workload runs during this measurement.

The loaded indexed host on original handle 14595 finishes all 1,200 commands and four original checkpoints; its thirteen-check audit passes. All 1,512,000 audio frames return and their PCM hash equals the earlier numeric-side host prefix. Pre-run source pins/catalog and current/recorded fingerprints match. Active duration is 38.9243334 seconds, 30.82904 tics/sec versus earlier 29.65579; mean discovery 5.15010 versus 6.15810 ms, update 18.42859 versus 18.58920, snapshot 7.96375 versus 8.08200. Headless completed-image rate is 53.92514, not console/display FPS. Separate run variation remains possible; neither result meets sustained 35/60. Actual automap worker lifecycle on original handle 68054 then passes all eight save/load/menu/new-game checks. Update the diagnostic profiler to include the new indexed segment method and start a finite 35-command smoke on original handle 61307; its timing is not a performance qualification. Once terminal, back up this bounded improvement and return to E1M4 route development (actual dropped weapons), keeping deeper pacing work and all release gates open.

Original profiler-smoke handle 61307 exits successfully. All 35 cumulative mapping hashes independently match the pre-change uninstrumented baseline; eight method columns exist and the new indexed-segment counter is nonzero. The short run retains one original initial checkpoint and is not a performance result. All study handles are terminal. Review and privately back up the indexed-discovery implementation, rejected alternative, full/all-map parity, loaded host and lifecycle evidence; no release milestone is marked complete.

## 2026-09-19 — E1M4 dropped-weapon routing

The previous goal turn made verified progress: indexed discovery preserves full-route/all-map state, improves the loaded prefix to 30.829 tics/sec, and passes save/load boundaries. Commit 797e1d8 is privately backed up; this continuation starts clean. Return to E1M4 qualification. Add an opt-in driver behavior that steers toward visible nearby dropped shotgun/chaingun pickups the player does not own, without changing game state. Limit each drop to 140 steering commands, a 160-unit radius, and 24-unit height difference; nearby enemies under 64 units retain combat priority. Record approach/acquisition/attempt-limit events. Existing route behavior is unchanged when the switch is omitted. Reuse the fifth plan initially so the pickup behavior's consequences remain inspectable. All live effect tests still require recording; this input-generation run is headless.

The sixth E1M4 route on original handle 42073 is terminal: it collects an actual dropped shotgun at command 1,356 after 27 steering commands, reaches both blue/yellow cards, and survives to the exit chamber with 80 health/172 armor/12 shells/36 kills. It fails after 6,535 updates at waypoint 225, position about (-1200,1808), floor 128. The plan aimed directly across sector 38's 192-height ledge, a 64-unit rise. Geometry shows the intended eight-step approach from the east (sectors 59–66, floor 136 through 192) and bridge sector 52/tag 2, raised by switch line 592/type 18. Correct only the late route: explicitly use that switch from its front, enter the staircase at x=-672,y=1888, climb west and cross the bridge. Do not relax collision or alter sectors. Add independent exact-command weapon acquisition checks to the qualifier for successful routes that report such events. Begin the seventh finite HMP candidate with unchanged opt-in driver behavior.

The seventh E1M4 ordinary-input candidate runs on original handle 88370. In parallel, start finite E1M5 music preparation on original handle 68091: revalidate the six existing tracks and synthesize/qualify only D_E1M5 before atomically publishing local/music-prepared-seven.json. All six existing tracks have passed reuse verification. Music source pins must remain unchanged while this job runs. The route is a functional unpaced test, not a timing benchmark; overlapping preparation invalidates any attempt to present its wall time as performance. No live terminal or capture benchmark may run concurrently with synthesis. Observe both original handles; the existence of a preparation lock file alone is not a live-job claim.

The seventh E1M4 candidate on original handle 88370 exits normally after 6,161 ordinary commands, following the intended staircase/bridge instead of cutting across the ledge. Driver and plan hashes still match. Begin fresh independent fixed-input qualification, including all periodic sector/floor/position/combat/inventory samples and the new exact-command shotgun-acquisition check. E1M5 music opening render completed successfully; its continuous three-period qualifier remains live on original parent handle 68091. A read-only E1M5 geometry export also completed under ignored local/ for subsequent route planning. These are functional tasks overlapping synthesis, not isolated speed measurements.

The independent E1M4 replay on original handle 89417 exits successfully: all 176 periodic position/sector/floor/combat/inventory samples match, the shotgun is independently acquired exactly at command 1,356, and 22 checkpoints cover 6,348 total commands. Normal intermission begins at 6,161, E1M5 at 6,277, followed by 71 destination tics; spawn inventory remains 77 health, 168 armor, zero bullets and twelve shells. This qualifies the fourth normal route headlessly, not continuous-episode/terminal/audio/35-60 behavior. Add a negative qualification check on original handle 94808 with only the acquisition claim shifted one command early; it must reject that claim through real independent replay. D_E1M5's eight-second opening reference is copied byte-identically to results/music-e1m5-preparation-opening.json. Its 492-audio-second continuous qualification remains live on original parent handle 68091; no loop/catalog completion is claimed.

The negative verifier test on original handle 94808 exits with its expected checked result: changing only the claimed acquisition command from 1,356 to 1,355 produces Independent weapon acquisition differs at command 1355, with exactly 1,355 replayed inputs and no success claim. The positive route remains qualified. Music parent handle 68091 is freshly polled and still live, with continuous synthesis reporting 57.14/492 audio seconds; this is progress, not a finished loop. The only remaining live study job is that original music preparation. Preserve the current milestone privately, then continue E1M5 ordinary-route planning from its inspected local geometry while re-polling the same music handle. Do not restart preparation based on elapsed time or the lock filename.

## 2026-09-19 — Resume and E1M5 route planning

The user clarified that their usage reset was already applied and requested continued goal work. No further reset is requested or consumed. The release goal is active. Reattach to original music preparation handle 68091; it remains live and reports continuous progress through 125.71/492 audio seconds. Original planning handle 79792 completed. Do not duplicate either job or infer completion from elapsed time.

The first conservative E1M5 spawn-to-armor plan fails when all damaging-floor boundaries are forbidden: the spawn pool sector 59 is damaging and must be crossed. Retain the failure under local/e1m5-first-leg-0.json. Unrestricted planar planning finds a route through that pool to armor, the placed HMP shotgun and the northern blue-key-room stair entrance. The western window is too high; use the actual north stairs. This is route guidance only, not gameplay or performance evidence. Finite ordinary-input validation follows, with unchanged game rules and music source pins.

E1M5 first route on original handle 75117 stalls after 1,837 ordinary updates at (44.54,144), 78 health/87 armor; a dropped shotgun had been acquired at command 311. Extend the failure inspector with a read-only final nearby-actor report, then replay the unchanged inputs on original handle 33160. All 52 selected samples match. The live barrel has moved from (80,176) to (71.16,169.05), health 11, and occupies the next eastward movement's collision square. This is a route obstacle, not evidence of a height/collision engine bug. The second plan gives the barrel southern/western clearance on both legs and runs on original handle 28975. Original music parent 68091 remains active through 148.57/492 audio seconds. Source pins for synthesis remain unchanged; these overlapping functional tests make no speed claim.

The second E1M5 candidate on original handle 28975 completes the barrel detour and shotgun-room pickup but stalls after 2,834 updates at the closed tag-7 passage (sector 141 ceiling 0), with 48 health/77 armor. The original northern approach was invalid before the switch inside the blue-key room. Further read-only geometry/source inspection establishes the intended dependencies: crossing line 271/type22 raises eastern walkway sector91 to56 and clears its damage special; that reaches yellow in room92, whose western window is only40 high. Yellow opens the western door; switch189/type103 opens central door82/tag2; stairs and the eastern loop then reach blue. Manual type31 doors must be treated as potentially operable in the local planning copy. Earlier direct eastern-to-blue and initial-north-stair hypotheses are rejected, not engine fixes. The western ring has steps from floor-104 down to-184; the middle pit is-208 and switch platform21 is-192, so a central pit crossing can return via the24-unit western rim while avoiding the initially raised side platforms20/35. Planning copies change ignored geometry only, never actual game state. Actual command validation is still required.

The third full E1M5 candidate is running on original handle 57715 with a finite 25,000-iteration bound and 386 planned waypoints. It follows the bridge/yellow/western switch/central stairs/eastern loop sequence; source and map geometry are unchanged in the actual game. First failure diagnostics additionally pass ten consistency checks, including the exact loaded bundle, all 52 samples, all 1,837 inputs and final position/health/armor. The optional source-only inspector changes do not affect gameplay or the live music synthesis job.

The third E1M5 candidate on handle 57715 dies after 5,519 commands in the western ring, floor-184, zero health/38 armor and last attacker Possessed. It had obtained yellow and traversed the raised bridge, but ammunition was exhausted by command5,250. A fourth candidate on original handle61248 changes only the route to collect the box of shells at (368,352) inside the already visited shotgun room; the rest of the full progression plan is retained. No gameplay change is justified by this bot failure. Start a cohesive working article from completed evidence and correct the README's stale E1M1-only qualification claim; current loaded pacing and incomplete campaign status are stated prominently.

The fourth E1M5 candidate on original handle61248 dies after4,214 commands, with39 armor and last attacker Player; 21 shells remained at command4,200. The extra ammunition is collected, but the player-attributed death is consistent with shooting a nearby explosive barrel. Add an opt-in ClearBarrels driver strategy: target visible live barrels at160–300 units, reject proactive clearing while another shootable barrel is within160 or an enemy within64, cap each target at140 commands, and hold movement35 commands after the target dies. All shots and explosion damage remain actual game actions; no claim of safety against chains or moving actors. Fifth candidate on original handle29778 uses the same fourth plan plus that option. Original handle89869 independently regenerates the fourth attempt with the option omitted; require its commands/trace/final state to match before claiming default preservation. Keep the engine and music synthesis sources unchanged.

The optional strategy does not complete E1M5 by itself. Fifth handle29778 is terminal after5,895 commands, western pit rim, zero health/37 armor, last attacker Troop. It records nine targeted barrel deaths; the input audit confirms the recorded admission distances/bounded attempts and315 post-death inputs without forward/sidemove. Default-regeneration handle89869 is terminal with the original fourth failure; all35 parity checks pass, including4,214 identical inputs and all trace/arrival/pickup/final-state values. Original handle13766 now independently replays the fifth failure to check ordinary-command reproduction. Sixth handle94782 adds upper-landing shells/medkit and the western medkit, retaining the full progression route and optional clearing. Music parent68091 remains live through377.14/492 audio seconds; the first two period state hashes already match but the full qualification is still pending.

The fifth candidate's fresh independent replay (original handle13766) is terminal: all5,895 ordinary commands and168 original position/health/height samples reproduce exactly with the unchanged engine bundle. This supports the driver-only nature of the optional barrel strategy, while retaining its failed campaign outcome. Sixth candidate94782 is still active and has reached the western return-lift stage. Music preparation68091 reports400/492 audio seconds; no catalog completion is claimed.

Sixth candidate94782 is terminal after8,672 updates: it reaches the western switch, rides the return lift and crosses the newly opened central door/stairs, then dies in eastern sector127/floor72, zero health/22 armor, last attacker Shotguy. At the western return it had only13 health despite ammunition remaining. Seventh candidate25653 adds the central medkit at(416,688), approaching from(432,696) to respect the cubby's wall clearance. The planner correctly rejected the item's exact center within its16.1-unit conservative wall margin; the offset remains inside ordinary pickup range. No game state was edited, and no completed E1M5 route is claimed. Default behavior, optional driver evidence, failure diagnostics and article links have passed their relevant checks.

The driver parity verifier also rejects a candidate with only the first command altered, at its identical-input check; the expected negative receipt is retained. GitHub confirms the existing origin remains private. Preserve the reviewed diagnostic/driver/article milestone while original seventh-route25653 and music-preparation68091 continue. These finite jobs remain part of the active release goal, not a reason to consume another reset or request a continue prompt.

## 2026-09-19 — Rendering fidelity and seventh music track

The preceding user-requested scope review changed no project scope or authoritative implementation state; classify it as no implementation progress. Resume by revalidating original handles: music parent 68091 remains live, while route 25653 is terminal with a retained failure. Seventh E1M5 candidate dies after 8,369 ordinary commands at waypoint 272, around (499.35,699.33), before completing the central medkit detour. This provides no new engine-defect evidence. Do not start another route solely to maintain bot activity; make progress on the existing rendering-fidelity gate.

Add an offline same-state comparison against the adopted PowerShell reference renderer. Inspect the resulting local reference/current/difference PNGs. E1M1 headings 0/90/180 initially have 1,511 differing HUD indices each; scene differences are 42,379/36,380/42,700 of 53,760 pixels. Identify missing weapon ownership numbers, ignored WAD patch offsets and variable-width number spacing. Repair the HUD, preserving the world patch path, and factor its drawing for focused comparison. The final three views have zero HUD differences while scene-difference counts are unchanged. An intermediate 171-difference run has unreliable end-only source attribution because the file was edited around completion; retain it as diagnostic history and add start/end source checks to the comparison harness. Final comparison handle 87295 is terminal with unchanged sources.

HUD test handle 80404 is terminal: all 64 varied single-player states exactly match the adopted reference's 10,240 HUD indices and independently match binary-cached assets rendered in seven uneven strips. This covers every face, all weapon/key bit combinations, ready weapon states and number boundaries. Actual process test handle 7288 is terminal: all 320,000 complete image pixels match serial output across five views, and 35 Matrix/katakana encoded strips also match. These offline checks do not present a terminal window, so no live-effect recording was made or claimed. See docs/rendering-fidelity.md for reference limitations and remaining 3D work.

Music parent 68091 is terminal and successful: D_E1M5 completes three continuously synthesized 164-second periods, repeating normalized state and second/third output exactly, and publishes the fully verified seven-track catalog. Copy its qualification receipt byte-identically into results/music-loop-e1m5-prepared.json. All six additional reader checks pass against the independent opening PCM and continuous boundary. No music source changed during the batch. Preparation removes the dependency for an E1M4-to-E1M5 recording; the next live run still needs footage, audio capture and checkpoint audit. Update the article and roadmap without adding Final Doom or converting the MyHouse audit into a support promise. Campaign, reference fidelity, acoustic checks and sustained 35/60 targets remain open.

## 2026-09-19 — Recorded E1M4 continuation and lighting isolation

Classify the preceding goal turn as progress: committed HUD repairs and seven-track music qualification were verified and privately backed up. Revalidate the clean worktree and completed dependencies; no prior study job remains live. Start the finite AnsiArt/katakana E1M4 replay with scoped audio and a fresh owned maximized window on original handle 68833. Use the completed seven-track catalog, 360-second bound and 180-second startup allowance. Save pre-run source pins under results/e1m4-ansiart-first-route-sources.json. Keep other experiment workloads idle during recording; preparing the unreferenced diagnostic comparison script does not change any game/capture source.

Original recording handle 68833 is terminal and successful. Independent audit 50134 is terminal with all 51 checks passing: 6,348 unchanged inputs, all 22 checkpoints, exact inventory-preserving intermission/E1M5 transitions, expected three music starts, all 7,998,480 audio frames returned, no canceled tails, source pins intact and full delivered audiovisual movie decode. The timing summary records 34.250 tics/sec and 50.491 console writes/sec, all startup/transition boundaries separately scoped, six audio queue-empty observations and three internal capture-alignment fills totaling 3,370 samples. The initial summary attempt exposed a PowerShell array-expression precedence error in receipt paths before any output was written; fix path parentheses and rerun successfully. Check gap count and mean independently against first/last completion timestamps. Do not label console writes or encoded video rate as displayed FPS.

Review actual footage at 60, 210, 220 and 225 seconds: gameplay, intermission and E1M5 destination are present; the viewport is centered, with large unused margins in the maximized ultrawide window. Create a separately labeled 20-second viewing excerpt at the observed 1280x800 game rectangle (1080,304), preserving the full 3440x1392 capture and raw PCM. The preview decodes and its extracted frame is visually checked; its hashes/crop are retained in results/e1m4-ansiart-first-preview.json. No physical listening claim.

After capture, diagnostic handle 59926 renders three E1M1 views with common fixed colormap 16. Differences decrease from 42,379/36,380/42,700 scene indices to 15,772/16,347/15,603; HUD differences remain zero. Source inspection finds different distance formulas and absent wall-orientation contrast in our current renderer. The darker shared map may also collapse texel differences, so treat this as evidence for investigating lighting, not a complete error attribution. No production rendering code changed this turn. The initial fixed-map receipt inherits an outdated generic Meaning sentence about heading-only fixtures; its explicit FixedColorMap field and this ledger establish the override. Correct that wording in the harness for subsequent runs. Next: compare reference lighting tables/selection, measure any candidate, and continue campaign work without redefining the release gates. All original handles from this turn are terminal.

## 2026-09-19 — Numeric lighting and reference wall contrast

The previous goal turn made progress: recorded E1M4 progression and lighting isolation were committed and privately backed up. Begin from clean 9914b96 and retain a byte-identical FastRenderer baseline copy; its hash matches the earlier recorded source manifest. Replace linear-distance shading with compact numeric scale/distance light tables and sector/extra-light selection, including wall-axis contrast and actor extra light. Table test completes with 768 scale and 2,048 distance palette-bin matches. First candidate image comparison reduces differences but retains a substantial near-wall mismatch.

A read-only equality experiment reproduces PowerShell's Fixed-object equality trap: distinct equal-valued coordinates compare unequal through -eq, although Data equality and explicit op_Equality are true. Check id Software's primary r_segs.c, which applies contrast using coordinate values. Correct six reference-renderer equality expressions in the three solid/pass/masked light-selection blocks. Against this corrected reference, old/new numeric scene differences are 41,012/17,111 at heading0, 36,720/17,410 at90 and 41,823/16,935 at180, with exact HUDs. Retain comparisons against the earlier buggy reference separately; do not tune the candidate to reproduce that bug.

Isolated alternating E1M3 serial timing completes on original handle74723: mean59.791/57.890ms, median54.983/56.241ms and p95 83.269/93.003ms before/after, all 20 calls retained per renderer. Mixed statistics are not a speedup claim. All subsequent functional handles are terminal: 81187 passes 144 discovery cases over 36 maps, 79994 matches 320,000 pixels and 35 actual AnsiArt worker strips, 20946 confirms fixed-colormap 16 output. Cross-check every earlier discovery hash/flag/counter and all three reference/current fixed-map image hashes directly; results/render-lighting-controls.json records exact preservation. No concurrent workload was used during the serial benchmark; functional checks may overlap and have no speed claim.

The first recorded Classic E1M2 attempt on handle72826 is terminal before gameplay: Read-GameRenderAssets cannot find New-FastLightingTables in the main host, which intentionally imports no rasterizer. The renderer-worker checks did not cover this import surface. Retain the failed game/capture receipts and footage; no startup success is claimed. Move the unchanged factory into RenderLighting.ps1 and import it from both consumers. A fresh process loading only RenderAssets reads a real legacy asset cache; table parity passes again. Preserve the pinned shared module in subsequent comparison/capture manifests. Record retry on original handle7990 with fresh prefix local/recordings/e1m2-classic-lighting-second, the qualified3233-command E1M2 route and seven-track catalog. It has passed the startup/audio gate and remains running. Do not edit game/capture source pins or start another workload while it records. The original failed Terminal window remains owned and needs targeted cleanup after the active recording; never kill the shared Terminal process.

The retry on original handle7990 is terminal and successful. Its fresh audit passes 53 checks, all 3,233 inputs and 13 state checkpoints through E1M3, and returns all 4,073,580 audio frames. Full Classic playback averages 34.9768 simulation tics/sec and 50.5017 console writes/sec; two queue-empty observations and one 26.80-ms interior capture-alignment fill remain. No physical listening or 60-display claim. The standalone timing summary includes all write gaps and a labeled same-world subset; retained source/receipt hashes make this a distinct workload/version rather than a causal comparison to the older AnsiArt recording.

Inspect the actual Classic gameplay frame and E1M3-entry frame; retain the full movie and create a separately labeled 20-second viewing crop. It decodes and its frame is visually checked. The font yields an approximately 1600x900 image for the 320x200 framebuffer, so aspect/font-cell qualification remains open. Close only the failed first capture's exact owned window after confirming recorded HWND/PID/title, using standard WM_CLOSE; do not terminate the shared Terminal process. Recheck window absence and retain the cleanup receipt. All study process handles from this turn are terminal. The next work remains presentation/fidelity and campaign qualification, with no change to the declared release scope.

## 2026-09-19 — Terminal write granularity comparison

The preceding user-requested review restated scope without changing implementation or producing new execution evidence: classify it as no progress toward the release. Revalidate the worktree and take the available terminal-output experiment forward. The full Ultimate Doom objective remains active; no scope changes are applied from the review. No experiment job is live at the start of this continuation.

Implement selectable Strips/Batch output with identical ordered ANSI bytes, reusable bulk-copy buffer and explicit report counters. Preserve Strips as default pending repeated actual-host evidence. Fix the optional-clear empty-array expression before live use. The first byte-test run rejects an invalid 40-row synthetic fixture retaining a 168-row HUD boundary; preserve results/terminal-output-byte-parity.json. Correct its HUD boundary, then results/terminal-output-byte-parity-second.json passes all 72 comparisons across three codecs, uneven strips, positions, clear/status combinations and growth/shrink reuse. Record output mode/source in capture metadata and verify frame/write counts in the campaign auditor. The first documentation patch failed atomically on a missing ledger context; no files were created by it. Reapply the new protocol and runner separately. The declared experiment in docs/terminal-output.md is Strips/Batch/Batch/Strips, with full same-route audio/window recordings and no competing study workloads.

All four declared recording handles are terminal and successful: 38473 Strips first, 81798 Batch first, 6948 Batch second, 42525 Strips second. Every run passes 58 recorded campaign checks, consumes the same 3,233 inputs with all 13 checkpoints, enters E1M3 with the expected inventory and returns all 4,073,580 audio frames. The four-trial comparison passes 148 checks: identical pinned sources, replay/IWAD/music/PCM, settings, font, viewport and capture configuration; independent endpoint-gap arithmetic agrees. No game/capture source changed during the trials, and no other study benchmark/synthesis workload ran alongside them.

Observed image completion rates in order are 39.437, 38.524, 57.168 and 55.237/sec; corresponding level-output means are 18.987, 8.273, 6.650 and 11.332 ms. Simulation averages 34.694, 34.986, 34.985 and 34.982 tics/sec. Batching consistently reduces the measured output phase but the whole-game comparison changes direction; repeat variation is large. Keep Strips default, retain Batch as an experimental option, and do not call either rate displayed FPS. Both same-world tails and audio queue observations remain visible in reports. The four runs contain 7/6/2/3 queue-empty observations and small interior capture alignment fills; there is no acoustic continuity claim. Sources/workloads match, but focus/background load/thermals were not independently controlled, so no cause is assigned to the temporal variation.

Inspect a frame extracted at 60 seconds from every retained full movie. Each shows centered Classic gameplay/HUD with no visible external occlusion; samples have different startup offsets and do not compare equal world states. Preserve original footage, PCM and PNGs. Large margins and physical aspect remain open. Document the complete comparison in docs/terminal-output.md and the article/roadmap/README. The next rendering-performance hypothesis is eliminating redundant ANSI color traffic while preserving display semantics; campaign completion, sound fidelity, projection/effects and release packaging remain required. No goal completion is claimed.

Post-run ownership inspection confirms no original game processes or owned windows remain. The initial cleanup receipt mistakenly counted a null produced by empty-array property enumeration as a live PID. The second receipt removed that error but caught a newly reused PID and returned Passed=false; its generic Meaning string overstated absence and is superseded here. An unchecked native exit code initially let an inaccurate success sentence into this ledger; replace it after inspecting the actual receipt. The third receipt compares current process start times against each game completion time to distinguish PID reuse and passes. No process was terminated. Preserve all three reports; terminal-output-cleanup-and-review-third.json is the corrected ownership/review evidence.

## 2026-09-19 — Independent foreground/background ANSI state

The preceding goal turn made progress: byte-preserving output batching, four audited recordings, the comparison and private backup were completed at ee2f0a4. Revalidate the clean worktree and terminal prior process handles. Continue the full Ultimate Doom release with measured ANSI traffic reduction; no scope or language-boundary change.

Implement an experimental truecolor encoder that sends only a foreground or background instruction when the other component is unchanged, resets both assumptions at each strip, retains half-block glyphs and source pixels, and uses cached standard UTF-8 strings. It does not retain cross-frame display state. Test-AnsiColorState independently parses every output token, rejects unknown sequences/duplicate painting, and compares every RGB sample to the source palette. Thirteen cases pass, including odd sizes, uneven partitions, explicit component transitions and six real E1M1/E1M3 views. The alternating serial 16-strip test retains 24 timed samples per version: baseline/candidate mean 36.474/31.125 ms, median 35.982/30.036 ms; output bytes fall from 16,147,500 to 13,406,496 in those samples. These are warmed serial encoding observations, not live throughput. Preserve results/ansi-color-state-first.json.

Wire an explicit Pairs/ColorState selection through launcher, host and workers, retaining Pairs default until actual-host evidence. Character-mode branches remain unchanged. Extend worker partition checks to compare Classic encoded bytes as well as pixels; the ColorState worker check is now running on original handle 76319. After targeted worker checks, the declared Classic live comparison is Pairs/ColorState/ColorState/Pairs, with Strips output throughout, the same E1M2 ordinary-input route, 16 workers, seven-track catalog, maximized window and full scoped audio/window capture. No game/capture source edits or competing study workloads during that sequence. Preserve failures and all receipts; no displayed-FPS claim follows from console throughput.

Both actual-worker handles (76319 Classic ColorState and 87522 Matrix/katakana with the Classic selection ignored) are terminal and successful: each compares 320,000 pixels and 35 encoded strips. The four subsequent live handles are terminal and successful: 72869 Pairs first, 69347 ColorState first, 66153 ColorState second, 22662 Pairs second. All four pass 65 integration checks and return all 4,073,580 audio frames; the shared-configuration comparison passes 160 checks. Sources stayed unchanged throughout the sequence and no other study experiment ran concurrently.

Results in declared order: 35.190/39.513/42.298/54.612 image writes/sec and 34.371/34.470/34.743/34.977 tics/sec. Candidate average bytes/image are 526,202 and 525,570, versus baseline 620,625 and 614,145. This supports a lower-bandwidth encoder, but not a consistent full-game speedup: the candidate wins the first pair and loses the second. Unchanged rasterizer timings also vary substantially. Keep Pairs default and retain ColorState as an explicit option. Do not run more uninstrumented long pairs as if they could establish causality; improve condition telemetry/time pairing for future performance work. Continue the remaining fidelity/campaign gates. Both synthetic and real-view codec tests passed without changing the source pixels.

Inspect extracted 60-second frames from all four complete movies: centered Classic image and HUD, no visible external occlusion; differing startup offsets mean different world states. Keep the original audiovisual footage, PCM and screenshots local, with hashes in portable receipts. All movies decode. Software queue-empty counts are 6/6/7/2 and every run includes interior capture-alignment fill; no acoustic or 60-display claim. Document findings, counterevidence and unchanged default in docs/ansi-color-state.md, README, article and roadmap.

Final ownership inspection passes in results/ansi-state-cleanup-and-review.json: no original trial processes or owned windows remain, with PID reuse distinguished by current start times. Review-image hashes are retained. No process/window termination was necessary.

## 2026-09-19 — Weapon lighting fidelity

The previous goal turn made progress: the optional exact-color ANSI encoder, all recorded comparisons and private backup completed at f9b2754. Begin from a clean worktree; prior trial handles are terminal. Return to rendering fidelity rather than repeating uninstrumented performance pairs. Full Ultimate Doom release gates remain active.

Source inspection confirms that numeric weapon rendering always selected colormap zero. Check id Software's primary r_things.c R_DrawPSprite/R_DrawPlayerSprites: non-invisible weapons use the player sector/extra-light scale table's final bin, full-bright frames use map zero, and fixed colormaps take priority. The adopted PowerShell reference implements those rules. Invisibility remains a separate open renderer feature; no external source body is copied.

Carry player SectorLight through the object and direct snapshot producers and previously reserved NumericV1 header slot 43; the decoder restores it and interpolation retains the current discrete value. Factor Draw-FastPlayerSprites out of the main rasterizer and apply sector/extra-light, full-bright and fixed-map precedence, preserving positioning/clipping and using the full 15-bit sprite frame mask. Add an isolated reference comparison covering 138 weapon images: all 16 light bands, fixed maps 16/32, full-bright flags, extra-light clamping, ready and flash states for Ultimate Doom's eight weapons. Every complete indexed image matches the adopted reference and asset-cached seven-strip drawing. Reproducing the old always-full-bright call mismatches 88 cases. Preserve results/weapon-lighting-first.json. The eight snapshot wire checks pass with deliberately differing old/current sector light and an explicit output path preserving prior evidence.

Full ordinary-input E1M2 plus all-36-map object/direct endpoint checks run on handle18958; actual Classic/Matrix/AnsiArt worker partition checks run sequentially on handle72913. These correctness jobs may overlap; do not draw timing conclusions from them. After both finish, record a full Classic campaign continuation with no competing study workload and frozen game/capture sources.

The first broad endpoint run (handle18958) completes all 336 byte comparisons across all maps and the E1M2 route, but fails all 13 historical checkpoint hashes. Inspect the actual mismatch and checkpoint implementation: Schema1 hashes the complete numeric render packet, including its formerly zero reserved header. The new sector-light field changes that derived digest without changing ordinary game state. Preserve the failed report. Keep Schema1's original zero slots43..47 as a canonical checkpoint representation and separately retain CurrentRenderSnapshotSha256 for the complete current packet. No previously hashed gameplay field is removed: all sector lighting remains in the existing sector array. This is checkpoint compatibility, not ignoring gameplay divergences. Re-run the same complete endpoint/route check on original handle22492; the new packet field remains covered by all-field equality, isolated known-light fixtures and worker tests.

The repeated endpoint test (22492) is terminal with 336 exact packet comparisons, all 3,233 ordinary commands and all 13 legacy checkpoints. Explicit schema controls (19799) are terminal with six checks, including lighting/health negative controls and exact restoration. The live Classic recording (73134) is terminal and passes all 65 capture/integration checks: E1M2/intermission/E1M3 progression, exact checkpoints, expected inventory and all 4,073,580 audio frames returned. It averages 34.980 tics/sec and 56.565 console writes/sec; p95/p99 same-world gaps are 24.258/31.639 ms and the maximum is 199.478 ms. Three software queue-empty observations and one 1,190-frame interior alignment fill remain. No performance speedup, acoustic continuity or 60-display claim is made.

Inspect actual capture frames at 60 seconds, seven seconds before the end, four seconds before the end, and 1.5 seconds before the end: gameplay, intermission, entering-map screen and E1M3 gameplay are present. Keep original footage and review hashes. Owned-window/process absence passes with PID reuse distinguished by start time; no termination necessary. A documentation patch failed atomically on an incorrect snapshot-document heading anchor; reapply the prose without changing runtime sources. Update the roadmap's current M4 status and article with the corrected weapon behavior and limits. All original handles this turn are terminal; the Ultimate Doom release remains incomplete.

## 2026-09-19 — Invisibility and Spectre rendering

Previous goal work is progress: the verified weapon-lighting implementation, tests, and live recording were committed and backed up as 7026f6a; remote equality and private visibility were checked. The intervening user-requested scope review changed no project direction. Continue the full Ultimate Doom release.

Source inspection finds that FastRenderer always draws opaque actor/player sprites and numeric snapshots omit the player's invisibility timer and actor flags. Implement NumericV2 with timer header44 and an appended actor-flag array, preserving positional offsets. Historical Schema1 replay hashes retain their exact old packet representation; new version-tagged render hashes cover the added fields and are compared by replay verification. This does not retroactively give old recordings coverage of flags/powers they never contained.

Implement PowerShell fuzz using vertical framebuffer neighbours and colormap6. The 50-entry table comes from the adopted GPL renderer. A per-column/game-tic phase makes independent strips deterministic; this intentionally differs from original Doom's shared sequential phase. Source-inspect id Software r_draw.c/r_things.c for the operation and precedence; no original source body is copied. Shadow actors trigger far-to-near sprite ordering so background actors exist when sampled. Player fuzz takes precedence over fullbright/fixed lighting and follows the >128 or bit8 blink condition. View borders and the HUD are excluded.

The first edit patch failed atomically on an inexact GameHost anchor; retry succeeded. A later combined fixture/documentation patch also failed atomically on a ledger heading; verify no files existed before retry. A worker-test shell invocation failed parsing before launching; the correctly quoted invocation succeeded. Preserve substantive test failures: checkpoint-fuzz-first.json selected the excluded camera actor as a flags negative control; fix it to select a rendered actor. The original malformed-wire test changed a byte to the now-valid version2; correct its invalid-version probe. These were test-fixture defects, not waived assertions.

Focused results: 111 fuzz checks pass, comparing the adopted column operation under explicit seeds, clipping/scaling/holes/flip/depth, reversed uneven strips, blink thresholds, precedence, animation and negative opaque controls. The eight transport tests pass. All138 prior weapon-lighting cases still match. All three real worker styles pass320,000 pixel comparisons and35 encoded strip checks each, with explicit visible shadow-actor negative controls. All36 maps plus the complete3233-command E1M2 route pass336 byte comparisons and13 original checkpoints (handle19085 terminal). Thirteen checkpoint-schema checks pass after adding enforcement of the version2 digest (58112 terminal). No speed claims from overlapping correctness jobs.

Prepare a dedicated save/replay visual fixture on handle67091: grant invisibility, shorten its timer, spawn a Spectre ahead of the E1M1 camera, then run350 idle commands. The fixture is explicitly not campaign completion or ordinary pickup evidence. Keep saves under ignored local storage and record every live style run. Projection, palette behavior, original global fuzz phase, remaining campaign routes, complete audio, and final performance/release gates remain open.

The first recording-fixture generator used replay version2, which correctly rejects LoadGame; the failed handle67091 is terminal and its local saves remain. Switch the fixture to the existing load-capable replay version3, using fresh save/output paths. Handle95967 succeeds, and headless handle45966 consumes350 commands and matches17 independent checkpoints with sound.

All three first live captures complete on handle21558 with retained original footage. The independent capture audit then catches an important fixture failure: the idle player dies at about tic164, leaving invisibility frozen at46 rather than reaching expiry. Preserve the failed Classic audit and all three movies. The commentary claiming verified expiry before that audit was premature and corrected immediately. Keep damage behavior unchanged; give the next explicit fixture999 player/actor health and assert living expiry before publishing it. This is labeled artificial test setup, not campaign or pickup evidence. New fixture generation42067 succeeds with17 checkpoints; additional overlap/flag tests run on30380 before the next recordings.

All 119 focused checks finish on30380. Corrected live captures run sequentially on82799, which is terminal with all three movies retained. The independent audit passes34 checks per style, including17 full-state/render checkpoints, all441,000 returned audio frames, media decode/source pins and resource absence. Existing replay validation passes58 checks. Classic/Matrix/AnsiArt average34.896/34.894/34.900 tics/sec and23.330/31.405/30.313 image writes/sec. Same-world maxima526.971/582.696/577.342ms remain; no performance win or60-display claim. These figures and audio alignment/queue limits are in rendering-fidelity.md.

Visual review first extracted save-loading screens at sseof-12, corrected samples at sseof-10, and expiry samples at sseof-4. All nine images were inspected; the corrected early images show fuzz instead of the pistol, while late images show the opaque pistol with the Spectre still distorting the scene. Matrix remains particularly dark. Preserve misselected review frames rather than labeling them gameplay. The cleanup/review receipt confirms all six captured windows and all original host/simulation/worker processes are absent, accounting for PID reuse; no termination performed. All original handles from this turn are terminal. Update roadmap, README, article and fidelity/transport docs; the complete Ultimate Doom release remains active and incomplete.

## 2026-09-19 — Profiling the Spectre scene

Previous goal turn is progress: invisibility/Spectre rendering, NumericV2 transport, 119 focused checks and three audited corrected captures were committed/pushed as117551c. Revalidate the clean working tree and current roadmap before further work; no prior jobs remain active.

Analyze the retained second captures: mean per-frame maximum worker rendering time is35.769/25.588/25.568ms for Classic/Matrix/AnsiArt, compared with encoding3.515/3.042/4.701ms and output13.884/10.673/9.901ms. These overlapping phases are not additive. Preserve results/fuzz-recorded-stage-analysis.json. Run a new finite, sequential worker-sized strip profiler on the independently saved Spectre scene at tics0,35,90,210,350 (handle24959 terminal). It identifies geometry as the largest phase, actors second; it does not reproduce concurrency or establish displayed frame rate.

Preserve the previous PowerShell fuzz helper byte-for-byte as scripts/fixtures/FuzzReference.ps1. Candidate optimization computes the identical source-row division/floor once per sprite row instead of once per covered pixel, caches its offset-table reference and texture-column base, and returns immediately for an empty rectangle. Phase sequence, pixel traversal, mask, depth, lighting and dimensions stay the same. Run six alternating old/new repetitions over all five saved states and all sixteen20-column strips on original handle39007. Every paired run compares full indexed pixels and depth; retain cold samples and all phase timings. Do not draw a whole-game speedup conclusion from this microbenchmark.

The paired run39007 is terminal:960 profiled strips,30 full indexed-image/depth comparisons, all exact. Actor means fall from2.894/3.992/3.786/4.427/4.569ms to0.991/0.784/0.775/0.920/0.952ms across the five states. Geometry is unchanged and still dominates at about5.6–6.9ms per strip; its variation remains visible. Keep the optimization with whole-game claims pending actual recorded validation. The focused fuzz and three-style real worker regressions are running sequentially on13033. No concurrent performance workload is running.

While captures run, inspect the next open fidelity path read-only: the adopted Renderer.GetPaletteNumber handles damage, bonus, berserk and radiation-suit color selection, but the terminal worker constructs its codec once from the base palette carried by RenderAssets. The current snapshot has no palette selector. This is a concrete remaining presentation omission, separate from the fixed colormaps already implemented. Carry that finding into the next fidelity work after this optimization is recorded and committed; no palette source or behavior is changed in this milestone.

Correctness handle13033 finishes119 focused checks and all three real worker-mode comparisons. Recorded host handle6962 is terminal with all three original audiovisual files. Each independent capture audit passes34 checks, all17 original full-packet checkpoints and all441,000 audio frames returned. Rates are34.889/34.895/34.882 tics/sec and46.452/41.177/45.346 image writes/sec; same-world maxima520.745/563.280/549.313ms remain. This is whole-host validation, not a controlled causal before/after comparison. No simultaneous benchmark ran during capture. The complete microbenchmark, recordings, queue/alignment limits and reproduction commands are documented in docs/fuzz-performance.md.

Inspect all six actual-window samples at ten and four seconds before recording end: active invisibility and the returned opaque pistol are present in Classic, Matrix and AnsiArt. Preserve their hashes in results/fuzz-row-cache-visual-review.json. The capture audits independently confirm original owned windows/processes absent, accounting for PID reuse; no termination performed. All original handles this turn are terminal. Update README, roadmap, rendering findings and article; keep the Ultimate Doom release active and incomplete.

## 2026-09-19 — Palette presentation integration

The previous implementation goal turn made progress: fuzz-row precomputation, paired pixel/depth evidence, three recordings and private backup completed at195b672. The intervening scope review was read-only and made no implementation progress or direction change. Revalidate the clean worktree, then resume the missing palette path under the full Ultimate Doom release objective.

Confirm id Software ST_doPaletteStuff against the adopted PowerShell Renderer.GetPaletteNumber. Reuse that selector in both snapshot producers and the simulation screen header. NumericV3 adds discrete palette slot45; preserve separately named NumericV2 compatibility hashes and historical Schema1 canonical hashes. Current comparisons include palette selection; older recordings cannot retroactively cover it. World and automap use the gameplay palette; this project's full-screen menus, intermission and finale select base0, with the menu choice an explicit presentation difference.

Transfer complete PLAYPAL in disposable assets-v2. Workers prepare fourteen small style contexts, caching pair strings only as encountered instead of eagerly constructing fourteen complete65,536-entry string tables. Classic uses raw selected RGB; AnsiArt applies its existing style mapping to that RGB; Matrix retains green while selected-palette luminance affects its glyphs and tones. No GPU shader or compiled game algorithm is added. Add palette identity to completed-frame and worker telemetry and pin all changed presentation/transport sources in recordings.

Initial targeted evidence:280 palette checks pass (explicit precedence/boundaries, object/direct packets, discrete interpolation, all fourteen768-byte palettes, exhaustive65,536 Classic pair combinations per palette, character menu/map/HUD equivalence);8 wire,18 checkpoint-compatibility/negative-control and58 replay-format checks pass. Actual worker checks are running on68210; all-map/full-route packet regression on43113. These concurrent correctness jobs are not performance comparisons. Live recorded validation remains pending.

The four worker modes on68210 are terminal and pass320,000 pixels/35 encoded strips each. All-map/full-E1M2 handle43113 is terminal with336 packet comparisons and13 preserved checkpoints across3,233 commands. Fixture generation41757 succeeds with four isolated saves,700 commands,52 V3 checkpoints and eight automap toggles. Headless handle40151 is terminal; its24-check audit validates every presented fixture frame against independently advanced palette/map states, exact saves, complete input and all882,000 audio frames returned. Raw indexed captures now carry matching palette companions.

Begin live recording on90935 with frozen sources. The first Classic launch mistakenly inherits the recorder default12-point font instead of6; this cannot fit the100-row Classic image. Keep its finite100-second run and resulting viewport failure. Correct subsequent invocation parameters rather than changing viewport behavior or suppressing the failed evidence. No simultaneous performance workload runs during captures.

Correction after90935 becomes terminal: the first host actually reachesReplayEnd with700 commands and a688x151 grid. The earlier predicted undersized-font failure was premature and wrong. The recorder rejects the fixture's missing expected Transitions list (four saves legitimately produce four load transitions). Preserve its failed receipt, video and audio capture. Add the initial state and four independently specified load boundaries to the fixture generator; generate a fresh fixture/save root, compare its commands/checkpoints to the original, then retry with explicit font sizes. No runtime source correction is needed for this failure.

Fixture regeneration77527 is terminal. Its700 commands and52 checkpoints match the original exactly; only the missing expected transition metadata is corrected (results/palette-fixture-metadata-correction.json). A brief generator parse error from a missing closing brace occurred before execution and was corrected. Standalone ANSI/Sixel checks and144 character partition cases plus independent probes/guards pass.

The corrected Classic recording on43234 reaches the replay end and passes transition verification, but external capture FFmpeg crashes with0xC0000005 after receiving q during shutdown. Audio recorder exits0; retain the original video, log and audio. This is a confirmed terminal process, not an observation timeout. The first capture's encoder exited0, so perform one bounded retry with unchanged game/capture sources and fresh output prefix; do not waive failed-media checks or claim a completed audiovisual recording.

The first bounded retry succeeds for Classic with encoder0 and a merged audiovisual file; remaining styles are still running on14947. No capture failure is waived. The new review extractor will sample actual movie frames using host QPC and the retained video origin, and records expected state separately from visual inspection. Source review confirms the new palette byte is discrete and checkpoint V2 compatibility clears only that field/version; existing actor flags and invisibility remain hashed.

Classic and Matrix third captures each pass55 independent checks and52 V3 checkpoints; complete movies decode and all882,000 audio frames return. Their tics/writes rates are34.940/58.999 and34.948/59.810; same-world maximum gaps508.240/571.803ms remain. Three queue-empty observations each and1,152/1,158 interior alignment-fill frames remain, with no display/acoustic guarantee. Inspect all ten extracted images using video-origin/QPC selection: actual red damage, bonus automap, late berserk, radiation and restored base images are present; Matrix remains green with greatly reduced strongest-damage contrast. Keep the original videos and review hashes.

Handle14947 is terminal: Classic/Matrix succeed, while AnsiArt again encounters the external FFmpeg0xC0000005 shutdown failure after q. Its game-only audit passes24 checks, all700 commands and52 checkpoints. Do not mark its audiovisual capture qualified. No capture source or game code changed during these runs. Investigate the external recorder teardown before further repeated trials; native tool sources are local/tools/capture-build/FFmpeg-n9.0.1/libavfilter/vsrc_gfxcapture_winrt.cpp and vsrc_gfxcapture.c. No capture-tool change has been made yet.

The user requests a safe point for a pending Codex update. Finish existing headless menu handle22745; it is terminal and passes24 session checks. An initial diagnostic accidentally selected the loading screen as the first menu; selecting MenuScreen1 proves the actual menu at tic16 uses palette0 while gameplay's damage palette is8. Retain results/palette-menu-active-reset.json. Make no new live recording before the update.

Checkpoint cleanup verifies all five captured windows and original runtime processes absent, accounting for PID reuse, and no matching project runtime remains. No termination is needed. Copy raw game/recording reports (including failed runs) into portable results; keep original movies/audio local. Private GitHub visibility remains verified. This turn is implementation progress, not a completed release. Immediate continuation after the update: resolve the recorder shutdown issue and finish AnsiArt palette audiovisual qualification, then projection/fidelity and E1M5/secret routes, full audio and remaining roadmap gates. Keep the full Ultimate Doom goal intact.

## 2026-09-19 — Recorder crash evidence during the update checkpoint

The previous goal turn made implementation progress: palette transport, focused/worker/full-route checks, Classic/Matrix recorded validation and an explicitly incomplete AnsiArt capture are committed/pushed at86b3c17. Revalidate the clean worktree. The user has not yet confirmed the pending Codex update finished; an asynchronous question is pending. Keep work to short read-only inspection and saved diagnostic notes, without starting a build, game, or recording.

Read Windows Application Error events filtered to the exact project ffmpeg.exe. Two events coincident with Classic second and AnsiArt third failures report graphicscapture.dll_unloaded version10.0.26100.9278,0xc0000005 at offset0x1115c. Preserve event messages/UTC times/record IDs and binary/source hashes in results/capture-shutdown-windows-events-first.json. Source inspection finds the existing deliberate graphicscapture.dll load to avoid WinRT-unload crashes; context destruction eventually releases its owning module handle. This strengthens a module-lifetime hypothesis but does not establish the exact callback ordering without a trace.

Document the next experiment in docs/capture-shutdown.md: preserve the baseline, pin the already-loaded capture DLL within a separate candidate recorder process, then run repeated finite shutdown tests and the outstanding AnsiArt replay after the update. Microsoft's GetModuleHandleExW documentation confirms process-lifetime pin semantics. No game algorithm, native capture source, binary, security setting, or runtime process is changed. This turn yields evidence that changes the next diagnostic action; the full release remains active and incomplete.

## 2026-09-19 — Explicit resume and recorder lifetime experiment

The user explicitly resumed after the Codex update; verify the full release goal active and resume implementation. Preserve the original recorder/source intact and extract a separate candidate from the verified FFmpeg archive. Extend Build-CaptureFfmpeg with a guarded optional process-lifetime graphicscapture.dll pin, identifying the existing module by mapped address and logging success/failure. This is external diagnostic tooling; engine, rendering, encoding and mixing remain PowerShell.

The candidate builds successfully in117.645seconds using the installed Visual Studio18.10 toolchain. Preparation/build receipts pin original archive, unchanged baseline, candidate source/binary and recipe. Start twelve finite owned-window lifecycle trials alternating explicit q and target closure, retaining movies, logs, hashes, full decoding and cleanup. A successful build or short trial alone cannot prove an intermittent fault fixed; full AnsiArt audiovisual qualification is still required.

Candidate and baseline each pass all twelve short lifecycle trials (six explicit quits, six target closures), full movie decoding and target cleanup. The candidate confirms module pinning in every log. The short workload does not reproduce the historical fault, so these results cannot establish causality or a proven fix. The new build also uses the updated18.10 toolchain. Begin full AnsiArt fixture capture with the candidate on80702, with sources frozen; do not run competing heavy jobs during this recorded trial.

Full AnsiArt candidate capture80702 is terminal and passes55 checks, all700 commands/52 checkpoints, all882,000 returned audio frames, full media decoding and owned-resource cleanup. Inspect all five extracted movie frames: intended tint states and base restoration are present; strongest damage obscures much scene/HUD contrast and surrounding margins remain. Measured34.937tics/55.051writes per active second, same-world p95/max27.284/550.397ms, all-gap max3.010s, three empty queues and1,114 interior alignment-fill frames remain. Preserve these limits.

The user correctly challenged the recorder investigation's priority. Disposition: could not reproduce in follow-up trials; cause unconfirmed. Keep the optional mitigation and historical failures, but stop treating external recorder reliability as a blocker for engine development. One repeat game recording was already running on11720 when this steering arrived; allow its finite shutdown/audit, start no further recorder trials. Next work returns to campaign progression and concrete rendering defects. The full Ultimate Doom goal remains active; no new permission or resume is required.

Repeat11720 is terminal and passes55 integrity checks and all882,000 audio frames returned, but falls to22.898tics/25.384writes per active second. Same-world p95/max113.792/714.486ms, all-gap max5.895s,63 empty queues and66,025 interior alignment-fill frames are explicitly retained. No unexplained slowdown is dismissed as a capture-only problem or certified playable. All owned resources pass cleanup. No further recorder trial is started. Copy original game/recording reports for both runs into tracked results and retain media locally. Return to actual renderer/performance investigation; automated routing is a repeatability tool, not a substitute for game development or physical play.

## 2026-09-19 — Ship a playable preview

The user redirects work to a deliverable after substantial usage and authorizes moving toward a public repository once something ships. Full Ultimate Doom certification remains future work, not a blocker for an honestly labeled preview. No further recordings are authorized before delivery; no recording runs after this instruction.

Add Play.cmd/Play.ps1 with a style chooser, Ultimate Doom IWAD/prerequisite checks, automatic common Steam/local WAD discovery, a maximized game window and sound effects enabled by default. Preserve the advanced Start-Doom entry point. Replace the research-heavy landing README with quick-start/controls/features/limits and retain its detail in docs/development-guide.md. Add preview notes, changelog, credits and source-inclusive packaging with per-file hashes; exclude local assets, tools, large measurement results and media. The first ZIP contains505 files and is about1.3MB.

Extract the ZIP into a fresh folder containing spaces. Verify every manifest hash and excluded content, successful requirements checking, and actionable rejection of an add-on PWAD. Launch Classic, Matrix and AnsiArt from the extracted Play.cmd for six seconds each, with effects enabled and no screen/audio recordings. Each advances209 tics and completes274/331/310 writes at688x151/430x85/430x85 grids, with no viewport pauses, host errors or audio cleanup errors. Audio device closes; duration-based exit retains the reported unreturned tail rather than claiming complete playback. No packaged runtime processes remain. These are launch checks, not physical gameplay, a performance benchmark or campaign completion.

Scan all2,021 reachable historical Git blob versions (515,655,455bytes) for declared credential patterns and prohibited asset signatures/extensions: no findings. Research metadata still contains local usernames/paths and timing/process details. This bounded scan is not a guarantee against every possible secret. Existing GPL notices, attribution and full source are included; commercial game data remains user-supplied.

After documentation and publication, the user requests X-ready audiovisual assets showing Matrix, color-art and Classic. Produce a comparison clip plus separate clips, using existing legitimate captured footage where suitable. Check X's official current specifications; do not post to X without explicit authorization. This request does not move new recording ahead of shipping.

Publication complete: repository is PUBLIC; prerelease v0.1.0-preview.1 targets3ab1cc80ab7873268997b99978371f5246f8bc46. The first upload returned404 during the visibility transition and left an empty draft. Inspect that draft, upload the two assets, then publish the existing release; no duplicate created. Anonymous ZIP download verifies1,306,297bytes and SHA2564C94C8DC37D4A2487AFDF2096117F0AEBC9C86044FEB72FB48E35BD5D044B02F. Final package runtime/engine hashes equal the fresh-folder-tested source; Play.cmd's exit-code preservation receives a final no-game prerequisite check. No further map runs are performed.

After publication, fulfill the user's X-assets request entirely from existing audiovisual gameplay. Export three30-second labeled1080p30 H.264/AAC clips and a90.021-second combined movie, Matrix then color then Classic. Crop empty margins while preserving gameplay speed/colors, scale/pad, and apply120ms audio fades at cut boundaries. Existing full source movies remain unchanged. Full decode and non-silent stereo audio checks pass; inspect all three final frames. The combined movie is132,384,922bytes and11.765Mbps average, below X's published140-second/512MB conservative bounds and25Mbps limit; configured video ceiling12Mbps. Record source/time/crop/output hashes in results/preview-social-assets-first.json. Sources are older development playthroughs with separately prepared music, not an assertion of bundled quick-start music or exact release-build footage. No content is posted to X, and no media is committed to the public repository.

## 2026-09-19 — Finish transparent-wall fix; stop repeated effect checks

Previous goal work made progress by implementing the masked-wall fix and gathering distinguishing evidence. The intervening answer to the user's loop concern was status-only (no progress). Revalidate the actual worktree and poll the same reference-comparison session 71636: terminal exit 0, three comparisons complete. No restart, new game window, recording or palette-fade trial.

Review the renderer change: queue visible two-sided masked texture columns, fill opaque scenery, then depth-test masked texels before actor rendering. Fourteen focused checks pass; the unchanged old renderer fails the same test at its first fence pixel. Existing 119 fuzz checks and seven-process Matrix equivalence pass (320,000 pixels, 35 encoded strips). Preserve failed test-development receipts and the rejected first reference invocation alongside final results. Reference images still differ substantially; no original fidelity or performance claim follows. Document the concrete game fix in rendering-fidelity, roadmap and changelog. The public preview remains available and unchanged; full Ultimate Doom release qualification remains incomplete.

## 2026-09-19 — Bounded E1M5 campaign investigation

Previous goal turn is progress: masked-wall source, evidence and documentation committed and pushed as aa58dd7, with clean worktree and matching remote. Inspect the retained seventh E1M5 failure before the next trial. It shows low-health combat before medkit collection, not proof of an engine defect. One new complete route trial enables the already implemented combat-strafe option with unchanged ordinary-input waypoints and HMP pistol start. Session 58747 finishes exit 1 after 6,592 commands: player dies earlier in western sector 19's damaging pit. Reject this strategy for the route and preserve the result. An earlier invocation selected a planning segment accidentally; it failed before map initialization and created no receipt. No live window, recorder or effect test was run, and no game algorithm was changed. Update campaign investigation/matrix; do not rerun the same strategy or claim completion. Full release goal remains active.

## 2026-09-19 — Qualify boss-triggered progression

Previous goal turn is progress: bounded E1M5 evidence rejected blanket strafing and was committed/pushed as c0f20d1. Revalidate a clean worktree. Move to a distinct unresolved campaign gate instead of another route retry. Inspect actual BossDeath, death-state dispatch, floor/door movers and id Software's published A_BossDeath source. Add one focused real-map behavioral test for E1M8/E2M8/E3M8/E4M6/E4M8. All 97 checks pass on first execution (session 43274, terminal exit 0). No engine change required.

Each fixture tests wrong actor/map, absence of a living player and another living same-type boss. Positive cases enter the actual final death state, then verify normal exit or tag-666 mover parameters and completion against independently derived neighboring geometry. Explicit health/type/map edits and a synthetic guard thinker mean this is not ordinary gameplay completion; document that boundary and leave map-completion claims unchanged. No live window, recording or palette check. The full release goal remains active, with ordinary boss combat, campaign continuity, secret routes, audio and pacing qualification still open.

## 2026-09-19 — Human-recorded demo inputs expose a missile gameplay crash

Previous goal turn is progress: all five Ultimate Doom boss-trigger cases qualified in explicit behavioral fixtures and pushed as 6dc5631. Revalidate clean worktree. Investigate built-in vanilla demos as a bounded source of real combat input instead of more waypoint-bot tuning. Confirm external-file Demo construction fails because it calls nonexistent this.new; share initialization between byte and file constructors. Nineteen checks pass, including signed input boundaries and all commands/options from three installed demos. No malformed-input or synchronization guarantee.

DEMO1 enters E1M5 and throws after 687 completed commands in ThingMovement.XYMovement: missile sky handling reads nonexistent Map.SkyFlatNumber. Correct to Map.Flats.SkyFlatNumber. Identical input now executes all 1,710 commands; all 19 retained pre-crash samples match. It observes player death at 1,632, so do not claim a successful route or original-engine synchronization. One distinct built-in E2M2 demo then executes 2,347 commands without exception or death. Retain reports and source hashes. Both sessions are terminal (15243 failed; 9165 and 35330 successful). Add only a modification comment after testing; executable source remains as tested.

No game windows, recordings or world-state edits. Demo data stays local. Document the two source fixes, attribution and limits; no launcher demo support or full campaign claim. Full release goal remains active. Before relying on external completion demos, compare original-engine state; further bot tuning is not needed to reproduce this fixed gameplay crash.

## 2026-09-19 — Package the gameplay fixes as preview 2

Previous goal turn is progress: missile sky collision and external demo file construction fixed and pushed as dc4a617. Revalidate clean source state. The remaining built-in DEMO3 executes all 3,863 commands on E3M5 without exceptions; first death is 3,822, not evidence of original synchronization. Session 68346 is terminal exit 0. A bounded source inspection finds no second Map.SkyFlatNumber access or remaining this.new constructor call; this is not a comprehensive property audit.

Prepare 0.1.0-preview.2 to deliver the three confirmed source fixes (masked walls, missile collision, external demo constructor), with boss-trigger and demo evidence documented. Keep earlier preview intact and full release scope unchanged. Update launcher documentation/version and package default. Packaging verification will extract to a fresh folder, verify every source hash and asset exclusions, and run prerequisites only. Existing targeted checks support the changes; no new recording or live launch is planned for this patch package.

Preview 2 published: https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.2 targets clean c69e41c35213377f36d5c9a6747cef648be34489. Source ZIP has512 manifest files,1,326,433bytes and SHA2564783AC6778CEC2A281857CA53FE34369E3EE591B4E70B0153B70E6BA0F6C50CF. Fresh extraction verifies all hashes/excluded content and Play.ps1 -Check succeeds. First prerequisite invocation misused native -Command argument forwarding; correct the invocation on the same extracted package, no source change or game launch. Publication is a non-draft prerelease with ZIP/checksum assets. Anonymous download independently matches the verified local ZIP. Receipts: results/preview-package-second.json and results/preview-publication-second.json. Earlier preview remains published; the full release goal remains incomplete.

## 2026-09-19 — Normal-launcher music option and Episode 1 preparation

Previous goal turn is progress: preview 2 published and its anonymous ZIP verified, receipts pushed as4149510. Revalidate clean worktree. Audio inspection confirms prepared catalogs are supported only through the advanced launcher and missing requested tracks intentionally fail rather than substitute music. Add explicit Play.ps1 -MusicCatalog forwarding, reject -Silent conflict, reject missing files, and label -Check as path-only rather than content validation. Existing startup performs actual qualification/WAD validation. Verify exact launcher copy against a stub Start-Doom (no game launch), both rejection paths, and actual path-only preflight; results/launcher-music-first.json passes.

Start finite Episode 1 preparation on original session3264 using the verified seven-track catalog, adding D_E1M6/D_E1M7/D_E1M8/D_VICTOR. Revalidate all seven existing tracks successfully. E1M6's independent eight-second opening render completes; full three-period qualification is running on the same live handle. Requested output catalog local/music-prepared-episode1.json is not yet published. Final receipt will be results/music-preparation-episode1-first.json. About305GB free before starting. Keep pinned synthesis sources unchanged; do not restart based on files/lock presence or observation timeout. No terminal/game window, recording or live audio playback is launched. This soundtrack step does not narrow the full Ultimate Doom goal.

## 2026-09-26 — Continue the actual E1M4 campaign state into E1M5

Resume from repository evidence. The working tree contained an unfinished `-StartingReplay` change in `scripts/Test-CampaignRoute.ps1`. Strengthen it to compare the complete recorded destination checkpoint (including the render snapshot), then use the qualified `results/e1m4-qualified-replay.json` to start the documented E1M5 route. PowerShell parsing passes. The route replays 6,348 prior commands, verifies E1M5 entry, then issues 7,442 ordinary route commands and dies at waypoint316/414. Preserve the failed receipt at `results/e1m5-continuation-candidate1.json` rather than treating earlier progress as completion.

Extend `scripts/Inspect-CampaignFailure.ps1` to reconstruct a qualified campaign continuation and verify its checkpoint before replaying only the failed map suffix. The failure receipt independently reproduces all 212 route samples. Damage is recorded at suffix commands7345,7421 and7442 from attacker type Troop, ending at zero health/armor. The final actor inventory includes nearby Troopshot projectiles but cannot identify the projectile responsible for a specific hit; this remains a route failure, not evidence of an engine defect. Update the E1M5 investigation, campaign matrix and roadmap with the unresolved outcome. The user's newly available JEV is not exposed in this task's connected tool/app inventory; continue without it until an interface is available. No recording or video harness was run.

## 2026-09-26 — Prepare one complete Episode 1 human playthrough

The user explicitly steers the next milestone to one complete human Episode 1
playthrough, not Ultimate Doom release completion and not map-by-map user
tests. Use the documented human-evidence option. Stop bot/waypoint route work;
retain qualified E1M1–E1M4 route inputs as regressions, and use focused checks
for mechanics and reproducible defects. Preserve the broader Ultimate Doom,
Doom II, and MyHouse roadmap.

The required human path is E1M1 -> E1M2 -> E1M3 secret exit -> E1M9 -> E1M4
through E1M8 -> Episode 1 finale. Its instructions, controls, prerequisites,
and single-result reporting path are in `docs/episode1-playtest.md`. The latest
E1M5 continuation failure is already documented: death at waypoint 316/414,
with a matching suffix trace and no reproducible engine defect. Do not retry
or reinterpret that route failure as product evidence.

Current focused checks on the installed Ultimate Doom IWAD
`6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F` pass:
all nine Episode 1 maps load, run 35 idle tics, and render two 320x200 frames;
57 episode/secret/return/finale transition checks pass; 97 boss-trigger checks
pass, including E1M8's tagged floor; and 125 menu/session checks with 46 screen
fixtures pass. A separate fresh synthetic input receipt passes six field/key
state checks and explicitly says desktop input was not injected. These are
readiness checks, not map completions or human keyboard evidence. No live game
window, gameplay recording, or bot route was run for this milestone.

The soundtrack batch reused its seven qualified tracks and completed three-period loop and reader qualification for D_E1M6, D_E1M7 and D_E1M8. D_VICTOR's independent eight-second opening passed, but the full three-period loop was still rendering. Because full soundtrack qualification is an M3 gate, not a prerequisite for normal Episode 1 gameplay, stop that long batch and finish the playtest handoff with `-Sound` effects enabled and no `-MusicCatalog`. This assumes missing background music is an acceptable limitation for this focused gameplay milestone; record it plainly and keep the full music gate open. The preparation lock released, no atomic catalog was published, and verified/partial reports remain under ignored `local/` for a later resume. Copy the successful D_E1M6/D_E1M7/D_E1M8 qualification JSON into tracked `results/`. `Play.ps1 -Check` then passes with the exact Steam IWAD, 36 maps, PowerShell 7.6.5 and Windows Terminal, in effects-only mode; this is path/prerequisite validation and launches no game window. The launch destination paths are clear. No synthesis or game source was changed.

## 2026-09-26 — Resume the full Episode 1 music catalog

The prior interruption was the earlier playtest-focused scoping choice, not a
project blocker. The full release goal remains active, so resume the preserved
atomic preparation job rather than leave the playable build effects-only. First
verify no game session or music-preparation process is active, confirm the lock
is released, and confirm the seven-track catalog plus the D_E1M6/D_E1M7/D_E1M8
qualification receipts exist. The resumed invocation validates/reuses all ten
tracks and runs only the missing D_VICTOR qualification; it is active on
session 15715. Do not restart it on an observation timeout.

Extend `scripts/Test-MusicEvents.ps1` with an Episode 1 finale assertion that
selects D_VICTOR. The focused event suite passes all 12 checks on the installed
IWAD, with no game window or device playback. This verifies track selection,
not audible finale playback or full-session continuity.

## 2026-09-26 — Fix sight-intercept zero comparison

While keeping E1M1–E1M4's existing fixed inputs as regressions, a direct test
of `VisibilityCheck.InterceptVector` reproduced an incorrect denominator-zero
result for parallel separated lines: `Int32.MinValue` instead of zero. The
PowerShell comparison was applied to distinct `[Fixed]` wrapper objects, not
their numeric `.Data` values. Change the guard to compare `.Data`; retain the
before/after receipts and focused test. Parallel lines now return zero and a
perpendicular halfway crossing returns 32768.

All four existing routes pass independent post-fix replay through their
expected campaign transitions: E1M1 -> E1M2 (1,747 commands, 8 checkpoints),
E1M2 -> E1M3 (3,233 commands, 87 samples, 13 checkpoints), E1M3 -> E1M4
(7,118 commands, 198 samples, 24 checkpoints), and E1M4 -> E1M5 (6,348
commands, 176 samples, 22 checkpoints). The first E1M1 adapter attempt omitted
the route's final-health field; after adding it, the same stored route passes.
This was an adapter correction, not a game defect or a reason to develop new
routes. The post-fix nine-map Episode 1 smoke also passes: all maps load, run 35
idle tics, and rasterize two 320x200 frames. The [compact regression index](../results/visibility-campaign-regressions.json) pins the pass and raw-report hashes. An initial invocation passed a
comma-separated map list as one literal PowerShell argument; it stopped before
any map loaded, and the corrected array invocation passed all nine. The failed
invocation is retained under ignored `local/visibility-intercept-regressions/`.
No window, recorder, or bot route was used. The
D_VICTOR full-loop qualification remains in progress separately.

## 2026-09-26 — Complete Episode 1 music and revalidate the handoff

Resumed the preserved atomic preparation job and completed the eleven-track
Episode 1 catalog: D_E1M1, D_INTER, D_E1M2–D_E1M9, and D_VICTOR. The catalog
is local at `local/music-prepared-episode1.json`, hash
`0E9C9542C75F4D5E2D7FC71E42FAFBB58F94321C3B8A49BA0C9AC5A93752EE58`; the
qualification batch synthesized 2,032.318 score seconds. The original pinned
synthesis/runtime sources and exact installed Steam IWAD were revalidated.

D_VICTOR passed three-period state and float-output recurrence over 25,401,600
frames (576 seconds). Its recurring period is 8,467,200 frames, with 62 voices
and state SHA-256
`433B5A35950B12F1FD3E9192E3281850988965194B05A25604C46B82DE74633D`. Its
eight-second opening reference is exact, and the independent long-track reader
suite passes all six checks. Portable qualification, opening-reference and
reader receipts are in `results/music-loop-dvictor-prepared.json`,
`results/music-loop-dvictor-opening-reference.json`, and
`results/music-loop-dvictor-reader-first.json`.

With the complete catalog, the actual simulation/audio worker passes 15
save/load/new-game checks on Episode 1, returns 97,020 music frames, reports no
audio error and closes the device. `Play.ps1 -Check` also confirms Windows
Terminal, PowerShell 7.6.5, all 36 IWAD maps, and the catalog path; its music
content validation is path-only, so the worker test is separate. The exact
preflight and worker receipts are tracked. A fresh transition suite passes all
57 fixtures, including E1M9/secret-history/finale cases. The focused visibility
correction, four old route regressions and nine-map Episode 1 smoke are pinned
in the prior commit's regression index.

The handoff at that point named source commit
`9b5a7b45f9b5d299f8f1bbebc866abc84eee30a4` with the full catalog enabled. It
has since been refreshed to the renderer source and revalidated, as recorded
below. Jason's one complete playthrough remains pending. Neither uninterrupted
campaign audio nor 35-tic/60-display pacing, audible review of every track,
vanilla fidelity, or the broader release gates is established by these bounded
checks.

## 2026-09-26 — Extend renderer comparisons to E1M2 and E1M3

While the full human Episode 1 run remains pending, extend M4 with the existing
same-endpoint reference harness, not a new route driver. Against the same
installed IWAD and unchanged engine bundle, compare E1M2 and E1M3 map starts
after 35 idle updates at headings 0/90/180, then repeat each with fixed
colormap 16 on both renderers. All four reports use bundle SHA-256
`61F6C9B2E6CE5B2316A363B81436A241ACEEF2B962B2CB4125596AD9DEA9BAE0`, record
no source mutation, and produce exact HUD indices.

Baseline scene-index differences per 53,760 pixels are E1M2 13,377 / 19,024 /
14,238 and E1M3 19,434 / 17,458 / 18,440. With fixed colormap 16 they become
10,326 / 14,553 / 10,514 and 14,134 / 13,068 / 14,125. The fixed control
changes palette lookup, so its improvement cannot be attributed mathematically
to lighting alone. The residual 19.2–27.1% index difference is substantial,
while mean absolute RGB-channel error is 2.01–3.90 levels. These are static
map-start views against the adopted PowerShell reference, not ordinary
gameplay, route, performance, or original-executable evidence. Four raw reports
and a source/hash index are tracked; PNGs remain under ignored `local/`.

At that time, no render algorithm changed. The next M4 investigation was
horizontal wall/plane sampling against the reference's fixed-point per-column
path. Keep the human playthrough pending as a single user milestone; no
map-by-map user request or bot route was run.

## 2026-09-26 — Match horizontal samples to Doom's integer columns

Source inspection found that the adopted renderer chooses each camera ray from
`xToAngle[x]`, while the numeric renderer sampled wall perspective
interpolation, screen rays, and flat U/V at `x+0.5`. At column 160 the
reference angle is zero; the former half-pixel analytic ray is about -0.18
degrees. Change those four horizontal samples to integer column `x`. Keep pixel
coverage and vertical sampling unchanged.

Use the same installed Ultimate Doom IWAD, pinned engine bundle, 35-idle-update
endpoints, headings 0/90/180, and E1M2/E1M3 states as the prior comparison.
Scene-index mismatches per 53,760 pixels fall from 13,377/19,024/14,238 to
8,490/12,695/10,264 on E1M2, and 19,434/17,458/18,440 to
13,014/9,564/11,511 on E1M3. Across all 322,560 pixels, this is 101,971 to
65,538 differences (35.73% fewer); RGB-channel MAE decreases in every view and
all HUD comparisons remain exact. Residual scene disagreement is 17.8–23.6%.
The adopted PowerShell renderer is not independently verified original-engine
output, and these static views do not establish navigation, full fidelity, or
performance. Raw report hashes and the combined table are in
`results/render-column-index-fidelity.json`.

The production source passes actual seven-strip worker equivalence in Classic,
Matrix/Katakana, and AnsiArt/Katakana: 320,000 pixels and 35 encoded strips per
style. A previously stored E1M1 fixed-input replay also passes through the
headless host: 1,747 commands, eight matching checkpoints, and E1M2 entry. This
is a replay regression, not human coverage or displayed-FPS evidence. The
attempted requalification that supplied an already-qualified replay to the
route-driver qualifier is not counted; it reached E1M2 but lacked that
qualifier's driver trace/final-health fields. The full-host replay report is
retained locally and its hash is indexed in the combined result. Preserve the
user's single complete Episode 1 run as the pending human milestone.

## 2026-09-26 — Refresh Episode 1 readiness on the renderer source

After the integer-column renderer correction, rerun the Episode 1 readiness
checks on source commit `4e66cd36fe2f9f54c5a9e7e9bc7519e152289664`. At skill 3,
all nine E1 maps load, advance 35 idle tics, and render two complete frames.
The current source also passes 57 transition/finale fixtures, 97 boss-trigger
checks, 125 menu/session checks with 46 screen fixtures, and six synthetic
console-input checks. The transition fixtures include E1M3's secret destination,
E1M9's return to E1M4, intermission progression, the Episode 1 finale, and
inventory/death handling. The boss checks include E1M8's tagged floor trigger.

The five raw reports and updated machine-readable readiness index are tracked
under `results/episode1-playtest-*current.*`. Their hashes are listed in
`results/episode1-playtest-readiness.json`, which now pins the renderer source
commit while keeping `HumanPlaythrough.Status=Pending`. Physical input and the
single complete human route remain Jason's playtest; focused fixtures and map
smoke do not claim campaign completion. The exact IWAD and prepared music
catalog were rechecked against their readiness hashes. The renderer comparison
and limits remain separately recorded in
`results/render-column-index-fidelity.json`.

## 2026-09-26 — Align vertical wall texels to integer rows

Inspection of `ThreeDRenderer.DrawColumnData` showed that it seeds a wall
column's texture fraction at `(y1 - centerY) * invScale`. The numeric renderer
sampled opaque and masked wall texels at `y+0.5`; change both to `y`. Keep plane
mapping at half-row centers because the reference's `ResetPlaneRendering`
explicitly adds one half. No simulation, HUD, sprite or weapon sampling changed.

An isolated candidate improves all six E1M2/E1M3 static views after the prior
integer-column correction. Differing indices fall from 8,490/12,695/10,264 to
7,189/8,343/6,644 on E1M2 and 13,014/9,564/11,511 to 8,378/5,153/7,043 on
E1M3. Every HUD remains exact and RGB-channel MAE decreases in all six. Across
322,560 scene pixels, the cumulative comparison improves from 101,971 to
42,750 differing indices (58.08% fewer than the original renderer baseline);
9.59–15.58% remain different. The same adopted PowerShell reference and IWAD
are used, so this is not independent original-executable evidence.

The first isolated-comparison invocation failed before rendering because the
candidate lived outside `src/`, while its shared `RenderLighting.ps1` import is
resolved relative to its own `$PSScriptRoot`. Rerunning from a temporary source
path and then with the production file succeeded; the failed invocation is a
harness path issue, not a product failure. The production comparison receipts
report no source changes during their runs.

After adoption, actual seven-process rendering matches serial output across
five views in Classic, Matrix/Katakana and AnsiArt/Katakana: 320,000 pixels and
35 encoded strips per style. A fresh skill-3 Episode 1 smoke passes all nine
maps with 35 idle tics and two full frames per map. Raw comparisons, worker
reports, smoke results, hashes and limits are in
`results/render-integer-row-fidelity.json`. This smoke is not map completion;
Jason's single complete Episode 1 playthrough remains pending.

## 2026-09-26 — Pin the revised Episode 1 handoff

The exact engine source baseline is now commit
`4311cc619eefd1246fcaa7f13332d8330e3f5a5f`. The current-source nine-map
smoke, renderer comparisons, all three worker-style reports, and actual
sixteen-process E1M1-to-E1M2 asset reload are indexed in the readiness receipt.
The stored replay has eight matching checkpoints but an older source
fingerprint, and wrote no terminal frames. The focused transition, boss,
menu/session and synthetic input checks remain valid: the renderer-only
change did not modify their simulation or UI dependencies. The handoff retains
one whole-episode human run as pending and makes no campaign-completion,
physical-keyboard, or displayed-FPS claim.

## 2026-09-26 — Fixed-point planes across render strips

I replaced continuous-double floor/ceiling texture mapping with the adopted
engine's fixed-point row slopes, fine-angle rays, distance scales, and
horizontal span steps. A first full-width comparison looked better, but an
early worker test showed the independent processes restarted a span at their
own left edges. The initial serial and worker spans therefore used different
fixed-point phases. One attempted per-column formula restored exact worker
output but erased the fidelity improvement. The retained design gives the
serial comparison path the same strip boundaries used by its worker pool and
starts each span at each strip edge. The asset transport now carries the
lookup tables and strip boundaries in format v4; an empty boundary list is
valid for the real simulation-created asset file.

With sixteen Classic strip boundaries, scene disagreement against the adopted
PowerShell reference falls from 42,750 to 37,798 of 322,560 pixels (11.58%
fewer); all six HUDs stay exact. Actual sixteen-process output is byte/pixel
exact with serial output for Classic, Matrix/Katakana, and AnsiArt/Katakana:
320,000 indices and 80 encoded strips per style across five E1M1 headings.
The current-source skill-3 smoke passes all nine Episode 1 maps. A headless
replay of the stored 1,747-command E1M1 route matches its eight available
checkpoints, reloads E1M2 assets in the same sixteen workers, and finishes at
34.97 simulation tics/sec and 59.18 scheduled render updates/sec. It wrote no
terminal frames, so those rates do not certify displayed FPS. Its map reload
paused output for 1.91 seconds.

The corrected alternating serial timings show median render time rising from
46.48 to 51.35 ms on E1M2 and from 43.46 to 46.07 ms on E1M3; p95 changes from
101.65 to 94.95 ms and 71.46 to 72.01 ms. These are single-process full-frame
measurements, not worker end-to-end or display timings. An earlier pair of
timing receipts was rejected when its baseline and candidate hashes proved
identical; the corrected reports pin different hashes and no source changes
during measurement. Results, parameters, and limits are indexed in
[`rendering-fidelity.md`](rendering-fidelity.md). This does not change the
pending human Episode 1 playthrough.

## 2026-09-26 — Refresh the one-run Episode 1 handoff

The launch handoff now pins engine/source commit
`4311cc619eefd1246fcaa7f13332d8330e3f5a5f`, uses the tested Steam Ultimate
Doom IWAD and locally prepared Episode 1 music catalog, and requests one
complete E1M1 → E1M8 human playthrough including E1M3's E1M9 secret route and
return, ending at the Episode 1 finale. Jason's result remains pending; no
individual map test is requested. The full route's display, sound continuity,
and human controls remain to be reported from that single playthrough.

## 2026-09-26 — Match projected sprite columns to Doom's fixed-point stepping

The numeric patch drawer used `Ceiling(left)` and derived each texture column
from the fractional projected edge. The adopted renderer floors the projected
left edge and advances the source fraction from that integer screen column.
`Draw-FastPatch` now uses floor-based coverage and an accumulated 16.16 inverse
scale, with a signed step for flipped patches and advancement for clipped
worker strips.

A current-source E1M1 pistol fixture compares weapon-visible and weapon-hidden
frames at seven fractional X offsets. The old renderer differed in 6,483 final
pixels in the union of changed weapon coverage; the corrected output matches at
all seven offsets. This accounting checks final pixels because contributor
masks can mistake a weapon texel equal to its background for transparency.
Ten static E1M1/E1M2 views at five headings improve against the adopted
PowerShell reference from 40,632 to 39,098 differing scene indices; all HUDs
remain exact. It is not original-executable ground truth.

All 36 Ultimate Doom maps pass the current-source skill-3, 35-idle-tic smoke
with two full rasterizations and sixteen worker strips. Actual 16-process
output matches serial pixels and encoded strips in Classic, Matrix/Katakana,
and AnsiArt/Katakana across five E1M1 views each. The 138-case weapon-lighting
suite passes. The paired serial measurements have 20 calls per version/map;
median full-frame times rise from 44.96 to 46.29 ms on E1M1 and 39.35 to 39.51
ms on E1M2. This is a measured fidelity fix, not a speedup. Exact commands,
source hashes, timing samples and caveats are in
[`rendering-fidelity.md`](rendering-fidelity.md) and
[`weapon-projection-sampling-comparison.json`](../results/weapon-projection-sampling-comparison.json).

## 2026-09-26 — Check first-person weapon vertical sampling

The focused E1M1 weapon-overlay comparison was repeated at seven fractional Y
offsets (-0.75 through +0.75 pixels) against the adopted PowerShell reference.
All seven final-pixel comparisons pass, so no scale-1 weapon-Y correction is
indicated. This result does not cover perspective-scaled actor sprites, masked
post boundaries at changing scales, or original-executable parity. The
[harness](../scripts/Compare-WeaponPatchVerticalSampling.ps1) and
[receipt](../results/weapon-projection-vertical-offsets.json) retain its
source and IWAD hashes.

## 2026-09-26 — Measure a live Classic E1M1 host session

A current-source, 28-second scripted E1M1 run used the normal Windows Terminal
launcher with 16 workers, sound effects, and the prepared D_E1M1 catalog. It
advanced 979 simulation tics and completed 1,671 terminal updates (59.67/sec),
at 34.959 simulation tics/sec. The p95 terminal-completion interval was 23.09
ms; p95 render-to-write latency was 34.90 ms. This is useful live-host evidence,
not displayed-FPS or campaign evidence. The mixer closed without a reported
device error or audio backpressure; one queue-starvation observation occurred
after packet 978, and no acoustic review was performed.

PresentMon 2.6.0 is installed, but its CLI could not start ETW because the
account lacks administrative or Performance Log Users access. No security
settings were changed. The full limitation, exact workload and measurements
are in [`performance.md`](performance.md) and
[`live-e1m1-classic-host-20260926.json`](../results/live-e1m1-classic-host-20260926.json);
the raw host report remains in ignored `local/`.

## 2026-09-26 — Recheck the complete Episode 1 human-playthrough handoff

The user explicitly sets one complete human Episode 1 playthrough as the next
qualification milestone, including E1M3's secret exit, E1M9 completion and
return to E1M4, E1M8's boss-triggered exit, and the finale. Do not ask for
map-by-map tests or resume route construction. Keep the full Ultimate Doom,
Doom II, Final Doom, and later MyHouse roadmap intact.

From checkout `cdc59a9280fd649638a869210beb799c92cd49ec` (engine/render source
baseline `6b229ccefaa2012626fa2c184ad1d4fff6c3e811`), `Play.ps1 -Check` reports
ready with the installed Steam IWAD, PowerShell 7.6.5, Windows Terminal, 36
IWAD maps, and the local eleven-track catalog. The catalog hash remains
`0E9C9542C75F4D5E2D7FC71E42FAFBB58F94321C3B8A49BA0C9AC5A93752EE58`; its
actual simulation/audio-worker qualification is separate and passes 15
save/load/new-game checks with 97,020 music frames and clean device shutdown.
No user settings file existed at preflight, so startup defaults are Always Run
off, turn speed 100%, volume 100%, and unmuted.

Fresh focused checks pass 295 assertions: 57 campaign/secret-return/finale
fixtures, 97 HMP boss-trigger checks, six synthetic console-input checks, ten
menu-key checks, and 125 menu/session checks with 46 screen fixtures. These
exercise transitions and controller/session behavior, not ordinary navigation
through the maps. The [portable receipt](../results/episode1-playtest-final-checks.json)
records evidence sources and limits. The current 36-map smoke and four stored
E1M1–E1M4 route regressions remain in their separate receipts. No full human
Episode 1 route or physical keyboard use is claimed. The handoff now asks for
one run from E1M1 through the E1M3 secret-map return, E1M8 exit, and Episode 1
finale; record Jason's result only as he reports it.

Update `episode1-playtest.md`, the campaign matrix, and the development guide
to agree on the complete music catalog and current verification. No game or
renderer source changed during this handoff pass. The next campaign evidence
is Jason's single complete human route; do not substitute more automated route
work or recording experiments.

## 2026-09-26 — Match perspective world-sprite post sampling

The adopted renderer's fixed-point column code exposed a gap in our projected
world-sprite drawer. A focused comparison of the installed Ultimate Doom
`TROOA1` patch across ten scales and four vertical texture origins found five
mismatching cases and 838 different palette indices. The first fixed-row-step
revision still differed at opaque-post edges, so the final change preserves
each post's fixed-point projected bounds, starts its row fraction at the
clipped post row, and applies the reference's 128-entry source-row mask. The
same 40 cases then match with zero differing pixels. Before/after receipts and
limits are documented in [rendering fidelity](rendering-fidelity.md).

The first process-worker run found that disposable asset transport discarded
post-column metadata. Asset format v5 now carries each post's bounds and a
reference to its shared source buffer and offset. This avoids repeating a
128-byte sample window for every post. After the transport fix, all three 16-process display styles
match serial output over five views, 138 weapon-lighting cases pass through a
v5 round trip, and the E1M1-to-E1M2 worker reload passes without restarting
the sixteen workers. The current 36-map, 35-idle-tic, two-frame smoke also
passes. These are renderer and startup checks, not campaign completion or
original-executable parity. Performance was not measured in this change.
The renderer and asset-transport update is committed as
`f12334e9941e2917da9d4de1c66e92967b0d3967`; the readiness receipt pins that
source while retaining Jason's single complete Episode 1 route as pending.

## 2026-09-26 — Fixed-point actor projection

The numeric actor drawer now performs Doom-style 16.16 camera transforms,
near/side clipping, projected scale and patch bounds, light-table selection,
and vertical texture-origin mapping using worker-safe PowerShell integer
arithmetic. Rotated-frame selection retains the existing floating-point angle
calculation, so this is a partial fidelity fix. A null rotated patch is skipped
to follow the reference renderer's guard.

Against the adopted PowerShell renderer, three static E1M1 views improve from
14,038 to 13,947 differing scene indices. Three E1M2 views with diagnostic
fixed colormap 1 improve from 21,633 to 21,186. This is a 538-index aggregate
reduction across six views, measured over full scenes rather than an actor-only
mask; it is not original-executable parity. The portable
[comparison receipt](../results/actor-projection-fixedpoint-comparison.json)
stores hashes and limits.

The current source matches serial rendering across 16 workers in Classic,
Matrix/Katakana, and AnsiArt/Katakana (320,000 pixels per style), and passes the
36-map, 35-idle-tic, two-frame smoke. Three-round paired serial measurements
show median paired deltas of +0.57 ms (+0.78%) on E1M1 and +1.40 ms (+3.00%) on
E1M2, with large per-sample variance. No performance improvement is claimed.

The first object-based fixed-point draft could not run in render workers because
they do not load engine `Angle`/`Fixed` classes; the failure is retained at
`results/render-partitions-actor-fixed-16-20260926.json`. Its paired E1M2
median was also substantially slower. Rewriting the transform as raw integer
PowerShell arithmetic removed that dependency while retaining the image
comparison result. Full rotation-boundary sweeps, moving-actor comparisons,
occlusion parity, and original-executable comparisons remain open.

## 2026-09-26 — Pin the Episode 1 playtest build

Commit `f0e85ba5ba6095cb105a69346ad3dd7f8ba7554c` contains the actor-projection
update and its portable comparison, raw paired timings, worker-equivalence,
and all-map smoke reports. Its renderer SHA-256 is
`CA56DD04BAC258F9ACF12AEA0A7535CDFE36A69D8C1EF9DAF8BBD56C63DEE9C8`.
The current source passes all 36 load/idle/render cases, exact 16-worker output
in Classic, Matrix/Katakana, and AnsiArt/Katakana, and a no-window launcher
preflight using the installed Steam IWAD and local Episode 1 music catalog.

The full-scene comparison against the adopted PowerShell renderer improves by
538 indices across six static E1M1/E1M2 views. The paired serial receipts each
contain 15 measurements per version; median paired costs are 0.57 ms (0.78%)
and 1.40 ms (3.00%), respectively. The compact comparison receipt initially
omitted sample counts and baseline/candidate medians; those fields now match
the raw trials, without changing or regenerating test data.

The one-run human handoff now pins this exact source commit. Its required scope
remains E1M1 through E1M8, including E1M3's secret exit to E1M9 and return to
E1M4, followed by the Episode 1 finale. Human route completion, physical input,
continuous campaign music, displayed FPS, original-executable visual parity,
and the broader release gates remain unclaimed.

## 2026-09-26 — Compare moving actors on the existing E1M1 regression

To extend fidelity evidence without building another gameplay route, replay
the first 280 commands from the qualified E1M1 regression and compare the
numeric renderer with the adopted PowerShell renderer every 35 simulation
tics. Across eight endpoints, the reference reports five visible world sprites
at tic 35, three at tic 70, one at tic 105, and none at tic 140; at least one
visible sprite changes projected position. HUD palette indices match exactly
at every endpoint. Full-scene disagreement ranges from 742 to 8,917 of 53,760
pixels.

The local triptych images show broad wall/floor differences; they do not
isolate an actor defect. The changing mismatch masks cannot prove actor parity
because the diagnostic does not subtract each renderer's actor-free
background. No renderer source was changed. Preserve this as a narrow
adopted-reference comparison, not original-executable fidelity, campaign
completion, or an occlusion qualification. The harness, input-route hash, WAD
hash, per-frame mismatch counts, and image hashes are in
[`rendering-fidelity.md`](rendering-fidelity.md#moving-actors-on-a-recorded-e1m1-prefix)
and [the receipt](../results/moving-actor-reference-e1m1-prefix-images-20260926.json).
Earlier idle-only probes are retained under ignored `local/` and do not count
as moving-actor checks.

## 2026-09-26 — Match Doom's rotated actor-frame arithmetic

The numeric renderer had been using floating-point `Atan2` and `Floor` to
choose a rotated actor frame. A source-matched boundary sweep found 172,724
wrong selections among 393,408 exact boundary cases. Replace it with a pure
PowerShell numeric port of `Geometry.PointToAngleData` and the adopted
renderer’s unsigned binary-angle wrap and three-bit frame selection. The
2,049-entry tangent lookup travels through disposable render-asset format v6;
the reader validates table size and endpoints. No compiled rendering helper
was introduced.

The new parity harness passes all 16,392 direction cases, 393,408 boundary
cases, six signed-int-minimum edges, and 100,000 angle round trips. Three actual
16-process styles each match serial pixels and encoded strips (320,000 pixels,
80 strips, zero differences); the full 36-map load/35-idle-tic/two-frame smoke
also passes. A focused direct E1M1-to-E1M2 map-change fixture rewrites v6
assets under sixteen persistent Classic workers; the E1M2 result matches
256,000 pixels and 64 encoded strips, with every worker PID unchanged. Raw
receipts are in `results/sprite-rotation-parity.json`,
`results/render-partitions-sprite-rotation-*.json`, and
`results/campaign-smoke-sprite-rotation.json`.

The 15-pair-per-map serial timing distributions do not support a performance
claim. Their median paired differences are about -0.4%, but E1M2's separate
candidate median is slower, illustrating the sample spread. The raw trials are
`results/sprite-rotation-performance-e1m1.json` and
`results/sprite-rotation-performance-e1m2.json`; they exclude setup, simulation,
workers, audio, encoding, Terminal, and displayed frame rate.

On exact source commit `693cc061a2caa1fac36fc8a0e6d2e6830a6a4577`, freshly rerun
checks pass: 57 campaign transition/secret-return/finale assertions, 97 boss
progression assertions, 10 menu-input assertions, 125 session-menu/screen
assertions, and six synthetic console-input checks. `Play.ps1 -Check` accepts
the installed Ultimate Doom IWAD and prepared Episode 1 music catalog, and the
catalog identity plus 36-map smoke are pinned in the readiness receipt. The
one full human Episode 1 route remains pending. Static math parity is not
moving-actor visual/occlusion validation, and no recording or automated route
work is part of this step.

## 2026-09-26 — Qualify finite D_INTRO playback

Loop playback already preserves its reader and source qualification. A separate
finite path is needed for non-looping engine callbacks. Added a bounded
PowerShell reader and report-based dispatch in `MusicPlayback.ps1`; loop reports
continue through the unchanged loop reader. At finite EOF the last device block
is zero-padded and the selection stops. Invalid loop-mode combinations and
offsets beyond the payload reject before commands mutate playback state.

The new `Qualify-MusicOneShot.ps1` renders the user's pinned D_INTRO score at
44.1 kHz through its MUS end event, then retains synthesizer voices until the
release tail ends. Two independent passes agree byte-for-byte: 471,240 stereo
float64 frames (10.686 seconds), comprising a 302,400-frame score (6.857
seconds) and 168,840-frame release tail (3.830 seconds), with 50 peak voices
and zero clipped samples. Receipt:
`results/music-one-shot-dintro-20260926.json`. The report pins the Ultimate Doom
IWAD, soundfont, six synthesis sources, qualifier, and PowerShell 7.6.5. It
does not establish original-synth fidelity or acoustic quality.

The 17-check playback receipt compares exact real loop-boundary slices, tests
D_INTRO's final six frames plus padding, confirms auto-stop, and checks invalid
commands and cleanup. The ten-check actual Windows waveOut test starts from the
D_INTRO finite report, switches to the E1M1 loop, and matches all 176,400
submitted frames against a separately scheduled offline mix. The current
12-check engine callback test still preserves the non-loop flag. A 15-check
save/load/new-game audio worker run against the unchanged eleven-track Episode
1 loop catalog passes on the updated worker. Receipts are
`music-playback-one-shot-dintro-20260926.json`,
`music-audio-worker-one-shot-dintro-20260926.json`,
`music-events-one-shot-dintro-20260926.json`, and
`save-worker-music-one-shot-dintro-20260926.json` under `results/`.

The worker-device check verifies only the opening 1,260 D_INTRO frames; the
reader's boundary test checks the final frames. Full-length device playback,
other non-looping scores, acoustic review, continuous campaign playback, and
Episode 1 human playthrough readiness remain open. No campaign route was added
or tuned.

## 2026-09-26 — Match Doom sky sampling

The numeric renderer's sky path used an analytic angle and clamped the
vertical coordinate. The adopted `ThreeDRenderer.DrawSkyColumn` instead uses
the wrapped high bits of `viewAngleData + xToAngleData[x]` and fixed-point
vertical sampling masked to 128 rows. The host viewport confirms a 256x128 sky,
scale 65536, altitude 6553600, and centerY 84. The existing 320-column Doom
angle table matches the reference at every column.

The PowerShell rasterizer now reuses that table to calculate exact sky columns
and wraps row `(y + 16)` with `& 127`. The precomputed sky column scratch array
is initialized for host and deserialized worker contexts. No serialized asset
format change was necessary. The source-pinned isolated test compares 320x168
sky samples at eight headings against the actual adopted renderer: 430,080
pixels, zero column-map mismatches, and zero pixel mismatches. Receipt:
`results/sky-sampling-20260926-v3.json`.

Classic, Matrix/Katakana, and AnsiArt/Katakana each retain exact serial output
across 16 process workers at five headings (320,000 pixels and 80 encoded
strips per style); the 36-map, 35-idle-tic/two-frame smoke passes. The final
E1M1 map-start scene comparisons produce the same per-heading counts as the
pre-change run, so they do not establish a full-frame sky difference. Retain
the direct sky sampler test as the targeted evidence. The checks do not establish
vanilla executable parity or 35-tic/60-display pacing.

The first worker attempt terminated before a frame because the reference
`ThreeDRenderer` class is not loaded in isolated render workers. Replaced that
call with the same local integer mask/modulo behavior and initialized scratch
storage in both context constructors; reran Classic worker parity, then all
three styles and the map sweep passed. No gameplay route was created or tuned.

## 2026-09-26 — Refresh the Episode 1 launch pin

The one-playthrough handoff now pins renderer build
`0fbdc40a77214c68203745800ec0a51cfed9a8fa`. Its gameplay, session/menu, and
input logic remain on the already-qualified baseline; the finite music path
and sky sampler have separate current evidence. A fresh `Play.ps1 -Check`
confirms Windows Terminal, PowerShell 7.6.5, the installed 36-map IWAD, and the
local Episode 1 music-catalog path. The `%LOCALAPPDATA%\pwshDoom\settings.json`
file is absent, so the documented defaults apply. The readiness receipt
preserves the earlier focused gameplay check pins and the new renderer pins
separately. Jason's one complete Episode 1 playthrough remains pending.

## 2026-09-27 — Reduce PowerShell effect-mixer cost

The isolated mixer stress case was a documented real-time problem: with
sixteen sustained voices, all 80 measured 1,260-frame blocks took longer than
their 28.57 ms audio duration. `Read-DoomAudioFrames` called `Math.Floor` for
every resampled frame and recomputed stereo array offsets. The PowerShell mixer
now initializes one integer source index from each voice's saved position,
advances it as positive pitch steps cross samples, and increments the stereo
index directly. Interpolation and all PCM arithmetic remain unchanged.

Two before/after pairs, with the run order reversed for the second, preserve
identical PCM digests for zero, one, five, and sixteen voices. The sixteen-voice
mean drops from 32.91/33.26 ms to 5.70/5.01 ms; every candidate block remains
below the audio duration. The five-voice means fall from 12.30/12.18 ms to
1.63/2.06 ms. The pre-change mixer also remains byte-identical for non-binary
pitch 0.97 and sample-skipping pitch 3.25, across split buffer reads. The final
26 mixer checks and nine music/effects checks pass. See
`results/audio-mixer-hotloop-summary-20260927.json` and the detailed record in
[`audio.md`](audio.md#per-sample-index-optimization-2026-09-27).

The first optimized draft reset the cached index at each read and failed the
existing partition-invariance check. That failure is retained in
`results/audio-mixer-hotloop-tests-20260927.json`; initializing from the saved
voice position fixed it. These are synthetic isolated costs. Renderer/device
load, live audio queue timing, speaker output, and acoustic continuity remain
unqualified.

## 2026-09-27 — Re-pin the single Episode 1 human-playthrough handoff

The user clarified that readiness means one complete human Episode 1
playthrough, including E1M3's secret route through E1M9, its return to E1M4,
and the E1M8 finale. Do not request map-by-map playtests or spend the milestone
on automated route construction. The four E1M1–E1M4 routes remain regressions;
the prior E1M5 route failure is not a product defect.

On source commit `76b18ac538a96e40b8aab2127039cf1a59718bec`, reran the focused
campaign/session checks: 57 transition fixtures, 97 boss-progression fixtures,
125 menu/session checks with 46 screens, and the 1,747-command ordinary-input
E1M1-to-E1M2 session route. The current mixer passes 26 focused PCM checks,
nine music/effects checks, and ten actual-device worker checks. The device
worker's submitted PCM matches its independent schedule and cleanup succeeds;
one queue-timing stall was logged. The 16-voice synthetic mixer case now stays
under its 28.57 ms block duration in both paired runs. The current launcher
preflight sees the installed IWAD, prepared catalog, PowerShell 7.6.5, and
Windows Terminal; the local settings file and human-run output paths are absent.

The exact human route, finale, actual secret-map traversal, dense-scene pacing,
and full-campaign audio continuity remain unverified until Jason's one
playthrough. The [current readiness receipt](../results/episode1-playtest-current-readiness-20260927.json)
collects exact hashes, report links, limits, and launch command. This is a
human-playtest handoff, not full Ultimate Doom release certification.

## 2026-09-27 — Reuse PowerShell renderer scratch buffers

The measured raster loop allocated its ray sine/cosine arrays, a masked-column
list, and one hashtable per deferred masked column every frame. The production
renderer now retains the two 320-entry arrays and a high-water pool of masked
column records per render context. Both direct host contexts and reconstructed
worker contexts initialize the scratch storage. No drawing equations or
ordering changed.

The pre-change renderer from `a8a8b9d` and current candidate match exactly at
36 E1M1–E1M9 map-start views after 35 idle tics and four headings: 2,304,000
indexed pixels, zero differences. Eight views exercise masked records (maximum
91); all 36 verify array and record reuse. Classic, Matrix/Katakana, and
AnsiArt/Katakana each pass five-heading, 16-process serial-equivalence checks:
320,000 pixels and 80 encoded strips per style, all exact. A fresh Ultimate
Doom smoke passes all 36 maps with two full renders after 35 idle tics.

Paired isolated serial render samples on E1M1/E1M3/E1M4 show candidate median
times 2.6–3.2% lower. p95 improves on E1M3/E1M4 but is 2.0% higher on E1M1;
large maxima also fall in these finite samples. The runs exclude simulation,
audio, workers, encoding, terminal output, and display presentation, so this
is not a live frame-rate claim. The E1 human-playthrough source pin stays at
`76b18ac538a96e40b8aab2127039cf1a59718bec`; this renderer work is later
continuing development and does not alter the delivered playtest build.

Evidence index: [scratch-reuse summary](../results/renderer-scratch-reuse-summary-20260927.json),
[pixel differential](../results/render-scratch-reuse-differential-e1-20260927.json),
[map smoke](../results/campaign-smoke-scratch-reuse-20260927.json),
[Classic workers](../results/render-scratch-reuse-workers-classic-20260927.json),
[Matrix workers](../results/render-scratch-reuse-workers-matrix-20260927.json),
[AnsiArt workers](../results/render-scratch-reuse-workers-ansiart-20260927.json),
and [paired timings](rendering-fidelity.md#reuse-per-context-raster-scratch-2026-09-27).

## 2026-09-27 — Refresh the active release queue

The Episode 1 playtest handoff is ready on the pinned `76b18ac` build; Jason's
one full route remains pending. The current renderer scratch-reuse commit is
later development and has separate pixel, worker, smoke, and timing evidence.
Keep those pins separate so the test build remains reproducible. The route
milestone covers E1M1–E1M8, the E1M3 secret detour through E1M9 and return to
E1M4, and the E1 finale. Do not resume map-by-map requests or AI route tuning.

The broader release queue remains active after handoff: M4 moving-world and
actor-occlusion fidelity, M3 full-campaign audio continuity and audible
quality, M5 Ultimate Doom campaign coverage, M6 repeated end-to-end pacing and
presentation evidence, then clean-checkout packaging and the final write-up.
`docs/roadmap.md` now separates this current queue from the September 19
chronology so old recommendations do not read as current work.

## 2026-09-27 — Reuse PowerShell truecolor strip builders

Classic Pairs and ColorState encoding allocated one string-reference array per
strip per image, concatenated it into a string, then encoded UTF-8 bytes. Each
codec context now retains a StringBuilder; the PowerShell encoders clear and
reuse that buffer and still return an owned byte array to the worker transport.
No pixel, SGR selection, cursor, or glyph algorithm changed. For sixteen
20-column strips at 320×200, the removed arrays contained 2,100 references
each; the source-derived total is 268,800 reference-payload bytes per image on
a 64-bit process, excluding headers and other strings/arrays. This is an
allocation calculation, not measured GC reduction or a frame-rate result.

The strict ANSI decoder passes 13 exact-color cases, including six real
E1M1/E1M3 views. Classic Pairs and ColorState each match serial output across
five views with sixteen workers: 320,000 pixels and 80 encoded strip checks,
zero pixel differences. The first strict test overlapped a renderer test while
both rewrote local/engine-bundle.ps1 and failed on that shared file lock; its
report is retained, and the test passed on a sequential rerun. This was test
build concurrency, not a product or encoder failure.

Evidence: [summary](../results/ansi-strip-buffer-reuse-summary-20260927.json),
[strict-color report](../results/ansi-color-state-stringbuilder-verified-20260927.json),
[retained first failure](../results/ansi-color-state-stringbuilder-20260927.json),
[Pairs workers](../results/render-partitions-pairs-stringbuilder-20260927.json),
and [ColorState workers](../results/render-partitions-colorstate-stringbuilder-20260927.json).

## 2026-09-27 — Reject the StringBuilder ANSI encoder change

The first focused comparison used a short debug sample and hinted that the
StringBuilder strip encoder was slower. I reran the measurement with the
encoder functions pinned directly from pre-change commit `37391e3` and candidate
commit `1fcda3d`, ten ABBA rounds, forty calls per measured block, and both
synthetic coherent and high-entropy frames. Each call encoded the same
320×200, 256-color strip of twenty columns; context construction and caches
were outside the timer. Pairs and ColorState output matched byte-for-byte.

Across those four cases, the candidate took 3.95–9.30 times the baseline
median time and allocated 82.8–102.8% more bytes on the measured PowerShell
thread. The removed reference-array estimate (16.8 KB per 20-column strip)
missed the larger cost in the end-to-end PowerShell encoder. This isolated
result does not prove whole-game pacing or identify one runtime operation as
the cause. The StringBuilder production change was reverted; the current
array-and-concatenate implementation matches the campaign/session baseline.

After restoration, 13 independent exact-color cases pass, 24 synthetic strip
round-trips pass, and both Pairs and ColorState match serial output across
320,000 pixels and 80 encoded strips with sixteen workers. The current
Episode 1 handoff pin is `e35874146856f00bc9568957982719ab0efdc909`; gameplay,
campaign/session, menu, input, and audio source files remain unchanged from the
tested campaign/session baseline `76b18ac`.

Evidence: [pinned-source benchmark](../results/ansi-strip-reuse-pinned-measurement-20260927.json),
[benchmark script](../scripts/Measure-AnsiStripReuse.ps1),
[strict color checks](../results/ansi-color-state-array-rollback-verified-20260927.json),
[synthetic round-trips](../results/ansi-strip-array-rollback-20260927.txt),
[Pairs worker checks](../results/render-partitions-pairs-array-rollback-20260927.json),
[ColorState worker checks](../results/render-partitions-colorstate-array-rollback-20260927.json),
and the [superseded candidate readiness receipt](../results/episode1-playtest-stringbuilder-candidate-readiness-20260927.json).

## 2026-09-27 — Refresh the Episode 1 human-playtest build pin

The original handoff used the campaign/session baseline `76b18ac`; its current
source retains the tested gameplay, session, menu, input and audio paths, plus
PowerShell renderer scratch reuse. The StringBuilder ANSI-strip experiment was
reverted after its pinned comparison measured worse time and allocation than
the baseline array-and-concatenate implementation. Strict color, synthetic
strip and sixteen-worker output checks pass on the restored encoder. A fresh
`Play.ps1 -Check` finds PowerShell 7.6.5, Windows Terminal, the 36-map Steam
Ultimate Doom IWAD, and the prepared Episode 1 music catalog; both local
content hashes match the handoff.

The current human-test pin is
`e35874146856f00bc9568957982719ab0efdc909`. The current-tip readiness receipt
links renderer and restored-encoder checks to the inherited campaign/session
test baseline and preserves each evidence source pin. The route remains one
HMP playthrough from E1M1 through E1M3's secret exit, E1M9, return to E1M4,
E1M8, and the finale. Jason's result remains pending.

Evidence: [current-tip readiness receipt](../results/episode1-playtest-current-tip-readiness-20260927.json),
[renderer scratch reuse](../results/renderer-scratch-reuse-summary-20260927.json),
[encoder regression measurement](../results/ansi-strip-reuse-pinned-measurement-20260927.json),
[restored encoder checks](../results/render-partitions-pairs-array-rollback-20260927.json),
and the unchanged [campaign/session receipt](../results/episode1-playtest-current-readiness-20260927.json).

## 2026-09-27 — Current Episode 1 candidate and secret-path readiness

`VisibilityCheck.InterceptVector` now keeps Fixed-point intermediates in raw
integers while preserving signed 32-bit wraparound, arithmetic shifts, division
saturation, and truncation. Two analytic cases and 50,000 seeded raw-Int32
comparisons against the previous Fixed-operator expression match exactly,
including exception types. The code is PowerShell and makes no claim of a new
renderer or a compiled gameplay helper. One instrumented 1,200-command profile
pair reports Game.Update means of 14.287 ms before and 13.424 ms after, and
Thinkers.Run means of 11.058 ms before and 10.400 ms after. Four selected
checkpoints match in each run. This is a single unpaced simulation-only profile
comparison, not repeated paired evidence, full-host pacing, or proof of 35
simulation tics/sec / 60 displayed updates/sec.

All four retained HMP route regressions pass on source commit
`f5f404afee415c1deec817e6adf6372bc3f3a009`: the unchanged E1M1 driver exits
after 1,560 commands with five kills; E1M2 completes 3,233 commands and 13
checkpoints into E1M3; E1M3 completes 7,118 commands and 24 checkpoints into
E1M4; and E1M4 completes 6,348 commands and 22 checkpoints into E1M5. These
remain regression routes, not new campaign automation. A fresh smoke also
passes all 36 Ultimate Doom maps with 35 idle tics and two serial frames per
map.

`Test-CampaignTransitions.ps1` now contains a focused session-state check for
the documented secret branch. Starting from E1M3, it advances the actual game
intermission, loads E1M9 from the IWAD, completes that map through the normal
intermission path, and loads E1M4; it checks fresh worlds and secret-history
state. The map exits themselves are fixture inputs, so this is not route
completion. The full 69 campaign/finale checks pass. The current build also
passes 97 boss checks, 125 menu/session checks with 46 screen fixtures, six
synthetic console-input checks, ten synthetic menu-input checks, and the
1,747-command E1M1-to-E1M2 ordinary-input session. `Play.ps1 -Check` finds the
installed PowerShell 7.6.5, Windows Terminal, 36-map Steam IWAD, and local
music catalog. The result is readiness for the single HMP Episode 1 human run,
not campaign certification. The detailed
[handoff](episode1-playtest.md),
[machine-readable receipt](../results/episode1-playtest-intercept-candidate-readiness-20260927.json),
and [campaign matrix](campaign-matrix.md) preserve scope and evidence limits.

Two harness assumptions were corrected without a production defect. The new
secret-path fixture first expected `DidSecret` to remain false at E1M9 entry;
the existing `DoWorldDone` transition marks the visit when advancing from
E1M3's secret exit. The test now checks that timing and passes all 69 checks.
The old E1M1 route report also predates the current independent qualifier's
Skill and complete checkpoint schema. `Qualify-CampaignRoute` could not replay
that legacy report, and adding metadata alone still left its first recorded
trace sample incompatible. I stopped adapting that report and ran the existing
E1M1 route driver directly; it passes as recorded above. Intermediate failed
reports remain under ignored `local/episode1-candidate-intermediate-20260927/`.
They are test-input/schema outcomes, not engine failures.

## 2026-09-27 — Fix renderer failures in retained E1M3/E1M4 replays

The refreshed candidate's fixed-input host replay exposed two real renderer
exceptions. E1M3 stopped at tic 2,680 when a plane-distance product of
`3,543,363,520` was converted directly to signed Int32. E1M4 stopped at tic
3,663 because the wall-light table lookup produced a negative index. The
PowerShell plane sampler now applies Doom's signed modulo-2^32 wrap. Wall-light
bucket selection now bounds the value before integer conversion for
nonpositive or invalid distances, and preserves the ordinary positive-distance
lookup. An intermediate patch called the engine's `[Fixed]` type from a render
worker that does not load that type; the worker-start error was corrected to a
local PowerShell wrap implementation before the successful route replays.

On source commit `4ed33630dcb26bb6f04456448535edc01f9b4bd5`, the stored E1M2
replay reaches `ReplayEnd` after 3,233 commands with all 13 checkpoints
matching; E1M3 completes 7,118 commands and all 24 checkpoints; E1M4 completes
6,348 commands and all 22 checkpoints. Each replay retains three session
transitions. The current 36-map smoke passes all maps with 35 idle tics and two
full serial frames per map. `Test-CampaignTransitions.ps1` passes 69 checks,
including real E1M3-to-E1M9 and E1M9-to-E1M4 world changes. Five-view renderer
parity is exact across 320,000 pixels with four workers in Classic,
Matrix/Katakana, and AnsiArt/Katakana; Classic also matches with sixteen
workers.

The production `CheckSight` bound setup now uses raw PowerShell integer math.
Its dedicated harness compares all three outputs with the prior `Fixed`
operators over 50,000 seeded raw-Int32 vectors and 200 boundary combinations:
50,200 calls, zero mismatches. One unpaired, instrumented 1,200-command profile
has lower means than the earlier intercept-only run, but does not establish a
repeatable performance improvement or qualify the 35-tic/60-display target.

The existing route drivers pass E1M1 (1,560 commands), E1M2 (3,046), and E1M4
(4,726). This pass's E1M3 waypoint-driver execution stopped at 2,293 commands
at waypoint 28, short of its next point, without a crash; no product defect was
reproduced and route tuning stopped. The retained 7,118-command E1M3 input
replays successfully as noted above. The failure and exact state are recorded,
not counted as route completion.

## 2026-09-27 — Correct actor occlusion and prepare the full Episode 1 handoff

The actor comparison found that `FastRenderer` wrote floor/ceiling fill depth
before drawing world sprites. Those fills are backgrounds, not occluders, so
lower sprite texels disappeared whenever a plane depth was nearer than the
actor. Removed plane depth ownership while retaining the plane IDs and colors;
opaque walls and composited sprites still own depth. The focused
`Test-MaskedWallOrder` fixture passes 18 checks. Across the retained E1M1
prefix, reference-only actor pixels fall from 247 to 3 at tic 35 and 344 to 5
at tic 70. A tic-105 candidate-only 17-pixel actor difference and broader
scene disagreement remain documented in the renderer-fidelity note.

I tried culling candidate sprites by sectors touched during BSP traversal. It
reduced one small off-screen difference, but Classic output from four worker
strips stopped matching serial output because each strip visited a different
set of sectors. The filter was removed; the no-plane-depth renderer passes
320,000-pixel serial/worker checks at five views in Classic, Matrix/Katakana,
and AnsiArt/Katakana. A fresh 36-map smoke, 69 transition checks, 97 boss
checks, 1,747-command E1M1-to-E1M2 session, 10 menu-input checks, and 24
session-screen checks also pass. `Play.ps1 -Check` finds PowerShell 7.6.5,
Windows Terminal, the installed 36-map IWAD, and the prepared local music
catalog. No bot routes or screen recordings were produced for this milestone.

The renderer change and focused comparison are committed as build
`e8ffd6edbc089d047e5eb5807377f93221d933bd`. The new
[candidate receipt](../results/episode1-human-playthrough-candidate-20260927.json)
and [human handoff](episode1-playtest.md) pin that build for one complete HMP
playthrough: E1M1–E1M3, the secret E1M9 visit and return to E1M4, E1M4–E1M8,
and the finale screen. Jason's result remains pending. This milestone does not
close the broader Ultimate Doom, Doom II, audio-continuity, rendering-fidelity,
performance, or MyHouse audit gates.

The [source-pinned readiness evidence](../results/episode1-render-guard-evidence-20260927.json)
prepares Jason's one complete HMP Episode 1 human playthrough; the [handoff](episode1-playtest.md)
pins the exact source, IWAD, music catalog, controls, route through E1M9 and
E1M4, and E1 finale. The [numeric visibility note](numeric-visibility.md) and
[renderer fidelity note](rendering-fidelity.md) preserve implementation and
limits. Compact reports remain tracked; 23 full raw route, replay, and
intermediate renderer reports totaling 51,482,267 bytes remain under ignored
`local/episode1-render-guard-raw-20260927/`, indexed by SHA-256 in the receipt.
Jason's human run, continuous campaign audio, audible review, physical keyboard
play, original-executable image parity, and sustained 35/60 pacing remain open.

## 2026-09-27 — Preserve actor occlusion at missing-texture walls

The wall rasterizer normally assigns depth while sampling texture pixels. A
solid wall with no texture still closes the BSP clip interval, but has no color
sample to claim depth; farther sprites could therefore leak through that wall
band. `FastRenderer` now records depth for the projected wall band only when
its corresponding texture is absent. Existing textured walls keep their
normal depth path. A first attempt wrote the entire newly closed screen
interval and failed the floor-background regression; it was narrowed to the
physical upper/lower or solid wall band before adoption.

The authored whole-scene masked-wall test now passes 20 checks, including a
sprite behind a textureless solid wall. The serial output also matches five
views across 320,000 pixels in Classic, Matrix/Katakana, and AnsiArt/Katakana
with four uneven strips; Classic passes the same with sixteen. The fresh
36-map load/render smoke, all 69 campaign transition fixtures, all 97 boss
fixtures, 24 session screens, 10 menu-input checks, and the local launcher
preflight pass. Exact reports and the candidate are linked in the [updated
Episode 1 receipt](../results/episode1-human-playthrough-candidate-20260927-r2.json).

The eight-endpoint E1M1 actor comparison still reports 17 candidate-only
pixels at tic 105 (and 3, 1, and 1 at other sampled tics). This wall change does
not resolve that separate visibility difference. It is a comparison against
the adopted PowerShell renderer, not an original-executable oracle. No
performance gain is claimed. The PowerShell source and regression harness are
committed as `0978112ef7b365f66b93770e1d98978e55b6d506`; the one complete HMP
Episode 1 human playthrough remains pending. No new bot route or screen
recording was run.

## 2026-09-27 — Inventory full Ultimate Doom music coverage

`Test-MusicInventory.ps1` parsed all 32 `D_` lumps in the installed Ultimate
Doom IWAD and checked the scheduled event sample positions against an
independent tick-times-315 projection. The IWAD maps reference 27 distinct
music-lump names across 36 episode/map slots; the prepared Episode 1 catalog
covers nine of those names and nine byte-distinct payloads. Episode 4 reuses tracks from the
first three episodes. Three score-lump pairs are byte-identical: E1M7/E2M5,
E2M9/E3M1, and E1M8/E3M4. Only D_INTRO has a finite-score qualification;
D_INTROA and D_BUNNY remain unqualified. These are inventory and scheduling
results, not synthesis, playback, acoustic, or campaign evidence. The full
[portable inventory](../results/ultimate-doom-music-inventory-20260927.json)
pins the IWAD and source hashes.

An offline Episode 2 batch was attempted for all nine E2 map tracks, using the
qualified Episode 1 catalog as its base. D_E2M1's independent opening check
passed, but loop synthesis was stopped at 902.43 of 1,829.57 audio seconds in
its three-period recurrence run, after about 16 minutes of wall time. No track
qualification or combined catalog was published; the other eight tracks were
not started. The incomplete attempt remains under ignored `local/` and must be
restarted at the D_E2M1 track boundary. This leaves the Episode 1 catalog
unchanged. Defer the full batch until its several-hour cost is better aligned
with the active release work; keep the 18 uncovered map scores and finite
score gaps visible in the audio roadmap.

## 2026-09-27 — Prove deterministic music recurrence from complete state

The three-period qualifier independently renders and compares the next loop's
PCM. That evidence is strong but expensive: an interrupted Episode 2 batch had
spent about 16 minutes before reaching half of D_E2M1's three-period render.
The pinned synthesizer is deterministic, so the optional
`-StateRecurrenceProof` mode now renders the intro and one complete candidate
loop, then compares their normalized complete future-driving states at the
aligned boundary. The serializer accepts only known synthesizer fields and
fails closed on unknown fields. It preserves event/score phase and channel,
voice, oscillator, envelope, filter and modulator state while normalizing
absolute counters that do not alter future samples. Equal state at the same
score phase with identical immutable assets entails recurrence for this
specific deterministic model. The report explicitly does not claim a third
independent PCM match. The old three-period check remains default and readable.

The proof was first exercised on actual E1M1: its 96-second period repeats
complete state at both loop boundaries with 35 voices. The exact separately
rendered canonical opening PCM remains unchanged. After the later preflight
bound guard, E1M1 was rerun against the current qualifier; two periods took
314.031 seconds of render/write/snapshot work. The state-proof evidence audit
passes 23 checks; reader compatibility passes 17, including the over-bound
rejection; the real reader/mixer qualification passes six; simulation playback
passes 17; and the actual waveOut worker passes ten, with the device closed.
The D_E2M1 test then completed: its aligned period is 609.857 seconds across
four score cycles, with 12 voices and recurrent state SHA-256
`BBD41D41F1D2C43F7BB0DEFB4BCD0D2790644EE864561DC1F5932DBEB261413E`. It
rendered two periods (1,219.714 audio seconds) in 1,320.515 seconds; the full
preparation command took 1,341.522 seconds. Its independent opening PCM is
exact. Six actual-reader/game-mixer checks and ten actual waveOut-worker checks
pass; the worker's submitted PCM hash matches its independent schedule and
the device closes. These device checks do not establish acoustic quality,
audible delivery or in-game queue timing.

The new qualified D_E2M1 result is the first newly covered Doom II map score;
the experimental combined E1/E2M1 catalog remains in ignored `local/` and does
not replace the unchanged Episode 1 catalog or constitute a full Episode 2
catalog. Seventeen unique Episode 2/3 scores and the two finite title/finale
scores remain open. Receipts are linked from [music loop evidence](music-loops.md#two-period-complete-state-recurrence-proof-september-27)
and [music preparation](music-preparation.md).

A bounds review found that the two-period mode's one-hour aggregate ceiling
could otherwise spend time synthesizing a single period longer than the
reader's 1,200-second playback maximum, then fail only when opening the loop.
`Qualify-MusicLoop.ps1` now rejects such a period before any synthesis, and
the reader's synthetic rejection test covers the boundary. The installed
stock-score inventory tops out at 805.457 seconds (D_INTER), so this does not
change any stock score. The D_E2M1 report predates this preflight-only guard;
its 609.857-second period is below the limit, and its synthesizer, state
normalizer, reader, and generated samples are unchanged.

## 2026-09-27 — Accept qualified music across PowerShell patch updates

Jason's first run of the Episode 1 handoff stopped at zero tics because the
loop reader required the qualification report's exact PowerShell patch string.
The report was valid on PowerShell 7.6.5; his launcher now resolves to 7.6.6.
The finite D_INTRO one-shot reader had the same exact-version check and would
also have failed once the loop reader passed. Both readers now accept a report
from the same PowerShell major/minor line while still recording its exact
qualification version and enforcing synthesis-source hashes, qualification
checks and cached-PCM SHA-256/length verification. Other major/minor lines,
malformed version strings, and invalid reports remain rejected.

The loop-reader suite passes 21 checks, including same-line patch acceptance
and major/minor rejection. Under the user's WindowsApps PowerShell 7.6.6
launcher, the 17-check playback suite opens the actual qualified E1M1 loop and
D_INTRO payloads; the state-proof reader/mixer evidence audit passes 23 checks.
The first cold full-start attempt exceeded the old 30-second simulation-ready
bound after all eleven catalog reports had opened without a music-reader
error. That bound is now 60 seconds. A repeat under the same 7.6.6 launcher
ran headless E1M1 for 2.002 seconds: 69 tics, 69 audio packets, 86,940
submitted music frames, all eleven catalog entries opened, no worker error,
and a clean device close. The compact [runtime-compatibility receipt](../results/episode1-startup-runtime-compat-20260927.json)
links the tracked test outputs and hashes the ignored raw session reports.
This is startup/integration evidence, not Jason's human playthrough, audible
quality review, campaign audio continuity or an E1 completion claim. The
playtest handoff now targets the fixed build; Jason's complete human route
remains pending.

## 2026-09-27 — Fix the chainsaw crash found in Jason's Episode 1 attempt

Jason reported a crash in E1M2 after collecting the chainsaw and attacking an imp
with Ctrl. The local human session recorded E1M1 intermission at tic 10,098 and
the E1M2 level load at tic 13,520; it ended with 26,731 tics, 39,094 frames,
and exit Error. This run is an interrupted human attempt, not Episode 1
completion. The simulation report identifies the failure in WeaponBehavior.Saw:
PowerShell's -gt tried to compare a custom Angle instance (16.89922378398478
degrees), which does not implement IComparable. The hit had already occurred;
player-facing adjustment crashed while processing it.

The chainsaw and Doom II homing-turn code now compare wrapped binary-angle
.Data values explicitly. The new focused [chainsaw/homing test](../scripts/Test-SawAttack.ps1)
uses the installed Ultimate Doom IWAD (SHA-256
6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F): it lands
a real E1M2 imp hit on its first attempt (60 to 56 HP), then exercises the
homing turn. Both checks pass in
[saw-attack.json](../results/saw-attack.json). The existing
Test-GameActions.ps1 regression also passes all nine checks. These are
focused component checks; Jason's route remains incomplete and must be
restarted from E1M1 on the fixed build.

The exact saved human command stream is now a crash regression as well. The
new [recorded-human replay check](../scripts/Test-RecordedHumanCrashReplay.ps1)
consumes all 26,731 inputs, passes E1M1 intermission at tic 10,098, loads E1M2
at tic 13,520, and reaches the end of the recording without an exception. All
79 saved gameplay/render checkpoints match, including the initial state. The
recorded source fingerprint differs because this replay tests the post-fix
engine; the separately logged 185 automap commands are excluded. This is an
in-process gameplay regression, not terminal/audio evidence or a completed
human campaign. See the
[replay receipt](../results/episode1-human-crash-replay-20260927.json).

The earlier 16-view comparison used tics 4,900–10,098 from the same human E1M1
input. Candidate-only actor-mask pixels range from 0 to 11 per sampled view
against the adopted renderer, but the specific Gibs/pickup view was not
isolated. A later map-data lookup confirmed these views include one camera
near the blue armor and several near Gibs placements. At tic 8400 neither
renderer showed actor pixels; at tic 4900 one candidate-only pixel was not
attributed to a specific sprite. These counts provide sparse context, not a
reproduction of Jason's exact angle. See the original
[pixel receipt](../results/human-pool-occlusion-samples-20260927.json) and the
[map-data audit](rendering-fidelity.md#audit-the-e1m1-pre-placed-gibs-report-2026-09-27).

## 2026-09-27 — Clip world actors at wall silhouettes

While preparing the single full Episode 1 human run, Jason reported E1M1
objects visible through walls and lower-level columns visible through an upper
floor. The notes remain recorded in his local playthrough tally. The replay
prefix comparison reproduced a world-actor leak at tic 245: BON1B0 at
(144,-3136,-8) changed 93 pixels over an upper-sector floor although the
adopted ThreeDRenderer clipped that actor behind a lower-wall silhouette. The
candidate actor-mask comparison at that checkpoint had 95 candidate-only
pixels and 68.3% overlap.

FastRenderer now saves per-column wall-silhouette clip bounds during its BSP
walk and applies them to a sprite when that wall is in front of the sprite and
the actor crosses the sector's upper or lower height boundary. This leaves
plane fill depth unchanged and also clips fuzzed world sprites. The focused
[regression](../scripts/Test-SpriteSilhouetteOcclusion.ps1) paints zero pixels
for the isolated occluded BON1B0; the pre-fix renderer changed 93 pixels in
the same view. At tic 245, the replay-prefix candidate-only actor mask drops
from 95 to zero and overlap rises to 95.2%; at tic 140, candidate-only mask
pixels drop from 44 to 3. The [full receipt](../results/actor-occlusion-human-prefix-245-20260927.json)
is adopted-reference parity evidence, not a vanilla executable comparison.

The updated renderer passes the 36-map load/simulation/two-frame smoke and
matches serial output across five views and seven uneven process strips in
Classic, Matrix/Katakana, and AnsiArt/Katakana (320,000 pixels per style).
Focused, smoke, partition, and actor-mask receipts are linked from the
[rendering-fidelity record](rendering-fidelity.md#clip-world-sprites-to-wall-silhouettes-2026-09-27).
The symptom in Jason's screenshot has not been separately confirmed as a
sprite or wall-geometry defect. Other camera states still show actor-mask
differences. His Episode 1 run remains pending; start one fresh complete route
from E1M1 when he has time. The implementation, focused regression, and
receipts are pinned in source commit
`b99dc8af6017622c6f80998873e56f58616333fe`.

## 2026-09-27 — Reuse sprite-clipping scratch and measure its cost

The focused E1M1 sprite-silhouette correction initially added a list of
hashtable records for every visible wall/column and allocated two 320-entry
clip arrays for every world actor. The renderer now retains per-column
high-water clip records and reuses the actor buffers in each render context.
Worker contexts rebuilt from serialized assets do not receive scratch arrays,
so the first partition check failed with a missing `SpriteClipWalls` property.
The renderer now initializes those fields on first render in the worker; the
serial and worker paths then share the same reuse behavior.

The first timing harness run was not used: it loaded both renderer versions
into one PowerShell function scope, allowing an older render entry point to
resolve the candidate patch helper. `Measure-RendererPair.ps1` now loads the
versions in separate PowerShell modules and reports that isolation mode. The
valid pair compares pre-clip source `703a1f7` with source `193c386` using six
alternating-order rounds, 30 serial 320x200 renders per version/map, and five
static E1M1/E1M3/E1M4 headings. The candidate medians are mixed (-0.9%, +2.0%,
and +6.6% respectively); p95 improves on E1M3/E1M4 and is effectively flat on
E1M1. This is renderer-only timing, not a full-host speedup or a 35-tic/60-
display claim. Raw reports are linked in the [performance record](performance.md#world-sprite-clipping-cost-2026-09-27).

The current source passes the 36-map load/render smoke, 119 fuzz checks, 20
masked-wall checks, and exact serial/worker output in Classic,
Matrix/Katakana, and AnsiArt/Katakana. The repeated-frame focused test confirms
zero pixel differences and reuse of the records and clip buffers. In the
retained E1M1 replay comparison, candidate-only actor-mask pixels fall from 95
to zero at tic 245 and from 44 to 3 at tic 140; reference-only pixels remain
(20 at tic 140 and 11 at tic 245). The raised-floor columns in Jason's
screenshot are still unclassified. The updated human-test build is
`193c386cc1a22feeb1bf7d269d9b2cc1d1ddaf73`; Jason's one full Episode 1 route
remains pending.

## 2026-09-27 — Classify the raised-floor E1M1 screenshot

Replayed the first 700 tics from Jason's own E1M1 input recording. The tic-700
state reproduces the submitted camera view at `(-81.12, -3266.78, 104)` and
16.171875 degrees. The bright upper fragments are two DoomEdNum 48 Techpillar
actors (`ELEC`) in sectors with floor height 40 and ceiling height 184. Their
38×128 patches project across the neighboring floor plane at height 104. The
lower white `COLU` actors are separate DoomEdNum 2028 decorations.

The two repository renderers show the same actor fragments at this view. In
the projected Techpillar regions, FastRenderer versus the adopted
ThreeDRenderer reports 354 versus 363 actor pixels (354 shared, zero
FastRenderer-only) and 576 versus 586 (573 shared, three FastRenderer-only).
The whole scene still has broader renderer differences; this is a focused
actor-mask comparison, not full-frame equivalence.

The original id Software Doom 1.10 renderer calls `R_DrawPlanes` before
`R_DrawMasked`, and its `R_DrawSprite` clips sprites through drawseg silhouettes
and their wall clips. It does not depth-test sprite pixels against floor-plane
depth. See [official render order](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_main.c#L3334-L3368)
and [official sprite clipping](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_things.c#L3436-L3620).
That source behavior explains the apparent overlap as classic Doom rendering,
not a FastRenderer-only leak; no code change was made. We did not capture an
independent DOSBox, Steam rerelease, or original-executable image, so visual
parity to that binary remains unmeasured. The separate pre-placed Gibs-through-
wall sighting near the blue armor was not reproduced at this camera state and
remains open; its object identity and the earlier sample coverage are clarified
in the [later audit](rendering-fidelity.md#audit-the-e1m1-pre-placed-gibs-report-2026-09-27).
The source-pinned replay details are in
[`raised-floor-techpillar-human-view-20260927.json`](../results/raised-floor-techpillar-human-view-20260927.json).

## 2026-09-27 — Move intermission background work before the visible frame

The earlier 1,747-command Matrix route measured 124.412 ms in its first
intermission session-screen call. `IntermissionRenderer` lazily decoded and
rasterized the selected full-screen background on that first call. Session
setup now prewarms only the active episode's `WIMAP0`–`WIMAP2` or `INTERPIC`
background and restores the shared screen bytes afterward. New-game selection
and save-load reconstruction also select the correct episode.

The first benchmark harness attempt stopped on a case-insensitive variable-name
collision between its baseline path parameter and the hash table; its failed
receipt is retained at `results/intermission-background-warmup-20260927.json`.
The corrected [48-check comparison](../results/intermission-background-warmup-20260927-r4.json)
passes for all four episodes and reproduces all eight previous Stats/Next
image hashes. A separate full session-screen run also reproduces all 24 prior
Stats, Next, finale-text and finale-art hashes. Five interleaved,
JIT/patch-cache-primed renders per screen show
7.84–8.88 ms lower first-render medians, moving about 8 ms into session setup.
This is an isolated one-host measurement, not full-game pacing or audio proof.
The actual simulation worker passes all 12 save/load checks while selecting
Episode 2 and restoring an Episode 1 save; the complete saved 26,731-command
chainsaw regression still matches all 79 available checkpoints. The user has
not yet completed the single full Episode 1 human playthrough.

## 2026-09-27 — Qualify and start Episode 2 map 2 music

D_E2M2 now has a local complete-state recurrence qualification using the
installed Ultimate Doom IWAD and pinned soundfont. Its loop period is
6,703,200 frames (608 seconds, one score cycle); two aligned periods repeat
the same complete normalized synthesizer state with 11 active voices and
state SHA-256
`59A1A22DE2725F04338DBA39D7F4F59D9087176E8BED60CFE5D3F92759C56BF4`.
The independently rendered eight-second opening PCM matches exactly. Six
reader/mixer checks pass, including the exact reusable loop seam. The
two-period result infers the next period from complete state; there is no
third independently rendered PCM comparison. Loop render/write/snapshot time
was 510.113 seconds and total preparation took 525.2 seconds.

The preparer then revalidated and published a 13-entry ignored local catalog:
the eleven Episode 1 scores plus D_E2M1 and D_E2M2. A two-second headless
Episode 2 map 2 run selected D_E2M2, submitted 86,940 music frames, returned
85,680 completed frames, reported an upper bound of 1,260 queued frames
canceled at shutdown, and closed the device without an audio-worker error.
That is brief catalog/selection/playback-start integration evidence. No
audible-quality or continuous-map/campaign conclusion follows.

Receipts: [track preparation](../results/music-preparation-e2m2-state-proof-20260927.json),
[six reader/mixer checks](../results/music-track-qualification-e2m2-state-proof-20260927.json),
[13-track catalog revalidation](../results/music-catalog-revalidation-e1-e2-20260927.json),
and the local [headless integration report](../local/episode2m2-music-integration-20260927.json).

## 2026-09-27 — Use world Z for lower sprite silhouettes

Code comparison found that FastRenderer derived a sprite's lower silhouette
boundary from patch top offset minus patch pixel height. The adopted renderer
uses the actor's world Z for `GlobalBottomZ` and uses the patch top offset only
for `GlobalTopZ`. In the installed E1M1 actors these are real distinct values:
the Techpillar patch is 123 units tall-offset over a 128-pixel image, and BON1
is 14 over 18. FastRenderer now anchors the lower silhouette test to the
actor's world Z.

The focused hidden-BON1 regression passes. Eight recorded E1M1 actor-isolation
views complete successfully; the actor masks at tics 35–245 are unchanged
from the prior receipt. The exact raised-floor tic-700 view also returns the
same isolated actor-pixel counts as its previous receipt, so this source
correction did not alter that screenshot or resolve the separate pool
visibility report; that tic-700 rerender used the ignored local
`audit-human-view-occlusion.ps1` helper and has no new portable receipt. The
fresh 36-map smoke passes, as do five-view/seven-strip
pixel checks in Classic, Matrix/Katakana, and AnsiArt/Katakana (320,000 pixels
per style). No performance or independent original-executable parity claim
follows. The first parallel test invocation collided on the shared temporary
engine-bundle filename; both renderer tests were rerun serially.

Receipts: [actor-mask comparisons](../results/actor-occlusion-human-prefix-world-z-20260927.json),
[focused wall-silhouette test](../results/sprite-silhouette-world-z-20260927.json),
[36-map smoke](../results/campaign-smoke-world-z-20260927.json), and
[Classic](../results/render-partitions-world-z-classic-20260927.json),
[Matrix](../results/render-partitions-world-z-matrix-20260927.json),
[AnsiArt](../results/render-partitions-world-z-ansiart-20260927.json)
partition checks.

## 2026-09-27 — Audit original Managed Doom references and apply narrow upstream math fixes

Reviewed the vendored engine's provenance (`src/ManagedDoom/ORIGIN.md`), the
original C# Managed Doom repository and its README references, the C# unit and
compatibility test layout, the post-pin PowerShell fork commits, and the user's
local GEBB PDF. The project clearly descends from the C# port through Oleyska's
PowerShell translation; the original reference suite can help target future
checks without becoming a runtime dependency. The new
[reference audit](reference-audit.md) distinguishes active implementation
references from secondary documents and future-only extensions. The GEBB
sections on masked draw-segment clipping are relevant to the reported sprite
visibility issue, but they do not diagnose it. The local PDF remains outside
the release/commit set.

The PowerShell fork's September 22 fix exposed three direct parity errors in
our pinned code: `SlopeDiv(1,1280)` rounded to 2 instead of using C# integer
division to produce 1; player bob-angle division rounded before multiplication;
and death-turn used five binary-angle units rather than five degrees. Adapted
only these narrow changes in `Geometry.SlopeDiv` and `PlayerBehavior`, leaving
the wider geometry rewrite for a future evidence-based review. 50,006 slope
inputs match unsigned 32-bit C# arithmetic; bob/death angle constants match.
This check is reproducible with
[`Test-ManagedDoomMathParity.ps1`](../scripts/Test-ManagedDoomMathParity.ps1).
The original C# `GeometryTest.PointToAngle` passes as a reference-project test.
The installed Ultimate Doom IWAD passes the 36-map load/render smoke and all 69
campaign-transition assertions after the PowerShell fixes. Neither check is
human campaign completion.

Receipts: [math parity](../results/upstream-math-parity-20260927.json),
[36-map smoke](../results/campaign-smoke-exact-math-20260927.json), and
[campaign transitions](../results/campaign-transitions-exact-math-20260927.json).

The retained 26,731-command human input recording was also replayed once as a
regression after these behavior changes. All commands were consumed without a
simulation exception, but the checker reported 134 mismatch entries across 79
checked checkpoint records, beginning at tic 350; the stream remained on E1M1 rather
than reaching the previously recorded E1M2 transition. Its captured source
fingerprint predates the current engine. This establishes that the old input
stream is no longer a valid exact replay baseline; it does not isolate a
product defect or reproduce the original crash. No waypoints or input were
retuned. Jason's fresh human playthrough remains the route-coverage oracle.

Receipt: [old human input replay after math corrections](../results/episode1-human-crash-replay-exact-math-20260927.json).

### Current-source Episode 1 requalification

After the upstream arithmetic corrections, current-source focused checks pass:
the 36-map Ultimate Doom load/render smoke; 69 campaign transition assertions
including E1M3 → E1M9 → E1M4 and finale routing; 97 boss-progression checks;
125 menu/session checks with 46 screen fixtures; 15 simulation-worker save,
load, and new-game checks with the prepared Episode 1 music catalog; and two
chainsaw-hit checks including the reproduced E1M2 imp case. A real two-second
headless `Invoke-Doom.ps1 -Sound -MusicCatalog` run starts the simulation and
audio workers and exits without an error (69 tics, 26 completed frames). This
is startup and short integration evidence, not continuous audio, displayed
frame rate, or campaign-completion evidence. The local C# reference test
`GeometryTest.PointToAngle` also passes, separately from pwshDoom.

The previous 26,731-command human input was replayed once against the changed
math. All 79 checkpoints were inspected; 134 state/render mismatch entries
begin at tic 350, and the old stream remains on E1M1 rather than reaching its
recorded E1M2 transition. No simulation exception or isolated reproducible
defect was exposed. Because its source fingerprint predates the arithmetic
fix, this is a stale-input result, not evidence of a current route failure.
Existing E1M1–E1M4 route receipts and fixed-input E1M2–E1M4 replays remain
retained at their recorded source pins; the E1M3 waypoint stall remains
documented without route tuning. These automated runs are not human campaign
evidence. The next route-coverage step is Jason's one complete Episode 1 run.

Receipts: [36-map smoke](../results/campaign-smoke-exact-math-20260927.json),
[campaign transitions](../results/campaign-transitions-exact-math-20260927.json),
[boss progression](../results/boss-progression-exact-math-20260927.json),
[menu/session checks](../results/session-menu-exact-math-20260927.json),
[save/audio worker](../results/save-worker-exact-math-20260927.json),
[chainsaw regression](../results/saw-attack.json),
[stale-input replay](../results/episode1-human-crash-replay-exact-math-20260927.json),
and [upstream math parity](../results/upstream-math-parity-20260927.json).
The short host startup report remains under ignored `local/`.

Before freezing the human-test candidate, the renderer's existing partition
check was rerun against the exact candidate source. Classic,
Matrix/Katakana, and AnsiArt/Katakana each match the serial image and encoded
strips across five headings, 320,000 pixels, and 16 uneven worker processes.
This confirms current serial/worker equivalence only; it is not original Doom
pixel parity or a performance result. `Play.ps1 -Check` also detects the
installed Windows Terminal, the 36-map IWAD, and the prepared catalog path;
that preflight does not validate the music contents. No per-user settings file
was present. The [r7 candidate receipt](../results/episode1-human-playthrough-candidate-20260927-r7.json)
pins these checks to the exact source build.

Receipts: [launch preflight](../results/episode1-launch-preflight-current-candidate-20260927.json),
[Classic](../results/render-partitions-current-candidate-classic-20260927.json),
[Matrix/Katakana](../results/render-partitions-current-candidate-matrix-20260927.json),
and [AnsiArt/Katakana](../results/render-partitions-current-candidate-ansiart-20260927.json).

# 2026-09-27 — Correct the E1M1 blue-armor Gibs report and sample coverage

Jason clarified that the object seen through a wall near the blue armor is a
pre-existing Gibs pile from the map, not the remains of an enemy killed during
play. The installed Ultimate Doom IWAD (`DOOM.WAD`, SHA-256
`6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`) has blue
armor (DoomEdNum 2019) at `(1824,-3280)`. A nearby E1M1 Thing type 24 is at
`(2112,-2688)`, ordinal 121; the adopted MobjInfo maps it to `Misc71`/`Gibs`,
whose state uses sprite `POL5`. DoomEdNum 2018 at `(-224,-3232)` is green armor.

The earlier sixteen-view actor-mask receipt did include spatially relevant
states: tic 8400 is 35.1 map units from the blue armor; tic 4900 is 215.1 units
from the closest Gibs pile; and tic 8750 is 11.4 units from another Gibs pile
at `(2272,-4000)`. Both renderers show zero actor pixels at tic 8400; at tic
4900 there is one candidate-only actor pixel, not attributed to a specific
sprite. The receipt therefore provides sparse context but does not reproduce
the exact reported view. The first spatial audit confused green armor 2018
with blue armor 2019; this entry and the corrected
[spatial audit](../results/episode1-blue-armor-gibs-sample-audit-20260927.json)
supersede that mistaken distance conclusion. No rendering code changed for
this correction.

## 2026-09-27 — Current-source isolation of the E1M1 pre-existing Gibs pile

Ran the same recorded E1M1 input at command indices 8400 and 8750 through the
current candidate and adopted renderers. The receipt records both input-command
index and in-game level time: those commands correspond to level times 1648 and
1998, respectively, because level time had restarted during the raw replay.
Both sampled endpoints are in E1M1 gameplay. At input 8400 neither renderer
produces world-actor pixels. At input 8750 the reference has no visible `POL5`
Gibs sprite, and the candidate produces no affected `POL5` pixels. The actor
masks have 98.7% IoU, with two candidate-only mask pixels (one `COLUA0` pillar
and one `BAR1B0` barrel, neither a palette mismatch) and 10 reference-only
`PLAYN0` pixels. Of 5,914 full-scene palette differences, 5,904 are outside
actor masks; the other 10 are reference-only actor pixels. These results do not
point to the Gibs pile as a visibility leak. The exact user-reported angle
remains unreproduced, and no rendering fix is justified by these samples.

The first current-source audit attempt exposed a harness error rather than a
game defect: it restored the sector actor-list heads captured when the map
started, not those present at each later sample, causing a false 2,007-pixel
repeat-render difference. A subsequent attempt also selected game level time
instead of the input-command indices used by the earlier sixteen-view receipt,
so it reached no requested samples. The diagnostic now snapshots live actor
heads at each selected command index, resets the reference renderer's fuzz phase
for same-state controls, and reports both clocks. The final [source-pinned
comparison](../results/human-pool-gibs-actor-audit-current-source-20260927.json)
passes repeat and restoration checks at both sample states. This does not prove
the historical report was mistaken; it only fails to reproduce it at the
available recorded views.

## 2026-09-27 — Qualify D_E2M3 music loop

Prepared the Ultimate Doom D_E2M3 score after D_E2M1 and D_E2M2. Its 8,811,180
frame (199.8 second) period repeats complete normalized synth state across two
continuous periods; the boundary has 17 voices and state hash
`07039D68DD2F720BA3E82422476A64CB3FBA6007762DF2B134310FDA34216C0A`. The
independent eight-second opening PCM matches through the actual loop reader and
game mixer (`3E5C985530423907A1DDA1D839F08B7B79ECBF0648C226D4072CC4AE9498EFCA`),
and six long-track reader/mixer checks pass. Preparation took 784.7 seconds.
The preparer published a one-track D_E2M3 catalog; it did not merge this entry
into the existing 13-track E1/E2M1/E2M2 catalog. This establishes offline loop
recurrence and byte-exact reader behavior, not independent third-period output,
live E2M3 play, acoustic quality, campaign continuity, or gameplay pacing.
Receipts: [preparation](../results/music-preparation-ultimate-doom-e2m3-stateproof-20260927.json)
and [reader/mixer checks](../results/music-track-qualification-e2m3-stateproof-20260927.json).

## 2026-09-27 — Qualify D_E2M4 and check actual host selection

Prepared the next unique Episode 2 map score with the default independent
three-period qualification mode. D_E2M4 has a one-cycle period of 11,113,200
frames (252 seconds); three continuous periods cover 33,339,600 frames (756
audio seconds). The startup boundary settles from zero voices to 19. Periods
two and three share complete normalized state hash
`71285BF154071DBFFA3D9182C9C8010C4DC3681396CC67C60048F352CE93906E` and
identical float64 output hash
`3595FDC15E49636FE2299749DD90735298B44A79B350B29170FFF40EA73CE2F3`. The
independent eight-second opening PCM matches through the real loop reader and
game mixer; six long-track reader/mixer checks pass, including the wrap seam.
Rendering, writing and snapshotting took 1,293.225 seconds; total preparation
took 1,309.288 seconds under PowerShell 7.6.5. This is offline preparation
cost, not a live audio deadline or performance result.

A two-second headless E2M4 host run selected D_E2M4 at frame zero, sent all 69
audio packets (86,940 frames), returned all 86,940 completed frames with zero
unconsumed packets, and closed waveOut without worker or cleanup errors. It
checks map-to-track selection and short-run shutdown only; there was no
listener review, full-map audio run or campaign continuity claim. D_E2M4's
one-track catalog and period payload stay local. The [preparation](../results/music-preparation-e2m4-20260927.json),
[reader/mixer qualification](../results/music-track-qualification-d-e2m4-20260927.json),
and [portable host receipt](../results/music-host-e2m4-integration-20260927.json)
pin the IWAD and source state. Four Episode 2 score loops were qualified at
this checkpoint; 14 other map-track names remained. The later byte audit
shows those names represent 11 unqualified score payloads because some tracks
duplicate Episode 1 content and D_E2M9/D_E3M1 duplicate each other. Two finite
title/finale scores remain open.

## 2026-09-27 — Qualify D_E2M5 and check actual host selection

Prepared the next uncovered Episode 2 map-track name with the default independent
three-period qualification mode. D_E2M5 has a one-cycle period of 6,652,800
frames (150.857 seconds); three continuous periods cover 19,958,400 frames
(452.571 audio seconds). The startup state differs from the recurring state.
Periods two and three share complete normalized state hash
`363A9C7E1456AB895DFC7286A4199908BA9BFF63685C02475EE54EC9A38792D9` with 66
voices and identical float64 output hash
`6E387C31C06032BE535E6E231B13CEA8B827EDAF185487D9F4FE84D9DFE59E23`. The
independent eight-second opening PCM matches through the actual loop reader and
game mixer; all six long-track reader/mixer checks pass, including the exact
loop seam. Rendering, writing and snapshotting took 1,673.010 seconds; total
preparation took 1,692.499 seconds under PowerShell 7.6.5. This is offline
preparation cost, not a live audio deadline or performance result.

A two-second headless E2M5 host run selected D_E2M5 at frame zero and submitted
69 packets (86,940 frames); all frames returned, with zero unconsumed packets
and no worker, audio or cleanup error. The audio report records one
queue-starvation observation after packet 68 at 22.884 seconds on the
audio-worker clock, with no subsequent resume. This is a stop-boundary metric,
not evidence of a mid-run audible interruption or sustained queue timing.
D_E2M5's one-track catalog and period payload stay local. The [preparation](../results/music-preparation-e2m5-20260927.json),
[reader/mixer qualification](../results/music-track-qualification-d-e2m5-20260927.json),
and [portable host receipt](../results/music-host-e2m5-integration-20260927.json)
pin the IWAD and source state. Five Episode 2 map-track names now have
individual loop qualifications. D_E2M1–D_E2M4 add four byte-distinct score
payloads, while D_E2M5 is byte-identical to D_E1M7; its qualification verifies
separate map-lump and catalog selection. Thirteen other Episode 2/3 map-track
names remain, representing eleven score payloads without a qualification.
Two finite title/finale scores remain open.

## 2026-09-27 — Qualify D_E2M6 and check actual host selection

Prepared the next byte-distinct Episode 2 map score with the default
independent three-period qualification mode. D_E2M6 has a one-cycle period of
7,815,780 frames (177.229 seconds); three continuous periods cover 23,447,340
frames (531.686 audio seconds). The startup state differs from the recurring
state. Periods two and three share complete normalized state hash
`90044183CF416BA18FED79881F2D561220B14EE389F8F038DE27183312066B0C` with 52
voices and identical float64 output hash
`079789945B5DF82409FC52CB751F1B1303C8BEA3568015CD2F46C408F1E78C63`. The
independent eight-second opening PCM matches through the actual loop reader and
game mixer; all six long-track reader/mixer checks pass, including the exact
loop seam. Rendering, writing and snapshotting took 1,503.712 seconds; total
preparation took 1,523.711 seconds under PowerShell 7.6.5. The IWAD lump SHA
`86BE00A645CB57EBE95C02B0FDFFC0F2F952A74C47752926400CF127E3116287` is
byte-distinct from every other map-score lump. This is offline preparation
cost, not a live audio deadline or performance result.

A two-second headless E2M6 host run selected D_E2M6 at frame zero and submitted
69 packets (86,940 frames); all frames returned, with zero unconsumed packets
and no worker, audio or cleanup error. The queue monitor recorded one
starvation observation after packet 68 at 23.773 seconds on its wall clock, with
no subsequent resume. This is a stop-boundary metric, not evidence of a mid-run
audible interruption. The short host run does not establish sustained queue
timing, listener quality or full-map/campaign playback. D_E2M6's one-track
catalog and period payload stay local. The [preparation](../results/music-preparation-e2m6-20260927.json),
[reader/mixer qualification](../results/music-track-qualification-d-e2m6-20260927.json),
and [portable host receipt](../results/music-host-e2m6-integration-20260927.json)
pin the IWAD and source state. Six Episode 2 map-track names now have
qualifications; D_E2M1–D_E2M4 and D_E2M6 add five byte-distinct payloads, while
D_E2M5 duplicates D_E1M7. Twelve other Episode 2/3 map-track names remain,
representing ten not-yet-qualified payloads, along with two finite scores.

## 2026-09-27 — Build and smoke-test a clean preview package candidate

Updated `scripts/Build-PreviewPackage.ps1` to omit PDF references under `docs/`
from the playable ZIP while continuing to reject other unrecognized file
types. This lets the local Gebbdoom reference remain available in the checkout
without entering the player download. Commit `eff3f14` was cloned into a clean
source tree; its package manifest reports no working-tree changes and pins all
533 included files. The local `0.1.0-preview.3` ZIP is 1,484,697 bytes with
SHA-256
`6676AAC3F26AB26DB4B871B8490CC639FA0717383809275D6AFAE94158FF3815`.

The ZIP was extracted, every manifest file hash was rechecked, and the PDF was
absent. `Play.ps1 -Check` on the extracted package found PowerShell 7.6.5,
Windows Terminal, and the supplied Ultimate Doom IWAD with all 36 maps. A
two-second headless Classic E1M1 host run from the extracted package reached
69 simulation tics and 91 completed frames before its requested `Duration`
exit, with no error. It used 16 PowerShell renderer workers (about 4.12 GB
reported worker working set); headless mode wrote zero Terminal frames, so
this is package/startup/render-worker integration evidence, not interactive
play, displayed-frame performance, audio continuity, or campaign qualification.
The [portable receipt](../results/preview3-package-candidate-validation-20260927.json)
and ignored raw report pin these checks. This is a local, unpublished candidate;
the complete human Episode 1 playthrough and broader Ultimate Doom release
gates remain open.

## 2026-09-27 — Cross-check the E1M1 renderer reports against GEBB

Visually checked the local *Game Engine Black Book: DOOM* pages 197, 208, 214,
240, and 242 against the current PowerShell renderer. The book describes
near-to-far BSP wall traversal, column-specific portal occlusion, planes before
masked sprites, and draw-segment silhouette clipping for actors. The
`FastRenderer` uses per-column wall-open bounds and silhouette records, draws
plane fills before world actors, and leaves plane fills out of the actor depth
buffer; the adopted `ThreeDRenderer` also draws its visplanes before masked
sprites. This corroborates the existing same-state classification of the
raised-floor E1M1 Techpillars as classic sprite/plane overlap, not a newly found
defect. The independent pre-placed `POL5` Gibs sighting near blue armor remains
unreproduced at Jason's exact view, so no clipping change is justified by this
comparison. The visual/source crosswalk and limits are in
[`reference-audit.md`](reference-audit.md) and
[`rendering-fidelity.md`](rendering-fidelity.md); the local reading PDF remains
excluded from packages and ordinary source commits.

## 2026-09-27 — Rerun E1M1 route and measure current-source presentation

The retained HMP E1M1 route driver was rerun against gameplay source commit
`1bd96b091a3202c534e4c36560d1e2ca529961a7` with the Steam Ultimate Doom IWAD
under PowerShell 7.6.6. With no waypoint edits it issued 1,560 simulation
commands, recorded five kills, and reached intermission. The source-pinned
receipt and raw result are in
[`e1m1-route-current-source-validation-20260927.json`](../results/e1m1-route-current-source-validation-20260927.json)
and [`e1m1-route-current-source-20260927.json`](../results/e1m1-route-current-source-20260927.json).
This confirms only the automated E1M1 route; Jason's documented full Episode 1
human playthrough remains pending.

A separate maximized Classic PresentMon run used the older fixed 1,560-command
input stream, without sound or music. It produced 47.73 display transitions per
second over 51.624 seconds, with 34.977 active simulation tics per second. A
7.119-second same-map asset reload caused the longest display gap. The fixed
input exhausted at `ReplayEnd` on E1M1, so this is a timing sample, not route
completion. The sample was unpaired with the prior windowed run and does not
establish a performance change or the 60-display goal. The exact run and raw
artifact hashes are in
[`presentmon-current-source-replay-20260927.json`](../results/presentmon-current-source-replay-20260927.json).

`Analyze-PresentMonGame.ps1` now accepts `ReplayEnd` only when explicitly run
with `-AllowReplayEnd`; its default still requires `LevelComplete`. This keeps
route completion as the normal acceptance condition while allowing finite
replay workloads to be analyzed honestly. No game or rendering code changed.

## 2026-09-27 — Correct the release and PresentMon status summary

The roadmap's M6 table still said PresentMon presentation was unverified, a
statement superseded by the installed service capture and the current-source
sample above. Updated it to preserve the initial standalone ETW denial as
history while stating the actual remaining performance limits. The changelog's
Unreleased qualification now includes the current E1M1 route regression and
the separate `ReplayEnd` timing sample. The README continues to identify
`0.1.0-preview.2` as the latest packaged release; the `.3` ZIP is a local
candidate from `eff3f14`, so release metadata should change only when a final
candidate is rebuilt and verified.

## 2026-09-27 — Rebuild and verify the current preview.3 package candidate

Built a fresh `0.1.0-preview.3` ZIP from clean commit
`e9c9f9d6f91f49a3a00d1f95f6505ecf60fffe07` in an isolated clean checkout. The
533-file manifest and every extracted size/hash match; the ZIP is 1,488,635
bytes with SHA-256
`B8FC5C41F37F9A6F2AC588A4B3EFDCE0C7A18594BC934A7B834F3F33048225D1`. The
research PDF and user IWAD are absent. The extracted `Play.ps1 -Check` passes
under PowerShell 7.6.6 and recognizes the supplied 36-map IWAD.

The packaged headless E1M1 host reaches its requested two-second duration with
69 simulation tics, 76 completed frames, and no error; reported worker working
set is 4,045,074,432 bytes. This run does not exercise visible Terminal
presentation, audio, or a campaign route. The raw report and package details
are pinned in
[`preview3-current-candidate-validation-20260927.json`](../results/preview3-current-candidate-validation-20260927.json).
The candidate remains local and unpublished pending Jason's one complete
Episode 1 human playthrough and the remaining scoped release checks.

## 2026-09-27 — Reject a stale E1M3 replay for current-source profiling

An attempted 1,200-command simulation profile used
[`e1m3-qualified-replay.json`](../results/e1m3-qualified-replay.json), whose
recorded source fingerprint is
`C7AE7AD6A2B8A3FD360468974D32D8CF2A24750F1F5C937A03B1657E9FE982C8`; the
current gameplay fingerprint is `D627BDF3D3605093095D9185EA564487ECE49A1FE2186134F2257191AB631682`.
The replay reached all 1,200 requested commands without a crash, but selected
checkpoints diverged at tics 350, 700, and 1050. This source-mismatched replay
cannot serve as a current performance comparison, and no engine defect was
established. Its raw [failed profile](../results/simulation-current-actors-profile-20260927.json)
is retained for audit (SHA-256
`90FE4EF1B1BDA284F60413C36CFA53304D79A40DB0D6C28C1B079144619686D9`); its
timings are not used. Do not retry this stale input as a route or profile.

## 2026-09-27 — Qualify D_E2M7 music and map selection

The installed Ultimate Doom IWAD's D_E2M7 MUS hash is
`FA014D3E627B9F35D9042F5C044FEDD55ACC20B3EF723517C99ACE5CBEAAE7E6`.
PowerShell 7.6.5 synthesized an independent eight-second opening and two
complete aligned 105.6-second periods using the complete-state recurrence
mode. Both period boundaries contain 102 voices and normalized state
`CAF6AC9FE0D4FB0DD370C57F3418441807738DD84D15CD8AC62B8F3C1CFD48B7`.
The opening PCM matches exactly. This proof does not render a third output
period; the report labels that limit explicitly. Offline render/write/snapshot
time was 856.254 seconds and total preparation was 886.966 seconds.

The six-check reader/mixer test verifies the payload, opening and recurrent
seam. The ten-check audio-worker test matches its submitted PCM to an
independent schedule. A 14-check engine callback/catalog test emits the exact
looping D_E2M7 start for E2M7 and validates the one-track catalog against the
installed IWAD. The actual two-second headless E2M7 host selects D_E2M7,
returns all 86,940 submitted frames across 69 packets, and closes the device
without starvation, rebuffer or worker error. These tests do not establish
full-map or campaign playback, audible quality or sustained timing. The raw
host report and PCM/catalog files remain under ignored `local/`; portable
receipts are the preparation, reader, worker, map callback and host reports
linked in [music-loop results](music-loops.md#d_e2m7-complete-state-recurrence-and-host-selection-september-27).
## 2026-09-27 — Qualify D_E2M8 music and map selection

The installed Ultimate Doom IWAD's D_E2M8 MUS hash is
`253A97E40D3909716DA51B066E4FEEC057EBC266C44509D168D6DBEBDDA5321A`.
PowerShell 7.6.5 synthesized an independent eight-second opening and two
complete aligned 176-second periods using the complete-state recurrence mode.
Both boundaries contain six voices and normalized state
`4E69A8C7F0641470B9CC86B7CBD9A1652C43090CE64353DEE8C830410951FB19`.
The opening PCM matches exactly. The proof does not render a third output
period. Offline render/write/snapshot time was 404.188 seconds; total
preparation took 421.369 seconds.

The six-check reader/mixer test verifies the payload, opening and recurrent
seam. The ten-check audio-worker test matches its PCM to an independent
schedule. A 14-check engine callback/catalog test emits the exact looping
D_E2M8 start for E2M8 and validates the catalog against the installed IWAD.
The actual two-second headless E2M8 host selects D_E2M8 and submits 86,940
frames across 69 packets; 85,680 complete before shutdown, with a 1,260-frame
upper bound on canceled queued audio. There was no queue-starvation
observation, rebuffer, unconsumed packet, worker error or cleanup error. This
is a stop-boundary tail, not evidence of a mid-run audible interruption. It
does not establish full-map/campaign continuity or acoustic quality. The raw
host report and PCM/catalog remain under ignored `local/`; portable receipts
are linked in [music-loop results](music-loops.md#d_e2m8-complete-state-recurrence-and-host-selection-september-27).

## 2026-09-27 — Qualify D_E2M9 music and map selection

The installed Ultimate Doom IWAD's D_E2M9 MUS hash is
`A6F854BDC4EC0DE7B8E3EC19B2EC5B1B5C0CF8DC00AC52A45A0E7E4C47D219E6`.
PowerShell 7.6.5 rendered an independent eight-second opening and two
continuous 96-second aligned periods using complete-state recurrence mode. The
opening PCM matches exactly. Both period boundaries have 127 live voices and
normalized state SHA-256
`A746B7B002D12F44F857D01CC46954477352EA72A640D9C07262F8DD3F94E789`.
The proof has no third independently rendered output period. Render, write and
snapshot took 859.227 seconds; total preparation took 877.463 seconds.

The reader/mixer passes all six checks, the actual audio worker passes ten,
and the engine callback/catalog test passes 14 for the E2M9-to-D_E2M9 mapping.
A two-second actual headless E2M9 run emits that looping score. It submits
86,940 frames across 69 packets and completes 84,420 before shutdown, with a
2,520-frame upper bound on canceled queued audio. There is no queue-starvation
observation, rebuffer, unconsumed packet, worker error or cleanup error, and
the device closes. This is a stop-boundary tail, not evidence of a mid-run
audible interruption. Full-map/campaign continuity, acoustics and sustained
playback deadlines remain unqualified. The raw host report and PCM/catalog
remain under ignored `local/`; portable results are linked in
[music-loop evidence](music-loops.md#d_e2m9-complete-state-recurrence-and-host-selection-september-27).

## 2026-09-27 — Reuse the exact D_E3M1 music payload

D_E3M1's MUS lump exactly matches the newly qualified D_E2M9 bytes, and the
soundfont is the same. The preparation command now searches validated current
catalog entries for an exact MUS/soundfont hash match, checks the source loop
against current code/assets, and writes a separate target qualification with
source-report and target-WAD provenance. The alias gets a D_E3M1 catalog entry
and map-specific callback/host checks, but no redundant synthesis or claim of
a newly distinct score payload.

The preparation-control regression passes nine checks, including exact payload
reuse without rendering, source report/catalog identity, mismatched-soundfont
rejection, resume and lock handling. The first run's only failure was the test
harness accessing `.Count` on an empty single-result enumeration under strict
mode; its alias subprocess had succeeded. The assertion now counts an explicit
array. The first corrected run passed; a second fresh run also explicitly
asserts the source and target soundfont hashes match. The original
[failed harness run](../results/music-preparation-controls-alias-20260927.json),
[first passing rerun](../results/music-preparation-controls-alias-20260927-r2.json),
and [soundfont-identity rerun](../results/music-preparation-controls-alias-20260927-r3.json)
are all retained.

The Steam IWAD alias report records source D_E2M9 qualification hash
`83B6B3A726B22D4F857D01CC46954477352EA72A640D9C07262F8DD3F94E789`, target
MUS hash `A6F854BDC4EC0DE7B8E3EC19B2EC5B1B5C0CF8DC00AC52A45A0E7E4C47D219E6`,
and soundfont hash
`82475B91A76DE15CB28A104707D3247BA932E228BADA3F47BBA63C6B31AAF7A1`.
Fourteen map-selection checks pass. The actual two-second E3M1 host selects
D_E3M1, closes the music/device, consumes all 69 packets without a queue
starvation or rebuffer, and returns 85,680 of 86,940 submitted frames before
shutdown. The canceled-tail upper bound is 1,260 frames. This remains a short
startup/selection/shutdown check, not campaign continuity or acoustic evidence.
Portable results: [alias preparation](../results/music-preparation-ultimate-doom-e3m1-alias-20260927.json),
[map selection](../results/music-events-map-selection-e3m1-alias-20260927.json),
and [host integration](../results/music-host-e3m1-alias-integration-20260927.json).

## 2026-09-27 — Reuse the exact D_E3M4 music payload

D_E3M4's MUS lump is byte-identical to the qualified D_E1M8 score. The
hash-based alias path therefore writes D_E3M4 provenance from D_E1M8's current
qualification rather than synthesizing an identical loop. Fourteen callback/
catalog checks pass for E3M4 selection. The actual two-second headless host
selects looping D_E3M4, closes the music/device, consumes all 69 packets, and
reports zero queue starvation, zero rebuffer, and no worker or cleanup error.
It completes 85,680 of 86,940 submitted frames before shutdown; the canceled
tail upper bound is 1,260 frames. This does not establish full-map/campaign
playback or acoustic quality. The target MUS hash is
`3118717CB94F58364199E838B2FDFC567023758CEFE1B7F31E2A554920ECB1E7` and the
source D_E1M8 qualification SHA-256 is
`F4C079000EC9267066940ED33C8E07FFB4A8FFE7A555AC5F9FC827BD3EA4B09E`.
Portable results: [alias preparation](../results/music-preparation-ultimate-doom-e3m4-alias-20260927.json),
[map selection](../results/music-events-map-selection-e3m4-alias-20260927.json),
and [host integration](../results/music-host-e3m4-alias-integration-20260927.json).

## 2026-09-27 — Qualify D_E3M2 music and map selection

D_E3M2 is a byte-distinct Episode 3 score. Its 10,348,380-frame period is
234.543 seconds; the complete-state method rendered two continuous periods
(20,696,760 frames total). Both boundaries have 47 live voices and normalized
state SHA-256
`914CAF4F1FCCA364DCD3EAEBB8603286D207A3E02570D46B28C235C37D3683C3`. The
independent eight-second opening PCM matches exactly. The proof infers the next
period from complete state; it does not include a third independent output
render. Render/write/snapshot took 892.403 seconds, and full preparation took
907.672 seconds.

The six-check reader/mixer audit verifies the exact opening and recurrent
seam. The ten-check audio-worker test matches its submitted PCM to an
independent schedule. Fourteen engine callback/catalog checks confirm E3M2
selects D_E3M2. The actual two-second headless host selects it, consumes all
69 packets, closes the music/device cleanly, and reports no queue starvation,
rebuffer or worker/cleanup error. It completes 85,680 of 86,940 submitted
frames before shutdown; the canceled-tail upper bound is 1,260 frames. This
does not establish full-map/campaign continuity, acoustic quality or sustained
deadlines. Portable receipts: [preparation](../results/music-preparation-ultimate-doom-e3m2-stateproof-20260927.json),
[reader/mixer](../results/music-track-qualification-d-e3m2-state-proof-20260927.json),
[audio worker](../results/music-audio-worker-d-e3m2-state-proof-20260927.json),
[map selection](../results/music-events-map-selection-e3m2-stateproof-20260927.json),
and [host integration](../results/music-host-e3m2-state-proof-integration-20260927.json).

## 2026-09-27 — Rebuild and verify the Preview.3 package candidate

Cloned the pushed `codex/feasibility-study` branch into a clean local checkout
at source commit `d49cbc6e9a1e946bc1f3e15e1459c2106159573d` and built a fresh,
unpublished Preview.3 ZIP. All 533 manifest entries match their packaged byte
lengths and SHA-256 hashes after extraction. The ZIP is 1,497,128 bytes with
SHA-256
`8CE9C39BD73A7879234B71B09E6D456A01FA29A66221873B71C512824052E11D`; its
checksum file matches. The ZIP itself contains 534 entries including the
manifest and contains no WAD, soundfont, native executable/library, generated
binary or research PDF. GPL and third-party notices are included; the final
release asset/license audit remains open.

Under PowerShell 7.6.6, the extracted package's `Play.ps1 -Check` recognizes
the installed IWAD, all 36 maps and Windows Terminal. A two-second silent,
headless E1M1 host smoke reaches its duration with no error: 69 simulation
tics, 71 completed frames, 34.469 tics/sec and 35.468 completed updates/sec.
The 16-worker set uses 4,036,415,488 bytes; the simulation process uses
371,351,552 bytes. These are short startup-smoke figures, not pacing claims.
The run does not exercise visible Terminal output, audio or campaign play. It
created `local/game-frame.bin` and `local/palette.bin` only in the extracted
test directory after the package contents had been verified; neither file is
present in the ZIP. The candidate-validation receipt is
[`preview3-current-candidate-validation-d49cbc6-20260927.json`](../results/preview3-current-candidate-validation-d49cbc6-20260927.json).
The complete Episode 1 human route and physical window/input checks remain
pending before release.

## 2026-09-28 — Defer the long D_E3M3 dry-loop proof

Started D_E3M3 preparation with the two-period complete-state recurrence
method. Its single loop period is 488.714 seconds; 977.429 seconds is the total
two-period proof horizon. The run advanced through 91.43 seconds of that total
score horizon before it was interrupted so the long CPU workload would not
compete with Jason's pending full Episode 1 playthrough. No loop qualification,
catalog or completed preparation report was produced. The independent opening
and partial attempt files remain under
`local/music-track-e3m3-stateproof-20260928/`; resume later with fresh catalog
and run-report paths according to [music preparation](music-preparation.md).
This does not change the already qualified Episode 1 soundtrack or Preview.3
candidate status.

## 2026-09-28 — Refresh terminal-Doom alternatives and article structure

Rechecked the current primary repositories for ManagedDoomPowershell,
nick0451/doom-powershell, spidychoipro/terminal-doom-pwsh,
cryptocode/terminal-doom, and dcouple/terminal-doom. The survey now separates
PowerShell engine code from PowerShell launch scripts and distinguishes
Windows Terminal/ANSI output from Kitty-protocol and browser/WASM approaches.
The newer compiled alternatives strengthen the case that Doom-in-a-terminal
already exists; neither a universal-first nor overall-performance claim is
supported. No alternative was built or measured against pwshDoom.

Reorganized the article draft around the actual PowerShell/Terminal/audio
boundary, rendering styles, separate pacing clocks, campaign evidence,
remaining audio/fidelity gaps, and alternatives. It now includes two Mermaid
diagrams and a workload-labeled measurement table. Existing source records
support the reported numbers; links in both updated Markdown documents pass a
local-path check and `git diff --check` passes. The draft is still not a
finished publication: Jason's full Episode 1 result, final release state, and
publication-ready illustrations remain outstanding. No new game recording
or copyrighted WAD image was created.

## 2026-09-28 — Repair and recheck the Preview.3 audio package

The extracted Preview.3 candidate failed before tic 0 with `Music loop source
changed: MusScore`. The qualification's raw file hash was being compared to
the package's raw hash; the clean Windows checkout had the same PowerShell
text with CRLF endings while the qualification used LF. This was a checkout
format mismatch, not a synthesis-source change. `Open-DoomMusicLoopReader`
now accepts the raw, canonical-LF or canonical-CRLF SHA-256 for a source file.
The check still rejects altered source text. `scripts/Test-MusicLoopReader.ps1`
passes all 22 reader checks under PowerShell 7.6.6, including those two cases.

Commit `8fe7600febb51693b58524c4dccbdfeac654979e` was cloned into a clean
Windows checkout and packaged with no working-tree changes. The extracted
ZIP verifies all 533 manifest files and 534 ZIP entries; no WAD, soundfont,
native binary or research PDF is included. The package SHA-256 is
`08F3ACB53BE7714E3385BC4BC8FB429FBEF06BD2EA556DD0617F5A62DDDD91F0`.
PowerShell 7.6.6 launcher preflight finds Windows Terminal and all 36 maps in
the local Steam IWAD. A two-second headless sound-enabled run starts D_E1M1,
reaches 69 tics and 74 frames, submits 86,940 PCM frames and closes the device
without an error. It records one queue-starvation observation after the final
packet; this is startup/shutdown evidence, not continuous campaign audio
qualification. The [package receipt](../results/preview3-current-candidate-validation-8fe7600-20260928.json)
and raw [host report](../local/preview3-package-8fe7600-audio-smoke-766.json)
preserve the measurements.

At this checkpoint the Episode 1 handoff pinned this commit and fresh `r5`
input/report paths; Preview.3 had not yet been published. It shipped later
that day. The static license/asset audit for this
candidate is complete: the archive contains GPL text and third-party notices,
all 206 vendored PowerShell files retain the upstream GPL terms, and no WAD,
soundfont, media, native binary or research PDF is present. Recheck if packaged
source changes. The full E1 human playthrough is the main product gate;
release-version README/changelog updates and publication-ready article
illustrations are also outstanding.
This is not waiting on Doom II, Final Doom, MyHouse, or the 35-tic/60-display
performance target.

## 2026-09-28 — Reconcile the Episode 1 handoff

The handoff command names fresh `r5` recording/report paths. A consistency
check found one stale sentence that still called them `r4`; it is now corrected.
The runtime note separates the 7.6.5 gameplay qualification from the later
7.6.6 clean-package audio startup check. The roadmap queue now uses the same
tested `8fe7600` build pin as the handoff. The ignored local directory still
contains only Jason's earlier `r2` E1M2 crash attempt and no `r5` outputs; no
gameplay process is active. Therefore the complete human route remains pending.

## 2026-09-27 — Recheck the E1M1 actor-mask discrepancy

The current renderer no longer reproduces the historical 17 candidate-only
actor pixels at E1M1 input tic 105. Replayed the existing 280-command
`e1m1-route-lineflags.json` regression against the installed Ultimate Doom
IWAD and compared actor-affected masks at tics 35, 70, 105, 140, 175, 210,
245 and 280. Same-state isolation and repeat-render controls passed. At tic
105 both renderers affect zero actor pixels.
Actor-mask IoU is 99.3%, 99.7%, and 99.8% at tics 35, 70 and 210. Tic 35 has
four candidate-only and four reference-only mask-edge pixels; the three and
one edge pixels at tics 70 and 210 are reference-only. Candidate-only scene
mismatches within actor-affected regions are zero at all eight endpoints.
Full-scene differences remain in the backgrounds, and this comparison does
not establish original binary parity or reproduce Jason's exact Gibs view.
The renderer source was unchanged at commit
`4427768372a4b0dc10ec5441dd69c1e748167ea8` during both runs.
The [eight-state receipt](../results/actor-occlusion-e1m1-prefix-current-20260928.json)
and [per-actor tic-105 isolation receipt](../results/actor-occlusion-tic105-current-20260927.json)
pin the evidence.

## 2026-09-28 — Refresh the E1M1 moving-ceiling comparison

Replayed the existing E1M1 line-flags input to level tic 315 and compared the
FastRenderer with the locally adapted PowerShell ThreeDRenderer while holding
the player, actor and other world state fixed. Only sector 26's ceiling height
changed. At the actual six-unit opening, 7 of 53,760 scene palette indices
differ; the HUD is exact. Counterfactual heights 0, 34 and 68 differ at 10,
410 and 4,166 scene indices. The earlier source pin measured 8, 1, 390 and
4,259 at those four heights, so the exact-pixel changes are mixed rather than
a uniform improvement. The 68-unit panels retain the same corridor layout,
with scattered palette differences across newly visible surfaces. This is a
renderer fidelity observation, not evidence of blocked progression, original
binary parity or performance. The reusable test is
[`Compare-MovingSectorHeightSweep.ps1`](../scripts/Compare-MovingSectorHeightSweep.ps1);
the [receipt](../results/moving-sector-e1m1-height-sweep-current-20260928.json)
pins source commit `532f2e3a90ab675db537616d1c166d8794cf4697`, IWAD and replay.

## 2026-09-28 — Qualify the D_E3M3 complete-state loop and host path

Resumed the preserved `local/music-track-e3m3-stateproof-20260928/` batch after confirming its exclusive preparation lock was free. The earlier opening and partial attempt were preserved; the new attempt used fresh catalog/report paths and the current installed IWAD and soundfont. The qualification ran under PowerShell 7.6.5 with WAD SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`, soundfont SHA-256 `82475B91A76DE15CB28A104707D3247BA932E228BADA3F47BBA63C6B31AAF7A1`, and D_E3M3 MUS SHA-256 `C52AFC2550020AACFED4F4C1F3A2C3600041A4DC6AC30B57FBE518CE96062A6B`.

D_E3M3’s period is 21,552,300 synth frames at 44,100 frames/sec (488.714 seconds) across four aligned cycles. The two-period proof rendered 43,104,600 frames (977.429 seconds total); period boundary snapshots at frames 21,552,300 and 43,104,600 both have 50 voices and normalized state SHA-256 `9809EC6D0C4873CEF5F3241AD767029D47C8DD09FCBF70E5E3E36F3D0B9D76E5`. The startup period and subsequent loop period have different float64 payload hashes; the matching state at the end of that loop period and one period later proves complete-state recurrence, but a third output period was not independently rendered. The exact eight-second opening reference and loop seam pass the six-check reader/mixer qualification. Render/write/snapshot took 4,674.868 seconds; full preparation took 4,692.003 seconds. The progress denominator `977.43 seconds` represents both proof periods, not one loop; this corrects the wording in the original deferral entry.

The actual engine callback/catalog test passes 14 checks and selects D_E3M3 on E3M3. The audio-worker suite passes 10 checks. The real two-second headless host starts D_E3M3, reaches 69 simulation tics, submits all 86,940 music frames, and returns 84,420 before shutdown; the 2,520-frame canceled-tail value is an upper bound. The host reports zero queue starvation, rebuffer, unconsumed packets, worker/cleanup error, and closes the device. These checks do not establish acoustic quality, full-map playback, continuous campaign audio, performance under sustained rendering, or 35/60 pacing.

A separate one-track D_E3M3 local catalog was published. The supplied Episode 1 catalog was an exact-payload alias lookup source, not a catalog-merge input, and the existing eleven-track Episode 1 catalog is unchanged. The current map-music preparation gap falls from six distinct track names to five (D_E3M5–D_E3M9), plus the two finite title/finale scores. All catalog and sound payload files remain local; no commercial assets were copied into Git.

Receipts: [qualification and two period hashes](../results/music-loop-d-e3m3-state-proof-20260928.json), [opening reference](../results/music-e3m3-opening-reference-20260928.json), [six reader/mixer checks](../results/music-track-qualification-d-e3m3-state-proof-20260928.json), [ten audio-worker checks](../results/music-audio-worker-d-e3m3-state-proof-20260928.json), [14 map-selection checks](../results/music-events-map-selection-e3m3-stateproof-20260928.json), [two-second host integration](../results/music-host-e3m3-state-proof-integration-20260928.json), and [preparation/catalog receipt](../results/music-preparation-e3m3-state-proof-20260928.json).

## 2026-09-28 — Profile and reject a music filter-update optimization

Profiled the first 98 seconds of D_E3M3 under PowerShell 7.6.5. It took
541.787 seconds with instrumentation, reached 97 voices, and spent
369.804 inclusive seconds in 9,514,726 voice-control updates; PCM conversion
took 0.668 seconds. This instrumented observation is not a live-playback or
unprofiled throughput claim. The raw [profile receipt](../results/music-profile-d-e3m3-98s-current-20260928.json)
pins all source hashes and the exact 98-second output.

Tested reusing each voice's already allocated five-coefficient filter array
instead of allocating a new array when its cutoff changed. The candidate
preserved the E1M1 eight-second PCM hash and matched the D_E3M3 32-second hash
`C8540C9480C0267330CA090746E4D7540E451DCDAE239DC2C09938CFDBC12329`.
In one same-window comparison, the old first 32 seconds summed to 113.165
seconds of block time and the candidate to 113.009 seconds (0.14%); this is
below a demonstrated gain, so the source rewrite was reverted. The
[E1M1 profile](../results/music-profile-e1m1-filter-reuse-8s-20260928.json)
and [candidate profile](../results/music-profile-e3m3-filter-reuse-32s-20260928.json)
retain those observations.

Added detailed envelope/filter timers to the offline profiler and repeated
the identical 32-second D_E3M3 render. The timers report 5,808,928 envelope
evaluations taking 51.362 seconds (46.1% of inclusive control time), and
618,011 filter updates taking 12.460 seconds (11.2%). Other control work
accounts for 47.494 seconds. Instrumenting these inner calls raises total
render time to 146.809 seconds, so these are within-profile attribution only.
The output exactly matches the prior 32-second result, and no source file
changed during the render. The [detailed receipt](../results/music-profile-e3m3-controls-32s-20260928.json)
and [synthesis notes](music-synthesis.md#dense-control-path-profile--2026-09-28)
identify envelope evaluation as the next measured optimization target. No
gameplay or synthesizer algorithm changed in this entry.

## 2026-09-28 — Measure and roll back dense-mix envelope reuse

Prototyped exact adjacent-endpoint reuse suggested by the detailed profile.
On the 32-frame control grid, a voice's interpolated `gainNext` can supply the
next boundary's envelope value if its frame and release time still match.
The candidate enabled reuse at 24 or more voices and left the original direct
path below that threshold.

The 55 dry-synthesis checks passed with the candidate. Same-command 32-second
D_E1M5 renders match exactly at PCM hash
`615663132F40145A20CC134EF6930E80DA614DC2102CB31E6650F745029309F1`; process
CPU fell from 97.422 to 83.969 seconds (13.8%). D_E3M3 also matched exactly
at `C8540C9480C0267330CA090746E4D7540E451DCDAE239DC2C09938CFDBC12329`, with
process CPU falling from 116.141 to 91.375 seconds (21.3%). The complete
prepared D_E1M5 track separately peaks at 170 voices; the tested opening
peaked at 74. The eight-second D_E1M1 prefix used 4.7% more process CPU in a
single pair while preserving hash
`1BE9256376413BE07688B984E1EDF7D017A5E0D7BB9E493F5595868490EA9650`.
These are offline preparation measurements, not live audio or frame pacing.

Opened the actual current E1M5 qualification with the prototype still in
`src/MusicSynth.ps1`. It failed with `Music loop source changed: MusicSynth`.
Because the optimization only changes offline synthesis and would invalidate
all existing source-pinned loops, it was rolled back rather than weakening
the reader's hash check or implying unperformed full-track requalification.
The working source was restored to its pinned hash; the qualified E1M5 report
now opens successfully again. The exact
baseline/candidate comparisons remain in the [D_E1M5 pair](../results/music-e1m5-envelope-cpu-base-32s-20260928.json)
and [candidate](../results/music-e1m5-envelope-cpu-candidate-32s-20260928.json),
[D_E3M3 pair](../results/music-e3m3-envelope-cpu-base-32s-20260928.json)
and [candidate](../results/music-e3m3-envelope-cpu-candidate-32s-20260928.json),
and [E1M1 pair](../results/music-e1m1-envelope-cpu-base-8s-20260928.json)
and [candidate](../results/music-e1m1-envelope-cpu-candidate-8s-20260928.json).

## 2026-09-28 — Qualify D_E3M5 map music

Before preparation, compared the five remaining Episode 3 score hashes with 65
report entries in the local prepared catalogs using both exact MUS SHA-256 and
the pinned soundfont SHA-256. None matched an existing qualification. D_E3M5
was prepared as its own track-sized batch; the eleven-track Episode 1 catalog
remains unchanged, and no WAD, soundfont or PCM payload was added to Git.

The stock Steam Ultimate Doom score has MUS hash
`1675CA9BD749027CDB4D0BC15A08BFCEF643616217D47BE43AA4073315182561`. Its
loop period is 6,652,800 frames (150.857 seconds); two continuous periods
rendered 13,305,600 frames. The complete normalized state at both boundaries
matches with 66 voices and hash
`310C820F065ABDA49F67D8A3280E386B1B122EFBA772F0E3EB5CA305DB268476`. The
independent eight-second opening matches through the real reader and game PCM
mixer. This is a two-period complete-state recurrence proof, not an
independently rendered third output period. Preparation took 1,201.894 seconds
under PowerShell 7.6.5; all pinned source and asset hashes remained unchanged.

Six long-track reader/mixer checks and ten actual audio-worker checks pass.
Fourteen music-event checks select D_E3M5 for E3M5. A two-second headless
E3M5 host run reaches 69 tics, submits and returns all 86,940 PCM frames, has
no simulation/audio/cleanup error, and closes both the device and music reader.
Its one queue-empty poll is after final sequence 68; there are no active
starvation observations and no canceled tail. This short startup/shutdown run
does not qualify full-map continuity, sustained timing or acoustic quality.

The distinct D_E3M5 payload is now one of the qualified Episode 3 tracks;
D_E3M6–D_E3M9 and finite D_INTROA/D_BUNNY remain open. The exact one-track
catalog SHA-256 is
`F0AF1B0B406A048613573400D0F29171AC18F77C4FFD58C39FDB1ECB2034B1E3`.
The current Episode 1 playtest package and its human-playthrough gate are
unchanged.

Receipts: [loop proof](../results/music-loop-d-e3m5-state-proof-20260928.json),
[independent opening](../results/music-e3m5-opening-reference-20260928.json),
[six reader/mixer checks](../results/music-track-qualification-d-e3m5-stateproof-20260928.json),
[ten audio-worker checks](../results/music-audio-worker-e3m5-stateproof-20260928.json),
[14 map-selection checks](../results/music-events-map-selection-e3m5-stateproof-20260928-r2.json),
[two-second E3M5 host run](../results/music-host-e3m5-stateproof-integration-20260928.json),
and [preparation/catalog receipt](../results/music-preparation-ultimate-doom-e3m5-stateproof-20260928.json).
## 2026-09-28 — Qualify D_E3M6 and test the playback buffer hypothesis

Prepared D_E3M6 as an isolated track from the installed stock Ultimate Doom IWAD and current soundfont. The MUS SHA-256 is `18D376A2910CC153F2360DE40400782FA446241FC44B6D6122288074F7E08BAF`; the loop period is 3,704,400 frames (84 seconds). Two continuous proof periods end with 41 active voices and matching normalized state hash `1F22D80D3D9B3923C204DD5330945B38A96193612ADD88724754D7456DB6EE83`. Preparation took 397.465 seconds under PowerShell 7.6.5. Six reader/mixer checks verify the independent opening and loop seam, ten worker checks verify output/lifecycle, and fourteen map-selection checks select D_E3M6 for E3M6. The separate one-track catalog SHA-256 is `9A7BB2D540910379C3C00E66CF5974D662D7A9775F0B1B469B0C4B5634AFF8B8`; no sound assets were added to Git.

The actual host's queue telemetry is variable under this machine's load. Two short 16-worker E3M6 runs had active starvation observations after packet 17, then later packets resumed. At eight workers a two-second run had only the final queue-empty poll; at 12 workers the two-second run also completed without active starvation. Extending 12-worker runs to eight seconds produced one clean 279-packet run (351,540 frames returned) and one 279-packet run with a starvation after packet 40, recovery after packet 42, and a 3,780-frame shutdown-cancellation upper bound. These are queue-poll observations, not proof of hardware underrun or audible dropout.

To test whether more queued device capacity absorbs scheduling jitter, temporarily doubled `Invoke-AudioWorker.ps1`'s waveOut buffer count from four to eight and repeated the same eight-second 12-worker host. The first 279-packet run had only a final queue-empty poll and returned all 351,540 frames. The second had an active starvation after packet 37, resumed after packet 39, and returned all 340,200 frames it submitted. Since the same one-of-two active-starvation rate persisted, the experiment did not show a stable improvement; the source was restored to four buffers. The ten-check actual-worker suite passed both with the temporary candidate and again after restoring the default. No product source change is retained from this buffer experiment.

These static-scene, headless runs do not qualify complete music playback, acoustics, audio-device telemetry, or 35/60 presentation pacing. The [buffer-count comparison receipt](../results/music-audio-buffer-count-e3m6-20260928.json), [84-second state proof](../results/music-loop-d-e3m6-state-proof-20260928.json), [opening reference](../results/music-e3m6-opening-reference-20260928.json), [six reader/mixer checks](../results/music-track-qualification-d-e3m6-stateproof-20260928.json), [default worker checks](../results/music-audio-worker-e3m6-stateproof-20260928.json), [restored-default worker rerun](../results/music-audio-worker-e3m6-final-4buffers-20260928.json), [map selection](../results/music-events-map-selection-e3m6-stateproof-20260928.json), [preparation/catalog report](../results/music-preparation-ultimate-doom-e3m6-stateproof-20260928.json), [two-second host worker-count pair](../results/music-host-e3m6-stateproof-integration-20260928.json), [four-buffer eight-second pair](../results/music-host-e3m6-stateproof-load-w12-8s-20260928.json), and [temporary eight-buffer pair](../results/music-host-e3m6-buffers8-w12-8s-20260928.json) retain the evidence. The Preview.3 candidate and its Episode 1 handoff are unaffected; Jason's single complete human playthrough remains the Preview.3 release gate.

A follow-up eight-second, 12-worker host on the packed-renderer candidate reproduced one active queue gap: after packet 35, playback resumed after packet 37 with a 54.17 ms rebuffer wait. Around that window, simulation packet publication intervals reached 67.42 ms while audio mixing took about 0.5–0.6 ms per block. The run submitted 352,800 frames and the driver returned 347,760 before shutdown; the remaining 5,040 are an upper bound on canceled queued audio, not proof of what reached the speakers. Raw ignored report: `local/audio-e3m6-before-independent-music-clock-20260928-r2.json` (SHA-256 `6519A31079BBA6C66F409613AFDE278EA28BC938D446EA0F1343BD4D3CD12261`). This supports producer-cadence jitter under renderer load as the immediate cause; it does not establish acoustic underrun or justify a playback-clock change by itself.
## 2026-09-28 — Qualify D_E3M7 music and map selection

Compared D_E3M7 against the current Episode 1, D_E3M5 and D_E3M6 catalogs and prepared it as a separate stock score. Its MUS hash is `8A856C8D819F1A62F7FCD49E8736C2CB67FE64D216B5B384727BE31874E75788`; the complete-state period is 4,656,960 frames (105.6 seconds). The two-period proof rendered 9,313,920 frames. Both boundaries have 102 voices and normalized state hash `CFEAEB505AA6B98A59E060EF18A0B3287EA3D9ECB1A616F035C1CAB6F78417C1`; the independent opening PCM matches at `F500F0E978006CC0B1BF6DB49D6C4903CDEDD5CE239813369361C59FC95E44A6`. Preparation took 874.216 seconds under PowerShell 7.6.5, including 844.425 seconds for render/write/snapshot. The one-track local catalog SHA-256 is `503EC2E2637860676507C627E53B19FF322FF4577953340F9A28B450A4CA89C7`.

Six reader/mixer checks, ten actual audio-worker checks and fourteen engine map-selection checks pass. The two-second E3M7 actual host selected D_E3M7, ran 69 simulation tics, returned all 86,940 submitted music frames, and closed the device without worker/cleanup errors. The one queue-empty observation followed the last packet; no active queue starvation was observed in this brief startup run. It does not qualify the full map, audible quality, sustained queue timing, or campaign continuity. The E3M7 score is now qualified; D_E3M8, D_E3M9, and finite D_INTROA/D_BUNNY remain open. The Episode 1 human-playtest build and its release gate are unchanged.

Receipts: [complete-state loop proof](../results/music-loop-d-e3m7-state-proof-20260928.json), [opening reference](../results/music-e3m7-opening-reference-20260928.json), [six reader/mixer checks](../results/music-track-qualification-d-e3m7-stateproof-20260928.json), [audio-worker checks](../results/music-audio-worker-e3m7-stateproof-20260928.json), [map-selection checks](../results/music-events-map-selection-e3m7-stateproof-20260928.json), [actual host run](../results/music-host-e3m7-stateproof-integration-20260928.json), and [preparation/catalog report](../results/music-preparation-ultimate-doom-e3m7-stateproof-20260928.json).
## 2026-09-28 — Qualify D_E3M8 music and map selection

Compared D_E3M8 against the current Episode 1 and D_E3M5–D_E3M7 catalogs; its stock MUS payload was not a reusable alias. The complete-state period is 4,233,600 frames (96 seconds), and the two-period proof rendered 8,467,200 frames. Both boundaries have 33 voices and normalized state hash `E75A1EC73F90C2EFB1BC9377CBFFE11718DBA9E225412FA4735140DED626868E`. The independent opening PCM matches at `07C56FA0D6A300ED2B37BC1EFE1CA28D706C4C469CA7F8067D27623D173ACCB1`. Preparation took 398.445 seconds under PowerShell 7.6.5, including 383.339 seconds for render/write/snapshot. The one-track local catalog SHA-256 is `CB925E42E3C2235ABFA745F2DE6E20FB0343349D4548C819B7440F1E13D79641`.

Six reader/mixer checks, ten actual audio-worker checks and fourteen engine map-selection checks pass. The two-second E3M8 actual host selected D_E3M8, ran 69 tics, submitted 86,940 frames and returned 85,680 before shutdown. The 1,260-frame canceled-tail figure is an upper bound; the device closed without worker/cleanup errors, active starvation, or rebuffer. This does not qualify full-map playback, acoustic quality, sustained timing or campaign continuity. Only D_E3M9 among the Episode 3 map scores and the finite D_INTROA/D_BUNNY scores remain open. The Episode 1 human-playtest build and release gate are unchanged.

Receipts: [complete-state loop proof](../results/music-loop-d-e3m8-state-proof-20260928.json), [opening reference](../results/music-e3m8-opening-reference-20260928.json), [six reader/mixer checks](../results/music-track-qualification-d-e3m8-stateproof-20260928.json), [audio-worker checks](../results/music-audio-worker-e3m8-stateproof-20260928.json), [map-selection checks](../results/music-events-map-selection-e3m8-stateproof-20260928.json), [actual host run](../results/music-host-e3m8-stateproof-integration-20260928.json), and [preparation/catalog report](../results/music-preparation-ultimate-doom-e3m8-stateproof-20260928.json).
## 2026-09-28 — Qualify D_E3M9 and close the Episode 3 map-score set

Compared D_E3M9 against the current Episode 1 and E3M5–E3M8 catalogs; its stock MUS payload was not a reusable alias. The complete-state period is 24,231,060 frames (549.457 seconds), and the two-period proof rendered 48,462,120 frames. Both boundaries have 26 voices and normalized state hash `0DBFAC69BC2C1AEDD330D8C336C28B038B086A39D2B0BED06EC0DAC729E098A4`. The independent opening PCM matches at `DF654910141E15DC83EFFF851281F59CA498767E3E57036B2113243F3111B8D3`. Preparation took 2,492.816 seconds under PowerShell 7.6.5, including 2,464.388 seconds for render/write/snapshot. The one-track local catalog SHA-256 is `5C7E7F6E91647A78AE59C9D846424C6FDDE5C768B8B9A064D948FA967FA76AA8`.

Six reader/mixer checks, ten actual audio-worker checks and fourteen engine map-selection checks pass. The two-second E3M9 actual host selected D_E3M9, ran 69 tics, submitted and returned all 86,940 frames, and closed the device without worker/cleanup errors. Its only queue-empty poll followed the last packet; no active queue starvation was observed in this brief startup run. This does not qualify full-map playback, acoustic quality, sustained queue timing, or campaign continuity. All Episode 3 map scores are now qualified; D_INTROA and D_BUNNY remain as finite-score qualifications. The Episode 1 human-playtest build and release gate are unchanged.

Receipts: [complete-state loop proof](../results/music-loop-d-e3m9-state-proof-20260928.json), [opening reference](../results/music-e3m9-opening-reference-20260928.json), [six reader/mixer checks](../results/music-track-qualification-d-e3m9-stateproof-20260928-r2.json), [audio-worker checks](../results/music-audio-worker-e3m9-stateproof-20260928.json), [map-selection checks](../results/music-events-map-selection-e3m9-stateproof-20260928.json), [actual host run](../results/music-host-e3m9-stateproof-integration-20260928.json), and [preparation/catalog report](../results/music-preparation-ultimate-doom-e3m9-stateproof-20260928.json).

## 2026-09-28 — Qualify the Episode 3 finale's looping D_BUNNY score

Reviewing the finale callback against the playback catalog exposed a mode
mismatch in the evidence plan: `Finale.sb.ps1` starts `Bgm.BUNNY` with
`loop = true`, while the recent exploratory qualification treated D_BUNNY as
a finite one-shot ([finite qualification](../results/music-one-shot-dbunny-20260928.json),
[mode-rejection check](../results/music-playback-one-shot-dbunny-20260928.json),
and [finite-mode worker check](../results/music-audio-worker-one-shot-dbunny-20260928.json)).
That report could not satisfy the real finale callback. The engine request is
unchanged; this work qualifies the score in the mode the game actually
requests.

Using the installed Steam Ultimate Doom IWAD and the pinned soundfont, D_BUNNY
has MUS hash `5A4CCE0F63CD3B42C1391D319AF418D9BEF241E4760C993A927D6DEC1C76A694`
and a 62-second score period (2,734,200 frames at 44.1 kHz). Two continuously
synthesized periods cover 124 seconds. Their complete normalized state matches
at both boundaries with 12 voices and state hash
`3F786BA8A1CD93BD27FE2FDA182572306A7C5A384A92990865E96BC7AC096780`. The
independent eight-second opening is exact at PCM hash
`80604CBA00AD0E701AC03D946B074AD3E308AA250904AB515110CD7ED5593A77`. This is
a two-period complete-state recurrence proof, not a third independently
rendered period. Preparation took 272.532 seconds (257.384 seconds rendering,
writing and snapshotting) under PowerShell 7.6.5. The single-track catalog
hash is `C075374CCC60CD75819C8C9824F414570688C7AF4BCAD1ED60D43243E77A7A71`.

Six real-reader/mixer checks reproduce the independent opening and loop seam;
17 persistent-playback checks accept Bunny as a loop; ten checks pass in the
actual waveOut worker with independent PCM schedule comparison. The worker
submitted 176,400 frames and returned 171,360 before its controlled shutdown,
leaving a 5,040-frame queued-device tail unreturned; it closed without worker
or cleanup errors. Its rebuffer counter reported one event. These short,
synthetic worker checks do not certify uninterrupted finale playback or
acoustic quality. Fifteen engine-event checks instantiate the actual `Finale`,
advance `Finale.Update()` across the text-to-art transition, confirm its
`D_BUNNY, Loop=true` event, validate that qualification against the installed
IWAD, then send the event through the persistent playback reader and mix one
second of nonzero Bunny audio. The event receipt pins the installed IWAD,
generated engine bundle, bundle builder and finale source; the bundle SHA-256 is
`19DE3303C005C6BD6CF96F7A101C2D7AD34B43CA678E1D65FD2ECE7A1E5E7038`. No
gameplay or audio algorithm changed.

The playback and worker harnesses now accept the track named by a one-shot
qualification instead of hardcoding D_INTRO, and the playback harness accepts
any current loop qualification rather than hardcoding D_E1M1. This lets tests
exercise real Bunny loop samples alongside the already qualified D_INTRO
one-shot. D_INTROA also has a deterministic finite-score qualification, but
the current Ultimate Doom opening code does not request `Bgm.INTROA`. Its
separate [one-shot qualification](../results/music-one-shot-dintroa-20260928.json)
is tested by the current generalized [playback](../results/music-playback-introa-generalized-20260928.json)
and [worker](../results/music-worker-introa-generalized-20260928.json) suites;
the two-pass render is 438,480 frames (6.857-second score plus 3.086-second
release tail), peaks at 15 voices, and clips no samples. It is inventory
coverage, not an additional game path. The generalized tests
also retain the default E1M1/D_INTRO behavior: [13 event checks](../results/music-events-default-regression-20260928.json),
[17 playback checks](../results/music-playback-default-regression-20260928.json),
and [10 waveOut worker checks](../results/music-worker-default-regression-20260928.json) pass.

Receipts: [loop qualification](../results/music-loop-d-bunny-state-proof-20260928.json),
[opening reference](../results/music-bunny-opening-reference-20260928.json),
[reader/mixer checks](../results/music-reader-dbunny-loop-20260928.json),
[playback checks](../results/music-playback-dbunny-loop-20260928.json),
[audio-worker checks](../results/music-worker-dbunny-loop-20260928.json),
[finale event-to-playback integration](../results/music-events-bunny-finale-playback-20260928-r2.json),
and [preparation/catalog report](../results/music-preparation-dbunny-loop-20260928.json).

## 2026-09-28 — Aggregate Ultimate Doom soundtrack and runtime verification

Revalidated existing local qualifications into a 30-entry aggregate loop
catalog: the 27 unique map-track names from the installed Ultimate Doom WAD,
plus D_INTER, D_VICTOR and D_BUNNY. No track was re-synthesized. The atomic
catalog publication took 12.055 seconds; its SHA-256 is
`24073D082C9CD89C7931521DDA567F76261CE8F67CBC6EB465730999EC27A2BF`. The
source WAD SHA-256 is
`6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`; the
soundfont SHA-256 is
`82475B91A76DE15CB28A104707D3247BA932E228BADA3F47BBA63C6B31AAF7A1`.

All 30 readers opened together and a source-pinned engine integration passed
126 checks. It initializes all 36 maps through the actual engine and checks
each emitted music event against the same live catalog/playback state; it also
advances D_INTER, the Episode 1 D_VICTOR callback, and the real Episode 3
Finale.Update() transition from D_VICTOR to D_BUNNY. Every callback advances
the selected reader. This is map music-selection and playback integration,
not route completion or audible campaign coverage.

Opening the three-period qualifications used another 2.958 GiB of output
whose third period is already proved byte-identical to the second. The reader
now validates metadata for all qualified periods but hashes only the first
and repeating playback payloads. For this catalog that changes the bytes
verified on each open from 13.09 GiB to 10.131 GiB; the proof-only PCM remains
on disk and its original qualification is unchanged. A focused reader/mixer
test passes 19 checks, including exact loop-boundary samples and a negative
control whose redundant third-period file is missing; the actual waveOut
worker passes ten. The all-catalog open-time samples (9.696 seconds before,
10.726 seconds after, each after previous full payload scans) are noisy and do
not support a wall-time speedup claim.

A current-reader PowerShell 7.6.6 headless host run opens all 30 reports,
starts E1M1/D_E1M1, advances 69 tics in 2.003 seconds, submits and returns all
86,940 audio frames, closes the device, and reports no worker/cleanup error,
unconsumed packet or canceled audio. One queue-empty/rebuffer observation
occurred after the final packet at shutdown, with no mid-run observation or
rebuffer resume. Its PCM digest matches the earlier full-catalog host run.
This does not certify audible quality, full-session music under visible
Terminal rendering load, uninterrupted campaign playback, or the campaign
route. See the [19-check reader receipt](../results/music-playback-independent-period-open-20260928-r2.json),
[portable optimized-host receipt](../results/music-host-full-campaign-catalog-optimized-20260928.json),
[126-check integration](../results/music-ultimate-doom-campaign-catalog-integration-20260928-r5.json),
and [aggregate preparation receipt](../results/music-preparation-ultimate-doom-loops-20260928.json).
The local catalog and generated PCM remain out of Git.

Two early aggregate-integration attempts stopped on test-script issues: an old
qualification shape omitted the optional `Mode` property, and a loop counter
collided with the script's validated `Map` parameter. Both raw failures are
preserved in `results/music-ultimate-doom-campaign-catalog-integration-20260928.json`
and `results/music-ultimate-doom-campaign-catalog-integration-20260928-r2.json`;
neither was an engine defect.

## 2026-09-28 — Two-minute full-catalog waveOut host

At commit `40924e7db9ac7171fd150c5e0de26f8b6512a9a5`, ran the real PowerShell
simulation, 16 renderer workers and waveOut device headlessly for 120 seconds
on HMP E1M1 with the full 30-track catalog and no input or screen capture. The
120.001-second session advanced 4,199 tics (34.991 tics/sec) and completed
5,791 host updates (48.258/sec). These are not Terminal writes or display
presentations. The session stayed on D_E1M1 for 5,290,740 frames, crossing its
96-second prepared music loop boundary.

The audio worker submitted and returned all 5,290,740 frames, used at most
three queued packets, clipped no samples, and closed without worker or cleanup
errors. Mix time was 0.522 ms median, 1.174 ms p95, 1.592 ms p99 and 46.929 ms
maximum; exactly one packet exceeded the 28.571 ms interval. Packet age at
submission was 80.491 ms p95 and 97.303 ms maximum. One queue-empty/rebuffer
observation occurred after the last packet at shutdown; there was no active-run
queue-empty observation or recovery. This is a no-input, single-map device
run, not full-campaign continuity, acoustic review or visible performance
qualification. No recording was made.

The [portable receipt](../results/music-host-e1m1-loop-seam-20260928.json)
pins the catalog, IWAD, current sources and raw ignored report hash. The broader
[performance record](performance.md#two-minute-audio-loaded-headless-e1m1-run--september-28-2026)
keeps headless host updates distinct from PresentMon display transitions.

## 2026-09-28 — Save/load audio regression on the optimized reader

PowerShell 7.6.6 ran the real simulation and waveOut audio worker with the
qualified Episode 1 catalog and the current two-period playback reader. All 15
checks passed across save, rejected load, new game, successful load, slot
replacement, replay-archive restoration, music epoch resets, D_E1M1 selection,
and clean audio-device shutdown. This is focused session evidence, not a
physical menu/playback review or campaign completion. The [portable receipt](../results/episode1-save-worker-reader-optimized-20260928.json)
pins the harness, catalog and run result.

## 2026-09-28 — Add evidence figures to the working article

Refresh `docs/article-draft.md` with the two-minute full-catalog host result,
the current save/load audio-worker receipt, and the qualified state of the
30-entry Ultimate Doom music catalog. Correct the current-source actor-mask
description: tic 35 has four candidate-only edge pixels; tics 70 through 280
have none, and the captured sequence does not reproduce the Gibs-through-wall
view. Add two original, WAD-free SVG figures: one explains the cell and pixel
tradeoffs of Classic, Matrix and AnsiArt; the other distinguishes simulation,
host-update, Terminal and display measurements while showing the measured
runs. Both SVGs parse as XML and render through ImageMagick for visual review.
The figures are diagrams based on documented architecture and measurements,
not captured gameplay frames. The [article draft](article-draft.md) remains a
working paper; the human route, editorial review, and final publication package
remain open.

## 2026-09-28 — E3M6 worker scaling under actual waveOut load

At source commit `50d6190e8a212d74d2d7f18cf0fc4b5b2b0c7c58`, ran the real
PowerShell simulation, software-rendering processes, full 30-track music
catalog and waveOut device on HMP E3M6 with no input and headless output. The
Steam IWAD SHA-256 is
`6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`; the
catalog SHA-256 is
`24073D082C9CD89C7931521DDA567F76261CE8F67CBC6EB465730999EC27A2BF`.
Commands differed only in `-Workers`, `-Seconds`, and the report path. The
16-worker 120.001-second run completed 2,957 tics (24.641/sec) and 4,089 host
render updates (34.075/sec), with 28.266 ms median and 49.468 ms p95 frame
latency. It observed 280 queue-starvation/rebuffer events; all 3,728,340
submitted audio frames were returned, with no unconsumed packets, clipping,
device error, or cleanup error. Worker working set was 4,946,075,648 bytes.

Two follow-up 30-second runs tested eight and twelve workers. Eight workers
completed 853 tics (28.432/sec) and 920 updates (30.665/sec), with 30.120/56.072
ms median/p95 latency, four queue-starvation/rebuffer events, and 2,491,588,608
bytes of worker working set. Twelve workers completed 794 tics (26.466/sec)
and 954 updates (31.799/sec), with 29.534/57.804 ms latency, 25 queue events,
and 3,682,467,840 bytes of worker working set. Both returned every submitted
audio frame and closed cleanly. All three queues peaked at one packet. The
first queue-empty observations occurred before shutdown, so these were active
run events; telemetry alone does not establish an audible dropout.

This is not a paired worker-count test: the 16-worker run lasted four times
longer, and each count has only one sample. Eight workers led on simulation
rate and queue continuity in these samples, while sixteen led on completed
host updates. No worker default changes from this evidence. Host updates are
not Terminal writes or display presentations. The portable
[comparison receipt](../results/music-host-e3m6-worker-scaling-20260928.json)
pins the metrics and hashes; full raw reports remain in ignored `local/`.

To narrow renderer costs, added
[`Measure-FastRendererPhases.ps1`](../scripts/Measure-FastRendererPhases.ps1)
with an option to replay each production 20-column stripe sequentially at a
fixed game state. On the 311-actor E3M6 start view, 192 calls across 16 stripes
had 14.920 ms median / 17.710 ms p95 total, including 9.754 / 12.221 ms for
actors and 4.075 / 5.219 ms for geometry. Stripe medians varied from 11.273 to
17.850 ms. This isolates renderer work; it does not include concurrent worker
scheduling, snapshot IPC, simulation, or audio. The
[current-source profile](../results/renderer-stripes-e3m6-start-16w-current-20260928.json)
stores per-stripe hashes and phase samples.

One measured code experiment moved actor x-scale division after the lateral
frustum rejection. All 16 fixed-state stripe pixel hashes matched exactly, but
current-source reruns measured 9.754 ms median actor work and 14.920 ms total
versus 9.730 and 14.770 ms for the candidate—within timing variation, with no
demonstrated speedup. The source change was reverted. Its
[candidate profile](../results/renderer-stripes-e3m6-projection-candidate-20260928.json)
preserves the experimental source hash. The working renderer blob was checked
against HEAD after the revert. No screen recording was made.

## 2026-09-28 — Rebuild the Preview.3 candidate from current source

A clean package build initially stopped at the new article SVGs because the
package script allowed only PowerShell, Markdown, JSON and text files under
`docs/`. The package input allowlist now accepts SVGs in documentation while
continuing to reject other unknown file types. Its 22-check music-reader
regression also passes on PowerShell 7.6.5; the portable result is
[`music-loop-reader-head-fee5ea2-20260928.json`](../results/music-loop-reader-head-fee5ea2-20260928.json).

Built and extracted a new local, unpublished Preview.3 ZIP from clean source
commit `aeb6772a3ddac78b24782d95b4c7f1b738136ab6`. All 537 manifest entries
match their extracted SHA-256 and length; the checksum file matches the
1,537,992-byte ZIP at
`DAFC42D13D9D754C26CB7EDC92CAED8D51DB2109A65D2081B6078A6F44C59579`. The
archive contains both article SVGs and no research PDF, WAD, soundfont, media,
or native binary. Its static license audit finds the root GPL license and
third-party notices, the origin record, and GPL terms in all 206 vendored
PowerShell files.

The extracted launcher preflight under PowerShell 7.6.5 found Windows
Terminal, the installed Steam Ultimate Doom IWAD, and all 36 maps. A
two-second headless sound-enabled host run with the local Episode 1 catalog
advanced 69 tics and completed 89 host updates with no host/simulation error
or audio-backpressure sample. This is startup evidence, not a full audio or
human campaign check. The [candidate receipt](../results/preview3-current-candidate-validation-aeb6772-20260928.json)
records the package, license, reader, preflight and host results.

The extracted clean package reports gameplay fingerprint
`861FA06A414183D7753C8EEF840FB402D0E8D3E8A12139D95772D67F461A6CF6`, while
the prior r7 receipt reports `D627BDF3D3605093095D9185EA564487ECE49A1FE2186134F2257191AB631682`.
The fingerprint hashes raw files; line-ending normalization makes all 216
gameplay/session input texts identical. The refreshed [Episode 1 handoff](episode1-playtest.md)
therefore directs Jason to the exact extracted package and uses fresh r6
record/report paths. The full human route and public release remain pending.

## 2026-09-28 — Correct fuzz partition fixture contamination

A Classic fuzz partition check initially reported a 13-pixel mismatch at
173 degrees with a single worker strip. The renderer was unchanged. Inspection
showed that the opaque-actor negative-control render reused the serial frame
buffer; fuzz reads adjacent rows from that buffer, so the diagnostic render
altered the next comparison's history. The control now uses its own render
context, and encoded-byte failures report pixel coordinates and colors.

The corrected baseline passes 320,000 pixel comparisons over five views with
one worker strip and five encoded-strip checks. The normal 16-worker run also
passes all 320,000 pixels over five views and 80 encoded-strip checks. Both
receipts pin renderer hash
`6E5B10FFE976179D04C4BA877739EEFC5892E1003403E3A9DED0E63D2817A8B4`; no game
renderer code changed. This closes a test-fixture false alarm, not a product
rendering defect. The results are
[`single-strip`](../results/render-partitions-fuzz-baseline-aeb6772-20260928.json)
and
[`16-worker`](../results/render-partitions-fuzz-workers16-20260928.json).
The corrected path also passes Matrix/Katakana and AnsiArt/Katakana with seven
workers: each matches 320,000 pixels over five views and 35 encoded strips.
Their receipts are
[`Matrix`](../results/render-partitions-fuzz-workers7-matrix-katakana-20260928.json)
and
[`AnsiArt`](../results/render-partitions-fuzz-workers7-ansiart-katakana-20260928.json).

## 2026-09-28 — Inspect an E1M1 actor-mask edge

Replayed the first 140 commands of the local human E1M1 prefix and isolated
the actor masks at input tic 140. The only reference-only sprite pixels in
this view belong to patch `BON2B0`, at x=229, y=90–105 (13 opaque pixels).
The candidate's background depth at that column is 236.735 map units, while
the isolated sprite is 514.134 units away; the candidate therefore hides the
sprite behind a nearer non-plane surface. These account for 13 reference-only
mask and full-scene pixels, with zero candidate-only full-scene pixels in the
actor region. This narrows one adapted-renderer difference but does not
reproduce the reported through-wall view or establish original-executable
parity. The compact, source-pinned
[depth audit](../results/actor-occlusion-depth-audit-human-prefix-tic140-20260928.json)
excludes both the private input recording and diagnostic images; those remain
under `local/`.

## 2026-09-28 — Refresh the article against the current candidate

The article's Preview.3 paragraph still carried figures from the previous
package receipt. It now reports the current candidate's 537 verified files
(538 ZIP entries with the manifest), PowerShell 7.6.5 reader/preflight checks,
and 69 tics / 89 host updates in the two-second sound-enabled smoke, with no
host error or audio-backpressure sample. The smoke does not record a returned
PCM frame count, so the article no longer attributes the separate 86,940-frame
result or post-final-packet observation to this package run. The rendering
section now links the latest isolated actor-depth audit and preserves its
scope limits. A local link check found 31 article links: all 26 local file
targets and all three heading anchors resolve. See the updated
[article draft](article-draft.md); the human episode result and release review
are still pending.

## 2026-09-28 — Repeat the E3M6 loaded host across PowerShell versions

The earlier E3M6 worker-count result showed 24.641 simulation tics/sec in a
120-second PowerShell 7.6.6 run. To determine whether that low result
reproduced, I ran the same 16-worker, headless HMP E3M6 workload with the
Steam IWAD, full 30-entry catalog, sound enabled and no input, alternating
two 30-second runs each on PowerShell 7.6.5 and 7.6.6. Both 7.6.6 samples
were below both 7.6.5 samples: 27.632 / 28.365 versus 33.497 / 34.932
tics/sec. A subsequent 120-second 7.6.5 run reached 34.366 tics/sec; the
earlier 7.6.6 120-second run remains 24.641. Current source commit
`9701f9b` and earlier pin `50d6190` have identical `src/` trees; intervening
script edits are package and measurement/partition-test tooling. This
supports a runtime-associated difference in these observations, not a claim
that the PowerShell update caused a performance regression. Environmental
load and scheduling are not fully controlled.

Audio returned every submitted frame in four of the five current-source runs.
The final 7.6.5 30-second run ended with one unconsumed packet and a 5,040-frame
canceled-tail upper bound; the device still closed without errors. The
120-second 7.6.5 run submitted and returned all 5,198,760 frames with zero
unconsumed packets, while recording five rebuffer observations. Device queue
polling cannot prove an audible interruption. These headless runs do not
measure Terminal presentation or displayed FPS, and none meets or closes the
35-tic/60-display gate. No worker default or product source changed.

The [portable receipt](../results/music-host-e3m6-runtime-comparison-20260928.json)
records each sample, source/WAD/catalog pins and raw-report hashes; the
complete reports remain in ignored `local/`. Updated [performance notes](performance.md),
the [article draft](article-draft.md) and [active roadmap](roadmap.md) now
describe the repeated result and its limits.

## 2026-09-28 — Reject visible-only Spectre sort optimization

On source commit `214fc20`, test a renderer-only idea: because fuzz samples
vertical neighbors in the same screen column, project only actors overlapping
each worker stripe, then preserve stable far-to-near ordering among those
sprites. Against the unmodified renderer on the Steam E3M6 HMP state, with four
live shadow actors, the candidate matches indexed pixels and the depth buffer
exactly in ten complete frames and 64 production-width stripes. The five view
headings are 0, 37, 90, 180 and 270 degrees at captured tics 1 and 701; each
heading was compared as a full frame, and headings 90 and 270 also cover all
sixteen stripes.

The alternating four-round static full-frame measurement retains twenty
samples per renderer over five headings. Candidate median is 71.944 ms versus
69.180 ms baseline (4.0% slower); P95 is 90.970 versus 97.830 ms and mean is
75.007 versus 82.616 ms, with large outliers on both sides. This small sample
does not establish a stable speedup, and the candidate adds projection
descriptors. Reject it and restore the original production renderer. Exact
parity and the full timed samples are in the
[comparison receipt](../results/renderer-e3m6-fuzz-visible-order-pair-20260928.json).
This was an isolated static renderer experiment, not a live-worker or game
pacing result; no product performance claim follows.

## 2026-09-28 — Sweep the E1M1 pool Gibs views

To narrow Jason's report of pre-placed `POL5` Gibs showing through walls near
the blue armor, replay the retained E1M1 human input to the two recorded camera
states nearest the armor and pool Gibs (input tics 8400 and 8750). At each
state, compare each of the two documented Gibs actors in isolation at sixteen
headings, against the adopted `ThreeDRenderer`; this yields 32 camera views and
64 isolated actor/view comparisons. The Steam IWAD, human input and current
`FastRenderer.ps1` hashes are in the [portable sweep receipt](../results/episode1-pool-gibs-angle-sweep-20260928.json).

There is one candidate-only actor-mask pixel across the sweep, for the Gibs
actor at `(2112,-2688)`, input tic 8400, heading 0 degrees. A detail rerun found
it at screen `(223,97)`. In the reference, both the actor and underlying floor
pixel have palette index 8, so the reference actor mask does not change there;
the candidate's floor index is 5 and changes to 8 when the actor is drawn.
Candidate plane id 32 leaves plane depth at infinity, consistent with the
book's planes-before-world-sprites pipeline. This is a one-pixel background
and mask disagreement, not evidence of the actor showing through a wall. The
exact view Jason saw remains unknown, this comparison uses the adopted
renderer rather than the original executable, and broader visual parity is
still open. Pixel/depth/clipping detail is in the [focused receipt](../results/episode1-pool-gibs-angle0-detail-20260928.json).

## 2026-09-28 — Publish Preview.3 for community testing

At Jason's direction, publish the next playable preview now so other people
can test it; do not hold publication for his complete Episode 1 playthrough.
The public prerelease is [pwshDoom 0.1.0-preview.3](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.3),
tagged at clean source commit `34e3d1755f458e5dbdc82e0c8458e0f1f51df634`.
The source-inclusive ZIP is 1,544,921 bytes and contains 537 hash-manifested
files plus the manifest. Its SHA-256 is
`97293984A38CFDC9635EEA8DB63989C0C24068DFD063283CF4F474C74142DD5B`.
Both article SVGs are included; the research PDF, IWAD, soundfont, recordings,
media and native binaries are excluded. Every manifest hash was verified after
extraction, and the freshly downloaded public ZIP matches the local archive.
The adjacent checksum asset is `SHA256SUMS.txt`.

The packaged launcher preflight passed under PowerShell 7.6.5 with the installed
36-map Steam Ultimate Doom IWAD and Windows Terminal. All 22 packaged
music-reader regression checks pass. A two-second sound-enabled, headless E1M1
startup using the locally prepared Episode 1 catalog completed 69 simulation
tics and 76 host frames in 2.003 seconds, with one audio event, no reported
audio-backpressure observation and no host error. This is startup evidence;
headless output frames are not displayed-frame performance, and the short run
does not prove audible quality or campaign audio continuity. Full Episode 1
human completion remains pending, along with broader campaign, fidelity,
audio and pacing qualifications. The [publication receipt](../results/preview3-publication-20260928.json)
records the asset digests and bounded checks. The user's research PDF remained
outside the package and uncommitted.

## 2026-09-28 — Recheck the chainsaw fix against current source

The reported E1M2 crash came from PowerShell comparing wrapped `Angle`
instances with `-gt` in `WeaponBehavior.Saw`; the fix compares their numeric
`.Data` values. The focused current-source check against the installed Steam
Ultimate Doom IWAD again passes both the real E1M2 chainsaw hit (imp health 60
to 56 on the first attempt) and the homing-turn action. The refreshed portable
result is [`saw-attack.json`](../results/saw-attack.json).

I also replayed the retained 26,731-command human input through the current
simulation. All commands were consumed without a simulation exception, but
the saved source fingerprint differs, the first of 79 gameplay checkpoints
diverges at tic 350, and the run remains in E1M1. This is not a passing
full-session replay and does not reach the E1M2 attack; the focused saw check
is the evidence that the corrected hit path still executes. The private replay
and its diagnostic report remain under ignored `local/` and are not committed.

## 2026-09-28 — Reject low-value actor-phase optimizations

A fixed E3M6 snapshot contained 280 actors. With one synthetic Shadow actor,
the current renderer's 16 sequential production-width stripes measured an
8.22 ms median actor phase per stripe and a 207.69 ms median for all 16 stripes
in one process. A stable PowerShell merge sort produced the same actor order
as `Sort-Object -Descending -Stable`, but was slower (1.23 ms versus 1.11 ms
per 280-actor sort); keep the existing sort.

Across 100 scans of those actors, converting X/Y doubles to 16.16 values took
1.54 ms, versus 0.23 ms to read cached values. That is about 0.013 ms per
280-actor scan, too small to justify enlarging and versioning the worker
snapshot protocol. Clearing only one 20-column stripe through 200 per-row
array operations took 1.85 ms per worker frame, versus 0.030 ms for the
existing full-array bulk clear/fill; retain the bulk reset. These isolated
PowerShell microbenchmarks exclude concurrent workers, terminal output, and
display presentation. No renderer source change or frame-rate claim followed
those trials; the later shared-order experiment below is a separate measured
change.

## 2026-09-28 — Share the Spectre actor sort across renderer workers

Source inspection showed `Invoke-FastRender` repeats the same stable
far-to-near `Sort-Object` over all actors in every worker whenever any actor
has the Spectre fuzz flag. Move this ordering to `Get-InterpolatedSnapshotBytes`
after camera/actor interpolation. Store a prepared-order bit in the existing
NumericV3 reserved header slot, reorder seven interpolated actor fields and
their appended discrete flags together, and let decoded transport snapshots
skip the renderer's duplicate sort. Keep direct-object snapshots on the old
fallback. Game, renderer, and transport algorithms remain PowerShell; the wire
format version and packet length do not change.

The first wrapper-based numeric sort increased preparation by about 85 ms and
was discarded before acceptance. A numeric index array with the existing
stable `Sort-Object` key/order removed that overhead. The [final paired receipt](../results/renderer-shared-fuzz-order-20260928.json)
uses two 24-frame profiles per mode on one fixed HMP E3M6 state (311 actors,
four Spectres), sixteen 20-column stripes, and five warmups. Summed stripe
render CPU median is 229.11 ms legacy and 210.40 ms prepared. After adding
snapshot preparation, the median is 235.92 ms versus 213.55 ms (9.48% lower);
p95 is 7.28% lower. Preparation median itself rises from 0.23 ms to 3.54 ms.
The legacy and prepared full-frame pixel hashes are identical. This is a
sequential per-process CPU profile, not live or concurrent-worker latency,
frame rate, audio load, or Terminal presentation.

Correctness evidence: [13 snapshot transport checks](../results/snapshot-actor-order-20260928.json),
[122 fuzz-rendering checks](../results/fuzz-rendering-actor-order-20260928.json),
and five-view output equivalence through 16 processes in [Classic](../results/render-fuzz-actor-order-classic-20260928.json),
[Matrix](../results/render-fuzz-actor-order-matrix-20260928.json), and
[AnsiArt](../results/render-fuzz-actor-order-ansiart-20260928.json). Each
worker report compares 320,000 pixels with zero differences. The transport
fixture also rejects malformed markers and prepared endpoints; the ordinary
direct renderer fallback remains covered. This improves repeated worker CPU
for Spectre scenes only. It does not resolve actor-through-wall reports,
qualify a campaign route, or demonstrate the 35-tic/60-display goal.


## 2026-09-28 — Assemble the three-style social video set

The user-requested Preview.3-era social asset is assembled from three
successful earlier audiovisual effect-test recordings: Matrix/Katakana on
E1M3 (September 19), Color Art/Katakana on E1M2 (September 12), and Classic
on E1M2 (September 19). Each source receipt reports process-scoped audio
capture and its original MP4 hash. A 30-second segment from each was cropped
to its gameplay window, scaled without color enhancement, labeled, faded at
the audio boundaries, and encoded as 1920×1080 H.264 at 30 fps with 48-kHz
stereo AAC. The 90.021-second showcase is 132,384,922 bytes; separate
30-second clips are also included. ffprobe confirms all four video/audio
streams, and audio level analysis confirms non-silent sound. Six frames across
each style and a 10-second image from each final clip were visually reviewed.

The share-ready files and checksums are in ignored
`local/social-assets-preview3-20260928/`; source footage remains untouched in
`local/recordings/`. The [portable asset receipt](../results/preview3-social-video-assets-20260928.json)
records source/output hashes, upload dimensions and the conservative X check.
The montage is below X's currently documented non-Premium limit of 140 seconds
and 512 MB, so upload fit does not depend on the user's subscription tier.
No upload was performed. This uses older effect-test footage rather than a
fresh current-branch capture; it is a demonstration asset, not release or
performance qualification.

## 2026-09-28 — Reject destination-index increment trial

The fixed-vertical sprite raster loop computes each destination index as
`y*320+x`. A trial initialized the index once per post and advanced it by 320
per row. All six fixed-state E3M6 profiles retained the same full 64,000-pixel
hash. Across three before/after pairs, actor-phase medians per 20-column
stripe were 7.53/7.28 ms, 8.88/7.52 ms, then 8.05/9.28 ms; the last pair
reversed direction, and that profile's total render median also rose from
12.54 to 14.32 ms. Variation is too large for this sample to support a causal
speed claim, so the source change was reverted. Raw profiles remain in ignored
`local/renderer-fastpatch-index-*.json`; no timing result is committed as
product evidence.

## 2026-09-28 — Cull actors before per-process projection

Profiling showed that each render process repeated fixed-point projection for
every actor even though a narrow column stripe can only contain a small part
of the projected sprites. Added a render-only NumericV4 extension to the
interpolated NumericV3 snapshot: the host computes each actor's conservative
screen-column span once in PowerShell, sets the corresponding worker bits, and
each process skips actors that cannot reach its stripe before projection and
raster setup. Simulation packets remain NumericV3. Missing sprite/rotation
geometry conservatively targets every worker, and the direct serial renderer
keeps its original path.

The first serial-stripe profile established that the work was reduced but did
not capture production concurrency, so it was not used as the acceptance
measurement. A paired 16-process E3M6 fixed-state profile includes interpolation,
submission, concurrent software rendering, and encoded-strip retrieval. It
compares four-warmup/24-frame runs in both orders. Median dispatch fell from
51.34 to 42.67 ms in the first pair and 50.24 to 43.07 ms in the
reverse-order pair; the corresponding p95 values fell from 65.56 to 52.68 ms
and 57.85 to 48.83 ms. The mask pass raises median submit cost from about
1.1–1.2 ms to 8.9–9.0 ms, but lowers the peak worker-render median from
37.6–38.1 ms to 17.9–18.8 ms. All paired encoded-strip hashes match. At this
view, 4,274 of 4,480 actor-worker pairs are skipped. The 42.7–43.1 ms dispatch
median remains above 16.67 ms and is not a display-rate result. See the
[measurement record](performance.md#project-actors-only-to-renderer-stripes-that-can-see-them--september-28-2026)
and four final-source [receipts](../results/renderer-worker-mask-impact-e3m6-baseline-final-20260928.json),
[candidate](../results/renderer-worker-mask-impact-e3m6-candidate-final-20260928.json),
[reverse-order candidate](../results/renderer-worker-mask-impact-e3m6-candidate-reverse-final-20260928.json),
and [reverse-order baseline](../results/renderer-worker-mask-impact-e3m6-baseline-reverse-final-20260928.json).

A final launcher-scope review found that the ordinary host loads
`SnapshotTransport.ps1` but not `FastRenderer.ps1`; the initial mask helper
had therefore fallen back to NumericV3 in the real launcher even though the
test profiles explicitly loaded the renderer. Moved the unchanged fixed-point
angle helpers into `SpriteProjection.ps1`, sourced by both the renderer and
snapshot transport. A new bootstrap assertion passes with `SnapshotTransport`
loaded alone, and the normal launcher completes a three-second headless E3M6
run with 83 tics and 94 host render updates. The measurement and partition
receipts below were regenerated against this final source layout.

Correctness passes include 16 NumericV4/bootstrap transport assertions; five-view,
seven-worker Classic partition comparisons on E1M1–E1M4; five-view,
16-worker fuzz comparisons in all three visual styles on E3M6; and the
16-worker Classic session-worker test through screen/menu/automap transport
and a live E1M1-to-E1M2 worker asset reload. The shared sprite math separately
passes 16,392 direction cases, 393,408 rotation boundaries, six `int.MinValue`
edges, and 100,000 angle round trips. Every partition comparison reports zero
pixel differences and matching encoded bytes. These compare pwshDoom's own
PowerShell render paths and do not claim original Doom pixel parity or map
completion. Final-source receipts are indexed in
[rendering fidelity](rendering-fidelity.md#skip-actors-outside-each-renderer-stripe-2026-09-28)
and the [campaign matrix](campaign-matrix.md).

The first optional unmasked phase profile exposed an uninitialized benchmark
field under strict variable checking; the measurement script now initializes
the absent mask statistics explicitly. That was a measurement-harness defect,
not a renderer or gameplay failure.

## 2026-09-28 — Measure the current renderer worker-count tradeoff

After the actor-worker mask change, the current source was exercised in both a
fixed-state renderer pool and a real sound-enabled E3M6 host. Fixed-state
process-pool dispatch medians/p95 were 55.60/61.89, 44.22/49.71,
43.39/49.49, and 45.93/55.47 ms at 4, 8, 12, and 16 workers. The 30-second
host trials ran once each in 8/12/16 order: simulation reached 34.70/31.90/
33.70 tics/sec, completed render jobs reached 29.30/30.60/30.30 per second,
and worker working sets were 2.17/3.31/4.14 GiB. The 8-worker run had no
queue-starvation observation and ended with a 1,260-frame canceled-tail upper
bound; 12 and 16 had five and eight starvation/rebuffer observations. All
devices closed cleanly, with no unconsumed audio packets or worker errors.

This is one short, ordered set, not a reliable default-selection experiment.
The 12-worker renderer also matched serial pixels and encoded strips over five
E1M1 views in Classic, Matrix/Katakana, and AnsiArt/Katakana (320,000 pixels
per style, zero differences). These tests establish internal partition
equivalence, not original-engine parity. The 16-worker default stays in place;
no setting reached 60 completed updates/sec, and this headless run says
nothing about visible Terminal presentation or audible continuity. The
[portable summary](../results/worker-count-host-render-comparison-20260928.json)
indexes the source, IWAD, music catalog, exact parameters, and hashes of the
full raw reports retained under ignored `local/` storage.

An initial PowerShell wrapper saw an inherited native-process exit-code value
after the 8-worker game report had already recorded `ExitReason=Duration`, and
mistakenly labeled that completed run a failure. The remaining runs were
checked against their own report status and error fields; no game failure was
hidden by the wrapper correction.

## 2026-09-28 — Reject two actor-mask bookkeeping shortcuts

After the committed actor-culling change, I tested two ways to lower its host
bookkeeping cost. First, a pre-encoding path appended worker masks to the
interpolated numeric array before producing bytes. It lowered the reported
submit stage but moved the same projection work into interpolation; reversed
24-frame dispatch pairs improved by only 1.01 and 1.54 ms, while the longer
96-frame pair was 2.63 ms slower. The byte output remained identical, but the
total result was not repeatable, so the path was reverted.

Second, I replaced each actor's scan of every worker with a 320-column lookup
and contiguous worker-bit calculation. The masks remained exactly 206 included
and 4,274 skipped pairs out of 4,480, and all six process-pool runs had the same
encoded output hash. One reversed 24-frame pair measured lookup 46.89 ms versus
44.14 ms for the scan; the longer 96-frame pair measured 41.29 versus 36.83 ms.
The first pair was heavily affected by scheduling variance, and neither short
nor long evidence supports a full-dispatch gain. The mapping code was reverted.

The trial's five-view serial comparisons still passed for all three styles at
12 workers and for a 16-worker Classic fuzz fixture. These are correctness
results for the rejected prototype, not campaign completion or original-Doom
parity. The [portable trial receipt](../results/actor-mask-bookkeeping-trials-20260928.json)
stores hashes for its source patches and full raw reports under ignored
`local/`. The current source remains the committed renderer path; the separate
16-check snapshot transport receipt was refreshed against it.

## 2026-09-28 — Revalidate the current Episode 1 playtest candidate

The current renderer source commit `32400a85a256c6063960297fefeeb3f961a9349e`
was checked against the installed Ultimate Doom IWAD
`6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F` on
PowerShell 7.6.5. The full 36-map load/idle/render smoke passes; the separate
69-transition fixture reaches real E1M9 and E1M4 map loads for the secret
return and checks finale state, but it does not complete those maps. The five
real IWAD boss-trigger fixtures pass 97 checks. The focused chainsaw/homing
action check passes twice, synthetic menu input passes ten checks, and all 24
session-screen frames render without an error.

The actual 16-process session worker preserves four screen/menu/automap/map-
reload checkpoints over 256,000 indexed pixels and 64 encoded strips. Five
E1M1 camera views in each of Classic, Matrix/Katakana, and AnsiArt/Katakana
match the serial renderer exactly: 960,000 total compared pixels, zero
differences. `Play.ps1 -Check` resolves the Steam IWAD, Windows Terminal, and
local music catalog. A five-second headless host run with effects and the
eleven-track Episode 1 catalog starts without an error and exits at its
requested duration: 174 tics and 226 headless render updates, or 34.79 tics/sec
and 45.18 updates/sec, with 4,155,396,096 bytes of combined worker working
set. This short run is not audio continuity, audible review, or a pacing
guarantee.

The [current candidate receipt](../results/episode1-current-human-candidate-20260928.json)
stores check counts, source and IWAD pins, and hashes for the full reports
preserved under ignored `local/episode1-current-candidate-20260928/`. The
updated [human-playthrough handoff](episode1-playtest.md) now names the current
source and uses fresh `r3` report/save/settings paths. Jason's complete HMP
Episode 1 human route remains pending; no map completion is inferred from
these fixtures or smoke tests.

## 2026-09-28 — Reject wall texture-step precomputation

A per-column wall texture scale produced exact serial/worker pixels across the tested E1M1 and E3M6 views, but paired timing was inconclusive: E1M1 regressed in 15/20 matched samples, and E3M6 had no median paired advantage. The source change was reverted. Timings, hashes, and the rejected patch are documented in [performance measurements](performance.md#rejected-wall-texture-step-precomputation--september-28-2026) and retained under ignored `local/renderer-vstep-incremental-ab-e3m6-20260928/`.

## 2026-09-28 — Run the existing Episode 1 route regressions

Against game-source commit 32400a85a256c6063960297fefeeb3f961a9349e and
the installed Ultimate Doom IWAD, the current E1M1 and E1M2 HMP route runs
reached intermission. The independent E1M2 replay matched 86 route samples and
entered E1M3. The current E1M3 and E1M4 route runs ended in player death at
waypoints 144 and 172. Their plans match the earlier successful receipts, but
the current route-driver hashes differ, and neither death exposed a reproducible
gameplay invariant failure. No route tuning or defect claim follows. Full inputs and
traces are retained in ignored local/; the
[portable regression receipt](../results/episode1-route-regressions-current-20260928.json)
records their hashes and limits. This does not substitute for the complete
human Episode 1 playthrough.

## 2026-09-28 — Publish generated engine bundle atomically

The retained concurrent save-worker failure came from multiple harnesses
writing the shared `local/engine-bundle.ps1` directly. The builder now writes
UTF-8 bytes to a unique temporary file beside the cache, then atomically
replaces the destination. Readers therefore see a complete prior or new
bundle. Eight simultaneous PowerShell 7.6.5 builders all exit successfully;
the final 1,587,533-byte bundle has the expected SHA-256, parses without
errors, and leaves no temporary files. This removes the observed cache-write
collision; it does not establish safety for unrelated shared test outputs or
prove concurrent gameplay pacing.

Evidence: [concurrent publication report](../results/engine-bundle-concurrent-publication-20260928.json).

The human Episode 1 candidate receipt is refreshed against the committed tree
`f612d839f74c598c086b91412593dff0fbe2bcbb`. A fresh Steam-IWAD smoke loads
all 36 Ultimate Doom maps, advances 35 idle tics, and renders two serial
320x200 frames per map (36 passed, zero failed). The E1M2 chainsaw fixture was
also rerun on this checkout: the first real hit lowers the imp from 60 to 56
health and the Doom II homing-angle check passes. These narrow checks do not
replace Jason's one HMP Episode 1 playthrough.

Evidence: [current human-playthrough candidate receipt](../results/episode1-current-human-candidate-20260928.json),
[fresh map smoke](../results/episode1-map-smoke-current-candidate-20260928.json),
and [chainsaw fixture](../results/saw-attack.json).

## 2026-09-28 — Pack renderer map geometry

The numeric renderer's BSP hot path and each render worker previously indexed
per-seg/per-node hashtables. It now uses compact flat PowerShell arrays, carried
through render-asset cache format v7. The E3M6 16-stripe profile preserves the
full-frame hash; the first candidate run lowers median stripe time 7.5% versus
the before-change run and a second short candidate run remains below that
baseline. Treat this as directional pending randomized paired dispatch and
memory measurement; it is not 60-FPS evidence.

Focused checks pass: 20 masked-wall assertions; 36 Ultimate Doom map
load/idle/render cases; five-view, 16-worker exact output in Classic,
Matrix/Katakana, and AnsiArt/Katakana; and an E1M1-to-E1M2 reload with all
worker processes preserved. See [performance details](performance.md#pack-per-map-bsp-geometry--september-28-2026) and the [compact receipt](../results/packed-map-geometry-profile-20260928.json).

## 2026-09-28 — Keep interactive audio advancing across simulation packet gaps

The four-buffer D_E3M6 host investigation recorded a 67.42 ms maximum
simulation-packet interval around an active queue-empty event, while nearby
PowerShell mix blocks took 0.5–0.6 ms. I changed interactive playback so the
audio runspace can fill a free waveOut slot from its current active music/effect
state when the packet queue is temporarily empty. It does not invent a game
event or packet sequence. Shared pause, map-epoch reset and explicit drains
still stop the fill. Headless hosts stay packet-exact unless
`Invoke-Doom.ps1 -RealtimeAudio` is explicitly selected.

The actual-device continuity test passes eight checks with one D_E1M1 packet:
ten total blocks are submitted, music advances across a no-packet interval,
pause stops production, resume continues the cursor, and a packet-bounded drain
returns all 12,600 frames with no rebuffer/starvation. The first test invocation
reached playback but exposed a report-writer path bug; after correcting the
test harness, its rerun passed all eight checks.

The four-second D_E3M6 simulation-host run under PowerShell 7.6.5 consumes 128
packets and generates 16 additional blocks. It submits 181,440 frames; 176,400
return before shutdown, with a 5,040-frame canceled-tail upper bound. The
worker reports zero active starvation/rebuffer and no error. The realtime
save/load/new-game worker run passes 15 checks over 77 packets, including three
audio epoch resets; it generates 29 additional blocks, returns all 133,560
submitted frames, and reports no starvation, rebuffer, or error. A fresh
current-source all-map load/35-idle-tic/two-frame smoke passes 36/36 cases.

The PowerShell 7.6.5 host command was `scripts/Invoke-Doom.ps1 -Wad
<Steam DOOM.WAD> -Workers 12 -Seconds 4 -Headless -Sound -RealtimeAudio
-MusicCatalog local/music-prepared-ultimate-doom-loops-20260928.json
-Episode 3 -Map 6 -Skill 3 -Style Classic`. Current raw receipts are under
ignored `local/`: `audio-realtime-continuity-poc-r2-20260928.json`,
`audio-e3m6-realtime-host-20260928.json`,
`save-worker-realtime-music-20260928.json`, and
`campaign-smoke-realtime-audio-code-20260928.json`. These software queue
checks do not measure acoustics, actual device underrun, event-to-speaker
latency, or sustained full-campaign behavior; they also do not make a slow
simulation keep pace with 35 tics per second. The focused result and [current
Episode 1 candidate receipt](../results/episode1-current-human-candidate-20260928-r3.json)
retain portable summaries and source hashes. The receipt is implementation
commit `41e167f04ab298c4af4c3f5150b2861ad8e3417c`; it records a new 36-map
smoke and the bounded realtime checks without claiming human route completion
or acoustic/device-underrun qualification.

## 2026-09-28 — Skip repeated prepared actor-order scans

The renderer now checks the interpolated packet's existing
`ActorsDepthSortedForFuzz` flag before scanning the full actor list. Packets
marked as prepared skip that repeated discovery loop in every render worker;
direct snapshots retain the original Spectre detection and sort fallback.

The change is pinned at `da3829c8d980789de2fc95fd51d09c5488982d95`. It passes
122 focused fuzz checks, exact five-view E3M6 output in 16 worker processes for
Classic, Matrix/Katakana, and AnsiArt/Katakana, and 36/36 map load/idle/render
cases with the Steam Ultimate Doom IWAD. It does not add route-completion
evidence.

Two matched short E3M6 profile runs per version use the same 311-actor state
and actor-worker masks. Mean actor-phase stripe medians move from 3.0211 ms to
2.8863 ms; mean total stripe medians move from 7.6236 ms to 7.5026 ms. All
before/after full-frame hashes match. These sequential single-process stripe
samples have material variation and do not prove a concurrent-host, live
Terminal, or FPS gain. See the [measurement record](../results/renderer-prepared-actor-order-fastpath-20260928.json)
and [current Episode 1 candidate receipt](../results/episode1-current-human-candidate-20260928-r4.json).

## 2026-09-28 — Filter renderer actors during worker snapshot decoding

After host-side projection had added exact stripe masks, every worker still
walked all 311 E3M6 actors to test its mask. NumericV4 decoding now reuses a
worker-local list containing only intersecting actors, and the PowerShell
renderer draws that list directly. The full actor array is preserved; stable
filtering keeps the prepared Spectre draw order. The simulation packet and
wire format are unchanged.

The source is pinned at `ab73eba07135fe0f834554be12aae279c151c314`. Snapshot
transport passes 18 checks. Actual 16-process comparisons pass five E3M6 views
in Classic, Matrix/Katakana, and AnsiArt/Katakana: 320,000 pixels and 80
encoded strips per style with no differences. A fresh 36-map smoke passes;
the 16-worker Classic session check matches 256,000 pixels and 64 encoded
strips while reloading E1M2 without worker restart. The [compact profile
receipt](../results/renderer-visible-actor-filter-20260928.json) indexes all
source hashes and ignored raw reports.

Two order-reversed 40-frame-per-stripe profiles lower actor-phase medians about
30% and combined decode-plus-render CPU 4.1% / 8.1%. Snapshot decode cost rises
12–13%, but both paired render totals also fall. The result is sequential
worker-equivalent CPU accounting, not concurrent latency or displayed FPS.
No additional map route or independent original-binary parity is claimed.
The single-playthrough handoff now pins this candidate and uses fresh `r6`
input, report, save, and settings paths. The local-state check found only
Jason's earlier `r2` session report; no `r6` outputs exist.

A five-second headless `Invoke-Doom` run with `-Sound`, the prepared Episode 1
catalog, and 16 workers exercises the current simulation/audio/render-worker
startup together. It reaches 174 tics and 135 completed host updates, then
exits at the requested duration without a host error. The run is not a route,
display-rate sample, or measurement of acoustic continuity. See the [raw
report](../local/host-visible-actor-filter-e1m1-audio-20260928.json) and
[candidate evidence index](../results/renderer-visible-actor-filter-20260928.json).

## 2026-09-28 — Cache fixed-point actor projections in dense worker packets

After stripe masks were added, every renderer process repeated fixed-point
depth/lateral transforms, scale calculation, and rotated-frame selection for
the actors visible to its stripe. NumericV5 now transports those five
PowerShell-prepared fields in typed arrays with `uint32` masks when a snapshot
has at least 200 actors. Sparse scenes remain NumericV4, preserving the
mask-only packet. This changes packet storage and reuses the host visibility
pass; gameplay, sprite rasterization, and output encoding remain PowerShell.

The 21-check snapshot suite passes. All 36 Ultimate Doom maps pass a fresh
35-idle-tic/two-view serial smoke. HMP E1M3's 309-actor snapshot selects V5 and
matches serial output across 16 processes, five angles, and all three display
styles (zero differing pixels across 320,000 pixels per style). The E3M6
dense-scene worker checks also pass in all three styles. The E1M1 sparse scene
selects V4 and matches its Classic worker output.

Two order-reversed E3M6 profiles at the profiler's Hard setting reduce summed
sequential worker-equivalent CPU work by 13.09% and 6.65%, with identical
frame hashes. Two order-reversed HMP E1M3 pairs disagree in direction; their
average favors NumericV4 by 4.28%, so no Episode 1 speed improvement is
claimed. These profiles sum per-stripe median decode/render work plus one
snapshot-preparation median. They are not concurrent latency, FPS, live
Terminal output, or evidence for the 35-tic/60-display gate. The 200-actor
cutoff is a simple sparse/dense guard, not a measured optimal threshold.

The [portable receipt](../results/renderer-projection-cache-20260928.json)
indexes the current-source tests, profile fingerprints, raw ignored reports,
and limits. The phase-profile harness now maps its user-facing skill selector
1–5 to `GameSkill` enum 0–4, consistent with campaign and worker tests. The
older typed-cache E3M6 stress receipts were recorded before that correction and
use internal `Hard` enum value 3; the new Episode 1 comparison uses HMP.

On this source, all 69 Episode 1 transition fixtures and 97 boss progression
fixtures pass. A five-second, headless, sound-enabled E1M3 launch with the
prepared episode catalog starts the simulation, 16 render workers, and audio;
it advances 174 tics and 155 headless updates. The mixer selects D_E1M3, emits
219,240 frames, closes without an error, and reports one rebuffer observation
while real-time mode is disabled. This is bounded startup/integration evidence,
not audible-quality, continuous-playback, or displayed-rate evidence.

## 2026-09-28 — Reject skipping hidden actor field decoding

Tried skipping worker snapshot assignments for an actor's position, angle,
sprite, frame, and light when its mask excludes that renderer stripe. The first
16-worker run found that the Spectre ordering path reads actor flags before it
switches to the filtered actor list. Retaining flags for every actor fixed the
test interaction. The corrected candidate passed the 21-check snapshot suite,
five-view E1M3 pixel equality in Classic, Matrix/Katakana, and
AnsiArt/Katakana (320,000 pixels per style), plus a Classic 16-worker fuzz
partition check (320,000 pixels).

Fixed-state E1M3 timing did not show a repeatable combined decode/render gain.
One prior/candidate profile pair was 129.42/129.85 ms; candidate decoding was
slower (11.77/14.63 ms). The other pair was dominated by a 196.25 ms earlier
render-sum sample, inconsistent with the other three near 115–119 ms runs.
All frame hashes matched, but evidence is too noisy to keep the extra decoder
branch. The experimental source was reverted; the current branch source is
unchanged. Raw reports and hashes are recorded in
[`performance.md`](performance.md).

## 2026-09-28 — Screen current E1M1 worker and ANSI-encoder settings

Ran four 60-second HMP E1M1 no-input sessions from the same source tree with
the Steam Ultimate Doom IWAD and prepared Episode 1 catalog, on PowerShell
7.6.5 / Intel Core Ultra 7 265K (20 logical processors). Real-time audio was
enabled. The source tree exactly matches the `c311868` human-playthrough
candidate; the documentation checkout is `e44f44f`.

Pairs encoding completed 35.483, 48.482, and 48.462 headless host render
updates/sec with 8, 16, and 20 workers. All sessions advanced approximately
34.98 simulation tics/sec. Sixteen and twenty workers were effectively tied;
twenty used 0.84 GiB more in the single end-run worker/simulation working-set
sample. Eight used about 1.51 GiB less than sixteen but completed about 27%
fewer updates. Keep the 16-worker default for this E1M1 workload.

At sixteen workers, ColorState completed 48.227 updates/sec versus 48.482 for
Pairs. Its slowest-worker median encode stage was 2.63 ms versus 3.07 ms, but
render and decode medians were slightly higher and whole-host updates did not
improve. Keep Pairs as the default. The measurement order was 16-Pairs,
8-Pairs, 20-Pairs, 16-ColorState, one session per setting; no randomized or
repeated timing claim is made.

All four sessions selected `D_E1M1`, reported no host/audio error, no software
queue-starvation observation or rebuffer, zero unconsumed packets, and clean
device closure. The final 3,780–5,040 unreturned frames match each report's
canceled-queue upper bound at shutdown; they do not establish an audible gap.
Headless mode skips Terminal writes, and these update rates are not display
presentations or campaign-route evidence. See the [measurement](performance.md#current-source-e1m1-worker-and-encoder-comparison)
and [portable receipt](../results/current-source-e1m1-worker-comparison-20260928.json).

## 2026-09-29 — Cache sector plane data in the PowerShell renderer

Profile results showed floor/ceiling geometry remained a large raster phase.
The renderer now resolves flat pixel arrays once and stores each sector's
fixed-point floor/ceiling height, current floor/ceiling flat index, and light
level in typed arrays. `Set-GameRenderSnapshot` refreshes those arrays on each
new snapshot, so moving sectors and changing light/flat state remain live.
Renderer worker and runspace setup use the same prepared cache.

The change is committed as `e8fd50012c343a3e858001a086e2de7b5efac786`.
Three baseline and three candidate runs, each with five warmups and 40 measured
frames across 16 sequential render stripes, preserve the exact same full-frame
hash. Median geometry time per stripe falls 10.62% (6.8955 to 6.1631 ms), and
total measured renderer work falls 9.80% (8.2215 to 7.4157 ms). The measured
candidate passes the 36-map load/idle/render smoke, 16-worker equality for
five views in each of the three styles, 20 masked-wall checks, and a focused
moving-sector refresh sweep. A single 60-second headless, sound-enabled run
observes 51.18 completed updates/sec versus 48.48 in one earlier run; the
unpaired comparison cannot establish causality. Snapshot decoding includes
cache refresh and its measured median rose, offsetting some raster gain.
Neither headless rate demonstrates Terminal writes, monitor presentation, or
the target frame rate. The human Episode 1 route remains pending.

The [performance record](performance.md#cache-sector-plane-data-for-rasterization--september-29-2026)
and [portable receipt](../results/performance-sector-render-cache-20260929.json)
retain the workload, hashes, and limitations. The [r7 human-playthrough
candidate](../results/episode1-current-human-candidate-20260929-r7.json) pins
this source while carrying forward earlier progression and session fixtures.

## 2026-09-29 — Reject direct plane-ID lookup tables

A follow-up tried to remove plane-ID decoding and the floor/ceiling branch
inside rasterization by precomputing height, flat-byte, and light arrays keyed
directly by plane ID. Five baseline and five candidate E3M6 map-start trials
preserve the same full-frame hash. The aggregate median geometry and total
stripe times improve by 2.77% and 2.44%, but total p95 is unchanged and the two
counter-ordered pairs disagree on the direction of the median change. Reject
the extra arrays; no prototype code remains in the working tree.

The [rejection record](performance.md#rejected-direct-plane-id-lookup--september-29-2026)
and [receipt](../results/rejected-direct-plane-lookup-20260929.json) retain all
ten timing reports, source fingerprints, image hash, and limits. A baseline raw
file-hash change was caused by the Windows checkout's CRLF conversion; Git
reported no source-content difference. The current candidate and pinned commit
remain unchanged.

## 2026-09-29 — Recheck the pinned renderer from a Windows checkout

After rejecting the extra plane-ID tables, the committed renderer was restored
from the existing implementation commit and rechecked under the Windows Git
checkout. The 36-map skill-3 load/35-tic/two-render smoke passes; Classic,
Matrix/Katakana, and AnsiArt/Katakana each match serial output over five E1M1
views and 320,000 pixels using 16 worker strips. Twenty masked-wall checks
pass. Tracked `src/` and `scripts/` compare cleanly to the pinned commit.

With `core.autocrlf=true`, the current Windows working-copy hash for
`FastRenderer.ps1` is `05E1A848F6F92B6913970F7440258813760BE850C308CBBF495F79774F69F54F`;
the earlier precommit measurement workspace recorded
`16872550743A07D7AD071FB66B04AF2483F518477FBECA506A0DEE815735530C`. The Git
blob SHA-256 is `D9CE1FBD6DAA19B8D8BB2612203D729925406CE8BB02E99BB0A40D2CD72C36BF`.
Git reports no content diff; these raw hashes differ because of checkout
newline conversion. See the [supplementary validation receipt](../results/episode1-r7-windows-checkout-validation-20260929.json).
## 2026-09-29 — Check output-clock audio with full E3M6 renderer load

A current-source HMP E3M6 host ran for 30 wall-clock seconds with 16 renderer
workers, the integrated Windows audio device, -RealtimeAudio, and all 30
qualified music reports in the local Ultimate Doom catalog. The output-clock
path selected D_E3M6, generated 104 fill blocks beyond 720 simulation
packets, and reported no rebuffer resumes, queue-starvation observations,
unconsumed packets, worker errors, or cleanup errors. The device closed
cleanly. It submitted 1,038,240 frames; 1,033,200 completed before shutdown,
leaving a 5,040-frame canceled-tail upper bound. Three clipped samples were
counted.

A same-map generation reload occurred around tic 420–421; the trigger is not established. Performance: the host advanced 719 tics in 23.244 active seconds
(30.932 tics/sec); the wall interval was 30.015 seconds and included a
6.769-second map-reload pause. It completed 35.106 render updates per active
second, or 27.186 per wall second. These are headless counts, not Terminal
writes or displayed frames. This was one deterministic scripted, single-map stress sample using cyclic movement, turning, fire, and use; it does not prove
audible continuity, acoustic quality, a completed map, or full-campaign audio.

The run used committed source dd3309e8c4cd9fb3d9c39edc85a44348e97c4449.
The [portable receipt](../results/e3m6-realtime-audio-loaded-20260928.json)
pins source and input hashes; the raw report remains in ignored local/.
See the [audio findings](audio.md#e3m6-music-under-current-renderer-load-2026-09-28),
[performance results](performance.md#output-clock-audio-under-e3m6-renderer-load--september-28-2026),
and [campaign matrix](campaign-matrix.md).

## 2026-09-29 — Reduce fixed-point visibility allocations

At implementation commit `203ca553c3cf947b1099d73b1722711ae1b405c7`,
`VisibilityCheck` returns raw integer intercept fractions internally and
computes sight-bound slopes without allocating intermediate `Fixed` wrappers.
The slope wrappers are now private to each checker and are updated in place.
Public `InterceptVector` still returns `Fixed`. The integer division preserves
the existing `Fixed.op_Division` saturation, signed wrapping, truncation, and
failure semantics.

The focused parity suite passes two direct intercept checks, 50,000
deterministic raw intercept comparisons, 121 fixed-point division boundary
pairs, and 50,000 random division comparisons. The production CheckSight
initialization passes 200 boundary and 50,000 random sight-bound comparisons.
The 36-map skill-3 load/idle/render smoke, 69 campaign transition checks, and
97 boss progression checks pass. Existing current-source route drivers pass
E1M1 (1,560 commands), E1M2 (3,011), and E1M4 (4,726). The E1M3 waypoint
driver stops at waypoint 28 after 2,302 commands; it exposed no crash or
reproducible engine defect, and its route was not tuned.

Performance uses the same 420-command HMP E3M6 input and two saved state
checkpoints, run twice per variant in baseline-candidate-candidate-baseline
order. In uninstrumented runs, the mean of each variant's two simulation
medians moves from 15.2169 ms on source `e8fd500` to 14.6270 ms on the
candidate, a 3.88% reduction; mean p95 moves from 39.3711 to 39.7350 ms. With
diagnostic instrumentation, the sight-check median improves 8.24%; this
inclusive timer adds overhead and is not the headline result. The measured
benefit is modest and narrow. It does not qualify 35 Hz or displayed frame
rate. All eight profiled/unprofiled runs match the same replay hash and both
checkpoints; the [receipt](../results/visibility-fixed-point-allocation-20260929.json)
pins raw-report hashes and the harness. Local raw data remain ignored in
`local/`.

The archived 7,118-command E1M3 fixed-input replay was also rerun against both
the pre-change source and the candidate. Its recorded source fingerprint no
longer matches; both builds diverge at the same 23 of 24 checkpoints beginning
at tic 350, with identical expected/actual hashes at every checkpoint. The
reason for that source-era mismatch is not established. The old report cannot
be used as current-source E1M3 completion evidence. The separate E1M3 waypoint
driver also stalls without a reproduced game defect; no route tuning was
started. The candidate still passes the other three existing normal-route
regressions, and Jason's complete human Episode 1 run remains the next route
evidence.

## 2026-09-29 — Reduce qualified music-catalog startup work

The first current-source r8 audio run exposed a large catalog-open stage: the
E1 catalog has eleven looping tracks, and startup verifies all playback-period
payload hashes before declaring the audio worker ready. A first size estimate
incorrectly included the redundant third proof period. The reader skips that
period; the correct total for the two playback periods is 5,320,062,720 bytes
(4.95469 GiB), not 7.43 GiB. The qualification and integrity checks remain
eager.

Commit `a26a0b439d0fee2e8ea0f1f1a3c785595bec1384` opens independent readers in
up to four PowerShell runspaces. The focused playback suite passes 21 checks,
including rejection of one invalid parallel catalog member and exclusive-open
probes proving that other readers release their handles after that failure.
On a warm OS file cache, baseline-candidate-candidate-baseline reader-open
trials measured medians of 4.665 and 2.050 seconds. All eleven readers opened
in every trial and the report-hash sets matched. This is a 56.06% reduction in
the reader-open stage, not a cold-start or whole-game claim; the portable
[performance receipt](../results/music-catalog-open-parallel-20260929.json)
and [21-check report](../results/music-playback-parallel-tests-20260929.json)
preserve the measurements.

A separate five-second headless E1M1 host run with the complete catalog under
PowerShell 7.6.5 selected D_E1M1, submitted and completed 220,500 audio frames,
and closed the device without a worker error. One queue-empty observation came
after the final packet; there was no rebuffer resume. Its 46.81-second total
process duration is a single unpaired startup/playback/shutdown sample. This
does not measure Terminal presentation, audible quality, full-campaign audio
continuity, or the 35/60 pacing goal; the complete human Episode 1 run remains
pending. See the [host receipt](../results/episode1-r9-audio-smoke-20260929.json).

## 2026-09-29 — Distinguish Preview.3 from the R9 development candidate

The public `v0.1.0-preview.3` tag remains pinned at `34e3d175`. That tagged
commit changes release-facing documentation and version text; it contains no
`src/` changes relative to parent `e9bbcee`. The later development history is
on `codex/feasibility-study`; the R9 game-source pin is
`a26a0b439d0fee2e8ea0f1f1a3c785595bec1384`. README, changelog, and the article
draft now name Preview.3 as the latest tagged package and describe R9 as a
separate, untagged candidate. This corrects ambiguity between a clean checkout
of the release tag and the newer branch; it does not change or rebuild the
Preview.3 release asset.

## 2026-09-29 — Recheck R9 startup on PowerShell 7.6.6

The installed PowerShell 7.6.6 executable now passes the current R9 music
playback suite: 21/21 focused reader, boundary, command, and cleanup checks.
The test source and qualified playback files match the R9 pin. This closes the
runtime-version gap for the focused suite after Jason's earlier startup error;
the report and executable are identified in the
[7.6.6 playback receipt](../results/music-playback-runtime-7.6.6-20260929.json).

A separate five-second sound-enabled, headless E1M1 run under the same runtime
exits by duration after 174 tics and 176 headless render updates. It selects
D_E1M1, submits and returns all 219,240 audio frames, and closes the device
without simulation, audio, or cleanup error. One queue-starvation poll appears
after packet 173 with no rebuffer resume. This is queue polling rather than
hardware underrun telemetry. It is not evidence of audible quality, sustained
continuity, visible frame rate, or 35 Hz / 60 displayed-update qualification.
The [portable host receipt](../results/episode1-r9-audio-smoke-7.6.6-20260929.json)
pins the raw local report hash; the IWAD and music catalog remain local.

## 2026-09-29 — Recheck the moving ceiling on current source

The old fixed-state moving-ceiling comparison used renderer source commit
`532f2e3`. I reran the same E1M1 input at tic 315 with sector 26 held at
ceiling heights 0, 6, 34, and 68 on the current R9 source under PowerShell
7.6.6. Candidate/reference scene-index differences remain 10, 7, 410, and
4,166, with exact HUDs at every height and unchanged mismatch bounds versus
the prior receipt. The rerun shows no new regression attributable to the
intervening renderer cache and worker changes. It remains a static comparison
against the adapted PowerShell renderer, not the original Doom executable or
the exact camera in Jason's screenshot. No renderer code change is justified
by this same-view check. See the
[source-pinned receipt](../results/moving-sector-e1m1-height-sweep-r9-20260929.json);
raw report and diagnostic images stay in ignored `local/`.

## 2026-09-29 — Exercise the chainsaw crash through the player command path

The saved R2 human-session report records the failure Jason saw after pressing
Ctrl with the E1M2 chainsaw: PowerShell attempted an ordered comparison on a
custom `Angle` instance (reported as 16.8992 degrees), which does not implement
`IComparable`. The stack enters `WeaponBehavior.Saw` through
`ExecutePlayerAction`, `SetPlayerSprite`, `MovePlayerSprites`, and `PlayerThink`.
The angle-turn comparisons were fixed in `d84861f` by comparing the signed
`Angle.Data` values in the affected branches.

I strengthened `Test-SawAttack.ps1` so it equips the fixture player, sets the
Chainsaw ready state, supplies the Attack bit through `DoomGame.Update`, and
lets the actual weapon-state/action chain run against a living E1M2 imp. On
PowerShell 7.6.5 it completes the hit after four simulation tics, lowers the
imp from 60 to 56 HP, and raises no comparison exception. The Doom II homing
angle regression also passes. This verifies the formerly crashing action path
on current source; its fixed player position and short duration do not replay
the human route or prove the whole E1M2 session. The refreshed
[focused receipt](../results/saw-attack.json) records both checks.

## 2026-09-29 — Reject changed-cell ANSI output

A 16-worker Classic E1M1 live comparison on the 1,560-command replay reduced
output volume by 37.8%, but updates fell from 38.43 to 26.01/sec, simulation
from 34.96 to 28.49 tics/sec, and measured display transitions from 24.95 to
17.76/sec. Worker encode median/p95 also worsened. The 17-check codec suite
and short worker smoke passed; they did not predict the live-output cost. I
removed the optional patch encoder and retained full-frame output. The paired
capture is a single workload and one wrapper timeout occurred after the game
reached `ReplayEnd`; details and hashes are in the
[portable receipt](../results/rejected-ansi-incremental-20260929.json).

## 2026-09-29 — Explain music qualification startup failures

The first PowerShell 7.6.6 Episode 1 launch failed before the first tic because
the music reader rejected its qualification report. The old exception named
only the broad “no current successful qualification” condition, leaving the
specific report/runtime cause unclear. I updated the reader to report the
track, report path, failed qualification checks, and requalification/catalog
repair step; changed synthesis-source reports now identify the stale module.
The validation gates still reject those reports.

The focused synthetic reader suite passes 40 checks, including combined
rejection reasons and the recommended recovery. The current real D_E1M1 report
opens under PowerShell 7.6.6 and releases both payload locks. These checks do
not claim playback quality or full-campaign continuity. Details are in the
[audio investigation](audio.md#music-qualification-error-diagnostics-2026-09-29)
and [test receipt](../results/music-loop-reader-actionable-rejections-20260929.json).

## 2026-09-29 — Check music qualification metadata before game launch

Jason's prior sound-enabled startup stopped at tic 0 when the audio worker found
an unusable music qualification. The audio reader now explains the failure,
and `Start-Doom.ps1` additionally checks the catalog and each report's
qualification, runtime, synthesis-source pins, and track name before opening
Windows Terminal or game workers. `Play.ps1 -Check` reports the same result.
The fast preflight intentionally does not read/hash the potentially large PCM
payloads or compare music lumps with the selected IWAD; the audio worker still
hashes and read-locks payloads, and simulation startup still verifies IWAD
score identity.

The current local eleven-track Episode 1 catalog passes the user-facing
`Play.ps1 -Check` under PowerShell 7.6.5. A direct `Start-Doom.ps1` probe with
an unqualified one-shot report fails before terminal or game-worker launch.
The focused playback suite passes 25 checks: both loop and finite-score
metadata pass, missing PCM remains deferred to and is rejected by the actual
playback open, and stale qualification metadata is rejected early. The
[portable receipt](../results/music-playback-preflight-20260929.json) pins the
reader, catalog, test source, and real local qualification reports; those PCM
files and IWAD remain local. The [complete-playthrough handoff](episode1-playtest.md)
now pins exact build `b79b668`, and the existing R9 gameplay/route evidence
carries forward because no gameplay or rendering code changed. The public
Preview.3 archive is unchanged.

## 2026-09-29 — Correct the article's E3M6 audio chronology

The article's sound section had described the earlier pre-output-clock E3M6
queue-starvation trials as though they were the latest loaded result. It now
distinguishes those failures from the current-source 30-second, 16-worker
output-clock run, which reported zero queue-starvation and rebuffer
observations, consumed 720 simulation packets plus 104 fill blocks, and closed
the device cleanly. The article also preserves the sample's 6.769-second
same-map reload pause, 30.93 active simulation tics/sec, and 5,040-frame
canceled-tail upper bound; this does not establish campaign continuity or
audible quality. The [campaign matrix](campaign-matrix.md) records its active
timing and reiterates that the sample is not map completion. No product source
or qualification status changed. Evidence: the
[source-pinned E3M6 receipt](../results/e3m6-realtime-audio-loaded-20260928.json).

## 2026-09-29 — Recheck the Episode 1 audio startup on PowerShell 7.6.6

The user-reported music-qualification startup failure is now verified through
the fast launcher preflight under both 7.6.5 and 7.6.6, followed by the actual simulation/audio workers on the
same workstation. A five-second, 16-worker, headless E1M1 run opened the full
local Episode 1 catalog under PowerShell 7.6.6, selected D_E1M1, advanced 174
tics, mixed 181 blocks (seven output-clock fill blocks), and reported zero
queue-starvation observations, zero rebuffer events, no worker or cleanup
error, and clean waveOut shutdown. It submitted 228,060 frames and returned
223,020; the remaining 5,040 queued frames are the duration-shutdown
cancellation upper bound. This closes the reproduced startup blocker for the
short integration path only; it does not qualify visible Terminal output,
audible quality, or campaign continuity. The [compact receipt](../results/episode1-current-audio-startup-7.6.6-20260929.json)
pins the [ignored raw report](../local/current-audio-startup-recheck-20260929.json).

## 2026-09-29 — Add experimental indexed-color Classic output

Added the PowerShell `Ansi256` encoder as an optional Classic mode and exposed
it through `Play.ps1`, `Start-Doom.ps1`, the render workers and existing trial
tools. It maps PLAYPAL colors to the nearest xterm indexed RGB value and emits
indexed foreground/background SGR; the original half-block framebuffer and
engine output remain unchanged. The terminal chooses actual indexed colors,
so this mode intentionally gives up exact RGB. `Pairs` remains the default.
Microsoft documents the [indexed SGR sequence](https://learn.microsoft.com/windows/console/console-virtual-terminal-sequences).

The existing ANSI decoder suite passes 24 truecolor/indexed round-trips. A
16-worker Classic render-partition check passes five E1M1 views and compares
320,000 source pixels against serial output. On one identical 320×200 indexed
frame and palette, the production 16-strip encoder emits 666,169 bytes with
Pairs versus 475,310 with Ansi256 (28.65% fewer bytes). This is output volume,
not a timing result. The hashes, trial settings and raw-report fingerprints
are in the [measurement receipt](../results/ansi256-runtime-20260929.json).

The live Windows Terminal Ansi256 run completes 647 writes/43.12 per second
and 524 simulation tics/34.92 per second over 15 seconds. The later single
Pairs run falls to 156 writes/10.38 per second and 169 tics/11.25 per second,
with a much larger p95 frame latency. These unpaired sequential sessions
have no controlled or recorded machine-load conditions, so they do not show
that either encoding caused the difference. Neither qualifies 60 writes/sec
or 35 simulation tics/sec, and Terminal writes do not measure monitor
presentations. Keep the indexed mode experimental; a repeated matched-state
comparison is still needed before making performance claims.

## 2026-09-29 — Re-pin the Episode 1 human-playthrough handoff

The development handoff now targets code commit `d5d1217108bfc3093db2e89a70c57215d481711f`.
R10 adds the optional Classic Ansi256 output mode; gameplay behavior,
FastRenderer's rasterization algorithm, and the default exact-truecolor `Pairs`
path remain unchanged from R9. A fresh PowerShell 7.6.5 load/update/render
smoke passes E1M1–E1M9 at HMP with 16 workers, including the secret map E1M9.
`Play.ps1 -Check` accepts the local eleven-track catalog. A five-second
headless sound/music run selects D_E1M1, advances 174 tics, returns all
219,240 submitted audio frames, and closes the device without worker or
cleanup error. It records one queue-starvation/rebuffer observation after
packet 173 near shutdown; this does not establish continuous playback or
acoustic quality. The smoke, audio report, previous R9 receipt, and source
revision are pinned in the [R10 handoff receipt](../results/episode1-current-human-candidate-20260929-r10.json).

The E1M1–E1M4 route evidence, transition and boss fixtures, and R7/R8 renderer
evidence carry forward because game behavior did not change. They still do not
complete a human map route. E1M3's waypoint driver remains stopped after
stalling without a reproduced defect. The complete HMP route through E1M9,
back to E1M4, and through the finale is still pending; fresh R10 paths in the
[playthrough handoff](episode1-playtest.md) preserve the earlier human attempt.

## 2026-09-29 — Align the project summary with R10

Update the article draft and README to distinguish the unchanged Preview.3
package from the newer R10 development handoff. The article now identifies
the R10 source pin, records the fresh nine-map Episode 1 smoke and five-second
headless audio result with its near-shutdown starvation observation, and
reports the Ansi256 same-frame byte reduction without treating it as a live
speed gain. The human route and 35-tic/60-display goals remain explicitly
unqualified. No game source changed.

## 2026-09-29 — Reduce flat-coordinate wrap work in the renderer

Replace per-pixel signed 32-bit wrap normalization in plane sampling with a
PowerShell-maintained 22-bit texture phase. The 64×64 flat lookup reads only
those low bits, so the sampled image remains exactly the same. Eight
alternating rounds at five headings compare 40 baseline and candidate frames
each on HMP E1M1 and E3M6; all 80 pairs match pixel-for-pixel. Median serial
render time falls 2.52% and 1.57% respectively, with p95 reductions of 7.13%
and 4.23%. These are fixed-state renderer timings, not live-game pacing.

The current candidate also passes the full 36-map smoke, fuzzed 16-worker
output checks in all three visual modes (320,000 pixels per mode), 20 masked-
wall checks, and the occluded-BON1 scene regression. The [portable receipt]
(../results/renderer-flat-phase-wrap-20260929.json) indexes exact report
hashes. No gameplay behavior changed; the Episode 1 human route remains
pending.

## 2026-09-29 — Pin the R11 Episode 1 human-playthrough build

The current handoff is source commit
`cafb337e553939d35b3330843698b85eeb47fa52`. Its source-pinned [R11 receipt]
(../results/episode1-current-human-candidate-20260929-r11.json) records the
36-map load/idle/render smoke, current launcher music preflight, and the
flat-phase renderer comparison. Every one of 80 paired frames matches the
prior renderer. Fixed-state serial medians fall 2.52% on E1M1 and 1.57% on
E3M6; these are isolated renderer calls, not live pacing.

A five-second actual-worker headless audio run selects D_E1M1, advances 174
tics, reports no starvation or rebuffer, and closes cleanly. Of 229,320
submitted audio frames, 224,280 were returned; 5,040 is only the
shutdown-cancellation upper bound. It does not establish audible quality or
full-session continuity. Three-style 16-worker pixel checks, masked-wall
checks, and the occluded-BON1 regression pass. Earlier transition, boss, and
E1M1/E1M2/E1M4 route evidence carries forward because gameplay behavior did
not change. The complete HMP Episode 1 human playthrough remains pending; the
handoff uses fresh `r11` input, report, save, and settings paths.

## 2026-09-29 — Defer flat-plane index-bit extraction and pin R12

R12 changes only PowerShell flat-plane coordinate arithmetic. The sampler
carries Int64 world coordinates between pixels and extracts X bits 16–21 and Y
bits 10–15 when it reads a 64×64 flat texel. Since the repeating-flat period is
2²² and divides the signed 32-bit coordinate period 2³², the selected texture
index remains identical. The implementation is pinned at
`c29b24e8a1c06635f90423672cc74f28836b7095`; the prior source is
`cafb337e553939d35b3330843698b85eeb47fa52`.

Three alternating-order fixed-state renderer samples each compare 40 frames
across five headings, with zero pixel differences in all 120 frame pairs.
E1M1 median renderer time fell 10.68% in one run and 5.70% in its repeat;
E3M6 moved 0.37% slower, effectively unchanged in this sample. A 100,000-case
random Int64 bit-selection check had no mismatches. The full-host A-B-B-A
comparison is inconclusive: its last baseline run fell to 19.52 updates/sec
and 30.12 tics/sec with 247 command-backpressure events, while baseline A and
both candidate runs were near 52–57 updates/sec. No environmental cause was
isolated, so the receipt makes no host-throughput claim.

The current source passes the 36-map smoke and five-view 16-worker output
checks in all three styles. A fresh five-second actual-worker headless E1M1
audio run advanced 174 tics and 198 updates, selected D_E1M1, returned
225,540/230,580 frames, observed no queue starvation or rebuffer, and closed
the device without worker or cleanup error. The remaining 5,040 frames are a
shutdown-cancellation upper bound. `Play.ps1 -Check` accepts the local catalog.
These checks are not Terminal pacing, audible review, or a completed map.
Jason's one complete Episode 1 route remains pending on fresh `r12` output,
save, and settings paths. The [R12 candidate receipt]
(../results/episode1-current-human-candidate-20260929-r12.json) and [focused
renderer receipt](../results/renderer-flat-texel-bit-extraction-20260929.json)
retain portable evidence and hashes.

The user asked why a release note could say only release metadata changed after
a long run of commits. Preview.3's tag `v0.1.0-preview.3` points to `34e3d17`,
whose parent-to-tag diff changes seven release/documentation files (+30/−38)
and no game source. That is the final release-preparation commit, not a summary
of development. At the time of this audit, the R12 source candidate `c29b24e` was 53 commits
after the Preview.3 tag, and the documentation pin `1ab6d16` was 54 commits
after it. At the audit correction commit `ef6e750`, the post-Preview.3 range
contained 55 commits. A fresh diff pinned to that commit reported 125 changed
files, +29,008/−333 lines:

- `src/`: 14 PowerShell source files, +616/−180 (net +436); 15 commits touch
  this tree.
- `scripts/`: 24 runtime, test, measurement, recording and build files,
  +556/−81.
- `results/`: 67 JSON evidence files, +25,645/−15. These account for about
  88% of additions and are measured output, not source code.
- `docs/`: 16 files, +2,145/−48. Root changelog, README and launcher files
  account for the remaining changed paths.

The earlier audit used inconsistent path groupings and stale totals. This
snapshot's counts are pinned to `ef6e750`; later development is recorded below.
The Preview.3 release-preparation commit itself changed only seven
release/documentation files and no `src/`. A metadata-only release commit can
therefore follow substantial source work already present in its tested parent;
that narrow release diff is not a summary of development.

## 2026-09-29 — Reuse static renderer assets on same-map resets

The prior source rebuilt and published every static renderer asset bundle on
same-map restarts, then asked all 16 persistent rendering workers to reload
that unchanged bundle. The simulation now keys static assets by game mode,
version, mission pack, episode, and map, and reuses the bundle when that key is
unchanged. Dynamic sector and actor state still travels in the usual snapshots.
The host checks the new snapshot generation first; different-map transitions
still refresh each worker's assets.

A sequential PresentMon comparison pinned baseline source `ef6e750` and
candidate source `8b48f99`. On the same 1,560-command E1M1 replay, the same-map
reload at tic 1,247 fell from 6.178 to 0.358 seconds (94.2% lower); the
candidate report records `RendererAssetsReused=True`. Active completed updates
fell from 49.70 to 46.22/sec, so this does not support a general throughput
gain. Measured display transitions were 43.66 and 45.89/sec, still below 60,
and simulation ran at 34.97/sec in both runs. The audio-disabled replay ends at
`ReplayEnd`, not at map completion. This one pair is not a pacing qualification;
the remaining 0.358-second handoff is unattributed. Full reports and raw ETW
rows are retained under ignored `local/presentmon-same-map-reset-20260929/`;
the [portable receipt](../results/renderer-same-map-reset-presentmon-20260929.json)
pins the code, workload, and report hashes.

Focused verification passed: PowerShell parsing, `Play.ps1 -Check` with the
Steam IWAD and current 11-track catalog metadata, 12 same-map save/new-game
checks, and E1M1-to-E1M2 worker/session checks for the changed-map reload path.
The complete Episode 1 human playthrough and the broader release gates remain
open.

## 2026-09-29 — Audit commits since the previous public preview

To answer whether the week-plus after Preview.2 was all test-harness work, the
pinned range `v0.1.0-preview.2..ef6e750` contains 169 commits (September 19–29).
Forty-one commits touch `src/`; its 23 PowerShell source files change by
+1,236/−160 lines. Those include renderer/visibility and audio/runtime changes,
not just test support. There are also 37 focused test/experiment tools
(+1,999/−125) and 20 other runtime/measurement scripts (+1,549/−67).

The repository's added-line count is nevertheless dominated by captured
measurements: 537 `results/` files add 783,631 lines, about 98.5% of all added
lines in that range. Documentation adds 7,076 lines across 31 files. The high
commit count reflects many small code, test, result, and documentation updates;
the enormous line count mostly reflects stored experiment output. Preview.3's
release-preparation commit is still only a seven-file docs/release diff because
it packages the already-tested source at its parent. These counts are pinned to
`ef6e750`; the later same-map renderer fix and its receipt are documented in the
following entry.

## 2026-09-29 — Pin the R13 Episode 1 human handoff

The current game-source pin is `8b48f994d19f055d1ce8ca2f06538bf37a92c2f3`.
R13 changes only the launcher and simulation worker behavior for same-map
renderer-asset reuse; game, rasterizer, and audio source files are unchanged.
The 36-map smoke and full rendering checks remain pinned to R12, and the
current-source focused tests cover the affected host/worker paths: 12/12
same-map save/new-game checks, 12/12 changed-episode checks, and four
session-worker output cases with 256,000 exact pixel comparisons and preserved
worker processes.

A fresh current-source player action check still lands the E1M2 chainsaw hit in
four tics (imp health 60 to 56) and passes the Doom II homing-turn check. The
previous human-session error was a real comparison failure, fixed by comparing
`Angle.Data`; the post-fix 26,731-command in-process replay consumed its full
recording and matched 79 saved gameplay/render checkpoints on source
`e13f407`. That is a simulation regression, not a full human Terminal session.

The source-pinned [R13 receipt](../results/episode1-current-human-candidate-20260929-r13.json)
sets fresh `r13` input, session, saves, and settings paths for one complete
HMP Episode 1 run, including the E1M3 secret exit to E1M9, return to E1M4, and
the finale. The current handoff is ready for that single human playthrough;
all broader release gates remain open. The same-map PresentMon result is one
non-audio pair and does not qualify 35-tic simulation, 60 display transitions,
full-session audio, or original-executable parity.

## 2026-09-29 — Audit the Preview.3 commit gap

The `v0.1.0-preview.3` tag points to release-preparation commit `34e3d17`.
That commit changes seven release/documentation files (+30/−38 lines) for the
version, download instructions and release notes; it contains no game-source
change. The tag was cut from the already-tested candidate. Later development
continued on this branch, so its present history is not the contents of that
tag.

From Preview.3 through source commit `cdd5fdd`, the branch contains 59 commits.
Sixteen touch PowerShell product source (`src/`, `Play.ps1` or
`Start-Doom.ps1`), for +636/−185 lines; sixteen touch project scripts, for
+595/−94 lines. Fifty-one commits touch documentation and 42 touch stored
results/evidence; those categories overlap. The 74 changed files under
`results/` account for +35,538/−10 lines, most of the total +39,072/−342
diff. No C# source file changed in this post-release range. Thus the commit
count is neither all test harness nor a measure of player-facing feature size:
it includes product fixes and optimizations, focused tests, experiment tools,
large machine-readable reports, and repeated evidence/documentation updates.

## 2026-09-29 — Pin the R14 audio arbitration handoff

Source commit `cdd5fdd68734dbc663367f44117fd8a49ac17694` changes PowerShell
sound arbitration so a new sound stops any active sound from the same emitter,
even when the categories differ. Sounds from distinct emitters remain mixed;
when the configurable voice pool is full, the oldest voice is replaced. This
implements the Linux Doom 1.10 same-origin stop and oldest-channel rules while
keeping the existing 16-voice setting. Gameplay, rendering and random-state
behavior do not change.

All 27 deterministic mixer checks and 7 production packet-path checks pass.
`Play.ps1 -Check` reports Ready for the installed 36-map Ultimate Doom IWAD in
effects-only mode. An attempted audio render from the old saved input replay
diverges from the current gameplay state at tic 350 after eight checkpoint
comparisons; its audio output is not qualification evidence. The initial
handoff had no current-source device check; the following entry records one.
The source-pinned
[R14 receipt](../results/episode1-current-human-candidate-20260929-r14.json)
updates the complete HMP Episode 1 human handoff path; the secret-map return,
episode finale and full-session audio remain open.

## 2026-09-29 — Verify current-source R14 audio startup

`Play.ps1 -Check` under PowerShell 7.6.5 reports Ready for the installed
36-map Ultimate Doom IWAD and all eleven local Episode 1 music qualification
reports. A five-second, 16-worker, headless E1M1 run with realtime audio then
starts the actual Windows audio device, selects D_E1M1, and exits on duration
without simulation, audio, or cleanup errors. The worker processes 174
simulation packets and ten realtime fill blocks. It submits 231,840 frames and
reports 226,800 completed; 5,040 remaining is the shutdown-cancellation upper
bound. Software polling reports zero queue-starvation observations and zero
rebuffer resumes, and the device closes cleanly.

The run records 174 simulation tics (34.777/sec), 214 completed headless render
updates (42.772/sec), and zero active effect voices. It is music-startup
evidence only: there was no Terminal output, acoustic review, live sound-effect
audition, route completion, or 35-tic/60-displayed-update qualification. The
[portable receipt](../results/episode1-current-audio-startup-r14-20260929.json)
pins the source and catalog hashes; its raw report remains ignored under
`local/`. The [R14 candidate receipt](../results/episode1-current-human-candidate-20260929-r14.json)
now carries this bounded current-source result.

## 2026-09-29 — Exercise sound effects through the R14 audio device

The idle startup did not generate a sound-effect voice, so a second five-second
current-source E1M1 run used the built-in scripted input's Attack bit while
running the real Windows audio worker and D_E1M1 music. It generated 14 audio
events and reached one active-source/voice peak. The worker submitted 230,580
frames and completed 225,540; 5,040 is the shutdown-cancellation upper bound.
There were no clipped samples, worker/cleanup errors, software queue-starvation
observations, or rebuffer resumes, and the device closed cleanly.

This exercises game-generated effect traffic through the live mixer/device
path. It does not retain an isolated SFX waveform, establish which effect
category reached the mix, test same-source cross-category replacement on the
device, or replace an audible review. The
[portable receipt](../results/episode1-current-audio-effects-r14-20260929.json)
pins the source, workload, and ignored raw report hash.

## 2026-09-29 — Recheck current music-catalog startup

The reported `Music loop has no current successful qualification` failure did
not reproduce with the current catalog under the available PowerShell 7.6.5
runtime. `Play.ps1 -Check` reports Ready for the Steam Ultimate Doom IWAD's 36
maps and eleven catalog qualifications. A three-second headless realtime-
audio E1M1 session selected D_E1M1, advanced 104 tics and mixed 139,860 frames.
It closed the real audio device with no simulation/audio/cleanup error,
software queue-starvation observation, rebuffer resume, or clipped sample.
It submitted 139,860 frames and returned 134,820; the 5,040-frame remainder is
the shutdown-cancellation upper bound. This directly verifies the current
catalog and source on PowerShell 7.6.5, not sound quality or sustained campaign
playback. The [7.6.5 receipt](../results/current-music-startup-recheck-20260929.json)
records the WAD/catalog/raw-report hashes; the raw session stays under ignored
`local/`.

The same current source, IWAD, and catalog then passed the preflight and actual
audio startup under the official portable PowerShell 7.6.6 x64 release. It
selected D_E1M1, advanced 104 tics, generated 120 headless updates and closed
the device without audio/cleanup error, clipped samples, queue-starvation
observations, or rebuffer resumes. It submitted 139,860 frames and returned
134,820; the remainder is the 5,040-frame shutdown-cancellation upper bound.
The 7.6.6 archive was hash-checked against its upstream release digest. The
I incorrectly recorded the original failed report as unavailable at this
point; the later correction below recovers it and establishes the runtime-
version cause. The [7.6.6 receipt](../results/current-music-startup-recheck-7.6.6-20260929.json)
pins its archive, WAD, catalog, source, and raw-report hashes.

## 2026-09-29 — Requalify the Episode 1 handoff under PowerShell 7.6.6

The R14 game-source commit `cdd5fdd` has no later engine-code changes. To test
the same runtime that produced the user-reported startup failure and chainsaw
crash, the official PowerShell 7.6.6 x64 portable archive was extracted under
ignored `local/` and verified against the upstream release SHA-256. The current
WAD and 11-track catalog pass `Play.ps1 -Check`; a three-second actual-device
E1M1 run selects D_E1M1 and closes without simulation/audio/cleanup error,
queue-starvation observation, or rebuffer. The prior qualification failure
does not reproduce under current source; the correction below establishes its
historical runtime-version cause.

Under this runtime, the E1M2 chainsaw action hits a real IWAD imp after four
tics without the former angle-comparison exception. All 69 campaign transition
fixtures, 97 boss-progression checks, and 10 menu-input checks pass. The secret
branch fixtures load real E1M9 and E1M4 worlds and preserve secret history;
finale state is checked. These are focused state/transition tests, not map
completion. The 36-map load/render smoke and E1M1/E1M2/E1M4 normal-input routes
carry forward from their pinned source receipts. The refreshed
[R15 candidate](../results/episode1-current-human-candidate-20260929-r15.json)
uses the same game-source commit and fresh R15 output paths. Jason's one
complete Episode 1 HMP playthrough remains pending; no automated route or
fixture is substituted for it.

## 2026-09-29 — Reject plane-boundary scan removal

The current renderer profile shows geometry as the largest E3M6 per-worker
phase, so I tested removing the global plane-boundary scan from each row. Two
short order-reversed baseline/candidate profiles preserve the exact full-frame
hash and all sixteen worker hashes. The candidate lowers pooled total medians
by 2.95%, but raises p95 by 1.58%; the slowest worker's median is 0.35% worse
and its p95 is 1.11% worse. The geometry median changes by only 0.54%. The
small result does not establish a useful pacing improvement, so the renderer
was restored without a code change. See the [performance record](performance.md#reject-per-row-plane-boundary-scans--september-29-2026)
and [receipt](../results/rejected-plane-boundary-scan-20260929.json).

## 2026-09-29 — Correct the Episode 1 music-startup diagnosis

An earlier R15 audit incorrectly said the failed startup report was unavailable
and left its cause unknown. The report was present at
`local/episode1-human-session.json`; I had failed to inspect it. It records
PowerShell 7.6.6, zero simulation tics, and the generic music-qualification
exception. The documented 11-track catalog on disk maps to reports qualified
under 7.6.5. At the source snapshot in effect before `398022a`,
`Open-DoomMusicLoopReader` compared the full runtime version string, so the
7.6.5 D_E1M1 report was rejected by 7.6.6 even though its qualification flags,
state recurrence, exact reference comparison, and source-stability check all
passed. Commit `398022a` changed the gate to major/minor compatibility. A later
LF/CRLF hash-normalization change is separate and did not cause this failure.

The failed session report does not embed the catalog path/hash; Jason said he
ran the documented command, which uses `local/music-prepared-episode1.json`.
The [root-cause receipt](../results/music-startup-failure-rootcause-20260927.json)
pins that retained report, the currently available documented catalog and
qualification hashes, and both source commits while preserving that limit.
Current 7.6.5/7.6.6 preflight and actual-device startup checks pass. This
correction supersedes the earlier statements in the R15 entries that the cause
was unknown and the report unavailable.

## 2026-09-29 — Drain queued audio on normal shutdown

Normal unpaused, error-free exit now waits up to 250 ms for already-submitted
waveOut buffers to complete before resetting and closing the device. The
worker reports pending frames, completion wait, timeout and shutdown-only
cancellation separately from intentional volume/world-epoch resets. Paused or
failed workers still cancel immediately; this avoids replaying stale audio
after a pause and preserves prompt cleanup on errors.

The actual-device 7.6.6 [nine-check runspace test](../results/audio-runspace-shutdown-drain-20260929.json)
queued 3,780 muted frames at shutdown and observed all of them return complete
after 57.178 ms; the shutdown-specific canceled count is zero. The full-run
counter includes 5,040 canceled frames from earlier epoch resets, and the test
observed one packet-gap queue poll. The eight-check
[D_E1M1 output-clock continuity test](../results/audio-realtime-continuity-shutdown-drain-20260929.json)
also passes; its explicit drain leaves no queued frames for shutdown. The
`Play.ps1 -Check` preflight accepts the installed 36-map IWAD and all eleven
music qualifications on portable PowerShell 7.6.6. The updated worker/device/test
files parse cleanly.

The first test invocation failed because its new wait call had no local helper;
the next failed only because the prior final packet assertion still expected
sequence 105 after test packets 106–107 were added. Both raw
[harness reports](audio.md#bounded-device-tail-completion-on-normal-exit--september-29-2026)
are preserved and explicitly classified. The second report independently
confirms the drain worked before the stale assertion fired. No gameplay,
rendering, or mixing algorithm changed in this step.

## 2026-09-29 — Refresh the post-Preview.3 work audit at R16

The release-preparation note describes only the difference between the tested
candidate and the Preview.3 release commit. It is accurate that this final
commit changes release/documentation text and contains no game-source change;
it does not describe the work accumulated since the previous public preview.
The annotated Preview.3 tag is dated September 28 in this checkout. Its tagged
commit `34e3d17` changes seven release/documentation files (+30/−38) and no
source. The development branch now has 68 commits after that tag.

Nineteen of those commits touch PowerShell game source or runtime code; sixteen
also touch test or measurement scripts, with overlap between the categories.
Across the range, `src/` changes 16 files (+648/−181), while `scripts/` changes
29 mixed runtime, test, build, and measurement files (+943/−98). Those changes
include actor visibility/projection and sector-render caching, packed render
geometry, fixed-point visibility allocation reduction, output-clock audio,
same-emitter sound arbitration, music startup preflight, optional ANSI-256
encoding, and the latest bounded audio shutdown drain. They are real engine and
runtime changes, but do not amount to the complete Episode 1 human playthrough
or finished Ultimate Doom release qualification.

The same range changes 90 `results/` files by +37,716/−11 lines and 16
documentation files by +2,712/−51 lines. Results account for about 90% of all
added lines; most are machine-readable measurements and experiment output.
The high commit count is a mixture of product code, test/measurement tooling,
captured results, and documentation updates—not 68 test-harness commits and not
68 player-facing features. The earlier count pinned through `cdd5fdd` remains a
historical snapshot; this audit is pinned to R16 source `3e0b630`.

The R16 handoff receipt pins the current source, PowerShell 7.6.6, the installed
Ultimate Doom IWAD and music catalog. Current-source preflight and a four-second
actual-device E1M1 audio run pass; all 36 maps pass the bounded load/idle/two-
render smoke. Focused audio shutdown and continuity checks pass. Those results do
not establish human map completion, audible quality, full-campaign continuity,
or 60 displayed updates per second. Jason's one complete HMP Episode 1
playthrough remains pending from E1M1 through the E1 finale, including E1M3's
secret route through E1M9 and return to E1M4. See the [R16 receipt]
(../results/episode1-current-human-candidate-20260929-r16.json) and [playtest
handoff](episode1-playtest.md).

## 2026-09-29 — Compare the nine-day Preview.2-to-Preview.3 interval

The preceding post-Preview.3 audit starts at the wrong point for a question
about the week before the release. Preview.2 is tagged September 19, Preview.3
September 28, and current R16 source is September 29. The complete
Preview.2-to-R16 range contains 182 commits. Forty-three touch `src/`, and 44
touch focused test or measurement scripts; these groups overlap. The range
changes 24 PowerShell source files (+1,268/−161), 61 mixed scripts
(+3,935/−209), 560 result files (+795,706/−3), and 31 documentation files
(+7,642/−95). Captured results account for about 98% of added lines.

So the release-preparation commit being documentation-only is consistent with
substantial work during the preceding nine days: it was a version/download/
release-notes commit on top of the already-tested candidate. The interval was
not all test harness; dozens of commits modified the PowerShell engine source,
while many others added focused checks, measurements, recorded output and
project documentation. The raw line total mostly measures retained experiment
data, not engine size or player-facing feature count. Preview.3 itself remains
the public package; R16 is the current development handoff and still awaits the
single complete human HMP Episode 1 playthrough.

### Current branch count after the R16 source pin

The 182-commit Preview.2-to-R16 count above is pinned to game source
`3e0b630`. At the audit snapshot, HEAD was `2c772fc`, four
documentation/evidence commits later: 186 commits from Preview.2 and 72 after
the Preview.3 tag. Those four commits did not change `src/` or `scripts/`; the
source diff remained 24 files (+1,268/−161) across 43 source-touching commits.
The Preview.3-to-HEAD range at that snapshot changed 94 result files
(+40,102/−11) and 19 documentation, README, or changelog files (+2,828/−58).
Thus the increase since the R16 source pin was documentation and recorded
evidence, not additional engine code.

## 2026-09-29 — Recheck the full campaign music catalog on R16

Under official portable PowerShell 7.6.6, `Play.ps1 -Check` reports `Ready`
for the installed Ultimate Doom IWAD and the local 30-entry music catalog. A
six-second R16 host run with realtime waveOut and 16 render workers selects
D_E1M1, returns all 265,860 submitted audio frames, completes the bounded
shutdown drain, and closes without simulation/audio/cleanup errors,
queue-starvation observations, or rebuffering. It reaches 34.81 simulation
tics/sec and 23.82 headless render updates/sec. These are not displayed frames;
the short run exercises only the D_E1M1 playback path, not all tracks or
campaign-length acoustics/continuity. See the [audio preparation record]
(music-preparation.md#current-source-full-catalog-runtime-check--september-29-2026)
and [portable receipt](../results/music-campaign-catalog-host-r16-20260929.json).

## 2026-09-29 — Reject worker-range snapshot masks

On the R16 source, a PowerShell candidate precomputed the 320-column
pixel-to-worker map and every contiguous worker-index range mask, replacing
the per-actor loop over renderer workers. Exact framebuffer output matched in
all four fixed E3M6 profiles, with 280 actors and 16 workers. In a warmup-
excluded baseline/candidate/candidate/baseline comparison under PowerShell
7.6.6, the two-pair average snapshot-preparation median improved 5.8%, but the
average p95 regressed 6.8%; the second candidate run was slower than its paired
baseline in both median and p95. Since this serial profile does not establish
concurrent worker or game-host pacing, the change was rejected and reverted.
The restored R16 source passes exact five-view, 16-worker E3M6 output checks
for Classic, Matrix/Katakana, and AnsiArt/Katakana. See the [measurement and
parity receipt](../results/rejected-worker-range-mask-20260929.json). The
separate source-count audit above is a snapshot pinned to commit `2c772fc`.

## 2026-09-29 — Correct the R16 source-delta record

The R16 candidate receipt carried forward a stale R15 source-change field. The
receipt now gives the exact delta under `ChangesSinceR15`: the audio worker
tracks completed Windows buffers and drains the normal unpaused shutdown tail.
It lists the three changed runtime files and distinguishes that
device-lifecycle change from unchanged gameplay, rendering, and mixing
algorithms. Its chainsaw and campaign-transition fixtures remain explicitly
pinned to the preceding `cdd5fdd` gameplay source; they are inherited evidence,
not tests newly run at `3e0b630`. The current 7.6.6 launcher preflight was
rechecked against the installed 36-map IWAD and the documented 11-track
Episode 1 catalog and reports `Ready`. The article draft now describes R16,
the measured shutdown behavior, the interrupted human attempt, and the
remaining campaign/fidelity/audio/pacing limits.

## 2026-09-29 — Validate a clean R16 playtest package

Built a local-only `0.1.0-dev.20260929` source archive from clean commit
`bcfb85e56cbe8ac4a7e14e0658bcae8b95a95a65`. Its `src/` and `scripts/` have
no path changes from R16 game-source commit `3e0b6308bac9dc152f9ae78fb8f23f70623b36e2`.
The package manifest covers 543 files; all packaged file hashes and the ZIP
checksum verify. The archive excludes `docs/gebbdoom.pdf`, IWADs, soundfonts,
local reports, and recordings. Its ZIP remains under ignored `local/` and is
not tagged or published.

The extracted launcher passes `Play.ps1 -Check` under the installed PowerShell
7.6.6, recognizing 36 maps and 11 prepared Episode 1 music tracks. A four-
second headless E1M1 host run from the extracted package selects D_E1M1 and
returns all 175,140 submitted audio frames before clean device close. One
queue-empty/rebuffer observation occurs after the final packet; it is retained
as a limitation rather than called continuous-playback success. The run
advances 139 simulation tics and 135 headless render updates, not display
frames, and exercises no active sound effect. It adds no campaign completion,
keyboard-play, acoustic, full-session audio, or pacing evidence. No recording
was made. See the [portable package receipt](../results/r16-playtest-package-validation-20260929.json)
and ignored raw host report `local/r16-package-audio-smoke-20260929.json`.

## 2026-09-29 — Reuse stationary map discovery

The renderer now skips repeated BSP discovery only when the camera/view key and
the relevant visible world state still match. It watches projected segments'
sectors and sides plus map-reset changes, so off-view sector animation does not
invalidate a stationary view. Under PowerShell 7.6.6, all 144 mapping-bitset
comparisons across 36 Ultimate Doom map starts match the uncached path, and
the eight-check simulation-worker automap fixture passes. A five-second idle
E1M1 host run records one traversal and 174 cache hits at 34.79 simulation
tics/sec. Its 81 headless render completions are not displayed frames. The
static E4M9 discovery-method benchmark is 0.082 ms cached versus 16.757 ms
uncached median; it is not a gameplay-FPS claim. See
[`automap-discovery-performance.md`](automap-discovery-performance.md#stationary-view-reuse-2026-09-29)
and the [qualification receipt](../results/stationary-discovery-cache-20260929.json).

The old 7,118-command E1M3 discovery replay was also run once with stationary
reuse disabled as a control. It diverges from its stored gameplay checkpoints
at tic 700 and ends without the old expected route transition. The checkpoint
source is stale for the current game build, so this is not evidence of a
stationary-cache defect or a newly reproducible gameplay bug. Per the
playtesting plan, the route was not tuned or retried; the short result is
retained in `results/e1m3-stale-discovery-replay-20260929.json` and the ignored
raw report remains under `local/`.

## 2026-09-29 — Pin the R17 Episode 1 playtest package

The local R17 archive is built from clean commit
`260cbf00cc35df45c3ffc6c5d014f41247e88e60`; its game implementation matches
the tested source at `00405deebef6b4e8477c9c9316987b82fbc9064d`. The 543
manifest-listed payload files all match the extracted package, which passes
the PowerShell 7.6.6 IWAD/music preflight for 36 maps and eleven prepared
tracks. The archive excludes the research PDF, game assets, and local reports.
Its SHA-256 is
`5B71FEFFDFC9C323141CBB02446C79712F799F9659145850C0D4999855FA1981`; it is a
local development handoff, not a new public release. See the
[package validation receipt](../results/r17-playtest-package-validation-20260929.json).

The final packaged four-second E1M1 smoke ran 139 simulation tics and 170
headless updates. It selected D_E1M1, returned all 175,140 submitted music
frames, and closed the device without errors. One queue-starvation poll came
after the final audio packet, with no rebuffer resume. These headless updates
are not displayed frames, and the short run does not establish continuous
campaign audio or map completion. The nine-map Episode 1 load/idle/render
smoke passed 9/9; the human HMP route remains pending. The candidate and
package receipts preserve the exact scope and raw report hashes.

## 2026-09-29 — Profile the R17 FastRenderer phases

On the R17 implementation under portable PowerShell 7.6.6, a fixed HMP E1M1
view was warmed for five frames and measured for 30 frames in each of 16
production-width stripes. The 480 stripes were rendered sequentially in one
process and retained the expected full-frame hash. Median geometry work was
6.935 ms per stripe (10.248 ms p95), versus 0.327 ms for actors, 0.086 ms for
the weapon, and 0.852 ms for the HUD; total median was 8.364 ms. This points
the next optimization at the wall/plane path but does not isolate an inner-loop
cause or establish concurrent worker pacing. It is not an FPS result and is
not directly comparable to earlier paired sector-cache runs. See the
[phase profile](../results/r17-fast-renderer-phases-20260929.json); the
complete 480-sample raw report and hash remain under ignored `local/`.

The article draft was refreshed to distinguish R17's current nine-map Episode
1 load/render smoke and all-map automap-bitset comparisons from the inherited
R16 36-map load/render sweep. R17 did not rerun that broader smoke; the full
Episode 1 human route remains the current playability milestone.

## 2026-09-29 — Audit the post-Preview.3 commit volume

At branch commit `3080188`, 78 commits followed `v0.1.0-preview.3`. The
Preview.3 release-preparation commit itself (`34e3d17`) changed seven
documentation/release files and no game source, which is the scope of the
clean-package note. Across the later 78 commits, 18 changed files under `src/`
(`+884/-186` lines), 30 changed files under `scripts/` (`+1,085/-103`), 100
measurement/result receipts under `results/` (`+40,542/-12`), and 20
documentation/release-note files (`+2,915/-170`). The `src/` changes are
runtime code; `scripts/` combines launch/runtime helpers with tests and
measurement tools. The 78-commit count therefore overstates feature work:
most changed lines are machine-readable evidence, and most commits record or
validate work. It is not accurate to call all post-preview work test harness,
but the ledger and harness activity outweigh product-code additions. These
counts compare the tagged release tree with `3080188` and count changed lines,
including generated receipts; they are not a measure of net project size or
human effort.

## 2026-09-29 — Reject cached wall-sector property reads

Following the R17 phase profile, I replaced repeated wall-loop reads from
sector snapshot hashtables with per-snapshot typed arrays for exact
interpolated floor/ceiling heights, ceiling-flat indices, and light levels.
Four initial candidate profiles looked faster than the four baseline profiles,
but the final-source adjacent baseline/candidate run changed median geometry
by only 0.5% and total renderer work by 0.6%; a second final-source candidate
sample was slower. The renderer profile does not include the new arrays'
snapshot-refresh cost. The result is not a sufficiently repeatable game-level
gain, so the candidate was discarded and `src/FastRenderer.ps1` remains at its
baseline source hash. The [receipt](../results/renderer-wall-sector-cache-rejected-20260929.json)
preserves ten raw profile hashes and their exact source fingerprints.

Correctness evidence from the discarded candidate is retained separately:
the 320x200 frame and all 16 worker-stripe hashes match the baseline; five
views across seven process strips match in Classic, Matrix/Katakana, and
AnsiArt/Katakana; moving-ceiling diagnostic images match at heights 0, 6, 34,
and 68; the 36-map load/idle/render smoke passes; and all 20 masked-wall
checks pass. The smoke and image comparisons do not certify route completion,
original-executable parity, live pacing, or a performance improvement.

## 2026-09-29 — Prepare Preview.4 at the commit threshold

The user requests a release whenever at least 35 commits have accumulated since the prior release. The branch had 80 commits since Preview.3 at ef5f487. Preview.4 packages the cumulative implementation without claiming the broader Ultimate Doom gates are complete. Fresh PowerShell 7.6.6 checks pass 36/36 map smokes, 69 campaign transitions, 97 boss assertions, 125 menu checks, 24 save checks, 27 mixer checks, 144 character-codec partition cases, and exact five-view/16-worker output in Classic, Matrix/Katakana and AnsiArt/Katakana with palettes and fuzz. The actual-device save worker passes 15 checks with the 30-entry music catalog; eight automap worker checks pass. Raw reports stay in ignored local/; the portable source/hash index is results/preview4-validation-20260929.json.

The initial test launch used a nonexistent portable executable path and ran no game; the correct path is local/pwsh-7.6.6-portable/runtime/pwsh.exe. A codec test's default report overwrote its historical tracked receipt; its fresh output was copied to local/ and the historical receipt restored. No user file was overwritten. Physical play, campaign completion, acoustic review, original-executable comparisons, repeated pacing and second-hardware evidence remain open. Packaged startup is checked before publication.

## 2026-09-29 — Publish and verify Preview.4

Preview.4 is published at https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.4, pinned to 8a1561d. The 544-file source ZIP SHA-256 is A9210CCBD736578DFF5DE12DCFD5195560A11C838AD20511F35AC51D0D4B91DA; a fresh public download matches. The manifest reports WorkingTreeDirty=true because the excluded untracked research PDF exists; tracked files were clean, every packaged payload hash matches, and the PDF is absent. Extracted preflight validates 36 maps and 30 catalog entries under PowerShell 7.6.6. An eight-second headless E1M1 device run advances 279 tics and 319 headless render updates and returns all 352,800 submitted audio frames. One queue-empty observation follows the final packet. This does not qualify sustained campaign audio, acoustic quality or display pacing. Twenty save/session-edge checks also pass. See results/preview4-package-validation-20260929.json. The published preview does not include later development changes.

## 2026-09-29 — Restore missing player notices

The engine emits pickup/key-lock/automap messages with a 140-tic lifetime, but the terminal path never displayed them. The new PowerShell module transports bounded sanitized ASCII within each seqlock-protected simulation snapshot and overlays readable text tied to the exact rendered frame. Classic/color art use bright red and Matrix bright green. Notices appear on automap, hide on session screens, and expire on simulation time. This deliberately uses the terminal font instead of the original WAD font; the shared 320×200 source raster remains unchanged.

Forty-one focused checks pass, including all three key-lock handlers, an actual E1M2 red locked door, real armor pickup, both output modes in each style, and actual-worker saved-notice restoration/140-tic expiry. Initial fixture failures were harness enum conversion, selecting a nonexistent E1M2 blue door, and a missing automap import. The first live Classic run consumed all 350 commands; its only checkpoint differences were two automap hashes because the oracle recorded before initial discovery on load. The corrected oracle discovers before the boundary checkpoints. Original reports and footage are retained; those fixture failures are not game defects. Twelve actual-save-worker and 58 replay-format checks also pass on the new source.

The retained E1M1 driver again completes in 1,560 ordinary commands. A generic route qualifier invocation used that older driver's incompatible sparse trace/final metadata shape and failed its final checks; it does not establish a product defect. The correct independent E1M1 continuation harness is Test-SessionProgression. Both raw attempts remain local.

## 2026-09-29 — Visual review rejects small notice typography

All three corrected terminal-font notice recordings finish 350 commands and their eleven independent checkpoints, with digital game audio, original footage and source receipts retained. Inspection of the Classic world/automap/armor/expiry samples found that one terminal row makes the text much smaller than Doom's own message font at the 5-point game profile. The prototype is superseded: simulation now draws the original STCFN font into a cached 320×8 notice, carries it atomically alongside the text/timer, and the host uses exact Classic half-block output or the readable menu downsampling for character styles. This adds a black notice band while active; it intentionally uses the base palette for readability. The source game raster remains full size, with no actor or simulation omissions. The prototype recordings remain evidence of the rejected typography, not final candidate footage.

The independent E1M1 continuation completes 1,747 commands through intermission and 71 E1M2 tics with inventory preserved. A frozen release-pacing protocol now gives machine/workload/display settings and numerical thresholds before the next live measurements. The PresentMon collector accepts actual audio and session controls and samples only owned game/Terminal process CPU and memory once per second. These samples are not continuously measured peaks and their overhead stays in the workload. The bitmap test's first attempt missed codec imports; the harness import is corrected, and its failed report remains local.

## 2026-10-01 — Resume and repair the actual notice host

Before the September 29 pause, the first loaded Classic PresentMon run stopped after 656 issued commands because `ConvertTo-AnsiStrip` was not imported by `Invoke-Doom.ps1`. The 48 focused bitmap checks had imported the helper themselves and did not exercise this host dependency; the earlier headless checks skip terminal output. The raw failed game/capture/frame reports remain under `local/candidate-pacing-classic-max-r1`. No failed-run timing is accepted as a completed-route performance result. The game processes had exited before the screen handoff; an exact PID/start-time ownership check found no remaining processes.

The resumed host explicitly imports `src/TerminalCodec.ps1`. The first corrected live Classic bitmap fixture consumes all 350 commands, matches eleven checkpoints, and exits cleanly with no game/audio error. Its media processing and visual review are still being completed before claiming recording qualification. The article now points to the actual public Preview.4 and its fresh 36-map validation. A documentation error claiming the existing PresentMon analyzer already produced per-world windows is corrected: it currently analyzes the global first-to-last-write interval, including transition holds.

## 2026-10-01 — Notice contrast and loaded pacing findings

Three original-font notice movies finish with 350/350 commands and eleven checkpoints each. An independent audit checks all observed world/automap text/timers and clean device/media completion. Its first assertion incorrectly expected expired text to remain in the transport because the fixture retains `Player.Message` after `MessageTime` reaches zero; the product correctly sends empty expired text. The failed report and exact audit script remain local, and the corrected audit passes 1,427 checks. These movies supersede terminal-font typography, but their Matrix sample still has poor contrast: the red IWAD font has low luminance in the ordinary green palette. A dedicated notice palette now uses channel peak brightness while retaining the reducer's original luminance ordering and black background. Only the notice emission changes; the world/HUD palettes and gameplay stay intact. Fifty focused checks pass, including maximum green brightness and black-background checks. The first contrast test ran after an atomic patch rejection and therefore lacked the new constructor; that failed local report is a harness/application-order failure, corrected before the passing run.

The collector now pins launcher/host/worker files and exact launch QPC. Its analyzer adds contiguous generation/state/map/screen windows, boundary gaps and nearest-rank p99 without excluding holds from global timing. Three retained Classic E1M1-to-E1M2 device runs on the same source reach 34.914/34.969/27.676 active tics/sec and 48.938/50.849/31.137 global Terminal display transitions/sec. R2 overlapped one PNG export/analyzer editing and is exploratory; R3/R4 have no concurrent recorder/export/qualification. The large R4 slowdown remains unexplained rather than discarded. Startup to first write is 37.254–39.498 seconds and sampled game private memory peaks at 5.419–5.440 GiB. All commands and submitted audio frames complete. These runs fail the pacing gate, do not identify distinct displayed Doom frames, and are not a passing three-repeat qualification. The portable receipt independently reconstructs display count/p99 from the raw CSV and retains CPU/audio/window details.

The brighter bitmap round passes 24 recording audits, but its Matrix screenshot still destroys small letter shapes when the seven-pixel font is reduced to four pixels. That typography is rejected. The final choice preserves the original font in Classic and uses the larger terminal font in Matrix/AnsiArt; fifty focused checks pass again. This is a documented style-specific typography approximation, without changes to world/HUD rendering, simulation or music. Fresh all-style footage is being completed on the final source. The new analyzer also passes the original legacy capture in a fresh local copy; absent world/startup/backlog metadata remains explicitly unavailable instead of breaking old reports or inventing passing values.

All three final typography recordings now finish 350 commands, eleven matching checkpoints, and clean device shutdown with every submitted audio frame returned. The independent final audit passes 24 grouped assertions covering every observed world/automap notice, and final Matrix/color-art samples show complete bright letters. Original assets stay local. The new R18 development ZIP at source `0918571` contains 548 manifest-verified files with no WAD, soundfont, executable/library, PDF or media. Its first extracted preflight used a nonexistent catalog filename and correctly returned the actionable missing-catalog message; the retry uses the documented eleven-track Episode 1 catalog. Extracted runtime verification follows before the package receipt is committed.

The extracted R18 preflight now passes under official PowerShell 7.6.6. Its eight-second E1M1 headless device run advances 279 tics and 299 headless updates and returns all 351,540 submitted audio frames. The device closes with no audio/cleanup error or rebuffer resume; one empty-queue observation follows the final packet. Every recorded source entry that occurs in the package manifest matches its hash. The [package receipt](../results/r18-playtest-package-validation-20261001.json) records the 1,674,438-byte ZIP with SHA-256 `1DFE6A69257F804607137BCFF4D0C9CAF1CF42C85523D34E39261D7FC5A24EE3`. The manifest's dirty flag reflects the excluded untracked research PDF, with tracked package inputs committed. R18 is a playable local development handoff; it does not close the full campaign, physical/acoustic, independent fidelity, repeated pacing or second-hardware gates.

## 2026-10-01 — Cache immutable renderer resources across maps

The earlier loaded Classic R3 E1M2 boundary spends 1,267.607 ms before asset preparation, 3,916.473 ms preparing renderer assets and 6,788.520 ms total. A fresh fixed-E1M2 stage profile isolates repeated texture/sprite conversion at 828–871 ms, asset serialization at 3,707–3,997 ms and read-back at 1,485–1,616 ms. The retained exploratory reports are `local/map-assets-baseline-20261001-r1.json` and `local/map-assets-reuse-20261001-r1.json`; they are not loaded-route comparisons.

Production simulation contexts now opt into immutable WAD-resource reuse. Each map retains private geometry, sectors, raster buffers and clipping scratch; contexts from another GameContent instance are rejected. The v7 asset transport remains readable by the existing reader. Static body bytes are cached with patch-order/object and flat/color-array identity checks; metadata is regenerated on every write. A changed sky rebuilds the single retained body rather than accumulating episode caches. Default contexts stay uncached for callers that deliberately mutate resource data. Reuse requires that the shared WAD-derived graph remain immutable.

The committed ABBA harness runs three sequential fresh/reuse/reuse/fresh cycles, with the initial cache cost reported separately. Fresh map preparation is 4,092–4,895 ms versus 81–112 ms with reuse; all twelve direct/read-back images have the same hash. Initial conversion takes 1,173 ms and body creation 3,905 ms, retaining 37,614,992 bytes. Read-back still costs 1,336–1,576 ms in this single-process test. This is a stage improvement, not a displayed-FPS claim. Actual sixteen-worker tests pass in Classic, Matrix and AnsiArt: per style 448,000 worker pixels, 112 encoded strips and 256,000 fresh-resource oracle pixels, with E1M2/E2M1/E3M1/E1M2 reloads and preserved PIDs. The [portable receipt](../results/map-render-resource-cache-20261001.json) pins the raw files, sources, IWAD and parameters. Full loaded-route timing follows separately.

The first complete audio-enabled live check consumes all 1,747 commands and enters E1M2 with no source drift or game/audio error and every submitted device frame returned. E1M2 preparation is 102.228 ms (19.873 ms context, 80.469 ms write), with the cached body actually reused. Total load remains 4,516.965 ms, including 1,187.946 ms before assets and the worker reload/acknowledgement. Global Terminal display rate is 51.530 transitions/sec, active simulation 34.980 tics/sec, p99 tic lateness 213.061 ms and sampled game private memory 5.487 GiB. Startup takes 40.114 seconds to first write. This single run misses the frozen pacing gate and is not a paired before/after route benchmark. The [independently audited receipt](../results/resource-cache-loaded-classic-20261001-r1.json) preserves the result; worker-side deserialization is the next targeted cost.

## 2026-10-01 — Reuse verified resource bodies inside persistent workers

The reader can now explicitly cache its immutable decoded patches/flats/colors. Each reload hashes the actual remaining file bytes after the metadata, compares that digest with the prior validated body and rebuilds fresh map metadata and raster scratch. A matching path or header is insufficient. Changed sky bodies invalidate the cache and take the ordinary decoder path. The private v7 format and default uncached-reader behavior remain supported. Worker reload timings and reuse decisions now appear in the host report rather than being inferred from a shorter pause.

All three sixteen-worker styles again pass 448,000 worker pixels, 112 strips and 256,000 fresh-resource oracle pixels each. All sixteen workers reuse E1M2's unchanged body and invalidate it for the changed episode skies. These runs precede the following length-check-only repair, explicitly pinned in the receipt. A synthetic changed-body/truncation regression finds that the existing flat/color reader accepted a short final color table. The failed `local/render-asset-reader-reuse-20261001-r1.json` is retained; full-length reads are now required for flats/colors and eighteen focused assertions pass, including changed-body fallback, refreshed geometry/palette metadata and private scratch. Three final-source ABBA stage cycles measure ordinary read-back at 1,295–1,505 ms versus 69–81 ms with verified body reuse; all twelve images match. Initial writer/reader cache construction remains reported. See the [reader receipt](../results/render-asset-reader-reuse-20261001.json). Loaded repeats follow without concurrent recording, export or qualification.

Three sequential live Classic/audio routes at `cfd8c26` finish all 1,747 commands, enter E1M2, have unchanged runtime sources and return every submitted audio frame with zero software starvation/rebuffer. All sixteen workers report body reuse. Total map load is 1,540.646 / 1,996.884 / 2,027.828 ms; sampled game private memory peaks at 4.469 / 4.598 / 4.541 GiB. Active simulation is 34.979 / 34.882 / 30.656 tics/sec, global Terminal display 55.184 / 53.750 / 47.430 transitions/sec and p99 tic lateness 150.965 / 186.411 / 5,168.668 ms. The gate still fails. The [audited receipt](../results/reader-cache-loaded-classic-20261001.json) independently reconstructs CSV display counts and p99 and preserves every window/load/CPU/audio result. This is three-repeat post-change evidence, not a paired causal full-route comparison with older builds.

The third slowdown is localized further: E1M2 terminal-output calls average 85.811 ms (max 362.526 ms), versus 12.245 / 10.016 ms in the first two runs. E1M1 output averages 7.938 / 7.952 / 8.617 ms. The third run has no audio backpressure; packet production averages 0.263 ms and worker E1M2 rasterization averages 10.197 ms. Its host is also the only input/replay producer, so synchronous output blocks admission of simulation commands. This supports investigating output/input decoupling; it does not yet explain why Terminal output slowed or prove that an asynchronous alternative will improve display pacing. Per-frame byte counts and paired output-path measurements are next. The worker harness now records source/runtime/IWAD hashes and rejects source changes during qualification.

## 2026-10-01 — Bounded asynchronous terminal-write alternative

Experimental `-TerminalOutput AsyncBatch` composes the same frame bytes in PowerShell and calls standard .NET Stream.WriteAsync. One pending job exclusively owns its buffer; the host continues supplying simulation commands and can prepare one next frame. Every frame keeps its own result metadata. Completion counts/timestamps are recorded only after the task completes and flushes; map loading and shutdown drain pending output. Strips remains the default. Per-frame output bytes and dispatch time are now reported separately from observed write completion, and the collector accepts/pins output mode and ANSI encoding for paired alternatives.

The first prototype failed a completion-ownership assertion because PowerShell emitted the runtime's boxed void-await result into the pipeline. Explicit void suppression fixes it; the failed report remains `local/terminal-output-async-20261001-r1.json`. The final transport test passes 108 byte-exact Classic/Matrix/AnsiArt comparisons across Strips, Batch and AsyncBatch, plus a real bounded named-pipe backpressure check and a broken-pipe failure check. Pending frames cannot overwrite the buffer or be counted as complete. This keeps formatting/copy algorithms in PowerShell; standard asynchronous I/O is not a compiled renderer.

One native Classic/audio smoke finishes all 1,747 commands and returns all 2,237,760 audio frames without software starvation/rebuffer. Its 2,683 completed writes sum exactly to the per-frame 1,635,875,764 output bytes. Most dispatch calls return well before completion. The single exploratory run measures 34.680 active tics/sec and 51.402 global Terminal display transitions/sec, with p99 tic lateness 107.412 ms. It still fails the pacing gate and is not a paired improvement claim. See the [transport/native receipt](../results/asynchronous-terminal-output-20261001.json). Same-source paired output trials follow.

The clean `06fb33b` Strips/AsyncBatch/AsyncBatch/Strips cycle finishes all four 1,747-command routes with clean audio and unchanged runtime source. Active simulation remains 34.975–34.979 tics/sec. Global display transitions are 54.910 / 54.868 / 54.069 / 50.610 per second; p99 tic lateness is 165.784 / 65.145 / 59.955 / 273.078 ms. Async dispatch averages 0.230 / 0.253 ms, and every frame/byte total reconciles. This supports lower simulation lateness in this cycle, not general superiority or a passing release gate. The [ABBA receipt](../results/output-abba-classic-20261001.json) independently audits CSV counts/p99 and retains CPU/memory, load and audio details. No recording/export/other qualification overlaps the four captures.

Source review then identifies a resize hazard: compact viewport warnings use direct synchronous Console.Write and could interleave with a pending asynchronous frame. The host now drains its pending job before writing those messages; an undersized viewport starts its reported pause before that drain. The output API also rejects either synchronous mode while a pending job owns output. The final transport test again passes 110 comparisons/pipe cases and now exercises those mixed-mode rejection assertions. These are correctness guards added after the paired captures, not present in their source. The recording wrapper accepts AsyncBatch; final-source all-style notice/automap/save-fixture recordings follow separately.

All three final-source AsyncBatch notice/automap/save-fixture recordings now consume 350/350 commands, match eleven checkpoints each, complete device audio cleanly and pass 24 grouped independent text/timer/media audits. Reviewed samples show complete readable Classic bitmap and Matrix/AnsiArt terminal lettering. The first Classic sample, selected at the earliest message-bearing write timestamp, still shows the loading screen in the movie; a later tic-20 sample shows the expected world and notice. Both samples are retained. This further illustrates why write completion is not optical display identity.

Recorder failures remain separate: Matrix WGC R1 passes the game/audio fixture but FFmpeg exits with access violation `-1073741819` during finalization. GDI R2 uses the minimal diagnostic recorder, which lacks gdigrab/framerate and exits before readiness; the created host/workers subsequently exit and only its recorded new Terminal window is closed. Full-build GDI R3 completes the fixture but produces over 99% black video, which the merge validator rejects. Fresh WGC Matrix/AnsiArt R4 succeeds. No game/render/audio algorithm is changed to accommodate recording. Original failed media/logs/reports and successful raw video/PCM/QPC metadata remain local. The [live receipt](../results/async-player-notices-live-20261001.json) records successes, failures and sample hashes. These recorded runs are separate from clean performance comparisons and do not qualify physical input, acoustic latency or campaign completion.

R19 preparation freezes the post-Preview.4 notices/cache/optional AsyncBatch source for a fresh local handoff. The playthrough guide selects R19 with default Strips and preserves R18. The article and changelog now include the successful fixtures and unsuccessful pacing thresholds. Extracted package validation follows; no test success or full-release qualification is predeclared. This local candidate does not reset the 35-commit public release count.

R19 extracted validation passes and retains source f0a16af, all 551 payload hashes, ZIP SHA-256 CF44D1D7842A48B85ABF8ED70B9E27DE422A50E09896F2CF35F1EA1FBBC47603 (1,695,503 bytes), all three live-source manifests, preflight with eleven music tracks, 110 output cases, 18 cache boundaries, 125 menus/46 screens, 15 music-enabled save-worker checks and all-style sixteen-worker cross-sky reloads with independent fresh-resource image oracles. The actual-device startup returns all submitted audio frames and closes; raw queue observations remain in results/r19-playtest-package-validation-20261001.json. This is a development handoff, not full-release qualification. Only excluded untracked docs/gebbdoom.pdf makes the manifest dirty. No WAD/SF2/binaries/media/PDF enters the ZIP. R18 and all originals are preserved. Local packaging does not reset the public release count.


Three clean live encoding ABBA cycles complete at checkout 61c7f7e with the frozen R19 runtime, Classic/maximized/font5, sixteen workers, same 1747-command route/settings/IWAD/music and AsyncBatch in both encoders. All twelve runs consume all input, return every submitted audio frame, close cleanly and report no software starvation/rebuffer. Fresh exact-color checks pass thirteen cases. Raw captures and analyzer output remain local; results/colorstate-abba-classic-r19-20261001.json pins their hashes and independently verifies CSV event counts/p99 and completed-frame byte accounting.

The first audit falsely fails host-source identity because dictionary property order differs between JSON files. The failed auditor is retained as local/audit-colorstate-abba-r19-failed-r1.py. Canonical sorted path/hash pairs confirm one identical host-source set; the corrected audit passes. No capture is rerun or dropped to repair the auditor. The original independently audited receipt and supplemental audit are both retained and hashed.

ColorState uses 14.73% fewer median observed bytes/frame; median global display-event rate is 53.750 versus Pairs 51.668/sec. Within-cycle mean differences are +2.39%, +8.86%, +0.03%; the last cycle effectively ties and retains a slow ColorState run. Sampled private-memory medians are 4.105 versus 4.534 GiB, with lower-bound sampling caveats. Startup first writes take 38.55–53.29 seconds. All global display rates remain below 59, and maximum display gaps remain 1.24–2.92 seconds; no run passes all numerical gates. Identical input does not make the observed image samples identical.

Failure investigation retains 1/4 at 34.641 reported active tics/sec, whose final observed asynchronous output drain takes 741.6 ms. No alternate denominator substitutes a passing rate. ColorState 3/3 measures 34.672 tics/sec, p99 lateness 370.199 ms and maximum 440.081 ms. Its E1M2 mean slowest raster is 19.0 ms, snapshot publication 9.0 ms, game update 6.8 ms, packet production 0.175 ms and observed output completion 15.0 ms, with zero audio backpressure. Its 2.9-second observed intermission completion overlaps the map load; observation timestamps cannot prove native I/O blocked throughout. Scheduling/system/thermal cause remains unestablished. Defaults stay Pairs/Strips. Continue transition-gap and broader workload/fidelity/campaign work; this optional encoding evidence does not qualify the full release or reset the 35-commit release count.


Post-R19 loading work separates map-reload start from polling completion. The existing synchronous wrapper remains; the API rejects another reload, rendering and harvesting while its pool is owned, and checks all workers for errors before collecting completion. A thirty-second total deadline applies to that owned reload. All three actual sixteen-worker fixtures preserve their processes and compare 448,000 pixels/112 strips plus 256,000 fresh-resource oracle pixels across E1M2/E2M1/E3M1/E1M2. The classic fault variant corrupts only its generated owned asset and propagates Unknown render asset format in 22.3 ms, then cleans up its workers/assets. Earlier all-style harness reports precede only the later fault-option extension; GameProcesses source is unchanged between them.

The host now polls preparation, drains/discards old render work, presents a custom centered PowerShell loading banner, polls worker reloads and consumes the exact new generation before resuming. Tiny windows receive clipped text. Loading has a separate bounded asynchronous output context and counters; no UI write contributes to gameplay FrameStats or CompletedFrames. The actual renderer and mixing remain PowerShell. The helper uses standard .NET stream Tasks. R19/public Preview.4 remain unchanged.

The independently decoded UI passes 84 viewport/animation cases. The headless saved-message fixture consumes 350 commands and matches eleven checkpoints with zero loading UI credit; it precedes only the added old-render error/deadline check. Final-source WGC recordings include that guard. Classic ordinary-input E1M1/intermission/E1M2 consumes all 1747 commands, preserves sixteen PIDs, logs 118 reload polls/seven UI updates and returns all 2,222,640 submitted audio frames. Classic/Matrix/AnsiArt save recordings consume 350 each and match eleven checkpoints each. They pass 24 grouped independent notice/audio/media assertions and 34 additional lifecycle/ownership/accounting checks. Classic/AnsiArt exercise Strips; Matrix exercises AsyncBatch. Raw media, audio and metadata stay local.

The first cloned audit description incorrectly labels every recording AsyncBatch. Its successful initial receipt is retained under local/loading-ui-notice-audit-initial-r1.json; the regenerated receipt identifies actual modes. Assertions are unchanged. results/loading-ui-live-20261001.json retains all raw hashes, separate UI/game byte/frame accounting, disjoint reported output ownership intervals (one-ms rounding tolerance), worker and UI reports, and reviewed full-resolution visual samples. The banner is a custom terminal graphic, not an original IWAD menu patch.

The ordinary route first loading update dispatches in 7.15 ms but its completion observation takes 989.6 ms; following observations are about 100 ms apart. First save-fixture observations take 3.5–12.2 ms. No pause-free display or clean pacing improvement is claimed; neither Task/terminal backpressure nor delayed host observation is established as the cause. The next useful investigation brackets actual Task completion observations and repeats clean ETW handoffs. Physical input/resize/acoustics, optical frame identity, independent moving-world fidelity and full campaign remain open. This change does not reset the user's 35-commit release count.

Output-delay investigation adds PowerShell observations around the standard stream Task: timestamp before a false IsCompleted read, timestamp after the first true read, probe counts and the write-call start. Immediate completion retains its first observation even when the host later collects it; waiting/polling preserves the last false observation. This brackets operation completion without a custom compiled callback, and does not establish optical display or isolate native I/O from scheduling. Gameplay and loading reports retain the bounds separately from their existing completion/flush timestamp. The final test passes 110 byte/ownership/pipe cases, including immediate completion and a deliberately delayed observer after an actual bounded pipe drains. Raw result local/terminal-task-bounds-r1.json; clean live handoffs follow, with no performance success predeclared.

### 2026-10-02 — Loading write completion and renderer log ownership

Three clean source-pinned cb7731d Classic/default Strips sessions finish all 1747 commands with clean audio. Independent CSV audits retain 49.587–53.428 global display transitions/sec, 34.897–34.979 active tics/sec, 3.737–3.855 GiB sampled private memory and 40.220–42.758-second startup. Every first loading write remains pending through 981.8–983.6 ms after the write call starts; first true observations follow at 983.8–985.7 ms. Bracket widths are 1.94–2.03 ms and each write receives 495–499 false probes. A delayed host observer alone cannot explain this interval. The [bracket receipt](../results/loading-task-brackets-classic-20261002.json) preserves raw hashes and per-update bounds; optical identity and the split between I/O and scheduling remain unknown.

Source inspection identifies thirty-two idle ReadToEndAsync Tasks for sixteen renderer processes, plus two simulation pipe readers. The installed .NET 10.0.12 console stream inherits its three-argument WriteAsync from System.IO.Stream; its initial minimum worker count is twenty. Thread-pool contention is a hypothesis, not a captured-stack diagnosis. Renderer output now redirects within PowerShell to unique owned stdout/stderr files, eliminating those thirty-two host readers. Successful empty files are removed; error/nonempty logs remain. Startup errors before the memory-mapped channel opens are caught and retained. A loading write records ThreadPool counters before dispatch without changing runtime settings.

All three actual sixteen-worker tests pass twenty grouped assertions per style, four map/sky changes, independent encoded-strip/pixel comparisons, resource reuse and promptly propagated corrupt-owned-asset failures. The final plain synchronous Classic reload passes too. Its first attempt exposed an existing harness-only flattening of the one-element map-pair array; the failed report is retained and assignment is corrected. A fresh-directory missing-channel test exits one and retains the startup error/stack. The [logging receipt](../results/worker-file-logging-20261002.json) pins these checks. Three clean corresponding live measurements follow; no improvement is predeclared. R19/Preview.4 remain frozen and full campaign/performance qualification remains open.

Three clean 22219c8 repeats complete. First loading Tasks are already complete at their first probe: upper bounds 2.7199 / 2.6640 / 2.7186 ms, versus about 983 ms before. At dispatch the host reports four pool threads, two busy workers, zero queued work and the unchanged twenty-thread minimum. Startup is 27.223 / 26.972 / 27.013 seconds. Sequential source cohorts, installed-method reflection and removing the idle readers support the hypothesis, but no baseline stack/counter capture proves the exact mechanism. Docs cite Microsoft's starvation guidance and .NET 10.0.0 reference source, distinguishing it from installed 10.0.12.

The [after-change receipt](../results/renderer-file-logs-pacing-classic-20261002.json) independently reconciles CSV and separate UI/game bytes, all1747 input commands and fully returned device audio. Display rates remain 52.397 / 50.541 / 50.908/sec; tics are 34.977 / 34.975 / 34.851/sec; p99 lateness worsens to 624.1 / 920.7 / 795.7 ms. Sampled private memory is 4.519–4.553 GiB. All numerical gates do not pass. An outer analysis command's misplaced stream redirection fails after all three analyzers have produced valid summaries; these summaries are independently audited, and no capture is rerun or discarded for the shell error.

A separate actual WGC/loopback route passes 36 source/lifecycle/media checks, consumes1747 commands, preserves sixteen workers and reports21 separately counted loading writes. First UI Task upper bound is3.3571 ms. The reviewed full-resolution-origin sample shows a centered readable red banner; review output is resized to2048x829 from3440x1392. Original movie/PCM/clock metadata and sample hashes are in the [live receipt](../results/renderer-file-logs-live-20261002.json). This is not a clean benchmark, acoustic measurement or human Episode1 completion.

Further investigation localizes maximum tic lateness to commands58–73. Median mix blocks are about0.7 ms, but packet construction-to-submission medians are661.7 /871.3 /872.1 ms. Runs2/3 retain1159/1220 audio producer-backpressure waits beginning at command162/157; realtime filler generated30/42/45 blocks. Zero software starvation/rebuffer does not establish low latency. Source inspection suggests filler duration followed by fully replayed caught-up packets accumulates playout delay; next reproduce a bounded gap/recovery before changing policy. Defaults remain Strips/Pairs, algorithms remain PowerShell, and the full release goal is active.

### 2026-10-02 — Controlled realtime audio recovery

A controlled muted waveOut/qualified-music test confirms persistent backlog without rendering: a 300 ms producer gap leaves a 312.7 ms final packet-age maximum; a 700 ms gap leaves 711.6 ms, even after two seconds of resumed 35-Hz packets. Every packet is consumed and both reports have zero software starvation. The original test source, runtime commit 6229287 and raw reports are preserved.

The PowerShell audio worker now credits intervals already represented by realtime filler. It applies every caught-up packet's controls/events in order without adding its duration again. Newly received sounds begin on the current output clock; successive emitter replacements may coalesce before the next output block, and past audible output cannot be reconstructed. A final credited effect produces one fresh output block before the explicit drain acknowledges it. World epoch, volume reset and music Start/Stop clear prior timing credits. Non-realtime playback keeps one exact block per packet.

The first prototype passes transport accounting but fails the old harness's expectation of twenty submission-age samples: 130 of 131 intervals are credited and have no separate PCM submission. That raw failure remains. The corrected harness measures all packet-processing ages and independently checks packet, timing-credit and submitted/returned-frame conservation. Final 300/700 ms recovery cases have 19.93/17.80 ms maxima; the four-event Start/Stop/final-effect case reaches 29.68 ms, applies all four credited controls and emits the final 1260-frame effect block before drain. These endpoints exclude device/acoustic tail; baseline submission ages include a mix step that final processing ages do not.

Eighty-one existing mixer/packet/device/volume/rebuffer/loading/music/realtime checks and fifteen actual music-enabled realtime save/load/new-game checks pass on the final worker source. Independent PCM cases preserve packet-exact output. The [recovery receipt](../results/audio-realtime-recovery-20261002.json) pins results and retained failures. Collector and recorder manifests now explicitly include Invoke-AudioWorker; previous captures lacked that standalone script hash, though source commits remain pinned. Final live route/effect recording and three clean loaded repeats follow. No loaded performance or acoustic success is predeclared.

Three clean source-pinned 0dd795b routes complete all 1747 input/audio packets with fully returned PCM and no software starvation/rebuffer. Every packet's processing age and all timing credits reconcile. Producer-backpressure waits are zero; median processing ages are 85.5 / 65.4 / 76.5 ms, versus prior submission medians 661.7 / 871.3 / 872.1 ms. The endpoints differ by mixing and both exclude device/acoustic tail. Maxima remain 184.1 / 166.7 / 177.2 ms. Sources, settings, CSV and separate UI/game accounting are retained in the [loaded receipt](../results/audio-recovery-loaded-classic-20261002.json).

Active tics are 34.810 / 34.966 / 34.972 per second; display events are 53.795 / 53.249 / 52.619 per second. P99 lateness remains 461.97 / 405.03 / 550.24 ms, with initial stalls. Steady command350–1400 medians of 7–8 ms are diagnostic only, never a substitute gate denominator. Startup is 26.37–27.61 seconds; sampled private memory is 4.469–4.559 GiB. No run passes all numerical gates.

A separate final WGC/loopback ordinary route passes46 source/lifecycle/media assertions, retains every packet age and timing credit, preserves sixteen workers and reports17 separate loading writes. A reviewed sample shows the banner; original media and source hashes are in the [live receipt](../results/audio-recovery-live-20261002.json). R20 preparation freezes this runtime for a new local whole-E1 handoff; extracted manifest/preflight, recovery/effect and worker/menu/save checks follow. The source/recording fixes stay PowerShell, all three styles remain available, and public release count reaches24 with this evidence/preparation commit. Local packaging does not reset it.

R20 extracted validation completes at source c4175ef6f628a0639efe71a482f5c668d924e0af. All 557 payload hashes and exact ZIP contents match; ZIP SHA-256 is 45AED018D4B6679066D31906345575C9928F110892E2AA2B05DAE5D3C3D8FC82 (1,723,727 bytes). Only excluded untracked docs/gebbdoom.pdf makes the manifest dirty. Final recorded Classic sources match every extracted counterpart. Official PowerShell 7.6.6 preflight accepts 36 maps and eleven tracks. No local assets/tools/media/PDF enter the package.

Extracted checks pass 110 terminal output/ownership/pipe cases, 18 resource-reader boundaries, 125 menu checks/46 screens, 15 actual music/realtime save/load/new-game checks and the controlled recovery/final-effect drain (29.51 ms maximum processing age). Each style passes twenty actual sixteen-worker nonblocking reload/fault assertions with 448,000 compared worker pixels, 112 strips and 256,000 fresh-resource oracle pixels. An eight-second actual-device startup advances 279 tics and returns all submitted audio frames, then closes. The [package receipt](../results/r20-playtest-package-validation-20261002.json) retains raw startup/queue/drain details. A queued PCM credit is produced output, not proof of sound already reaching the speaker; audio docs clarify that distinction.

The whole-E1 guide now uses fresh R20 saves/input/reports and preserves R19. This is a verified playable development handoff with explicit remaining gates, not the fully qualified Ultimate Doom release candidate. Broader campaign, original-executable moving-world fidelity, physical/acoustic review, distinct optical frame timing and second hardware remain open. Public release count reaches25 after this validation; the35-commit release rule is unchanged and the full goal remains active.

### 2026-10-02 — Early command publication investigation

Independent inspection of the three retained final-runtime traces confirms that maximum early lateness occurs at commands67/70/69. First350 presentation-stage maxima are roughly28–39 ms; the largest game update is about89–100 ms at command311. Repeated approximately115–119 ms gaps before command33 and other gaps between stages dominate the initial lateness accumulation. Update-start estimates subtract the stopwatch duration from update-end QPC and include instrumentation uncertainty; they are not OS scheduler traces. The raw stage audit is local/r20-early-tic-stage-inspection-r1.json, generated by local/inspect-r20-early-tic-stalls-r1.py.

The host currently issues at most one due command per outer rendering loop, with an unchanged two-command window. Add timestamps around publication/signal, active-clock due/issue times, prior consumed count and prior completed frame count. This separates delayed producer publication from worker wakeup/consumption delay without changing gameplay commands or their queue bound. A clean diagnostic route follows before attributing the gaps or changing recovery. R20 remains frozen; full release qualification is open.

The clean bfc62c1 diagnostic consumes all1747 commands. At maximum early producer lateness, command62 is published789.0 ms late with zero previously queued commands; the worker's approximate update start follows signaling by0.28 ms. A153.2 ms publication gap before command30 includes143.6 ms of output; command13's107.2 ms gap includes95.8 ms. The [publication receipt](../results/command-publication-stall-diagnostic-20261002.json) preserves each command and output overlap, the raw source hashes and inference limits. This establishes delayed production in this run, not an OS scheduling/optical diagnosis or general performance qualification.

The host now catches up already-due commands within a four-command per-pass budget and the unchanged two-command outstanding window. Recheck the active clock and loading status after each send. Exact recorded save/load/control boundaries stop a burst so the outer control loop handles the action before any later command is queued. Replay exhaustion still waits for consumed commands, then exits the outer loop. New traces report pass membership and actual bursts. Headless save/checkpoint/viewport checks and clean native repeats follow; no pacing success is predeclared.

All three real headless sixteen-worker fixtures consume350 commands, preserve every input field and both exact load controls, match eleven checkpoints each and pass fourteen admission/audio assertions each. Independent tracing verifies commands are already due, each observed pre-publication queue is below two and pass indices/order agree. Matrix exercises one two-command burst at244; Classic/AnsiArt stay at one. Neither exact control boundary is itself encountered inside a multi-command burst. The [fixture receipt](../results/command-burst-fixtures-20261002.json) states that coverage limit and distinguishes subsequent host hashes from run-embedded provenance: the replay fingerprint excludes Invoke-Doom.

The mapped-ring test passes five checks including1200 distinct commands/masks across1024-slot wrap and the hard overflow guard. Synthetic viewport integration pauses twice, issues no commands during either undersized interval and preserves the active clock; it is not a physical resize test. Admission audio auditing now reconciles produced realtime filler/credited frames rather than assuming one PCM block per consumed packet. Three native clean repeats and live control recordings follow the scheduler source freeze. R20 stays unchanged; this implementation/evidence commit reaches27 since Preview.4.

Three clean f200220 repeats finish all1747 commands, with33/63/34 two-command bursts. Due times, pass order and observed queue bounds pass independent audits. Active tics are34.972/34.959/34.979/sec; display events48.922/48.719/50.376/sec; p99 tic lateness105.64/646.89/79.41 ms. No complete numerical gate passes. Startup25.57–27.43 seconds and sampled private4.546–4.609 GiB remain within their individual limits. All audio packets, produced/returned PCM and timing credits reconcile; no producer backpressure, software underflow or rebuffer. Median processing ages81.8/164.6/93.3 ms remain digital endpoints.

The second repeat's worst early producer issue is788.4 ms late at command55 with zero queued commands observed and an approximate worker update0.31 ms after signaling. The preceding167.5 ms gap overlaps155.1 ms of terminal output. Repeats one/three also overlap synchronous output at their worst early publication gaps. Catch-up retains useful semantics but does not prevent output stalls; successive source cohorts do not establish paired causal improvement, and display rates are lower than the prior cohort. The [clean receipt](../results/command-burst-loaded-classic-20261002.json) preserves all failures and gate denominators. Native control/effect recordings follow separately; bounded AsyncBatch comparison on this runtime is the next useful pacing experiment. Public count reaches28 with the measurement commit.

Separate final-runtime WGC/process-loopback fixtures finish in Classic, Matrix and AnsiArt:350 commands, eleven checkpoints and fourteen command/audio checks per style. Independent notice and lifecycle audits pass24+37 grouped checks, preserve both exact load controls and all36 recorded source hashes, and reconcile every packet, realtime credit and returned PCM frame. Actual burst counts are7/8/13, maximum two commands per pass. UI/game writes remain separately accounted. Six full-window-origin samples review red-lock notices in automap and armor pickup notices in world/style views; review images are2048x829 resized from3440x1392, not complete-film or human-playability certification.

The [live receipt](../results/command-burst-live-20261002.json) retains original local media/audio/clock/source hashes and the explicit coverage limit: command174 is first in its pass in all three recordings. Thus no control crossing occurs, but stopping a multi-command pass exactly at175 is not exercised. R20/Preview.4 stay frozen. This live-validation commit reaches29 since Preview.4; the next clean study holds the same runtime/route/encoding fixed and compares Strips/AsyncBatch in three full ABBA cycles. No default change or performance success is predeclared.

Three complete same-source Strips–AsyncBatch–AsyncBatch–Strips cycles finish at cafa405 (runtimef200220). All twelve retain1747 ordered commands/audio packets, due/observed queue bounds, complete source manifests, independently reconstructed CSV display counts/p99 and separate UI/game/credit/PCM accounting. Collection runs sequentially without study tests/recordings/exports/timing analysis; low-frequency status reads include one inspection of completed game reports. No source changes occur. [Paired receipt](../results/command-output-abba-classic-20261002.json).

AsyncBatch cycle medians lower p99 tic lateness77.33→61.03,87.36→67.22 and151.35→91.14 ms, while display-event changes are+3.28%,−1.65%,+3.47%. Only one of six asynchronous p99 values meets57.2 ms; no run passes all numerical gates. All active tic rates34.960–34.980 meet their individual rate check. Global display rates47.29–56.05/sec remain below59; startup24.74–27.22 seconds, sampled private4.414–4.617 GiB and sampled game CPU41.6–47.6% of twenty logical cores retain explicit sampling limits. Every audio packet, credit and produced/returned PCM frame reconciles, with zero producer backpressure/software underflow/rebuffer. Acoustic endpoints remain unmeasured.

Outlier inspection retains cycle3/position1 Strips command50 issued336.1 ms late, observed queuezero, approximate worker start0.39 ms after signal and157.2 ms synchronous-output overlap in the preceding180.6 ms gap. Cycle2/position2 AsyncBatch's1575.75 ms display-event gap contains96 gameplay completions (largest consecutive completion gap21.08 ms),94 dropped present starts and no loading UI. No physical-display, OS scheduling, occlusion or thermal cause is established. Cycle3/position2's303.08 ms display gap overlaps four loading observations and no game completion. Asynchronous output intervals remain completion observations rather than synchronous-blocking proof. Nothing is dropped from gate denominators.

Defaults remain Strips/Pairs, with AsyncBatch opt-in: paired evidence supports a narrower tic-pacing benefit and variable display results, not a general winner or full release pass. Stop repeating this same comparison without new changes or a justified unresolved concern; move to concrete frame-cost/fidelity/broader-workload work. All algorithms remain PowerShell and all styles remain available. This evidence commit reaches30 since Preview.4; publish at35 or more. R20 is the stable playable development handoff, while full campaign, original-executable moving-world fidelity, physical/acoustic/display and second-hardware gates remain open.

### 2026-10-02 — Independent original-binary frozen-view diagnostic

Prepare-OriginalDoomFixture.ps1 authors a vanilla109 demo from explicitly quantized ordinary input, then a pause packet and finite empty packets. Four successful preparations decode all315 input commands exactly, freeze candidate LevelTime315 and repeat all64,000 indexed pixels. The final helper also pins the engine bundle, preserves DEFAULT.initial.CFG, and rejects fractional packets/existing directories before creating output. The first palette-report failure remains local.

Four finite original DOSBox runs have exited. The retained642x512 JPEG shows original Doom paused in the corresponding wall/pistol/health/ammo view; it is a lossy visual diagnostic. Observed shortcuts produced no raw PNG/PCX. Automatic approval review rejected another visible launch before execution, without a detailed reason; no bypass or further launch was attempted. Original hidden state, exact framebuffer parity and broad moving-world fidelity remain unqualified.

The first independent file audit detects DEFAULT.CFG changed after original Doom exits. All eight explicit settings survive; the original adds defaults/formatting. Preserve both hashes and verify the emitted hash against the untouched next fixture, rather than silently accepting a general mismatch. All demo/image/emulator-config hashes agree. The [receipt](../results/original-doom-frozen-fixture-20261002.json) distinguishes candidate checks, observed independent evidence, retained failures and rejection. User-owned EXE/IWAD/emulator/images/input remain ignored; production algorithms remain PowerShell. This milestone reaches31 commits since Preview.4; publish at35 or more.

### 2026-10-02 — Frame-cost attribution before optimization

The [post-collection twelve-run audit](../results/host-frame-cost-audit-20261002.json) groups world frames by map generation without changing gate denominators. E1M1 median worker critical spans are12.18–13.24 ms; E1M2 spans19.82–22.79 ms. Median maximum worker render duration rises from7.88–8.73 to14.43–17.09 ms. Unattributed per-worker elapsed medians are only0.17–0.20 ms and include copying, bookkeeping and scheduling; they are not pure pixel-copy measurements. Defer the proposed omission of sixteen64,000-byte indexed publications: final images/captures require them, and these traces do not justify that extra lifecycle complexity.

Add opt-in geometry-detail QPC boundaries to the PowerShell profiler. Default production workers make no additional QPC reads. One fresh fixed E1M2 startup profile attributes the slowest stripe's14.25 ms total median mainly to10.12 ms wall traversal/drawing, versus2.22 ms planes. Across all stripes, geometry median is6.32 ms, walls4.29 ms, planes1.88 ms; independent medians are not additive. An E3M6 startup profile has different state/geometry and cannot stand in for dense moving gameplay. Both use three warmups/twenty samples per sixteen stripes sequentially, not concurrent live workers or display timing.

Detailed profiling preserves the prior E1M2 full-frame hash and all sixteen measured stripe hashes. Default actual16-process tests compare the exported prior renderer in Classic, Matrix and AnsiArt over five E1M2 views each:960,000 pixels and240 encoded strips match. The first test fails because the local baseline export lacks relative dependencies; preserve that log and correct in a fresh owned directory. [Stage/profile/source/equality receipt](../results/geometry-stage-profile-20261002.json). Continue a bounded exact-output wall-loop investigation rather than changing pixel transport or claiming a pacing gain. This reviewable instrumentation/evidence milestone reaches32 commits since Preview.4; release at35 remains required.

### 2026-10-02 — Reject power-of-two wall wrapping trial

A local-only wall-loop trial replaces normalized remainder with signed bit masks for power-of-two texture heights, keeps general-height modulo and hoists the texture-column offset. It preserves floating sampling arithmetic. Three sequential ABBA fixed-E1M2 profiles retain all twelve full-frame hashes and sixteen measured-stripe hash sets, but do not support adoption. Median stripe totals are3.62%,0.77%,1.61% slower; summed stripe medians are2.95%,0.33%,1.54% slower. Slowest-stripe reductions2.71%/2.35% reverse to a6.61% regression in cycle3; total p95 changes also vary, ending6.998% worse.

The [retained twelve-run receipt](../results/rejected-wall-texture-wrap-20261002.json) pins local trial/baseline/harness bytes and all run metrics. These isolated startup-view timings are not live worker/display results, causal confidence intervals or whole-campaign fidelity. Reject the trial without adopting it; no broad tests or repeat benchmark are justified for this discarded path. Production stays at032d009. The exact-image failure-free trial still provides no repeatable speed advantage. Continue a different wall-traversal/representation investigation or broader qualification. This evidence milestone reaches33 commits since Preview.4; publish at35 or more.

### 2026-10-02 — Prepare Preview.5 at the release cadence

Prepare the public cumulative preview from committed fixes after Preview.4: readable notices, immutable map resources, bounded asynchronous output option, pollable loading feedback/owned logs, realtime audio recovery and bounded already-due command catch-up. Keep Strips/Pairs and all three styles. The [release scope](release-preview5.md), README/changelog and whole-E1 guide distinguish playable preview from still-open full qualification. Preserve R20 and use fresh Preview.5 human saves/input/settings/reports.

This preparation commit reaches34 since Preview.4. Build/extract from committed inputs, validate hashes/preflight/actual worker/menu/save/audio/admission checks, then commit the evidence at35 and publish immediately. No package or test success is predeclared. No asset/tool/media/PDF is included; diagnostic original binaries stay local. Existing performance/recording receipts retain explicit source and endpoint limits.

### 2026-10-02 — Preview.5 extracted validation and release threshold

All559 payloads match the manifest and committed package source1681532d0ea63fd4fcdd95e153f74694a3cbb446 after checkout newline normalization. The1,735,913-byte ZIP has SHA-256 3B767865F367A51D00F09BFEC1ECAA8CF9B4E6BDED28943375DA3C69FAEEED0C. License/attribution checks retain all206 adopted GPL PowerShell sources and exclude commercial assets/tools/media/PDF. Only excluded untracked docs/gebbdoom.pdf accounts for the manifest dirty flag. A wrapper first serializes the external process's formatted text rather than its object, causing extraction to receive a null path; preserve that malformed metadata and verify/extract the existing ZIP directly, without rebuilding.

Extracted preflight recognizes36 maps/eleven E1 tracks under PowerShell7.6.6. Output110/resource18/menu125+46screens/save-worker15 checks pass. All three styles pass20 persistent16-worker reload/fault checks each, comparing448,000 worker pixels plus256,000 fresh-reference pixels each. Recovery/effect/credited-control tests reach19.4071 ms maximum digital age and complete the final effect before drain. The eight-second startup advances279 tics and returns all360,360 submitted audio frames; no software rebuffer occurs. The reported34.847 headless active rate is not a pacing-gate success.

All36 maps pass35 idle tics/two indexed headings each, with source pins matching extraction. The ring passes five wrap/overflow checks. Actual extracted Classic/Matrix/AnsiArt save/control fixtures each retain350 commands, eleven matching checkpoints and14 admission/audio checks. Retained WGC/loopback footage matches35 of36 packaged sources: only the renderer's opt-in profiler differs, bounded by prior-renderer default image/strip tests. Do not call the footage fully final-source identical. [Full package receipt](../results/preview5-package-validation-20261002.json).

This validation commit reaches35 since Preview.4. Tag/publish Preview.5 now, then verify a fresh public download and remote tag/branch. Archive source34 and release tag35 are explicitly distinguished; no gameplay/source changes are introduced during validation. Community-preview publication does not complete the full Ultimate Doom goal. Campaign/human input, independent moving-world/framebuffer fidelity, sustained pacing, physical/1080-DPI/acoustic and second hardware gates remain open.

### 2026-10-02 — Preview.5 published and independently downloaded

Public Preview.5 is created immediately at35 commits after Preview.4, tagged56e132a39a6ee1ad864df37eca73438c70afa7a8. A fresh public ZIP/checksum download matches the tested1,735,913-byte archive and GitHub asset digests. All559 payload hashes/exact archive entries pass again. All478 runtime payloads independently agree with the release tag after checkout newline normalization. Manifest preparation source1681532 and validation/tag56e132a remain explicitly distinct. Remote branch/tag are verified; [publication receipt](../results/preview5-publication-20261002.json).

The cadence resets at Preview.5; this publication-evidence commit is the first subsequent commit. Refresh the article's formerly current Preview.3/R17 package discussion to the public Preview.5 evidence, with remaining campaign, fidelity, pacing, physical/acoustic/1080-DPI and hardware limits. No asset/media/tool is published and no full Ultimate Doom completion is claimed. The complete goal remains active after this playable preview.

### 2026-10-02 — Preview.5 dense E3M6 all-style pacing

**Ownership correction:** this entry's separate-audio-process inference below is superseded by the later source/live-PID audit. Audio runs inside the sampled simulation process; the numerical measurements are unchanged. See [the correction receipt](../results/audio-process-ownership-20261002.json).

Nine sequential native clean stress captures complete at7063aa3 with three repeats per style, full30-track catalog,16 workers and default Strips. Classic uses Pairs/font5; Matrix/AnsiArt use their character encoders/Katakana/MS Gothic12 (runtime AnsiEncoding is correctly NotApplicable). All420 exact commands and both stored endpoints repeat. Each ends Health0/Kills0/OutcomeStopped: the captured stress input includes player death and does not qualify ordinary combat navigation or map completion. Source fingerprint in the supplied old replay is null; actual runtime/input/launch hashes remain pinned by each capture.

Active tics are Classic30.537/30.502/30.392, Matrix30.811/28.582/29.761, AnsiArt30.049/29.648/29.922 per second. Global display events are40.041/39.478/39.660,47.249/45.288/44.785,42.803/42.668/42.306. P99 tic lateness spans1646–2707 ms. No full numerical gate passes. Whole windows, dropped presents and every outlier remain; clustered style order/fonts do not establish paired causal encoding rankings.

Every audio packet and produced/returned PCM frame reconciles, with zero producer backpressure/software starvation/rebuffer. Digital processing-age medians are13.9–15.4 ms, maxima32.4–43.3 ms. Startup28.05–30.13 seconds is measured from launch. Sampled host/simulation/renderer private memory3.46–4.16 GiB and CPU48.1–54.0% of20 logical cores are subsets: inspection confirms the collector omits the separate audio worker as well as Terminal. Earlier collector cohorts share this omission; do not use these subset figures as complete game-budget proof. Correct sampling before making total resource claims.

First precheck stops before startup because the invocation omits mandatory Wad; preserve its log and use a fresh corrected r2 path. The independent audit initially carries a Classic-only encoding assertion into character modes; correct the explicit NotApplicable expectation rather than changing runtime behavior. Raw CSV count/p99, ordered/due/queue commands, mode/source/UI accounting and PCM credits are independently audited. All recorded owned PIDs have exited before analysis; no concurrent study tests/exports/recordings/analyzers run during collection, with low-frequency status/source reads only. [Full receipt](../results/preview5-e3m6-all-style-pacing-20261002.json).

A diagnostic first Classic update mean18.18 ms plus snapshot publication7.12 ms does not isolate the complete command pipeline or scheduler cause. Next fix the resource-sampling omission and inspect publication/worker-count costs with exact-output controls; record dense effects separately. Preview.5 remains frozen; this evidence commit reaches2 after that release. Full Ultimate Doom scope remains active.

### 2026-10-02 — Correct audio ownership interpretation

The preceding separate-audio-process omission claim was wrong. It inferred process topology from Invoke-AudioWorker's filename without reading Start-DoomAudioRunspace. That function creates a local RunspaceFactory runspace and calls PowerShell.BeginInvoke inside the simulation process; it never starts a separate process. The sampler already includes audio/music CPU and memory through its Simulation role. Do not create another Audio process sample and double-count it. Terminal remains separately sampled/excluded from game totals; unsampled startup/tails and once-per-second peak limits remain.

Add ProcessId to audio/simulation reports and an explicit resource-scope statement to the collector. A native full-catalog420-command E3M6 diagnostic confirms audio PID19620 equals the simulation-report PID and sampled Simulation PID, retains both checkpoints and returns every submitted PCM frame. The final generic caller-runspace label also passes15 actual music/realtime save/load checks with equal audio/simulation PIDs. [Source/live identity receipt](../results/audio-process-ownership-20261002.json).

The original nine-run receipt is preserved locally and corrected in place with an explicit provenance note; all Runs/StyleSummaries/raw capture hashes remain unchanged. Current performance/roadmap prose is corrected, and the historical ledger entry is marked superseded. No buffer, mixer, sampler, game or renderer algorithm changes. This correction/evidence commit reaches3 after Preview.5. Next examine worker-count pressure and snapshot publication with bounded controls, while keeping failed primary gates and remaining full-release scope intact.

### 2026-10-02 — Dense effects recorded in all three modes

Three separate frozen-b99bdf8 WGC/NVENC recordings finish with scoped simulation-process loopback audio. All420 exact commands/two stored checkpoints repeat, all36 source hashes match, and all submitted PCM frames return: Classic602,280, Matrix606,060, AnsiArt594,720. Each retains63 scheduled audio events,15 peak sources, base/pickup/damage palette metadata, and player death. No map-completion claim or bot route tuning. Six full-window samples show the pistol/world/HUD and pickup notice; Classic keeps pixels, Matrix green glyphs, and AnsiArt color glyphs. Review uses2048x829 resized samples from3440x1392, not whole-movie/reference fidelity.

The53-check independent audit reconstructs aligned PCM from raw packet/QPC placements, checks explicit zero gaps, and verifies compressed video/timestamps survive merging. Startup lies outside loopback coverage; a retained near-tail gap spans1057/1141/1067 frames (24–26 ms). Do not call missing coverage measured silence or claim acoustic effect identity from nonzero digital samples. Software starvation/rebuffer/backpressure remain zero. Container video-duration rounding differences remain explicit in raw reports. [Recording receipt and hashes](../results/e3m6-effects-live-20261002.json).

All57 recorded game/Terminal PIDs are absent after collection. Recordings are separate from the nine clean measurements and do not qualify display FPS. This evidence commit reaches4 after Preview.5. Next pair the frozen16-worker primary against8 workers on the unchanged dense input, keeping full resolution/actors/tics and all failed gates.

### 2026-10-02 — Paired renderer worker-count tradeoff

Three clean Classic E3M6 ABBA cycles (16/8/8/16) finish on627a246 with the full30-track music catalog, unchanged420-command stress input, font5/Cascadia Mono/Pairs/Strips and full320x200/actors/tics. Eight-worker prechecks in every style match960,000 serial pixels and120 encoded strips across palette/invisibility fixtures. All twelve native runs retain420 exact commands, two stored endpoints, complete realtime credit/PCM accounting and zero audio backpressure/software starvation/rebuffer. Player death stays in the stress input; no map-completion claim. [Full paired receipt](../results/e3m6-worker-count-abba-20261002.json).

Eight workers improve cycle-median active tics10.47/13.71/12.12%, reduce p99 tic lateness70.33/69.22/71.64%, private memory37.28–39.17% and game CPU30.41–33.67%. Display-event medians decline8.26/9.99/8.03%. No run passes all numerical gates:16 workers advance27.831–30.857 tics/sec;8 advance32.220–33.737. Median critical worker spans rise from12.84 to16.93 ms with fewer stripes. Those QPC spans include scheduling; do not invent a scheduler/thermal cause or optical FPS gain. Startup varies rather than improving consistently. Audio/music remain included in simulation resource samples; Terminal and unsampled startup/tails/peaks retain their separate limits.

The first analysis wrapper falsely interprets a reused Windows PID as still owned and stops before timing analysis. Preserve its log; fresh r2 compares PID and sampled process start time, verifying all180 original identities have ended without killing unrelated processes. All raw CSV counts/p99, source manifests, ordered/due/queue commands, stage and resource groups are independently checked. Default/primary remains16;8 is a selectable tradeoff, not a release-gate fix. This evidence commit reaches5 after Preview.5. Continue the ignored exact-current snapshot endpoint trial; all-map/replay byte equality and bounded paired profiling precede any adoption.

### 2026-10-02 — Snapshot trials rejected; complete command stages attributed

Three ignored pure-PowerShell packing trials each pass170 complete endpoint byte comparisons across36 maps and the420-command dense replay, then2760 endpoint comparisons across60 profile slots (five states, three ABBA cycles each). All input checkpoints repeat. Retain all warmups separately and time20 calls per slot; source activation/byte comparison are outside the interval. These are isolated warm microbenchmarks, not live pacing or original-engine fidelity.

The [current-endpoint specialization](../results/snapshot-current-endpoint-trial-20261002.json) removes redundant position/height interpolation at fraction1 while preserving unwrapped camera angle. It saves a median1.566% (about0.08 ms/pair), too little to justify duplicating the full packing function. [Translation-table hoisting](../results/snapshot-table-lookups-trial-20261002.json) changes median pair time−0.012%, with mixed directions; [record-offset indexing](../results/snapshot-store-indices-trial-20261002.json) changes−0.241%, including regressions. None is adopted; production stays unchanged. Stop these trials rather than claiming tiny noisy arithmetic gains solve pacing.

The [full twelve-run command-stage audit](../results/e3m6-command-stage-audit-20261002.json) reveals the missing significant component: automap discovery, performed every world tic even while hidden, has median run means5.91 ms at16 workers and5.38 ms at8. Corresponding game updates are18.47/16.77 ms, snapshot publication7.31/6.70 ms, and adjacent update-end cycles33.21/29.73 ms. Intercommand residual means0.83/0.32 ms include ready/control/read/host availability and scheduling, rather than proving pure waiting. The420-tic full release gates remain unchanged; the419 adjacent-cycle diagnostic has its own explicit denominator. Presentation residual includes checkpoint work/observer overhead. QPC-derived starts are approximate and do not isolate OS scheduling.

This evidence commit reaches6 after Preview.5. Investigate discovery with the existing full mapped-line oracle, stationary/heading/map/save checks and captured input. Never remove hidden-map discovery or tune the stress input into a route. Full campaigns, independent moving-world fidelity, numerical pacing, physical/acoustic/DPI and second-hardware gates remain open.

### 2026-10-02 — Position-angle discovery trial remains unadopted

An ignored owned-bundle trial retains absolute vertex angles across calls when exact camera X/Y and vanilla map identity stay unchanged. It still performs visibility/BSP/occlusion for heading, sector and light changes; no visibility result is cached across changed views. The scope assumes static vanilla vertices, not dynamic geometry/MyHouse. All420 fresh E3M6 mapped-line states/two gameplay checkpoints agree with the prior indexed path. All36 starts/four headings and11 existing semantic invalidation cases pass, with pixels/validity/other flags checked. [Trial source and raw evidence](../results/discovery-position-angle-trial-20261002.json).

Only27/420 calls reuse positions. Isolated alternating method means are4.179 ms baseline and4.227 ms candidate (+1.16%), while medians are4.404/4.350 ms. This preliminary single stream is not a three-cycle ABBA performance claim and does not justify adoption. Stationary-view skipping is disabled on both timed paths; do not confuse this with the loaded native costs. Keep current source and profile the existing traversal. This evidence commit reaches7 after Preview.5; publish again at35 or more. All broader gates remain open.

### 2026-10-02 — Dense discovery method profile

The finite unpaced420-command baseline and subsequent owned-bundle instrumented discovery run preserve every full mapped-line bitset and both stored endpoints. The unchanged baseline mean/median is4.746/5.152 ms; instrumentation raises it to5.671/5.961 ms. No production instrumentation is adopted. Initial discovery is outside this diagnostic's per-command timing, while native release windows/gates stay unchanged. [Raw/source pins and method audit](../results/e3m6-discovery-method-profile-20261002.json).

Instrumented inclusive means identify IsPotentiallyVisible2.096 ms, DiscoverIndexedSeg1.851 ms, PointToAngleData1.761 ms (~95 calls/command), PointOnSide0.657 ms (~33 calls), and projection0.161 ms (~67 calls). These overlap and include substantial timers; never add them or substitute instrumented means for loaded performance. Solid/pass discovery wall methods are about0.101/0.078 ms here. Source inspection shows the numeric angle helper calls SlopeDiv, including DivRem/ref marshalling. Next investigate a bounded exact-integer slope calculation inside the discovery helper, retaining unsigned wrap, table selection, octant boundaries and int32-minimum fallback; baseline angle/error and mapped-state comparisons must precede adoption. This is a hypothesis for a trial, not an established bottleneck cause or speedup.

This evidence commit reaches8 after Preview.5. All Classic/Matrix/AnsiArt behavior and production algorithms remain unchanged by the rejected trials/profiler. Full Ultimate Doom campaign/fidelity/pacing/physical/acoustic/hardware gates remain active; continue without requesting a milestone approval.

### 2026-10-02 — Adopt exact numeric discovery slope calculation

Inline only the nonnegative slope calculation in Geometry.PointToAngleData.
The unsigned numerator wrap, denominator cutoff, floor quotient, table,
octants and int32-minimum fallback stay intact; general SlopeDiv and legacy
PointToAngle remain unchanged. The algorithm stays PowerShell with standard
Math.Truncate. Bounded double operands cannot round a noninteger quotient to
an integer in this domain; the receipt states the error argument and checks
20,509 quotients independently against DivRem.

The portable production check passes 20,900 prior-numeric angle comparisons,
including signed-coordinate wrap and boundaries, then three ABBA cycles.
Median256-call batches improve55.76/55.51/55.47%. The trial retains420 fresh
E3M6 mapped bitsets/two stored endpoints,144 headings over36 maps and11
semantic invalidations. Production additionally passes2,139 legacy angle
comparisons,61 moving full-renderer discovery views/two endpoints, eight
actual automap save/load/menu/new-game checks and15 audio/music save-worker
checks. All baseline/candidate full images, validity counters and other flags
remain covered by the retained map harness. The single alternating E3M6
discovery timing is diagnostic, not three-cycle native pacing evidence.
[Source pins and independent audit](../results/discovery-slope-production-20261002.json).

Retain two failures. The first method harness passes equality then fails in
timing-coordinate array construction; r2 parenthesizes products. The extra
7,118-command E1M3 run unnecessarily reused the stale historical route despite
the September27 ledger warning. Its7,118 fresh bitsets agree, but23 of24
stored checkpoints fail. All24 actual hashes exactly match the September29
unchanged-runtime report, including the final E1M3 state. No new gameplay
regression is isolated. Preserve the failure, exclude its timings and route
outcome from qualification, and do not tune inputs or regenerate expected
checkpoints. The earlier progress message's7,002 count was historical; this
trial actually compared7,118 fresh states.

This implementation/evidence commit reaches9 after Preview.5. Next measure
the committed build live with the unchanged full-catalog dense stress input,
primary16 workers and all styles, then record effects separately. Full
Ultimate Doom campaign/fidelity/pacing/physical/acoustic/hardware gates remain
open; no milestone approval is needed.

### 2026-10-02 — Committed slope change measured and recorded

Nine clean native runs on97ff8d9 retain all420 stress commands/two endpoints,
the full30-track catalog/audio, primary16 workers and320x200 output. Runtime
and launch hashes remain unchanged. Raw CSV display counts/p99, ordered/due
command accounting, PCM credits and all171 owned process/start identities are
independently checked after collection. Audio/music are included inside the
simulation process. No concurrent tests/exports/recordings/analyzers run during
collection; only low-frequency status reads.
[Native evidence](../results/discovery-slope-native-pacing-20261002.json).

Active rates are Classic32.136/32.822/32.721, Matrix31.200/30.747/32.034 and
AnsiArt30.305/31.920/32.002 tics/sec. Display events are42.483/41.619/42.298,
46.756/47.567/46.375 and43.398/42.237/43.257 per second. P99 tic lateness spans
813–1869ms. No full numerical gate passes. Median run-mean discovery is about
4.16ms in Classic/Matrix and4.17ms in AnsiArt. Historical earlier-build median
tic rates are lower, but these batches are unpaired and do not establish a
causal native speedup. Every window/outlier and player death remains; this is
stress evidence, not map completion or optical distinct-frame qualification.

Separate three-mode WGC/loopback recordings pass56 consistency checks on the
same committed gameplay fingerprint, including the adopted Geometry source.
Every command/checkpoint/audio frame reconciles; reviewed pickup/damage samples
retain pixels, green Matrix glyphs, color-art glyphs, HUD and notices.
[Recording receipt](../results/discovery-slope-effects-live-20261002.json).
The first Classic recorder receives q then exits with0xC0000005; game and audio
finish normally. Preserve its failed metadata/log/video. All19 recorded PIDs
are absent before one bounded retry of actual effects with the existing15sec
target hold instead of3sec. All three retries succeed, supporting that capture
setting without proving the native crash cause or changing runtime algorithms.
All57 retry game/Terminal PIDs are absent after collection.

Do not confuse56 passing consistency checks with uninterrupted captured audio.
Independent packet/QPC reconstruction retains startup outside coverage and
24.8–25.6ms post-game near-tail gaps. Matrix additionally has882 uncovered
frames (20ms) beginning1.114sec after the first gameplay write; adjacent raw
packets have Flags0 and no API-discontinuity marker. Game-side starvation,
rebuffer/backpressure remain zero, and all submitted/returned PCM reconciles.
This is missing loopback timestamp coverage, not measured acoustic silence or
an isolated mixer defect. Raw packets/timing and the pre-inspection receipt are
retained. Acoustic and physical A/V continuity remain unqualified.

This evidence commit reaches10 after Preview.5. Keep default16 workers and
Strips/Pairs. Continue a focused rendering-fidelity arithmetic review; full
Ultimate Doom campaign, independent moving-world/original-binary fidelity,
numerical pacing, human input/acoustic/DPI and second-hardware gates remain
active. Release again at35 or more commits since the prior public release.

### 2026-10-02 — Correct fractional sprite slope and unsigned wrap

Source review finds Get-FastSlopeDiv still assigning floating division to an
integer, which rounds, and shifting its numerator without uint32 overflow.
The exact engine SlopeDiv was corrected earlier, but this shared rendering
helper was missed. Reproduce a real bucket-selection consequence with the
synthetic fixed vector512 x212.125015 units and actor yaw0: exact slope848
selects rotation4, while the previous helper rounds to849 and selects5. The
uint32-wrap example and double-int-minimum fallback also diverge. This is a
mathematical product defect, not a stock-map human sighting.

Correct only the helper's operand normalization, denominator cutoff, wrapped
numerator and truncated floor. It remains PowerShell/standard .NET. Gameplay,
audio, tables, octants and sprite-selection convention stay unchanged. Add
the shared helper to actual recording source manifests; its omission from
earlier manifests is explicit, and older recordings retain their original pins.
[Before/after source and checks](../results/sprite-slope-correction-20261002.json).

The old exhaustive integer-table directions and393,408 boundary rotations
still pass the incorrect helper because their quotients are integral. The
expanded baseline test now retains a failing report: one int-min edge,
15,509/20,004 fractional/wrapped angles and9,677 rotations differ. Broad seeded
int32 inputs include values outside usual stock-map geometry; these counts
are not observed gameplay-frame frequencies. Corrected production has zero
mismatches across16,392 directions,393,408 boundary selections, seven int-min
edges,20,004 fractional/wrapped directions and100,000 angle round trips.
Twenty-one prepared-snapshot transport checks and actual16-worker all-style
palette/fuzz comparisons pass960,000 pixels and240 encoded strips against
serial rendering. The baseline failure and normalized-LF previous helper
from3534635 remain ignored/raw; no failed expectations are rewritten.

This implementation/evidence commit reaches11 after Preview.5. The preceding
native rates and live recordings belong to97ff8d9, before this correction.
Next record actual effects on the new committed build, then continue
independent moving-world fidelity and remaining full-release work. Do not
call helper math or serial/parallel equality original-framebuffer parity.

### 2026-10-02 — Corrected sprite build recorded in all modes

Three finite actual WGC/loopback runs on7cee1fc complete using the existing
15sec post-report target hold. All37 recording sources, now including the
shared SpriteProjection helper, match. All420 exact stress commands/two
checkpoints,63 scheduled audio events, palette metadata and complete packet/
credit/PCM shutdown accounting pass56 consistency checks. Submitted/returned
frames are574,560 Classic,577,080 Matrix and574,560 AnsiArt. All57 recorded
game/Terminal PIDs are absent after collection; no termination is needed.
[Current-build media/source receipt](../results/sprite-slope-effects-live-20261002.json).

Six reviewed full-window pickup/damage samples retain pixels, green Matrix
glyphs, color-art glyphs, pistol/imp/HUD and notices; Classic/AnsiArt show red
damage tint and Matrix remains green. Review uses2048x829 from3440x1392, not a
whole-movie or independent original-frame comparison. Independent packet/QPC
reconstruction finds no zero-filled interval overlapping gameplay writes in
these three runs. Startup is outside capture coverage and24.7–25.7ms near-tail
gaps occur after gameplay writes. The earlier97ff8d9 Matrix20ms active gap
remains retained separately: no audio algorithm changed, and these unpaired
successes do not isolate its cause or resolution. Acoustic continuity, physical
A/V latency and full-campaign audio remain unqualified.

This evidence commit reaches12 after Preview.5. Preserve the complete release
scope and35-commit release rule. Continue independent moving-world fidelity,
focused gameplay/session correctness and measured bottleneck work rather than
repeating this same short recording matrix without a new reason. Whole human
Episode1/Ultimate Doom campaign and physical/acoustic/DPI/second-hardware gates
remain open; existing tests and synthetic fixtures do not substitute for them.

### 2026-10-02 — Correct the wall inverse scale in the adopted reference

The pinned GPL C# reference divides unsigned integers in three wall paths.
The adapted PowerShell solid, portal and masked paths instead cast a floating
quotient to int, which rounds. Apply explicit truncation to those three
assignments; the production FastRenderer is unchanged. The new portable test
evaluates the actual source expressions against independent integer DivRem.
The retained old-source report fails 30,024 of 60,066 comparisons; corrected
source passes all 60,066 across 20,022 valid scale values per path.
[Source pins, failed baseline and controls](../results/reference-wall-inverse-scale-20261002.json).

The frozen E1M1 input-315 counterfactual ceiling sweep now disagrees with the
candidate at 19/11/410/4,170 indices for heights 0/6/34/68, versus the previous
10/7/410/4,166. HUD remains exact. The saved height-0 and height-68 candidate
RGB panels are unchanged while the reference panels change. This is a change
to the oracle, not a candidate improvement or regression. Preserve both raw
sweeps and images; do not rewrite historical mismatch counts. A fresh E3M6
420-command check retains all mapped-state hashes and both stress checkpoints.
The local C# source/license are pinned and no native production helper is added.

This correction/evidence commit reaches 13 after Preview.5. Next isolate the
candidate's wall texel stepping with a row-pattern fixture and test a bounded
PowerShell fixed-point implementation. Full original-image, campaign, pacing,
human input and acoustic qualification remain open. Release again at 35 commits.

### 2026-10-02 — Correct vertical wall sampling in the playable renderer

A numbered-row texture reproduces the candidate's continuous-distance sampling
error against the adopted reference column drawer. The retained old renderer
fails 293,120 of 7,029,760 texel/depth samples. Quantize projection scale and
texture anchors to 16.16, floor the unsigned inverse scale, and use that step
for solid, upper, lower and finite masked textures. Keep pegging, depth/order,
edge coverage and arbitrary-height wrapping. All algorithms remain PowerShell.
[Production checks, source pins and all trial results](../results/wall-vertical-sampling-20261002.json).

The implementation evaluates exact binary fractions instead of incrementing a
long accumulator. Signed fixed coordinates and the visible row range keep the
integer numerator far below double's exact-integer limit; division by 65,536
is exact. It matches the first correct accumulator trial across 960,000 pixels
and depth entries in 15 E1M1/E1M2/E3M6 views. Cache anchors only within a segment,
and reuse a front-parallel step only after a visible textured band needs it.
Angled walls still calculate their own step per column. No persistent cache,
native helper, omitted actors or reduced resolution is introduced.

Production passes 28,119,040 authored samples across heights 64/96/128/256,
including negative offsets, clipped starts and finite masked rows/holes. At
height 128 the oracle calls the adopted reference DrawColumn; other heights
use independent Floor/DivRem wrapping. Twenty existing masked-wall depth/order
checks pass. Actual 16-worker Classic, Matrix and AnsiArt output matches its
serial reference over 960,000 pixels and 240 encoded strips with palette/fuzz
fixtures. All 36 maps load, execute 35 idle tics and render twice. These checks
qualify their narrow conditions, not navigation or original-image parity.

Real-map comparisons are mixed and retained. E1M2 scene mismatch counts change
9,111/3,822/6,468/6,577/9,013 to 5,847/3,823/6,301/4,616/5,223 at headings
0/37/90/180/270. E3M6 changes 5,049/4,166/7,312/4,570/4,026 to
5,049/4,163/7,408/4,493/4,016. The reference pixels are identical within each
pair and HUD is exact. The moving-ceiling fixture now has 12/7/410/4,167 scene
mismatches at heights 0/6/34/68. The analytic geometry and masked-post edges
still differ from the reference; do not claim monotonic or full fidelity.

Nine finite serial datasets each retain 60 calls in three ABBA cycles at five
headings, with initial calls/outliers included and no concurrent study work.
The accumulator, wrapping-mask and eager-preparation alternatives are retained.
The adopted lazy version's whole-run mean is lower by 2.80% in E1M2 and 1.81%
in E3M6, but initial baseline calls are asymmetric. Later cycle means are still
slower, including 5.61%/4.47% in dense E3M6. Adopt for arithmetic correctness;
no native pacing gain or full gate pass is inferred. Keep all cost evidence.

Retain three setup failures: comma-string angle binding before the static test;
the old cost harness resolving a module-private helper outside its module, with
zero timed calls; and a masked fixture whose supposed backdrop was too short.
Correct the fixture sector before baseline/production comparison. The receipt
auditor also initially expects 21 existing order checks; the actual 20 all pass,
and its failing source/count diagnosis is retained. No failed product result is
rewritten. The pair harness now supports explicit candidates/ABBA and performs
snapshot setup inside each renderer's module.

This implementation/evidence commit reaches 14 after Preview.5. Record actual
effects on the committed renderer next, then continue the remaining release
gates. The whole human campaign, independent original moving frames, numerical
pacing, physical/acoustic/DPI and second-hardware qualification remain open.

### 2026-10-02 — Wall correction recorded in Classic, Matrix and color art

Three finite WGC/loopback recordings complete on committed eb5e551 with the
unchanged full 30-track catalog, primary 16 workers and Strips/Pairs. All 37
source pins agree, including the new FastRenderer. Each executes all 420 stress
commands and both checkpoints; player death remains. Independent input, credits,
PCM reconstruction and media checks pass 56 conditions. Submitted/returned
frames are 575,820 Classic, 580,860 Matrix and 628,740 AnsiArt. All 57 recorded
game/Terminal PIDs are absent after collection; no termination is needed.
[Raw-media hashes, source pins and coverage](../results/wall-vertical-effects-live-20261002.json).

Six reviewed full-window samples preserve pickup notices, pistol/imp/HUD,
Classic pixels, green Matrix glyphs and color-art glyphs. Classic/AnsiArt damage
samples show red tint; Matrix remains green. Review displays 2048x829 from the
original 3440x1392 frames, not exact optical write identity or a whole-movie
review. The narrow row-pattern tests establish sampling arithmetic; these
recordings do not independently qualify reference wall projection.

Independent QPC/packet inspection finds no uncovered interval overlapping the
first-to-last gameplay-write window in these runs. Startup is outside loopback
coverage and 15.1–25.9 ms near-tail gaps occur after gameplay writes. Retain the
earlier Matrix 20 ms active gap and all previous recorder failures. No mixer
algorithm changed; unpaired successes do not isolate the prior gap's cause or
prove acoustic continuity, physical A/V latency or full-campaign audio. These
recordings add capture load and do not update clean pacing claims.

This evidence commit reaches 15 after Preview.5. Continue useful release work
without repeating this short recording matrix absent a new change. Whole human
Episode 1/Ultimate Doom qualification, independent moving original frames,
numerical pacing and physical/acoustic/DPI/second-hardware gates remain open.
Cut the next public release at 35 commits since the prior release.

### 2026-10-02 — Attribute remaining wall projection differences

Read the adopted renderer's actual visible-wall Scale1/ScaleStep history after
the frozen E1M1 input-315, ceiling-68 fixture. An ignored candidate trace records
visible textured bands while preserving all 64,000 ordinary pixels and depth
entries. Match segment/column keys without changing coverage or the input route.
Of 656 paired band samples, 618 have different scale and 273 have different
horizontal texture columns reconstructed from the pinned reference formula.
The reference contains 45 visible ranges and 1,548 segment/column keys.
[Attribution controls, failures and source pins](../results/wall-projection-attribution-20261002.json).

Injecting only actual reference scale changes disagreement from 4,167 to 3,855;
injecting only reconstructed wall-U changes it to 2,302; both yield 1,951.
HUD stays exact. These interact, so reductions cannot be added. Scale comes
from actual recorded reference fields; U is derived with its distance, angle,
tangent and offset formula rather than independently logged column calls.
Reference endpoint-angle equality and the tangent's angle mask are checked.
This identifies horizontal sampling as the stronger next bounded implementation
trial. It leaves 1,951 differences and does not establish original-image parity.

The first ignored diagnostic mistakenly resolves the trace function as its
ordinary control through dynamic-module exports and fails before creating the
control's trace fields. Retain that error and source, then module-qualify both
renders and compare pixels/depth. Align the derived-U angle mask with the actual
reference; the corrected diagnostic still yields 1,951. Production is unchanged,
and no performance or campaign qualification follows from these counterfactual
texture overrides. Preserve every raw run and the prior helper versions.

This evidence commit reaches 16 after Preview.5. Next implement and test bounded
PowerShell wall-U quantization, with scalar/scene controls and cost measurement
before adoption. Continue all full-release gates; release again at 35 commits.

### 2026-10-02 — Adopt horizontal wall texture quantization

Preserve original WAD segment angles in a uint32 array and additive v7 render
asset metadata. The visible-segment/column wall-U formula stays PowerShell and
reuses existing sine/angle tables plus transported fine tangent data. Coverage,
depth, lighting and vertical sampling retain their existing behavior. Authored
contexts without angles keep analytic sampling. The pinned GPL reference and
license attribution are retained. [Full receipt](../results/wall-horizontal-sampling-20261002.json).

The first worker run fails because its class-based preparation requires Trig,
Fixed, Angle and Geometry, which separate workers do not load. Keep the failed
Classic log and exact source. Numeric functions remove that dependency and match
all 20,038 returned class-based parameter cases. Eleven extreme coordinate cases
fail with the same underlying OverflowException. The first harness falsely
distinguishes outer method/function wrapper types; retain that report/source,
inspect the exception chains, then compare their innermost causes explicitly.
Do not count matching errors as rendered scenes.

The signed wrapped texture column passes 20,023 independent byte-oracle cases.
The frozen trace agrees in 656 derived reference columns/320 camera lookups;
production matches the class trial in 960,000 pixels and depth entries. Preserve
20 masked-order checks, 23 asset checks, seven million height-96 vertical samples,
36-map idle smoke and all-style actual workers: 960,000 pixels/240 encoded strips.
Ten static reference views improve; the frozen ceiling sweep changes from
12/7/410/4,167 to 12/7/344/2,270, with exact HUD. Remaining image differences and
the adapted reference's independent qualification stay open.

Six finite 60-call serial ABBA datasets retain every initial call and outlier.
Class-based alternatives have later-cycle costs up to 16.66%; the final numeric
version's later cycles increase 0.18–1.56%. Whole means include initial-call
asymmetry; different batches cannot establish a causal optimization gain. Adopt
for demonstrated sampling fidelity and keep native pacing claims unchanged.

This implementation commit reaches 17 after Preview.5. Record actual effects
on the committed source next, then continue useful campaign/fidelity/performance
work. Whole human Episode 1/Ultimate Doom, original-frame, native pacing and
physical/acoustic/DPI/second-hardware gates remain open. Release at 35 commits.

### 2026-10-02 — Review wall-U effects and session reloads

Three actual committed-277edaf recordings preserve Classic, Matrix and color art,
all 420 stress commands/two stored endpoints, 37 unchanged source pins and the
full 30-track catalog. Reviewed six pickup/damage samples show the world, pistol,
HUD and notices; Classic/color art show damage tint and Matrix stays green.
The tool scales original 3440×1392 frames to 2048×829 for inspection. This reviews
selected effects, not an entire movie or exact optical write identity.
[Recording receipt](../results/wall-u-effects-live-20261002.json).

All 56 independent digital checks pass, including reconstructed PCM and credits.
Submitted/returned audio frames are 561,960/567,000/621,180 by style; each run has
63 events and 15 peak sources. All 57 recorded game/Terminal PIDs are absent.
Independent timeline inspection finds no uncovered interval inside gameplay
writes. Startup lacks loopback coverage; 23.7/25.2/24.8 ms near-tail gaps follow
the last writes by over 400 ms. Keep the older Matrix active gap and recorder
failures. No mixer algorithm changed or acoustic continuity claim follows.

On the same source, actual sixteen-process pools also pass 60 session checks:
1,344,000 worker-image pixels/336 encoded strips and 768,000 additional fresh
resource pixels. Screen/menu/automap and E1M2/E2M1/E3M1/E1M2 reloads match serial
controls. Worker PIDs persist through reloads, expected resource body reuse/misses
remain correct, private scratch stays separate and foreign content is rejected.
Overlapping/duplicate operations and corrupt owned asset rejection pass; all 48
recorded worker PIDs are absent afterward. This qualifies transport and reloads,
not human controls, save continuation, route completion or clean timing.
[Session receipt](../results/wall-u-session-reload-20261002.json).

This evidence commit reaches 18 after Preview.5. Measure current-source native
pacing separately, with no concurrent qualification/export/recording work. Keep
all campaign, original-frame and physical/acoustic/hardware gates open; release
again at 35 commits since the preceding release.

### 2026-10-02 — Measure current wall-U native pacing

Nine sequential clean captures on committed e5c12f9 / implementation 277edaf
retain three repeats in each mode, default sixteen workers, full source image,
all 3,780 stress commands/18 endpoints, audio and thirty-track catalog. No study
qualification, analysis, exports or recordings run during collection. Independent
checks reconcile raw display counts/p99, unchanged source/input, audio credits,
resource groups and all 171 ended PID/start identities.
[Native receipt and full raw windows](../results/wall-u-native-pacing-20261002.json).

All nine fail the full numerical pacing gates. Median active tics/sec are
31.983/32.262/31.534 for Classic/Matrix/color art; median display transitions/sec
are 37.363/39.603/41.562. Tic p99 lateness spans 1,025–1,576 ms. Zero software
audio starvation/rebuffer and complete PCM credits establish bounded accounting,
not acoustics. Every command and player death remain; no completion claim follows.

Startup spans 26.77–30.60 sec, sampled game private totals 3.46–4.22 GiB and
CPU 47.9–55.9% of twenty-core capacity. These include simulation-process audio
and exclude separately sampled Terminal. Sampling misses some startup/tail and
peak behavior. Historical current/previous display medians are lower, but those
batches are unpaired and cannot isolate a causal wall cost or system effect.
Do not turn the isolated serial sampling result into a native performance claim.

This evidence commit reaches 19 after Preview.5. Investigate retained stage
timings/lateness for a bounded product improvement, while keeping defaults,
thresholds, all prior failures and full qualification gates. Release at 35 commits.

### 2026-10-02 — Directly dispatch built-in state actions

Allocation profiling localized much of the dense E3M6 update work to thinker
state changes: the 420-tic headless replay allocated 5,685 MiB, with 4,549 MiB
in `ThinkerRun` and a sampled estimate of 3,707 MiB attributable to
`Mobj.SetState`. These are profiled attribution estimates, not an isolated
allocation proof. Two earlier alternatives were rejected: skipping empty
interpolation calls worsened later-quarter timings by as much as 11.69%; routing
all action kinds through `ExecuteMobjAction` retained replay checkpoints but
raised allocations about 1% with mixed or slower timings.

The adopted PowerShell route maps each of the 52 built-in `MobjActions` names to
the same-named method, using a case-sensitive switch. Ultimate Doom's loaded
state table references all 52 and none are missing. Scriptblock state actions
still use `ExecuteMobjAction`; unknown names retain `PSMethod.Invoke`. Campaign
transitions (69), boss progression (97), movement (27), game actions (9), menu
and screen fixtures (171), save/menu/input (26), save reconstruction and
validation (34), simulation-worker saves (12), and route-coverage (6) checks
pass. The saved E1M1 state at tic 700 reconstructs and continues identically to
tic 840; worker load/save/new-game/replay behavior also passes.
[Dispatch and regression evidence](../results/mobj-action-dispatch-20261002.json).

Across two baseline and two candidate 420-command E3M6 runs, pooled per-tic
headless `Game.Update` median falls 10.02% (17.43 to 15.68 ms), mean falls
7.82% (20.29 to 18.70 ms), and p95 falls 5.66%. The pooled p99 remains 67.17 ms,
above the frozen 57.2 ms threshold. Allocations rise 1.01% (5,685 to 5,743 MiB).
All 421 tic-boundary player/state and numeric render hashes match the baseline,
including the two stored replay checkpoints. These captures are not randomized
ABBA native-host runs; they include no workers, terminal output, audio or
presentation and do not establish release pacing or acoustic equivalence.

This implementation and evidence commit reaches 20 after Preview.5. Measure the
committed candidate in the full native configuration across all three styles;
retain every miss and continue the human campaign, original-frame, audio,
physical-input and second-display gates. Release again at 35 commits.

The committed dispatcher also passes the candidate-source 36-map smoke: each
map loads, runs 35 idle tics and renders two full serial frames. This is startup,
bounded simulation and rasterization coverage only; it does not establish player
navigation or completion. The first native retest was blocked before launch by
the already-running user Windows Terminal, which the isolated PresentMon
harness correctly refuses to attribute as a fresh game window. No existing
Terminal was closed. The [smoke receipt](../results/campaign-smoke-dispatch-20261002.json)
is retained; clean native performance remains open pending an isolated display
session.

The all-map smoke extends the committed-source regression set without converting
it into a route claim. This follow-up evidence commit reaches 21 after Preview.5.
Resume clean native capture once Windows Terminal is available for exclusive
measurement, while continuing the documented Episode 1 human route and other
independent release gates. Release at 35 commits.

The committed candidate also retains exact actual process-worker rendering in
Classic, Matrix and AnsiArt. Five E1M1 headings per mode compare 320,000 pixels
each against the serial renderer with zero differences using sixteen uneven
strips; Matrix and AnsiArt each add 80 exact character-strip checks. This is
serial/worker and encoder parity, not original-game pixel equivalence. See the
[mode comparison receipt](../results/mobj-action-render-modes-20261002.json).
The source-pinned dispatch evidence now includes this run. The map-smoke and
mode-parity receipts were combined in the same follow-up evidence commit, which
is 21 after Preview.5. Native pacing and a complete human Episode 1 remain the
next high-value gates.

This documentation correction is commit22 after Preview.5. Resume the full
native pacing matrix when an exclusive Terminal measurement session is available;
the next public release remains due at35 commits.

### 2026-10-02 — Refresh the Episode 1 human handoff

The one-session playthrough guide now targets the tested local source candidate
`5682bc4` directly, with fresh save/input/report/settings paths, the existing
Ultimate Doom IWAD and prepared Episode 1 music catalog. Its route remains
E1M1–E1M3, the E1M9 secret return to E1M4, E1M4–E1M8 and the finale. This is
preparation for one human route, not route qualification; no game window was
launched and the existing Terminal stays untouched. `Start-Doom.ps1`, the local
catalog and PowerShell 7.6.6 are present. This handoff commit reaches23 after
Preview.5. The native retest still needs an exclusive Terminal session; the
human playthrough remains open.

The dense 420-command candidate replay now attributes simulation work using
the direct state-action router. Thinkers average 15.28 ms/tic under profiling;
state actions average 12.01 ms inclusive, with 7,892 `CheckSight` calls and
8.20 ms inclusive. Those slices overlap and include instrumentation overhead,
so they direct investigation but do not establish a performance gain. Both
stored replay checkpoints match. [Profile receipt](../results/actor-hotspots-dispatch-20261002.json).
The action-dispatch test again passes all six checks across 52 actions. This
profiler and evidence commit reaches24 after Preview.5; continue into the
measured thinker/visibility paths while the clean native pacing and full human
campaign gates remain open.

A second diagnostic pass counts sight-query traversal work without changing
the runtime. The same 420 commands matched both checkpoints and recorded 119,780
BSP-node visits, 65,838 segment iterations and 4,765 intercept calculations.
The added counters affect timing, so keep this receipt for attribution only and
do not compare its milliseconds with the earlier profile.
[Traversal evidence](../results/sight-traversal-dispatch-20261002.json).
This instrumentation commit brings the count to25 after Preview.5. Continue
with a source-preserving traversal alternative and exact replay comparison.

The disposable iterative near-side-first BSP walk matches recursive reference
hashes across all420 input tics and current renderer snapshots. Four process
timing runs in ABBA order show pooled `Game.Update` mean −6.1%, median −12.0%
and p95 −5.7%; p99 rises1.7% and remains over the 57.2 ms limit. This is
simulation-only evidence for integration testing, not a native pacing claim.
[All-tic/timing receipt](../results/visibility-iterative-dispatch-20261002.json).
The test harness and this evidence commit reach26 after Preview.5. Trial the
same walk in production PowerShell, then rerun broad state and rendering tests.

Production commit `c3d0d0c` replaces recursive BSP calls with the tested
PowerShell near-first stack walk. Its 420-tic current-render/state hashes match
the committed trial at every tic; the recursive reference also retains its two
checkpoint matches. All 36 maps pass 35 idle tics and two serial frames each;
campaign, boss, movement, actions, save/load, 50,200 visibility bounds, 50,000
intercepts, 50,121 division cases and 27 offline audio mixer checks pass. Classic,
Matrix and AnsiArt each retain five-view/320,000-pixel parity through 16 actual
worker strips. [Integration evidence](../results/visibility-iterative-integration-20261002.json).
No new live effect recording or completed human route is claimed, and native
p99 remains open. This test/documentation commit reaches28 after Preview.5;
resume the isolated three-style pacing and one-session Episode 1 route when the
exclusive display resource is available. Cut a release at35 commits.

The next profiling-only pass separates the 52 direct state actions and hitscan
passes, then counts blockmap traversals and intercept-list sizes on the same
420-tic dense E3M6 replay. Both stored checkpoints match. `Look` and `Chase`
remain the largest inclusive action buckets. The quadratic intercept scan sees
at most 23 entries in this trace (only 9 traversals fall in the 17–32 bucket),
so it is retained without a speculative ordering rewrite. Counts include
profiler instrumentation and do not measure native pacing or uninstrumented
speed. [Attribution receipt](../results/hitscan-path-profile-iterative-20261002.json).
The profiler/evidence/documentation commit reaches 29 after Preview.5. Native
capture, human Episode 1 completion and current-source live effect review remain
open; release is due again at 35 commits.

A headless current-source run refreshes live effect output evidence without
opening a Terminal window. It replays 420 commands, matches both endpoints,
schedules 63 effects, returns all 594,720 submitted frames and captures 19.99
seconds of process PCM with zero reported discontinuities. A first receipt had
a check-count mismatch despite all six recorded checks passing; it is preserved
and the corrected seven-check rerun passes. This verifies digital output, not
acoustics or video. [Receipt](../results/live-effect-headless-20261002-r2.json).
The next commit reaches 30 after Preview.5; keep the human route, acoustic
listening, display and fidelity gates open, and release again at 35.

A fresh fixed-state current-renderer audit measures E1M2 across 16 equal 20-pixel
stripes and 80 observations per stripe. Wall/BSP work remains the largest phase
(5.72 ms median); plane fill is1.91 ms median. The 160–180 center stripe is the
most expensive in this one view (15.96 ms total median), while edge stripes are
substantially cheaper. The harness measures stripes sequentially, so it does not
establish concurrent-worker pacing. [Pinned profile](../results/renderer-phase-profile-current-wall-u-20261002.json).
The profile/documentation commit reaches31 after Preview.5; isolate wall work
counts next, and release again at35 or more.

The profiling-only follow-up counts BSP and segment traversal, projected wall
columns, fixed-point wall-U setup, wall bands, occlusion/deferred-mask work and
plane pixels in a generated `FastRenderer.ps1` copy. Its final E1M2 Classic
frame exactly matches the prior uninstrumented frame hash. Full-view work is
212 BSP entries, 294 segment visits, 2,744 wall-column attempts, 43 wall-U
parameter calls, 938 column-U calculations, 410 texel-step calculations,
14,438 wall-texture rows and 39,322 plane pixels. Across stripes, wall time
tracks band tests and per-column setup more closely than texture-row count;
those correlations are one fixed view and the band counter is proportional to
column attempts. Two harness-only startup errors (string interpolation and
source-relative imports after relocating the generated copy) were fixed before
the final sampling run; both corrections are noted in the receipt. The counts
support a bounded active-band trial, not an assumed speedup. Instrumented
timings are discarded. See the [counter receipt](../results/renderer-work-counters-current-wall-u-20261002.json).
Count reaches32 after Preview.5. The human campaign, clean live pacing,
independent renderer fidelity and acoustic review remain open; release is due
again at35 commits.

An ABBA E1M2 fixed-view trial preselects eligible wall-texture bands in a
generated PowerShell renderer variant. Two baseline and two variant runs retain
640 measured stripe samples each, match all four full-frame hashes and all 64
per-stripe hashes, and reduce pooled total-render median2.88% and wall median
5.03%. Total p99 falls4.20%; wall p99 falls6.42%. Relative managed allocation
median is effectively flat (−0.11%). Classic, Matrix and AnsiArt each match
the production worker path at five E1M1 headings, 320,000 pixels per mode, with
zero differences. A failed comparison launch from `local/` was a relative-import
path issue; a temporary copy beside renderer dependencies passed and was
removed. The trial is source-pinned [here](../results/wall-band-preselection-trial-20261002.json).
These are bounded headless results, not native pacing. The modest win moves to
production qualification; count reaches33 after Preview.5, with two commits
until the next release. The human campaign and remaining release gates stay open.

Production integration commit `05556ee` now preselects wall-texture bands once
per projected segment in PowerShell. The Steam IWAD passes all36 map start
smokes, each with35 idle tics and two serial frame headings. Classic, Matrix
and AnsiArt each retain320,000 exact serial/16-worker pixels over five E1M1
headings. Focused checks pass20 masked-wall order cases, 20,023 column-wrap
cases, 7,029,760 wall vertical-sampling comparisons, 20,049 wall-U comparisons
(11 matched reference/candidate errors), and122 fuzz checks. All focused
renderer source pins match the integrated file. This remains map smoke and
internal worker parity, not route completion or original-framebuffer proof.
[Source-pinned integration evidence](../results/wall-band-renderer-integration-20261002.json).
Count reaches34 after Preview.5. Prepare the next cumulative community package
at35 commits; the full Episode 1 route and original full-release gates stay open.

### Preview.6 package qualification — October 2, 2026

The clean `0145d75` Preview.6 source archive was extracted and audited: all569
manifest payload hashes, the 1,819,451-byte archive checksum, and the adjacent
checksum file match; no game or research assets are bundled. The extracted
launch check passes with the local licensed IWAD. All36 maps pass35 idle tics,
and Classic, Matrix and AnsiArt each match serial output across five views and
16 worker strips (320,000 pixels, zero differences). This is package and
internal parity evidence only, not human route completion, live pacing or
external framebuffer qualification. The [package receipt](../results/preview6-package-validation-20261002.json)
pins the archive and test reports. Release threshold was reached at35 commits
after Preview.5; [Preview.6 is published](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.6).
The downloaded release assets match the tested ZIP and checksum file; the
[publication receipt](../results/preview6-publication-20261002.json) pins both.
