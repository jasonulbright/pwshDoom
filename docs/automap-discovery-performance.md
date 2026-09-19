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
