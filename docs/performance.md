# Live host pacing evidence

This page separates terminal writes from actual monitor presentation. A high
write count is useful, but only ETW presentation telemetry can establish how
many distinct frames Windows displayed.

## Current-source E1M1 run — September 26, 2026

The asset-free game was launched in a fresh maximized Windows Terminal window
with PowerShell 7.6.5, Classic block output, 16 render workers, sound effects,
and the user-supplied Episode 1 music catalog. A deterministic scripted input
ran for 28.0 seconds on E1M1. It advanced 979 simulation tics, completed 1,671
terminal updates, and ended at the requested duration with 100 health and zero
kills. This is a short E1M1 runtime measurement, not a campaign route or a
human playthrough.

| Measurement | Result |
| --- | ---: |
| Simulation rate | 34.959 tics/sec |
| Completed terminal updates | 59.670 updates/sec |
| Consecutive terminal completion gap, p50 / p95 / p99 / max | 16.645 / 23.087 / 30.514 / 95.861 ms |
| Render-to-terminal-write latency, median / p95 / max | 23.090 / 34.902 / 118.385 ms |
| Slowest worker render per frame, p50 / p95 / p99 / max | 5.384 / 16.319 / 20.258 / 37.407 ms |
| Terminal write time, p50 / p95 / p99 / max | 5.315 / 14.032 / 23.437 / 89.559 ms |
| Encoded terminal output | 856,620,591 bytes across 1,671 frames; about 513 kB/frame |

The window reported 688 columns by 151 rows; pwshDoom centered its 320×100
cell image at column 184, row 25, with no viewport pauses. These measurements
come from the game host's counters and `QueryPerformanceCounter` timestamps.
They are terminal completion and write measurements, not displayed-frame
measurements.

Sound effects were enabled (63 sound events, up to two voices). Music selected
`D_E1M1` and submitted 1,233,540 PCM frames in 979 packets. The mixer reported
no clipped samples, stale packets, audio backpressure, device error, or cleanup
error, and the device closed. It also recorded one queue-starvation observation
after packet 978; this telemetry cannot determine whether the speakers had an
audible gap. No acoustic review or video recording was made for this run.

PresentMon 2.6.0 was installed and its console executable was callable, but the
trace failed with `access denied`: PresentMon requires an elevated process or
membership in the Windows `Performance Log Users` group. No privilege or group
settings were changed. Therefore this run does not prove 60 displayed frames
per second. The machine-readable [receipt](../results/live-e1m1-classic-host-20260926.json)
contains source-file and IWAD/catalog hashes, detailed percentiles, and the
ignored raw host report hash.

The next pacing evidence must include moving geometry and combat, repeated
paired runs, a measured display path, and audio queue behavior across at least
one map transition. The current 59.67 terminal updates/sec is a useful baseline,
not release certification.

## World-sprite clipping cost — September 27, 2026

To check the E1M1 sprite-occlusion correction against its immediate pre-fix
source, `Measure-RendererPair.ps1` renders both versions from the same
35-tic map-start state at headings 0, 37, 90, 180 and 270 degrees. Six
alternating-order rounds retain all 30 render calls per version and map,
including each first call. Context creation and snapshot setup are outside the
timer. Both versions run in separate PowerShell modules so the baseline does
not accidentally call candidate private helpers. The workload is serial
320×200 rendering under PowerShell 7.6.5; it excludes live simulation,
parallel workers, encoding, terminal output, audio and display presentation.

Baseline source is commit `703a1f7`; the clipped, scratch-reusing candidate is
`193c386`. Times are milliseconds per full render:

| Map | Baseline median / p95 | Candidate median / p95 |
| --- | ---: | ---: |
| E1M1 | 52.50 / 95.36 | 52.04 / 95.70 |
| E1M3 | 51.42 / 104.71 | 52.46 / 95.72 |
| E1M4 | 42.59 / 77.90 | 45.40 / 69.92 |

The medians are mixed: E1M1 is 0.9% lower, E1M3 is 2.0% higher, and E1M4 is
6.6% higher in this sample. The p95 is nearly unchanged on E1M1 and lower on
E1M3/E1M4. Mean times move differently because long-tail outliers remain
large. This is a measured fidelity cost with variable timing, not an overall
speedup or a 35-tic/60-display claim. The raw source-pinned reports are
[E1M1](../results/sprite-clip-final-performance-e1m1-20260927.json),
[E1M3](../results/sprite-clip-final-performance-e1m3-20260927.json), and
[E1M4](../results/sprite-clip-final-performance-e1m4-20260927.json).
