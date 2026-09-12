# Campaign qualification matrix

Updated from the completed smoke report dated 2026-09-11T00:50:32.9972562Z. Release sequence: Ultimate Doom, Doom II, then a MyHouse-based audit. See [roadmap](roadmap.md).

**Smoke: 36/36 passed at skill 3.** Each case loads the map, runs 35 idle simulation tics, and renders two complete 320×200 serial frames from two camera headings. A smoke pass is not a completed level or visual-reference match. Headless stage timings are not gameplay FPS.

Source/IWAD hashes and detailed results: [results/campaign-smoke-lineflags-fixed.json](../results/campaign-smoke-lineflags-fixed.json).

E1M1 has an [input-only completion report](../results/e1m1-route-lineflags.json) with 1560 commands. That route ends at intermission; it does not qualify next-level presentation or a whole episode. Other maps still need completion evidence. The route harness targets E1M1/HMP; source-version matching is checked separately in the campaign validation report.

The [save/load core](save-load.md) now preserves the E1M1 → intermission → E1M2 input route across reconstruction and a fresh PowerShell process. Death/respawn and all four finale boundaries pass explicit save fixtures. These add state-continuation coverage; map-completion and terminal-host entries below retain their existing scope.

The integrated host also loads an intermission save, advances to E1M2, then loads an E3M8 finale save with acknowledged worker/asset generations. Its [448-command replay](../results/save-host-session-edges-replayed.json) matches six checkpoints. E3M8 ending playback here starts from an explicit fixture; its boss exit and map completion remain unqualified.

| Map | Load / idle simulation / two frames | Input-only completion | Transition / ending |
| --- | --- | --- | --- |
| E1M1 | Pass | Pass, HMP | Pass: real intermission -> E1M2 |
| E1M2 | Pass | Untested | Entered/rendered; exit untested |
| E1M3 | Pass | Untested | Untested in terminal host |
| E1M4 | Pass | Untested | Untested in terminal host |
| E1M5 | Pass | Untested | Untested in terminal host |
| E1M6 | Pass | Untested | Untested in terminal host |
| E1M7 | Pass | Untested | Untested in terminal host |
| E1M8 | Pass | Untested | Untested in terminal host |
| E1M9 | Pass | Untested | Untested in terminal host |
| E2M1 | Pass | Untested | Untested in terminal host |
| E2M2 | Pass | Untested | Untested in terminal host |
| E2M3 | Pass | Untested | Untested in terminal host |
| E2M4 | Pass | Untested | Untested in terminal host |
| E2M5 | Pass | Untested | Untested in terminal host |
| E2M6 | Pass | Untested | Untested in terminal host |
| E2M7 | Pass | Untested | Untested in terminal host |
| E2M8 | Pass | Untested | Untested in terminal host |
| E2M9 | Pass | Untested | Untested in terminal host |
| E3M1 | Pass | Untested | Untested in terminal host |
| E3M2 | Pass | Untested | Untested in terminal host |
| E3M3 | Pass | Untested | Untested in terminal host |
| E3M4 | Pass | Untested | Untested in terminal host |
| E3M5 | Pass | Untested | Untested in terminal host |
| E3M6 | Pass | Untested | Untested in terminal host |
| E3M7 | Pass | Untested | Untested in terminal host |
| E3M8 | Pass | Untested | Untested in terminal host |
| E3M9 | Pass | Untested | Untested in terminal host |
| E4M1 | Pass | Untested | Untested in terminal host |
| E4M2 | Pass | Untested | Untested in terminal host |
| E4M3 | Pass | Untested | Untested in terminal host |
| E4M4 | Pass | Untested | Untested in terminal host |
| E4M5 | Pass | Untested | Untested in terminal host |
| E4M6 | Pass | Untested | Untested in terminal host |
| E4M7 | Pass | Untested | Untested in terminal host |
| E4M8 | Pass | Untested | Untested in terminal host |
| E4M9 | Pass | Untested | Untested in terminal host |

## Current blockers and next work

- [Recorded terminal session](../results/session-recorded-classic-game.json) verifies E1M1 intermission -> E1M2 and map-asset generation refresh. E1M2 completion and other terminal transitions remain unqualified.
- Isolated controller fixtures verify episode finales, all four secret returns, par units, secret-visit history, inventory carryover and death/respawn. See results/campaign-transitions-session.json. Fixtures do not qualify map playthroughs or boss-triggered exits.
- Add ordinary-input recording and completion routes for the remaining maps, including normal/secret paths and boss-triggered effects. Keep targeted state fixtures separate from playthrough evidence.
- Save/load has the bounded coverage above. Physical controls, audio, automap, harder scenes, visual fidelity, other difficulties, and 1080p hardware still need their own validation.
- Doom II and MyHouse coverage has not started. MyHouse requires a version-pinned package/feature audit before choosing an extension scope.

The initial sweep failed E2M7 because an enum conversion rejected extra line-flag bits. The raw failure and synthetic before/after tests remain in results/campaign-smoke-baseline.json and results/line-flags-*.json; the fix preserves the bitfield rather than deleting unknown bits.

The numeric automap discovery follow-up preserves all eight legacy checkpoints
and matches discovered-line sets at 48 sampled poses on the established
E1M1/intermission/E1M2 route (`results/automap-numeric-route.json`). This adds
regression coverage; it does not add another completed map to the campaign matrix.

Persistent input preferences now have isolated storage/command tests and actual
host restart/recovery coverage. Replays bypass preference-based command generation;
three settings-menu recordings preserve the existing control fixture checkpoints.
This UI work adds no map completion to the matrix. See [settings](settings.md).

Music integration currently has E1M1 and E1M2 qualified loops. E1M1's longer-bound source requalification preserves every prior sample; E1M2 passes continuous recurrence and six long-reader checks. Intermission qualification remains active. Eight-second E1M1 audiovisual captures now pass in all three styles with 88 recording-evidence checks. No additional campaign route or completed map is claimed. See [music integration](music-integration.md) and [audiovisual capture evidence](audiovisual-recording.md).
