# Terminal write granularity investigation

September 19, 2026. Full Ultimate Doom release requirements remain unchanged.

The latest Classic E1M2 capture has 4,533 level-state frames. Mean host output time is 12.3991 ms (median 11.2826, p95 21.1499), compared with 1.3888 ms submission and 1.4522 ms collection. These phases identify output as a measurement target; they do not prove where Terminal itself spends that time.

The selectable `-TerminalOutput Strips|Batch` path preserves the complete ANSI stream. Strips sends the synchronized-update start, optional clear, worker strips, optional diagnostics and update end separately. Batch copies those bytes into a reusable buffer and writes only its used length once. Both flush once. Standard .NET copying and stream APIs perform transport; all rendering and encoding stay PowerShell. Strips remains the default pending evidence.

`scripts/Test-TerminalOutput.ps1` compares both modes against the original direct-write sequence. The successful second receipt covers 72 byte-exact comparisons across Classic, Matrix and AnsiArt katakana, seven uneven strips, viewport offsets, clear/status combinations, and large/small/coherent frames sharing buffers. Its first attempt incorrectly retained a 168-row HUD boundary in a 40-row synthetic image. That rejected fixture/report is retained; the corrected fixture uses a valid 32-row HUD. No performance inference comes from memory streams. The host also avoids a PowerShell empty-array pipeline expression that would turn its optional clear buffer into null.

## Declared live comparison

Run the independently qualified 3,233-command E1M2 route through intermission into E1M3, with Classic, 16 workers, the same maximized font/viewport and seven-track audio catalog. Record every run with the existing owned-window/process-audio capture. Order: Strips first, Batch first, Batch second, Strips second. Do not change game/capture sources or run other study workloads during this sequence. Audit each run before proceeding; stop for a real error. Include startup and transitions in retained reports, and report same-world gaps as a separately labeled subset. These are captured end-to-end trials, not isolated terminal microbenchmarks or displayed-FPS certification.

Reproduce each trial from the repository root in PowerShell 7 using fresh names:

```powershell
./scripts/Invoke-TerminalOutputTrial.ps1 -Mode Strips -Name output-strips-first
./scripts/Invoke-TerminalOutputTrial.ps1 -Mode Batch -Name output-batch-first
./scripts/Invoke-TerminalOutputTrial.ps1 -Mode Batch -Name output-batch-second
./scripts/Invoke-TerminalOutputTrial.ps1 -Mode Strips -Name output-strips-second
```

Compare simulation rate, completed image writes, host output-time distribution, consecutive console-completion gaps and audio queue observations. Retain movie/source hashes, all route checkpoints and audio-return checks. Byte preservation is necessary but does not guarantee identical presentation pacing. Adopt a default only if the repeated comparison supports it; preserve inconclusive or negative findings.

## Completed comparison

All four runs finish normally and independently pass 58 campaign/capture checks: every command, all 13 selected-state checkpoints, intermission/E1M3 inventory carryover, matching synthesized PCM and all 4,073,580 audio frames returned. Full movies decode. The [comparison receipt](../results/terminal-output-four-trials.json) passes 148 checks, including shared source/workload/font/viewport/capture settings, stable viewport geometry, and a separate endpoint-identity check of the mean write gap. Each receipt retains raw media/report hashes. No game/capture source changed between runs.

| Run order | Mode | Simulation tics/sec | Completed images/sec | Level output mean ms | Same-world gap p95 ms | Audio queue-empty observations |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | Strips | 34.694 | 39.437 | 18.987 | 34.377 | 7 |
| 2 | Batch | 34.986 | 38.524 | 8.273 | 40.874 | 6 |
| 3 | Batch | 34.985 | 57.168 | 6.650 | 23.780 | 2 |
| 4 | Strips | 34.982 | 55.237 | 11.332 | 24.503 | 3 |

Batch reduces observed host output time in both adjacent comparisons, but end-to-end throughput changes direction: about 2.3% lower in the first pair and 3.5% higher in the second. Both modes vary substantially between repeats. The next render overlaps output, so a shorter output phase is not an additive reduction in the total frame interval. These trials do not establish a repeatable whole-game speedup. Keep **Strips as default** and retain Batch as an explicitly selectable experiment.

Each image averages about 614–618 kB of encoded bytes. Batch uses a 1 MiB reusable buffer and one managed Stream.Write call per image; Strips averages just over eighteen such calls because each level also clears once. These counters are managed API calls, not counts of underlying kernel writes. Reducing redundant color instructions is a concrete next hypothesis, but must preserve exact displayed colors and earn its own end-to-end evidence. No encoder algorithm changed in this comparison.

The captures have no reported API discontinuity packets, but all contain a small interior alignment fill, and every run has software queue-empty observations. This does not certify uninterrupted sound at the speakers. The test machine was an active desktop; background workload, focus, CPU scheduling, thermals and compositor behavior were not controlled or independently logged. The observed temporal variation is not assigned a cause. The results do not certify 60 distinct displayed images/sec.

A later [live Classic E1M1 host measurement](performance.md) uses the current
source and retains separate completion-interval, worker, and terminal-write
statistics. It likewise lacks monitor-presentation telemetry because the
installed PresentMon CLI could not start its ETW trace under the current
account's permissions.

At 60 seconds in each original movie, the reviewed frames show centered Classic gameplay with the HUD and no visible external occlusion. Different startup durations mean those samples are not the same game state and are not pixel-equivalence evidence. The existing large margins and approximately 1600×900 physical image/aspect issue remain. Raw movies, PCM and extracted review PNGs remain in ignored `local/recordings`; portable receipts are backed up in Git.

## Reuse ANSI strip assembly buffers (2026-09-27)

Both Classic truecolor strip encoders previously allocated a string array for
every worker strip on every image, then concatenated it to a string before
UTF-8 conversion. The 16-worker 320×200 layout creates 100 character rows per
strip; for each 20-column strip the removed array held 2,100 string references.
New-CodecContext now owns a StringBuilder, and ConvertTo-AnsiStrip and
ConvertTo-AnsiColorStateStrip clear and reuse it. Each renderer process has
its own codec context. SGR selection, glyphs, cursor placement, indexed pixels,
and output bytes are produced by the same PowerShell loops; UTF-8 conversion
still returns an owned byte array to the process transport.

The source-derived reference-slot estimate is 268,800 bytes per 320×200 image
across sixteen strips on a 64-bit process, excluding array headers, cursor
strings, the concatenated output string, and the returned byte arrays. It is
an allocation estimate from the former array-length formula, not a measured
GC or frame-rate result.

The strict color test passes all 13 cases, including six actual E1M1/E1M3
raster views; its independent decoder verifies every output RGB pixel, odd
dimensions, uneven strips, offsets, and foreground/background-only
transitions. Classic Pairs and ColorState each pass exact serial/16-process
partition output across five views (320,000 pixels and 80 encoded strips per
mode). These establish encoder correctness and worker parity, not a measured
allocation or throughput improvement. The [receipt](../results/ansi-strip-buffer-reuse-summary-20260927.json)
links the raw reports and source hashes.

The first strict-test invocation overlapped another existing test that rebuilds
local/engine-bundle.ps1; the shared file was busy. The attempt is retained in
the receipt, and the strict test passed when rerun sequentially. This was a
test-build artifact collision, not a game or encoder failure.
