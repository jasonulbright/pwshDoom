# pwshDoom: game completion and research roadmap

Created 2026-09-10. This is a living plan, not a declaration that the listed features work. The user authorized continuing implementation, experiments, and documentation toward a complete, enjoyable game and a substantial write-up.

## Product and research objective

Build a usable single-player Doom experience in a PowerShell terminal, with gameplay, rasterization, interpolation, and terminal encoding algorithms in PowerShell. Keep the 320×200 full-color image and original 35 Hz simulation semantics while targeting 60 displayed updates/sec on the measured machine. Standard .NET collections, bulk operations, IPC, and Windows device APIs are allowed; compiled game/rendering helpers and GPU Doom shaders do not meet the user's requirement.

The user confirmed the sequence: **Ultimate Doom first, Doom II second, then a MyHouse-based audit**. They also approved PowerShell sound decoding/mixing with standard Windows/.NET audio playback. Sound decoding, mixing, music synthesis, and the Windows playback backend are implemented; their performance, audible quality, and continuous campaign behavior still require qualification. Device playback authorization does not authorize moving gameplay/rendering into compiled code. Other IWAD editions, expansions, multiplayer, and cross-platform support are future scopes unless explicitly added.

The MyHouse audit is a named follow-on, not part of the first-release gate. Begin by pinning the exact package/version and inventorying its required formats, scripts, geometry, audio, and engine behaviors against a matching reference runtime. Distinguish unsupported extensions from incorrect implementations. A [first-hand package-editing report](https://www.speedrun.com/myhouse_wad/guides/y43o3) identifies `MyHouse.pk3`, `ZSCRIPT`, and `MAPINFO`, with differences between 2023 and 2025 releases. This supports treating the audit as more than a vanilla-map stress test; it is not our own package verification. Do not substitute a different same-named WAD and call that compatibility. Direct package inspection is still pending, and the original release forum could not be retrieved in the initial lookup. Do not promise that a vanilla Doom implementation can run this mod, or expand this audit into full GZDoom compatibility without a measured scope assessment.

## Active milestone: one complete Episode 1 human playthrough

On 2026-09-26 the user explicitly chose one complete human playthrough as the
next milestone, using the roadmap's documented human-evidence option. Do not
stop for individual map tests or spend the milestone on route-driver tuning.
Keep the qualified E1M1–E1M4 input routes as regressions; focused controller,
input, and crash checks remain useful. The requested scope is E1M1–E1M8 plus
the E1M3 secret exit to E1M9 and its return to E1M4, ending at the Episode 1
finale. The exact launch command, controls, evidence, and result entry live in
[`episode1-playtest.md`](episode1-playtest.md).

Readiness work fixed a reproducible `VisibilityCheck.InterceptVector`
denominator-zero defect. Its focused checks, all four stored E1M1–E1M4 route
regressions, the nine-map Episode 1 smoke, and 57 campaign transition fixtures
pass against the installed Ultimate Doom IWAD; [the evidence index](../results/visibility-campaign-regressions.json)
and [readiness receipt](../results/episode1-playtest-readiness.json) record
their limits. Fixtures do not claim that a human map route has completed or
that desktop keyboard play has been observed. The complete eleven-track
Episode 1 music catalog is now prepared locally, and the actual simulation and
audio worker passes 15 save/load/new-game checks with clean device shutdown.
The exact source, controls, catalog, and single playthrough scope are in
[`episode1-playtest.md`](episode1-playtest.md). The existing E1M5 continuation
route ended in player death and did not expose a reproducible product defect;
it is documented and route automation is stopped for this milestone. The
broader release acceptance gates below remain intact.

## Historical Episode 1 handoff — R17 (2026-09-29)

The current implementation candidate is commit 00405deebef6b4e8477c9c9316987b82fbc9064d. The clean development package and bounded R17 checks are pinned in the [candidate receipt](../results/episode1-current-human-candidate-20260929-r17.json) and [package receipt](../results/r17-playtest-package-validation-20260929.json). The archive has 543 manifest-verified files, excludes local assets and the research PDF, and passes extracted-package preflight under PowerShell 7.6.6.

R17 passes 144 all-map stationary-discovery bitset comparisons, eight simulation-worker automap checks, and the nine-map Episode 1 load/idle/render smoke. A four-second packaged E1M1 audio startup returns all 175,140 submitted frames and closes cleanly; a single queue-starvation observation follows the final packet, with no rebuffer resume. These checks do not complete a map or establish continuous audio or display pacing.

The focused R16 chainsaw, transition, boss, and menu-input evidence remains applicable because R17 changed renderer discovery and worker telemetry only. Physical keyboard play and Jason's complete HMP route remain pending: E1M1–E1M3, E1M3 secret exit through E1M9 and return to E1M4, E1M4–E1M8, defeat the E1M8 boss, and reach the Episode 1 finale. The R17 launch command, required IWAD/catalog, controls, limitations, and reporting steps are in [episode1-playtest.md](episode1-playtest.md). Do not split the human test into per-map requests. R17 is a local development handoff, not a new public release; the broader Ultimate Doom gates remain open.

## Baseline and acceptance

Latest gameplay correction (2026-09-19): built-in human-recorded demo input exposed a missile-collision exception in E1M5. The corrected sky-flat lookup completes that input stream and a separate E2M2 stream without exceptions; external demo file construction is also repaired. See [vanilla demo investigation](vanilla-demo-investigation.md). Original-engine synchronization and map completion remain unverified by these runs.

Earlier renderer milestone (2026-09-19): transparent fence/grille pixels now survive later opaque scenery, with depth-correct actors and overlapping masked walls. Fourteen focused checks, the original-renderer negative control, existing fuzz checks and worker equivalence are recorded in [rendering fidelity](rendering-fidelity.md). This is post-preview source work; the published preview ZIP remains unchanged. Campaign completion and pacing gates remain open.

The current baseline is a single-player session prototype, not a campaign-qualified game. A historical E1M1/HMP input-only completion route and intermission advancement into E1M2 exist, but the preserved fixture now dies before intermission on current source; E1M1 remains unqualified and the automated route is not being retuned. Other features include 35 Hz simulation scheduling, parallel PowerShell rendering, truecolor ANSI output, keyboard handling, resize pauses, and independent presentation telemetry for earlier builds. Intermission/finale screens, map-specific asset refresh, new-game/quit menus and pause/resume are implemented. Six save slots, confirmed save/load and replayed loads are implemented. Automap controls, save/load and replay are integrated, with numeric discovery/encoding recovering near-target averages on the bounded map-control test; timing spikes remain. Persistent settings now include always-run, turn speed, independent sound levels and editable primary game-key bindings while preserving the defaults and legacy aliases. PowerShell sound decoding/mixing and Windows playback are integrated; full-campaign continuity, latency under renderer load and audible review remain unqualified. See [save/load](save-load.md), [automap investigation](automap.md), [menus](menus.md), [campaign session work](campaign-session.md), [audio](audio.md), [implementation](implementation.md), [viewport](viewport.md), and [provenance](../src/ManagedDoom/ORIGIN.md).

Preview.6 also passes one current-source fresh-process save continuation: a
command-700 save loaded at tic 701 and matched an uninterrupted 140-command
reference at four checkpoints and the final save graph. This does not qualify
the desktop menu flow or broader route boundaries; see the
[source-pinned receipt](../results/preview6-current-source-save-continuation-20261002.json)
and [save/load record](save-load.md).

The historical 1,747-command E1M1-to-E1M2 progression fixture was rerun against
the current source and no longer completes E1M1: its player dies to a Troop at
tic 1,245, respawns, and remains in E1M1 through the replay end. The ordinary-
input progression harness consequently records only initial map entry and
fails to reach intermission. No reproducible mechanic defect was isolated and
the automated route was not tuned; current-source E1M1 route completion remains
unqualified. See the [replay diagnostic](../results/current-source-session-progression-diagnostic-20261002.json).

The five-skill E1M1 behavior matrix was rerun on current source after the
visibility and actor-dispatch changes: all37 spawn-filter, damage/ammo,
monster-behavior, option-override and respawn-threshold checks pass. This is
component regression evidence and does not restore the stale route's campaign
qualification. See the [source-pinned receipt](../results/current-source-difficulty-20261002.json).

Release acceptance requires:

- Every included map listed by exact IWAD hash has loading/rendering smoke coverage and a completed ordinary-input route or documented human playthrough. Record skill, secrets, deaths/reloads, and route provenance. A direct exit fixture or 35 idle tics is never campaign completion evidence.
- Normal/secret exits, secret-map returns, episode finales, boss-triggered changes, doors, lifts, moving floors/ceilings, stairs, teleporters, keys, weapons, pickups, damage, death/respawn, and inventory carryover have appropriate behavioral checks. Core skill-dependent behavior now has a focused five-skill E1M1 qualification; campaign routes across skills and maps remain open.
- New game, episode/difficulty selection, pause/resume, settings, save/load, exit confirmation, intermission, finale, and automap are usable with the documented controls. Save formats have versions, bounded validation, and round-trip continuation tests. Never overwrite user saves in tests.
- Audio includes sound effects, spatial direction/volume, overlapping channels, music, pause/resume, volume/mute, and clean device shutdown. The chosen playback/synthesis boundary is explicit; underruns, latency, and CPU cost are measured. Asset and soundfont rights/provenance are recorded.
- Visual comparisons cover fixed player/world states at interpolation endpoints: geometry, clipping, texture orientation/pegging, sky, lighting, sprites, HUD, palettes, invisibility, and aspect ratio. Classify intentional approximations and test tolerances. Full vanilla pixel/demo compatibility is a separate claim requiring separate evidence.
- Repeated full-game benchmark routes cover quiet areas, dense combat, moving geometry, effects, audio, and UI transitions. Report simulation backlog/lateness, writes, ETW display transitions, frame identity limitations, p50/p95/p99/max gaps, drops, startup time, memory, CPU, and audio underruns. No resolution reduction, suppressed actors, discarded simulation tics, or hidden warm-up exclusions to achieve a headline.
- The 60-display/35-tic targets remain goals, not universally certified guarantees. Before a release comparison, freeze a machine/workload/display matrix and numeric pacing acceptance thresholds. Include all measured windows and startup behavior; report warm-up separately. The existing ~57.6 windowed versus ~59.7 maximized results are an open issue.
- A fresh checkout can be launched with a user-supplied IWAD; missing prerequisites produce actionable messages. Verify physical keyboard play, actual 1080p sizing at declared DPI, windowed/maximized behavior, focus/resize, normal exit, and owned-resource cleanup. Test at least one second hardware configuration before making portability claims.
- Publish source, licenses, reproducible commands, pinned comparisons, result tables, limitations, and an accessible narrative. No commercial WADs, extracted assets, native binaries, or private test artifacts enter the repository.

## Milestones and dependencies

| Milestone | Concrete result | Exit evidence | Status |
| --- | --- | --- | --- |
| M0 — Preserve the baseline | Reproducible E1M1 game, source lineage, raw timings | Existing input route, codec/transport/lifecycle checks, PresentMon captures | Baseline established; limits recorded |
| M1 — Campaign foundation | Map inventory and failure matrix; correct state transitions; renderer asset refresh on level changes | Per-map smoke results, normal/secret routing tests, E1M1 → E1M2 through the real host, carryover/death checks | The current Preview.6 runtime passes all36 map-start smokes, 69 controller/transition fixtures (including the E1M3 → E1M9 → E1M4 secret branch), and 97 boss-progression checks. Earlier E1M1 → E1M2 host routes remain recorded in all three styles. These tests verify state and loading, not ordinary-input completion of the maps or episode. |
| M2 — Complete single-player session | Menus, intermission/finale display, pause, save/load, automap, input recording | Scripted state-machine checks, save continuation, short user playtest | Intermission/finale, resume/new-game/quit menus, pause, six save/load slots and versioned input/control recording implemented; automap controls/save/replay integrated; persistent settings include editable game-key bindings. Physical play and broader qualification remain |
| M3 — Audio | PowerShell-controlled effects/music and declared device backend | Offline output correctness, real playback review, underrun/latency/load measurements | [Opt-in PowerShell effects and Windows playback](audio.md) integrated; volume/mute and full-host PCM identity verified; [dry PowerShell music](music-synthesis.md) has 55 synthesis tests; [bounded music workers](music-workers.md) preserve the entire E1M1 loop with nineteen current group/lifecycle checks; paced four/eight-worker runs fail 38/118 virtual deadlines, independently audited; [finite float64 cache](music-cache.md) preserves full-score PCM with 22 storage and 391 evidence checks; [E1M1 reusable loop](music-loops.md) qualifies full state/output recurrence and bounded reading; [E1M1 host music](music-integration.md) passes worker/save/headless/live-window checks; the eleven-track Episode 1 catalog including D_VICTOR passes loop preparation and save/load integration; D_INTRO now has a source-pinned deterministic end/tail qualification, finite reader EOF checks, and an actual-worker first-block PCM match. D_E2M1–D_E2M3 and D_E2M7–D_E2M9 have two-period complete-state recurrence proofs; D_E2M4–D_E2M6 have default three-period independent-output qualifications. D_E2M1–D_E2M4 and D_E2M6–D_E2M9 add eight byte-distinct payloads, while D_E2M5 duplicates D_E1M7. D_E3M2 also has a two-period complete-state proof: 234.54 seconds per period, 47 voices at both boundaries, exact opening PCM, and 892.403 seconds of render/write/snapshot work. D_E3M3 now has a two-period complete-state proof: 488.714 seconds per period, 50 voices and matching boundary state, exact opening PCM, and 4,674.868 seconds of render/write/snapshot work. D_E3M5–D_E3M9 have two-period proofs at 150.857, 84, 105.6, 96 and 549.457 seconds per period with 66, 41, 102, 33 and 26 matching boundary voices. D_E3M5 passes its six reader/mixer, ten worker, fourteen map-selection and two-second host checks. D_E3M6 passes six reader/mixer, ten worker and fourteen map-selection checks; sustained host timing is intermittently starved. D_E3M7 passes six reader/mixer, ten worker and fourteen map-selection checks; its two-second host returns all 86,940 frames. D_E3M8 passes the same checks and returns 85,680 of 86,940 frames before shutdown, with a 1,260-frame canceled-tail upper bound and no active starvation. D_E3M9 passes six reader/mixer, ten worker and fourteen map-selection checks; its two-second host returns all 86,940 frames with no active starvation. D_E3M1/D_E3M4 reuse D_E2M9/D_E1M8 only after exact MUS and soundfont hash checks. Short host checks cover E2M4–E2M9 and E3M1–E3M9; E2M4–E2M6 each saw one post-final-packet starvation; E2M7 returned every frame; E2M8 completed 85,680 of 86,940 submitted frames with a 1,260-frame canceled-tail bound; E2M9 completed 84,420 of 86,940 with a 2,520-frame bound; E3M1/E3M2/E3M4 each completed 85,680 of 86,940 with a 1,260-frame bound; E3M3 completed 84,420 with a 2,520-frame canceled-tail bound; E3M5 completed all 86,940 frames with no canceled tail and one queue-empty poll after its final packet. E2M8/E2M9/E3M1–E3M4 had no starvation or rebuffer. Before the September 28 output-clock change, two eight-second 12-worker D_E3M6 hosts with the four-buffer default had one active starvation in one of two trials; doubling the device buffers also had one active starvation in one of two, so the default remains unchanged. These short sessions do not qualify uninterrupted campaign playback. Presentation pacing, sustained underrun/latency, and acoustic review remain open. D_BUNNY is now qualified as the 62-second loop requested by the Episode 3 finale, with actual Finale.Update transition and qualified playback checks; D_INTROA has finite-score evidence but no caller in current Ultimate Doom code. |
| M4 — Rendering fidelity | Reference comparisons and corrected effects/geometry/HUD | Golden states, categorized differences, regressions tested with animation and moving sectors | HUD parity, numeric world/weapon lighting and invisibility/Spectre fuzz implemented. Fuzz uses a documented per-column phase approximation; 119 focused checks and all three actual worker modes pass. Palette selection is implemented with focused/worker checks and Classic/Matrix captures; AnsiArt capture cleanup remains open. Integer-column rays, integer-row walls, fixed-point planes, floored actor/weapon patch columns, and fixed-point world-actor projection improve adopted-reference comparisons; exact worker output passes in all three visual modes and the current-source smoke covers all 36 maps. Untextured solid wall bands retain sprite depth. Wall-silhouette clipping suppresses the reproduced BON1 leak: candidate-only actor pixels fall from 95 to zero at tic 245 and from 44 to 3 at tic 140; reference-only pixels and wider scene differences remain. The raised-floor screenshot replays as lower-sector ELEC Techpillar sprites whose overlap follows classic Doom's plane/sprite draw order. The blue-armor sighting is a pre-placed E1M1 Gibs decoration (DoomEdNum 24); a two-camera, sixteen-heading sweep compares the two documented piles in 64 isolated views. One candidate-only mask pixel is explained by the actor palette index matching the reference floor at that plane pixel; this does not reproduce a through-wall leak or the exact reported angle. Moving-world and independent original-executable comparisons remain. See the [latest fidelity record](rendering-fidelity.md#clip-world-sprites-to-wall-silhouettes-2026-09-27) and the [Gibs sweep](../results/episode1-pool-gibs-angle-sweep-20260928.json). |
| M5 — Campaign qualification | Complete first-target campaign with normal/secret paths and endings | Route evidence per map and transition, difficulty matrix, longer human sessions | E1M2–E1M4 normal routes are qualified. The historical E1M1 fixture now dies before intermission on current source; it remains unqualified and is not being retuned. The focused [five-skill behavior matrix](../results/difficulty-behavior-r1-20260929.json) passes 37 checks on E1M1, including skill-filtered spawns, damage/ammo modifiers, fast-monster behavior, and Nightmare/Respawn Monsters thresholds. This does not qualify complete routes across skills or maps. One E1M4-continuation attempt ended in player death at E1M5 waypoint 316/414; exact suffix replay matched 212 samples without establishing an engine defect. The prepared handoff calls for one human E1M1–E1M8 playthrough through E1M9 and the finale; broad per-map/release qualification remains. All five Ultimate Doom boss-trigger cases pass 97 [behavioral checks](boss-progression.md), rechecked on Preview.6 and pinned in the [current regression receipt](../results/preview6-session-regression-20261002.json); they remain separate from ordinary-input boss victories and map completion. |
| M6 — Performance and usability | Stable pacing, lower overhead, sensible worker/font defaults | Repeated paired trials including audio and hard scenes; second machine/display testing | Preview.6 retains a four-run fixed-view Classic E1M2 ABBA renderer result: median total render −2.88%, wall/BSP −5.03%, with exact hashes. This is sequential stripe timing, not full-host latency. The latest clean native and live effects batches are from earlier runtime revisions and do not qualify Preview.6 at the frozen 35-tic/60-distinct-display thresholds. No new windowed capture was attempted while the user-owned Terminal is open. Current-source paired native pacing, optical frame identity and second-hardware/display testing remain open. See [performance evidence](performance.md) and the [Preview.6 renderer trial](release-preview6.md). |
| M7 — Release and paper | Reproducible package and substantial illustrated article | Clean-checkout test, license/asset audit, linked evidence for every comparison claim | Public [Preview.6](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.6) ships after 35 commits since Preview.5. Its clean-source 569-file package passes extracted manifest/hash verification, launch preflight, a 36-map smoke and five-view worker parity in all three styles; publication/download hashes are verified. The package is a playable community preview, not full certification. Human campaign, current-source pacing/fidelity, physical/acoustic review, second hardware and article illustrations remain open. See [package validation](../results/preview6-package-validation-20261002.json), [publication receipt](../results/preview6-publication-20261002.json) and [article draft](article-draft.md). |
| M8 — Doom II qualification | Doom II campaign, actors/weapons, secret routes, text/cast endings | Expanded campaign matrix and complete route/play evidence with performance checks | After Ultimate Doom release |
| M9 — MyHouse-based audit | Version-pinned requirements and compatibility/performance audit | Required-feature inventory, reference behavior, supported/unsupported/incorrect classification, scoped extension plan | After Doom II; full mod support not yet promised |

The 2026-09-28 audio output-clock change addresses the D_E3M6 packet-queue
gaps seen in packet-exact headless runs. Interactive PowerShell playback now
advances active music/effect state when the simulation has not yet published
another packet; explicit pause, epoch reset, and drain still hold the clock.
The focused actual-device check passes eight continuity/pause/resume/drain
assertions. A four-second D_E3M6 host run passes through the real simulation
process with 16 generated blocks and no queue starvation or rebuffer; a
save/load/new-game worker run passes 15 checks across three audio epoch
resets. These establish bounded device-queue continuity, not audible latency,
physical-device underrun, or sustained full-campaign behavior. Packet-exact
headless mode remains available for reproducible PCM checks. See
[audio continuity](audio.md#interactive-realtime-fill-2026-09-28).

The 2026-09-27 PowerShell mixer index optimization preserves every tested PCM
hash and lowers the isolated 16-voice block mean from 33.1 ms to 5.0–5.7 ms;
all 80 measured candidate blocks stay below the 28.57 ms audio-block duration.

This improves the loaded audio path but does not qualify renderer/device load,
live campaign continuity, or acoustic quality. Details and raw receipts are in
[audio](audio.md#per-sample-index-optimization-2026-09-27).

The 2026-09-27 renderer scratch-reuse change matches 2.304 million pixels
across 36 E1 map-start views, preserves exact 16-process output in all three
styles, and passes a fresh 36-map smoke. Three static serial comparisons show
2.6–3.2% lower median render time, with variable p95 changes. This does not
measure full-host pacing; the 35-tic/60-display gate remains open. See the
[rendering-fidelity record](rendering-fidelity.md#reuse-per-context-raster-scratch-2026-09-27).

Do not postpone all performance work until M6. Measure after a feature adds substantial work; keep a known-good replay and compare against it. Prefer one bounded change and a targeted check over multiple simultaneous optimizations with ambiguous attribution.

2026-09-26 campaign update: [E1M5 investigation](campaign-e1m5-investigation.md) now records the first ordinary-input continuation from the qualified E1M4 state. It dies after 7,442 E1M5 commands; the failure is exactly replayable, and the observed Troop damage does not by itself establish an engine defect. No E1M5 completion or full-campaign qualification is claimed.

## Active work queue (2026-09-29)

- **M3/M6 R15 loop-boundary check:** a 100-second actual-device E1M1 run mixed 100.2 seconds of the qualified 96-second D_E1M1 loop, with no software queue-starvation/rebuffer observations and clean close. It reached 34.987 tics/sec and 40.287 headless render updates/sec; these are not displayed frames and remain below target. Acoustic review and campaign-length continuity remain open. See [audio evidence](audio.md#r15-e1m1-actual-device-loop-boundary-run--september-29-2026) and the [receipt](../results/audio-e1m1-realtime-loop-boundary-r15-20260929.json).
- **M3 current catalog startup recheck:** the retained zero-tic failure report is PowerShell 7.6.6; the 11 qualifications in the documented catalog are PowerShell 7.6.5. Source `68a2033` required exact runtime-string equality, and `398022a` changed this to compatible major/minor versions. Current catalog preflight and actual-device startup pass on 7.6.5 and portable 7.6.6. The session report does not embed the catalog hash, which is recorded as a limit in the [root-cause receipt](../results/music-startup-failure-rootcause-20260927.json). The separate LF/CRLF compatibility fix was not the cause. See [audio evidence](audio.md#current-music-qualification-startup-recheck--september-29-2026) and both [7.6.5](../results/current-music-startup-recheck-20260929.json) / [7.6.6](../results/current-music-startup-recheck-7.6.6-20260929.json) receipts.
- **M3 clean audio exit:** normal unpaused shutdown drains outstanding waveOut buffers for at most 250 ms; paused/error exits and world/volume resets retain immediate cancellation. A muted actual-device test completes 3,780 queued shutdown frames in 57.2 ms with no shutdown cancellation. A current-source four-second D_E1M1 host run returns all 186,480 frames and drains the final 3,780 in 68.8 ms. These short checks do not qualify audibility or full-session continuity; see [audio evidence](audio.md#bounded-device-tail-completion-on-normal-exit--september-29-2026), the [worker receipt](../results/audio-runspace-shutdown-drain-20260929.json), and the [current-source host receipt](../results/episode1-audio-shutdown-r16-20260929.json).
- **M3 current-source 30-track startup:** the 30-entry Ultimate Doom campaign catalog passes launcher preflight under official PowerShell 7.6.6. A six-second actual-device R16 host run selected D_E1M1, returned all 265,860 frames, drained shutdown audio, and reported no queue starvation, rebuffer or cleanup errors. It reached 34.81 simulation tics/sec and 23.82 headless render updates/sec; neither rate is a displayed-frame measurement, and only D_E1M1 played. See [audio preparation](music-preparation.md#current-source-full-catalog-runtime-check--september-29-2026) and the [source-pinned receipt](../results/music-campaign-catalog-host-r16-20260929.json).
- **M6 rejected sprite-post lookup hoist:** exact E3M6 frame hashes, but actor medians were 1.950 ms baseline / 1.971 ms candidate and total medians 7.145 / 7.130 ms; p95 did not improve. The prototype is reverted. See the [comparison](performance.md#rejected-masked-sprite-post-property-hoist--september-29-2026) and [receipt](../results/renderer-post-properties-hoist-rejected-20260929.json).
- **M6 rejected translated-flat color cache:** exact frame hashes, but geometry median increased 2.9%, and total median improved only 0.14% with worse p95. The candidate was reverted. See the [comparison](performance.md#rejected-translated-flat-color-cache--september-29-2026) and [receipt](../results/rejected-flat-color-cache-20260929.json).

- **M3 output-clock audio under E3M6 load:** a current-source 30-second, 16-worker host with the complete local music catalog selected D_E3M6 and reported zero rebuffer resumes or queue-starvation observations, consumed all 720 packets, and closed the real audio device cleanly. It remains a single deterministic scripted, single-map headless sample; campaign audio continuity and acoustic quality are open. The same run advanced 30.932 active tics/sec, so M6 pacing remains open. See the [source-pinned receipt](../results/e3m6-realtime-audio-loaded-20260928.json).

- **M6 sector-plane cache:** current-source measurements keep the complete indexed frame identical while lowering the isolated geometry median by 10.62% and total measured stripe-render median by 9.80%. All 36 maps pass load/idle/render smoke; five-view serial/16-worker equality passes in all three display styles. A single ordered headless host comparison is inconclusive, and Terminal/display pacing remains unqualified. See the [measurement](performance.md#cache-sector-plane-data-for-rasterization--september-29-2026) and [portable receipt](../results/performance-sector-render-cache-20260929.json).
- **M6 plane-boundary scan trial:** removing the per-row boundary lookup keeps all frame/worker hashes but does not improve the slowest worker and regresses total p95; the candidate is reverted. See the [measurement](performance.md#reject-per-row-plane-boundary-scans--september-29-2026) and [receipt](../results/rejected-plane-boundary-scan-20260929.json).
- **M6 indexed-color output:** optional Classic `Ansi256` maps each Doom palette RGB to the nearest xterm indexed color. Its output for one identical 320×200 E1M1 frame is 28.65% smaller than exact truecolor and the production worker/launcher path passes serial/partition tests. A single Ansi256 live run completed 43.12 Terminal writes/sec; its later truecolor companion varied to 10.38/sec, so this pair cannot attribute a pacing difference. Keep it experimental and truecolor as default. Next compare repeated interleaved live trials at matched session state with machine-load conditions recorded. See the [indexed-color experiment](ansi-256-color.md) and [receipt](../results/ansi256-runtime-20260929.json).
- **M6 rejected plane lookup:** a direct plane-ID metadata table matched every tested E3M6 frame but did not produce a repeatable paired median gain or a p95 total improvement. The prototype is removed; the sector-index cache remains. See the [rejected experiment](performance.md#rejected-direct-plane-id-lookup--september-29-2026) and [receipt](../results/rejected-direct-plane-lookup-20260929.json).

- **M4 moving-ceiling current-source check:** the tic-315 E1M1 sweep under PowerShell 7.6.6 exactly matches the prior candidate's 10/7/410/4,166 scene-difference counts at ceiling heights 0/6/34/68 and retains an exact HUD. This narrows the stale-evidence gap but remains a comparison to the adapted PowerShell renderer, not an original Doom executable; no new source defect was isolated. See the [receipt](../results/moving-sector-e1m1-height-sweep-r9-20260929.json).

- **Episode 1 human milestone:** R17 implementation commit 00405deebef6b4e8477c9c9316987b82fbc9064d passes a clean 543-file package check, 9/9 Episode 1 load/idle/render smoke, all-map 144-view stationary-discovery parity, and eight automap worker checks under official portable PowerShell 7.6.6. A four-second packaged E1M1 actual-device startup returns all 175,140 submitted frames and closes cleanly, with one queue-starvation observation after the final packet and no rebuffer resume. The 2 chainsaw, 69 transition, 97 boss, and 10 menu-input checks remain valid from R16 because R17 changes renderer discovery and telemetry, not gameplay/session code. These are not map completions. The one human HMP route remains pending through the E1M3 secret exit to E1M9, return to E1M4, and the E1M8 finale. Use the [R17 candidate receipt](../results/episode1-current-human-candidate-20260929-r17.json) and [playtest handoff](episode1-playtest.md); do not split the human run into map-by-map requests.
- **M4 rendering fidelity:** missing-texture wall bands retain sprite depth, and the E1M1 BON1 leak now has focused wall-silhouette clipping. Lower sprite silhouettes now anchor to actor world Z, matching the adopted renderer; this did not change sampled E1M1 actor masks through tic 245. Reused per-context clip records and worker scratch initialization pass the 36-map smoke, 119 fuzz checks, 20 masked-wall checks, and serial/worker tests in Classic, Matrix, and AnsiArt. A separate input-tic-140 audit found 13 reference-only `BON2B0` mask pixels where FastRenderer's nearer background depth suppresses the farther sprite; there were zero candidate-only full-scene pixels in that actor region. This does not reproduce the reported through-wall view. Broad scene differences persist. The raised-floor screenshot replays as lower-sector Techpillar sprites with classic Doom draw-order overlap. The blue-armor sighting is a pre-placed Gibs decoration; a two-camera, sixteen-heading sweep compares the two documented piles in 64 isolated views. One candidate-only mask pixel is explained by the actor palette index matching the reference floor at that plane pixel; this does not reproduce a through-wall leak or the exact reported angle. Continue targeted comparisons, especially moving geometry, without claiming independent original-executable visual parity ([depth audit](../results/actor-occlusion-depth-audit-human-prefix-tic140-20260928.json); [Gibs sweep](../results/episode1-pool-gibs-angle-sweep-20260928.json)).
- **M3 audio:** continue toward full-campaign continuity, audible quality and queue timing under renderer load. The Episode 1 loop catalog and finite D_INTRO path are prepared, but an actual-device queue-timing stall has been observed and the full campaign has not been heard through. The selected intermission background now warms during setup; four-episode Stats/Next images match their prior hashes, and isolated first-screen medians fall 7.84–8.88 ms after JIT/cache priming. This does not requalify audio continuity or the earlier single route. The IWAD map table references 27 distinct music-lump names with three byte-identical pairs (24 distinct payloads); Episode 1 covers nine. All D_E2M1–D_E2M9 are qualified, with eight new payloads because D_E2M5 duplicates D_E1M7. D_E3M1 and D_E3M4 are qualified aliases of D_E2M9 and D_E1M8. D_E3M2 is newly qualified with a two-period state recurrence proof and actual map/host checks. D_E3M3 now has a two-period recurrence qualification (488.714 seconds per period), matching 50-voice boundary states, and a verified E3M3 map/host path. D_E3M5 now has a two-period 150.857-second proof with 66 matching boundary voices and verified opening PCM. D_E3M6 has an 84-second complete-state proof, six reader/mixer checks, ten worker checks, fourteen map-selection checks, and a separate one-track local catalog. Its repeated actual-host trials still show intermittent packet-queue starvation, and doubling waveOut buffers did not stabilize the result. D_E3M7 adds a 105.6-second complete-state proof with 102 matching voices, an exact opening, focused worker/map-selection checks, and one clean two-second host startup. D_E3M8 adds a 96-second complete-state proof with 33 matching voices, an exact opening and focused tests; the two-second host returns 85,680 frames with a 1,260-frame canceled-tail upper bound. D_E3M9 adds a 549.457-second proof with 26 matching voices, an exact opening, focused tests and a clean two-second host start. Map-selection and short host checks now cover E2M4–E2M9 and E3M1–E3M9. These short checks do not qualify continuous campaign audio. D_E2M3–D_E2M9 each have separate one-track local catalogs; the prior 13-track E1/E2M1/E2M2 catalog is unchanged, and separate one-track D_E3M3, D_E3M5–D_E3M9 catalogs are qualified. All Episode 3 map-track names are qualified. D_BUNNY now has a 62-second complete-state loop proof and finale callback/playback checks; D_INTROA is finitely qualified but not selected by current Ultimate Doom code. Before long preparation, compare requested MUS hashes with existing qualifications; preserve alias map-name/catalog checks without repeating expensive output renders. Continue track-sized batches and keep offline costs visible.
- **M3 full-campaign catalog:** a 30-entry aggregate catalog now covers all 27 map-track names plus D_INTER, D_VICTOR and D_BUNNY. A 126-check integration covers actual callbacks for all 36 maps and Episode 1/Episode 3 finale transitions. A PowerShell 7.6.6 two-second headless waveOut run opens all 30 reports and returns all 86,940 submitted frames. Runtime validation checks 10.131 GiB of playback payload instead of rereading another 2.958 GiB of third-period proof data; warm wall-time samples do not establish a launch-speed gain. One queue-empty/rebuffer observation followed the final packet, with no mid-run observation. This does not certify uninterrupted campaign audio, acoustics or loaded device timing. See [music preparation](music-preparation.md#preparing-a-local-music-catalog) and the [catalog integration evidence](../results/music-ultimate-doom-campaign-catalog-integration-20260928-r5.json).
- **M3 audio endurance:** a 120-second PowerShell 7.6.6 headless E1M1 run with the full catalog crossed its 96-second music loop boundary, returned all 5,290,740 audio frames and closed waveOut cleanly. There was one 46.929 ms mix block over the 28.571 ms packet interval, but no queue-empty observation during active packets; the only rebuffer followed the final packet at shutdown. One no-input map does not qualify campaign transitions, audible quality or the human route. See the [run measurements](performance.md#two-minute-audio-loaded-headless-e1m1-run--september-28-2026).

September 28 interactive-audio follow-up: the audio worker now fills a free
waveOut slot from current music/effect state during temporary simulation-packet
gaps. Focused continuity, save/load/new-game, and four-second E3M6 host checks
report zero software queue starvation/rebuffer, and the source candidate passes
a fresh 36-map load/idle/render smoke. This bounded evidence does not measure
acoustics, physical device underruns, event-to-speaker latency, continuous
Episode 1 playback, or 35-tic/60-display pacing; see the [current candidate
receipt](../results/episode1-current-human-candidate-20260928-r3.json).
- **M3/M6 E3M6 loaded finding:** the initial 120-second 16-worker headless waveOut run reached 24.641 simulation tics/sec and 34.075 completed host render updates/sec, with 280 queue-starvation/rebuffer observations. Two 30-second worker-count samples at 8 and 12 workers reached 28.432 / 26.466 tics/sec and 30.665 / 31.799 host updates/sec. A same-workload runtime repeat then measured 33.497 / 34.932 tics/sec in two 7.6.5 runs and 27.632 / 28.365 in two 7.6.6 runs; a 120-second 7.6.5 session held 34.366, compared with the earlier 24.641 result on 7.6.6. Production source trees match across those source pins, so the runtime version is associated with the difference, but the small sample does not establish causality. Audio queue counters do not establish audible gaps, and headless updates are not display presentations. No game code or worker default changed. A serial 16-stripe profile attributes about 9.75 ms median per stripe to actor work and 4.07 ms to geometry; the attempted projection-division reorder showed no reliable gain and was reverted. See [loaded E3M6 measurements](performance.md#e3m6-worker-count-load-comparison--september-28-2026), [runtime comparison](performance.md#powershell-runtime-comparison-on-e3m6--september-28-2026), and the [portable runtime receipt](../results/music-host-e3m6-runtime-comparison-20260928.json).
- **M3 synthesis cost:** detailed profiling identified repeated envelope evaluation as the largest measured substage. An exact adjacent-envelope-endpoint cache showed 13.8% less process CPU in one D_E1M5 preparation slice and 21.3% less in a D_E3M3 slice, with matching PCM; an E1M1 low-polyphony slice used 4.7% more process CPU. The experiment was removed from game source because its changed `MusicSynth.ps1` hash invalidated every current loop qualification; the E1M5 reader reproduced that rejection, and the original source restored acceptance. It remains research evidence pending a source-equivalence/requalification design. These are offline preparation measurements, not live audio or frame-pacing claims. The separate in-place filter-array rewrite showed no measurable benefit and was reverted. See [music synthesis](music-synthesis.md#dense-mix-envelope-endpoint-trial--2026-09-28).
- **M6 performance:** the 35-tic/60-display goal remains open. A 120-second audio-loaded headless E1M1 run reached 34.991 simulation tics/sec and 48.258 completed host updates/sec; it does not measure Terminal presentations. The current-source PresentMon sample reports 47.73 display transitions/sec, 34.977 active tics/sec, and a 7.119-second asset-reload gap in one non-audio replay; the input ends at `ReplayEnd`, not a completed route. It is not paired with the earlier windowed run. The latest sequential E3M6 decode-plus-render profiles preserve the frame hash and reduce summed worker-equivalent CPU by 4.1% and 8.1%; they do not represent concurrent dispatch. A repeated live Terminal run with audio, effects, and moving geometry is still needed. A StringBuilder strip-assembly attempt is rejected after exact-output measurements showed 4.0–9.3x slower encoding and 83–103% more thread allocations; array-and-concatenate is restored. Keep isolated encoder/renderer/mixer timings separate from simulation, audio, output and displayed-frame claims; see [terminal output](terminal-output.md) and [renderer timings](performance.md#decode-worker-visible-actors-before-rasterization--september-28-2026).
- **M6 shared-renderer work:** Spectre actor order is now sorted once in the interpolated PowerShell snapshot instead of once per renderer process. The fixed E3M6, 16-stripe CPU profile preserves the full-frame pixel hash and reduces median summed render-plus-preparation CPU by 9.48%; sequential stripes are not concurrent worker time or displayed FPS. Actual 16-worker fuzz fixtures still match 320,000 pixels in each of Classic, Matrix and AnsiArt. This narrows duplicated renderer work but leaves live frame pacing unmeasured ([profile](../results/renderer-shared-fuzz-order-20260928.json); [details](performance.md#share-spectre-actor-ordering-across-renderer-workers--september-28-2026)).
- **M5/M7 release:** keep the broader Ultimate Doom release gates intact beyond the one Episode 1 playthrough, including the other maps, normal/secret behavior, independent compatibility boundaries, clean-checkout launch, licenses, package and write-up. The article now distinguishes earlier active E3M6 queue starvation from the single post-output-clock run with zero reported queue-starvation/rebuffer observations; it preserves the same-map reload and below-target simulation-rate limitations. Continue from reproducible product findings; a route death or slow/incomplete automated route alone is not an engine defect.

At that earlier checkpoint the Episode 1 human-test pin was `e35874146856f00bc9568957982719ab0efdc909`. The 2026-09-27 renderer scratch-reuse change (`3113b68`) preserves all pixels across 36 E1 views, matches 16-process output in all three styles, and passes a 36/36 map smoke. The ANSI strip array-and-concatenate path is retained: the later StringBuilder alternative matched bytes but measured 4.0–9.3x slower and 83–103% more allocating, so it was reverted. Strict color and 16-worker checks pass on the restored code. The newer handoff pin and readiness receipt are linked above; see also the [rejected encoder measurement](../results/ansi-strip-reuse-pinned-measurement-20260927.json).

- **M6 current-source worker comparison:** after actor culling, one 30-second sound-enabled, headless E3M6 run per worker count measured 34.70/31.90/33.70 simulation tics/sec and 29.30/30.60/30.30 completed host updates/sec for 8/12/16 workers. Eight used the least worker memory; twelve had the highest host-update rate; sixteen retained the highest simulation rate among the larger settings. Fixed-state process-pool medians were 55.60/44.22/43.39/45.93 ms at 4/8/12/16 workers. The samples were ordered, unpaired and headless, so they do not justify a default change or a 60-display claim. The 12-worker path matches serial output in five E1M1 views for all three styles. See the [performance entry](performance.md#current-source-worker-count-follow-up--september-28-2026) and [compact receipt](../results/worker-count-host-render-comparison-20260928.json).

- **M6 actor-mask bookkeeping trials:** pre-encoding masks during interpolation and replacing the host's per-actor worker scan with a 320-column lookup both passed output-equivalence checks but failed to show a repeatable full-dispatch gain. Both prototypes were reverted. The retained worker mask is now consumed during snapshot decoding to build each worker's visible-actor list; the later renderer profile measures that change separately ([rejected trials](performance.md#rejected-actor-mask-bookkeeping-shortcuts--september-28-2026), [current profile](performance.md#decode-worker-visible-actors-before-rasterization--september-28-2026)).
- **M6 packed map geometry:** per-seg/per-node hash tables are replaced by flat typed arrays in the PowerShell renderer and v7 render-asset cache. Thirty-six maps pass load/idle/render smoke; Classic, Matrix/Katakana, and AnsiArt/Katakana each match serial output across five views on 16 workers; a live E1M1-to-E1M2 asset reload keeps its workers. E3M6 stripe-render medians are directionally lower in two short candidate runs, with unchanged pixels; randomized paired dispatch and memory measurements remain open ([profile record](performance.md#pack-per-map-bsp-geometry--september-28-2026); [receipt](../results/packed-map-geometry-profile-20260928.json)).

### Historical milestone notes and task record

The following dated notes preserve experiment history and previous queue decisions; they are not the current task queue.

**Preview delivered, September 19:** `0.1.0-preview.1` was published with Classic/Matrix/AnsiArt, menus, saves, automap, sound effects, a simple launcher and source-inclusive asset-free ZIP. The repository is public and the preview remains a separate milestone from the full release. The Episode 1 handoff and the Ultimate Doom, Doom II, fidelity, audio and performance gates below remain active development work.

Current September 19 fidelity work: [palette presentation](palette-presentation.md) now carries damage, bonus, berserk and radiation selection through NumericV3 snapshots, assets and terminal workers. All280 focused checks, four actual worker-mode checks and the all-map/full-E1M2 packet regression pass. The700-command headless fixture passes24 integration checks with52 independent checkpoints and correct world/automap palette restoration. All three styles now pass55 recorded integrity checks. AnsiArt repeats vary sharply in pacing; neither integrity checks nor recording success certify playability. The external recorder fault is closed for this investigation as not reproduced in follow-up trials, cause unconfirmed; reopen on recurrence during useful game work. The user explicitly prioritizes game code over further recording-harness qualification. Next: concrete projection/rendering defects and measured game bottlenecks, with E1M5/secret routes, complete audio and remaining release gates still active. This adds no campaign completion or performance guarantee.

Latest September 19 optimization: [fuzz row precomputation](fuzz-performance.md) preserves all 30 paired full indexed-image/depth comparisons and all 119 focused checks. Actual worker tests pass in all styles; each new recording passes 34 checks and 17 unchanged replay checkpoints. Recorded Classic/Matrix/AnsiArt writes average 46.45/41.18/45.35 per second at about 34.9 game tics/sec, still below the target and with substantial gaps. Geometry remains the largest profiled render phase. The next concrete fidelity omission is palette selection for damage, bonuses, berserk and radiation protection: the current terminal codec uses only the base palette. Continue that work alongside projection, E1M5/secret-route qualification, audio and remaining release gates; no scope reduction or full-release claim.

Latest September 19 effect milestone: [invisibility and Spectres](rendering-fidelity.md) now use background fuzz, with timer/actor-flag transport, final-period blinking and correct precedence over weapon lighting. The implementation preserves worker-strip equivalence using a documented phase approximation. New version-tagged replay hashes cover the added fields while historical checkpoints remain comparable. All 119 focused checks pass. Three corrected live save fixtures each pass 34 capture checks and 17 independent checkpoints through living power expiry. They retain approximately 34.9 tics/sec but only 23.3–31.4 image writes/sec, with significant pacing gaps; optimize measured effect/scene cost without weakening coverage. Continue projection/palette fidelity, E1M5 and secret-route qualification, broader audio and the remaining release gates. These fixtures add no campaign completion or performance guarantee.

Latest September 19 fidelity milestone: [weapon lighting](rendering-fidelity.md) now follows sector/extra light, full-bright frames and fixed colormaps instead of always drawing full-bright. All 138 reference fixtures and three-style worker checks pass. The snapshot extension retains historical Schema1 checkpoint hashes with negative controls; all-map endpoint and full-route tests pass. Recorded Classic continuation passes 65 checks at 34.980 tics/sec and 56.565 image writes/sec, with pacing/audio limits retained. Continue invisibility/projection/palette fidelity and E1M5/secret-route qualification; no full-release or 60-display claim.

Latest September 19 encoder experiment: [independent ANSI color state](ansi-color-state.md) preserves exact decoded RGB in 13 cases and actual Classic/Matrix worker output. Four recorded E1M2 continuations pass 65 checks each. ColorState reduces live bytes/image by approximately 15%, but whole-game comparisons change direction; Pairs remains default. Unchanged renderer timings also vary substantially between trials. Improve condition telemetry or pair measurements more closely before further causal full-game performance claims. Continue weapon/effect and projection fidelity, plus E1M5/secret-route qualification; this experiment does not replace those release gates.

Latest September 19 presentation experiment: [terminal write granularity](terminal-output.md) preserves bytes in 72 codec checks and completes four recorded E1M2 continuations, each passing 58 integration checks. Batching lowers measured host output time, but whole-game throughput varies widely and does not improve consistently. Keep Strips as default and retain Batch for explicit experiments. Investigate redundant ANSI color traffic and frame-stage variation without losing the campaign/fidelity work below; the full release gates remain unchanged.

Latest September 19 milestone: [numeric lighting and reference corrections](rendering-fidelity.md) are implemented and verified through the actual Classic host. All 2,816 lighting-table bins match the adopted reference; E1M1 image disagreement falls substantially against the corrected reference, and 144 discovery cases retain their earlier results. The first host attempt exposed a helper import dependency and was fixed; the retry passes 53 checks through E1M3. Its 34.9768 tics/sec and 50.5017 console writes/sec leave 60-display pacing open. Continue remaining projection/texture and weapon/effect fidelity, measured presentation bottlenecks, and E1M5/secret-route qualification. Keep the full Ultimate Doom release gates intact.

September 19 recorded milestone: [E1M4 AnsiArt continuation](campaign-e1m4.md) passes 51 integration checks and all 22 route checkpoints through E1M5, with all 7,998,480 audio frames returned. The run averages 34.250 tics/sec and 50.491 console writes/sec; six queue-empty observations and a 215.250-ms worst same-world write gap remain. Preserve the footage and source-pinned receipt. The fixed-colormap rendering diagnostic substantially reduces scene disagreement and identifies lighting-table/selection comparison as a concrete next rendering task; no production lighting change or full-fidelity claim yet. Campaign E1M5 completion remains open.

September 19 rendering milestone: [reference comparisons and HUD repairs](rendering-fidelity.md) now cover 64 exact HUD states and actual Matrix/katakana worker output. Broader 3D fidelity remains open. E1M5 candidate seven died after 8,369 ordinary commands before completing the central medkit detour; preserve it as a route failure without an engine-defect claim. Its music preparation completed successfully. Balance campaign qualification with rendering diagnosis, measured pacing and follow-up to the completed E1M4 continuation recording.

September 19 E1M5 continuation: the [route investigation](campaign-e1m5-investigation.md) retains displaced-barrel, closed-passage, ammunition and explosion failures. The ordinary eastern trigger and yellow-key route now work in candidate runs; the western switch and remaining completion still require qualification. An optional barrel-clearing driver is being checked against unchanged default behavior. The [working article](article-draft.md) now connects the architecture, visual styles, measurements and campaign findings for readers; it does not claim a finished release or superiority over untested alternatives.

Historical continuation record: [E1M2 normal completion](campaign-e1m2.md) is independently qualified from an HMP pistol start, then recorded in AnsiArt through intermission into E1M3. All 3,233 commands, 13 checkpoints and 4,073,580 returned audio frames pass the 42-check capture audit. A real queue-overflow failure led to bounded producer waiting before the next tic; eight saturated-queue/control checks and 15 save-worker checks pass. The successful recording still has 17 unexpected pre-shutdown empty queues, 33.857 active tics/sec and 59.074 active console writes/sec. It does not qualify sustained 35-tic/60-display or uninterrupted audio. E1M1, E1M2, intermission, E1M3, E1M4 and E1M9 have qualified dry loops through the [finite preparation command](music-preparation.md). The [E1M3 normal route](campaign-e1m3.md) now completes and independently matches 198 samples and 24 checkpoints through inventory-preserving E1M4 entry. The [investigation](campaign-routing.md) retains the failed attempts and resulting hazard/stair fixes. A [fractional camera snapshot correction](snapshot-fractions.md) passes 28 real-world checks. The first Matrix E1M3 recording failed from input backlog; bounded command admission now preserves a 1,200-command prefix and all audio frames, initially at about 19.4 ticks/sec (see [command admission](command-admission.md)). [Shared numeric snapshots](direct-snapshots.md) now preserve every tested packet/checkpoint and improve that same real-host prefix to 23.8 ticks/sec; the 35/60 target remains open. The [numeric visibility change](numeric-visibility.md) preserves 44,424 side comparisons and all full E1M3 checkpoints, improving the headless prefix to 29.7 tics/sec. Its recorded full Matrix route reaches E1M4 at 30.5 tics/sec with all 24 checkpoints, but the audio audit exposes 23 unconsumed tail packets at shutdown. The bounded replay-end drain is now repaired: the third recording passes all 47 integration checks and returns all 8,968,680 audio frames. It still averages 29.983 tics/sec and only 47.965 console writes/sec, with 77 pre-final queue-empty observations. Retained timing analysis shows increased output/worker delays across the route; causal attribution remains open. Investigate that variation and reduce measured automap discovery cost, then remaining sight work. The [indexed discovery implementation](automap-discovery-performance.md) now preserves 7,002 full-route fresh mapping states, all 24 original checkpoints and 144 headings across all 36 maps. Its real loaded prefix improves to 30.829 tics/sec with all audio frames returned; eight automap save/load/menu/new-game checks pass. The dictionary cache alternative was slower and rejected. E1M4 dropped-weapon routing now qualifies; its E1M5 continuation remains part of the current one-human-playthrough milestone above. A separate [numeric movement-gate fix](mobj-movement-gates.md) passes 27 focused assertions and all three existing normal-route regressions. E1M4 now completes with ordinary dropped-weapon collection and the intended staircase/bridge: the [qualified route](campaign-e1m4.md) preserves 176 samples, one exact weapon-acquisition event, 22 checkpoints and inventory through E1M5 entry. Six failed candidates remain in the [investigation](campaign-e1m4-investigation.md). The earlier seven-track E1M5 music set later expanded to the complete eleven-track Episode 1 catalog, including D_VICTOR; see [music preparation](music-preparation.md). The earlier next step to continue E1M5 routes was superseded by the current one-human-playthrough milestone above. Preserve all four completed normal routes as regressions. Boss endings, full-campaign continuity, reference fidelity, repeated pacing, acoustic checks and packaging remain open.

1. Completed first step: all 36 Ultimate Doom maps pass the load/35-idle-tic/two-frame smoke sweep after fixing E2M7 line-flag conversion. See [campaign matrix](campaign-matrix.md). This is smoke coverage only.
2. Controller routing/finale/par/secret-history fixes pass 57 isolated checks, including carryover and death/respawn. Broader boss/exit behavioral qualification remains in M5.
3. The historical ordinary-input E1M1 -> intermission -> E1M2 route used generation-checked asset refresh in persistent workers, but its preserved input now dies before intermission on current source. Keep the old record as history; do not retune the automated route from stale input. A human campaign playthrough is still required.
4. Versioned input recording is implemented with asset/source hashes, starting settings, overwrite protection and selected-state checkpoints. The full session matches eight checkpoints on replay; an altered command produces a nonzero divergence failure. See [input recording](input-recording.md). Physical keyboard use remains unobserved.
5. Menus/new-game/pause and replayed new-game controls pass the [menu milestone](menus.md). [Save/load](save-load.md) now has six integrated slots, overwrite/load confirmations, source-version warnings, isolated candidate loading and immutable replay archives. The core has 90 named checks; integrated host tests restore gameplay/intermission/finale, and three live save-menu captures replay all four checkpoints each. Footage retains the pre-correction time labels; the final local-time fix has its own regression and compatible replay. Automap is integrated; numeric discovery matches 2,139 angle cases and 48 moving-route poses, and numeric discovery/encoding recover approximately 35-tic/60-update averages on the bounded control fixture. Timing spikes, broader moving-world discovery and display qualification remain open. Persistent input settings are implemented; the settings menu now separates effects volume, music volume and effects mute. Music selection/playback qualification, acoustic review and remaining audio work are still open. Keep the dim Matrix menus and sampled partial redraw visible in presentation qualification; the engine-bundle cache now publishes atomically under concurrent builders.
6. Present a small physical-play checklist only after the relevant controls/UI are implemented. The scope and audio boundary are now resolved; no user input blocks the next implementation work.

Reproduce the current foundation checks from PowerShell 7 with fresh output paths:

```powershell
.\scripts\Test-LineFlags.ps1 -Output .\local\my-line-flags.json
.\scripts\Test-CampaignSmoke.ps1 -Output .\local\my-campaign-smoke.json
.\scripts\Test-E1M1Route.ps1 -Output .\local\my-e1m1-route.json
```

The first two harnesses refuse an existing output file. Their default IWAD is the already-installed Steam Ultimate Doom copy; supply `-Wad` for another location on the campaign/route scripts. The smoke test deliberately renders serially and should not be used as an FPS benchmark.

## Alternatives and decisions to revisit

| Choice | Existing evidence | Next fair experiment |
| --- | --- | --- |
| Adopted PowerShell gameplay core + new rasterizer | Working E1M1 route; upstream attribution retained | Broader correctness, same-state reference renderer comparisons |
| Upstream PowerShell reference renderer | Source retained; earlier baseline was slower | Same scene, same resolution/features, documented host and timing boundary |
| Persistent processes versus runspaces | Tested process design won earlier workloads; memory cost is substantial | Matched current snapshots/render kernel, warm steady state, worker scaling, startup/RAM; do not generalize early failures to all runspace designs |
| ANSI output encoding | `Pairs` is exact truecolor; `ColorState` keeps exact RGB with fewer color instructions; optional `Ansi256` uses nearest indexed colors and cuts one identical frame's bytes 28.65%. The live comparison is inconclusive. | Repeat interleaved real-game sessions at matched state and capture machine-load conditions; compare bytes/frame and output/presentation pacing separately |
| Truecolor ANSI versus Sixel/image protocols | ANSI currently works; Sixel has isolated tests | Parallel encoding plus actual terminal presentation, same pixels and physical image size, emulator/version recorded |
| Full-frame versus changed-region output | Full-frame baseline known | Static UI/HUD and moving-camera workloads; include comparison/encoding overhead |
| Other PowerShell Doom implementations | Source survey exists, some reproduced scene work | Refresh commits/licenses; compare supported behavior separately from comparable performance cases |
| Compiled native/C# terminal Doom | Important practical control outside the language constraint | Show efficiency/fidelity/install tradeoffs openly; never label shell launching as a PowerShell engine |
| Audio implementation routes | PowerShell effects mixer and integrated waveOut playback; MUS/SF2 readers verified offline | Qualify PowerShell synthesis against a reference, bank provenance and polyphony cost; integrate score/session controls and measure audiovisual latency |

The [existing-offerings survey](existing-implementations.md) and earlier [experiment protocol](experiment-protocol.md) remain evidence, with their original workload limitations. Primary README/source claims were refreshed on 2026-09-28; equivalent builds and workloads have not been benchmarked, so no new competitor ranking has been established.

## Visual-style exploration

The user raised and authorized an optional Matrix/ANSI-art direction after the campaign roadmap. `-Style AnsiArt` and `-Style Matrix` are now implemented in PowerShell over the shared gameplay, assets, simulation, and 320×200 source framebuffer. They emit 160×50 character cells with a block HUD; Classic remains the default. See [character modes](character-modes.md) for the actual algorithms, evidence, launch commands, and limitations. No GPU effect has been implemented. A general-purpose effect for other games would be a distinct project if pursued.

The existing output is already truecolor ANSI: each upper-half-block character carries two independently colored pixels. ANSI describes color/cursor control, not an obligation to draw recognizable letters. The proposed art mode would deliberately expose glyph shapes.

| Proposed mode | Work | Evidence status |
| --- | --- | --- |
| Green phosphor blocks | Remap the startup palette to green intensity levels; retain current half-block encoder | Small implementation change inferred from existing palette lookup; appearance/performance untested |
| Truecolor character art | Sample image regions, choose glyphs from brightness/edge shape, color them from the Doom image | Implemented; independent codec and actual worker partition tests; loses pixel-level detail by design |
| Matrix character art | Green contrast curve, spatially stable code, sparse moving leaders and fades, block HUD | Implemented; deterministic animation and seam tests; no previous-frame trails; live results in character-mode findings |
| Optional Terminal shader | HLSL post-processing for glow, scanlines, tint, procedural code or image-to-glyph effects | Microsoft documents an experimental terminal texture/time shader hook; compiled GPU effect must be declared separately from the PowerShell implementation |
| General game post-process | Implement a reusable character/Matrix effect in a framework such as ReShade | Separate compatibility/performance project; does not run other games in PowerShell or automatically transport them into a terminal |

Microsoft's [Terminal shader sample](https://github.com/microsoft/terminal/blob/main/samples/PixelShaders/README.md) provides the terminal image, time, scale and resolution; it does not provide Doom's geometry or object identities. Effects derived from image colors are plausible. Geometry-attached symbols, object-specific effects, or persistent trails need additional design/state rather than assuming a simple tint supplies them. [ReShade's upstream description](https://github.com/crosire/reshade) establishes a general game post-processing route, with actual compatibility to be tested per target.

The first experiment uses a PowerShell character encoder over fixed real-game captures, followed by live replay measurements. The glyph view is a stylized, lossy representation of the 320×200 source image; retain Classic for fidelity comparisons. The prototype does not reduce simulation or omit scene actors to make room for the effect. Human playability, dark-scene tuning, and temporal artifacts remain feedback/qualification work. Shader-based embellishments are an explicit alternative to the all-PowerShell style path, not silently included in its performance claim. Campaign progression remains the next main release milestone after this optional display prototype.

The Japanese-glyph follow-up is implemented for both styles, with half-width katakana and an explicit MS Gothic profile. Two complete E1M1 screen recordings and repeatable window-capture/export scripts are available; see [recordings and validation](recordings.md). Those recorded runs sustain approximately 35 simulation tics and 60 console writes per second, while movie frame rate remains separate from unique displayed game frames. Three newer [campaign-session captures](campaign-session.md#actual-terminal-recordings) verify E1M1 → E1M2 and retain their slower 58.2–59.4 writes/sec plus roughly 0.9-second asset handoff. Small text is harder to read in character styles; M2 must provide readable menus. Broader automap qualification and audio are next; save/load and menu recordings are documented in the immediate queue.

## Write-up structure

Working subject: **Doom in PowerShell: how far can a terminal go?**

1. The challenge and exact meaning of "PowerShell Doom."
2. What already existed, credited accurately, with separate language/display/feature boundaries.
3. Source lineage and why this gameplay foundation was chosen.
4. Experiments that failed, measurements that misled us, and corrections—including output versus display FPS and the user-resized 98-row window.
5. The current architecture: simulation, snapshots, process rendering, encoding, terminal composition, input, and audio.
6. Campaign and visual correctness: what the tests prove and what they cannot prove.
7. Controlled performance comparisons and cost: pacing, throughput, memory, startup, and hardware dependence.
8. Playing it: installation, user-owned assets, controls, display fit, short play footage, and known limits.
9. Where this approach wins under the stated constraints, where alternatives win, and what could improve next.

Write sections from completed evidence as work proceeds. Figures/tables must name their raw input files and measurement boundaries. Keep user-derived screenshots/recordings local until publication rights and an explicit publication request are handled. Documentation in the repo is authorized; creating a public repository, publishing an article, or contacting upstream authors is a separate action.

## Collaboration and continuity

The user supplies priorities, already-installed legitimate assets, and occasional physical play/audio/display feedback. They do not need to design the engine or choose routine implementation details. Ask short questions at actual decision points; continue independent work while awaiting optional preferences.

Each work session should update this plan's current milestone, the campaign matrix, and `docs/ledger.md`; preserve raw failures, run relevant checks, and leave a reviewable local commit. Keep experiments finite and clean up only owned resources. No scheduled/background work is created by this plan. Duration estimates should follow measured milestone progress rather than a promise based on the E1M1 prototype.

Latest fidelity correction (2026-09-12): [type-16 damaging floors](sector-damage.md) now share the intended type-4 handler; 512 isolated real-object checks and existing E1M1/E1M2 input continuations pass. The E1M3 fourteenth failure was environmental pit damage, correcting an earlier combat diagnosis. The conservative walkway route now qualifies E1M3 normal completion and headless E1M4 entry after a separate [stair-building fix](stair-building.md), whose 86 checks pass. Terminal playback and remaining campaign coverage stay open.

## Current release instruction — September 29, 2026

The user requested autonomous work across the full Ultimate Doom gates, retaining PowerShell gameplay/rendering/audio algorithms and all three styles, with reviewable commits, measurements, documentation and local effect-test footage. Cut a release at 35 or more commits since the prior release. Preview.4 preparation follows 80 commits after Preview.3. Its [scope](release-preview4.md) and [fresh validation](../results/preview4-validation-20260929.json) keep the unfinished campaign, acoustic, display and independent-fidelity gates explicit. Continue useful implementation/qualification between milestones; the pending human Episode 1 milestone does not block independent work.

## Resumed development — October 1, 2026

Preview.4 was published and its downloaded ZIP verified against the local archive; see the [package receipt](../results/preview4-package-validation-20260929.json). It supersedes the historical Preview.3 publication status in the milestone table above. The full release remains unqualified.

Development now restores [pickup/key-lock notices](player-notices.md) with the original IWAD font in Classic and readable terminal lettering in Matrix/AnsiArt. The first actual Classic performance run exposed a missing host codec import despite passing focused/headless checks. That dependency is fixed, and three live save-fixture recordings now consume all 350 commands and match eleven checkpoints each. Their original media/audio/clock metadata remain local. They do not complete maps. The independent E1M1 route and continuation through intermission into E1M2 remain passing regressions.

The next performance evidence uses the [frozen numerical protocol](release-performance-protocol.md): sequential live routes with audio, explicit launch timing, owned-process CPU/memory samples and ETW display events, including transition holds. Repeated pacing, full-campaign play, independent original-executable fidelity, acoustic/physical-input review and second-hardware/display qualification remain open. Keep the complete Ultimate Doom scope and the one full Episode 1 human route intact.

Map-handoff investigation now isolates and caches repeated WAD-resource conversion/serialization. Three ABBA stage cycles reduce preparation from 4.09–4.90 seconds to 81–112 ms with identical image hashes; initial cache construction, worker read-back and total load remain separate. Sixteen-worker reloads across three episode skies pass all styles. This change follows R18 and is not included in that frozen handoff ZIP. See the [stage receipt](../results/map-render-resource-cache-20261001.json); full loaded pacing and release gates remain open.

Verified-body reuse inside persistent workers then reduces isolated read-back to 69–81 ms. Three live Classic/audio routes at `cfd8c26` measure complete map loads of 1.54–2.03 seconds and sampled private memory of 4.47–4.60 GiB, but still miss pacing thresholds. The slowest run localizes E1M2 terminal output at 85.8 ms per call on average, while the host also supplies simulation commands. Output/input decoupling and paired byte-path measurements are the next performance investigation. See the [three-run receipt](../results/reader-cache-loaded-classic-20261001.json). Full campaign, independent fidelity, physical/acoustic and second-hardware gates remain open.

Experimental bounded AsyncBatch output subsequently passes byte-exact and real-pipe ownership/backpressure/error tests. One same-source ABBA cycle retains 34.975–34.979 active tics/sec and lower p99 simulation lateness in its asynchronous runs (60–65 ms versus 166–273 ms), while all display rates still fall below the release threshold. Strips remains the default. Resize/compact-menu output is guarded against interleaving; final-source all-style live fixture recordings are being qualified. [ABBA evidence](../results/output-abba-classic-20261001.json).

Final-source AsyncBatch recordings now pass in Classic, Matrix and AnsiArt: 350 commands, eleven checkpoints per run and 24 grouped notice/audio/media audits. Failed WGC finalization and unusable GDI attempts are retained separately; successful WGC retries provide the reviewed footage. [Recording receipt](../results/async-player-notices-live-20261001.json). R18 remains frozen for comparison; the later [R19 candidate](candidate-r19.md) now packages these changes and passes extracted manifest/preflight, output/cache/menu/save, all-style sixteen-worker and short actual-device startup checks. [Package receipt](../results/r19-playtest-package-validation-20261001.json). Remaining full-release gates stay open.

Three subsequent live Classic encoding ABBA cycles retain every command/audio frame but pass no complete numerical pacing gate. With AsyncBatch fixed, ColorState reduces median observed bytes/frame 14.73% and raises median global display events from 51.668 to 53.750/sec; per-cycle gains vary from 0.03% to 8.86%. A slow ColorState run and final-drain rate failure are investigated and retained. Defaults remain Pairs/Strips. Transition display gaps (1.24–2.92 seconds), broader workloads/styles, original-executable fidelity, human campaign and physical/acoustic/second-hardware checks remain open. [Twelve-run evidence](../results/colorstate-abba-classic-r19-20261001.json).

Later development adds [pollable worker reloads and separate loading feedback](loading-screen.md), with all-style worker/image/ownership tests, a corrupt-owned-asset failure check, 84 UI bounds cases and actual route/save recordings. Loading updates receive no gameplay FPS credit. The recorded ordinary route's first loading completion observation still takes about 990 ms; repeated clean display measurements and tighter task-completion observations remain needed. R19 and Preview.4 remain frozen. [Live lifecycle receipt](../results/loading-ui-live-20261001.json).

## Continued qualification — October 2, 2026 (UTC)

Completion brackets confirm the first loading Task stays pending for about983 ms
in three clean repeats. Owned PowerShell renderer logs remove thirty-two idle
host pipe readers; three corresponding upper bounds fall below2.72 ms and
startup falls to about27 seconds. All-style reload/fault checks preserve images
and process ownership. [Loading investigation](loading-screen.md).

Controlled300/700 ms audio producer gaps reproduce permanent312.7/711.6 ms
packet-age tails. Realtime output now credits already-covered intervals and
applies caught-up controls/events on its current clock. Ninety-six existing
audio/save assertions plus three recovery cases pass. Three final clean routes
have zero producer-backpressure waits and65–85 ms median processing ages,
but52.6–53.8 global display events/sec and early simulation stalls still fail
the release gates. [Controlled evidence](../results/audio-realtime-recovery-20261002.json),
[loaded measurements](../results/audio-recovery-loaded-classic-20261002.json),
[actual recorded effects/handoff](../results/audio-recovery-live-20261002.json).

The [R20 development handoff](candidate-r20.md) prepares these fixes for the
whole E1 human route with fresh saves/input/reports and preserves R19. Extracted
package validation follows. Continue broader workload/alternative pacing and
initial-stall diagnosis, original-executable moving-world parity, physical
input/resize/acoustics and remaining campaigns. Human E1 completion remains
pending and does not prevent that useful work. Public release count reaches24
with this preparation; publish a new release at35 or more, as requested.

R20 extracted validation now passes: 557 manifest hashes and exact archive
contents, final recorded source matching, 36-map/eleven-track preflight under
PowerShell7.6.6, output/resource/menu/save/recovery checks, all-style actual
sixteen-worker reload/fault/image oracles and an eight-second actual-device
startup with every submitted frame returned. The [package receipt](../results/r20-playtest-package-validation-20261002.json)
and [whole-E1 guide](episode1-playtest.md) identify the checked archive/extraction.
Public release count is25 after this validation commit; Preview.4 remains the
latest public release and the35-commit rule remains active.

Early-stall diagnosis subsequently finds a command published789 ms late with
an empty queue and a worker update starting about0.28 ms after signaling in
one clean route. A bounded host catch-up loop now publishes only already-due
commands, preserves the two-command window and stops at exact replay-control
boundaries. All-style headless save/checkpoint/audio and synthetic viewport
checks pass; Matrix exercises one two-command burst. Native repeated pacing
and live control qualification follow. [Diagnostic](../results/command-publication-stall-diagnostic-20261002.json),
[fixture coverage and limits](../results/command-burst-fixtures-20261002.json).
Public release count reaches27 with this change; R20 remains frozen.

Three clean native repeats retain all commands/audio but fail full numerical
pacing gates; the second preserves substantial synchronous-output overlap
at its worst producer delay. Subsequent all-style WGC/audio save fixtures pass
350 commands, eleven checkpoints, all-input/credit/PCM accounting and reviewed
notice/style samples. [Clean evidence](../results/command-burst-loaded-classic-20261002.json),
[live coverage and limits](../results/command-burst-live-20261002.json).
Three paired Strips/AsyncBatch ABBA cycles on this runtime follow before any
default change. Public release count reaches29; publish at35 or more.

The twelve-run paired study now completes. AsyncBatch lowers median p99 tic
lateness in all three cycles, while display-rate changes vary−1.65% to+3.47%.
No complete numerical gate passes; all commands/audio and source/accounting
audits pass. A retained1.576-second display-event gap contains96 completed
game writes and94 dropped presents, keeping writes distinct from display.
[Paired receipt and investigated failures](../results/command-output-abba-classic-20261002.json).
Defaults remain Strips/Pairs; continue concrete frame-cost, independent
moving-world fidelity and broader-workload work rather than repeating this
unchanged comparison. Public release count reaches30; the35-commit rule and
all broader release gates remain active.

An independent original-binary diagnostic now observes a matching paused input315 wall/pistol view. Exact demo preparation, candidate pause and repeated indexed images pass, but the retained original image is JPEG and no raw framebuffer or hidden state trace was captured. A further visible launch was rejected before execution by automatic approval review. [Receipt and limits](../results/original-doom-frozen-fixture-20261002.json). Full independent fidelity remains open. Public count reaches31; continue useful frame-cost/broader-workload work and publish at35 or more.

Frame-cost attribution now finds longer E1M2 worker spans and isolates wall traversal/drawing in a fixed startup view. An opt-in PowerShell profiler splits geometry stages and preserves exact images; default all-style16-worker tests match the prior renderer's960,000 pixels/240 encoded strips. [Live stage audit](../results/host-frame-cost-audit-20261002.json), [profile/equality evidence](../results/geometry-stage-profile-20261002.json). No pacing gain is claimed. Next investigate the wall loop with exact-output controls; full campaign/fidelity/physical/acoustic/hardware gates remain open. Public count reaches32; publish at35 or more.

A local power-of-two wall-wrapping trial now retains all twelve fixed-state image/stripe hashes across three ABBA cycles, but all cycle median stripe totals regress and the final slowest stripe is6.61% worse. The trial is rejected and never enters production. [Retained failure to improve](../results/rejected-wall-texture-wrap-20261002.json). Continue a different investigation or broader qualification; public count reaches33, with a new public release due at35 or more.

Preview.5 preparation now packages the accumulated post-Preview.4 fixes with explicit limits, refreshed play instructions and fresh whole-E1 output paths. [Scope](release-preview5.md). Count reaches34 with preparation; extracted validation and immediate public release at35 follow. This cadence release remains a playable community preview; the complete Ultimate Doom objective and acceptance gates remain active.

Preview.5 extracted validation completes:559 manifest/Git payloads,36-map smoke,
output/resource/menu/save/recovery checks, all-style persistent worker oracles
and350-command/eleven-checkpoint admission fixtures. Actual device startup
returns every submitted frame. [Receipt and exact boundaries](../results/preview5-package-validation-20261002.json).
Count reaches35 with this evidence; tag/publish now and verify the public assets.
The archive pins preparation source34, while tag35 adds validation. This is a
cadence community preview; all full Ultimate Doom gates remain active.

Preview.5 is now public at the requested35-commit threshold. A fresh public
download matches the tested ZIP/checksum and GitHub digests, all559 payloads
pass, and all478 runtime payloads match the release tag. [Publication receipt](../results/preview5-publication-20261002.json).
The cadence resets at Preview.5; the evidence commit starts the next count at1.
The full Ultimate Doom release goal remains active, with the explicit remaining
campaign/fidelity/pacing/physical/acoustic/hardware gates unchanged.

Dense E3M6 qualification now retains nine clean source-pinned native stress
captures across all modes. All420 commands/two checkpoints/audio accounting
repeat, but the player dies and every numerical pacing gate fails: active rates
28.6–30.8 tics/sec and39.5–47.2 display events/sec. [Receipt and scope](../results/preview5-e3m6-all-style-pacing-20261002.json).
Audio/music resource use is included inside the sampled simulation process;
the earlier separate-process omission claim is corrected by source and live
process-ID evidence. Sampling still omits unsampled startup/tails and excludes
Terminal from game totals. Investigate command publication/worker-count costs
and record effects separately. Preview.5 stays frozen; new release count reaches2.

Audio ownership is now directly verified: its in-process runspace shares the
simulation PID already sampled by PresentMon's collector. The earlier separate
process omission claim was incorrect; reports/docs retain an explicit correction
without changing the nine-run measurements. [Source/live identity and save checks](../results/audio-process-ownership-20261002.json).
Additive PID/scope metadata passes the native420-command endpoint/PCM check
and15 music-enabled save/load assertions. Continue worker-count/publication
investigation and dense effect recordings. Release count reaches3 after Preview.5.

Dense effect recordings now finish in all three styles on frozen source, with420
commands/two endpoints,36-source identity and complete packet/PCM accounting.
Six reviewed movie samples preserve pickup/damage/HUD and each style. Startup
outside loopback coverage and24–26 ms near-tail capture gaps remain explicit;
these are loaded effect recordings, not clean pacing/acoustic/navigation proof.
[Receipt](../results/e3m6-effects-live-20261002.json). Continue paired16/8-worker
cost investigation; release count reaches4 after Preview.5.

Three paired Classic16/8/8/16 cycles now retain all commands/endpoints/audio.
Eight workers improve simulation rate10–14% and p99 lateness69–72%, with lower
sampled CPU/memory, but reduce display-event rate8–10%; no full gate passes.
[Exact controls, resource tradeoff and retained PID-reuse audit failure](../results/e3m6-worker-count-abba-20261002.json).
Keep16 primary/default. Continue the ignored current-endpoint snapshot trial
with all-map/replay byte equality before adoption. Count reaches5 after Preview.5;
all campaign/fidelity/physical/acoustic/hardware gates remain active.

Three exact-byte snapshot packing trials are retained and rejected: small/mixed
gains do not justify adoption. A [twelve-run command-stage audit](../results/e3m6-command-stage-audit-20261002.json)
identifies5.4–5.9 ms/tic automap discovery omitted from the earlier update-plus-
snapshot account. Discovery while hidden preserves mapped lines and must remain.
Investigate that path with full mapped-state oracles next. Count reaches6 after
Preview.5; full release gates remain active.

The preliminary position-angle discovery trial now preserves420 fresh mapped
states/two endpoints,144 all-map headings and11 invalidations, but reuses only27
calls and has a slightly slower overall mean. [Retained unadopted trial](../results/discovery-position-angle-trial-20261002.json).
Profile existing traversal before further cache changes. Count reaches7 after
Preview.5; all full Ultimate Doom gates remain active.

The dense discovery profile now preserves all420 mapped states/two endpoints
and identifies bounding-box/angle work: about95 numeric angle calls per tic,
with overlapping instrumented scopes and explicit overhead. [Receipt](../results/e3m6-discovery-method-profile-20261002.json).
Continue a bounded exact slope/angle trial before any source adoption; count
reaches8 after Preview.5. All full Ultimate Doom gates remain active.

The exact numeric discovery slope calculation is now adopted in PowerShell.
It passes20,900 prior-method angles,20,509 integer quotients, fresh mapped-line
oracles and actual automap/save/audio workers. Three method ABBA cycles reduce
batch time about55%; native pacing is still unmeasured for this change.
[Production evidence, bounded division argument and retained stale-input failure](../results/discovery-slope-production-20261002.json).
Count reaches9 after Preview.5. Measure the committed primary16-worker build
in all modes with the unchanged full-catalog dense input, then record effects
separately. All full Ultimate Doom gates remain active.

Nine committed-source dense repeats now retain all commands/endpoints/audio
but fail the full numerical pacing gates in every style: active rates30.3–32.8
tics/sec, display events41.6–47.6/sec. Historical comparisons are unpaired.
[Native receipt](../results/discovery-slope-native-pacing-20261002.json).
Separate actual effect recordings preserve all three modes and pass56
consistency checks, with a failed first recorder and an active20ms Matrix
loopback-coverage gap retained. [Recording receipt](../results/discovery-slope-effects-live-20261002.json).
Count reaches10 after Preview.5. Continue focused rendering arithmetic and
moving-world fidelity work; all full Ultimate Doom gates remain active.

Focused review now reproduces and corrects fractional rounding/unsigned wrap
in the shared sprite-angle helper. Expanded old-source tests fail; corrected
production passes exact angles/boundaries,21 snapshot checks and all-mode
960,000 worker pixels/240 strips. [Correction evidence](../results/sprite-slope-correction-20261002.json).
Count reaches11 after Preview.5. Record actual effects on the corrected
committed source, then continue independent moving-world fidelity. Prior
native measurements remain pinned to the earlier build; all full gates stay
active.

The corrected sprite build now has actual Classic/Matrix/color-art WGC/audio
recordings with37 unchanged source pins and56 consistency checks. All420
commands/two checkpoints/audio reconcile. Reviewed effect samples preserve
the three styles; these runs have no uncovered interval inside gameplay
writes, while startup/post-game gaps and the prior-build Matrix gap remain.
[Current-build recording and limits](../results/sprite-slope-effects-live-20261002.json).
Count reaches12 after Preview.5. Continue remaining fidelity, correctness and
measured bottleneck work; full human campaign/physical/acoustic/DPI/hardware
qualification remains open.

The adopted comparator now truncates unsigned inverse wall scale in its three
wall paths, matching the pinned C# source and 60,066 independent integer checks.
Its prior rounded expressions fail 30,024 cases. Retained frozen-ceiling images
show changed reference panels and unchanged candidate panels; this is a comparator
correction, not candidate-fidelity progress. Fresh discovery and stress endpoints
remain exact. [Evidence and limits](../results/reference-wall-inverse-scale-20261002.json).
Count reaches 13 after Preview.5. Isolate candidate wall vertical sampling next;
all full-release gates remain active, with another release due at 35 commits.

Candidate opaque/masked wall texels now use quantized anchors and inverse scale.
The retained baseline fails 293,120 authored samples; production passes 28.1
million across four heights, 20 depth/order checks, all-style actual workers and
36-map idle smoke. Static comparisons improve overall in E1M2 but worsen selected
views; later dense serial cost cycles remain 4–6% slower. This qualifies a narrow
arithmetic correction, with full fidelity/pacing/campaign gates open.
[Production, alternatives and limits](../results/wall-vertical-sampling-20261002.json).
Count reaches 14 after Preview.5. Record actual committed-source effects next;
release again at 35 commits since the prior public release.

Actual committed-source wall-build recordings now pass 56 digital consistency
checks in all three modes, with 37 source pins and reviewed pickup/damage frames.
Every stress command/checkpoint and audio credit reconciles; all owned PIDs end.
Startup/post-game capture gaps and prior failures remain explicit. These recorded
runs establish neither clean pacing nor acoustic/full-campaign qualification.
[Recording evidence](../results/wall-vertical-effects-live-20261002.json).
Count reaches 15 after Preview.5. Continue remaining campaign/fidelity/performance
and physical qualification; release at 35 commits since the prior release.

The frozen-view wall diagnostic now isolates horizontal texture coordinates as
the stronger remaining contributor: 4,167 disagreements become 3,855 with actual
reference scale, 2,302 with reconstructed wall-U, and 1,951 with both. Ordinary
trace pixels/depth and HUD are exact; these ignored overrides change no production
code and qualify no campaign, original-image or pacing gate.
[Attribution evidence](../results/wall-projection-attribution-20261002.json).
Count reaches 16 after Preview.5. Implement a bounded PowerShell wall-U trial next,
with independent math/scene controls and cost measurement; all full gates stay open.

Horizontal wall texture quantization is now adopted in numeric PowerShell with
original WAD angles and transported tangent tables. A worker dependency failure
and exception-wrapper test correction remain recorded. Returned parameters,
wrapped columns, all-style workers and 36-map idle smoke pass; all ten static
views improve and the frozen ceiling-68 view drops from 4,167 to 2,270 differences.
Final later serial cycles cost 0.18–1.56% more; native pacing remains unqualified.
[Production evidence and alternatives](../results/wall-horizontal-sampling-20261002.json).
Count reaches 17 after Preview.5. Record committed-source effects next, then
continue release work without waiting; cut another release at 35 commits.

Current wall-U effects are recorded and reviewed in all three modes, with 56
digital consistency checks and no uncovered audio interval during gameplay writes.
Actual reused worker pools pass 60 menu/automap/map-reload checks and retain
expected resource cache behavior and corrupt-asset failure propagation.
[Recordings](../results/wall-u-effects-live-20261002.json),
[session reloads](../results/wall-u-session-reload-20261002.json).
Count reaches 18 after Preview.5. Collect current-source native pacing next;
all full-release gates stay open and another release is due at 35 commits.

Nine current-source native repeats retain every command/endpoints and full windows,
with clean audio accounting and ended process identities. All fail the full pacing
gates: median active tics/sec are 31.98/32.26/31.53 and display transitions/sec
37.36/39.60/41.56 by mode, with tic p99 lateness over one second.
[Native evidence and sampling limits](../results/wall-u-native-pacing-20261002.json).
Count reaches 19 after Preview.5. Investigate stage/lateness records for the next
bounded improvement; keep frozen thresholds/defaults and release at 35 commits.

The PowerShell Mobj action dispatcher now covers all 52 action methods used by
the loaded Doom state table. Four 420-tic dense E3M6 samples reduce pooled
headless `Game.Update` median 10.02%, while all 421 recorded state/render hashes
and campaign, boss, menu, movement and save regressions pass. The 1.01% allocation
increase and 67.17 ms p99 remain material; full-host behavior is not yet measured.
[Evidence](../results/mobj-action-dispatch-20261002.json).

Count reaches 20 after Preview.5. Rerun frozen all-style native pacing on this
committed candidate, then resume ordinary-input Episode 1 route preparation and
remaining fidelity, audio, physical-input and hardware qualification. Release at
35 or more commits since Preview.5; do not narrow the Ultimate Doom scope.

The committed candidate passes all36 map starts, with35 idle tics and two serial
renderings per map. This establishes smoke coverage only. A native rerun cannot
start while the existing user Terminal is open because the frozen PresentMon
harness requires an isolated Terminal process; that window remains untouched.
[Candidate smoke receipt](../results/campaign-smoke-dispatch-20261002.json).
Evidence count reaches21 after Preview.5; keep native pacing unqualified until
an exclusive measurement session is available.

Sixteen actual worker processes now match the serial raster at five E1M1
headings in Classic, Matrix and color art, with 320,000 pixels per mode and
zero differences; both character encoders pass 80 strip-byte checks. This is
mode preservation against the internal serial reference only.
[Worker-mode receipt](../results/mobj-action-render-modes-20261002.json).
The smoke and mode-parity receipts were committed together, at21 commits after
Preview.5. This documentation correction brings the count to22. Keep the
all-style live timing retest pending the isolated display resource; release at35.

The one-session HMP Episode 1 handoff now launches the local `5682bc4` candidate
with fresh input, save, report and settings paths. It covers the E1M3 secret
route through E1M9, return to E1M4, E1M8 boss/exit and the finale. This is ready
for a single human playthrough and makes no route-completion claim.
[Human handoff](episode1-playtest.md). This documentation commit reaches23
after Preview.5; the full campaign remains unqualified.

Simulation-stage attribution on the direct-dispatch candidate retains all 420
tic samples and matches both replay endpoints. `ThinkersRun` averages 15.28 ms
per tic, with inclusive state actions at12.01 ms and sight checks at8.20 ms;
the latter run inside the former and these profiled slices include timing
overhead. [Source-pinned attribution](../results/actor-hotspots-dispatch-20261002.json).
The direct action route remains covered by all six dispatch checks. Count
reaches24 after Preview.5. Investigate the measured visibility path without
loosening state fidelity; full pacing and campaign gates remain open, release
at35 or more commits.

Sight-traversal counters in a follow-up owned bundle report119,780 BSP visits,
65,838 segment iterations, 53,662 unique lines and 4,765 intercept calculations
over the same replay; both saved checkpoints still match. Additional counters
change timing, so use the receipt for attribution only.
[Traversal evidence](../results/sight-traversal-dispatch-20261002.json).
Count reaches25 after Preview.5. Probe a traversal alternative against exact
replay controls; keep all movement, rendering and sound logic in PowerShell.

The iterative near-side-first visibility walk in a disposable bundle now matches
all420 recursive-reference state/current-render hashes. Four separate ABBA
headless timings improve pooled mean6.1%, median12.0% and p955.7%; p99 is1.7%
slower and still exceeds the frozen57.2 ms limit. Keep the exact timeline and
all 1,680 update samples in the [trial receipt](../results/visibility-iterative-dispatch-20261002.json).
Count reaches26 after Preview.5. Integrate this bounded candidate in PowerShell,
repeat the full regression surface and retain the native performance gate.

Production source commit `c3d0d0c` now uses the PowerShell iterative BSP walk.
The integrated timeline matches the recorded trial on every one of420 tics,
and a temporary recursive reference still passes both stored replay endpoints.
The production build passes the 36-map idle/render smoke and campaign/boss,
movement, action, menu/save, visibility arithmetic, offline mixer and 16-worker
Classic/Matrix/AnsiArt checks. See the [source-pinned integration receipt](../results/visibility-iterative-integration-20261002.json).
Human route, current-source live effects, acoustic and clean native pacing gates
remain open; the p99 trial remains above57.2 ms. Count reaches28 after Preview.5.
Continue those gates and release at35 commits.

The headless live-effect rerun refreshes current-source digital audio evidence
without opening a Terminal: all 420 replay commands and two checkpoints match,
63 effect events are scheduled, all 594,720 submitted frames return, and the
19.99-second process capture has zero discontinuity packets. The initial
receipt's check-count error is retained; the corrected seven-check run passes.
[Audio receipt and limits](../results/live-effect-headless-20261002-r2.json).
This does not provide video or acoustic listening evidence. Count reaches 30
after Preview.5; publish again by 35 and continue the human campaign, fidelity,
performance and acoustic gates.

The current-source fixed-state E1M2 renderer profile keeps all 16 production
stripes and 80 samples per stripe. Wall/BSP traversal has a 5.72 ms median per
stripe; plane fill is1.91 ms. Costs vary strongly by column, with the 160–180
stripe highest for the captured view. These stripes were measured sequentially,
not as live concurrent-worker latency. [Profile and limits](../results/renderer-phase-profile-current-wall-u-20261002.json).
Count reaches31 after Preview.5; measure wall-operation counts before another
candidate change and release at35 or more.

### Renderer work counters — October 2, 2026

A generated profiling-only renderer copy records geometry-operation counts for
the fixed E1M2 Classic view without changing production `FastRenderer.ps1`. The
instrumented full-frame hash matches the prior uninstrumented 80-frame profile.
The run counts 2,744 wall-column attempts, 938 column wall-U calculations and
14,438 wall-texture rows; the three-band branch count and wall time co-vary
across stripes, while texture-row volume does not explain the center cost in
this view. This evidence motivates a disposable test of selecting active wall
bands once per segment. No production optimization or general performance
claim follows yet. See the [counter profile](../results/renderer-work-counters-current-wall-u-20261002.json)
and [performance interpretation](performance.md#current-wall-operation-counters--october-2-2026).
This evidence commit reaches32 after Preview.5; three commits remain before the
next scheduled release. The human Episode 1 route, clean current-source native
pacing, independent original-renderer comparison, and acoustic review remain
open.

### Active wall-band trial — October 2, 2026

A generated PowerShell variant preselecting eligible textured wall bands once
per segment matches the current renderer's four full-frame hashes and every
worker-stripe hash in an E1M2 ABBA trial. With 640 samples per condition, the
fixed-state renderer median improves2.88%, wall median5.03%, and renderer p99
4.20%; thread-local allocation median is flat within0.11%. Classic, Matrix
and AnsiArt match the production workers at five E1M1 headings, totaling
960,000 pixels with zero differences. This is one-map headless evidence, not
live pacing. The initial comparator import-path error was corrected with a
temporary source-folder copy; no product test was skipped. See the [trial
receipt](../results/wall-band-preselection-trial-20261002.json). Move the
bounded optimization into production and rerun all-map/mode regressions before
the next 35-commit release. This evidence commit reaches33 after Preview.5.

### Wall-band integration — October 2, 2026

PowerShell segment traversal now selects only the wall-texture bands eligible
to draw, preserving their original order. The production source passes all36
map load/35-idle-tic/two-heading smokes, all three five-heading 16-worker mode
comparisons (320,000 pixels per style, zero differences), masked-wall order,
signed wall-column wrap, vertical wall sampling, wall-U arithmetic and fuzz
regressions. The [integration receipt](../results/wall-band-renderer-integration-20261002.json)
pins the source and raw report hashes. These checks do not complete maps or
establish external reference-frame parity. The ABBA performance gain remains
limited to a fixed E1M2 camera. This code commit reaches34 after Preview.5; the
new cumulative preview is due at35, while human route, live pacing, fidelity,
acoustic and hardware gates remain open.

### Preview.6 package verification — October 2, 2026

Preview.6 was assembled from clean commit `0145d75` and the extracted ZIP
passes all569 manifest hashes, launch prerequisites, 36 map-start idle smokes,
and five-view serial/16-worker rendering checks for Classic, Matrix and
AnsiArt. Each style compares 320,000 pixels with zero differences. The
[validation receipt](../results/preview6-package-validation-20261002.json)
records the archive checksum and retained test report hashes. This satisfies
the next 35-commit community-preview cadence, not the full-release gates: the
human Episode 1 route, live displayed-frame pacing, independent rendering
fidelity, acoustic review and second-hardware test remain outstanding.
The release is published as
[v0.1.0-preview.6](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.6);
its downloaded assets match the local validation package and checksum.

Post-Preview.6 renderer work adds fixed-point wall scale stepping in PowerShell.
It lowers disagreement by 1,322 indices across six E1M2/E3M6 reference views,
preserves all three styles' worker parity, and costs 2.5% median/2.7% p95 in one
serial E1M2 profile. The human Episode 1 route, moving/original-frame fidelity,
live pacing and acoustic review remain open; see the [scale record](rendering-fidelity.md#fixed-point-wall-scale-stepping--october-2-2026).
