# Input and sound settings

Open **Escape → Settings** to change preferences. Up/down chooses an
item; Left/Right or Enter changes its value. Enter activates
Reset Defaults or Back. Escape returns to the main menu.

| Preference | Default | Behavior |
| --- | --- | --- |
| Always run | Off | Uses run movement by default; hold Shift to walk. When off, Shift runs. |
| Turn speed | 100% | Scales keyboard turning to 50%, 100% or 150%; movement and strafing speeds are unaffected. |
| Sound | 100% | Changes sound-effect volume in ten-percent steps, clamped to 0–100%. Applies when launched with `-Sound`. |
| Mute sound | Off | Silences effects while retaining their selected volume and advancing their playback positions. |

Changes apply after the settings action succeeds. Menus pause simulation and held
gameplay keys must be released before acting again. Automap arrow capture remains
in effect; WASD follows the chosen movement preference. Input preferences affect
keyboard command generation, not monster speed, game physics or the 35 Hz clock.
Sound preferences affect the PowerShell mixer. Changing effective volume clears
device buffers mixed at the previous gain, potentially cutting a short sound tail.
This avoids replaying old loud samples after leaving a muted menu. Active voice
positions remain advanced; unmuting does not restart effects. Gain changes apply
at a worker boundary, not at a claimed zero-latency acoustic boundary.

Ordinary interactive launches save to `%LOCALAPPDATA%\pwshDoom\settings.json`.
`Start-Doom.ps1 -SettingsPath C:\path\preferences.json` selects a separate file.
Replay, scripted and headless runs use defaults unless explicitly supplied a
settings file. Tests use fresh paths under ignored `local/`.

Version-two JSON contains `Version`, `AlwaysRun`, `TurnSpeed`, `SoundVolume` and
`SoundMuted`. Version-one files gain 100%/unmuted defaults in memory and remain
unchanged on disk until a successful edit saves version two.
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

Music is not implemented yet. Display style,
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
recorded menu revisions; `results/settings-demo-schedule.json` belongs to the
earlier four-item input menu and must not be used for the six-item version.

## Sound controls qualification

`results/sound-settings-unit.json` passes sixty settings checks, including legacy
migration without rewriting, independent volume/mute persistence, malformed
sound values, clamped volume navigation, mute and reset. The first expanded menu
fails the native font bounds check for `SOUND VOLUME: 100%`; that report is retained
as `sound-settings-menus.json`. Shortening it to `SOUND: 100%` passes 125 checks
and 46 screen fixtures in `sound-settings-menus-fit.json`.

`results/sound-volume-worker.json` compares every submitted PCM byte against an
independent numeric ramp through full volume, mute and quarter volume. All four
checks pass, including three muted packets and preserved source positions after
unmute. This is actual runspace/device submission evidence, not listening or
acoustic latency measurement.

`results/sound-settings-host.json` passes seven checks across two real hosts. The
full 1,747-tic route preserves all eight checkpoints while six successful edits
set 90%, 80%, 70%, mute, unmute at 70%, then mute again. The worker consumes all
packets, including 1,164 muted packets, and closes cleanly. A fresh process reads
70% plus mute and starts its output muted. All paths are isolated under `local/`.
The first run cancels an upper bound of 10,080 previously queued stereo frames
across gain changes; the largest single cancellation is 3,780 frames (85.7 ms).
These are queued-frame bounds, not measurements of how much sound was heard.

Replaying the actual worker gain boundaries through the direct offline mixer
preserves the entire submitted-PCM hash, including mute/unmute source positions:
`165DA79BA2BEAAC5B65E7FE68B60B4DB8FDC0FCEC25364E58CE851DC6A228E84`.
See `results/sound-settings-audio-replay.json` and
`results/sound-settings-volume-schedule.json`. The reconstructed WAV includes
submitted blocks that the device may later cancel; it is not a loopback recording.
Input replays describe gameplay commands, while this optional volume schedule
describes audio gain boundaries. Use `results/sound-settings-demo-schedule.json`
for the new menu layout.

The audio-enabled input-settings regression (`sound-settings-recovery.json`)
passes eleven checks across edit/reset, fresh-process loading and malformed-file
recovery. It preserves the two gameplay/map checkpoints in both replay runs,
keeps default sound gain after reset/error recovery and closes the devices.

The actual color-art recording (`results/sound-settings-recording.json`) performs
all six edits and retains all eight campaign checkpoints. Full-size samples show
all six readable settings rows, sound at 70%, mute Off and mute On, and gameplay.
The separate viewing copy `local/recordings/sound-settings-ansiart-view.mp4`
fully decodes to 3,668 frames over 61.133 seconds at 1280×800. The original is
retained. This video is silent, with no tint/speed/scaling change; encoded frame
count is not a unique-display count. QPC at recorder process creation is not
assumed to be the first encoded frame's timestamp.

`results/sound-settings-validation.json` pins fourteen current source files and
passes 26 evidence checks over 207 accepted named checks, the independent PCM
comparison, actual recordings and syntax checks. No owned game or recorder
processes remain. Music, acoustic timing and physical keyboard/audio review remain
unfinished release work.
