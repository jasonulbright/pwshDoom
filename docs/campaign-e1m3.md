# E1M3 normal route qualification

Measured 2026-09-12 with the installed Steam Ultimate Doom IWAD, SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`.

The seventeenth HMP pistol-start candidate reaches E1M3's normal exit with 6,931 ordinary commands and 66 health. Its final periodic sample has 48 kills, 80 armor, 82 bullets, four shells and the blue card. This is a fresh start on E1M3, not a continuous E1M1–E1M3 playthrough or a secret-route qualification.

`routes/e1m3-normal.json` obtains western weapons/armor, visits the northern medkit, follows the horseshoe walkway around the damaging pit, collects the northeast blue key and returns to the blue door and exit stairs. The driver uses ordinary movement, turning, firing and use commands, with six-unit arrival tolerance, a 15,000-iteration bound and combat strafing off. Geometry informs provisional waypoints; no player relocation, god mode, direct damage or special activation is used in the route.

The [route investigation](campaign-routing.md) retains sixteen normal failures and two failed secret candidates. A [fixed replay diagnosis](sector-damage.md) corrected the earlier claim that the fourteenth route died from stationary combat: it fell into a damaging pit. The sixteenth corrected route reached the exit area and exposed a real [stair-building exception](stair-building.md). The seventeenth uses the same route after the stair guard repair. The separate type-16 damaging-floor repair is also present; neither fix makes hazards or stairs easier than their intended semantics.

| Evidence | Scope |
| --- | --- |
| `results/e1m3-route-seventeenth.json` | Successful ordinary-input driver; 6,931 commands and 198 periodic samples. |
| `results/e1m3-qualified-replay.json` | All 198 periodic samples match, including armor. 7,118 fixed commands, 24 checkpoints, normal intermission and inventory-preserving continuation into E1M4 pass. |

The independent replay enters intermission at command 6,931, E1M4 at 7,047, and runs 71 destination tics. Spawn inventory remains 66 health, 80 armor, 82 bullets and four shells. Replay SHA-256: `A9E3E3E48DF5A483D904A412E3AF7A872ED5B5862713A331DC3310007AA09970`. The receipt pins the current implementation source separately from its selected-state checkpoints.

No E1M3 live terminal recording, audio playback, display pacing, secret exit, E1M9 return, harder difficulty or human playthrough is qualified by this headless result. The current route wording remains provisional in its JSON to preserve the plan hash. The successful receipt establishes its narrower measured behavior.

The September 19 Matrix recording failed with a full input-command ring after about 59.8 active seconds. The [command-admission investigation](command-admission.md) retains the footage and failure evidence, then verifies a bounded 1,200-command headless prefix with all four checkpoints and all audio frames returned. It still runs at only 19.424 ticks/sec; full recorded E1M3 completion remains open.

Reproduce with fresh paths and PowerShell 7 (or supply another user-local IWAD with `-Wad`):

```powershell
./scripts/Test-CampaignRoute.ps1 -Route ./routes/e1m3-normal.json -ArrivalDistance 6 -MaxTics 15000 -Output ./local/my-e1m3-route.json
./scripts/Qualify-CampaignRoute.ps1 -RouteResult ./local/my-e1m3-route.json -Output ./local/my-e1m3-replay.json
```
