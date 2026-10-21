# Ultimate Doom Episode 1 human playthrough

This is one complete human playthrough milestone, not a request for separate map-by-map reports. It advances the broader release roadmap without closing the remaining Ultimate Doom, Doom II, performance, fidelity, or MyHouse gates.

## Playthrough scope

Start a new game on HMP (skill 3) in Episode 1. Take E1M3's secret exit to E1M9, finish that map, verify the return to E1M4, then complete E1M4 through E1M8. In E1M8, defeat the boss to open the exit. Advance the ending intermission until the Episode 1 finale appears.

`E1M1 → E1M2 → E1M3 → E1M9 → E1M4 → E1M5 → E1M6 → E1M7 → E1M8 → Episode 1 finale`

A normal completion is enough; 100% kills, items, and secrets are not required. The finish point is the E1 finale screen (`E1TEXT` / `CREDIT`).

## Build and launch

Use the public [Preview.10 release](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.10), built from source commit `c39f1dc`. Its extracted package has 588 manifest payloads whose SHA-256 hashes verify; the [publication receipt](../results/preview10-publication-20261020.json) records package integrity and the repo footprint. The current local verified extraction is `C:\projects\pwshDoom\local\releases\preview10\validation\pwshDoom-0.1.0-preview.10`; use it for `$root` below. Preview.10 supersedes the older local `e3` candidate. The package excludes the IWAD, prepared music, tools, research files and media. Historical readiness evidence remains in the [earlier candidate receipt](../results/episode1-playtest-candidate-20261020-r3.json), [wall-band integration receipt](../results/wall-band-renderer-integration-20261002.json), [Preview.6 package validation](../results/preview6-package-validation-20261002.json), [traversal receipt](../results/visibility-iterative-integration-20261002.json), and [playthrough performance evidence](performance.md#active-wall-band-preselection-trial--october-2-2026).

Use 64-bit PowerShell 7.6.x and Windows Terminal. The required user-owned Ultimate Doom IWAD has SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`. WADs, soundfonts, prepared music, media, tools and the research PDF are excluded. The local eleven-track Episode 1 catalog covers this route; omit `-MusicCatalog` for effects-only play. Audio startup rechecks payloads and IWAD score identity.

From PowerShell, run the extracted local development candidate and use fresh output paths:

~~~powershell
$root = 'C:\projects\pwshDoom\local\releases\preview10\validation\pwshDoom-0.1.0-preview.10'
$wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD'
$local = 'C:\projects\pwshDoom\local'
$catalog = Join-Path $local 'music-prepared-episode1.json'
$record = Join-Path $local 'episode1-human-input-preview10-20261020.json'
$report = Join-Path $local 'episode1-human-session-preview10-20261020.json'
$saves = Join-Path $local 'episode1-human-saves-preview10-20261020'
$settings = Join-Path $local 'episode1-human-settings-preview10-20261020.json'
pwsh -NoProfile -File (Join-Path $root 'Start-Doom.ps1') -Wad $wad -Workers 16 -Episode 1 -Map 1 -Skill 3 -Style Classic -Sound -MusicCatalog $catalog -RecordInput $record -Report $report -SaveRoot $saves -SettingsPath $settings -Maximized -FontSize 5
~~~

Allow up to 60 seconds for startup. Keep the 16 renderer workers and fit at least 320 columns by 100 rows; maximized with a 5-point font is the tested Classic setting. If the viewport is short, enlarge the window or press Ctrl+- to reduce the font. Blank space around the centered image is expected. Keep generated inputs, reports, saves and settings under the local directory. The launch above uses default Strips output; optional AsyncBatch is experimental and does not close the performance gates.

The input recording has a checksummed `.journal` sidecar while the session runs. If the game or computer stops unexpectedly, recover its complete recorded prefix with a fresh output path:

~~~powershell
pwsh -NoProfile -File C:\projects\pwshDoom\scripts\Recover-DoomInputReplayJournal.ps1 `
  -Journal C:\projects\pwshDoom\local\episode1-human-input-preview10-20261020.json.journal `
  -Output C:\projects\pwshDoom\local\episode1-human-input-preview10-20261020-recovered.json
~~~

The journal is removed after a successful orderly recording. Recovery keeps it and does not overwrite the requested output. The recovery implementation has offline contract and static wiring checks; no game session or actual process interruption has exercised it yet.

If the companion journal is still present on a later launch, `Start-Doom.ps1`
now refuses to start another recording and prints a copyable recovery command.
It selects the first unused `.recovered.json` output name and leaves the
journal and any existing replay untouched. The 33-case offline contract covers
quoting and filename collisions; abrupt-stop recovery through a real game
session remains unverified.

R19 and R20 checks are historical evidence from October 2026, not validation of the current package. Their route, worker, and audio results do not close the campaign or pacing gates. Current saved-replay renderer evidence compares the packaged source at E1M1 tic 315; at ceiling height 68 it records 21 differences against the adapted reference (18 plane-buffer and three mapped-column color differences), with no live game or device used. The current package receipt and [row-trace comparison](../results/moving-sector-lower-boundary-20261020-v17.json) preserve the exact limits. The complete route and acoustic/physical-input review remain required.

## Controls

| Key | Action |
| --- | --- |
| W / S or Up / Down | Move forward / backward |
| A / D | Strafe |
| Left / Right | Turn |
| Ctrl | Fire |
| E or Space | Use doors and switches |
| Shift | Run |
| 1–7 | Select weapon |
| Tab | Open / close automap |
| Escape | Open menu / go back |
| Ctrl, E, Space, or Enter | Advance intermission |
| P / Pause | Pause / resume |

The table lists default controls. Use Escape → Settings → Configure keys to
change movement, strafe, turn, fire, use, or run bindings before starting. Do
not alter bindings during the route unless needed; if you do, record the choice.

Use brief movement presses, release before changing direction, and tap switches. Report delayed controls or visible stalls.

## What to report

At the end, send **all clear** if you reached the finale. Otherwise report the last map, what you pressed or expected, what happened, and whether you died, reloaded, paused, or resized the window. Mention any audio dropout or prolonged stall. Keep the input recording and session report until the result is written down; they can help reproduce a problem. Do not send WAD files.

Your report will be recorded only for the scope and outcomes you state. Automated fixtures and route replays are not substitutes for this human playthrough.

## Current evidence and limits

The [Preview.10 publication receipt](../results/preview10-publication-20261020.json) pins the clean source commit, payload hashes, asset digests and footprint. The [renderer identity receipt](../results/renderer-source-offset-20261020.json) covers one fixed E1M2 frame; it does not start the game host or qualify a route. An earlier four-second E1M1 actual-device check returned all 175,140 submitted music frames and closed cleanly, with one queue-starvation observation after the final packet and no rebuffer resume; that older check is not a sustained audio or audible-quality qualification. No live test is part of this handoff preparation.

The Preview.10 package pins the current launch and replay-recovery code at
`c39f1dc`. Its single renderer change since the older local `e3` handoff is
limited to reusing texture-column base indices; the fixed E1M2 frame hash is
identical. This does not establish a complete human route or live behavior.

Preview.6 passes 36/36 map-start smokes at 35 idle tics and five-view 16-worker parity in each visual style. These tests do not finish maps. Earlier bounded simulation and audio-host rates were below the frozen 35-tic/60-display target, and neither Terminal writes nor worker parity establish distinct monitor presentations. See the [package receipt](../results/preview6-package-validation-20261002.json), [publication receipt](../results/preview6-publication-20261002.json), and [performance evidence](performance.md).

The former E1M2 chainsaw crash was caused by ordering a custom Angle value that does not implement IComparable. The current wrapped binary-angle comparison passes the focused attack regression against an E1M2 imp, which loses 4 HP after four tics. It is a mechanic check, not a route; later renderer changes do not change that gameplay code.

The raised-floor Techpillar overlap matches the plane/sprite draw order in the two repository renderers, but original-executable parity for that view remains unverified. Jason clarified that the apparent wall leak near blue armor was the pre-placed Gibs decoration. A 64-view sweep did not reproduce a wall leak; its one candidate-only mask pixel was explained by a background-color difference. If either visual issue recurs in the human run, note the map and viewing direction.

A saved E1M3 automated replay no longer matches its older gameplay checkpoints, and the old chainsaw recording's source fingerprint also differs. Those are stale-source diagnostics, not current route evidence. The E1M1–E1M4 routes remain pinned regressions; the failed E1M5 continuation ended in player death without exposing a repeatable engine defect and was not tuned further.

The required human playthrough is still one complete HMP route: E1M1 through E1M3, take the secret exit to E1M9, finish and return to E1M4, complete E1M4–E1M8, defeat E1M8's boss, and advance to the E1 finale. The visual route, physical keyboard response, campaign-length audio, and display pacing remain unverified. Completing this route advances the Episode 1 milestone; it does not close the broader Ultimate Doom release gates, Doom II, or the MyHouse audit.

The [roadmap](roadmap.md) retains those broader gates. The [reference audit](reference-audit.md) explains the original C# Managed Doom lineage and current source references; src/ManagedDoom/ORIGIN.md records the adopted PowerShell fork and local changes.
