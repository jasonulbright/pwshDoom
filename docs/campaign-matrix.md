# Campaign qualification matrix

Updated 2026-09-26. Release sequence remains Ultimate Doom, Doom II, then a MyHouse-based audit. See [roadmap](roadmap.md).

**Smoke: 36/36 passed at skill 3.** Each case loads the map, runs 35 idle simulation tics, and renders two complete 320×200 serial frames from two camera headings. A smoke pass is not a completed level or visual-reference match. Headless stage timings are not gameplay FPS.

Source/IWAD hashes and detailed results: [results/campaign-smoke-lineflags-fixed.json](../results/campaign-smoke-lineflags-fixed.json).

E1M1 has an [input-only completion report](../results/e1m1-route-lineflags.json) with 1560 commands. That route ends at intermission; it does not qualify next-level presentation or a whole episode. E1M2 now has a separate [normal-route qualification](campaign-e1m2.md), including recorded continuation into E1M3. The remaining maps still need completion evidence. Source-version matching is checked separately from input/state equivalence.

The [save/load core](save-load.md) now preserves the E1M1 → intermission → E1M2 input route across reconstruction and a fresh PowerShell process. Death/respawn and all four finale boundaries pass explicit save fixtures. These add state-continuation coverage; map-completion and terminal-host entries below retain their existing scope.

The integrated host also loads an intermission save, advances to E1M2, then loads an E3M8 finale save with acknowledged worker/asset generations. Its [448-command replay](../results/save-host-session-edges-replayed.json) matches six checkpoints. E3M8 ending playback here starts from an explicit fixture; its boss exit and map completion remain unqualified.

| Map | Load / idle simulation / two frames | Input-only completion | Transition / ending |
| --- | --- | --- | --- |
| E1M1 | Pass | Pass, HMP | Pass: real intermission -> E1M2 |
| E1M2 | Pass | Pass, HMP pistol start, normal exit | Pass: recorded AnsiArt intermission -> E1M3, 13 matching checkpoints |
| E1M3 | Pass | Pass, HMP pistol start, normal exit; [evidence](campaign-e1m3.md) | Recorded Matrix intermission -> E1M4 passes 24 checkpoints and all audio frames; 47 integration checks. Pacing/queue starvation remain open |
| E1M4 | Pass | Pass, HMP pistol start, normal exit; [evidence](campaign-e1m4.md) | Recorded AnsiArt intermission -> E1M5 passes all 22 checkpoints and 51 integration checks; all audio frames return. Pacing and acoustic continuity remain open |
| E1M5 | Pass | [Automated route investigation](campaign-e1m5-investigation.md) is paused for the single human Episode 1 milestone; HMP completion remains unqualified. The qualified E1M4 continuation reaches waypoint 316/414 then dies; exact suffix replay matches 212/212 trace samples without reproducing an engine defect | E1M4→E1M5 entry is qualified through headless replay; E1M5 terminal-host completion untested |
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

## Episode 1 human playthrough milestone

The next user milestone is a single HMP human playthrough from E1M1 through
the Episode 1 finale, including E1M3's secret exit to E1M9 and the return to
E1M4. Do not split this into per-map user tests. The exact scope, launch
command, IWAD and sound-effects prerequisites, controls, and reporting
instructions are in [episode1-playtest.md](episode1-playtest.md). The user
result will be entered there only after it is reported.

Current focused readiness evidence uses the same Ultimate Doom IWAD hash
`6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`:

[Episode 1 playtest readiness summary](../results/episode1-playtest-readiness.json)
combines the passing receipts below and explicitly leaves the human route and
physical keyboard input pending.

- [Episode 1 smoke](../results/episode1-playtest-smoke.json): E1M1–E1M9,
  35 idle tics and two 320x200 rasterizations per map; 9/9 passed. This is
  loading/rendering smoke, not map completion.
