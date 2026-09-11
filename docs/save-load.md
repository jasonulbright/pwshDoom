# Save/load core and qualification

The inherited `VERSION 109` serializer is not connected to this host's menus. A 350-command E1M1 probe saves and loads successfully as a file operation, but its selected-state checkpoint changes and RNG moves from index 177 to 144. Loading a one-byte truncated file throws after replacing the live world. [save-inherited.json](../results/save-inherited.json) retains the measured results and exact source hashes. Source inspection also finds omitted monster target/tracer links, sector sound targets, switch timers and fire-flicker thinkers, plus changed thinker ordering when actors and specials are archived separately.

The release needs a new versioned format, with bounded validation and a candidate session that is only installed after successful reconstruction. It must preserve cyclic actor/thinker/spatial references, both RNG streams, moving sectors, pending switches, inventory, interpolation endpoints and campaign/session counters. WAD assets and executable callbacks should be reconstructed from the installed code and exact matching user IWAD, never executed from save data.

`src/SaveState.ps1` now implements that restricted object graph over a fixed catalog of engine data types. Map geometry/assets and engine callbacks have explicit bindings to a freshly constructed candidate; mutable map entities and world components retain their identities within that candidate. Other actor/data objects use standard .NET allocation followed by validated property assignment. Both the serializer and the restored gameplay methods are PowerShell. No engine algorithm is moved to a compiled helper.

The core has passed the bounded tests below. It is connected to six save/load slots in the terminal menu. This experimental format is specific to pwshDoom, not a vanilla/Managed Doom save interchange format. Test saves use unique directories under ignored `local/`; existing user saves are never test targets.

## Playing with saves

Press Escape, then choose Save Game or Load Game. Empty slots save immediately. Replacing an occupied slot asks first and defaults to No; the previous bytes remain in a uniquely named `.bak` file. Every load also defaults to No. The list shows the map and local save time. A changed engine/source version is shown on the confirmation screen; confirming it permits an attempted load, while incompatible schemas, wrong IWADs and invalid data remain hard failures. A failed operation shows an error and leaves the game paused so the player can return or choose another slot.

Normal launches store saves under `%LOCALAPPDATA%\pwshDoom\saves\<IWAD SHA-256>`. `Start-Doom.ps1 -SaveRoot C:\my-doom-saves` selects another root; the IWAD-specific subdirectory is still used. Saves in the six `slot-01.pds` through `slot-06.pds` files survive restarts. The optional root is also available to the headless host and recording harness, so tests can use isolated ignored directories.

The progress screen pauses command scheduling while PowerShell serializes or reconstructs the game. Successful loads replace the candidate at the paused boundary, attach the host's devices, discard queued key taps and mask held keys until release, refresh session graphics and advance the render-asset generation. Game clocks can rewind; the recorded input-command index stays monotonic. Intermission and finale saves also use this handoff. Device playback continuity remains part of the upcoming audio implementation.

Version-3 input recordings identify loads by the exact save hash. Successful loads retain those bytes under the IWAD directory's `replay/<SHA-256>.pds`, so overwriting the slot cannot change a later replay. Replaying such a recording requires its archived saves under the matching `-SaveRoot`; the host checks their presence/hash before starting. These referenced `.pds` files are local dependencies and are not embedded in the portable JSON evidence. Versions 1/2 and historical command-only routes remain readable.

## File and reconstruction boundaries

The version-1 JSON envelope contains metadata, the exact IWAD SHA-256, a schema hash, an engine/source fingerprint, and a checksummed JSON graph. The graph uses explicit null/scalar/reference/IWAD-binding tokens. It contains no evaluated code, assembly names to load, delegate bodies or embedded WAD artwork. Constructor-created callbacks remain attached to the new candidate world. Cyclic thinker, actor, spatial and sector references retain identity and order.

The reader limits the file to 64 MiB, the graph payload to 32 MiB, nodes to 200,000 and graph values to 2,000,000. It checks catalog types, bindings, references, numeric ranges, enum values, map entity ordering, player/world ownership, thinker rings and spatial chains. It rejects pending engine actions at an unfinished simulation boundary. Candidate construction independently checks the actual content IWAD, even if metadata was initially read without an expected hash. The current loader accepts one original Doom IWAD and single-player sessions; Doom II/PWAD stacks are outside this milestone.

Writes use a unique sibling temporary file. New saves refuse existing destinations. Replacement requires the caller's previously confirmed file hash, rechecks it immediately before `File.Replace`, and retains an exact backup of the prior save. The menu carries the hash of the selected slot through confirmation; a changed slot requires selecting it again. Parsing and hashing use the same byte buffer. Loading constructs a separate game with null device backends; callers publish that game only after reconstruction and immutable replay archival succeed. This prevents a rejected candidate from replacing the live session or resetting live devices. Failures after installation are treated as host/worker failures, not reported as rejected candidates that supposedly left the old game intact.

