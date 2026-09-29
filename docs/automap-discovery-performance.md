# Profile discovery before replacing it

2026-09-19. Loaded E1M3 measurements put endpoint automap discovery at approximately 5–6 ms per simulation tick. It is performed even with the map closed, so discovered walls remain available when the player opens it. Skipping that work without equivalent discovery would change behavior.

`scripts/Measure-AutomapDiscovery.ps1` replays the first 1,200 original E1M3 commands in a single process. It calls actual discovery after each world update, records a hash of the complete mapped-line bitset after every command, and checks the original gameplay checkpoints. Hashing and gameplay are outside the discovery timer; the initial pre-command discovery is outside timing. This is a diagnostic workload, not the loaded host or display benchmark.

The optional profiler modifies only a uniquely owned generated engine bundle. Seven method bodies receive inclusive timers and call counters; production sources remain unchanged. Counters reset after gameplay, before discovery. The instrumented run independently checks every mapping hash against the uninstrumented baseline. Both preserve all four original gameplay checkpoints and the same final selected-state hash. Five additional receipt/source/state checks pass in `results/automap-discovery-profile-audit.json`.

| Method | Calls over 1,200 commands | Inclusive mean ms per command |
| --- | ---: | ---: |
| PointOnSide | 45,507 | 0.796 |
| PointToAngleData | 235,248 | 1.687 |
| DiscoverSeg | 73,412 | 4.638 |
| ProjectDiscoveryAngles | 117,624 | 0.344 |
| IsPotentiallyVisible | 45,507 | 2.205 |
| DrawSolidWall | 26,072 | 0.431 |
| DrawPassWall | 10,037 | 0.254 |

These rows overlap. DiscoverSeg includes angle/projection and wall calls; bounding-box visibility includes angle/projection calls. Do not sum them. Overall discovery mean is 7.166 ms without instrumentation and 9.839 ms with instrumentation; timer overhead is substantial and the two runs are sequential. Neither the difference nor an inclusive row is an achievable saving. Earlier full-host means come from different execution conditions.

The evidence favors investigating repeated endpoint-angle calculation and the inherited chain of segment/visibility/wall calls. PointOnSide alone accounts for only 0.796 instrumented ms per command; optimizing it cannot reasonably be presented as removing the entire discovery cost. A candidate can reuse shared vertex angles within one discovery pass or use a dedicated numeric traversal, while retaining exact angular tables, occlusion, moving-sector rules, and every mapped-line result. Such a replacement is **not implemented or qualified yet**. Start with a bounded candidate and measured mapping parity; then expand to all-map headings and moving-world routes before adopting it. No actor, wall or discovery update may be dropped to inflate throughput.

Reproduce with fresh output paths in PowerShell 7:

```powershell
./scripts/Measure-AutomapDiscovery.ps1 -Replay ./results/e1m3-qualified-replay.json -Output ./local/my-discovery-baseline.json
./scripts/Measure-AutomapDiscovery.ps1 -Replay ./results/e1m3-qualified-replay.json -Profile -ReferenceReport ./local/my-discovery-baseline.json -Output ./local/my-discovery-profile.json
```

Raw results are `results/automap-discovery-baseline-first.json` and `results/automap-discovery-profile-first.json`. Both pin the source bundle, harness, replay and IWAD. Derive each method mean by summing its `ProfileTicks` column, multiplying by 1,000, and dividing by the recorded QPC frequency and command count. The audit retains those sums and input hashes. Original run handles 44685 and 58906 both exited successfully; no production change or loaded-performance improvement is claimed by this investigation.

## First cache experiment: correct but slower

The isolated dictionary-by-vertex candidate clears its cache every discovery pass. `Test-DiscoveryAngleCache.ps1` alternates baseline/candidate order at each of 1,200 actual E1M3 states, clears mapped flags before both calls to expose fresh visibility differences, compares those complete bitsets, then restores cumulative discovery. All 1,200 fresh comparisons and all 1,200 prior baseline cumulative hashes agree; all four original gameplay checkpoints also pass. Production sources are unchanged.

`results/discovery-angle-cache-first.json` retains every timing. Baseline/candidate mean is **7.353/11.008 ms**, median 7.316/10.990, p95 13.372/19.765. The candidate loses whether it runs first or second (candidate means 11.06/10.96 ms). It is not adopted. Reduced angle evaluation does not compensate for cache lookup/reference handling and surrounding overhead in this implementation; the experiment does not isolate those individual costs. Test indexed storage next before any production change. Timings include per-pass cache clearing and cold calls, exclude flag reset/hash/setup; neither is a loaded-host result.

## Indexed candidate: paired improvement and broader parity

The indexed alternative constructs segment-to-vertex indices once per map, clears a boolean validity array on each discovery pass, and reuses angle values only within that pass. Its dedicated segment entry also avoids the inherited DrawSeg forwarding call. This tests the combined indexed/direct-entry implementation, not an isolated dictionary-versus-array operation.

The first builder attempt stopped before gameplay because a text marker was ambiguous; its exact source and error are retained in `results/discovery-angle-indexed-build-failure.json`. Restricting replacement to the discovery-only subsector block resolves the construction failure.

