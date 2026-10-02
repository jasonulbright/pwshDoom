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
save fixtures' first observations are 3.5–12.2 ms. No pause-free loading display
or clean pacing gain is claimed. Repeated ETW measurements and tighter task
completion observations remain work; physical keyboard/resize/acoustic and
full-campaign qualification remain open.

R19 and Preview.4 stay frozen and do not contain this change. The complete
Episode 1 human route and broader Ultimate Doom release gates remain in the
[roadmap](roadmap.md).
