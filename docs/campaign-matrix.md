# Campaign qualification matrix

Updated 2026-09-29. Release sequence remains Ultimate Doom, Doom II, then a MyHouse-based audit. See [roadmap](roadmap.md).

**Smoke: 36/36 passed at skill 3.** Each case loads the map, runs 35 idle simulation tics, and renders two complete 320×200 serial frames from two camera headings. A smoke pass is not a completed level or visual-reference match. Headless stage timings are not gameplay FPS.

Source/IWAD hashes and detailed results: [results/campaign-smoke-lineflags-fixed.json](../results/campaign-smoke-lineflags-fixed.json).

The preceding r5 Episode 1 human-playthrough candidate was implementation commit
`ab73eba07135fe0f834554be12aae279c151c314`. The broad candidate receipt and
geometry/cache supplement retain the 36/36 map smoke and 69 transition
fixtures, including real E1M9 and E1M4 loads on the secret branch. The latest
audio supplement reruns a 36/36 load/idle/render smoke and records bounded
realtime audio checks. That renderer change consumes per-worker actor
masks during decoding and passes a fresh 36-map smoke, exact 16-worker output
in all three styles, and a persistent-worker map reload. Transition exits are
explicit fixtures and do not mark any map complete; audio continuity checks do
not qualify campaign completion. See the [current candidate
receipt](../results/episode1-current-human-candidate-20260928-r5.json),
[broad receipt](../results/episode1-current-human-candidate-20260928.json),
[geometry/cache supplement](../results/episode1-current-human-candidate-20260928-r2.json),
and [realtime-audio supplement](../results/episode1-current-human-candidate-20260928-r3.json); the [visible-actor profile](../results/renderer-visible-actor-filter-20260928.json) reports sequential worker-equivalent CPU and does not claim a frame-rate gain.

