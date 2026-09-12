# pwshDoom: game completion and research roadmap

Created 2026-09-10. This is a living plan, not a declaration that the listed features work. The user authorized continuing implementation, experiments, and documentation toward a complete, enjoyable game and a substantial write-up.

## Product and research objective

Build a usable single-player Doom experience in a PowerShell terminal, with gameplay, rasterization, interpolation, and terminal encoding algorithms in PowerShell. Keep the 320×200 full-color image and original 35 Hz simulation semantics while targeting 60 displayed updates/sec on the measured machine. Standard .NET collections, bulk operations, IPC, and Windows device APIs are allowed; compiled game/rendering helpers and GPU Doom shaders do not meet the user's requirement.

The user confirmed the sequence: **Ultimate Doom first, Doom II second, then a MyHouse-based audit**. They also approved PowerShell sound decoding/mixing with standard Windows/.NET audio playback. Backend and music-synthesis implementation still require experiments; device playback authorization does not authorize moving gameplay/rendering into compiled code. Other IWAD editions, expansions, multiplayer, and cross-platform support are future scopes unless explicitly added.

The MyHouse audit is a named follow-on, not part of the first-release gate. Begin by pinning the exact package/version and inventorying its required formats, scripts, geometry, audio, and engine behaviors against a matching reference runtime. Distinguish unsupported extensions from incorrect implementations. A [first-hand package-editing report](https://www.speedrun.com/myhouse_wad/guides/y43o3) identifies `MyHouse.pk3`, `ZSCRIPT`, and `MAPINFO`, with differences between 2023 and 2025 releases. This supports treating the audit as more than a vanilla-map stress test; it is not our own package verification. Do not substitute a different same-named WAD and call that compatibility. Direct package inspection is still pending, and the original release forum could not be retrieved in the initial lookup. Do not promise that a vanilla Doom implementation can run this mod, or expand this audit into full GZDoom compatibility without a measured scope assessment.

"Best" means strongest demonstrated result for this particular combination of language boundary, terminal play, correctness, usability, and reproducible evidence. The study must publish losses and tradeoffs. A compiled source port may win performance, fidelity, portability, or ease of installation; that does not make it a PowerShell-engine implementation. Do not claim superiority over untested alternatives or present our adopted gameplay translation as original work.

## Baseline and acceptance

The current baseline is a single-player session prototype, not a campaign-qualified game. It has an E1M1/HMP input-only completion route, intermission advancement into E1M2, 35 Hz simulation scheduling, parallel PowerShell rendering, truecolor ANSI output, keyboard handling, resize pauses, and independent presentation telemetry for earlier builds. Intermission/finale screens, map-specific asset refresh, new-game/quit menus and pause/resume are implemented. Six save slots, confirmed save/load and replayed loads are implemented. Automap controls, save/load and replay are integrated, with numeric discovery/encoding recovering near-target averages on the bounded map-control test; timing spikes remain. Persistent always-run and keyboard turn-speed settings are implemented; audio remains unfinished. See [save/load](save-load.md), [automap investigation](automap.md), [menus](menus.md), [campaign session work](campaign-session.md), [implementation](implementation.md), [viewport](viewport.md), and [provenance](../src/ManagedDoom/ORIGIN.md).

Release acceptance requires:

- Every included map listed by exact IWAD hash has loading/rendering smoke coverage and a completed ordinary-input route or documented human playthrough. Record skill, secrets, deaths/reloads, and route provenance. A direct exit fixture or 35 idle tics is never campaign completion evidence.
- Normal/secret exits, secret-map returns, episode finales, boss-triggered changes, doors, lifts, moving floors/ceilings, stairs, teleporters, keys, weapons, pickups, damage, death/respawn, and inventory carryover have appropriate behavioral checks. Difficulty-dependent behavior is separately qualified.
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
| M1 — Campaign foundation | Map inventory and failure matrix; correct state transitions; renderer asset refresh on level changes | Per-map smoke results, normal/secret routing tests, E1M1 → E1M2 through the real host, carryover/death checks | Foundation verified: 57 controller checks and recorded E1M1 → E1M2 in all three styles; broader campaign unqualified |
| M2 — Complete single-player session | Menus, intermission/finale display, pause, save/load, automap, input recording | Scripted state-machine checks, save continuation, short user playtest | Intermission/finale, resume/new-game/quit menus, pause, six save/load slots and versioned input/control recording implemented; automap controls/save/replay integrated, with near-target averages recovered in a bounded test; input settings implemented; physical play and broader qualification remain |
| M3 — Audio | PowerShell-controlled effects/music and declared device backend | Offline output correctness, real playback review, underrun/latency/load measurements | [Opt-in PowerShell effects and Windows playback](audio.md) integrated; volume/mute and full-host PCM identity verified; [dry PowerShell music](music-synthesis.md) has 55 synthesis tests; [bounded music workers](music-workers.md) preserve the entire E1M1 loop with nineteen current group/lifecycle checks; paced four/eight-worker runs fail 38/118 virtual deadlines, independently audited; [finite float64 cache](music-cache.md) preserves full-score PCM with 22 storage and 391 evidence checks; indefinite looping, effects/live integration, fidelity and audible latency remain |
| M4 — Rendering fidelity | Reference comparisons and corrected effects/geometry/HUD | Golden states, categorized differences, regressions tested with animation and moving sectors | Can start alongside M1/M2 |
| M5 — Campaign qualification | Complete first-target campaign with normal/secret paths and endings | Route evidence per map and transition, difficulty matrix, longer human sessions | Builds on M1–M4 |
| M6 — Performance and usability | Stable pacing, lower overhead, sensible worker/font defaults | Repeated paired trials including audio and hard scenes; second machine/display testing | Continuous work; final gate after feature load |
| M7 — Release and paper | Reproducible package and substantial illustrated article | Clean-checkout test, license/asset audit, linked evidence for every comparison claim | Outline maintained throughout |
| M8 — Doom II qualification | Doom II campaign, actors/weapons, secret routes, text/cast endings | Expanded campaign matrix and complete route/play evidence with performance checks | After Ultimate Doom release |
| M9 — MyHouse-based audit | Version-pinned requirements and compatibility/performance audit | Required-feature inventory, reference behavior, supported/unsupported/incorrect classification, scoped extension plan | After Doom II; full mod support not yet promised |

Do not postpone all performance work until M6. Measure after a feature adds substantial work; keep a known-good replay and compare against it. Prefer one bounded change and a targeted check over multiple simultaneous optimizations with ambiguous attribution.

## Immediate work queue

1. Completed first step: all 36 Ultimate Doom maps pass the load/35-idle-tic/two-frame smoke sweep after fixing E2M7 line-flag conversion. See [campaign matrix](campaign-matrix.md). This is smoke coverage only.
2. Controller routing/finale/par/secret-history fixes pass 57 isolated checks, including carryover and death/respawn. Broader boss/exit behavioral qualification remains in M5.
3. The ordinary-input E1M1 -> intermission -> E1M2 route now runs through the host with generation-checked asset refresh in persistent workers. Preserve this as the session regression while implementing M2.
4. Versioned input recording is implemented with asset/source hashes, starting settings, overwrite protection and selected-state checkpoints. The full session matches eight checkpoints on replay; an altered command produces a nonzero divergence failure. See [input recording](input-recording.md). Physical keyboard use remains unobserved.
5. Menus/new-game/pause and replayed new-game controls pass the [menu milestone](menus.md). [Save/load](save-load.md) now has six integrated slots, overwrite/load confirmations, source-version warnings, isolated candidate loading and immutable replay archives. The core has 90 named checks; integrated host tests restore gameplay/intermission/finale, and three live save-menu captures replay all four checkpoints each. Footage retains the pre-correction time labels; the final local-time fix has its own regression and compatible replay. Automap is integrated; numeric discovery matches 2,139 angle cases and 48 moving-route poses, and numeric discovery/encoding recover approximately 35-tic/60-update averages on the bounded control fixture. Timing spikes, broader moving-world discovery and display qualification remain open. Persistent input settings are implemented with isolated file and host checks; audio is next. Keep the dim Matrix menus, sampled partial redraw and concurrent-startup cache collision visible in presentation/startup qualification.
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
| Truecolor ANSI versus Sixel/image protocols | ANSI currently works; Sixel has isolated tests | Parallel encoding plus actual terminal presentation, same pixels and physical image size, emulator/version recorded |
| Full-frame versus changed-region output | Full-frame baseline known | Static UI/HUD and moving-camera workloads; include comparison/encoding overhead |
| Other PowerShell Doom implementations | Source survey exists, some reproduced scene work | Refresh commits/licenses; compare supported behavior separately from comparable performance cases |
| Compiled native/C# terminal Doom | Important practical control outside the language constraint | Show efficiency/fidelity/install tradeoffs openly; never label shell launching as a PowerShell engine |
| Audio implementation routes | PowerShell effects mixer and integrated waveOut playback; MUS/SF2 readers verified offline | Qualify PowerShell synthesis against a reference, bank provenance and polyphony cost; integrate score/session controls and measure audiovisual latency |

The [existing-offerings survey](existing-implementations.md) and earlier [experiment protocol](experiment-protocol.md) remain evidence, with their original dates and workload limitations. Refresh primary sources before a release comparison. No new competitor ranking has been established by this plan.

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
