# Reproducible input recordings

`-RecordInput` writes a reusable input replay when a session ends. It records the commands actually consumed by the simulation, the user's IWAD hash, starting skill/episode/map, engine-source fingerprint, state transitions, and sampled checkpoints. It contains no WAD data. This is separate from screen recording.

```powershell
.\Start-Doom.ps1 -Style Matrix -RecordInput .\local\my-play-session.json
.\Start-Doom.ps1 -Replay .\local\my-play-session.json
```

Use a new recording filename each time. An existing file is never replaced. Replay launch uses the recorded starting settings; an explicitly supplied conflicting skill, episode or map is rejected. A different IWAD hash is rejected. The presentation style and worker count can change independently of the recorded simulation commands.

The current format starts a fresh game and records one four-integer `TicCmd` per simulation tick: forward, sideways, turn and buttons. Intermission inputs and respawn use this same stream. Loading and undersized-window wall pauses are not commands, so replay reproduces simulation order rather than the exact wall-clock duration of a play session. The recorder uses the simulation's final consumed log, including any commands completed during shutdown; the host report separately retains its measured tic count before cleanup.

## Validation and checkpoints

The format identifies itself as `pwshDoom.InputReplay`. Version 1 contains commands/checkpoints; version 2 also records ordered new-game controls between commands. Both remain readable. Loading bounds the file at 128 MiB, commands at 1,260,000 (ten simulation hours), JSON depth at 16, integer values at the input protocol's limits, starting settings, and ordered checkpoint tic/hash entries. Version 2 bounds controls at 10,000 and validates their settings/types/boundaries. Writes use a temporary sibling file, validate it, then rename without overwrite. Historical study route files remain supported with their documented E1M1/skill-3 defaults and original first-exit behavior unless `ContinueCampaign=true` is present.

Recording/checkpoint-enabled playback samples at the beginning, every 350 commands, on state/world changes, and at orderly shutdown. Playback also samples the exact checkpoint tics supplied in the recording, including its final non-round tic. A checkpoint includes the renderer's endpoint snapshot hash, player position/inventory/health, RNG index, level time, session state and selected intermission/finale counters. It deliberately excludes wall clocks and process IDs. This is a divergence detector over selected data, **not a complete game-state serialization or save file**. Hidden thinker fields and every intermediate tick are not fully compared.

A source fingerprint mismatch produces a warning and is retained in the game report. This permits old evidence to be tested against fixes; checkpoint outcomes decide the observed compatibility of that run. A consumed checkpoint mismatch produces `ReplayDiverged`, explicit expected/actual hashes and a nonzero process exit. A deliberately shortened replay compares only checkpoints within the consumed prefix. Successful samples do not establish vanilla demo compatibility or campaign completion beyond the route actually played.

The recorder is currently opt-in and writes at orderly exit. Abrupt process termination or a machine failure may lose the in-memory recording; incremental crash recovery is not implemented. Version 2 supports new-game selection; save/load events still need a declared extension when implemented. Menu navigation and wall-clock pauses do not alter simulation state and are omitted from the replay. Neither video playback nor arbitrary commands embedded in a file are executed by this format.

## Evidence

The first no-replay recording probe failed before startup because strict mode rejected an optional replay field. The failure is retained in `results/input-recording-short-game.json`. The first format sweep caught use of `Contains` with the actual PowerShell bound-parameter dictionary; key membership now works with the launch binding. That failure is retained in `results/input-replay-format.json`.

The corrected short host run records 139 scripted commands on E1M2 at skill 2. Playback selects those nondefault settings and matches both start/final checkpoints: `results/input-recording-short-fixed-game.json` and `results/input-recording-short-replay-game.json`. Its source warning is expected because the dictionary handling fix occurred between those runs. This is a scripted host check, not a physical keyboard playthrough.

The final format sweep passes 35 checks, including malformed/versioned/legacy inputs, explicit setting conflicts, existing-file preservation, file-size bounds, and missing/divergent/prefix checkpoint comparisons: [report](../results/input-replay-format-final.json).

The real headless host then records all 1,747 commands in the established E1M1 → intermission → E1M2 route. A second independent host run consumes the resulting recording and matches all eight checkpoints at tics 0, 350, 700, 1,050, 1,400, 1,560, 1,676 and 1,747. Both runs render E1M2 with asset generation 2; the simulation-source fingerprint matches. The portable [versioned replay](../results/input-session-replay.json) is explicitly marked as originating from the existing route, not physical user play.

A negative host run changes only the first turn command of the short recording from 0 to 640 and retains the expected checkpoints. The start checkpoint still matches, the final tic-139 checkpoint differs, and the process returns exit code 1 with `ReplayDiverged`. The changed input, expected/actual hashes, source fingerprints, report hashes, 71 syntax checks and zero remaining owned processes are retained in the [validation record](../results/input-recording-validation.json).

Eight checkpoint captures in the full recording have a 3.618 ms median and 66.506 ms maximum; the maximum is the initial checkpoint before the active game clock. These samples include JSON/hash/snapshot work and are not a clean performance comparison. Keep checkpoint overhead visible in later pacing qualification.

```powershell
.\scripts\Test-InputReplay.ps1 -Output .\local\my-replay-format-check.json
.\Start-Doom.ps1 -Replay .\results\input-session-replay.json -Seconds 90
```

Checkpoint generation is opt-in with recording or checkpoint-bearing replay. Its measured cost is reported as `Simulation.ReplayCheckpointMs` and individual samples; no clean performance claim follows from these lifecycle tests.