Schema and IWAD mismatches are hard failures. The engine source fingerprint is advisory (`SourceMatches`); the replay fingerprint now includes `SaveState.ps1` and `SaveSlots.ps1` as well as the engine/session sources. The menu exposes a difference before loading, and replays retain the original exact bytes. There is no stable cross-version save promise or schema migration yet. The checks provide bounded corruption coverage, not a claim of exhaustive adversarial validation.

## Completed evidence, 2026-09-11

| Test | Result | Scope |
| --- | --- | --- |
| [Ordinary-input saves](../results/save-state-session-corrected.json) | 48 checks pass | Save at commands 700, 1550, 1600 and 1700; continue 140 commands each; actor/sector/player/HUD projection, canonical graph, overwrite/backup and rejection checks |
| [Special objects](../results/save-specials-first.json) | 12 checks pass | Explicit E1M1 switch, fire-flicker, crusher, stasis platform, target/tracer and sector-sound fixtures; 70 continued tics, including stop/resume and texture restoration |
| [Session edges](../results/save-session-edges-first.json) | 20 checks pass | Lethal damage → save → use → respawn; actual E1/E2/E3/E4M8 worlds with direct completion and clocks positioned near the text/end-art boundary |
| [Additional validation](../results/save-validation-final.json) | 10 checks pass | Truncated/oversized files, actual wrong IWAD, repeated binding, null thinker ring, invalid block grid/RNG/fixed value, header mismatch; live checkpoint preserved |
| [Fresh-process load](../results/save-process-load-final.json), [uninterrupted reference](../results/save-process-reference-final.json) | Five sampled checkpoints and final canonical graph match | Load the command-1600 intermission save and run 147 commands; separate PIDs 4772 / 17252, PowerShell 7.6.5 |
| Original recorded session regression | All eight original checkpoints match in the reference, both remaining checkpoints match after load | Preserves the pre-save-work E1M1 → E1M2 route's selected state/render snapshot checks |

These are 90 named core checks plus the separate-process comparisons, captured before menu integration. Canonical graph equality checks the fields included in the declared schema. The independent projection manually enumerates actors/links/sectors/HUD and incorporates the existing selected-state/render snapshot hash; it does not establish every vanilla behavior or rendered pixel. The special/finale fixtures are not additional campaign completions or human play evidence. No live display algorithm changed during those headless tests, so no live-effect recording was made for that core milestone.

The subsequent menu integration passes [46 replay-format checks](../results/save-menu-replay-format-first.json), [15 save-navigation/metadata checks](../results/save-menu-navigation-first.json), [12 actual simulation-worker checks](../results/save-worker-first.json), [90 menu checks / 39 screen fixtures](../results/save-menu-unit-layout.json), and [10 synthetic input checks](../results/save-menu-input-final.json). The worker test restores an E1M1 save after switching to E2M1, validates failed-load isolation and backups, then restores the archived original after its slot is overwritten. The full [headless save/load host](../results/save-host-first.json) records 530 consumed commands (529 measured before shutdown); [replay](../results/save-host-first-replayed.json) matches all four checkpoints. A [second host test](../results/save-host-session-edges.json) loads an intermission save, advances into E1M2 and loads an E3 finale; [replay](../results/save-host-session-edges-replayed.json) consumes 448 commands and matches all six checkpoints. The fixtures use their explicitly confirmed older source versions. These tests qualify state/worker handoff rather than physical play or clean pacing.

| Save boundary | State | Bytes | Graph nodes | Save ms | Candidate load ms |
| --- | --- | ---: | ---: | ---: | ---: |
| 700 | E1M1 gameplay | 398,503 | 1,847 | 1,680.4 | 1,225.9 |
| 1550 | E1M1 before exit | 398,496 | 1,848 | 1,327.6 | 1,028.9 |
| 1600 | Intermission | 404,666 | 1,893 | 1,760.7 | 1,161.4 |
| 1700 | E1M2 gameplay | 778,651 | 3,423 | 2,495.3 | 1,964.5 |

Single observations from the corrected ordinary-input harness, not a latency distribution or gameplay FPS. Load timing includes candidate construction/restoration; save timing includes graph serialization, validation, writing and hashing. The final process pair ran concurrently, so its 2,902.7 ms load is correctness evidence under overlapping work, not a clean performance comparison. Saves should pause simulation with visible progress when integrated. The overwrite test replaces its final fixture file; the original boundary remains in the generated backup. The 1600 file used for fresh-process comparison was not overwritten.

