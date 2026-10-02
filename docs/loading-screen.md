# Map handoff and loading feedback

Development after the frozen R19 package makes worker asset reloads pollable and
adds loading feedback while the host waits for a new generation. The simulation
and audio retain their existing pause/drain/acknowledgement boundary. The host
discards old rendered work, waits for every worker to install the new assets,
then acknowledges that exact snapshot generation before returning to gameplay.

`Start-GameRenderAssetReload` starts one owned reload. Polling completion checks
every worker for errors, collects telemetry once all finish, and applies the
existing thirty-second deadline to the whole reload. The synchronous wrapper
remains available. Rendering, harvesting and overlapping reloads are rejected
until completion is consumed; duplicate completion is rejected too.

The loading banner is a small custom PowerShell 5×7 terminal graphic. It is red
in Classic/color art and green in Matrix. Animated dots indicate waiting; a
clipped one-line fallback fits tiny windows. It does not use an original Doom
menu patch. Standard .NET asynchronous stream I/O writes the bounded UI update;
the host continues polling preparation and worker completion. It drains that
last UI write before allowing gameplay output to own the stream again.

Loading writes have separate counters, byte totals and QPC observations under
`LoadingScreen` in session reports. They receive no gameplay-frame/FPS credit.
Their nominal update cadence is ten per second, independent of the paused game
clock. Terminal display events can include those UI changes; neither a write
nor an ETW event establishes optical Doom-frame identity.

## Validation and limits

The [live receipt](../results/loading-ui-live-20261001.json) retains 24 independent
notice/audio/media checks and 34 additional lifecycle checks. All three styles'
sixteen-worker tests compare 448,000 pixels and 112 encoded strips, plus 256,000
pixels against freshly converted resources, across four map changes. Actual
polls observe unfinished reloads and reject overlapping operations. Corrupting
only a test-owned asset file propagates the worker failure in 22.3 ms. The banner
passes 84 independently decoded viewport/animation cases.

An actual Classic ordinary-input E1M1/intermission/E1M2 recording consumes all
1,747 commands, preserves sixteen workers and returns all 2,222,640 submitted
audio frames. Its changed-map handoff logs 118 polls and seven loading updates.
Three actual save-fixture recordings also consume all 350 commands and match
eleven checkpoints each. Classic and color art use default Strips output;
Matrix exercises AsyncBatch. Reported game/loading output ownership intervals
are disjoint, with one-millisecond rounding tolerance. Reviewed samples show
the banner in every style. Original videos/audio/clock metadata remain local.

The ordinary route's first loading update takes 7.15 ms to dispatch and has a
989.6 ms observed completion interval. Later observations are about 100 ms
apart. The first interval does not establish when native I/O itself completed,
or distinguish task/terminal backpressure from a delayed host observation. The
save fixtures' first observations are 3.5–12.2 ms. The later investigation below
measures this delay more tightly. Physical keyboard/resize/acoustic and
full-campaign qualification remain open.

Three clean ordinary-route repeats at cb7731d bracket the first loading write's
Task completion at 981.8–985.7 ms, with hundreds of false completion probes.
This excludes a delayed host observation as the whole explanation. It still
does not isolate native I/O from scheduling. The [baseline receipt](../results/loading-task-brackets-classic-20261002.json)
pins each interval and its raw captures.

Sixteen renderer processes previously left thirty-two idle stdout/stderr
ReadToEndAsync Tasks in the host. PowerShell now redirects each renderer's
streams to unique owned log files. Empty successful files are removed;
nonempty/error files remain. Startup failures before channel creation retain
their error and stack. All-style reload/fault checks and a final synchronous
reload pass; the [logging receipt](../results/worker-file-logging-20261002.json)
also retains a corrected single-map test-harness failure. Gameplay, rendering
and mixing algorithms remain in PowerShell, and thread-pool settings are unchanged.

Three corresponding clean repeats at 22219c8 have first completion upper bounds
of 2.664–2.720 ms, with no false probes. At dispatch the host reports four pool
threads, two busy workers and zero pending work items. Startup is 26.97–27.22
seconds versus 40.22–42.76 seconds before. These sequential source cohorts
support the targeted change; they are not randomized/ABBA trials. There is no
before-change stack/counter capture proving the exact scheduling mechanism.
[Microsoft's diagnosis guidance](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/debug-threadpool-starvation)
supports investigating blocked pool work; the [.NET 10.0.0 reference Stream source](https://github.com/dotnet/runtime/blob/v10.0.0/src/libraries/System.Private.CoreLib/src/System/IO/Stream.cs)
schedules its base asynchronous write on the default task scheduler. Reflection
on installed .NET 10.0.12 confirms the console stream inherits that method;
the cited source tag is not the installed patch's binary source.

The [after-change receipt](../results/renderer-file-logs-pacing-classic-20261002.json)
retains 50.54–52.40 global display transitions/sec, 34.851–34.977 active tics/sec
and 4.519–4.553 GiB sampled private memory. P99 tic lateness is 624–921 ms,
worse than the preceding cohort; none passes all gates. Global ETW display
gaps include loading feedback and cannot identify distinct gameplay images.
The shorter loading Task interval does not qualify overall pacing or campaign play.

R19 and Preview.4 stay frozen and do not contain this change. The complete
Episode 1 human route and broader Ultimate Doom release gates remain in the
[roadmap](roadmap.md).
