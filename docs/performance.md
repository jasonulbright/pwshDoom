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

## PowerShell runtime comparison on E3M6 — September 28, 2026

To check whether the 24.641-tic/sec 7.6.6 result reproduced, I alternated two
30-second runs on PowerShell 7.6.5 with two on 7.6.6, then ran a 120-second
7.6.5 session. All used the same 16-worker, headless, no-input HMP E3M6
workload, Steam IWAD, 30-entry music catalog, and sound-enabled waveOut path.
The 30-second order was 7.6.5, 7.6.6, 7.6.6, 7.6.5. The two current-source
7.6.6 samples were run explicitly with that executable; every report records
its PowerShell version. Current and earlier Git source pins have identical
`src/` trees; only package/measurement/partition-test scripts differ. This
helps isolate the runtime version, but does not control all system scheduling
and load variation.

| Runtime and duration | Simulation tics/sec | Completed host updates/sec | Frame latency median / p95 | Audio submitted / returned | Rebuffer observations; shutdown state |
| --- | ---: | ---: | ---: | ---: | --- |
| 7.6.5, two 30-second runs | 33.497 / 34.932 | 35.163 / 37.298 | 27.07 / 49.01 ms; 25.76 / 45.88 ms | 1,268,820 / 1,268,820; 1,320,480 / 1,315,440 | 4; 1. The latter ended with one unconsumed packet and a 5,040-frame canceled-tail upper bound. Device closed without errors. |
| 7.6.6, two 30-second runs | 27.632 / 28.365 | 33.232 / 34.332 | 28.98 / 49.91 ms; 28.67 / 46.43 ms | 1,047,060 / 1,047,060; 1,073,520 / 1,073,520 | 13 / 7; both returned all frames and closed without errors. |
| 7.6.5, 120-second run | 34.366 | 34.891 | 27.93 / 45.65 ms | 5,198,760 / 5,198,760 | 5; zero unconsumed packets, device closed without errors. |
| Earlier 7.6.6, 120-second run | 24.641 | 34.075 | 28.27 / 49.47 ms | 3,728,340 / 3,728,340 | 280; zero unconsumed packets, device closed without errors. |

Both current 7.6.6 short repeats were below both 7.6.5 repeats. The later
7.6.5 long run also held near 34.4 tics/sec, unlike the earlier 7.6.6 long
run. This is a runtime-associated difference in these trials, not proof that
the 7.6.6 update caused a regression; background load and other machine state
were not fully controlled. Queue/rebuffer telemetry counts device polling
events and cannot establish that a listener heard a gap. All runs are
headless: completed host updates are not Terminal writes or monitor
presentations. No renderer or worker default was changed.

The [portable comparison receipt](../results/music-host-e3m6-runtime-comparison-20260928.json)
pins the workload and raw-report hashes. The complete per-session reports stay
under ignored `local/`. These measurements narrow the performance question;
they do not pass the 35-tic/60-display gate or qualify continuous audible
music.

## Share Spectre actor ordering across renderer workers — September 28, 2026

The legacy renderer sorted all actors far-to-near in every process whenever a
Spectre was present. The interpolated NumericV3 snapshot now performs that
stable PowerShell sort once and marks the prepared actor order in its existing
reserved header slot; render workers skip only their duplicate sort. Direct
object snapshots keep the old renderer fallback. This preserves the intended
fuzz compositing order while removing repeated work from the actor phase.

The paired fixed-state profile uses E3M6, HMP, the installed Steam IWAD, 311
actors including four Spectres, and sixteen 20-column stripes. Each mode has
two profiles with 24 measured frames apiece after five warmups. The stripes
run sequentially in one PowerShell process, and the comparison adds snapshot
preparation CPU to the summed stripe-render CPU. Median summed render CPU
falls from 229.11 ms to 210.40 ms; including snapshot preparation, the median
falls from 235.92 ms to 213.55 ms (9.48%). Combined p95 falls 7.28%. Median
preparation rises from 0.23 ms to 3.54 ms, while actor-phase CPU summed across
stripes falls 8.50%. The full 64,000-pixel output hashes match exactly.

This isolates CPU work in one fixed state. The stripes are not concurrent
worker wall time; no live host, terminal write, audio load, PresentMon sample,
or displayed-frame rate was measured. The result does not establish a 60 FPS
gain. The [portable paired receipt](../results/renderer-shared-fuzz-order-20260928.json)
pins source and raw-profile hashes; the [snapshot checks](../results/snapshot-actor-order-20260928.json),
[fuzz checks](../results/fuzz-rendering-actor-order-20260928.json), and
16-worker [Classic](../results/render-fuzz-actor-order-classic-20260928.json),
[Matrix](../results/render-fuzz-actor-order-matrix-20260928.json), and
[AnsiArt](../results/render-fuzz-actor-order-ansiart-20260928.json) receipts
retain correctness results.

## Current-source worker-count follow-up — September 28, 2026

After adding actor-to-stripe culling, I compared worker counts on the current
branch (`32400a8`) using PowerShell 7.6.5 on Windows 11 Pro with an Intel Core
Ultra 7 265K (20 logical processors). Each run was a single 30-second,
no-input, headless HMP E3M6 session with sound and the local Ultimate Doom music
catalog enabled. The order was 8, 12, then 16 workers; the runs were not paired
or randomized.

| Workers | Simulation tics/sec | Completed host updates/sec | Frame latency median / p95 | Worker working set | Audio submitted / returned | Starvation / rebuffer observations |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 8 | 34.70 | 29.30 | 37.19 / 57.29 ms | 2.17 GiB | 1,314,180 / 1,312,920 | 0 / 0; one 1,260-frame shutdown-tail upper bound |
| 12 | 31.90 | 30.60 | 37.70 / 52.49 ms | 3.31 GiB | 1,208,340 / 1,208,340 | 5 / 5 |
| 16 | 33.70 | 30.30 | 37.63 / 59.18 ms | 4.14 GiB | 1,275,120 / 1,275,120 | 8 / 8 |

