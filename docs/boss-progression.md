# Ultimate Doom boss progression

2026-09-19. All 97 checks in `results/boss-progression-first.json` pass against the installed Ultimate Doom IWAD (SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`). No engine change was necessary.

The expected trigger selection follows id Software's [A_BossDeath](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/p_enemy.c): map and monster type select the action, another living boss of the same type blocks it, and a living player is required. E1M8/E4M8 lower tag-666 floors; E4M6 opens tag-666 doors at fast speed; E2M8/E3M8 request a normal level exit.

| Map | Verified result in this IWAD |
| --- | --- |
| E1M8 | Sector 30 floor reaches -136 units and releases its mover. |
| E2M8 | Final cyberdemon death-state action requests a normal exit. |
| E3M8 | Final spider mastermind death-state action requests a normal exit. |
| E4M6 | Sectors 37, 38, 39 and 41 open to ceiling height 84 at 8 units/tic and release their movers. |
| E4M8 | Sector 75 floor reaches -80 units and releases its mover. |

The test loads each real map at HMP. Explicit fixture edits set the boss health and test wrong monster type, wrong map, dead player, and an additional living same-type thinker. Every guard must leave level completion false and tagged geometry inactive. The final positive case enters the actual terminal death animation state with `Mobj.SetState`, exercising its action dispatch. It checks mover type, direction, speed and destination, then runs those actual movers to completion. Expected destinations are calculated independently from adjacent map-sector heights, rather than calling the engine's target-selection helper.

These are behavioral fixtures, not ordinary-input boss kills or completed maps. Health/type/map edits and the synthetic thinker are confined to these disposable test worlds. Other world actors do not run during the bounded mover checks. Combat, simultaneous damage, the full death animation timing, finale continuation and physical play remain separate requirements. The campaign completion matrix remains unqualified for all five maps. No terminal window, recording, audio device or performance measurement is involved.

Reproduce from PowerShell 7 with a fresh output path:

```powershell
.\scripts\Test-BossProgression.ps1 -Output .\local\my-boss-progression.json
```

The receipt pins the IWAD, built engine bundle and test source. Game data stays outside the repository.
