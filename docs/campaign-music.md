# Recorded campaign transitions with music

The established E1M1 → intermission → E1M2 ordinary-input route now runs with qualified music and effects in actual recorded terminal windows. It still completes E1M1 only; entering and briefly playing E1M2 is not E1M2 completion. The full Ultimate Doom release remains unfinished.

## Functional result and exact timing

Each of three recorded runs consumes all 1,747 commands from `results/input-session-replay.json`, matches its eight historical checkpoints, and returns all 2,201,220 submitted audio frames. No command is replaced by direct state edits. Gameplay, music synthesis and mixing remain PowerShell; scoped Windows audio capture and external video encoding use the documented device/tool boundary.

E1M1/intermission/E1M2 selections consume the successful pinned qualifications. The audio worker records:

| Event | Music frames already advanced | Reason |
| --- | ---: | --- |
| Start D_E1M1 | 0 | Initial map synchronization before the first packet |
| Start D_INTER | 1,965,600 | First intermission Update, after entry at completed tic 1,560 |
| Reset old audio epoch | 2,110,500 | Map asset publication pauses/resets the old selection |
| Start D_E1M2 | 2,110,500 | New-world callback, in the packet for completed tic 1,676 |

The first evidence audit incorrectly expected only three total events and intermission music on the entry tick. Its failure is retained as `music-route-matrix-evidence-first.json`. Inspection of `Intermission.Update` (`bgCount=1`), world construction and `Publish-SimulationMapChange` explains the existing behavior. The corrected audit checks all four events explicitly; it does not change the game to fit its original expectation. The original auditor fingerprint remains in the pre-run snapshot; the corrected post-run auditor is hashed separately from runtime sources.

## Actual recordings and readability

| Run | Source UI behavior | Evidence checks | Writes | Wall seconds | Largest mix block, ms | Largest packet submission age, ms | Pre-shutdown starvation observations |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Matrix, initial | Katakana intermission | 34 | 3,027 | 52.107 | 39.643 | 234.945 | 3 |
| Matrix, revised | Green block intermission | 36 | 3,009 | 52.313 | 78.929 | 320.166 | 4 |
| Color-art, revised | Original-color block intermission | 36 | 2,970 | 52.527 | 69.278 | 293.072 | 4 |

The initial intermission image was unreadable character noise. Intermission/finale screen jobs now use the existing menu block encoder in character modes. Sampled revised footage shows recognizable HANGAR/FINISHED and KILLS/ITEMS/SECRET labels. Color-art preserves the original title colors; Matrix stays green with lower contrast. E1M2 remains katakana gameplay with the existing block HUD. Classic encoding is unchanged. General finale readability, fonts, DPI and 1080p sizing still require qualification.

Both character modes pass the seven-worker screen/menu/automap/map-reload fixture, each comparing 256,000 pixels and 28 encoded strips without restarting workers. The existing menu tests pass 125 checks and 46 screen fixtures; the independent character codec suite also passes. See [character modes](character-modes.md). Those checks support the encoding/transport change, not full rendering fidelity.

Full-window audiovisual movies remain under ignored `local/recordings/`:

```text
music-route-matrix-first-av.mp4
  A06659A994C21285F20A5A05BC3C43BC7749B94010D997AE097B44A07A450D13
music-route-matrix-ui-av.mp4
  C09CC7E7D03400D8A5EDD022AFA2A6FC1953E5C3DBB06F408240BB1E6759A1C8
music-route-color-ui-av.mp4
  EF9714380BC46A5D7E063986BB3688D7D6238532C3BA2309FDD129B663B3F01F
```

Corresponding `-transitions.mp4` excerpts preserve the actual map-handoff time and full window. Their exact offsets, durations and hashes are in `results/music-route-*-viewing.json`. Full movies and excerpts decode successfully. The recording pipeline preserves compressed video packets and clocks while placing captured PCM on the original WGC QPC timeline; see [audiovisual recording](audiovisual-recording.md). Sampled visual review does not establish human listening or physical screen/speaker synchronization.

Complete game/capture/audio/merge/source receipts are copied byte-identically into `results/music-route-*.json`. Commercial assets, generated sound and video remain local and outside Git backup.

## Open audio and pacing issue

All three recordings overlap E1M3 preparation. They are correctness/readability observations, not clean paired performance trials. Console writes and encoded 60 fps are not proof of 60 distinct displayed updates. Source state/checkpoint equivalence does not establish acoustic continuity.

Initial Matrix starvation polls occur after packets 310, 1674 and 1677. Revised Matrix and color-art both report polls after 313, 316, 1674 and 1684. These include a repeatable early-game region and the map handoff. They are queue observations, not hardware underrun telemetry, and cause remains unclassified. Returning every submitted frame does not imply timely continuous playback. The next timing experiment should repeat this workload without synthesis/build/test contention, retain capture instrumentation and inspect simulation lateness and audio queue behavior before changing buffer sizes or scheduling.

## Reproduce

Prepare a local catalog for D_E1M1, D_INTER and D_E1M2 using [music preparation](music-preparation.md), plus the [diagnostic capture prerequisites](audiovisual-recording.md). Use fresh paths:

```powershell
./scripts/Record-DoomReplay.ps1 -Style Matrix -Seconds 90 -ExpectedExit ReplayEnd `
  -Replay ./results/input-session-replay.json -CaptureAudio `
  -MusicCatalog ./local/my-route-music.json `
  -Ffmpeg ./local/tools/capture-build/FFmpeg-n9.0.1/ffmpeg.exe `
  -MediaFfmpeg ./local/tools/ffmpeg/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe `
  -OutputPrefix ./local/recordings/my-music-route
./scripts/Export-MusicRouteClip.ps1 -Prefix ./local/recordings/my-music-route `
  -Output ./local/my-route-viewing.json
```

Use `AnsiArt` for color-art. `Test-MusicRouteEvidence.ps1` additionally requires a pre-run `<prefix>-route-sources.json` source snapshot; the retained examples list the runtime paths. This research verifier deliberately targets the named 1,747-command/eight-checkpoint route and is not a general campaign-completion test.