- [Transition fixtures](../results/episode1-transition-readiness.json):
  57/57 checks, including normal episode progression, E1 secret destination
  E1M9, E1M9 return to E1M4, and Episode 1 finale flat/text.
- [Boss progression fixtures](../results/episode1-boss-readiness.json):
  97/97 checks, including E1M8's tag-666 floor opening. Explicit boss-state
  fixtures are not an ordinary combat victory.
- [Menu/session checks](../results/episode1-session-menu-readiness.json):
  125/125 checks and 46 screen fixtures.
- [Synthetic keyboard-state checks](../results/episode1-console-input-readiness.txt):
  six checks passed. They do not inject desktop input or establish physical
  keyboard usability.
- [Launcher preflight](../results/episode1-launch-preflight.json): the Steam
  IWAD, 36 episode maps, PowerShell 7.6.5, and Windows Terminal are detected.
  It explicitly selects effects-only mode and does not launch the game.
- [Launch parameter binding](../results/episode1-launch-binding.txt): the
  documented source entry point parses and exposes every playtest argument.

These checks support a normal playthrough attempt but do not certify route
completion. E1M5's failed automated continuation ended in player death and
reproduced its recorded trace; it did not expose a repeatable engine defect.
Route-driver development is stopped for this milestone. The separate E1M1–E1M4
normal-exit routes remain regressions.

## Current blockers and next work

- [Recorded terminal session](../results/session-recorded-classic-game.json) verifies E1M1 intermission -> E1M2 and map-asset generation refresh. The [E1M2 route](campaign-e1m2.md) completes normally with 3,046 commands and independently continues into E1M3. Recorded AnsiArt playback passes all 42 integration checks after fixing an audio queue overflow. E1M3 normal completion and recorded Matrix entry into E1M4 now pass; secret paths, audio starvation and below-target pacing remain open.
- Isolated controller fixtures verify episode finales, all four secret returns, par units, secret-visit history, inventory carryover and death/respawn. See results/campaign-transitions-session.json. Fixtures do not qualify map playthroughs or boss-triggered exits.
- Record this one complete human Episode 1 playthrough as the next campaign evidence. For the later Ultimate Doom and Doom II release matrix, continue using ordinary-input completion routes or documented human playthroughs; keep targeted state fixtures separate from either form of evidence.
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

Music integration currently has E1M1, E1M2, intermission, E1M3, E1M4 and E1M9 qualified dry loops. E1M4 now plays in the recorded host after E1M3; E1M9's campaign route remains unqualified. E1M1's requalification preserves prior samples; the three longer tracks each pass six actual reader checks. The 1,747-command/eight-checkpoint E1M1 route passes with music and recorded audio in Matrix/color-art, including the block intermission UI. The longer E1M2 route completes with all 4,073,580 audio frames returned; the third E1M3 recording returns all 8,968,680 frames after the bounded shutdown repair. Queue starvation remains an open timing issue. See [E1M2 qualification](campaign-e1m2.md), [E1M3 qualification](campaign-e1m3.md), [campaign music](campaign-music.md), [preparation](music-preparation.md) and [audiovisual capture evidence](audiovisual-recording.md).

September 19 discovery optimization: all 36 map starts at four headings preserve fresh mapped-line bitsets and pixels/counters/other flags. The full E1M3 route preserves 7,002 fresh discovery states and all 24 gameplay checkpoints. This adds discovery coverage, not completion of additional maps. Loaded prefix pacing improves to 30.829 tics/sec; sustained 35/60 and E1M4 terminal-host qualification remain open. E1M4 subsequently passes independent headless completion as recorded above. See [discovery performance](automap-discovery-performance.md).

Boss-trigger coverage (2026-09-19): [97 checks](boss-progression.md) verify E1M8, E2M8, E3M8, E4M6 and E4M8 selection guards, final death-state action dispatch and tagged mover completion. These explicit-state fixtures do not change the input-only completion entries above.
