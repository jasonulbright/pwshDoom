# Investigation ledger

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