In separate fixed-state E3M6 runs through the actual process pool, dispatch
wall medians/p95 were 55.60/61.89 ms at four workers, 44.22/49.71 ms at
eight, 43.39/49.49 ms at twelve, and 45.93/55.47 ms at sixteen. These runs
used four warmups and 24 measured frames; they exclude simulation, audio,
terminal output, and worker startup. Twelve workers had the lowest median in
this single pass, while sixteen reduced the busiest worker's median render
time the most. That does not establish a default-setting winner.

Twelve-worker partition tests on E1M1 match the serial renderer for five views
in each of Classic, Matrix/Katakana, and AnsiArt/Katakana: 320,000 pixels per
style with zero differences and matching encoded strip checks. These are
internal renderer equivalence tests, not original-Doom parity. Keep the
16-worker default: the host comparison is one ordered sample per count, and
all configurations remain far below 60 completed updates/sec. A repeated,
randomized visible-Terminal comparison is still needed before changing the
default or making a display-pacing claim.

The compact [comparison receipt](../results/worker-count-host-render-comparison-20260928.json)
records runtime, machine, workload, source hashes, summary values, and SHA-256
identifiers for the full reports, which remain in ignored `local/` storage.
Headless completed updates are not Terminal writes or monitor presentations;
audio queue counters are not an acoustic review. These E3M6 sessions are not
map-completion evidence.

## Project actors only to renderer stripes that can see them — September 28, 2026

Each interpolated world snapshot now gets a render-only NumericV4 extension
with one PowerShell-computed stripe-visibility mask per actor. The simulation
still publishes NumericV3; the host applies Doom's fixed-point actor
projection and rotated patch width once, and each process skips an actor only
when its patch cannot overlap that process's columns. Missing sprite geometry
uses a conservative all-worker mask. In the tested E3M6 view, 4,274 of 4,480
possible actor-worker pairs were skipped (95.4%); the extra mask payload was
2,240 bytes for 280 actors.

The focused measurement uses the actual 16-process renderer pool at one fixed
HMP E3M6 state on PowerShell 7.6.5, with four warmup and 24 measured frames per
run. It includes endpoint interpolation, host submission, process rendering,
blocking completion, and encoded-strip retrieval. Worker startup is excluded;
simulation, audio, terminal output, and monitor presentation are not measured.
The second pair reverses run order:

| Pair order | No-mask dispatch median / p95 | Mask dispatch median / p95 | Submit median, no-mask / mask | Peak worker render median, no-mask / mask |
| --- | ---: | ---: | ---: | ---: |
| No-mask, then mask | 51.34 / 65.56 ms | 42.67 / 52.68 ms | 1.13 / 9.04 ms | 38.14 / 17.91 ms |
| Mask, then no-mask | 50.24 / 57.85 ms | 43.07 / 48.83 ms | 1.19 / 8.85 ms | 37.65 / 18.84 ms |

Both pairs return identical encoded-strip SHA-256 values. The host mask pass
adds about 7.7–7.9 ms to median submission, while reducing the slowest worker's
median render time; measured end-to-end dispatch medians fall 16.9% and 14.3%
in the two runs. The result is promising but leaves E3M6 dispatch at 43 ms
median, well above a 16.67 ms 60 Hz frame interval. It is not a 60 FPS
qualification or a live-game pacing measurement. The normal launcher also
completes a three-second, no-audio headless E3M6 run on this source with 83
simulation tics and 94 host render updates; those updates are not displayed
frames ([receipt](../results/actor-worker-mask-launcher-bootstrap-20260928.json)).

The [measurement tool](../scripts/Measure-RenderWorkerMaskImpact.ps1),
[first no-mask run](../results/renderer-worker-mask-impact-e3m6-baseline-final-20260928.json),
[first mask run](../results/renderer-worker-mask-impact-e3m6-candidate-final-20260928.json),
[reverse-order mask run](../results/renderer-worker-mask-impact-e3m6-candidate-reverse-final-20260928.json),
and [reverse-order no-mask run](../results/renderer-worker-mask-impact-e3m6-baseline-reverse-final-20260928.json)
pin the workload, output hashes, and source hashes.

## Rejected actor-mask bookkeeping shortcuts — September 28, 2026

Two PowerShell-only alternatives tried to reduce the host cost of assigning
worker visibility masks. Both preserved output, but neither showed a
repeatable improvement in full renderer-pool dispatch, so neither remains in
the game source.

The pre-encoding prototype generated masks from the interpolated numeric
array before serializing it. This avoids a V3 byte-pack/decode/repack cycle,
but mostly moved time from submission into interpolation. With 24-frame pairs,
dispatch medians were 47.09 ms for baseline versus 46.08 ms for candidate, then
44.78 versus 43.24 ms in reversed order. In the 96-frame reversed pair,
candidate was slower: 41.10 versus 38.47 ms. Output hashes matched in all
pairs; mixed end-to-end results did not justify keeping the extra path.

The worker-span prototype replaced an all-worker scan with a table mapping the
320 output columns to worker indexes and a contiguous bit-span calculation.
Each of the six E3M6 runs assigned the same 206 of 4,480 possible actor-worker
pairs and emitted the same encoded output hash. At 24 frames, one scan-first
pair was dominated by worker scheduling noise (48.80 ms scan versus 75.60 ms
lookup; lookup p95 193.28 ms); in the reversed pair, lookup was 46.89 ms and
scan 44.14 ms. In the 96-frame lookup-first pair, lookup was 41.29 ms and scan
36.83 ms. The longer run and reversed short pair do not support a speed claim.

The lookup prototype also passed five-view E1M1 serial comparisons at 12
workers in Classic, Matrix/Katakana, and AnsiArt/Katakana, with zero pixel
differences and matching encoded strips. A 16-worker Classic fuzz fixture
also matched across all five views. These checks establish partition
correctness for the trial; they do not change map completion status. Both
prototypes were reverted, leaving the measured all-worker scan intact. The
[portable trial receipt](../results/actor-mask-bookkeeping-trials-20260928.json)
indexes exact run parameters, source patches, and raw-report hashes in ignored
`local/` storage. These experiments are not displayed-frame measurements.

## Five-second candidate sound-and-music host startup — September 28, 2026

