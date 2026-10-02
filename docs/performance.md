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

## Reject per-row plane-boundary scans — September 29, 2026

The plane rasterizer checked the global worker-boundary array on every row,
although production calls already restrict each worker to its own
`FirstColumn..EndColumn` stripe. A candidate removed that lookup and left the
existing `EndColumn` limit in place. Two short E3M6 profiles per version used
the prepared NumericV5 worker-mask path, 16 production-width stripes, three
warmup frames and twelve measured frames per stripe. The order was baseline /
candidate, then candidate / baseline.

The full-frame hash and all sixteen per-worker hashes match exactly. Across the
two run medians, total stripe-render median moved from 7.6949 to 7.4676 ms
(2.95% lower), while total p95 moved from 10.0697 to 10.2294 ms (1.58%
higher). Geometry median moved only 0.54%; the mean slowest-worker median was
0.35% worse and its p95 1.11% worse. Given the small sample and no improvement
in the worker that gates a completed frame, the change was reverted. This is
not evidence of better host pacing or displayed frame rate. The
[portable receipt](../results/rejected-plane-boundary-scan-20260929.json)
indexes the four ignored raw profiles and their hashes.

## Reject worker-range mask lookup — September 29, 2026

For 280-actor E3M6 snapshots, a candidate precomputed the worker owning each
pixel column and a bit mask for every contiguous worker range. Snapshot
preparation then resolved the first and last sprite columns and looked up the
covering-worker mask, replacing the per-actor scan across all 16 workers.
PowerShell 7.6.6 profiles used eight warmups and 40 measured frames in
baseline/candidate/candidate/baseline order. All four fixed-view framebuffer
hashes match. Across the two pairs, mean median preparation time fell from
12.6644 to 11.9290 ms (5.8%), but mean p95 rose from 14.6085 to 15.5967 ms
(6.8%); the second pair regressed in both median and p95. This does not show a
stable worker-pacing gain, and the serial stripe profile does not measure
concurrent completion, host pacing, terminal writes, or displayed frames. The
candidate was reverted. The restored R16 source passes five-view, 16-worker
serial/worker equality on E3M6 in Classic, Matrix/Katakana, and
AnsiArt/Katakana (320,000 pixels per style). See the
[source-and-timing receipt](../results/rejected-worker-range-mask-20260929.json);
raw profiles remain under ignored `local/`.

## Current-source R17 E1M1 renderer phase profile — September 29, 2026

The R17 FastRenderer was profiled under official portable PowerShell 7.6.6 at
HMP E1M1's initial state, with 91 actors and no simulation tics advanced. The
profile warmed five frames and measured 30 frames for each of the 16 production
20-column stripes. It rendered the stripes sequentially in one PowerShell
process; it did not launch worker processes or write to Terminal. The run's
64,000-pixel output had SHA-256
`B6B0A8899E495CA1A82658CBAF108D892F6E513B8CC87C7BA6DB99829C0DF67C`.

| Phase | Median per stripe | P95 per stripe |
| --- | ---: | ---: |
| Geometry (wall and plane path) | 6.935 ms | 10.248 ms |
| Actors | 0.327 ms | 0.739 ms |
| Player weapon | 0.086 ms | 0.204 ms |
| HUD | 0.852 ms | 1.519 ms |
| Total | 8.364 ms | 12.310 ms |

Geometry is about 83% of the median total in this fixed E1M1 view. Snapshot
preparation has a 1.681 ms median and 2.741 ms p95 in the harness. This narrows
the next code investigation to the wall/plane renderer; it does not identify a
single inner-loop cause. The result is a descriptive profile, not a speedup or
FPS claim, and it is not directly comparable to the earlier sector-cache trial
because this run uses a different transport/runtime profile and was not paired.
The [portable profile receipt](../results/r17-fast-renderer-phases-20260929.json)
pins source and raw report hashes; the full report remains under ignored
`local/` storage.

## Reject cached wall-sector property reads — September 29, 2026

The geometry timing above led to an inspection of the visible-wall loop. It
read floor/ceiling heights, ceiling flats, and light levels from snapshot
sector hashtables for every visible segment even though per-snapshot typed
arrays already held the flat and light values. A candidate added exact-double
interpolated wall-height arrays and used those arrays in the loop; all game and
rendering algorithms remained PowerShell.

Four baseline and four initial-candidate profiles used the same HMP E1M1
tic-zero view under PowerShell 7.6.6, with five warmups and 30 measured renders
for each of 16 production-width stripes. Two further profiles used the final
candidate source. The closest final-source comparison ran baseline then
candidate: geometry median was 5.900/5.870 ms per stripe, and total median was
6.996/6.955 ms. One other final-source candidate run was slower than the
baseline. The small median differences do not establish a repeatable gain;
the profile also excludes the extra sector-cache refresh work. The candidate
was reverted.

All ten profile frame hashes and per-worker output hashes match the baseline.
The candidate also matches the baseline across five views and seven uneven
process strips in Classic, Matrix/Katakana, and AnsiArt/Katakana (320,000
pixels per style); the moving-ceiling diagnostic images match at four tested
heights. Its 36-map load/idle/two-heading smoke and 20 masked-wall checks pass.
Those are correctness checks, not evidence of better live pacing or completed
campaign play. The [rejection receipt](../results/renderer-wall-sector-cache-rejected-20260929.json)
records the raw profile hashes, candidate source fingerprint, output parity,
and limits; raw files remain under ignored `local/` storage.
## Loaded Classic route repeats — October 1, 2026

Three retained PowerShell 7.6.6/16-worker/maximized Classic runs use the same
1,747-command ordinary-input E1M1 completion, intermission advancement and
71-tic E1M2 continuation, with the eleven-track Episode 1 catalog and actual
audio device. They use the same runtime source at implementation commit
`3bc0ccc`. The later Matrix-notice contrast change is absent. Startup is
measured from the collector's explicit launch timestamp to the first completed
game write. The global display window includes the entire map handoff.

