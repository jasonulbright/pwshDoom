# PowerShell audio investigation

The terminal game has opt-in sound effects with `./Start-Doom.ps1 -Sound` and [music integration](music-integration.md) with an explicit `-MusicCatalog`. Interactive playback now advances active PowerShell music/effect state on the device clock between simulation packets; deterministic headless hosts remain packet-exact unless explicitly launched with `-RealtimeAudio`. The complete eleven-track Ultimate Doom Episode 1 looping catalog is qualified locally and its actual simulation/audio worker passes save/load/new-game integration checks. A finite D_INTRO score now passes deterministic end/release-tail qualification, reader EOF checks and an actual worker first-block PCM comparison; other one-shot scores remain open. The default remains silent when calling the engine launcher without `-Sound` or a catalog. DMX decoding, stereo positioning, linear resampling, music synthesis and mixing run in PowerShell, with a standard Windows playback queue. Persistent [sound volume and mute](settings.md#sound-controls-qualification) are implemented. Full-campaign continuity, audio-event delay during simulation backlog, audible latency, and acoustic quality remain open release requirements.

## Implementation boundary

`src/AudioEvents.ps1` implements the retained engine's `ISound` callbacks without consuming gameplay RNG. It records start/stop/reset/pause/resume events and assigns reference-based numeric emitter IDs. Both adapters update gains from current listener/emitter positions once per tic. The first direct offline adapter retains sources until level reset; the new packet adapter retires them after their longest pending sound plus two active audio tics. Paused packets do not advance this expiry clock. A later emission gets a new ID. The real route peaks at four retained sources; broader moving/destroyed-emitter semantics remain to qualify.

`src/AudioMixer.ps1` accepts format-3 DMX unsigned 8-bit samples, validates the declared rate/count, removes the conventional sixteen samples at each end, maps unsigned midpoint 128 to zero, and resamples linearly to stereo signed 16-bit PCM. The explicit `None` padding option is for unpadded experimental data. The DMX mode rejects source counts of 48 or fewer. These header/padding rules are informed by [Chocolate Doom's primary implementation](https://github.com/chocolate-doom/chocolate-doom/blob/master/src/i_sdlsound.c), inspected 2026-09-11; this moving link is a reference, not a pinned vendored dependency. The implementation is original GPL PowerShell, with no external algorithm body adopted for this milestone.

Distance uses the retained backend's 160/1200 world-unit full-volume/cutoff constants, with Doom's approximate distance metric and a sine pan. Facing east, a sound north of the player is louder on the left. Centered audio uses half amplitude per channel for headroom. Voices share an emitter/group replacement rule; a full mixer replaces its oldest voice. This is a declared approximation, not exact DMX priority, randomized-pitch or OpenAL equivalence. Chaingun falls back to the pistol lump when DSCHGUN is absent. Asset names, rates, lengths and hashes are in the replay report; samples stay ignored under `local/`.

`src/WaveOutDevice.ps1` compiles only Windows ABI structures and P/Invoke declarations. PowerShell owns buffer preparation, submission, completion checks, pause, restart, reset and cleanup. It opens the default Windows output device at 44.1 kHz/stereo/16-bit. The APIs may perform ordinary system format conversion. There is no compiled custom decoder, mixer or synthesizer.

Microsoft documents [event callbacks and device opening](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutopen), [prepared-buffer lifetime](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutprepareheader), [completion flags](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/ns-mmeapi-wavehdr), [reset returning buffers](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutreset), and [unpreparing before freeing](https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-waveoutunprepareheader). Cleanup retains allocations if a driver refuses to return ownership, allowing a safe retry instead of freeing driver-owned memory.

## Evidence so far

- `results/audio-mixer-first.json`: 21 independent checks covering malformed DMX data, padding, unsigned conversion, interpolation values, block partition invariance, overlapping saturation, pause/mute advancement, voice replacement, stereo direction, distance and listener rotation.
- `results/audio-replay-first.json`: preserved failed harness attempt. A legacy replay has null control events; a strict-mode `.Count` access failed before asset decoding. The corrected harness handles null and bounds fixtures to ten minutes.
- `results/audio-replay-legacy.json`: the ordinary-input E1M1/intermission/E1M2 route emits 75 events, preserves all eight existing checkpoints and produces 2,201,220 stereo frames (49.914286 seconds). Maximum simultaneous voices: five. Sixteen channel samples clip; replacement count is 29. The first sound is near 8.89 seconds, so the opening silence is intentional. ffprobe independently identifies the output as 44.1 kHz stereo PCM signed 16-bit.
- `results/audio-device-first.json`: eleven checks pass using the replay's segment starting at nine seconds. Four 882-frame buffers provide 80 ms nominal queue capacity. All 352,937 submitted frames return completed, including a 137-frame tail. The test pauses for 204 ms, resumes, closes twice safely, then opens another device and resets an outstanding buffer during early close. Wall duration is 8.229 seconds. Zero polls observe an empty queue while input remains. This is API completion evidence, not an audibility review, measured end-to-end latency or hardware-underrun telemetry.
- `results/audio-mixer-cast.json`: 22 checks pass after optimization, including independent ties-to-even rounding and asymmetric saturation-boundary values.
- `results/audio-validation-canonical.json`: 26 evidence checks pass, including source hashes, parsing, PCM identity and ordered event identity. The earlier `audio-validation.json` retains a harness failure caused by comparing JSON property order across PowerShell processes; sorting property names within each event fixes the comparison without reordering events.

No live game/window test occurred in the initial foundation milestone. Later integration tests are described below. The WAV is derived from the user's local IWAD and is excluded from Git. There is no claim that existing screen recordings contain this audio.

## Cost and next integration decision

The initial real-route mixer costs 11.09 ms mean, 21.96 ms p95 and 41.79 ms maximum per 1,260-frame block. Each block represents 28.571 ms at 44.1 kHz. Event processing averages 0.172 ms. These exclude gameplay and file writing.

The first optimization skips empty-voice mixing, caches source bounds, replaces a per-sample minimum call with a bounds check, and uses PowerShell's numeric ties-to-even cast with explicit saturation boundaries. All four synthetic PCM hashes are identical before and after. The tests separately cover the -32768.5 versus +32767.5 rounding boundary.

| Sustained voices | Initial mean ms/block | Optimized mean ms/block | Optimized p95 ms |
| --- | ---: | ---: | ---: |
| 0 | 4.80 | 0.04 | 0.04 |
| 1 | 10.99 | 2.80 | 3.26 |
| 5 | 27.83 | 11.19 | 13.44 |
| 16 | 78.50 | 32.88 | 34.20 |

Sources: `results/audio-mixer-cost-baseline.json` and `results/audio-mixer-cost-cast.json`. Each uses ten warmup blocks and eighty timed blocks per voice count, with the same deterministic 11.025 kHz source at 44.1 kHz output. Generation/hashing are excluded. These sequential isolated trials do not establish performance under renderer load. All eighty optimized sixteen-voice blocks still exceed their audio duration.

The optimized real route (`results/audio-replay-cast.json`) preserves the entire WAV SHA-256, all 75 events and eight gameplay checkpoints. Mixing falls to 2.137 ms mean, 6.608 ms p95 and 12.271 ms maximum. Event processing averages 0.147 ms, with a 20.634 ms maximum. This is still an isolated offline route, not a live deadline test. The later [per-sample index optimization](#per-sample-index-optimization-2026-09-27) addresses the isolated sixteen-voice cost; live deadlines remain unverified.

## Per-sample index optimization (2026-09-27)

`Read-DoomAudioFrames` previously called `Math.Floor` for every output frame
and multiplied each frame number by two for stereo indexing. Voice positions
are nonnegative and their steps are positive, so the mixer now truncates the
saved position once at each block boundary and advances an integer sample
index as the fractional position crosses input samples. A `while` handles
steps that skip more than one sample. Interpolation, pitch, gain, accumulation,
clipping, and PCM conversion are unchanged.

Two before/after pairs ran the same 90-block workload per voice count: ten
warmups, then eighty timed 1,260-frame blocks at 44.1 kHz. Pair order was
reversed on the second pass. The baseline is the pre-change mixer from commit
`13e4301`; the candidate source is pinned in the [summary receipt](../results/audio-mixer-hotloop-summary-20260927.json).

| Sustained voices | Baseline mean ms/block, two runs | Candidate mean ms/block, two runs | Reduction | Blocks slower than 28.57 ms, baseline → candidate |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 0.0217 / 0.0212 | 0.0217 / 0.0209 | control | 0/0 → 0/0 |
| 1 | 2.790 / 2.815 | 0.548 / 0.562 | 80.1–80.4% | 0/0 → 0/0 |
| 5 | 12.302 / 12.179 | 1.633 / 2.064 | 83.1–86.7% | 0/0 → 0/0 |
| 16 | 32.911 / 33.260 | 5.698 / 5.013 | 82.7–84.9% | 80/80 → 0/80 |

All four voice-count PCM digests match in both pairs. The 26-check mixer suite
also matches pre-change golden PCM at pitch 0.97 and pitch 3.25, including
block splits; the nine music/effects-mix checks pass. Receipts include the
[first pair](../results/audio-mixer-hotloop-paired-before-20260927.json) and
[candidate](../results/audio-mixer-hotloop-paired-after-20260927.json), the
[reversed-order candidate](../results/audio-mixer-hotloop-paired-after-repeat-20260927.json)
and [baseline](../results/audio-mixer-hotloop-paired-before-repeat-20260927.json),
and the [focused checks](../results/audio-mixer-hotloop-tests-final-20260927.json)
and [music/effects checks](../results/audio-mixer-hotloop-music-tests-20260927.json).

This is an isolated synthetic mixer measurement: it excludes asset decoding,
the renderer, device submission, live scheduling, and speaker output. The
improvement removes the prior 16-voice block overrun in this fixture; it does
not certify dense-combat audio deadlines or eliminate the observed live queue
starvation. The first candidate failed the existing block-boundary check
because its cached index restarted at zero; that preserved failure is
`audio-mixer-hotloop-tests-20260927.json`. Initializing from the voice's saved
position fixed it, and the full focused suite then passed.

## Live worker integration

`src/AudioRunspace.ps1` starts a dedicated runspace for `scripts/Invoke-AudioWorker.ps1`. The simulation thread sends numeric sound events and gain snapshots using `src/AudioPackets.ps1`. Decoded sample arrays are shared read-only; game objects and PowerShell class method calls stay on the simulation thread. A bounded 32-packet collection rejects overflow explicitly. Nothing silently discards a gameplay tic to meet an audio target.

The device uses four 1,260-frame buffers (114.3 ms nominal capacity), starts after two queued blocks, and responds to a shared pause flag. A dedicated host-memory field tracks active-clock pauses, including a too-small viewport. Menu pauses are also applied by the simulation. Map/new-game/load transitions advance an epoch and reset old-world queued sound; stale packets are counted. A packet from a newer epoch is retained until control catches up. Successful save loading resets the former sound state before replacing its listener. Device shutdown reports how much queued audio may have been cancelled. It does not pretend those frames were heard.

## Interactive realtime fill (2026-09-28)

The earlier worker consumed one 1,260-frame output block for every simulation
packet. That tied music and effect playback to simulation scheduling: a
67.42 ms packet interval under renderer load could empty the four-buffer queue
and force a 54.17 ms rebuffer wait. The mixer itself took about 0.5–0.6 ms per
block in that interval.

Interactive launches now let the PowerShell audio worker fill a returned device
slot from its current mixer and music-reader state when no new simulation
packet is ready. It does not invent packet sequence numbers or game events.
Music and active effect voices advance at 44.1 kHz until the next simulation
packet updates events and gains. Shared pause, map-epoch reset, and an explicit
packet-bounded drain prevent this fill. When no music or effect voice is active,
the worker pauses instead of reporting idle time as active starvation. Headless
hosts retain the one-packet/one-block path by default so existing replay PCM
comparisons remain deterministic; `scripts/Invoke-Doom.ps1 -Headless
-RealtimeAudio` enables the integrated output-clock path for a bounded test.

The focused [continuity test](../scripts/Test-AudioRealtimeContinuity.ps1)
passes eight actual-device checks: one qualified D_E1M1 start packet produces
ten total blocks, music continues with no new packet, shared pause stops
production, resume continues the cursor, and a drain stops at its requested
packet. All 12,600 submitted frames return, with zero rebuffer/starvation and no
worker error; its [source-pinned receipt](../results/audio-realtime-continuity-20260928.json)
preserves the measured counters. The four-second D_E3M6 simulation-host check under PowerShell
7.6.5 consumed 128 packets and generated 16 additional blocks; it submitted
181,440 frames, returned 176,400 before shutdown, and reported a 5,040-frame
canceled-tail upper bound, with no active queue starvation or rebuffer. The
focused packet-exact music-worker (10 checks), rebuffer (7), load-boundary (9),
runspace lifecycle (6), and simulation backpressure (8) regressions also pass.

This removes gaps caused by short packet-production stalls in the tested
interactive path; it cannot accelerate a simulation that stays below 35 tics
per second. Packets still wait for free output slots, so these checks do not
establish audible effect latency, absence of physical-device underruns, or
full-campaign acoustic quality. Raw current-host reports remain under ignored
`local/`; no recordings were made.

`results/audio-packets-replay.json` preserves the entire earlier PCM hash and all eight checkpoints. `results/audio-packets-unit.json` independently checks numerical packet output, conservative source expiry, paused lifetime, reset and missing-asset rejection. `results/audio-runspace-future-epoch.json` checks an actual output device in a separate runspace, including a deliberately early future-epoch packet. Those synthetic tone tests are not audibility reviews.

The first full Classic headless host (`results/audio-host-first.json`) runs all sixteen rendering workers and the real output device. It consumes 1,747 tics in 50.887 active seconds with 3,017 completed renders (59.29/sec), matching all eight checkpoints. Audio consumes all 1,747 packets, submits and receives completion for 2,201,220 stereo frames, and closes cleanly. Mixing averages 3.141 ms, with 31.580 ms maximum; packet construction averages 0.216 ms. Packet age ends at driver submission: mean 91.843 ms, maximum 226.301 ms. Four polling starvation observations occur before the last packet and another after route completion. These are not direct hardware-underrun or acoustic-latency measurements. Worker wall time includes its wait during renderer startup; it is not the active game clock. No uniquely displayed-FPS claim follows from this headless run.

The first host precedes the reviewed future-epoch race correction, paused-expiry correction, PCM digest telemetry and explicit loading-pause hold. Do not treat its hashes as evidence for later code changes.

The corrected controls run (`results/audio-host-controls.json`) pauses at twelve seconds, resumes at thirteen, shrinks its synthetic Classic viewport to 98 rows at sixteen seconds and restores it at seventeen. All 1,747 tics and eight checkpoints match. The worker reports two pause transitions and one level epoch reset, consumes every packet without stale/unconsumed entries, returns all 2,201,220 frames and closes cleanly. Its SHA-256 of submitted PCM bytes is `25C7077C167D10105F0A8408B7EAEFE52566808E5F9BD46A15D98D40CF82D8F6`, matching the entire offline WAV payload after its 44-byte header. Timing pauses therefore preserve the content on this route. This does not establish acoustic timing or every gameplay transition.

`results/audio-save-worker.json` passes fourteen checks in the actual simulation process, including isolated save replacement/rejection, new-game and two successful loads, exact numeric state restoration and three audio epoch resets. Audio closes without worker or cleanup error. This short fixture is primarily session/lifetime evidence; it does not qualify acoustic transitions during a noisy fight.

`results/audio-live-recording.json` records the actual Matrix terminal run and local media hashes. It preserves all eight checkpoints and the same complete submitted-PCM hash, with a menu pause and clean audio shutdown. The host completes 3,002 writes in 51.665 active seconds (58.10/sec); these are recorded-run writes, not unique displayed frames. The 1472×1006 original has 5,129 encoded frames. The inspected 1280×800 crop begins at X=96/Y=120, matching the observed 184×60 terminal and centered 160×50 game grid. Its 54.483-second viewing copy fully decodes to 3,269 frames. A full-size frame and five populated contact-sheet tiles show katakana gameplay and HUD; the sixth tile is unused. Dim green scene values remain a known limitation. Original and copy remain under ignored `local/recordings/`; neither contains an audio stream.

`results/audio-integration-validation.json` passes 27 evidence checks and pins sixteen current source files, including fifteen standalone parses. The engine-dependent event class is exercised by the actual host. No owned game or recorder processes remain after these runs. The full Ultimate Doom release goal remains active.

Next: broaden menu/save/load/new-game/viewport timing qualification, reduce queue delay without hiding starvation, measure audible latency, add music with documented synthesis/instrument provenance, and record actual audiovisual output. The recorder can launch with `-Sound`, but its existing `-an` video path does not capture playback audio; footage is explicitly silent video until loopback capture is implemented.

## E3M6 music under current renderer load (2026-09-28)

A 30-second current-source, 16-worker headless host used the actual Windows
audio device, -RealtimeAudio, and the 30-report Ultimate Doom music catalog.
It selected D_E3M6, produced 104 device-clock fill blocks alongside 720
simulation packets, and reported zero rebuffer resumes or queue-starvation
observations. The audio device closed without worker or cleanup error; no
packets remained unconsumed. Of 1,038,240 submitted frames, 1,033,200 were
reported complete at shutdown, leaving a 5,040-frame canceled-tail upper
bound. The mixer counted three clipped samples.

This is one deterministic scripted, single-map headless stress sample, not a campaign route, audible
quality review, latency measurement, or proof against physical-device underruns.
The built-in input cycles forward movement, turning, periodic fire, and use. One same-map generation reload occurred around tic 420–421; its trigger is not isolated. The game advanced 719 tics in 23.244 active seconds (30.93 tics/sec); the
30.015-second wall interval also included 6.769 seconds of map reload. The
headless update count is not Terminal presentation. See the
[source-pinned receipt](../results/e3m6-realtime-audio-loaded-20260928.json)
and raw report under ignored local/.

## Reproducing the bounded experiments

Run in PowerShell 7.4 or newer from `C:\projects\pwshDoom`, using fresh report filenames:

```powershell
./scripts/Test-AudioMixer.ps1 -Output local/audio-unit.json
./scripts/Measure-AudioMixer.ps1 -Output local/audio-cost.json
./scripts/Render-AudioReplay.ps1 -Output local/audio-route.json
./scripts/Test-WaveOutPlayback.ps1 -Output local/audio-device.json -ReplayReport local/audio-route.json
```

The last command plays an eight-second segment through the current default output device. The replay script's default IWAD is the user's Steam Ultimate Doom installation; supply `-Wad` for a different legitimate path. It intentionally requires the existing eight-checkpoint route and has not been generalized to arbitrary save/new-game control-event fixtures.

## Open qualified music readers concurrently — September 29, 2026

The audio worker still validates every report, source set, playback-payload
length and SHA-256 before it announces readiness, and it keeps each validated
payload read-locked for playback. The change only opens independent tracks in a
PowerShell runspace pool capped at four readers; it does not defer integrity
checks until a later map. The current Episode 1 catalog opens all eleven tracks
and preserves the exact sorted set of qualification-report hashes.

The [paired reader-open receipt](../results/music-catalog-open-parallel-20260929.json)
records baseline-candidate-candidate-baseline trials with a warm OS file cache.
All [21 music-playback checks](../results/music-playback-parallel-tests-20260929.json)
pass, including rejection of an invalid catalog entry while confirming that
readers opened by other runspaces release their file handles. The [r9 host
receipt](../results/episode1-r9-audio-smoke-20260929.json)
records a five-second, sound-enabled E1M1 run under PowerShell 7.6.5: D_E1M1
was selected, all 220,500 submitted frames returned, and the audio device
closed without worker or cleanup error. Its only queue-empty observation was
after the final packet; no rebuffer resume occurred.

This is not a cold-start comparison, a full-campaign audio run, an acoustic
review, or visible Terminal pacing evidence. The measured full process lasted
46.81 seconds, but that single unpaired duration includes all startup and
shutdown work and does not assign the remaining time to this audio change.

## PowerShell 7.6.6 host recheck — September 29, 2026

The same R9 source passes all 21 focused music-playback checks under the
installed PowerShell 7.6.6 runtime. A five-second, sound-enabled, headless
E1M1 host run then selects D_E1M1, advances 174 simulation tics, returns all
219,240 submitted audio frames, and closes the device without worker or
cleanup error. The host records one queue-starvation poll after packet 173
with no rebuffer resume. The polling counter is not hardware underrun
telemetry, and no acoustic review was performed.

The [7.6.6 playback receipt](../results/music-playback-runtime-7.6.6-20260929.json)
and [host receipt](../results/episode1-r9-audio-smoke-7.6.6-20260929.json)
pin the runtime, source, and raw local report hashes. This confirms startup
compatibility on the patch version that previously failed; it does not
qualify full-session or campaign continuity, visible Terminal performance,
or the 35 Hz simulation / 60 displayed-update goals. The 176 headless render
updates are not displayed frames.
