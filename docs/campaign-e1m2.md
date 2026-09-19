# E1M2 normal-route qualification

E1M2 now has a completed HMP pistol-start route through normal input. The authored driver collects the shotgun and red key, uses the locked door and upper switch, and reaches the normal exit in 3,046 commands with 82 health and 21 kills. It does not use teleporting, direct damage, god mode or direct special activation. This is a normal-route fixture, not 100% kills/items/secrets, all difficulties or human play qualification.

`scripts/Export-CampaignMap.ps1` reads the installed map into a local planning diagram and geometry JSON. System.Drawing draws that documentation diagram only; it is not part of game rendering. Extracted geometry/images remain under ignored `local/`. Authored waypoint coordinates are in `routes/e1m2-normal.json`.

## Retained route development

| Attempt | Commands before stop | Health | Result |
| --- | ---: | ---: | --- |
| First | 969 | 100 | Wall before shotgun lift; side-corridor entry required |
| Second | 1,220 | 100 | Shotgun acquired; alcove's north wall blocks the proposed departure |
| Third | 2,058 | 100 | Red key acquired; waypoint crosses lower corridor edge |
| Fourth | 2,248 | 100 | Proposed waypoint lies inside a pillar |
| Fifth | 3,443 | 82 | Upper switch reached; waypoint cuts through the switch alcove |
| Sixth | 3,046 | 82 | Normal exit reached, 21 kills |

All six input streams, periodic position/inventory traces, waypoint arrivals and IWAD/plan/driver hashes remain in `results/e1m2-route-*.json`. The original driver source is retained in `results/campaign-route-driver-v1.ps1.txt`; the later driver adds timed facing/use holds for a switch. These were navigation-fixture errors; no engine change was needed to cross the map.

## Independent fixed-command replay

`Qualify-CampaignRoute.ps1` starts a fresh engine instance and feeds the successful recorded commands, without navigation or targeting queries. It matches all 87 sampled position, height, health, ammo, keys, weapon and kill states. This separates the authored driver's observed result from deterministic fixed-command execution.

Ordinary use presses then advance intermission and enter E1M3 for 71 tics. At next-map spawn, inventory remains 82 health, zero armor, 122 bullets and 13 shells. E1M3 completion is not claimed.

The qualified replay, `results/e1m2-qualified-replay.json`, contains 3,233 commands and 13 selected-state/render checkpoints. It exits E1M2 at tic 3046 and enters E1M3 at tic 3162. Checkpoints sample state; they are not complete thinker-graph or vanilla-demo equivalence.

## Recorded host qualification

The first AnsiArt recording attempt fails before simulation. The host-ready file is published just after the recorder's 35-second startup deadline; the game later times out at its capture gate with zero tics and closes its workers/audio cleanly. Failed game, input, source, clock and recording receipts are retained in `results/e1m2-color-first-*.json`. Its 48-byte movie is invalid startup output, not gameplay footage.

The recorder now gives readiness a separate bounded 60-second allowance, configurable from 15 to 180 seconds. Video/report deadlines include gameplay duration plus that startup allowance and 15 seconds of closing time. Scoped audio still starts after readiness and retains its existing gameplay-plus-35-second bound. The gameplay duration limit is now 240 seconds so this longer route can complete; default gameplay duration remains 90 seconds. An explicit `ReplayEnd` request checks all transitions at longer durations too.

The second AnsiArt run reaches tic 2238, then fails when the 32-packet audio queue fills. Seven checkpoints match before failure. The producer had already advanced game state before discovering that it could not enqueue that tic's audio. The failure receipts and actual failure footage are retained; manually muxing that footage does not turn it into a passing game run.

The simulation now waits before advancing another tic when the queue holds 31 packets. One slot remains for concurrent consumer semaphore bookkeeping. It returns through the control loop while waiting, so session requests and shutdown remain serviceable. The capacity stays 32; no command or audio packet is dropped. Each completed wait is recorded as AudioBackpressure, with an explicit unfinished-wait field. These waits remain in the active timing budget.

