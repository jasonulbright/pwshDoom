# PowerShell audio investigation

The terminal game has opt-in sound effects with `./Start-Doom.ps1 -Sound` and [music integration](music-integration.md) with an explicit `-MusicCatalog`. The complete eleven-track Ultimate Doom Episode 1 looping catalog is qualified locally and its actual simulation/audio worker passes save/load/new-game integration checks. The default remains silent when calling the engine launcher without `-Sound` or a catalog. DMX decoding, stereo positioning, linear resampling, music synthesis and mixing run in PowerShell, with a standard Windows playback queue. Persistent [sound volume and mute](settings.md#sound-controls-qualification) are implemented. Broader soundtrack preparation, one-shot music, synthesis fidelity, audible latency and uninterrupted campaign qualification remain open release requirements.

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

The optimized real route (`results/audio-replay-cast.json`) preserves the entire WAV SHA-256, all 75 events and eight gameplay checkpoints. Mixing falls to 2.137 ms mean, 6.608 ms p95 and 12.271 ms maximum. Event processing averages 0.147 ms, with a 20.634 ms maximum. This is still an isolated offline route, not a live deadline test; sixteen-voice cost remains unresolved.

## Live worker integration

`src/AudioRunspace.ps1` starts a dedicated runspace for `scripts/Invoke-AudioWorker.ps1`. The simulation thread sends numeric sound events and gain snapshots using `src/AudioPackets.ps1`. Decoded sample arrays are shared read-only; game objects and PowerShell class method calls stay on the simulation thread. A bounded 32-packet collection rejects overflow explicitly. Nothing silently discards a gameplay tic to meet an audio target.

The device uses four 1,260-frame buffers (114.3 ms nominal capacity), starts after two queued blocks, and responds to a shared pause flag. A dedicated host-memory field tracks active-clock pauses, including a too-small viewport. Menu pauses are also applied by the simulation. Map/new-game/load transitions advance an epoch and reset old-world queued sound; stale packets are counted. A packet from a newer epoch is retained until control catches up. Successful save loading resets the former sound state before replacing its listener. Device shutdown reports how much queued audio may have been cancelled. It does not pretend those frames were heard.

`results/audio-packets-replay.json` preserves the entire earlier PCM hash and all eight checkpoints. `results/audio-packets-unit.json` independently checks numerical packet output, conservative source expiry, paused lifetime, reset and missing-asset rejection. `results/audio-runspace-future-epoch.json` checks an actual output device in a separate runspace, including a deliberately early future-epoch packet. Those synthetic tone tests are not audibility reviews.

The first full Classic headless host (`results/audio-host-first.json`) runs all sixteen rendering workers and the real output device. It consumes 1,747 tics in 50.887 active seconds with 3,017 completed renders (59.29/sec), matching all eight checkpoints. Audio consumes all 1,747 packets, submits and receives completion for 2,201,220 stereo frames, and closes cleanly. Mixing averages 3.141 ms, with 31.580 ms maximum; packet construction averages 0.216 ms. Packet age ends at driver submission: mean 91.843 ms, maximum 226.301 ms. Four polling starvation observations occur before the last packet and another after route completion. These are not direct hardware-underrun or acoustic-latency measurements. Worker wall time includes its wait during renderer startup; it is not the active game clock. No uniquely displayed-FPS claim follows from this headless run.

The first host precedes the reviewed future-epoch race correction, paused-expiry correction, PCM digest telemetry and explicit loading-pause hold. Do not treat its hashes as evidence for later code changes.

The corrected controls run (`results/audio-host-controls.json`) pauses at twelve seconds, resumes at thirteen, shrinks its synthetic Classic viewport to 98 rows at sixteen seconds and restores it at seventeen. All 1,747 tics and eight checkpoints match. The worker reports two pause transitions and one level epoch reset, consumes every packet without stale/unconsumed entries, returns all 2,201,220 frames and closes cleanly. Its SHA-256 of submitted PCM bytes is `25C7077C167D10105F0A8408B7EAEFE52566808E5F9BD46A15D98D40CF82D8F6`, matching the entire offline WAV payload after its 44-byte header. Timing pauses therefore preserve the content on this route. This does not establish acoustic timing or every gameplay transition.

`results/audio-save-worker.json` passes fourteen checks in the actual simulation process, including isolated save replacement/rejection, new-game and two successful loads, exact numeric state restoration and three audio epoch resets. Audio closes without worker or cleanup error. This short fixture is primarily session/lifetime evidence; it does not qualify acoustic transitions during a noisy fight.

`results/audio-live-recording.json` records the actual Matrix terminal run and local media hashes. It preserves all eight checkpoints and the same complete submitted-PCM hash, with a menu pause and clean audio shutdown. The host completes 3,002 writes in 51.665 active seconds (58.10/sec); these are recorded-run writes, not unique displayed frames. The 1472×1006 original has 5,129 encoded frames. The inspected 1280×800 crop begins at X=96/Y=120, matching the observed 184×60 terminal and centered 160×50 game grid. Its 54.483-second viewing copy fully decodes to 3,269 frames. A full-size frame and five populated contact-sheet tiles show katakana gameplay and HUD; the sixth tile is unused. Dim green scene values remain a known limitation. Original and copy remain under ignored `local/recordings/`; neither contains an audio stream.

`results/audio-integration-validation.json` passes 27 evidence checks and pins sixteen current source files, including fifteen standalone parses. The engine-dependent event class is exercised by the actual host. No owned game or recorder processes remain after these runs. The full Ultimate Doom release goal remains active.

Next: broaden menu/save/load/new-game/viewport timing qualification, reduce queue delay without hiding starvation, measure audible latency, add music with documented synthesis/instrument provenance, and record actual audiovisual output. The recorder can launch with `-Sound`, but its existing `-an` video path does not capture playback audio; footage is explicitly silent video until loopback capture is implemented.

## Reproducing the bounded experiments

Run in PowerShell 7.4 or newer from `C:\projects\pwshDoom`, using fresh report filenames:

```powershell
./scripts/Test-AudioMixer.ps1 -Output local/audio-unit.json
./scripts/Measure-AudioMixer.ps1 -Output local/audio-cost.json
./scripts/Render-AudioReplay.ps1 -Output local/audio-route.json
./scripts/Test-WaveOutPlayback.ps1 -Output local/audio-device.json -ReplayReport local/audio-route.json
```

The last command plays an eight-second segment through the current default output device. The replay script's default IWAD is the user's Steam Ultimate Doom installation; supply `-Wad` for a different legitimate path. It intentionally requires the existing eight-checkpoint route and has not been generalized to arbitrary save/new-game control-event fixtures.
