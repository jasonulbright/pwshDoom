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