The candidate pinned at source commit `32400a8` ran for 5.00 seconds on PowerShell
7.6.5 with 16 renderer workers, sound effects, and the prepared eleven-track
Episode 1 catalog. It completed 174 simulation tics and 226 headless render
updates before exiting at the requested duration, with no host error. The
single short sample reports 34.79 simulation tics/sec and 45.18 headless host
updates/sec; combined worker working set was 4,155,396,096 bytes. These update
counts are not Terminal writes or displayed frames. The run verifies startup
with the qualified catalog but does not measure audio packet completion,
audible output, campaign continuity, loaded pacing, or the 35-tic/60-display
goal. The [candidate receipt](../results/episode1-current-human-candidate-20260928.json)
indexes the raw host report and its hash under ignored `local/` storage.

## Rejected wall texture-step precomputation — September 28, 2026

I replaced the per-pixel division in wall texture sampling with a per-column precomputed scale and multiplication, with a fallback at integer boundaries. The fallback retained exact output: the baseline and candidate agreed over 320,000 Classic E1M1 pixels and 960,000 E3M6 pixels across Classic, Matrix/Katakana, and AnsiArt/Katakana fuzz views.

Four alternating rounds at five headings measured 20 serial frames per version per map. On E1M1 the candidate median was 66.96 ms versus 67.75 ms baseline, but its p95 was 119.85 ms versus 108.77 ms, and paired candidate timings won only 5 of 20 comparisons. On E3M6 the candidate median was 86.61 ms versus 89.02 ms, while paired median change was effectively zero and candidate won 10 of 20. These small, inconsistent gains do not justify a source change; the optimization was reverted. This measures serial software-renderer calls only, not simulation, workers, terminal output, or displayed frame rate.

