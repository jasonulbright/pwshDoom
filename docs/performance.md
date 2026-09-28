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

## Current-source E1M1 PresentMon replay — September 27, 2026

The current game source was measured with the installed PresentMon 2.6 service
through a maximized Classic Terminal window at 6-point font, PowerShell 7.6.6,
16 render workers, the Steam Ultimate Doom IWAD, and the existing 1,560-command
`results/e1m1-route.json` input. The harness isolated a new Terminal process;
the capture returned 2,526 frame events and passed timestamp/interval
cross-checks to better than `1.5e-14` ms.

PresentMon observed 2,464 display transitions across its 51.624-second window,
or **47.73 transitions/sec**. Median / p95 display interval was 18.18 / 30.31
ms; 71 intervals exceeded 33.33 ms and 15 exceeded 50 ms. Six of 2,470
submitted frames were marked dropped. Median / p95 present-to-display delay
was 6.04 / 11.46 ms; median / p95 GPU-busy time was 2.31 / 4.34 ms. These
are Terminal presentation measurements, not a one-to-one count of distinct
Doom images on the monitor.

The game advanced 1,560 simulation tics and 2,476 completed updates. Its active
clock reports 34.977 tics/sec and 55.514 updates/sec over 44.601 seconds; the
wall interval was 51.721 seconds because it included a 7.119-second asset
reload at tic 1247. The saved input then ended as `ReplayEnd` while the report
was still on E1M1, so this is **performance evidence only**, not a completed
route. The same existing E1M1 route driver independently passed on current
source in 1,560 commands; that does not convert this older input stream into a
current-source route result. No engine defect was established by the replay
outcome.

This was one run, without audio, and it is not paired with the earlier windowed
PresentMon run. The output and source runtime differ, so no performance change
is attributed. The machine-readable
[receipt](../results/presentmon-current-source-replay-20260927.json) records
the exact source, workload, dropped-frame counts and local raw-artifact hashes;
the 35-tic/60-display gate remains open.

## Two-minute audio-loaded headless E1M1 run — September 28, 2026

At commit `40924e7db9ac7171fd150c5e0de26f8b6512a9a5`, PowerShell 7.6.6 ran
`Invoke-Doom.ps1` for 120 seconds in headless mode with the installed Ultimate
Doom IWAD, the local 30-loop campaign catalog, sound enabled, and 16 rendering
workers. It advanced 4,199 tics (34.991 tics/sec) and completed 5,791 host
updates (48.258/sec). Because the session was headless, these updates are not
Windows Terminal presentation or display-frame measurements.

The actual waveOut worker selected D_E1M1 throughout its 96-second loop period
and mixed 5,290,740 audio frames across 4,199 packets. It submitted and
returned every frame, reported no clipping or worker/cleanup errors, and closed
the device. The packet queue peaked at three. Mixer time was 0.522 ms median,
1.174 ms p95, 1.592 ms p99, and 46.929 ms maximum; one block exceeded the
28.571 ms packet interval. The sole queue-empty/rebuffer observation was after
the final packet during shutdown; there was no mid-run queue-empty observation
or recovery. Packet age at submission was 80.491 ms p95 and 97.303 ms maximum.
The loop crossed its prepared seam, but this is one idle-map run, not a human
route, audible-quality test, campaign-transition test, or continuous visual
load measurement.

The [portable receipt](../results/music-host-e1m1-loop-seam-20260928.json)
includes the PCM digest and source hashes. The complete session report stays in
ignored `local/`; no screen recording was made. The 35-tic/60-display gate
remains open.

## E3M6 worker-count load comparison — September 28, 2026

Three no-input HMP sessions started on E3M6 with PowerShell 7.6.6, the stock
Steam Ultimate Doom IWAD, the local 30-track catalog, sound enabled, and
headless output. The 16-worker run lasted 120 seconds; the 8- and 12-worker
runs lasted 30 seconds each. All used source commit `50d6190`. Host updates
below are completed render jobs, not terminal writes or monitor presentations.

| Workers | Duration | Simulation tics/sec | Completed host updates/sec | Frame latency median / p95 | Worker working set | Queue starvation / rebuffer | Audio frames submitted / returned |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | 120.001 s | 24.641 | 34.075 | 28.27 / 49.47 ms | 4.61 GiB | 280 / 280 | 3,728,340 / 3,728,340 |
| 8 | 30.002 s | 28.432 | 30.665 | 30.12 / 56.07 ms | 2.32 GiB | 4 / 4 | 1,077,300 / 1,077,300 |
| 12 | 30.001 s | 26.466 | 31.799 | 29.53 / 57.80 ms | 3.43 GiB | 25 / 25 | 1,002,960 / 1,002,960 |

The 8-worker sample has the highest simulation rate and fewest queue-empty
observations, while 16 workers complete the most render jobs per second. The
12-worker sample lies between them on render throughput but below eight on
simulation rate. The unequal durations and one trial per configuration make
these exploratory comparisons; they do not justify changing the default.
Every session returned all submitted audio frames, had zero unconsumed packets
and clipped samples, and closed the device without a worker or cleanup error.
Queue-starvation/rebuffer counters still expose serious continuity risk on
E3M6. They do not tell us whether a listener heard a dropout. None of these
headless measurements establishes a 35-tic/60-display result.

A separate fixed-state PowerShell profile divides the E3M6 view into the same
16 twenty-column stripes as production workers and measures them sequentially.
Across 192 measured stripe renders, the total median/p95 was 14.92/17.71 ms;
the actor phase was 9.75/12.22 ms and geometry was 4.07/5.22 ms. Individual
stripe medians ranged from 11.27 to 17.85 ms. The actor scan runs in every
worker, so this profile identifies repeated work worth investigating; it is
not a concurrent worker or whole-host timing. See the [stripe profile](../results/renderer-stripes-e3m6-start-16w-current-20260928.json)
and [portable session comparison](../results/music-host-e3m6-worker-scaling-20260928.json).

An experiment moved the actor scale division after the frustum test. Its
fixed-state pixel hashes matched all 16 current-source stripes exactly, but
the actor/total medians were 9.73/14.77 ms for the candidate and 9.75/14.92 ms
after reverting it—within timing variation, with no demonstrated speedup. The
edit was reverted. The [candidate profile](../results/renderer-stripes-e3m6-projection-candidate-20260928.json)
preserves its distinct source hash and is not current game code. The complete
raw host reports are retained in ignored `local/`; no recording was made.
