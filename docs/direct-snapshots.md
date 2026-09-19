# Direct numeric world snapshots

The failed E1M3 Matrix recording spent 17.083 ms per update publishing its two render snapshots. The existing path builds per-sector, sidedef, actor and HUD objects, then serializes them to NumericV1 arrays. `Get-GameRenderSnapshotBytes` packs those same fields directly in PowerShell. The object path remains intact as the reference and checkpoint implementation. No geometry, actor, light, texture, weapon or interpolation field is omitted.

The initial experiment was measured before adoption in the simulation worker. `results/direct-snapshots-first.json` pins the experimental source, harness, bundle and IWAD, preserved in commit `28efb2b`. It passes 1,152 exact whole-packet byte comparisons: all 36 maps at startup with endpoints, fractional interpolation and clamps, after 35 idle tics, and every 35 commands plus transitions/end of the complete E1M3 replay. All 7,118 commands and 24 original gameplay checkpoints match, including intermission and E1M4 entry. This is sampled snapshot equivalence, not proof for every possible world state or reference Doom fidelity.

| Isolated paired measurements (ms per snapshot) | Object path | Direct packing |
| --- | ---: | ---: |
| All 1,152 calls, mean | 5.849 | 4.772 |
| All calls, median | 5.206 | 4.421 |
| All calls, p95 | 8.878 | 7.109 |
| All calls, maximum | 111.631 | 28.759 |
| 414 replay endpoint calls, mean | 5.912 | 4.983 |

Order alternates within each frozen game state; every sample, including cold calls, is retained. No other study workload ran concurrently. The mixed-map mean reduction is about 18%; the E1M3/E1M4 replay endpoint subset is about 16%. These are in-process microbenchmarks, not full-host timings or displayed FPS. They cannot be subtracted directly from the recorded run's differently loaded stage measurements.

## Shared endpoint data

`Get-GameRenderSnapshotPair` packs the current endpoint once, copies its numeric data, and changes only old camera/actor positions, camera angle/view height and sector heights. Actor membership and discrete fields describe the same frozen world update. Current actor angles, weapon sprites, textures, lighting, inventory and other unchanged fields are preserved in both packets. The camera's shortest wrapped angle and first-tic/interpolation rules remain unchanged.

`results/paired-snapshots-first.json` passes all 558 full-packet comparisons at 279 states across all 36 maps and the full E1M3 replay, with all 24 original checkpoints. Alternating paired measurements retain cold calls: old pair mean 10.212 ms, shared pair 5.823 ms (about 43% less); medians 10.056/5.914 ms and p95 13.640/8.261 ms. This separate run measures two endpoints together and should not be compared as if each sample were a single snapshot.

The simulation worker now uses the shared pair for normal world rendering. Menus, automap and intermission/finale retain their existing screen paths.

## Real-host prefix check

The same 1,200-command E1M3 prefix, 16 Matrix workers, effects and six-track music catalog completed after adoption. Both runs were headless, each without another study workload running. The new run deliberately retained the old replay fingerprint: `ReplaySourceMatches` is false, and all four original checkpoints still match. `results/e1m3-host-paired-audit.json` passes thirteen checks including every recorded input field and all 1,512,000 returned audio frames, with no audio error, cancellation or unconsumed packet.

| Whole-run result | Earlier object pair | Shared pair |
| --- | ---: | ---: |
| Active seconds for 1,200 commands | 61.780 | 50.495 |
| Simulation ticks/sec | 19.424 | 23.765 |
| Snapshot publication mean, ms | 15.674 | 8.270 |
| Snapshot publication p95, ms | 21.520 | 10.941 |
| Game update mean, ms | 28.003 | 26.929 |
| Maximum recorded tick lateness, ms | 27,414.630 | 16,149.992 |

Receipts: `results/e1m3-host-admission-first.json`, `e1m3-host-paired-first.json`, `e1m3-host-paired-first-sources.json`, `e1m3-paired-recorded.json`, and the audit above. These are one before/after host run, supported by the separate same-state paired measurements, not a repeated display benchmark. The headless completed-image rates are not console or display FPS. The prefix does not qualify a full live E1M3 route, other presentation styles under load, or full campaign behavior.

The improvement leaves a substantial deficit: game update plus snapshot publication still average roughly 35.2 ms before other work, exceeding the 28.6 ms tick budget. Profile gameplay stages next, preserving exact commands, original checkpoints, fixed resolution and all actors. Full live recording and sustained 35-tic/60-display qualification remain open.

## NumericV3 palette selection

The [palette presentation](palette-presentation.md) follow-up uses header45 for a discrete PLAYPAL index0..13. Both producers reuse the adopted PowerShell selector, and interpolation preserves the current endpoint selection. NumericV2 compatibility digests retain version2 and a zero45 slot; current V3 digests include the field. Schema1 keeps its original representation. All336 current all-map/E1M2 byte comparisons and13 legacy checkpoints pass. Compatibility hashes preserve old evidence; they do not retroactively expand what it checked.