The current single-playthrough handoff is r7 at source commit
`e8fd50012c343a3e858001a086e2de7b5efac786`; see its [candidate receipt](../results/episode1-current-human-candidate-20260929-r7.json)
and the exact [complete Episode 1 scope](episode1-playtest.md). Jason's human
route remains pending. The sector-plane cache passes a new 36-map load/idle/render
smoke and five-view 16-worker equality in all three styles. An isolated
PowerShell phase experiment shows lower geometry time with unchanged full-frame
hashes; one matching 60-second headless host pair is unpaired and cannot assign
the observed rate difference to the change. See the [sector-cache performance
record](performance.md#cache-sector-plane-data-for-rasterization--september-29-2026)
and [portable receipt](../results/performance-sector-render-cache-20260929.json).
The [post-commit Windows checkout validation](../results/episode1-r7-windows-checkout-validation-20260929.json)
also confirms 36/36 load/render cases, all three five-view worker styles, and 20
masked-wall checks against the checked-out source. These checks do not complete
any map or change campaign completion status.

A current-source, sound-enabled, 30-second headless E3M6 host comparison on
September 28 reached 34.70, 31.90, and 33.70 simulation tics/sec at 8, 12,
and 16 renderer workers; the corresponding completed render-job rates were
29.30, 30.60, and 30.30/sec. This no-input run did not complete E3M6 and does
not count Terminal or monitor presentations. It changes no campaign status;
see the [worker-count comparison](../results/worker-count-host-render-comparison-20260928.json).

A later 30-second output-clock audio follow-up on E3M6 selected D_E3M6 from
the full local catalog and used 16 render workers. It reported zero rebuffer
resumes and zero queue-starvation observations, with all simulation packets
consumed and clean device shutdown. This single deterministic scripted headless sample
does not complete the map, verify a campaign transition, or establish audible
continuity; see the [audio-load receipt](../results/e3m6-realtime-audio-loaded-20260928.json).

A later worker-mask span-lookup prototype also matched the serial E1M1 renderer
for five views in each style at 12 workers and for a 16-worker Classic fuzz
fixture. It was reverted after the longer dispatch comparison showed no speed
gain. These fixed-view renderer checks do not qualify map completion; see the
[bookkeeping trial record](../results/actor-mask-bookkeeping-trials-20260928.json).

The current actor-projection and fixed-angle sprite renderer also passes a
fresh **36/36-map smoke** at 35 idle tics and two full 320×200 serial frames
per map: [receipt](../results/campaign-smoke-sprite-rotation.json). Its
`WorkerStrips=16` field is configuration metadata; the smoke itself does not
start render processes. This is startup/render coverage, not any of the
ordinary-input completion evidence in the table below.

The current Doom sky-sampling source passes a further **36/36-map smoke** with
the same 35 idle tics and two 320×200 serial frames per map:
[receipt](../results/campaign-smoke-sky-20260926.json). Its `WorkerStrips` value
is configuration metadata; this smoke does not start processes. Exact
16-process serial parity for each of the three display styles is recorded
separately in the [rendering-fidelity record](rendering-fidelity.md#doom-sky-column-and-vertical-wrap-sampling-2026-09-26).
This remains load/render smoke, not route or campaign completion.

The 2026-09-27 per-context scratch-reuse candidate also passes **36/36 maps**
at 35 idle tics and two 320×200 frames per map. Its full report is
[here](../results/campaign-smoke-scratch-reuse-20260927.json); the smoke runs
serially, and `WorkerStrips` is configuration metadata. Matching 16-process
output in the three styles is recorded separately in the
[renderer fidelity record](rendering-fidelity.md#reuse-per-context-raster-scratch-2026-09-27).
This is load/render smoke, not route completion.

The current Episode 1 human-playthrough build is source commit
`193c386cc1a22feeb1bf7d269d9b2cc1d1ddaf73`. Its
[candidate receipt](../results/episode1-human-playthrough-candidate-20260927-r5.json)
links a fresh 36-map smoke, 69 campaign transition checks, 97 boss progression
checks, 10 menu-input checks, 24 session-screen checks, and the 1,747-command
E1M1-to-E1M2 session regression. The transition checks load real E1M9 and E1M4
worlds and verify secret history and finale state; fixtures do not claim those
maps were played. The current renderer also passes 20 masked-wall checks, 119
fuzz checks, and serial/worker equality in Classic, Matrix/Katakana, and
AnsiArt/Katakana. The actor-occlusion replay prefix suppresses the reproduced
tic-245 leak but retains actor-mask and broad scene differences. The receipt
records the raised-floor view as classic Doom Techpillar sprite overlap and
preserves the launcher preflight and remaining limits. Jason clarified that
the blue-armor object is a pre-placed Gibs decoration. The earlier 16-view
receipt includes a camera near the blue armor and views near Gibs placements,
but does not reproduce the exact sighting. The earlier
[renderer-guard receipt](../results/episode1-render-guard-evidence-20260927.json)
keeps its original `4ed3363` source pin, four retained E1M1–E1M4 route
regressions, and fixed-input E1M2–E1M4 host replays. The E1M3 waypoint-driver
attempt stopped short without a reproduced defect and route tuning remains
stopped. The exact recorded 26,731-command human attempt also replays through
the chainsaw input without an exception, matching all 79 recorded gameplay and
render checkpoints; its separate automap, audio, and terminal output are not
replayed ([receipt](../results/episode1-human-crash-replay-20260927.json)).
These results prepare one human run; no automated test claims the remaining
maps or finale were played.

The current renderer worker-mask change also passes exact serial/worker
comparisons across five views each on E1M1–E1M4, and 16-worker Spectre/fuzz
scenes across Classic, Matrix/Katakana, and AnsiArt/Katakana on E3M6. These
renderer regressions do not add map-completion evidence or establish original
Doom pixel parity; details and receipts are in the
[rendering-fidelity record](rendering-fidelity.md#skip-actors-outside-each-renderer-stripe-2026-09-28).

The prior `e358741` renderer, `76b18ac` campaign/session, and `f5f404a`
Episode 1 receipts remain available with their original source pins. Detailed
renderer failures and corrected route-replay reports are linked from the
current readiness receipt above.

An additional E1M3 waypoint-driver attempt stopped short of its next point
without a crash or reproducible engine defect; route tuning was not continued.
The retained 7,118-command E1M3 fixed-input replay reaches E1M4 with all 24
checkpoints matching, and is the regression evidence for that map.

E1M1 has an [input-only completion report](../results/e1m1-route-lineflags.json) with 1560 commands. That route ends at intermission; it does not qualify next-level presentation or a whole episode. The existing E1M1 driver was rerun without waypoint changes on current source commit `1bd96b0` and again reached intermission in 1560 commands; its [source-pinned receipt](../results/e1m1-route-current-source-validation-20260927.json) distinguishes this automated route from human play. The older fixed input in `results/e1m1-route.json` is not current-source completion evidence: its live replay ended at `ReplayEnd` on E1M1. E1M2 has a separate [normal-route qualification](campaign-e1m2.md), including recorded continuation into E1M3. The remaining maps still need completion evidence. Source-version matching is checked separately from input/state equivalence.

The first 280 commands from that existing E1M1 report also supply eight
dynamic scene checkpoints for the
[moving-actor renderer comparison](rendering-fidelity.md#moving-actors-on-a-recorded-e1m1-prefix).
This reuses the regression input without creating another route; it does not
add campaign-completion evidence.

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
command, IWAD and qualified music prerequisites, controls, and reporting
instructions are in [episode1-playtest.md](episode1-playtest.md). The user
result will be entered there only after it is reported.

The 2026-09-28 shared Spectre-order optimization preserves exact full-frame
pixels and passes five-view 16-worker partition fixtures in all three visual
styles. This renderer/transport check adds no map-route or campaign-completion
coverage; the single human playthrough remains pending. See the
[paired performance receipt](../results/renderer-shared-fuzz-order-20260928.json)
and the [three-style worker receipts](rendering-fidelity.md#share-spectre-actor-order-across-renderer-workers-2026-09-28).

Current focused readiness evidence uses the same Ultimate Doom IWAD hash
`6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`:

[Episode 1 playtest readiness summary](../results/episode1-playtest-readiness.json)
uses the source baseline recorded in the readiness receipt,
links the current renderer smoke and the focused game/session/input checks,
and explicitly leaves the human route and physical keyboard input pending.

- [Visibility fix and route regressions](../results/visibility-campaign-regressions.json):
  two intercept checks, the original E1M1–E1M4 stored route replays, and a
  fresh E1M1–E1M9 smoke. All nine maps load, run 35 idle tics, and render two
  320x200 frames. Routes and smoke remain separate from human coverage.
- [Transition fixtures](../results/episode1-transitions-sprite-rotation.json):
  57/57 checks after the source correction, including normal-map destinations,
  E1 secret destinations and history, finale states, inventory carry-over,
  and death/respawn behavior.
- [Boss progression fixtures](../results/episode1-bosses-sprite-rotation.json):
  97/97 checks, including E1M8's tag-666 floor opening. Explicit boss-state
  fixtures are not an ordinary combat victory.
- [Menu/session checks](../results/episode1-session-menu-sprite-rotation.json):
  125/125 checks and 46 screen fixtures.
- [Synthetic menu-key checks](../results/episode1-menu-input-sprite-rotation.json):
  10/10 transitions pass; no desktop keyboard input was injected.
- [Synthetic keyboard-state checks](../results/episode1-console-input-sprite-rotation.txt):
  six checks passed. They do not inject desktop input or establish physical
  keyboard usability.
- [Music preparation](../results/music-preparation-episode1-first.json) qualifies
  the eleven local Episode 1 loops; D_VICTOR's three-period recurrence and
  independent reader checks are recorded in adjacent `music-loop-dvictor-*`
  results. [Actual worker integration](../results/save-worker-episode1-music-after-catalog.json)
  passes 15 save/load/new-game checks with 97,020 music frames and clean device
  shutdown. This is not a full-campaign continuity check.
- [Current-source launcher preflight](../results/episode1-launch-preflight-sprite-rotation.json):
  the Steam IWAD, 36 episode maps, PowerShell 7.6.5, Windows Terminal and exact
  catalog path are detected. The separate audio-worker check validates the
  catalog contents; preflight itself does not launch the game.
- [Launch parameter binding](../results/episode1-launch-binding.txt): the
  documented source entry point parses and exposes every playtest argument.
- The current-source [36-map smoke](../results/campaign-smoke-sprite-rotation.json)
  passes after the latest renderer changes: every Ultimate Doom map advances
  35 idle tics and renders two frames using sixteen strips. The focused transition/finale,
  boss, menu/session, synthetic console-input, and menu-key checks were freshly
  rerun for the human-playthrough handoff; all 295 assertions passed. The
  [current readiness receipt](../results/episode1-playtest-readiness.json)
  records their counts, exact IWAD, settings defaults and limits. The separate
  [integer-row renderer receipt](../results/render-integer-row-fidelity.json)
  captures the latest sampling comparison and serial/worker equivalence; the
  [integer-column receipt](../results/render-column-index-fidelity.json) retains
  the preceding correction. None of these substitutes for the one physical
  human playthrough.
- Perspective [world-sprite post sampling](../results/world-sprite-vertical-sampling-verified.json)
  now matches the adopted fixed-point masked-post path in 40 real-IWAD
  scale/origin cases (838 palette-index differences before, zero after).
  Asset format v5 preserves the required post sources across sixteen workers;
  all three styles match serial output, 138 weapon-lighting fixtures pass, and
  a live E1M1-to-E1M2 worker reload preserves all processes. This is a patch
  raster and transport check, not original-executable parity or map completion.
- Exact rotated actor-frame arithmetic now matches the adopted Doom angle rule
  across 393,408 synthetic sector-boundary cases; the former floating formula
  disagreed in 172,724. Asset v6 carries its lookup to workers. The actual
  three-style worker checks are exact, but moving-actor visual selection and
  occlusion remain open. The current v6 E1M1-to-E1M2 reload preserves all
  sixteen workers and matches 256,000 pixels and 64 strips against serial
  output ([receipt](../results/session-worker-sprite-rotation-classic.json));
  see [rendering fidelity](rendering-fidelity.md) for limits.
- Current-source [weapon/actor patch sampling](../results/weapon-projection-sampling-comparison.json)
  uses the adopted renderer's floored screen origin and fixed-point column
  stepping. Seven fractional pistol offsets match exactly, ten E1M1/E1M2
  views improve cumulatively by 3.78%, and 16-worker output matches in Classic,
  Matrix/Katakana and AnsiArt/Katakana. Its serial pair shows a small timing
  cost; neither result establishes campaign completion or displayed FPS.

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

At the time of the E1M4/E1M3 host qualifications, dry loops were available for E1M1, E1M2, intermission, E1M3, E1M4 and E1M9. The later [Episode 1 music preparation](music-preparation.md) completed all eleven loops, including E1M5–E1M8 and D_VICTOR. E1M4 plays in the recorded host after E1M3; E1M9's campaign route remains unqualified. E1M1's requalification preserves prior samples; the three longer tracks each pass six actual reader checks. The 1,747-command/eight-checkpoint E1M1 route passes with music and recorded audio in Matrix/color-art, including the block intermission UI. The longer E1M2 route completes with all 4,073,580 audio frames returned; the third E1M3 recording returns all 8,968,680 frames after the bounded shutdown repair. Queue starvation remains an open timing issue. See [E1M2 qualification](campaign-e1m2.md), [E1M3 qualification](campaign-e1m3.md), [campaign music](campaign-music.md), [preparation](music-preparation.md) and [audiovisual capture evidence](audiovisual-recording.md).

September 19 discovery optimization: all 36 map starts at four headings preserve fresh mapped-line bitsets and pixels/counters/other flags. The full E1M3 route preserves 7,002 fresh discovery states and all 24 gameplay checkpoints. This adds discovery coverage, not completion of additional maps. Loaded prefix pacing improves to 30.829 tics/sec; sustained 35/60 and E1M4 terminal-host qualification remain open. E1M4 subsequently passes independent headless completion as recorded above. See [discovery performance](automap-discovery-performance.md).

Boss-trigger coverage (2026-09-19): [97 checks](boss-progression.md) verify E1M8, E2M8, E3M8, E4M6 and E4M8 selection guards, final death-state action dispatch and tagged mover completion. These explicit-state fixtures do not change the input-only completion entries above.

Current-source probes ran the existing HMP E1M1–E1M4 waypoint plans once with
the present route drivers. E1M1 and E1M2 reached intermission; the E1M2
independent replay matched 86 samples over 3,198 commands and entered E1M3.
The current M3 and M4 route attempts ended in player death at waypoints 144 and
172. Those plans match earlier successful route receipts, but the current M3
and M4 driver hashes differ from the earlier runs. This does not establish an
engine regression, and the drivers were not tuned. See the
[current-source route report](../results/episode1-route-regressions-current-20260928.json);
Jason's complete human playthrough remains pending.
