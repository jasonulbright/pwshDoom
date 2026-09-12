# Ordinary-input route development

E1M1, E1M2 and [E1M3 normal](campaign-e1m3.md) have completed input routes. The seventeenth E1M3 attempt passes independent replay and headless continuation into E1M4; its secret route and terminal playback remain open. None of the retained failures below is campaign qualification. All runs use the installed Ultimate Doom IWAD already pinned in the campaign matrix, HMP, a fresh pistol start and ordinary movement/turn/attack/use commands. The driver reads positions, sight and inventory to choose input; it does not teleport, apply damage, activate specials directly or alter game state. Independent qualification subsequently executes the fixed recorded input without those navigation or targeting queries.

`Export-CampaignMap.ps1` writes initial line/sector/thing data and a planning diagram under ignored `local/`. The diagram uses System.Drawing solely for documentation. The updated export includes explicit blocking flags, initial floor/ceiling heights and initially solid non-player/non-CountKill obstacles with their actual radii. A two-sided line can still block movement. Initial heights and obstacles do not describe subsequent triggered changes or destroyed barrels.

`Find-CampaignPath.ps1` supplies provisional planar guidance with PowerShell A*, a bounded number of visited grid points, bucketed wall lookup and square clearance at grid points and edge midpoints. It treats one-sided and explicitly blocking lines as walls and avoids exported initial solid decorations/barrels. The current grid is eight units, with a selectable sixteen-unit alternative. A sixteen-unit grid missed an offset narrow passage even though a finer grid found it. This planner does not solve floor height, closed/locked doors, lifts, moving actors, damage or timed triggers; successful search is not proof of a walkable route. Older geometry without the optional obstacle list is treated as wall-only input.

The first planning result failed during array construction. The next contained a bad diagonal-wall clearance calculation because integer Clamp bounds caused PowerShell overload selection to round a projection. Both failures and their exact source versions are retained in `results/campaign-path-before-*.ps1.txt`. The correction clips the line segment against an axis-aligned player square with explicit double precision. The original sixteen-unit corrected version is retained as `campaign-path-grid16.ps1.txt`, with its hash checked against the corresponding receipt. Actual input attempts remain the stronger validation.

## E1M3 findings and corrections

The initial annotation reversed the blue and yellow keys. **Thing type 6 at (-2688,-1728) is the yellow key; type 5 at (-160,-864) is blue.** `CardType`, the adopted `DoomInfo.MobjInfos` table and the actual collected card index agree. Earlier commentary and provisional ledger wording calling the western key blue are incorrect. The normal blue-locked door correctly refuses the yellow key; no engine fix is warranted.

| Retained attempt | Actual stop / result |
| --- | --- |
| `e1m3-route-first` / `second` | Starting-room walls; bad waypoints |
| `third` / `fourth` | Stairwell obstruction; raw line flags 29 identify an impassable window |
| `fifth` | Inaccessible approach to the door beyond the upper shotgun platform |
| `sixth` | Diagonal corridor wall on the attempted maze approach |
| `seventh` | Bad planner wall clearance; corrected separately |
| `eighth` | Maze door with initial floor equal to ceiling; its tag-10 switch had not been used |
| `ninth` | Tag-10 switch and yellow key obtained; player dies on the return trip |
| `tenth` | Survives return after pickup changes; blocked by a barrel near (-1280,-3024) |
| `eleventh` | Routes around the barrel; correctly denied by the blue-locked door |
| `twelfth` | Correct upper route reaches the horseshoe room; player dies before collecting blue key |
| `thirteenth` | Medkit detour blocked by a solid decorative column, raw thing type 48 at (-1760,-1056) |
| `fourteenth` | Column bypass and health pickups work; fixed replay identifies a fall into the horseshoe pit and repeated type-7 floor damage. Earlier stationary-combat diagnosis corrected. |
| `fifteenth` | Alternating combat strafing from the beginning causes an earlier death in the western approach; not an improvement |
| `sixteenth` | Avoids the damaging pit, obtains blue and reaches the exit area; real stair-building exception after 6,261 completed commands |
| `seventeenth` | Same route after stair fix completes in 6,931 commands with 66 health; independent continuation into E1M4 passes |
| `secret-first` | Direct start-room route encounters an initially closed/raised corridor |
| `secret-second` | Western pit-door approach fails in combat; not a secret exit |