Raw alternating-pair reports and the source patch are retained in ignored `local/renderer-vstep-incremental-ab-e3m6-20260928/`. Both reports pin the Steam IWAD SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`, baseline renderer `5E701091DDB6706727631BC93E200C553D7C81DDF391F028264DD7353A5FDCCF`, and candidate renderer `99025DD76D1BE4F1936D7C3FEA5DDF9686B034698EAD6870493CB01FCA06F7DA`. E1M1 report SHA-256: `0FAC4A78CC7D8D49EEB2601E72FD3EC789423C871FC65C3F8EBDA0A2A0F421DF`; E3M6 report SHA-256: `C3EFEE387E226263274774C651CFB1B8CB4FF146AACB7A6F8FE798BCEC509F16`; source patch SHA-256: `23824E50C25F103126CB6C2CE4A3EF7493F134660F9A01D294D340EE79B4463F`.

## Pack per-map BSP geometry — September 28, 2026

`New-FastRenderContext` previously built a PowerShell hashtable for every BSP
node and seg, including separate child-bound arrays. Those immutable map
records are now stored as flat typed PowerShell arrays: doubles for segment
coordinates/length/offset and node coordinates/bounds, and integers for sector,
side, flag, and child indexes. The asset transport writes and reconstructs the
same arrays using cache format v7. The BSP traversal and rasterization remain
PowerShell; the new layout changes storage and indexing only.

The source-pinned E3M6 profile renders 16 worker-equivalent stripes sequentially
in one process. Its baseline median/p95 total stripe time was 9.01/13.00 ms;
the candidate measured 8.34/10.71 ms, and a repeat measured 7.66/10.84 ms.
Geometry-phase median fell from 4.32 to 3.93 ms in the first candidate run.
All runs produced the same full-frame SHA-256. The short, ordered baseline and
candidate runs are directional evidence, not randomized paired timing; asset
size and worker memory were not measured.

The candidate also passes 36 Ultimate Doom map load/idle/render smokes, five
serial-equivalent views in each of Classic, Matrix/Katakana, and
AnsiArt/Katakana with sixteen processes (320,000 compared pixels and zero
differences per style), and a real E1M1-to-E1M2 asset reload without restarting
workers. These checks do not establish full campaign completion or 35-tic/60-
display pacing. Raw report paths and SHA-256 values are indexed in the compact
[profile receipt](../results/packed-map-geometry-profile-20260928.json).

## Skip repeated prepared actor-order scans — September 28, 2026

Interpolated worker packets already mark actor arrays sorted when they contain
a Spectre. The renderer previously rescanned the actor array in each worker on
every frame before noticing that marker. It now trusts that packet flag and
keeps the prior scan/sort fallback for direct snapshots.

Two short E3M6 profiles before and after the change use the same 311-actor
state, 16 worker masks, six warmups, and 30 measured frames per production-
width stripe. Each stripe runs sequentially in one PowerShell process. The two
before runs average 3.0211 ms actor-phase median and 7.6236 ms total stripe
median; the two candidate runs average 2.8863 and 7.5026 ms. Every profile has
the same full-frame pixel hash. The changes are small and run-to-run variation
is material; these measurements do not establish a live-dispatch gain or a
display-rate improvement.

The candidate passes 122 focused fuzz checks, five-view 16-worker comparisons
in Classic, Matrix/Katakana, and AnsiArt/Katakana (320,000 pixels per style,
zero differences), and a fresh 36-map load/35-idle-tic/two-frame smoke. These
checks establish output consistency and map load/render coverage, not
campaign completion or original-executable parity. See the [source-pinned
profile receipt](../results/renderer-prepared-actor-order-fastpath-20260928.json)
and [current Episode 1 candidate pin](../results/episode1-current-human-candidate-20260928-r4.json).

## Decode worker-visible actors before rasterization — September 28, 2026

NumericV4 packets already carry a projected-column mask for every actor, but
each renderer process still walked the full actor array to test its own bit.
The worker decoder now builds a reusable list of only the actors whose sprite
patch intersects that worker's stripe. The full snapshot actor array remains
available for state and compatibility; filtering preserves its order, including
the host-prepared far-to-near order used by Spectre fuzz. No packet format or
image algorithm changed.

Two order-reversed fixed-state E3M6 comparisons used 311 actors, 16
production-width stripes, eight warmups and 40 measured frames per stripe.
Each stripe ran sequentially in one PowerShell process. The table sums each
stripe's median render time and median decode time; it is a CPU-work comparison,
not concurrent worker latency or a frame-rate result.

| Pair order | Path | Actor phase sum / render sum / decode sum / combined (ms) | Slowest stripe render + decode medians (ms) |
| --- | --- | ---: | ---: |
| Full scan, then list | Full actor-array scan | 51.17 / 124.74 / 22.26 / 147.00 | 12.00 |
| Full scan, then list | Per-worker visible list | 35.88 / 115.86 / 25.18 / 141.04 | 11.61 |
| List, then full scan | Per-worker visible list | 37.34 / 117.79 / 26.59 / 144.38 | 11.85 |
| List, then full scan | Full actor-array scan | 53.99 / 133.52 / 23.64 / 157.16 | 12.59 |

The new decode adds 12–13% to measured snapshot-decode CPU, while actor-phase
work falls about 30%; combined decode-plus-render CPU falls 4.1% and 8.1% in
the two run orders. Every full-frame hash is
`629A3A3CDA2B6365C0406A6BA70AC5A1EEFAD701BE926FD86A572AAD78F64D0C`.
The current implementation also passes 16-process, five-view comparisons in
Classic, Matrix/Katakana and AnsiArt/Katakana (320,000 pixels per style, zero
differences), an 18-check snapshot transport suite, a 36/36 map load/render
smoke, and a 16-worker E1M1-to-E1M2 reload with menus and automap pixels
matching. Those checks establish worker output and lifecycle consistency, not
campaign completion or original-executable parity.

The compact [comparison receipt](../results/renderer-visible-actor-filter-20260928.json)
indexes source hashes and raw ignored reports. This profile excludes actual
process scheduling, simulation, audio, ANSI output, and monitor presentation;
the 35-tic/60-display goal remains open.

## Reuse typed actor projections on dense scenes — September 28, 2026

The worker visibility pass already computes each actor's fixed-point depth,
lateral offset, horizontal scale, and rotated sprite frame to build conservative
stripe masks. Dense scenes now carry those values to workers in a compact typed
cache, so the PowerShell renderer can reuse them rather than repeat the
transform for every worker. The ordinary NumericV3 simulation snapshot remains
unchanged. Sparse scenes keep NumericV4's double-valued mask extension;
snapshots with at least 200 actors use NumericV5, which stores `uint32` worker
masks followed by five `int32` projection fields per actor. The projection flag
lets workers retain the existing calculation for actors that could not be
prepared safely.

The 200-actor cutoff is an adaptive guard, not a measured optimal crossover.
At the HMP initialization state, E1M1 has 91 actors and E1M2 has 199, so they
keep V4; E1M3 through E1M7 have 200–369 and select V5; E1M8 and E1M9 keep V4.
These are one-update map snapshots, not counts throughout a route. The renderer
can switch packet format as actors are created or removed.

Two order-reversed profiles used E3M6's 311-actor scene with the profiler's
Hard setting, 16 production-width stripes, eight warmups, and 40 measured
frames per stripe. Each stripe ran sequentially in one PowerShell process.
Combined work sums each stripe's median render and decode CPU time plus one
median host snapshot-preparation time:

| Order | Path | Combined median CPU work |
| --- | --- | ---: |
| Candidate then control | NumericV5 typed projections | 116.80 ms |
| Candidate then control | NumericV4 worker-side projections | 134.40 ms |
| Control then candidate | NumericV4 worker-side projections | 133.60 ms |
| Control then candidate | NumericV5 typed projections | 124.72 ms |

The candidate reduced this summed CPU work by 13.09% and 6.65% in the two
orders, averaging 9.88%. All four runs produced full-frame hash
`629A3A3CDA2B6365C0406A6BA70AC5A1EEFAD701BE926FD86A572AAD78F64D0C`.
However, the HMP E1M3 comparison did not reproduce a stable speed gain: the
candidate/control order changed the sign, and the two-pair mean was 4.28% more
CPU work for the candidate. Its four frame hashes were identical
(`8351F9034EAE4A6F13B2622689C9C82B556175DA7A11CB706500F271D8EE9EF5`). Treat
E3M6 as a positive dense stress result and E1M3 timing as inconclusive; do not
claim an Episode 1 speedup from these samples.

The current candidate passes 21 snapshot transport checks; a 36/36 Ultimate
Doom map load, 35-idle-tic, two-view serial smoke; and exact 16-process,
five-view worker output for E1M3 HMP in Classic, Matrix/Katakana, and
AnsiArt/Katakana (320,000 pixels per style, zero pixel differences, NumericV5
in each). Equivalent E3M6 checks pass in all three styles. A 91-actor E1M1
check uses V4 and also matches 320,000 Classic pixels. These fixed views and
fuzz fixtures prove only the exercised serial/worker cases, not original-game
parity or route completion.

Against the same current source, the 69 E1 transition fixtures (including
E1M3→E1M9→E1M4 and finale state) and 97 boss progression fixtures pass. A
five-second headless E1M3 run with sound and the local Episode 1 music catalog
starts 16 workers, advances 174 simulation tics, and records 155 completed
headless updates (30.95/sec). The audio report selects D_E1M3, mixes 219,240
frames, closes the device, and has no worker error; it records one rebuffer
observation with real-time mode disabled. This checks startup and bounded
integration only, not acoustic quality or continuous playback. Headless update
counts are not Terminal writes or monitor frames and do not pass the 60-display
target.

The compact [projection-cache receipt](../results/renderer-projection-cache-20260928.json)
indexes source fingerprints and raw ignored reports. The profile is sequential
worker-equivalent CPU accounting: it excludes concurrent process scheduling,
simulation, audio, ANSI writes, terminal presentation, and monitor updates. It
does not pass the 35-tic simulation or 60-displayed-update target.

A final five-second current-source `Invoke-Doom` run also starts the actual
simulation process, all 16 render workers, sound output, and the prepared
Episode 1 music catalog on E1M1. It exits at the requested duration without a
host error after 174 tics (34.72 tics/sec) and 135 completed headless host
updates (26.94/sec). Those updates are not Terminal writes or monitor frames;
the short run does not establish acoustic quality or continuous audio
underrun-free playback. See the [raw host report](../local/host-visible-actor-filter-e1m1-audio-20260928.json)
and its hash in the [candidate profile receipt](../results/renderer-visible-actor-filter-20260928.json).

## Skip decoding actor render fields outside a worker stripe — rejected, September 28, 2026

A follow-up tried to avoid assigning position, angle, sprite, frame, and light
fields to actor objects whose existing worker mask excludes that renderer
stripe. Worker masks, projection validation, actor ordering, and actor flags
remained available. The first worker render exposed an interaction with the
Spectre ordering path, which inspects actor flags before selecting the filtered
list; decoding flags for every actor restored the expected behavior.

The corrected experiment passes 21 snapshot transport checks and exact
16-process E1M3 output for five views in Classic, Matrix/Katakana, and
AnsiArt/Katakana: 320,000 pixels per style with no differences. A 16-process
Classic fuzz-partition check also matches 320,000 pixels. These checks found no
remaining output defect in the tested paths.

Two fixed-state E1M3 profile runs per version used eight warmups, 40 measured
frames per stripe, and 16 sequential production-width stripes. One run pair
was effectively tied: summed decode-plus-render medians were 129.42 ms before
and 129.85 ms with the change; decode alone rose from 11.77 ms to 14.63 ms.
The other pair disagreed sharply because its earlier baseline render sum was
196.25 ms versus 119.18 ms for the experiment. All full-frame hashes matched,
but the timing variation is too large to establish a gain. The optimization
was rejected and the decoder restored to the previously tested implementation.

Raw trial reports remain in ignored `local/snapshot-decode-skip-*` files; the
two experimental E1M3 reports have SHA-256 values
`2287DD057CEA6CEB9F27981A3A6B4EDB82F1A4DC21DA8AFA020EB76607B1E1EB` and
`D91B6312A944A36497E10B5A1F1BC5243E749A05581A62CC51E1E55990252A30`. This
experiment does not change the current renderer candidate or support an FPS
claim.

## Current-source E1M1 worker and encoder comparison

Measured September 28, 2026.

Four 60-second, no-input HMP E1M1 sessions used the Steam Ultimate Doom IWAD,
the prepared Episode 1 music catalog, PowerShell 7.6.5, and an Intel Core Ultra
7 265K with 20 logical processors. Sound and real-time music playback were
enabled. The source tree is identical to the documented `c311868` Episode 1
candidate; the measured checkout commit is `e44f44f`.

| Renderer workers | ANSI encoder | Simulation tics/sec | Completed headless render updates/sec | Submit-to-host-completion median / p95 (ms) | End-run sampled worker + simulation working set (GiB) |
| ---: | --- | ---: | ---: | ---: | ---: |
| 8 | Pairs | 34.983 | 35.483 | 28.48 / 42.86 | 2.67 |
| 16 | Pairs | 34.982 | 48.482 | 21.84 / 30.70 | 4.18 |
| 20 | Pairs | 34.980 | 48.462 | 22.60 / 28.34 | 5.02 |
| 16 | ColorState | 34.979 | 48.227 | 22.32 / 28.94 | 3.86 |

The settings ran once each, in the table's order; this is a screening comparison,
not a randomized repeated benchmark. Sixteen and twenty workers tie at about
48.5 completed updates/sec, while twenty uses 0.84 GiB more in the end-run
working-set sample. Eight workers reduce sampled memory but complete about 27%
fewer updates. Keep the 16-worker default for this workload. Working set is a
single end-run sample, not a peak or time average.

ColorState reduces the median encoding time of the slowest worker from 3.07 ms
to 2.63 ms compared with the single 16-worker Pairs run. The slowest-worker
render median rises from 11.44 ms to 11.74 ms and decode median from 1.53 ms to
1.71 ms; completed host updates do not improve. Keep Pairs as the default.
This does not contradict its known reduction in encoded bytes: fewer bytes did
not make this complete headless workload faster.

All four sessions selected `D_E1M1`, reported no host/audio error, no software
queue-starvation observation or rebuffer, zero unconsumed packets, and a closed
audio device. The submitted/returned-frame differences (3,780–5,040 frames)
equal the recorded canceled-queue upper bounds at duration shutdown; they are
not mid-session underrun evidence. These counters are software polling, not
speaker-loopback telemetry.

Headless mode still runs the PowerShell renderer and encoder, but skips
Windows Terminal writes. Completed host updates are not console writes or
displayed frames. This quiet map-start workload does not qualify moving combat,
campaign completion, audible quality, or the 35-tic/60-display goal. The
[portable receipt](../results/current-source-e1m1-worker-comparison-20260928.json)
indexes the exact settings and SHA-256 hashes for the raw reports, which remain
under ignored `local/` storage.

## Cache sector plane data for rasterization — September 29, 2026

The PowerShell rasterizer previously resolved sector heights, flat objects,
and light values repeatedly inside floor/ceiling sampling. The renderer now
keeps these values in typed per-sector arrays, refreshes them from each decoded
snapshot, and resolves flat indices through a direct byte-array table. This
keeps moving heights, translated flats, and lighting current while reducing
property lookup in the inner raster loop.

Three baseline and three candidate trials used the same idle HMP E1M1 view at
320×200. Each trial warmed five frames and measured 40 frames for each of 16
production-width stripes, rendered sequentially in one PowerShell 7.6.5
process on the Intel Core Ultra 7 265K. The median of the three run medians
fell from 6.8955 to 6.1631 ms per stripe for geometry (10.62%) and from
8.2215 to 7.4157 ms per stripe for the total measured renderer work (9.80%).
The corresponding median p95 values fell from 10.4701 to 9.0836 ms for
geometry (13.24%) and from 12.2528 to 10.6531 ms for total work (13.06%). All
six baseline/candidate full-frame hashes are identical
(`B6B0A8899E495CA1A82658CBAF108D892F6E513B8CC87C7BA6DB99829C0DF67C`).

The candidate passes a 36-map load/idle/render smoke. Five E1M1 views match
serial pixels across 16 workers in Classic, Matrix/Katakana, and
AnsiArt/Katakana (320,000 pixels per style, zero differences); encoded strips
also match. The masked-wall fixture passes 20 checks. A focused moving-sector
sweep refreshes sector 26 at tic 315 across four ceiling heights with no
render error or HUD difference. These are bounded renderer checks, not map
completion or original-executable parity.

One 60-second sound-enabled headless host run on the candidate completed
51.18 render updates/sec versus 48.48 in one earlier matching run, while both
advanced at about 34.98 simulation tics/sec. The runs were ordered and
unpaired, so the 5.57% observed host-update difference is not attributable to
this change. Worker profiling shows raster median down from 8.7437 to 8.3744
ms, while snapshot-decode median rises from 0.7861 to 1.2142 ms because the
cache refresh happens during decoding. Treat the isolated stripe result as a
measured improvement and the whole-host result as inconclusive. Headless
updates skip Terminal writes and are not monitor presentations; the 60-display
target remains open. See the [portable sector-cache receipt](../results/performance-sector-render-cache-20260929.json).

## Rejected direct plane-ID lookup — September 29, 2026

A follow-up replaced per-pixel plane-ID decoding and the floor/ceiling branch
with direct typed arrays for plane height, flat bytes, and light. Five baseline
and five candidate runs measured the same static HMP E3M6 map-start frame with
five warmups and 30 measured frames per each of 16 sequential production-width
stripes. All ten full-frame hashes match
(`92BFF34916AE31903A0A2A35A386940121EEE521346A3355543985E371561D82`).

The median of run medians moved geometry from 3.7352 to 3.6317 ms per stripe
(2.77% lower) and total measured renderer time from 6.5455 to 6.3858 ms
(2.44% lower). Geometry p95 improved only 0.44%; total p95 was effectively
unchanged at 9.2428/9.2364 ms. The two adjacent counter-ordered pairs disagree
on median direction: one candidate total median was 1.65% lower, while the
other was 1.48% higher. This does not establish a stable gain, so the additional
plane-ID arrays were discarded and the existing sector-index cache remains.

The baseline renderer's raw file hash changed across this experiment because
the Windows checkout uses `core.autocrlf=true`; Git reported no content change,
and the normalized baseline is the same committed renderer. This is why the
receipt keeps both the Git blob and working-copy fingerprints. These runs use
sequential stripes without simulation, audio, Terminal output, or real worker
concurrency; they are not live-frame or display-rate evidence. The
[rejection receipt](../results/rejected-direct-plane-lookup-20260929.json)
indexes all ten raw reports and their hashes.

## Output-clock audio under E3M6 renderer load — September 28, 2026

At current source commit dd3309e8c4cd9fb3d9c39edc85a44348e97c4449,
PowerShell 7.6.5 ran HMP E3M6 for a requested 30 seconds with 16 PowerShell
render workers, the full local Ultimate Doom music catalog, and the integrated
device-clock audio path. The actual output device selected D_E3M6. This was
one deterministic scripted, single-map headless stress sample using cyclic movement, turning, fire, and use; no Terminal presentation or campaign route was
measured.

The host advanced 719 tics in 23.244 active seconds (30.932 tics/sec), while
the wall interval was 30.015 seconds. A same-map generation reload occurred around tic 420–421; its trigger is not established. The run reported 6.769 seconds in map reload,
which is excluded from the active clock. Completed render updates were 35.106
per active second and 27.186 per wall second. These are headless host updates,
not Terminal writes or displayed frames.

The audio worker mixed 824 blocks, including 104 output-clock fill blocks for
gaps between simulation packets. It consumed 720 packets and reported zero
rebuffer resumes, zero queue-starvation observations, and zero unconsumed
packets. It submitted 1,038,240 frames; 1,033,200 were complete at shutdown,
with 5,040 queued frames as the cancellation upper bound. Three clipped samples
were counted. The device and music reader closed without an error.

The scripted pattern is a repeatable stress input, not a human-playtest substitute. This result shows that the output-clock change avoided the earlier measured
queue starvation during this one E3M6 load sample. It does not establish
uninterrupted audible output, acoustic quality, effect latency, full-campaign
continuity, or 35-tic/60-display pacing. The simulation remained below 35 tics
per active second. See the [audio discussion](audio.md#e3m6-music-under-current-renderer-load-2026-09-28)
and [portable receipt](../results/e3m6-realtime-audio-loaded-20260928.json);
the ignored raw report is local/current-source-e3m6-realtime-audio-30s-w16-20260928.json.

## Reduce fixed-point visibility allocations — September 29, 2026

The PowerShell `VisibilityCheck` now carries line-intercept fractions and
slope divisions as raw signed 32-bit values through its hot path. It reuses
per-instance `Fixed` slope wrappers, retaining the engine's wrap, saturation,
arithmetic-shift, and truncation behavior. The change is pinned to source
commit `203ca553c3cf947b1099d73b1722711ae1b405c7`.

Correctness checks compare the raw operations with the existing `Fixed`
implementation over two direct intercept cases, 50,000 deterministic random
intercept inputs, 121 division boundary pairs, and 50,000 random division
inputs. The production sight-bound path also matches 200 boundary and 50,000
random cases. A 420-command E3M6 replay matches both saved state checkpoints in
all baseline and candidate runs.

For the paired performance comparison, each variant ran twice in
baseline-candidate-candidate-baseline order on the same 420-command HMP E3M6
input. Without stage instrumentation, the mean of the two simulation median
times fell from 15.2169 ms to 14.6270 ms (3.88%); the corresponding p95 was
39.3711 ms versus 39.7350 ms. Instrumented sight-check median time fell 8.24%,
but that timing includes profiler overhead. The uninstrumented median is a
modest single-scene result, not proof of the 35 Hz goal; the p95 did not
improve. The [portable receipt](../results/visibility-fixed-point-allocation-20260929.json)
contains every run hash and the exact test outcomes.

The current-source 36-map smoke, 69 campaign-transition fixtures, and 97 boss
progression checks pass. Existing HMP route drivers pass E1M1, E1M2, and E1M4;
the E1M3 waypoint driver stalls without reproducing an engine defect. The
archived 7,118-command E1M3 replay now diverges on 23 of 24 checkpoints against
both the pre-change source and this candidate, with identical actual hashes;
its source fingerprint does not match current source. The mismatch cause is
unresolved, so that old recording is not current-build completion evidence.
The human Episode 1 route remains pending. These runs do not measure a loaded
Terminal, audio output, displayed frames, or full-campaign behavior.

## Open the qualified Episode 1 music catalog in parallel — September 29, 2026

Startup validates and locks two playback periods for each of eleven music
tracks, about 5,320,062,720 bytes (4.95469 GiB) in this local catalog. The
previous loader hashed them one track at a time. The PowerShell audio reader
now opens independent tracks through a runspace pool capped at four, while
keeping eager validation, qualification/source checks, and read locks intact.

Four baseline/candidate/candidate/baseline trials measured only catalog-reader
initialization with the OS file cache already warm. The serial medians were
4.665 seconds; the parallel medians were 2.050 seconds, a 56.06% reduction in
this stage. Every trial opened all eleven readers, and the sorted report-hash
sets matched. The focused suite passes 21 checks, including invalid-catalog
failure and cleanup of readers opened by the other runspaces. See the
[performance receipt](../results/music-catalog-open-parallel-20260929.json)
and [the 21-check playback report](../results/music-playback-parallel-tests-20260929.json).

One separate five-second sound-enabled headless E1M1 process completed in
46.81 seconds end-to-end. That run was unpaired and includes startup, playback,
and shutdown; it cannot establish the whole-game startup gain from the reader
measurement. Headless completed updates are not terminal writes or displayed
frames. Cold startup, full-campaign continuity, and the 35-tic/60-display
targets remain open.

## Rejected changed-cell ANSI output — September 29, 2026

On the same 1,560-command E1M1 replay, a 16-worker Classic run compared full
320×200 ANSI output with changed-cell patches in maximized Windows Terminal
using PowerShell 7.6.6. The patch path emitted 375,767 bytes/frame versus
604,470 (37.8% fewer), but completed updates fell from 38.43 to 26.01/sec,
simulation from 34.96 to 28.49 tics/sec, and PresentMon display transitions
from 24.95 to 17.76/sec. Slowest-worker encode median/p95 rose from
3.50/7.04 ms to 4.53/10.14 ms. A correctness suite passed 17 checks and a
short worker smoke completed, but the live pacing regression rejects this
implementation. The experiment and test code were removed; full-frame output
remains the product path. One capture wrapper timed out while draining its
report, though the game reached `ReplayEnd` and the raw PresentMon capture
covered game end. This is one matched workload, not a repeated performance
qualification. See the [portable receipt](../results/rejected-ansi-incremental-20260929.json).

## Carry the flat-texture phase modulo 64 — September 29, 2026

The plane sampler previously normalized each 16.16 world-coordinate step to a
signed 32-bit value for every sampled pixel. A 64×64 flat repeats every 64 map
units, and the lookup uses only the coordinate's low 22 bits. The PowerShell
loop now carries those 22 texture-phase bits directly; modulo 2²² gives the
same sampled texels because 2²² divides 2³².

Eight alternating baseline/candidate rounds rendered 40 full-width frames per
implementation at five fixed headings on each map. Every one of the 80 paired
frames is pixel-identical. On HMP E1M1, median serial render time fell from
52.4496 to 51.1285 ms (2.52%) and p95 from 93.6523 to 86.9725 ms (7.13%). On
E3M6, the median fell from 72.2761 to 71.1417 ms (1.57%) and p95 from
111.4349 to 106.7223 ms (4.23%). These are fixed-state renderer calls; they
exclude simulation, audio, worker scheduling, Terminal output, and display
presentation. The long-tail maxima varied and are not used to claim a pacing
gain.

The changed source passes the 36-map load/idle/render smoke, five-view fuzzed
16-worker pixel/encoding comparisons in Classic, Matrix/Katakana, and
AnsiArt/Katakana, all 20 masked-wall checks, and the occluded-BON1 scene check.
Those checks protect output and regressions; they do not show the complete
campaign or qualify the 35-tic/60-display target. See the [source-pinned
receipt](../results/renderer-flat-phase-wrap-20260929.json); raw reports remain
under ignored `local/` storage.

## Defer flat-texture index-bit extraction — September 29, 2026

R12 replaces the per-pixel 22-bit coordinate masks with carried Int64 plane
coordinates. At each texel lookup, PowerShell extracts only X bits 16–21 and Y
bits 10–15 for the 64×64 flat index. This preserves Doom's signed 32-bit wrap
semantics for these bits because the flat period (2²²) divides 2³².

Eight alternating baseline/candidate rounds rendered 40 full-width paired
frames per sample at five fixed headings. Two independent HMP E1M1 samples
show serial-render medians falling from 53.7246 to 47.9883 ms (10.68%) and
from 59.0802 to 55.7099 ms (5.70%). The HMP E3M6 median is effectively flat:
76.7806 to 77.0622 ms (0.37% slower). Across the three samples, all 120
baseline/candidate frame pairs match exactly (7,680,000 compared pixels,
zero differences). The percentile changes also vary by scene and repeat, so
these isolated medians do not establish a general game-speed gain.

A separate 15-second, 16-worker headless A-B-B-A host comparison is
inconclusive. Baseline A and both candidate runs completed about 52.25, 53.98,
and 57.33 headless updates/sec, while baseline B dropped to 19.52 updates/sec
and 30.12 tics/sec with 247 command-backpressure events. No cause was isolated;
do not attribute the difference to R12. This comparison is not a live Terminal
test or display-rate result.

The R12 source also passes 36-map load/idle/render smoke, exact five-view
16-worker checks for Classic, Matrix/Katakana, and AnsiArt/Katakana, 100,000
random-coordinate equivalence cases, `Play.ps1 -Check`, and a five-second
actual-worker E1M1 audio startup with 174 tics, 198 headless updates, no
starvation/rebuffer observations, and clean device shutdown. The 5,040-frame
shutdown tail is only a cancellation upper bound. None of these checks finishes
a map, qualifies audible continuity, or establishes 35-tic/60-display pacing.
See the [renderer comparison receipt](../results/renderer-flat-texel-bit-extraction-20260929.json)
and [R12 candidate receipt](../results/episode1-current-human-candidate-20260929-r12.json).

## Reuse renderer assets on same-map resets — September 29, 2026

The persistent renderer workers need static map assets only when the map identity
changes. A death/restart or same-map reload rebuilds dynamic simulation state,
but it does not change the IWAD's map geometry or textures. The simulation worker
now skips rebuilding the static renderer bundle for the same game mode, version,
mission pack, episode, and map. Dynamic sectors and actors still arrive in the
normal snapshots. The host validates the new snapshot generation and skips
reloading worker assets only when the episode and map match; a changed map still
reloads them.

A source-pinned, sequential E1M1 replay pair compared baseline `ef6e750` with
candidate `8b48f99` in maximized Windows Terminal, Classic truecolor, 16 workers,
and PowerShell 7.6.5. Both runs consumed 1,560 commands and performed the same
E1M1 reload at tic 1,247. The measured same-map handoff pause fell from 6.178
seconds to 0.358 seconds (94.2% lower), and the candidate report confirms static
assets were reused. The residual 0.358 seconds was not separately attributed.

| Measurement | Baseline | Candidate |
| --- | ---: | ---: |
| Same-map reload pause | 6.178 s | 0.358 s |
| Simulation rate | 34.971 tics/sec | 34.966 tics/sec |
| Completed updates while active | 49.70/sec | 46.22/sec |
| PresentMon displayed transitions | 43.66/sec | 45.89/sec |

This is one sequential pair, not a repeated performance qualification. Active
completed updates were lower in the candidate, so the pair does not establish a
general speedup. Both simulation samples are slightly below 35 tics/sec, and
both measured display rates are below 60/sec. The replay stops at `ReplayEnd`,
does not finish E1M1, and had audio disabled. PresentMon is ETW presentation
telemetry rather than an optical monitor measurement. This result only supports
the targeted same-map reset improvement; it does not qualify other map loads,
full-session audio, the campaign, or 35/60 pacing.

The same-map save/new-game worker checks pass 12 focused assertions, and the
changed-map E1M1-to-E1M2 session path continues to refresh worker assets. The
launcher check reports `Ready` with the installed 36-map IWAD and qualified
11-track catalog metadata. The compact [source-pinned receipt]
(../results/renderer-same-map-reset-presentmon-20260929.json) stores all metrics
and hashes; full game reports and PresentMon captures remain in ignored `local/`.

## R14 current-source audio-loaded headless run — September 29, 2026

The current R14 source was run for five active seconds on E1M1 under PowerShell
7.6.5 with 16 renderer workers, the installed Ultimate Doom IWAD, the local
11-track catalog, and realtime audio enabled. The actual Windows audio worker
selected D_E1M1 and closed without a reported error. It submitted 231,840
frames and completed 226,800, leaving a 5,040-frame shutdown-cancellation
upper bound. No software queue-starvation or rebuffer observation occurred.

The run advanced 174 simulation tics (34.777/sec) and completed 214 headless
render updates (42.772/sec); it wrote nothing to Windows Terminal. It emitted
no active sound-effect voice. This confirms startup and short music-worker
operation only. It is below the 35-tic and 60-update goals, and says nothing
about visible presentation, live sound effects, acoustics, sustained campaign
playback, or a completed map. The
[source-pinned receipt](../results/episode1-current-audio-startup-r14-20260929.json)
links the portable summary to the ignored raw report.

A second five-second run uses the launcher's scripted attack input with
realtime audio enabled. It reaches 34.720 simulation tics/sec and 48.488
completed headless updates/sec, submits 230,580 audio frames, and completes
225,540 with the same 5,040-frame shutdown-cancellation upper bound. Fourteen
audio events produce a peak of one active voice; there are no clipped samples,
software queue-starvation observations, or rebuffer resumes. The actual audio
device closes cleanly. This run exercises one brief game-effect path but does
not measure monitor presentations, acoustics, or full-session audio. The
[scripted-effect receipt](../results/episode1-current-audio-effects-r14-20260929.json)
preserves the raw report hash and its limits.

## Rejected masked-sprite post property hoist — September 29, 2026

A small PowerShell candidate copied each masked sprite post's data-array and
offset properties to locals before the inner vertical pixel loop. Two
fixed-state E3M6 profiles per variant used the Steam IWAD, HMP, the prepared
worker-mask snapshot, 16 production-equivalent stripes rendered serially, four
warmup frames, and 20 measured frames per stripe. All 640 stripe samples per
variant produced the same indexed framebuffer and per-worker pixel hashes.

| Phase | Baseline median / p95 | Candidate median / p95 |
| --- | ---: | ---: |
| Actor phase | 1.950 / 4.215 ms | 1.971 / 4.265 ms |
| Total stripe render | 7.145 / 9.846 ms | 7.130 / 10.062 ms |

The actor phase was slightly slower; the 0.016 ms total-median difference is
not a repeatable gain, and candidate p95 was worse. The edit was reverted.
These are serial fixed-state phase timings, not concurrent-worker, host, or
display performance. The [compact comparison receipt](../results/renderer-post-properties-hoist-rejected-20260929.json)
indexes the ignored raw profiles and exact source hashes.

## Rejected translated-flat color cache — September 29, 2026

A candidate lazily cached each flat after translation through the selected
colormap, keyed by flat and light. Two fixed-state E3M6 profiles per variant
covered 640 serial production-equivalent stripe renders; the exact frame and
per-worker hashes matched. Geometry median/p95 was 3.8148/5.3055 ms at
baseline and 3.927/5.4123 ms with the cache. Total median/p95 was
7.0278/9.2991 ms and 7.0181/9.3107 ms, respectively. The 0.14% total-median
difference is noise, geometry was 2.9% slower, and candidate p95 was worse;
the source was restored. Cache population cost and memory growth were not
measured. These serial fixed-state timings do not establish host or display
performance. The [compact comparison receipt](../results/rejected-flat-color-cache-20260929.json)
indexes the ignored raw profiles and exact source hashes.
