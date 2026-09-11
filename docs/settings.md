# Input settings

Open **Escape → Settings** to change the input preferences. Up/down chooses an
item; Left/Right or Enter changes always-run and turn speed. Enter activates
Reset Defaults or Back. Escape returns to the main menu.

| Preference | Default | Behavior |
| --- | --- | --- |
| Always run | Off | Uses run movement by default; hold Shift to walk. When off, Shift runs. |
| Turn speed | 100% | Scales keyboard turning to 50%, 100% or 150%; movement and strafing speeds are unaffected. |

Changes apply after the settings action succeeds. Menus pause simulation and held
gameplay keys must be released before acting again. Automap arrow capture remains
in effect; WASD follows the chosen movement preference. These settings affect
keyboard command generation, not monster speed, game physics or the 35 Hz clock.

Ordinary interactive launches save to `%LOCALAPPDATA%\pwshDoom\settings.json`.
`Start-Doom.ps1 -SettingsPath C:\path\preferences.json` selects a separate file.
Replay, scripted and headless runs use defaults unless explicitly supplied a
settings file. Tests use fresh paths under ignored `local/`.

The file is versioned JSON containing `Version`, `AlwaysRun` and `TurnSpeed`.
Only the documented types and choices are accepted. Invalid, unknown-version or
oversized files produce a warning and default input preferences, preserving the
file. If saving fails, the attempted change is rolled back and the game shows
**Settings not saved**; Escape/Enter returns to the settings menu. The detailed
error is in `SettingsEvents` in the game report. Existing invalid files require
repair or moving aside before persistent edits can succeed.

Writes publish a complete temporary file in the same directory. A hash check
detects changes observed since loading and refuses a stale save. This is not a
cross-process transaction or a guarantee against every concurrent edit race.
Settings files and save slots are separate. Input replays already contain final
movement/turn/button commands, so replaying them bypasses these input preferences.

Initial verification: [47 isolated checks](../results/settings-unit-dictionary.json)
cover file validation, typed round trips, stale writes, IPC objects, menus, the
twelve always-run/Shift/turn-speed combinations and held-key suppression. The
[menu suite](../results/settings-menu-first.json) covers 123 checks and 44 screen
fixtures, including all four settings choices. Real-host and live recording
results follow as they are verified. Physical keyboard play remains unobserved.

Sound/music volume controls will be implemented with audio. Display style,
worker count, font and diagnostics remain launch parameters; this screen does
not claim those additional options are already implemented.

The [three-host fixture](../results/settings-host-dictionary.json) passes nine
checks: five persisted edits including reset, fresh-process reload, and a
malformed-file save failure followed by normal gameplay. Both control-route
checkpoints match in the edit and recovery runs. The failed first host and the
intermediate dictionary-conversion failure remain in `results/` and the ledger.

## Recorded settings interaction

The [settings audit](../results/settings-validation.json) preserves 297 source
hashes, 91 standalone parses plus the aggregate engine parse, 205 accepted
checks and metadata for three actual window recordings. Each consumes all 350
fixture commands and map masks, performs five successful persisted edits, and
matches both gameplay/map checkpoints. No game/recorder processes remain at audit.

| Style | Viewing copy under `local/recordings/` | Duration / decoded frames |
| --- | --- | --- |
| Classic | `settings-classic-view.mp4` | 15.00 s / 900 |
| Matrix | `settings-matrix-view.mp4` | 15.17 s / 910 |
| AnsiArt | `settings-ansiart-view.mp4` | 15.73 s / 944 |

Untrimmed originals remain beside these copies. Full-size screen samples and
contact sheets show readable values, selection, map/HUD and return to gameplay.
Matrix is still dim. Classic's early captured game image remains visible through
several reported menu writes: a 0.25-second sample sequence stays on that image
until roughly 2.75 seconds, then shows the settings. The host reports menu writes
around 1.24–2.63 seconds from its first render start. These different time origins
are not an exact display-latency measurement, but the missing early menu content
requires further capture/presentation investigation. Static UI completion is
not the same as verified visible state at every intermediate action.

Capture/export durations include approximate contrast-based trimming and possible
CFR duplicates. These UI demonstrations do not establish gameplay FPS, uniform
pacing or physical keyboard interaction. Historical menu schedules belong to their
recorded menu revisions; use `results/settings-demo-schedule.json` for this menu.