Each report retains commands, periodic state/inventory, waypoint arrivals, errors, IWAD and source/plan hashes. Counts and timings are headless fixture data, not gameplay FPS. The fifteenth normal candidate uses the same medkit/column route with optional `-CombatStrafe`: player sidemove alternates between +24/-24 every 70 commands while facing a target, without changing damage, enemies or game state. Its early death rejects this setting as a general improvement. The later successful route uses a safer pickup/approach sequence that avoids the damaging pit. The driver now also records armor, the explicit iteration limit and the strafing option. Its previous source is retained as `results/campaign-route-before-strafe.ps1.txt` with the fourteenth report's exact source hash. The first six attempts used the default eighteen-unit tolerance and 10,000-iteration bound; seventh through eleventh and both secret attempts used six units and 10,000 iterations. Twelfth onward uses six units and 15,000 iterations. Strafing is off in all attempts before the fifteenth and remains off by default.

The secret route needs additional triggered-state planning. The actual exit is line 785, special 51. The northwestern switch at line 360, special 20/tag 27, targets the initial starting-room floor; this is source/map inspection, not proof that an input route has activated it and completed the secret exit. Normal exit line 982 has special 11.

## Independent continuation checks

`Qualify-CampaignRoute.ps1` now accepts `-ExpectedNextMap` and `-SecretExit`. It verifies actual exit kind and the advertised intermission destination before advancing with ordinary use presses, then checks the entered map, 71 destination tics, spawn inventory and secret history for a declared secret exit. A secret request requires an explicit destination. Defaults retain the normal next-numbered-map behavior.

The changed destination checker passes the existing E1M2 fixture: `results/e1m2-qualified-declared-destination.json` matches all 87 sampled states, 3,233 commands and 13 checkpoints and enters E1M3. That receipt predates the subsequent optional armor-sample comparison; that branch awaits qualification of a newer driver report. Actual E1M3 secret-route qualification remains pending; controller fixtures alone do not satisfy it.

Example commands, with fresh local output paths:

```powershell
./scripts/Export-CampaignMap.ps1 -Episode 1 -Map 3 -OutputPrefix ./local/my-e1m3
./scripts/Find-CampaignPath.ps1 -MapGeometry ./local/my-e1m3.json `
  -StartX -1888 -StartY -1568 -EndX -1760 -EndY -992 -Output ./local/my-path.json
./scripts/Test-CampaignRoute.ps1 -Route ./routes/e1m3-normal.json `
  -ArrivalDistance 6 -MaxTics 15000 -Output ./local/my-e1m3-route.json
```

Only after a route succeeds should it be independently qualified and recorded through the host. Music preparation for E1M4/E1M9 is separate, finite work; no live effect recording runs while that study synthesis competes for resources. Raw map geometry, generated diagrams, music payloads and movies stay local.

The [damaging-floor investigation](sector-damage.md) adds an independent fixed-command diagnosis and repairs a separate type-16 gameplay defect. All 512 hazard checks and both completed route regressions pass. The optional conservative planner now avoids initial hazard boundaries; the sixteenth candidate follows the upper walkway and omits the pit medkit. The sixteenth outcome is the stair exception described below.

Sixteenth reaches the blue key and exit-area approach with 58 health and 43 kills, then exposes a real [stair-building exception](stair-building.md), retained with 6,261 completed commands. Both direct stair variants reproduce it; a precedence correction passes 86 checks. Seventeenth completes the same route with that repair; all 198 trace samples and 24 checkpoints pass independent continuation into E1M4. Terminal playback and secret coverage remain open.
