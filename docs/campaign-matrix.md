# Campaign qualification matrix

Updated from the completed smoke report dated 2026-09-11T00:50:32.9972562Z. Release sequence: Ultimate Doom, Doom II, then a MyHouse-based audit. See [roadmap](roadmap.md).

**Smoke: 36/36 passed at skill 3.** Each case loads the map, runs 35 idle simulation tics, and renders two complete 320×200 serial frames from two camera headings. A smoke pass is not a completed level or visual-reference match. Headless stage timings are not gameplay FPS.

Source/IWAD hashes and detailed results: [results/campaign-smoke-lineflags-fixed.json](../results/campaign-smoke-lineflags-fixed.json).

E1M1 has an [input-only completion report](../results/e1m1-route-lineflags.json) with 1560 commands. That route ends at intermission; it does not qualify next-level presentation or a whole episode. Other maps still need completion evidence. The route harness targets E1M1/HMP; source-version matching is checked separately in the campaign validation report.

The [save/load core](save-load.md) now preserves the E1M1 → intermission → E1M2 input route across reconstruction and a fresh PowerShell process. Death/respawn and all four finale boundaries pass explicit save fixtures. These add state-continuation coverage; map-completion and terminal-host entries below retain their existing scope.

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
- Physical controls, audio, save/load, automap, harder scenes, visual fidelity, other difficulties, and 1080p hardware need their own validation.
- Doom II and MyHouse coverage has not started. MyHouse requires a version-pinned package/feature audit before choosing an extension scope.

The initial sweep failed E2M7 because an enum conversion rejected extra line-flag bits. The raw failure and synthetic before/after tests remain in results/campaign-smoke-baseline.json and results/line-flags-*.json; the fix preserves the bitfield rather than deleting unknown bits.
