# PowerShell audio investigation

The normal terminal game remains silent. The first audio foundation implements game sound-event capture, DMX decoding, stereo positioning, linear resampling and mixing in PowerShell, plus a tested Windows playback queue. Music and live host integration remain open release requirements.

## Implementation boundary

`src/AudioEvents.ps1` implements the retained engine's `ISound` callbacks without consuming gameplay RNG. It records start/stop/reset/pause/resume events and assigns reference-based numeric emitter IDs. The offline adapter updates gains from current listener/emitter positions once per tic. Its source registry currently lasts until level reset; bounded emitter lifecycle and destroyed/moving-source semantics require qualification before live use.

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

No live game/window test occurred in this milestone. The WAV is derived from the user's local IWAD and is excluded from Git. There is no claim that existing screen recordings contain this audio.

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

Next: decide an explicit bounded audio-worker/event transport, measure deadlines with the renderer running, integrate host pause/menu/save/load/reset semantics and volume settings, then implement music with documented synthesis and instrument provenance. Capture actual audiovisual runs once that path exists. Do not place this workload on the simulation thread and assume the existing 35/60 targets survive.

## Reproducing the bounded experiments

Run in PowerShell 7.4 or newer from `C:\projects\pwshDoom`, using fresh report filenames:

```powershell
./scripts/Test-AudioMixer.ps1 -Output local/audio-unit.json
./scripts/Measure-AudioMixer.ps1 -Output local/audio-cost.json
./scripts/Render-AudioReplay.ps1 -Output local/audio-route.json
./scripts/Test-WaveOutPlayback.ps1 -Output local/audio-device.json -ReplayReport local/audio-route.json
```

The last command plays an eight-second segment through the current default output device. The replay script's default IWAD is the user's Steam Ultimate Doom installation; supply `-Wad` for a different legitimate path. It intentionally requires the existing eight-checkpoint route and has not been generalized to arbitrary save/new-game control-event fixtures.
