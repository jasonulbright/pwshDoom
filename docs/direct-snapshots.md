# Direct numeric world snapshots

The failed E1M3 Matrix recording spent 17.083 ms per update publishing its two render snapshots. The existing path builds per-sector, sidedef, actor and HUD objects, then serializes them to NumericV1 arrays. `Get-GameRenderSnapshotBytes` packs those same fields directly in PowerShell. The object path remains intact as the reference and checkpoint implementation. No geometry, actor, light, texture, weapon or interpolation field is omitted.

The initial experiment is **not yet adopted in the simulation worker**. `results/direct-snapshots-first.json` pins the experimental source, harness, bundle and IWAD. It passes 1,152 exact whole-packet byte comparisons: all 36 maps at startup with endpoints, fractional interpolation and clamps, after 35 idle tics, and every 35 commands plus transitions/end of the complete E1M3 replay. All 7,118 commands and 24 original gameplay checkpoints match, including intermission and E1M4 entry. This is sampled snapshot equivalence, not proof for every possible world state or reference Doom fidelity.

| Isolated paired measurements (ms per snapshot) | Object path | Direct packing |
| --- | ---: | ---: |
| All 1,152 calls, mean | 5.849 | 4.772 |
| All calls, median | 5.206 | 4.421 |
| All calls, p95 | 8.878 | 7.109 |
| All calls, maximum | 111.631 | 28.759 |
| 414 replay endpoint calls, mean | 5.912 | 4.983 |

Order alternates within each frozen game state; every sample, including cold calls, is retained. No other study workload ran concurrently. The mixed-map mean reduction is about 18%; the E1M3/E1M4 replay endpoint subset is about 16%. These are in-process microbenchmarks, not full-host timings or displayed FPS. They cannot be subtracted directly from the recorded run's differently loaded stage measurements.

The next bounded experiment shares unchanged fields between the pair of interpolation endpoints, checking both complete packets against the retained object path before adoption. Gameplay update cost remains a separate bottleneck.
