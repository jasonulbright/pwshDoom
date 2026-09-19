# Bound input backlog without hiding slow simulation

Measured 2026-09-19. E1M3's first recorded Matrix run failed with `Simulation command ring overflow`. The host issued 2,091 inputs while only 1,067 updates completed in the measured interval: the full 1,024-slot ring was occupied. Shutdown completed five more updates. Four available original replay checkpoints matched. This was a host throughput failure, not E1M3 campaign qualification.

The recorded run averaged 30.552 ms in `Game.Update` and 17.083 ms publishing snapshots. Together those stages exceed the 28.571 ms budget for 35 ticks/sec. Completed console writes averaged 57.258/sec; this does not measure displayed FPS. The failure receipts are `results/e1m3-matrix-first-{game,recording,audio,clock,input,host-ready,failure-av}.json`.

The host now waits before sampling input or advancing replay and automap indices whenever two simulation commands are outstanding. The active clock continues running during that wait, preserving measured slowdown and lateness. The existing 1,024-slot hard overflow guard remains. No commands, actors or simulation ticks are discarded. The configured bound appears as `MaximumPendingCommands`; it is a limit, not an independently sampled high-water mark.

| Check | Result |
| --- | --- |
| Actual mapped-memory transport, deterministic consumer | Five checks; all 1,200 distinct commands and automap masks survive the physical ring wrap; admission and wake events work; hard overflow still rejects publication. |
| Real 16-worker headless host, E1M3, Matrix encoder, six-track music catalog | All 1,200 supplied commands complete, all four original checkpoints match, no host/simulation/audio error. |
| Independent evidence audit | Thirteen checks compare every input field, settings, checkpoints, ordered pressure intervals and audio accounting. |
| Audio accounting | 1,200 packets; all 1,512,000 submitted frames returned, zero queued-frame cancellations or unconsumed packets. This is digital accounting, not acoustic review. |
| Throughput | 61.780 active seconds, 19.424 simulation ticks/sec. Crash prevention is demonstrated; 35/60 performance is not. |

Transport receipts: `results/command-admission-ring-second.json`; its first attempt and exact harness are retained as `command-admission-ring-first.json` and `command-admission-first-harness.ps1`. That initial harness failed before assertions because PowerShell bound a null memory-map name to an invalid empty string. The corrected fixture uses a unique named map; production admission logic did not change.

Host evidence: `results/e1m3-host-admission-first.json`, `e1m3-admission-prefix.json`, `e1m3-admission-recorded.json`, and `e1m3-host-admission-audit.json`. The prefix ends at 1,200 commands and does not reach the exit. Its source fingerprint matches the pre-optimization implementation. Later snapshot optimization must receive separate qualification.

The original failed capture and a separately labeled muxed failure movie remain under ignored `local/recordings/e1m3-matrix-first*`. The mux receipt verifies preserved compressed video frames/timestamps and a 103.017-second container. A decoded frame at 60 seconds was visually inspected: Japanese glyphs and HUD are present, but scene contrast is low. This is not a full movie or acoustic review. Recorder/source fingerprints exist, but an additional pre-run route-source snapshot was omitted; none was reconstructed retrospectively. No successful full-route capture is claimed.

Next reduce measured snapshot and game-update cost, then repeat full host playback with source-pinned recordings. Increasing the ring or extending the recording deadline would not establish the performance target.

Follow-up: [shared numeric snapshot packing](direct-snapshots.md) preserves both endpoints and raises the same headless prefix from 19.424 to 23.765 ticks/sec, with all four original checkpoints and all audio frames intact. The admission limit remains two. The 35-tic target and full recorded route remain open.
