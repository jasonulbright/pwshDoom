# Damaging-floor fidelity correction

Measured 2026-09-12 against the installed Ultimate Doom IWAD, SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`.

The adopted PowerShell `PlayerInSpecialSector` had an empty `16 {}` case preceding the type-4 handler. PowerShell does not fall through between these cases. Type 16 therefore neither damaged the player nor consumed the radiation-suit leak random byte. This defect is also present in the pinned upstream PowerShell source; the repair is an adaptation, not an original Doom feature.

Original id Software [P_PlayerInSpecialSector](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/p_spec.c#L944-L1004) shares the type-16/type-4 damage branch: grounded players receive 20 damage at level-time multiples of 32, subject to radiation-suit protection and its random leak. With a suit, the leak draw occurs even between damage boundaries. Airborne players return before that draw. The repair selects the existing adopted branch for both values, preserving its condition order.

`scripts/Test-SectorDamage.ps1` uses real E1M1 world/player/sector objects and the actual damage method. It sets isolated fixture state explicitly; this is not campaign completion. Its 512 assertions cover player and actor health, last damage source, and random index for types 5, 7, 4 and 16; tics 31, 32, 33 and 64; grounded/airborne players; suits absent/present; and deterministic protected/leaking draws. DamageMobj's own pain-check draw is included.

| Receipt | Result |
| --- | --- |
| `results/sector-damage-before.json` | Initial test oracle omitted the pain draw; 40 assertions fail. Exact initial harness retained in `results/sector-damage-initial-harness.ps1.txt`. This is not a valid engine-failure count. |
| `results/sector-damage-before-corrected-harness.json` | Corrected oracle, unchanged engine: 30 of 512 fail, all type 16. |
| `results/sector-damage-after.json` | Same corrected harness, repaired engine: all 512 pass. |
| `results/e1m1-session-sector-damage.json` | Existing fixed E1M1 inputs still complete, advance through intermission and run 71 tics in E1M2; 1,747 total commands and spawn inventory preserved. |
| `results/e1m2-qualified-sector-damage.json` | All 87 original route samples still match; 3,233 commands, 13 checkpoints and inventory-preserving E1M3 entry pass. |

This changes gameplay in type-16 sectors and can change later random-number ordering. Historical recordings remain evidence for their pinned source, not automatically for this correction. The two route regressions above pass; the full campaign and full vanilla demo fidelity remain unqualified. No live effect window or new performance measurement was used for these checks.

## Separate E1M3 route diagnosis

`scripts/Inspect-CampaignFailure.ps1` replays the fourteenth failed route without the navigation driver. All 3,392 commands and 96 original position/health/height samples reproduce (`results/e1m3-fourteenth-damage-diagnostic.json`, engine before this repair).

The player falls into sector 48 at command 2,740; its floor is -32 versus the surrounding walkway's 88, a 120-unit climb. Later damage repeats every 32 commands, with a null last attacker and the player grounded on special 7. Five damage becomes four health lost plus one armor absorbed. The final damage is environmental. The previous ledger's classification as prolonged stationary combat was inaccurate, although combat did occur earlier in the run. End-of-tic attacker reporting is not instrumentation of every source within a tic.

The planner previously considered walls and initial solid objects, but ignored floor heights and hazards. A conservative optional `-AvoidDamagingFloors` now treats initial hazard boundaries as walls. It does not model later moving floors, lifts, all step heights, or prove that a starting point lies outside a hazard. The sixteenth candidate removes the pit medkit detour and follows guidance around the upper walkway. Only an actual input run can qualify that route; a found planning path is not completion.