| Run | Active tics/sec | Global display transitions/sec | p95 / p99 / max display gap, ms | Launch to first write, sec | Peak sampled game private memory, GiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| R2, exploratory | 34.914 | 48.938 | 30.302 / 42.452 / 8,412.026 | 37.254 | 5.419 |
| R3, sequential repeat | 34.969 | 50.849 | 30.301 / 42.422 / 6,836.352 | 39.498 | 5.440 |
| R4, sequential repeat | 27.676 | 31.137 | 84.811 / 133.323 / 9,078.793 | 38.056 | 5.440 |

R2 overlaps one PNG frame extraction and analyzer editing, so it is retained
as exploratory evidence and does not count as a third clean qualification
repeat. No recorder/export/other qualification ran during R3/R4. All three
complete every command, enter E1M2 and return every submitted audio frame.
They do not satisfy the frozen pacing gate. R4's large slowdown is retained;
the source/runtime pins alone do not explain it. Simulation p99 lateness is
186.862 / 180.207 / 14,144.137 ms, respectively. The command admission window
remains bounded at two; it preserves commands rather than dropping overdue
game tics.

The extended analyzer reports contiguous world/intermission windows, p99 and
the boundary gap without removing those holds from global timing. Independent
CSV-derived display counts and p99 values match its output. The main Terminal
swapchain is selected by the most observed display events, without independent
Doom-frame content identity. Sampled memory omits unsampled peaks; CPU deltas
omit startup before readiness and final unsampled tails. These tests measure
software queue behavior, not acoustics or physical speaker latency. See the
[source-pinned receipt](../results/loaded-classic-route-pacing-20261001.json)
for all raw hashes, window/stage timing, CPU samples and audio counts.

## Map asset preparation — October 1, 2026

The simulation now reuses converted WAD textures, sprite/HUD patches and
lighting tables, while each map gets fresh geometry and mutable render state.
An opt-in immutable-resource cache retains the v7 binary body and regenerates
its map/palette metadata. Its identity checks invalidate the body when patches,
sky or flat/color-array identities change; callers that mutate resources must
use the default uncached context. One body is retained, not a body per map.

Three sequential ABBA stage trials compare a fixed E1M2 snapshot after initial
E1M1 preparation. Fresh context/write preparation takes **4.09–4.90 seconds**;
resource reuse takes **0.081–0.112 seconds**. All twelve direct and read-back
frames have the same SHA-256. Initial cache construction still costs 1.173
seconds for conversion and 3.905 seconds for serialization, and retains
37,614,992 bytes (35.87 MiB). Read-back still takes 1.34–1.58 seconds in this
single-process workload. These numbers do not measure concurrent worker
reloads, total campaign load or Terminal display pacing.

The sixteen-worker regression passes all three styles across E1M2, E2M1,
E3M1 and a return to E1M2, including sky changes and independent fresh-resource
pixel comparisons. Worker PIDs remain unchanged. See the
[source-pinned stage and worker receipt](../results/map-render-resource-cache-20261001.json).
Reproduce with official PowerShell 7.6.6, a fresh output path and no concurrent
qualification or recording:

~~~powershell
pwsh -NoProfile -File scripts/Measure-MapRenderAssets.ps1 -Output local/map-render-assets-new.json
pwsh -NoProfile -File scripts/Test-SessionWorker.ps1 -ResourceReuse -Style Classic -Output local/session-worker-resource-new.json
~~~

One subsequent live Classic/audio route completes all 1,747 commands and enters
E1M2. Its context/write preparation takes 102 ms with the body cache reused;
the total loading boundary remains **4.517 seconds**. Global Terminal display
rate is 51.530 transitions/sec, active simulation 34.980 tics/sec, p99 tic
lateness 213 ms, startup 40.114 seconds and sampled game private memory 5.487
GiB. All submitted audio frames return cleanly. This single check fails the
frozen gate, does not establish a causal full-route speedup and leaves worker
deserialization as a measured remaining cost. See the
[live receipt](../results/resource-cache-loaded-classic-20261001-r1.json).

The next change reuses decoded immutable resources inside each persistent
worker after hashing the actual v7 body bytes. Every reload still decodes new
map/palette metadata and allocates private raster scratch. Changed bodies use
the ordinary decoder. Three final-source ABBA cycles measure **1.295–1.505
seconds** for ordinary read-back and **0.069–0.081 seconds** with verified
reuse. All twelve images match. Actual workers in all three modes confirm the
reuse decision and invalidate changed episode skies. Eighteen focused checks
also cover body tampering, fresh geometry/palette metadata, private buffers and
truncation; the truncation check exposed and repaired a pre-existing incomplete
flat/color read. These are stage/functional results; loaded pacing follows
separately. [Reader evidence](../results/render-asset-reader-reuse-20261001.json).

Three sequential live Classic/audio routes on committed `cfd8c26` complete
every command, enter E1M2 and report all sixteen workers reusing the body. None
has software audio starvation/rebuffer or lost submitted device frames.

