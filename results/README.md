# First-batch measurements

All JSON measurements were recorded on 2026-09-10. Absolute runtime paths identify the actual executable and should not be mistaken for a requirement to use that path on another machine.

| File | Contents |
| --- | --- |
| `environment.json` | Hardware/software inventory, Defender status, power plan. Not hardware performance measurements. |
| `encoding.json` | 16 baseline encoding cases: sizes, palettes, patterns, ANSI/Sixel. Three warmups, twelve samples. |
| `ansi-optimization.json` | Original versus bulk-string ANSI, identical output checked, sixteen samples. |
| `sixel-optimization.json` | RLE versus bulk-mask Sixel, twelve samples; includes output sizes. |
| `terminal-replay.json` | 32 pre-encoded synthetic cases, four seconds each, requested 165 writes/second. |
| `terminal-live.json` | 12 live synthetic cases, five seconds each, component timings and completed writes. |
| `doom-scene.json` | External PowerShell E1M1 renderer and our encoders, sixteen headless samples across eight headings. |
| `doom-replay.json` | 12 real-scene replay cases using cached encodings. |
| `doom-live.json` | Headless repeats plus 12 four-second live geometry/encode/write cases. No game simulation. |
| `doom-live-post-install.json` | Same 12 live-scene cases after the user reported Steam installation completion; includes slower observations and substantial low-resolution variability. |
| `post-install-context.json` | User-reported installation state, one pre-run CPU snapshot, and harness hash for that comparison. Not a continuous idle-state measurement. |
| `terminal-probe.json` | Post-run encoding/grid probe in the same Terminal profile; not retrospective process telemetry. |
| `terminal-utf8-check.json` | Raw UTF-8 half-block cursor-advance probe, comparing inherited and explicit UTF-8 encoding. |
| `pre-utf8-fix/` | Superseded original terminal runs and smoke test, retained to document the console code-page defect. |

`WriteSamplesMs` measures blocking console write calls. Reports with live generation include component measurements as described in their `Meaning` field and protocol. None measures monitor-visible FPS. Raw timing arrays are retained; do not replace ranges with a single favorable repetition.

`local/` contains ignored machine inventory, external source, benchmark plans, encoded caches, PNGs, and the downloaded PresentMon tool. Commercial WADs remain in the Steam installation. The main [findings](../docs/findings-2026-09-10.md) state the measurement limitations.

Current terminal performance reports explicitly record `OutputCodePage: 65001`. Initial reports without that precondition are superseded, as explained in `pre-utf8-fix/README.md`. Headless results were unaffected.

## Parallel-renderer follow-up

| File | Contents |
| --- | --- |
| `parallel-scene.json` | Initial runspace partition experiment, including pixel mismatches and the byte-enumeration defect. |
| `parallel-scene-corrected.json` | Partition-independent interpolation; correct pixels against the adapted serial renderer, still before the byte-array return fix. |
| `parallel-scene-bytearray.json` | Runspace recheck after fixing byte-array pipeline enumeration. |
| `process-scene.json` | Initial separate-process experiment, before the array-return fix. |
| `process-scene-bytearray.json` | Corrected 1/2/4/8-process headless construction and transfer measurements. |
| `process-scene-more-workers.json` | 12/16-process headless comparison. |
| `process-scene-live-truecolor.json` | Initial 12-second continuously rotating live cases, uncapped and coarse-paced. |
| `process-scene-live-truecolor-30s.json` | Longer full-rotation truecolor cases; includes discovery of coarse pacing jitter. |
| `process-scene-live-precise.json` | 30-second full-color case with precise pacing, interval stats, deadline misses, and worker memory use. |
| `process-scene-live-ansi256.json` | Corresponding approximate-color comparison. |

See [the follow-up findings](../docs/sixty-fps-investigation.md). These are scene-rendering tests with no gameplay. Correctness comparisons use the adapted serial renderer, not a claim of exact upstream or reference-Doom fidelity. Older JSON files retain the behavior and defects of their original runs even though the scripts have since been fixed.

## Camera transforms lead

| File | Contents |
| --- | --- |
| `camera-transforms.json` | Four-method coordinate-only comparison: scalar relative/affine math and direct Matrix3x2 transforms with cached/new Vector2 inputs. |
| `camera-transforms-typed.json` | Five-method follow-up adding explicitly typed matrix and result locals. |

Both reports transform 470 E1M1 vertices, with 64 warmups and 64 samples of 16 batches per method. Raw samples are milliseconds per complete map-coordinate transformation, not rendered frames. The Matrix module itself was not executed or timed. See the [ledger](../docs/ledger.md#2026-09-10--user-supplied-matrix-transforms-lead) for sources, numerical checks, limitations, and reproduction.
