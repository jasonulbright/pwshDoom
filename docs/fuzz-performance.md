# Fuzz drawing cost

September 19, 2026. This follows the [invisibility/Spectre implementation](rendering-fidelity.md). The effect, resolution, actors, depth rules and per-column animation phase remain unchanged.

## Diagnosis

The retained close-up Spectre recordings average 23–31 image writes/sec. Their per-frame maximum worker render duration averages 35.77 ms in Classic and 25.59/25.57 ms in Matrix/AnsiArt. Encoding averages 3.51/3.04/4.70 ms, and host output 13.88/10.67/9.90 ms. These stages overlap and cannot be added to derive a frame rate; independent maxima need not name the same worker. See `results/fuzz-recorded-stage-analysis.json`.

`scripts/Measure-FuzzRenderer.ps1` loads the existing explicit test save and samples game tics 0, 35, 90, 210 and 350. It profiles sixteen 20-column strips sequentially in one process. This separates geometry, actor, weapon and HUD work without claiming to reproduce actual parallel-worker contention. The initial report is `results/fuzz-profile-baseline.json`. Geometry is the largest phase and actors the next largest.

## Change and controlled comparison

The original fuzz loop calculates the source row using division, floor and a clamp for every visible pixel. That row is the same for every column of a given sprite. The optimized helper calculates it once per row, then indexes a small integer array. It also retains the offset table and texture-column base in local variables and returns early for an empty clipped rectangle. It preserves in-place neighbour sampling and phase advancement through covered pixels.

The previous helper is preserved byte-for-byte as `scripts/fixtures/FuzzReference.ps1`. The paired experiment alternates old/new order across six repetitions at each of five fixed states. All 960 strip samples are retained, including cold calls. All 30 paired complete indexed images **and depth buffers** match exactly.

| Fixture tic | Old actor mean/strip | New actor mean/strip | Old total mean/strip | New total mean/strip |
| --- | ---: | ---: | ---: | ---: |
| 0 | 2.894 ms | 0.991 ms | 12.351 ms | 8.933 ms |
| 35 | 3.992 ms | 0.784 ms | 11.197 ms | 7.195 ms |
| 90 | 3.786 ms | 0.775 ms | 11.665 ms | 7.884 ms |
| 210 | 4.427 ms | 0.920 ms | 11.668 ms | 8.080 ms |
| 350 | 4.569 ms | 0.952 ms | 12.054 ms | 8.476 ms |

The unchanged geometry phase still varies, especially in the cold first state. The actor reduction is present in all five state means. This supports the local optimization; it is not a measured whole-game or displayed-FPS gain. Raw timings are in `results/fuzz-row-cache-comparison.json`; arithmetic summaries and the input hash are in `results/fuzz-row-cache-summary.json`.

The existing 119 focused fuzz checks still pass, including the adopted neighbour/color operation, clipping, masks, flip, scale, depth, blinking, precedence, real flag transport and overlapping actors. Actual seven-worker tests also pass for all three styles: 320,000 pixel comparisons and 35 encoded strips per style. Reports use the `fuzz-row-cache` name. No codec changed.

Reproduce with the existing local test save and user-owned IWAD:

```powershell
./scripts/Measure-FuzzRenderer.ps1 -Output ./results/my-fuzz-comparison.json `
  -ReferenceFuzz ./scripts/fixtures/FuzzReference.ps1 -Repeats 6
./scripts/Test-FuzzRendering.ps1 -Output ./results/my-fuzz-correctness.json
```

The save comes from `scripts/New-FuzzRecordingFixture.ps1`, with its output replay and save root passed explicitly to the profiler when different from the documented defaults. It grants a shortened invisibility timer, gives the test player extra health and spawns a Spectre. It remains a visual/performance fixture, not campaign completion evidence. Whole-host recordings are a separate validation step.

## Actual terminal validation

Three sequential recordings of the optimized helper each pass all 34 capture checks and all 17 independent replay checkpoints. Each completes all 350 commands, returns all 441,000 sound frames with no canceled tails, preserves its pinned sources/media, decodes completely, and closes its owned game window and processes. No concurrent study benchmark ran during capture. Receipts are `results/fuzz-row-cache-{classic,matrix,ansiart}-first-recorded.json` and the corresponding `-timing.json` files.

| Style | Game tics/sec | Image writes/sec | Same-world p95 gap | Same-world maximum |
| --- | ---: | ---: | ---: | ---: |
| Classic | 34.889 | 46.452 | 31.630 ms | 520.745 ms |
| Matrix | 34.895 | 41.177 | 31.362 ms | 563.280 ms |
| AnsiArt | 34.882 | 45.346 | 29.411 ms | 549.313 ms |

These averages exceed the earlier recorded fixture's 23–31 writes/sec, but those historical sessions were not interleaved controlled trials. The local paired experiment establishes the effect-loop improvement; the new movies establish continued whole-host operation and its observed pacing. They do not establish a universal speedup, 60 displayed frames/sec, or a release-ready worst-case bound. Save-loading gaps remain in the all-gap series, with maxima around 2.9–3.0 seconds.

Audio queue-empty observations are 1/4/3 for Classic/Matrix/AnsiArt. Capture alignment includes 1,143/1,177/1,134 interior inserted audio frames. Acoustic continuity is not established. Actual sampled frames show the invisible weapon before expiry and the opaque pistol afterward in all styles; Matrix remains dark. Six reviewed image hashes are retained in `results/fuzz-row-cache-visual-review.json`.

Original audiovisual recordings remain at `local/recordings/fuzz-row-cache-{classic,matrix,ansiart}-first-av.mp4`. The same shortened-power/extra-health save fixture is used without changing its commands or checkpoints. This optimization adds no campaign completion evidence. Remaining geometry cost, palette presentation, broader visual fidelity, campaign routes, audio and final release pacing remain open.
