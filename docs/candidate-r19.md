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

## Extracted validation completed

The [package receipt](../results/r19-playtest-package-validation-20261001.json) identifies source `f0a16af7a289c2f479477eee240e5b3c09d20274`, the 1,695,503-byte ZIP (`CF44D1D7842A48B85ABF8ED70B9E27DE422A50E09896F2CF35F1EA1FBBC47603`) and all 551 verified payloads. The excluded untracked research PDF alone accounts for the manifest's dirty flag. Recorded live-fixture source entries match the extracted package in each style.

Extracted checks pass: 110 terminal byte/ownership/pipe cases, 18 resource-reader boundary cases, 125 menu checks with 46 screens, and 15 music-enabled save-worker checks. Each style's sixteen-worker fixture compares 448,000 pixels and 112 encoded strips across screens and four map reloads, plus 256,000 pixels against freshly converted resources. The short actual-device startup reconciles every submitted/returned frame and closes. Retain the receipt's queue/timing details and narrow startup scope; it does not qualify sustained audio, display pacing or human play.
