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