The third isolated AnsiArt recording passes all 42 checks in `results/e1m2-color-third-evidence.json`: all 3,233 commands, 13 independently selected checkpoints, both transitions, three score starts, and all 4,073,580 submitted audio frames returned with none canceled or unconsumed. Source snapshots pin the actual unchanged capture runtime. ReplaySourceMatches is false because the independent reference predates the host queue fix; direct checkpoint and input comparisons pass. This is not a claim that the reference ran identical host code.

The real burst fixture, `results/audio-backpressure-bursts-first.json`, passes eight checks with two unpaced 150-command batches, menu/resume at command 150, and actual audio playback. It exercises 123 completed waits totaling 2,108.139 ms, maximum 35.835 ms; queue high-water is 31. All 300 commands and 378,000 audio frames survive and return. The first menu acknowledgement includes execution of the intentionally queued batch; its 3,993.979 ms is not interactive menu latency. Resume acknowledges in 15.517 ms. Existing save/menu/new-game/load coverage also passes 15 checks in `save-worker-audio-backpressure.json`.

## Pacing and media limits

The recorded route contains 161 queue waits totaling 2,407.099 ms, maximum 29.097 ms, with no unfinished wait. Its 95.490 active / 98.279 wall seconds yield 33.857 simulation tics/sec and 59.074 console writes/sec active, or 57.398 writes/sec wall. These writes are not measured displayed FPS. This longer full-feature run does not meet a sustained 35-tic/60-display target.

There are 17 unexpected empty-queue observations before the final packet, plus the final shutdown observation. The intentional map loading boundary is 2,798.440 ms, including 955.680 ms draining prior audio. Exact sample accounting does not prove uninterrupted sound, short physical latency or acoustic fidelity. Submission PCM SHA-256 is `E3F83A18976BF6DB60D16A707770B3ED3EAE14FA9E1A173D3417DCFF1F2DD0CF`.

The full actual audiovisual movie, `local/recordings/e1m2-color-third-av.mp4`, decodes and has SHA-256 `BA14274134CCCA51965FD2002A4E4C93AF887405972149D90ACB2472BA9AC3B4`. The 9.512-second real-time transition excerpt, `e1m2-color-third-transitions.mp4`, also decodes; SHA-256 `76A4D564B7E22A21F16639CDA81BCB645EF92347BFBDEFD22AF7B3480051E100`. Sampled actual images show the block intermission screen and katakana E1M3 gameplay with the carried inventory in the block HUD. The intermission lettering remains low contrast and the glyph scene loses detail. This image review is not a listening or human-play test. Full source/game/capture/audio/mux receipts are copied byte-identically to `results/`; user assets and movies remain ignored locally, outside Git backup.

Classic/Matrix playback of this route, secret coverage, E1M3 completion, visual-reference fidelity, repeated pacing and the remaining campaign remain open. The route JSON retains its original candidate wording to preserve the qualified plan hash; the successful evidence above supersedes that provisional status.

## Reproduce

Use fresh output paths and the installed Steam IWAD, or supply `-Wad`:

```powershell
./scripts/Test-CampaignRoute.ps1 -Route ./routes/e1m2-normal.json -Output ./local/my-e1m2-route.json
./scripts/Qualify-CampaignRoute.ps1 -RouteResult ./local/my-e1m2-route.json -Output ./local/my-e1m2-replay.json
```

Recorded playback uses the [audiovisual capture prerequisites](audiovisual-recording.md) and a prepared catalog containing D_E1M2, D_INTER and D_E1M3. Both external capture and actual device playback have their explicitly documented boundaries; gameplay/rendering/mixing remain PowerShell.

September 19 lighting regression: a new full Classic recording passes 53 integration checks, preserving all 3,233 ordinary commands and 13 checkpoints through E1M3. All4,073,580 audio frames return, with two queue-empty observations. It averages 34.9768 tics/sec and 50.5017 console writes/sec; these are recorded-run measurements, not sustained 60-display certification. The first attempt failed at startup from a newly introduced helper import dependency; that was fixed and retained in the evidence. See [lighting implementation and full-host evidence](rendering-fidelity.md) and `results/e1m2-classic-lighting-recorded.json`.
