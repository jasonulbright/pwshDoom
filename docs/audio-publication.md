# Queue audio before drawing the session

Ordinary simulation tics now construct and enqueue their audio packet before automap discovery, replay checkpoints and UI/snapshot publication. The first packet of a new world retains the existing loading/epoch/renderer handoff before publication. Volume and pause state are refreshed at the point of publication. Gameplay, rendering, music and mixing algorithms are unchanged and remain PowerShell.

Previously, even a completed tic's audio waited behind independent presentation work. The new order lets the audio runspace work while the simulation prepares the image. It does not shorten the simulation tic itself or eliminate expensive UI work.

## Recorded result

One isolated actual Matrix route consumes all 1,747 ordinary commands, matches all eight established checkpoints, and returns every one of its 2,201,220 submitted audio frames with no canceled tail. Submitted PCM remains exactly `DB35F5D34C9206B8D47126FEF57070EB6D10BD0D3D3A302BC11269666288AD63`, matching the retained prior loading-boundary route. All 42 campaign recording checks and six independent publication-analysis checks pass.

There are **zero unexpected empty-queue observations before shutdown** in this trial. The final empty queue after packet 1746 remains reported. The intentional map-loading drain/pause remains, lasting 2,236.881 ms at the simulation boundary, including a 247.991 ms wait for the old audio tail. This is one successful trial, not a repeatability, acoustic-continuity or hardware-underrun guarantee.

| Measurement | Result |
| --- | ---: |
| Tics with audio queued before presentation work | 1,746 |
| Of those, intermission tics | 116 |
| Deferred new-world packet | Sequence 1675 |
| Update completion → enqueue, mean / p95 / max | 0.298 / 0.421 / 31.208 ms |
| Presentation work after enqueue, mean / p95 / max | 9.413 / 18.466 / 131.494 ms |
| Intermission presentation after enqueue, mean / max | 15.491 / 131.494 ms |
| Largest audio mix block | 67.954 ms |
| Largest packet age at device submission | 180.915 ms |
| Wall / active duration | 52.231 / 49.996 seconds |
| Completed console writes | 2,966 |

The trace records update-end, enqueue and presentation-start/end QPC for every tic. The analyzer checks their ordering, sequence coverage, identical IWAD and input commands, checkpoint matches and submitted PCM against the prior retained report. Presentation time overlapped with audio is not a measured reduction in physical speaker latency. Console writes and encoded movie FPS are not distinct displayed frames. Earlier isolated trials still contain failures and timing spikes; no comparison ranking or universal 35-tic/60-display guarantee follows.

The actual simulation-worker save/menu/new-game/load fixture also passes its 15 checks with qualified music (`results/save-worker-early-audio.json`). That is control regression coverage, not additional map completion. Renderer code and the Classic/Matrix/color-art encoders are unchanged; this new full-window recording is Matrix only.

## Evidence and reproduction

The portable results are `audio-publication-first.json`, `audio-route-early-audio-timing.json` and `music-route-early-audio-evidence.json`. Complete game/audio/capture/merge/source receipts are copied byte-identically into `results/music-route-early-audio-*.json`.

The actual full audiovisual movie is retained locally as `local/recordings/music-route-early-audio-av.mp4`, SHA-256 `54A7D365BE4148EB032638E39C68CDCF4274614195A40783C8D90DFAC8D61698`. Its real-time transition excerpt is `music-route-early-audio-transitions.mp4`, SHA-256 `9BD690113BD1B246649B29628BC1FEE3E43248DEB32FF5B50C464A2739C16498`. Both decode successfully. Sampled actual intermission/E1M2 frames preserve the existing low-contrast block UI and katakana gameplay. This is not a listening test. Media and user assets remain ignored and outside Git backup.

Use the [campaign recording command](campaign-music.md), then analyze fresh paths:

```powershell
./scripts/Analyze-AudioPublication.ps1 -GameReport ./local/recordings/my-route-game.json `
  -Baseline ./results/music-route-loading-boundary-game.json -Output ./local/my-publication.json
```

The analyzer is deliberately specific to the established 1,747-command/eight-checkpoint route. The subsequent [E1M2 qualification](campaign-e1m2.md) exposed a real queue overflow on a longer route. Producer waiting now prevents that failure, but its successful recording has 17 unexpected pre-shutdown empty queues. The single zero-starvation trial above must not be generalized. Repeated pacing trials, difficult scenes, full soundtrack, fidelity, physical controls and portability remain release work.
