# E1M4 normal completion

2026-09-19. The seventh HMP pistol-start candidate completes E1M4 with **6,161 ordinary commands**, 77 health, 168 armor and twelve shells. A fresh independent replay verifies all **176 periodic samples**, including sector/floor state, and the exact command at which the player acquires a shotgun. It then advances through intermission into E1M5 with exit inventory preserved. The initial qualification was headless; the later recorded-host result is documented below. Whole-episode qualification remains open.

The driver now has an optional `CollectDroppedWeapons` behavior. It seeks a visible dropped shotgun or chaingun that the player does not own, within 160 units and 24 height units, by turning and walking normally. Each drop receives at most 140 steering commands; enemies within 64 units retain combat priority. It never grants inventory or alters the world. E1M4's actual dropped shotgun is collected at command **1,356**, after 27 steering commands. An enemy's initial spawn position was not a reliable pickup location in the earlier route attempts.

The route uses the northern platform/armor, central blue key and western yellow key. Its final approach explicitly uses the bridge switch and climbs the eastern staircase before crossing west to the exit. The sixth candidate had survived with both keys but tried to cross a 64-unit ledge directly; correcting the route required no collision or gameplay change. The [investigation](campaign-e1m4-investigation.md) retains the six failed candidates and their distinct causes.

| Evidence | Scope |
| --- | --- |
| `results/e1m4-route-seventh.json` | Successful ordinary-input route; 6,161 commands, 176 periodic samples and recorded dropped-weapon acquisition. |
| `results/e1m4-qualified-replay.json` | 6,348 fixed commands, 22 selected-state checkpoints, all 176 samples and one acquisition check pass; intermission and E1M5 entry preserve inventory. |
| `results/e1m4-altered-pickup-rejection.json` | Negative check: unchanged route inputs with the pickup claim shifted to command 1,355 are rejected at that exact command. This is an expected verifier rejection, not a gameplay failure. |

Intermission starts at command 6,161 and E1M5 at 6,277; the replay includes 71 destination tics. Spawn inventory is 77 health, 168 armor, zero bullets and twelve shells. Replay SHA-256: `3DDB764D06A8C54ADA8FA05EBAA803932433CB91BF4046D08E8755D9B8BF129B`.

Reproduce with fresh output paths in PowerShell 7:

```powershell
./scripts/Test-CampaignRoute.ps1 -Route ./routes/e1m4-normal.json -CollectDroppedWeapons -ArrivalDistance 6 -MaxTics 15000 -Output ./local/my-e1m4-route.json
./scripts/Qualify-CampaignRoute.ps1 -RouteResult ./local/my-e1m4-route.json -Output ./local/my-e1m4-replay.json
```

The route JSON retains its candidate wording to preserve the measured plan hash; the completed receipts establish qualification. A continuous E1M1–E1M4 playthrough, physical controls, live terminal presentation, E1M4-to-E1M5 music/capture and harder difficulties remain unqualified. E1M5 music preparation subsequently completed with full recurring-state/output verification. The driver and qualifier ran alongside preparation, so their wall times are not performance measurements.

`results/e1m4-qualification-audit.json` additionally confirms the current plan/driver/qualifier source pins, positive/negative receipt consistency, and exact weapon-array carryover between the exit and E1M5-entry checkpoints.

## Recorded color-art continuation

The first full E1M4-to-E1M5 AnsiArt/katakana recording now passes all **51 integration checks** (`results/e1m4-ansiart-first-recorded.json`). It consumes all 6,348 unchanged commands, matches all 22 independent checkpoints, preserves exit inventory and renders the E1M5 generation. Music starts D_E1M4, D_INTER and D_E1M5 at the expected packets; all 7,998,480 submitted audio frames return before device closure, with no canceled or stale tail. This run includes the corrected HUD. Gameplay, intermission and E1M5 entry were inspected in sampled footage; a full physical play/listening review remains outstanding.

The 16-worker maximized run uses a 430x85 terminal grid with a centered 160x50 character image and zero resize pauses. Captured window size is 3440x1392. It averages **34.250 simulation tics/sec** and **50.491 console writes/sec** over 185.341 active seconds (188.097 host wall seconds, excluding earlier startup). The delivered movie includes startup and lasts 228.650 seconds. It is encoded at 60 fps, which does not establish 60 distinct displayed images. There were no concurrent study workloads during recording, but recording itself adds load and this is not a controlled before/after speed comparison.

Consecutive console-write gaps have nearest-rank p50/p95/p99 of 19.112/28.273/34.062 ms and maximum 2,801.193 ms, including map transitions. The separately labeled same-world subset has p50/p95/p99 of 19.129/28.197/33.808 ms and maximum 215.250 ms. These gaps differ from the overlapping render-pipeline latency reported as FrameMs. Six software audio-queue-empty observations remain. The capture reports no API discontinuity packets, but timeline alignment inserts 3,370 interior zero frames (76.42 ms) in three intervals, plus 1,647,834 leading zero frames before scoped capture. Buffer return and those capture observations do not prove uninterrupted sound at the speakers.

The portable timing summary is `results/e1m4-ansiart-first-timing.json`, generated by `scripts/Summarize-CampaignCapture.ps1`. Its full gap mean and count additionally agree with an independent first/last-QPC calculation. The original game/capture/PCM receipts stay under `local/recordings/e1m4-ansiart-first*`, with hashes in the audit. The full delivered movie is `local/recordings/e1m4-ansiart-first-av.mp4`; `e1m4-ansiart-first-preview.mp4` is a 20-second cropped viewing excerpt from seconds 60–80, preserving the original separately. The preview decodes fully and its crop was visually checked. Metadata is `results/e1m4-ansiart-first-preview.json`.