## Failures and corrections retained

The early [single-point probe](../results/save-state-first.json) passed 22 checks, but its button projection referenced a nonexistent property and lacked strict mode. The corrected harness uses `Button.Position` and strict mode. The first [multi-point run](../results/save-state-session.json) also reused the prior run's last command during initialization; later runs now clear all commands before creating a new reference game. Those early reports do not establish the intended full matrix.

The multi-point run exposed an actual engine lifecycle issue: `Player.Attacker` retained an E1M1 actor/world after entry into E1M2. A finite probe confirmed the stale world identity and that clearing only that reference removed the unbound-subsector serialization failure. `ThingAllocation.SpawnPlayer` now clears the damage source alongside the damage counter. Ordinary in-map targets and tracers remain serialized. The full corrected matrix and original checkpoint regression pass after this adaptation; upstream modification notices are retained.

Additional malformed-graph testing first rejected a null thinker ring through an incidental property-access exception. The loader now has an explicit guard. Two following validation attempts exposed case-sensitive property lookup in the test fixture (`Index` / `x`); the fixture lookup now follows PowerShell's case-insensitive property convention. The [first](../results/save-validation-first.json), [null-guard](../results/save-validation-null-guard.json) and [fixture-correction](../results/save-validation-corrected.json) failures remain alongside the passing final report.

## Remaining release work

The integrated menus have actual Classic, Matrix and AnsiArt footage, with retained originals, crop/trim parameters and hashes in [save-menu-recordings.json](../results/save-menu-recordings.json). All three runs save, load, cancel an overwrite, confirm an overwrite, cancel a load and confirm quit. Their captured input streams replay 493 / 479 / 493 commands with matching source and four matching checkpoints each. Viewing copies under `local/recordings/` are `save-menu-classic.mp4` (31.8 s / 1,908 decoded frames), `save-menu-matrix.mp4` (31.7 s / 1,902) and `save-menu-ansiart.mp4` (31.9 s / 1,914). All use 60 CFR and contain static/duplicate frames, with no audio, rescaling, speed change or added effect.

Sampled footage verifies the decisions and progress screens. Matrix remains dim; one cancellation sample has a partially drawn footer, complete in the sample 0.2 seconds later. This is retained presentation evidence, with cause unestablished. The movies also exposed UTC-looking slot times: the JSON parser had already produced a UTC DateTime, and reparsing it as a string discarded that information. A [failing fixture](../results/save-menu-time-before.json) reproduces it; the [corrected 16-case check](../results/save-menu-time-fixed.json) preserves the timestamp's kind and displays local time. The footage intentionally retains the earlier labels. A [post-fix replay](../results/save-menu-classic-replayed-timefix.json) still matches all four checkpoints, with the expected source-version warning.

Three external Graphics Capture teardown failures and a black GDI capture are retained in the recording report. Lowering the capture ceiling and delaying window close did not establish a reliable fix; successful retries are evidence only for those completed recordings. The additional [corruption sweep](../results/save-validation-integrated.json) passes ten checks against the integrated reader. Two simultaneous final test launches collided on the existing generated engine-bundle cache; [failure](../results/save-worker-final.json) and the [serial worker rerun](../results/save-worker-final-serial.json) distinguish that startup limitation from save behavior. Avoid concurrent game startup pending its qualification.

Next, qualify automap/settings and broaden campaign/audio work from the roadmap. Physical controls, repeated long play sessions, schema migration and audio restoration remain outside the current save evidence. [save-menu-validation.json](../results/save-menu-validation.json) records the current audit and exact differences from capture-time sources.

Reproduce core checks from the repository in PowerShell 7 using fresh output paths:

```powershell
.\scripts\Test-SaveState.ps1 -SaveAt 700,1550,1600,1700 -ContinueTics 140 -Output .\local\my-save-checks.json
.\scripts\Test-SaveSpecials.ps1 -Output .\local\my-save-specials.json
.\scripts\Test-SaveSessionEdges.ps1 -Output .\local\my-save-edges.json
```

The first report supplies its unique save directory. Pass its untouched `at-1600.pds` to `Test-SaveProcessContinuation.ps1` in two separate `pwsh` invocations, with `-Mode Load` and `-Mode Reference`, `-StartCommand 1600 -ContinueTics 147`, and distinct `-Output` paths. Compare sample hashes and the final graph hash, not process IDs or timing. `Test-SaveValidation.ps1` takes the untouched `at-700.pds` and another fresh output path.