| Run | Active simulation tics/sec | Global Terminal display transitions/sec | Total map load (sec) | Sampled game private GiB | p99 tic lateness (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| R1 | 34.979 | 55.184 | 1.541 | 4.469 | 150.965 |
| R2 | 34.882 | 53.750 | 1.997 | 4.598 | 186.411 |
| R3 | 30.656 | 47.430 | 2.028 | 4.541 | 5,168.668 |

These repeat measurements still fail the gate. They are not interleaved with
the older implementation and do not establish a causal whole-route speedup.
Startup is 39.876 / 39.120 / 37.403 seconds to first write. The third run's
E1M2 output calls average 85.811 ms, versus 12.245 / 10.016 ms in R1/R2; its
worker rasterization averages 10.197 ms and it has no audio backpressure.
Because the host supplies simulation commands and writes output synchronously,
this identifies a path through which Terminal stalls can slow the game. It
does not yet establish their cause or qualify an asynchronous replacement.
[Independent CSV/CPU/audio/load audit](../results/reader-cache-loaded-classic-20261001.json).

An experimental `-TerminalOutput AsyncBatch` now lets the host keep supplying
simulation commands while one ordinary .NET write task owns the frame buffer.
Its completion count and timestamp come after actual task completion; dispatch
time is separate. Strips remains the default. A completed next frame is bounded
behind the pending write; loading and shutdown drain output. All formatting and
buffer composition remain PowerShell over standard .NET I/O/copy APIs.

The [transport receipt](../results/asynchronous-terminal-output-20261001.json)
covers 108 byte-exact comparisons in all three styles and output paths, plus
real pipe backpressure/error accounting. One native Classic/audio smoke
completes all 1,747 commands and returns every submitted frame, but measures
34.680 active tics/sec and 51.402 global Terminal display transitions/sec. It
is exploratory, still fails the gate and supplies no paired speed claim.
The collector now accepts `-TerminalOutput` and `-AnsiEncoding` to compare
alternatives on otherwise identical source and input. Observed asynchronous
completion time includes host polling delay and does not identify display
content or physical output latency.

One clean same-source ABBA cycle at `06fb33b` compares Strips and AsyncBatch
on the ordinary E1M1/intermission/E1M2 route, with identical sound, 16 workers,
Pairs encoding and maximized five-point Classic output.

| Order | Mode | Active simulation tics/sec | Global display transitions/sec | p99 / max tic lateness (ms) |
| --- | --- | ---: | ---: | ---: |
| A1 | Strips | 34.979 | 54.910 | 165.784 / 196.050 |
| B1 | AsyncBatch | 34.978 | 54.868 | 65.145 / 138.118 |
| B2 | AsyncBatch | 34.975 | 54.069 | 59.955 / 148.023 |
| A2 | Strips | 34.979 | 50.610 | 273.078 / 300.819 |

All commands and submitted audio frames complete, with zero software
starvation/rebuffer. Per-frame byte sums equal output totals in every run.
Async dispatch averages 0.230 / 0.253 ms and observed completion averages
7.556 / 7.726 ms. It has lower simulation lateness in this cycle; this does
not establish general superiority, a passing three-cycle qualification or
59 display transitions/sec. The default remains Strips while asynchronous
resize/menu/effect behavior is checked. The
[independent ABBA receipt](../results/output-abba-classic-20261001.json)
keeps all global/window/CPU/audio/load results and source hashes.


## Three live exact-color ABBA cycles — October 1, 2026

Twelve sequential sessions at checkout `61c7f7e` use the frozen R19 runtime
source (`f0a16af`), PowerShell 7.6.6, sixteen renderer workers, maximized Classic
at font size 5, and the same 1,747-command E1M1/intermission/E1M2 route, settings,
IWAD and eleven-track music catalog. Both encoders use AsyncBatch. Each cycle
runs Pairs, ColorState, ColorState, Pairs; no other study qualification,
recording, export or analyzer overlaps collection. The [portable receipt](../results/colorstate-abba-classic-r19-20261001.json)
pins all raw reports/CSVs, source hashes, protocol and audits. Startup, loading
holds and asynchronous output completion observations remain in the evidence.

| Cycle / position | Encoder | Active tics/sec | Global display events/sec | Tick lateness p99 (ms) | Mean bytes per observed frame |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 / 1 | Pairs | 34.967 | 52.196 | 83.330 | 613,387 |
| 1 / 2 | ColorState | 34.966 | 52.460 | 78.452 | 524,510 |
| 1 / 3 | ColorState | 34.978 | 53.806 | 80.825 | 519,614 |
| 1 / 4 | Pairs | 34.641 | 51.585 | 94.820 | 612,893 |
| 2 / 1 | Pairs | 34.979 | 51.669 | 69.174 | 614,585 |
| 2 / 2 | ColorState | 34.979 | 55.022 | 73.488 | 523,743 |
| 2 / 3 | ColorState | 34.972 | 56.696 | 72.765 | 521,901 |
| 2 / 4 | Pairs | 34.973 | 50.958 | 85.279 | 612,720 |
| 3 / 1 | Pairs | 34.978 | 51.667 | 68.474 | 614,190 |
| 3 / 2 | ColorState | 34.976 | 53.693 | 67.162 | 524,003 |
| 3 / 3 | ColorState | 34.672 | 51.665 | 370.199 | 520,977 |
| 3 / 4 | Pairs | 34.979 | 53.661 | 57.104 | 612,296 |

ColorState's median mean bytes per observed frame is 14.73% lower. The median
global display-event rate is 53.750/sec versus 51.668/sec. Within-cycle mean
rate differences are +2.39%, +8.86% and +0.03%; the third cycle is effectively
tied and includes the slow ColorState run. Identical inputs do not establish
identical rendered/interpolated frame samples, so these byte ratios describe
observed sessions rather than an identical-image compression ratio. The fresh
thirteen-case codec test independently parses every painted RGB pixel and
retains its six real static views and alternating-order isolated samples.

Peak sampled game private memory has medians of 4.105 GiB for ColorState and
4.534 GiB for Pairs; these sampled values are lower bounds on actual peaks.
First completed writes occur 38.55–53.29 seconds after launch. All runs consume
all commands, close audio cleanly and return every submitted frame, with zero
software queue-starvation observations and rebuffer resumes. The independent
CSV audit confirms display counts/p99 gaps, and per-frame byte totals reconcile
with completed-output accounting. Its first attempt incorrectly compared
source dictionaries by property order; sorted actual path/hash pairs confirm
one identical host-source set. That failed auditor and corrected receipt are
retained separately.

None passes all frozen numerical gates. Every global display rate is below
59/sec, and maximum display gaps are 1.24–2.92 seconds. The 1/4 run's reported
active rate includes a 741.6 ms final observed output drain; that failed rate is
retained. In 3/3, E1M2's mean slowest-worker raster is 19.0 ms, snapshot
publication 9.0 ms, game update 6.8 ms and observed output completion 15.0 ms;
audio packet production averages 0.175 ms with no audio backpressure. Its
2.9-second intermission completion observation overlaps map loading and does
not prove native I/O blocked for that duration. System/scheduling/thermal cause
remains unestablished. Neither the failed rate nor the outlier is discarded.

Keep Pairs and Strips as defaults. ColorState remains an exact-color opt-in;
this experiment supports a modest workload-specific benefit with AsyncBatch,
not a general winner or a release performance pass. Further work must reduce
transition display gaps and repeat other styles, viewport sizes and heavier
workloads. Optical frame identity, acoustic review and second hardware remain
unqualified.


## Loading feedback after R19

[Pollable reloads and separate loading UI](loading-screen.md) now allow feedback during map preparation and worker reload. Four actual WGC/audio recordings qualify specific route/save/ownership behavior, with separate UI counters and no gameplay FPS credit. The ordinary route's first UI dispatch takes 7.15 ms but its completion observation takes 989.6 ms; later updates are about 100 ms apart. This is a recorded correctness/effect test, not a clean ETW comparison or a pause-free-display qualification. Native task completion, host observation delay and terminal backpressure need stronger separation before causal attribution. R19 and the twelve-run comparison remain frozen evidence from the earlier source.

Three later clean cb7731d repeats bracket the first loading Task completion at
981.8–985.7 ms, excluding host observation delay alone. Replacing thirty-two idle
renderer pipe readers with owned PowerShell logs reduces corresponding 22219c8
first-write upper bounds to 2.664–2.720 ms. Startup falls from 40.22–42.76 to
26.97–27.22 seconds. Sequential before/after cohorts support this specific
change; they do not establish a general pacing winner. All three styles pass
actual worker/resource/fault checks, and a separate WGC route passes 36 grouped
source/accounting/media checks with a reviewed loading sample.

The [clean receipt](../results/renderer-file-logs-pacing-classic-20261002.json)
retains global display rates 52.397 / 50.541 / 50.908/sec and active tics
34.977 / 34.975 / 34.851/sec. P99 tic lateness is 624.1 / 920.7 / 795.7 ms;
maximums are 666.4 / 942.4 / 880.0 ms. Sampled private memory is 4.519–4.553 GiB.
No run passes all gates. ETW intervals include the separately accounted loading
feedback, so reduced global gaps do not prove smoother distinct gameplay frames.

Early command 58–73 delays precede sustained audio packet age. Median age from
packet construction to submission is 661.7 / 871.3 / 872.1 ms, while median
mix blocks take about 0.7 ms. Runs two/three retain 1159/1220 producer-backpressure
intervals, starting at command 162/157. Realtime filler generated 30/42/45 blocks
while packets were unavailable. All submitted frames return and software
starvation/rebuffer counts remain zero, but those facts do not qualify latency.
A controlled producer-gap/recovery test follows before changing timing policy.
The [recorded route receipt](../results/renderer-file-logs-live-20261002.json)
and original media stay separate from these clean measurements.

## Clean loaded routes after audio recovery

Three sequential 0dd795b Classic/maximized/font5 sessions retain the same
1747-command route, sixteen workers, default Strips/Pairs and device audio.
All packets and submitted PCM reconcile. Audio producer-backpressure waits
fall to zero; median all-packet processing ages are 65–85 ms. The worker applies
caught-up events on the current output clock instead of repeating elapsed
filler duration. Prior submission-age medians included the mixing step;
these new consumption ages precede it. Device/acoustic latency is unmeasured.

| Repeat | Active tics/sec | Global display events/sec | P99 tic lateness (ms) | Startup (s) | Sampled private GiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 34.810 | 53.795 | 461.97 | 26.92 | 4.531 |
| 2 | 34.966 | 53.249 | 405.03 | 26.37 | 4.559 |
| 3 | 34.972 | 52.619 | 550.24 | 27.61 | 4.469 |

The [independent receipt](../results/audio-recovery-loaded-classic-20261002.json)
preserves source manifests, CSV/display metrics, all packet-processing ages,
timing credits and separate loading/game output accounting. Initial tic stalls
remain; steady command350–1400 medians are about7–8 ms, but they do not replace
the full-run gate denominator. No run passes all gates. The separate
[actual WGC/audio recording](../results/audio-recovery-live-20261002.json)
passes46 grouped source/lifecycle/media checks, with no clean-performance claim.

## Bounded command catch-up

A diagnostic route at bfc62c1 finds command62 published789 ms late with an
empty observed queue; the worker starts its update about0.28 ms after signaling.
The next host implementation, f200220, catches up already-due35-Hz commands
within a four-command pass budget and the unchanged two-command window. It
stops at recorded control boundaries and rechecks loading/clock status.

Three sequential clean runs retain the same Classic/maximized/font5 route,
sixteen workers, Strips/Pairs and eleven-track device audio:

| Repeat | Catch-up bursts | Active tics/sec | Display events/sec | P99 tic lateness (ms) | Maximum lateness (ms) | Startup (s) | Sampled private GiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 33 | 34.972 | 48.922 | 105.64 | 173.35 | 27.43 | 4.546 |
| 2 | 63 | 34.959 | 48.719 | 646.89 | 790.45 | 27.31 | 4.549 |
| 3 | 34 | 34.979 | 50.376 | 79.41 | 157.27 | 25.57 | 4.609 |

Every burst contains two commands in these runs; all1747 commands and audio
packets finish. Independent traces verify due times, pass order and the
pre-publication queue observations. All PCM and realtime credits reconcile;
software starvation/rebuffer and producer-backpressure counts remain zero.
Median all-packet processing ages are81.8 /164.6 /93.3 ms, excluding the
device/acoustic tail.

The second run retains substantial producer delay: command55 is issued788.4 ms
late with zero observed queued commands and an approximate worker-start delay
of0.31 ms. Its preceding167.5 ms publication gap overlaps155.1 ms of terminal
output. The worst early gaps in repeats one/three also overlap output. Catch-up
does not prevent synchronous output stalls. These successive source cohorts
are not a paired A/B causal comparison, and the observed display rates are
lower than the previous cohort. No run passes all numerical gates; p99 display
gaps are60.6 /78.8 /54.5 ms and maximums169.7 /727.3 /951.6 ms. Keep failed
whole-window measurements and investigate bounded asynchronous output on the
current runtime before changing defaults. [Source/CSV/audio/scheduling receipt](../results/command-burst-loaded-classic-20261002.json).

## Output comparison with the current scheduler

Three full Strips–AsyncBatch–AsyncBatch–Strips cycles at cafa405 retain the
f200220 runtime, Classic/maximized/font5, sixteen workers, Pairs, the same
1747-command route and eleven-track actual-device audio. Twelve sequential
runs complete, with no concurrent study recordings, exports, tests or timing
analysis during collection. Routine collection-status reads remain possible.
Independent raw-CSV display counts/p99, source manifests, command due/queue
observations, separate UI/game accounting and all audio packets/credits/PCM
reconcile. [Twelve-run receipt and retained outlier inspection](../results/command-output-abba-classic-20261002.json).

| Cycle | Strips median display events/sec | AsyncBatch median display events/sec | Change | Strips median p99 tic lateness (ms) | AsyncBatch median p99 tic lateness (ms) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 53.110 | 54.850 | +3.28% | 77.33 | 61.03 |
| 2 | 53.043 | 52.170 | −1.65% | 87.36 | 67.22 |
| 3 | 51.671 | 53.462 | +3.47% | 151.35 | 91.14 |

AsyncBatch lowers each cycle's median p99 tic lateness, but display-rate
direction varies. Its six individual p99 values are55.85–95.86 ms; only one
meets the57.2 ms limit. Strips values are70.54–232.16 ms. No run passes all
numerical checks. Display rates across both modes are47.29–56.05 events/sec,
below59. Active tics are34.960–34.980/sec; all1747 commands and packets finish.
Startup is24.74–27.22 seconds, sampled private memory4.414–4.617 GiB and sampled
game-process CPU41.6–47.6% of twenty logical cores. CPU excludes Terminal and
sampling omits unsampled startup/tails. Software underflow/rebuffer and audio
producer-backpressure remain zero; acoustic quality/latency remain open.

Retain three different failures. Cycle3's first Strips run publishes command50
336.1 ms late with zero queued commands observed and an approximate worker
start0.39 ms after signaling; its preceding180.6 ms gap overlaps157.2 ms of
synchronous output. Cycle2's first AsyncBatch run has a1575.75 ms display-event
gap containing96 completed gameplay writes (maximum consecutive completion
gap21.08 ms) and94 dropped present starts. These counters do not establish
the physical display or OS/occlusion/thermal cause. Cycle3's first AsyncBatch
run has a303.08 ms global display gap overlapping four loading observations
and no gameplay completion. Each remains in the whole-window gate results.
An asynchronous completion observation is not proof that the host blocked
through its duration.

Keep Strips/Pairs as defaults and AsyncBatch as an opt-in alternative. This
paired study supports a specific tic-pacing benefit on one workload, with
variable display results and retained failures. It does not qualify60 unique
displayed game frames/sec, all styles/workloads, campaign completion, acoustic
review or second hardware. Further useful work includes reducing host/render
frame costs, independent moving-world fidelity and broader workloads; more
repeats of this same comparison alone will not close those gates.

### Attribute live frame costs and split geometry profiling — October 2, 2026

A [twelve-run stage audit](../results/host-frame-cost-audit-20261002.json) groups completed world frames by generation while preserving all release-gate windows. Median critical worker spans are12.18–13.24 ms in E1M1 and19.82–22.79 ms in E1M2. Median per-frame maximum render times are7.88–8.73 and14.43–17.09 ms. Submit medians are1.91–2.17 and3.40–4.54 ms, with harvest medians1.23–1.49 and1.10–1.50 ms. Component maxima may come from different workers; do not add them into an invented frame total. QPC spans include scheduling. AsyncBatch OutputMs is a completion observation, unlike synchronous Strips call duration.

Workers always publish64,000 indexed bytes each, including when the host reads only encoded strips. However, the largest per-worker elapsed portion outside named phases has median0.17–0.20 ms, encompassing input/output copying, timing/writes and descheduling. This does not isolate publication cost or establish a useful gain from omitting it. Final-image/capture behavior would need an explicit replacement protocol. Defer that change and examine geometry first.

Use `Measure-FastRendererPhases.ps1 -GeometryDetails -WorkerCount16 -TransportPrepared -TransportWorkerMasks` for opt-in setup, BSP/wall, plane and masked-wall boundaries. Default workers make no extra QPC reads. The [fixed-state profiles and equivalence checks](../results/geometry-stage-profile-20261002.json) identify wall traversal/drawing in E1M2's slowest stripe:10.12 ms median, versus2.22 ms planes and14.25 ms total. The detailed profile retains the full indexed hash and sixteen measured stripe hashes; default all-style16-worker comparisons match960,000 pixels and240 encoded strips against the prior renderer. One missing-relative-dependency harness failure remains recorded.

These profiles render each stripe sequentially with three warmups/twenty samples. The E1M2 and E3M6 startup views do not recreate full live routes, measure concurrent scheduling, or establish an optimization gain. Use the wall-stage attribution to guide a bounded exact-output trial; all frozen release pacing gates remain open.

### Reject power-of-two wall texel wrapping — October 2, 2026

A local candidate masks signed texel coordinates for power-of-two wall texture heights, retains normalized modulo otherwise, and hoists the column source offset. All twelve profiles in three fixed-E1M2 ABBA cycles retain identical full-frame and sixteen measured-stripe hashes. However, median stripe totals regress3.62%,0.77%,1.61%, and summed stripe medians regress2.95%,0.33%,1.54%. The slowest-stripe gains in cycles1/2 reverse to6.61% worse in cycle3; total p95 also regresses6.998% in that cycle. [Exact source/run metrics and rejection](../results/rejected-wall-texture-wrap-20261002.json).

The candidate remains ignored and was never adopted into production. Exact image equality is necessary but does not establish speed. These sequential isolated startup-view profiles do not measure live display performance or confidence intervals. Stop this path and retain the current renderer; further broad tests for the rejected change would add no release coverage.

### Dense E3M6 stress across all styles — October 2, 2026

The [nine-run Preview.5-runtime receipt](../results/preview5-e3m6-all-style-pacing-20261002.json) retains three sequential maximized16-worker/audio stress runs per mode, the full30-track catalog and Strips defaults. All420 commands and two stored checkpoints match. The player dies in every run; this is a captured stress workload, not ordinary route or map-completion evidence.

| Mode | Active tics/sec, three repeats | Display events/sec, three repeats |
| --- | --- | --- |
| Classic |30.537 /30.502 /30.392 |40.041 /39.478 /39.660 |
| Matrix |30.811 /28.582 /29.761 |47.249 /45.288 /44.785 |
| Color art |30.049 /29.648 /29.922 |42.803 /42.668 /42.306 |

P99 tic lateness is1.646–2.707 seconds. None passes all numerical gates; every whole window/outlier remains. Classic uses Pairs/font5, character modes use Katakana/MS Gothic12 and report encoding NotApplicable. Sequential style groups and different fonts are not a paired causal ranking. Audio packet/credit/PCM accounting passes with zero producer backpressure/software starvation/rebuffer; processing medians13.9–15.4 ms exclude speaker/device latency.

Startup is28.05–30.13 seconds. Reported private memory3.46–4.16 GiB and CPU48.1–54.0% cover host, simulation and16 renderers. Audio/music runspaces execute inside the sampled simulation process, so their resource use is included. An earlier separate-audio-process claim was incorrect and is superseded by source inspection and live process-ID evidence. Terminal remains separately sampled/excluded from game totals; once-per-second observations omit unsampled startup/tails and remain lower bounds on peaks. [Ownership correction](../results/audio-process-ownership-20261002.json). All recorded PIDs exit before analysis; recordings/exports/tests/analyzers do not overlap clean capture.

A first Classic diagnostic has18.18 ms mean game update and7.12 ms snapshot publication, leaving other stages/scheduling unclassified. Further work should investigate the command pipeline and worker-count alternatives with exact commands/images, then qualify effects separately. It should not tune this stress input into a map route or change failed gate denominators.

Separate [dense WGC/loopback recordings](../results/e3m6-effects-live-20261002.json) now retain all420 commands/two endpoints in all modes,36 unchanged source hashes and complete PCM shutdown. Six reviewed samples show pickup/damage and preserved style/HUD/notice behavior. Independent PCM reconstruction retains startup outside capture coverage and24–26 ms near-tail capture gaps. These loaded recordings do not replace clean pacing, acoustic review, original-binary fidelity or map completion. Next compare16 and8 renderer workers in paired order before changing defaults.

### Eight-worker tradeoff in dense E3M6 — October 2, 2026

The [three-cycle Classic ABBA study](../results/e3m6-worker-count-abba-20261002.json) changes only16/8/8/16 workers. All twelve runs keep420 commands/two endpoints, full resolution/actors, catalog/audio and font/output settings. Independent all-style8-worker palette/fuzz prechecks match960,000 pixels and120 encoded strips. All packet/credit/PCM accounting passes, with zero audio producer backpressure/software starvation/rebuffer.

| Cycle | Active tic-rate change with8 workers | P99 tic-lateness change | Display-event-rate change |
| --- | --- | --- | --- |
|1 |+10.47% |−70.33% |−8.26% |
|2 |+13.71% |−69.22% |−9.99% |
|3 |+12.12% |−71.64% |−8.03% |

Sampled game private memory falls37.28–39.17% and CPU30.41–33.67%; audio/music are inside the simulation sample. Median critical worker spans increase12.84→16.93 ms. QPC stages include scheduling and are not a causal scheduler diagnosis. Startup varies across cycles. None passes full numerical gates: eight-worker active rates remain32.220–33.737 tics/sec and display events35.465–38.273/sec. Player death and all windows/outliers remain. Keep16 as the primary/default and8 as a documented selectable tradeoff; this Classic comparison does not qualify other modes' live pacing with8. Process cleanup checks both PID and recorded start identity because Windows can reuse IDs.

Three isolated snapshot-packing ABBA trials preserve exact endpoint bytes across36 maps/replay and every timed call, but give little benefit: [current-endpoint specialization](../results/snapshot-current-endpoint-trial-20261002.json) median−1.566% (~0.08 ms/pair), [table hoisting](../results/snapshot-table-lookups-trial-20261002.json)−0.012%, [record-offset indexing](../results/snapshot-store-indices-trial-20261002.json)−0.241%. None enters production. Warmup/raw samples and mixed directions remain; no full-host gain is claimed.

The [command-stage audit](../results/e3m6-command-stage-audit-20261002.json) instead finds substantial discovery cost. Median run-mean16/8-worker stages are game update18.47/16.77 ms, automap discovery5.91/5.38 ms and snapshot publication7.31/6.70 ms. Discovery runs while the automap is hidden to preserve mapped lines. Adjacent update-end cycles average33.21/29.73 ms across419 intervals/run; the full420-tic release denominator is unchanged. Intercommand residual0.83/0.32 ms includes availability, bookkeeping and scheduling; QPC-derived starts are approximate. Optimize discovery only with complete mapped-state equality checks.

A [position-keyed vertex-angle trial](../results/discovery-position-angle-trial-20261002.json) preserves420 fresh mapped states/two endpoints plus144 all-map headings and11 invalidations. It retains absolute angles, while visibility/occlusion still run. Only27/420 calls reuse positions; an isolated alternating stream has slightly worse mean4.179→4.227 ms and slightly better median4.404→4.350 ms. It remains unadopted. These preliminary method times disable stationary-view skipping and do not replace native or three-cycle paired evidence. Profile the current traversal next.

The [owned-bundle discovery profile](../results/e3m6-discovery-method-profile-20261002.json) now retains420 full mapped states/two endpoints. Uninstrumented mean4.746 ms rises to5.671 ms with method timers. Inclusive IsPotentiallyVisible2.096 ms and DiscoverIndexedSeg1.851 ms overlap with PointToAngleData1.761 ms (~95 calls/command) and projection0.161 ms. PointOnSide is0.657 ms (~33 calls). These identify angle/bounding-box work for a bounded next trial, not exact loaded costs or a causal speedup. Initial discovery is outside this isolated diagnostic, and all native release denominators remain unchanged. Production instrumentation is not added.

### Exact numeric discovery slope — October 2, 2026

Inlining the discovery helper's nonnegative slope calculation avoids DivRem
ref marshalling while preserving uint32 wrap and the exact floor quotient.
The [production receipt](../results/discovery-slope-production-20261002.json)
retains20,900 previous-method angle comparisons,20,509 independent quotient
checks and three256-call ABBA cycles. Cycle-median batch cost falls55.76%,
55.51%,55.47%; these warm method times are not native tic/display rates.
The general slope/legacy angle methods stay unchanged.

Fresh mapped-line equality passes420 dense commands,144 headings over36 maps
and11 semantic invalidations. Production moving views and automap/save/audio
worker checks also pass. Retain the initial harness arithmetic error and an
unnecessary stale E1M3 run: all24 actual gameplay hashes equal a preexisting
unchanged-runtime failure, but its23 historical mismatches remain failures.
Exclude that run's timings/route outcome. Committed-source live pacing and
separate effects recordings are next; every full release gate remains open.

The committed build's [nine clean native repeats](../results/discovery-slope-native-pacing-20261002.json)
now retain all420 commands/two endpoints/audio and fail every full pacing gate.
Median active tics/sec are32.721 Classic,31.200 Matrix and31.920 color art;
median display events/sec are42.298,46.756,43.257. P99 tic lateness spans
813–1869ms. Median run-mean discovery is4.16–4.17ms. Earlier-build median tic
rates are lower, but the historical batches are unpaired; a causal native
gain is unqualified. All full windows, source/accounting checks and player
death remain. Keep primary16 workers and the frozen thresholds.

Separate [three-mode effect recordings](../results/discovery-slope-effects-live-20261002.json)
pass56 consistency checks and retain style/HUD/pickup/damage behavior in six
reviewed samples. One failed FFmpeg teardown is retained; fresh actual-effect
retries use the existing15sec target hold and succeed. Matrix still has20ms
of uncovered loopback timestamp coverage during gameplay, alongside startup
and post-game tail gaps. Complete game-side PCM accounting and zero software
starvation do not prove acoustic continuity. No recording replaces clean
pacing, full campaign or independent original-binary fidelity evidence.

### Wall sampling correctness and cost — October 2, 2026

The [wall sampling receipt](../results/wall-vertical-sampling-20261002.json)
retains nine isolated baseline-versus-trial datasets, each with three ABBA
cycles at five static headings and all 60 calls. A long accumulator and wrapping
mask do not solve the cost regression. The adopted exact binary-fraction version
prepares anchors/scale only for visible textured bands and reuses a constant
step within a front-parallel segment. No persistent lookup cache is added.

Whole-run mean changes are −2.80% in E1M2 and −1.81% in E3M6, with asymmetric
initial calls retained. Later dense-cycle means are 5.61% and 4.47% slower.
This is an arithmetic fidelity correction with a measured serial cost, not a
native pacing improvement. All failed alternatives and setup errors remain
attributable. Module-qualified dispatch is included; snapshots/context creation,
simulation, audio, worker contention and Terminal display are outside these calls.
The frozen 35-tic/60-display gates remain unchanged and unpassed.

### Horizontal wall coordinates — October 2, 2026

Six finite serial datasets retain three ABBA cycles and all 60 calls each.
The first class-based wall-U variants have later-cycle increases of roughly
4–17%; removing unused analytic coordinates preserves output but the unpaired
batches do not isolate its speed effect. The actual worker integration fails
because engine classes are intentionally absent. The adopted numeric PowerShell
implementation uses transported tables and matches all returned parameters.
[Costs, failed integration and source pins](../results/wall-horizontal-sampling-20261002.json).

Its later-cycle mean increases are 0.18%/0.78% in E1M2 and 1.56%/0.81% in E3M6.
Whole-run means are 66.94→64.70 ms and 74.05→72.56 ms, respectively, retaining
asymmetric initial calls. The implementation is adopted for measured sampling
fidelity. These isolated calls exclude simulation, audio, worker contention and
Terminal display; they establish no native pacing improvement. Historical clean
captures and effect recordings remain pinned to their earlier builds.

The [current nine native captures](../results/wall-u-native-pacing-20261002.json)
retain three repeats per mode, all 3,780 commands/18 endpoints and all full
windows. Median active rates are 31.983 Classic, 32.262 Matrix and 31.534 color art;
median display transitions/sec are 37.363, 39.603 and 41.562. Tic p99 lateness
spans 1,025–1,576 ms. Every run fails the full numerical gate set.

Startup is 26.77–30.60 sec; sampled game private totals span 3.46–4.22 GiB and
sampled CPU uses 47.9–55.9% of twenty logical-core capacity. Audio is inside the
sampled simulation process and is not counted again; Terminal stays separate.
Software starvation/rebuffer counts are zero and packet/PCM credits reconcile.
All 171 recorded process start identities have ended. Sampling can miss peaks
and startup/tail work. Display transitions do not identify distinct game frames.
Historical rates are unpaired: lower current display medians neither isolate
the wall change's cost nor establish a causal speed regression. Keep the frozen
thresholds/defaults and investigate the retained stage/lateness records next.

## Built-in state-action dispatch — October 2, 2026

Allocation profiles of a dense 420-command E3M6 replay point to `Mobj.SetState`
and `ThinkerRun` as hot paths. The baseline allocated 5,685 MiB across the
timed headless `Game.Update` calls. The new implementation routes the 52 known
PowerShell `PSMethod` actions through a same-name, case-sensitive switch in
`MobjActions`; scriptblock actions keep their helper path and unknown methods
keep the generic fallback. It adds no compiled game helper.

Two baseline and two candidate 420-tic runs retain all samples. Pooled
descriptive statistics are:

| Per-tic `Game.Update` | Baseline | Direct dispatch |
| --- | ---: | ---: |
| Count | 840 | 840 |
| Mean | 20.29 ms | 18.70 ms |
| Median | 17.43 ms | 15.68 ms |
| p95 | 46.78 ms | 44.13 ms |
| p99 | 68.28 ms | 67.17 ms |
| Allocated across two 420-tic runs | 5,685 MiB | 5,743 MiB |

Median and mean decrease 10.02% and 7.82%, respectively; allocation increases
1.01%. p99 still exceeds the frozen 57.2 ms gate. Pooled samples are descriptive,
not independent observations: each run contributes 420 serial tics and the two
baseline/candidate pairs were not randomized ABBA host captures. Timings exclude
render workers, character encoding, Terminal, audio mixing/device work and
display presentation. The prior nine current-source native captures still miss
the release thresholds; this change needs a clean all-style native rerun before
any host-level claim. No audio/acoustic equivalence claim follows.

Behavior controls compare each tic from 0 through 420: all 421 combined state,
current renderer and numeric render hashes match across builds, including the
two stored replay checkpoints. Focused menu, save reconstruction/worker,
campaign-transition, boss, movement and gameplay-action regressions also pass.
The committed candidate also loads all 36 maps, advances 35 idle tics and
renders two serial frames per map; this does not qualify navigation or completion.
The [source-pinned receipt](../results/mobj-action-dispatch-20261002.json)
includes raw local sample hashes, runtime/IWAD pins, test receipts, allocation
profiles, methods and known limits. A fresh three-style PresentMon retest could
not start because a user Windows Terminal was already running; its isolation
guard remains in force, and the existing window was left untouched.

The current source also passes exact serial/worker checks in all three styles:
five E1M1 camera headings per mode compare 320,000 pixels each with zero
difference through sixteen uneven process strips. Matrix and AnsiArt each pass
80 additional character-strip checks. This verifies internal raster/encoder
parity for that static scene, not the original game's pixels, moving-world
fidelity or native display rate. [Mode evidence](../results/mobj-action-render-modes-20261002.json).

### Simulation hot-path attribution — October 2, 2026

An owned diagnostic bundle replayed the same 420-command E3M6 input on the
committed direct-dispatch candidate and matched both stored endpoints. Stage
timers put `ThinkersRun` at 15.28 ms mean / 13.86 ms median / 28.27 ms p95 per
tic, against 19.70 / 16.31 / 41.54 ms for the whole profiled update. Additional
inclusive timers measured 12.01 ms for built-in state-action dispatch, 8.20 ms
inside `CheckSight`, 2.22 ms in XY movement and 0.15 ms in Z movement. The
replay observed 4,501 state actions, 7,892 sight checks, 393 XY calls and 1,876
Z calls. `CheckSight` can execute inside a state action, so actor slices
overlap and must not be summed. All values include profiler overhead; they are
hot-path attribution, not an uninstrumented speed comparison or a live pacing
result. No gameplay code changed for this measurement. The [source-pinned
receipt](../results/actor-hotspots-dispatch-20261002.json) records every sample,
selected checkpoint result, hashes and limits. The profiler now instruments
the direct dispatcher itself, rather than silently missing known actions after
their routing changed.

The follow-up adds counters at the BSP/subsector/line level in a second owned
bundle. Across the same 420 commands it records 119,780 BSP visits, 65,838
segment iterations, 53,662 unique-line visits and 4,765 intercept calculations
(5,531 slope divisions). Only 434 sight queries exit at the reject matrix;
1,986 crossed portals close the opening and 999 close the vertical slope
window. Both stored checkpoints match. These counters point to repeated tree
traversal and line tests for continued profiling; they do not justify skipping
a visibility query or reusing its result. This run adds counter overhead, so
its reported timings are not compared with the preceding actor-only profile.
[Traversal receipt](../results/sight-traversal-dispatch-20261002.json).

### Iterative BSP traversal trial — October 2, 2026

A PowerShell-only iterative near-side-first stack walk was tested in an owned
engine bundle. Against the recursive implementation, a 420-command E3M6 replay
produced no mismatches in the combined state/current-render hash timeline at
any tic. Four separate headless timing runs in Reference, Iterative, Iterative,
Reference order retain all 1,680 `Game.Update` samples and compare both stored
checkpoints in each run.

| Simulation-only `Game.Update` | Recursive | Iterative | Change |
| --- | ---: | ---: | ---: |
| Samples | 840 | 840 | — |
| Mean | 20.46 ms | 19.21 ms | −6.1% |
| Median | 17.70 ms | 15.58 ms | −12.0% |
| p95 | 44.97 ms | 42.39 ms | −5.7% |
| p99 | 68.21 ms | 69.36 ms | +1.7% |

The run pairs do not improve uniformly, and samples are serial observations,
not independent trials. The p99 remains above the frozen 57.2 ms limit. This
is promising evidence for a production trial, not a release pacing result: the
measurement excludes rendering workers, terminal, audio and presentation, and
only one dense map/input sequence was exercised. The [source-pinned receipt
and all-tic hashes](../results/visibility-iterative-dispatch-20261002.json)
retain all samples, run order, gates and limitations.

### Production traversal regression pass — October 2, 2026

The iterative stack walk is now in `VisibilityCheck.sb.ps1`, with its pending
node stack owned by the PowerShell checker and grown to the loaded map's node
count when required. Near-side-first order, subsector visitation and line tests
are preserved. The integrated source matches the trial at every tic of the
420-command E3M6 state/current-render timeline; the retained recursive reference
also passes both original checkpoint endpoints. The production build passes all
36 map load/idle/raster smoke cases, 69 campaign transitions, 97 boss checks,
27 movement gates, 9 game actions, menu and save/load coverage, 50,200 sight
bound cases, 50,000 intercept plus 50,121 division parity cases, and 27 audio
mixer checks. Classic, Matrix and AnsiArt each match 320,000 serial pixels
across five E1M1 views through sixteen actual process strips. The [integration
receipt](../results/visibility-iterative-integration-20261002.json) retains the
full production timeline and source/report pins. The measured p99 gate still
fails, and no complete human route, current-source live effect recording,
acoustic test or clean native pacing result follows from this regression pass.