The 1,200-command paired run passes every fresh and prior cumulative mapping hash and four original checkpoints. Mean baseline/candidate is 4.803/3.895 ms; both alternating order groups improve. Initial map indexing takes 16.276 ms and remains included in the first timed call. Baseline timing differs from the earlier dictionary experiment, so cross-run means are not used to attribute a speedup.

The full 7,118-command E1M3 replay passes 7,002 fresh mapping comparisons across level states and all 24 original checkpoints through E1M4. Baseline/candidate mean is 3.379/2.726 ms, median 2.920/2.375 and p95 7.383/5.717. Both map setup costs (20.020 and 7.232 ms) are included. Intermission commands have no discovery work and are explicitly excluded from the per-discovery timing summary, while all commands/checkpoints remain in the receipt. These are operation costs, not loaded-host FPS.

The separate all-map fixture passes 144 synthetic heading cases over all 36 map starts, with complete mapped-bit agreement, unchanged framebuffers, unchanged world/sector renderer counters and unchanged other line flags. One candidate renderer is reused across all maps; all 36 index rebuilds occur. This broadens discovery parity, not campaign completion or inherited renderer buffer-limit fidelity. Receipts: `results/discovery-angle-indexed-first.json`, `discovery-angle-indexed-full.json`, and `discovery-angle-indexed-maps.json`.

## Adopted path and loaded host

The indexed path is now the production default. `CacheDiscoveryAngles = false` selects the retained reference path for diagnostic paired tests. The complete adopted renderer class matches the validated candidate after normalizing only newlines and the default switch; helper classes remain intact. The paired harness explicitly sets its reference instance to false. The indexed experiment builder copies an already-adopted bundle unchanged. Reproduce the retired dictionary experiment at commit `2a25f78`; its prior harness/source hashes remain in Git.

The actual 16-worker headless Matrix prefix with effects and the unchanged six-track music catalog completes all 1,200 commands and four original checkpoints. All thirteen input/state/audio audit checks pass; all 1,512,000 audio frames return, and the complete PCM hash matches the prior host prefix. Current/pre-run/recorded-input source fingerprints agree, with the original replay source mismatch explicitly declared.

| Loaded prefix metric | Previous numeric-side build | Indexed discovery |
| --- | ---: | ---: |
| Active seconds | 40.4643 | 38.9243 |
| Simulation tics/sec | 29.6558 | 30.8290 |
| Mean discovery ms/tic | 6.1581 | 5.1501 |
| Mean game update ms/tic | 18.5892 | 18.4286 |
| Mean snapshot publication ms/tic | 8.0820 | 7.9637 |
| Headless completed images/sec | 54.6408 | 53.9251 |

These are separate before/after host observations, not controlled repeats. The older build also predates the separately qualified audio shutdown repair; it had already returned all prefix audio frames. The paired discovery tests support the local optimization; this single host comparison does not prove stable 35-tic/60-display performance. Headless image completions are neither console writes nor displayed frames. Original raw samples, pins, input and audit are `results/e1m3-host-indexed-discovery*`, `e1m3-indexed-discovery-recorded.json` and `e1m3-indexed-discovery-comparison.json`.

The actual simulation-worker automap fixture also passes eight save/load/menu/new-game checks after adoption (`results/automap-worker-indexed-discovery.json`). This covers restoring map pixels under a new generation and switching map identity without stale cache effects. The profiler now includes DiscoverIndexedSeg as an additional inclusive method when available, so future profiles will not silently omit the new hot path. Campaign completion, reference fidelity, audio queue starvation and physical presentation targets remain open.

## Stationary-view reuse (2026-09-29)

`DiscoverMap` still ran on every simulation tic, including while the player and view were stationary. The renderer now reuses the prior mapping result when the map, world, screen, player position and angle, clipping window, relevant visible sector/side state, and mapped-line state still match. It tracks sectors and sides referenced by BSP segments projected into the viewport. Off-view sector lighting changes therefore do not force a traversal; changes to visible floor/ceiling heights or flats, light levels, middle textures, camera state, viewport clipping, or cleared mapped flags do.

The PowerShell 7.6.6 all-map comparison passes all 36 Ultimate Doom map starts at four headings (144 complete mapped-line bitset comparisons). It preserves each framebuffer, renderer validity counters, and unrelated line flags. Eleven invalidation cases cover relevant sector/side changes, off-view lighting, mapped-flag resets, player movement/angle, and viewport clipping. The actual simulation-worker fixture passes all eight automap, save/load, menu, and new-game checks.

A five-second idle E1M1 simulation-host run under PowerShell 7.6.6 performs one discovery traversal followed by 174 cache hits. It advances 174 tics at 34.79 tics/sec; the report records 81 headless render completions (16.20/sec), which are not terminal or display frame rates. Automap discovery reports 0.177 ms mean, 0.123 ms median, and 0.147 ms p95 across the short run. There are no startup or runtime errors.

The alternating static E4M9 method benchmark measured 16.757 ms median without stationary reuse and 0.082 ms with it across 120 calls per path, with zero traversals during cached batches. This is a `DiscoverMap` microbenchmark with an unchanged world, not a whole-game speedup or FPS result. The idle host confirms that reuse occurs in the live simulation loop; it does not establish 60 displayed frames/sec, moving-view benefit, or campaign completion. The compact qualification receipt is `results/stationary-discovery-cache-20260929.json`.
