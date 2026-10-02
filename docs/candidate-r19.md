# R19 development candidate — October 1, 2026

`0.1.0-dev.20261001.r19` is a local playable handoff after Preview.4, for the complete Episode 1 human route documented in [the playthrough guide](episode1-playtest.md). It includes the final readable player notices, immutable map-resource caching, verified-body reuse in persistent render workers and optional bounded AsyncBatch output. Gameplay, rasterization, encoders and audio mixing remain PowerShell algorithms. Classic, Matrix and color art remain available; Strips remains the default output mode.

The archive is created by `scripts/Build-PreviewPackage.ps1` from committed tracked inputs. Its manifest identifies every payload file and source commit. The separate package-validation receipt pins the ZIP and extracted checks; measurement files remain in the source repository rather than the small playable ZIP. Consult `results/r19-playtest-package-validation-20261001.json` in the repository for the completed validation status. This document records the frozen source scope; it does not predeclare extracted tests successful.

The planned validation checks every manifest file, compares recorded live-fixture source hashes with packaged sources, runs launcher preflight with the user's IWAD and eleven-track Episode 1 catalog, and tests extracted menu/save/load, resource-cache boundaries and actual workers in all three styles. A short actual-device startup must reconcile submitted and returned audio frames and close cleanly. These checks are separate from sustained pacing, acoustic fidelity, physical input and full-map completion.

Use the ZIP under `local/episode1-r19-package` and checked extraction under `local/episode1-r19-extracted`. Fresh save/input/report paths in the playthrough guide preserve the R18 comparison build. The archive excludes WADs, soundfonts, tools, prepared audio, recordings, research PDFs and local reports. Supply your own Ultimate Doom IWAD; music preparation remains optional.

## Evidence and remaining work

- Final-source live notice fixtures pass in all three styles: 350 commands and eleven checkpoints per recording, plus 24 grouped notice/audio/media audits. Recorder failures and retries remain documented in [the notice record](player-notices.md).
- Same-WAD resource preparation falls from 4.09–4.90 seconds to 81–112 ms in three isolated ABBA cycles. Verified-body read-back takes 69–81 ms. Fresh-resource image oracles and sixteen-worker reload tests preserve compared images; new map geometry and mutable scratch remain private.
- Three live Classic/audio routes measure complete loads of 1.54–2.03 seconds, but still fail the [frozen performance gates](release-performance-protocol.md). A single same-source AsyncBatch ABBA cycle improves simulation lateness in its paired runs without qualifying display pacing or establishing a general winner.
- All 36 map starts have smoke coverage; focused progression/boss/menu/save checks and existing normal routes remain evidence. The continuous human E1 secret-map/finale route, remaining Ultimate Doom campaigns, independent original-executable moving-world comparisons, acoustic/physical-input review and second-hardware/display qualification remain open.

This is a development candidate, not a fully qualified Ultimate Doom release candidate. Preview.4 remains the public release. The user's 35-commit release rule remains in force; freezing this local handoff does not reset that count. [Roadmap](roadmap.md), [ledger](ledger.md) and [working article](article-draft.md) retain the broader scope and limitations.
