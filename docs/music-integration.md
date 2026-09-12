# Qualified music in the audio worker and game host

Music can now run through the persistent audio worker alongside effects using an explicitly supplied catalog of qualified tracks. E1M1 is the only real track qualified so far. This is opt-in integration, not a complete soundtrack release. The normal `-Sound` path remains effects-only.

## Catalog and commands

`MusicPlayback.ps1` opens a catalog of qualified readers at worker startup. Each reader validates its source/runtime identity and the complete cached payloads before playback. The simulation process additionally verifies that each catalog track's MUS hash matches the score in the active IWAD. Relative report paths are resolved against the catalog's directory. No asset is supplied by the repository.

Packets can carry numeric/string-only music commands: start a named qualified loop, stop, or set explicit music gain. Start resets the selected track to frame zero unless a validated start offset is supplied. The entire command batch is validated before selection, gain or cursor changes. Missing tracks, unqualified one-shot requests, invalid offsets and nonfinite gains fail explicitly; another track is never substituted.

The audio worker owns all music readers and file handles. Shared pause prevents packet consumption; engine pause packets stop both music and effect advancement. Master mute still advances active music and effects while producing zero output. Effects volume and the explicit music gain are multiplied by the same master control at final mixing. Epoch changes stop the old selection before a future session packet can select new music. Stop/disposal closes every reader and the device.

The reader caches one decoded page per opened track as it is used, at most 25,200 stereo frames per reader. The device still has four 1,260-frame buffers. There is no separate music prefetch thread yet; page reads occur in the audio runspace while existing device buffers play. Queue/starvation and block costs are measured without treating them as hardware underrun telemetry.

## Engine callbacks and save/load

`MusicEvents.ps1` implements the retained engine's `IMusic` callbacks and maps `Bgm` names to `D_` lumps. Initial startup attaches the adapter after warm-up and synchronizes the actual starting map. Subsequent world, intermission and finale callbacks enqueue track selections with their original loop flags. Successful save loads synchronize the restored Ultimate Doom level/intermission/finale stage after committing the reconstructed game. The existing epoch reset clears old audio before the new selection is consumed. Music position itself is not serialized: a successful load restarts its appropriate score.

An initial adapter used a backing property named `Volume`. In this PowerShell class, the generated property accessor bypassed the intended `set_Volume` method: diagnostic calls left the value at -5 and emitted no commands. The first two failed reports are retained. Renaming the backing field to `StoredVolume` fixes method dispatch; full-volume gain is also calculated as `.2 * (volume / 15)` to preserve the exact default .2 endpoint. Eleven adapter/catalog checks pass, including actual world initialization, destructive event draining, clamp/gain commands, Ultimate Doom finale-stage selection and active-IWAD identity rejection.

One-shot opening music and Doom II finale restoration remain unqualified. Non-E1M1 selection tests verify callback routing only, not playback of those tracks. The incomplete catalog must be expanded before a normal campaign can run with music enabled throughout.

## Evidence so far

- Thirteen persistent-catalog checks pass, including an exact file-slice comparison across the real intro/loop boundary, atomic rejection, restart, epoch reset, stop and cleanup.
- Ten actual audio-worker checks pass. The fixture plays four seconds of submitted audio, starting near E1M1's 96-second boundary, with a quiet synthetic effect, packet/shared pauses, separate music gain, master mute, a future epoch packet, stop and restart. Every submitted PCM byte matches an independently scheduled offline result. All 140 packets and 176,400 submitted frames are accounted for; 161,280 music frames advance, including muted music. Device reset can cancel queued tails, so submitted PCM is not acoustic waveform evidence.
- The existing six-check effects-only runspace test passes with the expanded worker.
- A six-second headless Matrix host run completes without error. Its final simulation report records 209 tics/audio packets, all 263,340 submitted frames returned, and one initial E1M1 start. The host's earlier final snapshot reports 206 tics; these counters have different observation boundaries. Music and renderer workers execute concurrently, but this short run does not qualify sustained performance. Its maximum observed mix block is 54.041 ms; the single recorded starvation observation is after the final packet, during shutdown.
- Fifteen actual save-worker checks pass with the E1M1 catalog and same-episode new game, including failed-save/load isolation, numeric save restoration, immutable replay archives, three epoch resets, music consumption and clean closure. This explicitly uses episode one because other music tracks are not yet qualified; the existing default test still switches to episode two for effects-only runs.

Actual device tests exercise Windows `waveOut`. No microphone or desktop loopback is captured by those tests. Acoustic latency, a full audiovisual recording, playback under longer game/render load and complete track availability remain open.

The subsequent visible eight-second Matrix run also succeeds, with 279 simulation/audio packets and all 351,540 submitted frames returned. Its maximum observed mix block is 35.086 ms, and the only starvation poll is after the final packet. The host completes 480 writes; these are not measured distinct display updates. The recorder excludes one preexisting Terminal window and captures the new game window. The preexisting Terminal remains after the game closes.

Original footage is `local/recordings/music-matrix-first.mp4`, SHA-256 `69E7B38F716745547A737721633482DAE1E8F4CE3BDCB4E6E84BD66983C378DC`, 1472×1006 with 2,266 frames and 37.766 seconds including startup. A six-second viewing copy is `local/recordings/music-matrix-first-play.mp4`, 360 frames at the same size. Both fully decode. The inspected gameplay frame shows katakana geometry and HUD with the existing dark-green shading; this is a sampled visual review, not inspection of every frame. Neither video has an audio stream. `music-live-recording.json` pins both media hashes and the extraction timing; original footage is retained.

Byte-identical copies of the full live game report and recorder metadata are backed up as `results/music-live-game.json` and `results/music-live-capture.json`. Video/audio assets remain local; these portable measurements and hashes are included in Git.

`music-integration-validation-final.json` passes 51 evidence checks covering targeted device/catalog/callback/save tests, complete independent worker PCM, host frame accounting, recorded window selection, media hashes, explicit silent-video labeling, current source checks and parses. All finite study processes and owned file/device handles close. This establishes E1M1 integration, not a complete soundtrack or campaign release.

## Run the current E1M1 integration

Create a local JSON catalog mapping `D_E1M1` to the absolute path of `results/music-loop-e1m1-first.json`. `Test-MusicEvents.ps1` currently creates `local/music-catalog-e1m1.json` for this workspace. Then:

```powershell
./Start-Doom.ps1 -Style Matrix -MusicCatalog ./local/music-catalog-e1m1.json
```

Supplying a catalog enables sound playback automatically. It does not prepare missing tracks, and leaving E1M1 will require the destination/intermission qualifications. Use ordinary `-Sound` for a session that should retain effects-only behavior while the soundtrack is completed.

`Record-DoomReplay.ps1` forwards the catalog and records its hash. Its window targeting now excludes every preexisting visible Terminal window and selects the newly created `pwshDoom` window. Existing Terminal windows can remain open. The recorder captures only that game window, and still explicitly produces silent video until loopback audio capture is implemented.
