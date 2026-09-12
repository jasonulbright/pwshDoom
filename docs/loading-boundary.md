# Loading before the next world is constructed

The host now enters its loading phase before `DoomGame.DoLoadLevel` changes the world. Previously, the expensive World constructor ran before the host was told to stop its active clock and pause audio. That let the old audio queue run empty during work already intended to be a loading pause.

`DoomGame.BeforeLevelLoad` is an optional host-only PowerShell callback. The simulation installs it after initial setup and again when a reconstructed save becomes the live game. The callback is excluded by the existing data-only save catalog; executable callbacks are neither stored in nor accepted from saved game data. Callers without a callback retain the existing controller behavior.

The callback publishes loading status, then requests an audio drain through the last packet already produced. The worker consumes and plays that tail, acknowledges only once its buffers have returned, and holds later packets through world construction and renderer asset refresh. A lone queued packet can finish without waiting for a second. The existing map epoch reset still occurs before new-map audio; normal packet publication resumes after the renderer acknowledges the new asset generation.

This is an explicit loading pause, not uninterrupted sound and not faster world construction. It preserves old PCM instead of resetting a live tail. Loading time remains in wall-clock reports and actual footage. Active-clock rates exclude that reported pause, so comparisons must include wall duration and the loading interval.

## Verification

The initial device test passes nine checks for empty startup, a single-packet drain, holding later queued packets, rejecting overlapping requests, complete return of all 6,300 frames, independent literal PCM identity, separate intentional-drain reporting and clean shutdown while held. Six engine tests verify notification before construction/reload, no notification on ordinary tics, callback-free save data and failure propagation before world replacement.

The existing music/control test passes ten checks, the delayed-producer rebuffer test passes seven, controller transition tests pass 57, and save-state reconstruction/continuation/corruption checks pass 24. The save fixture restores at tic 700 and continues 140 ordinary commands. These targeted fixtures do not establish broad campaign completion, physical listening or every menu/load interaction.

The actual simulation-worker save/menu/new-game/load fixture with the three-track catalog passes 15 checks in `results/save-worker-loading-boundary.json`. It retains numeric saved state, exact archived bytes, three audio epoch changes, qualified music and clean closure. Three loading receipts drain through packet 69, 69 and 76 respectively; successful save-candidate construction remains covered by the existing busy-menu pause, while the pre-construction callback applies to ordinary/new-game world loading. This fixture does not exercise a later ordinary exit after a save restoration.

Reports are `results/audio-loading-boundary-first.json`, `level-loading-boundary-first.json`, `music-audio-loading-boundary.json`, `audio-rebuffer-loading-boundary.json`, `campaign-transitions-loading-boundary.json` and `save-state-loading-boundary.json`.

## Recorded integration result

The actual Matrix E1M1/intermission/E1M2 route completes all 1,747 commands, matches all eight historical checkpoints, and returns all 2,201,220 submitted frames with no canceled tail. Submitted PCM remains exactly `DB35F5D34C9206B8D47126FEF57070EB6D10BD0D3D3A302BC11269666288AD63`, matching all three prior isolated routes. The original 37-check recording audit passes; five additional loading-boundary assertions bring the expanded audit to 42 passing checks, retained in `results/music-route-loading-boundary-verified.json`.

At command boundary 1675, the worker drains through packet 1674 and returns all 2,110,500 old-map frames. The producer wait is 272.370 ms. Time from the beginning of the boundary to renderer asset work is 1,138.589 ms; the whole acknowledged boundary is 2,167.431 ms. The host independently records a 2,163.484 ms loading interval. The difference reflects where the polling host observes status changes. The pre-construction portion is now included in loading, rather than allowing the host's active clock to run through it.

The route takes 52.374 wall seconds and 50.211 active seconds, with 2,978 completed console writes. Two unexpected empty queues remain after packets 1684 and 1692, plus the final shutdown observation after 1746. Maximum mix time is 89.136 ms and submission age 222.751 ms. This single recorded trial does not establish improved frame pacing or continuous audio. The deliberate loading pause and later starvation are different events, both retained.

Full portable game/audio/capture/merge/source receipts are copied byte-identically to `results/music-route-loading-boundary-*.json`. Actual footage remains under ignored `local/recordings/`. The full audiovisual movie has SHA-256 `7BC4FD95D0022876EB1DC3DA0F29DDF90848100E3EF1996872E4F499363138D1`; the real-time transition excerpt is `music-route-loading-boundary-transitions.mp4`, SHA-256 `828582FA3296198F89FC74594FF2A4F85A0BC0A207B726AE86242BFCFB7CD42F`. Both decode successfully. Sampled actual intermission and E1M2 images retain the existing low-contrast block UI and katakana gameplay; no renderer algorithm changed. No physical listening claim follows.

## Timing and failure handling

Simulation reports retain `LoadingBoundaries` with start/end QPC, command boundary, drain wait/acknowledgement, time before renderer asset creation and total interval. An unfinished boundary is retained separately on failure. Audio reports retain `LoadingDrains` independently from unexpected queue-starvation observations. Buffer return is the device API's completion boundary, not proof that a physical speaker emitted the samples.

The producer waits at most three seconds for acknowledgement, then fails explicitly and invokes ordinary host cleanup. The bounded queue remains 32 packets; overflow is still an error. No extra game tics or audio samples are generated to conceal a pause. Menu/volume/epoch controls retain their existing explicit behavior, including reported canceled tails where applicable.

The next audio producer issue is intermission/UI work before packet publication. The earlier [recovery study](audio-recovery.md) retains those measurements and the original late-loading behavior for comparison.
