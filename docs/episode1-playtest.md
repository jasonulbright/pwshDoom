# Ultimate Doom Episode 1 human playthrough

This is one complete human playthrough milestone, not a request for separate map-by-map reports. It advances the broader release roadmap without closing the remaining Ultimate Doom, Doom II, performance, fidelity, or MyHouse gates.

## Playthrough scope

Start a new game on HMP (skill 3) in Episode 1. Take E1M3's secret exit to E1M9, finish that map, verify the return to E1M4, then complete E1M4 through E1M8. In E1M8, defeat the boss to open the exit. Advance the ending intermission until the Episode 1 finale appears.

`E1M1 → E1M2 → E1M3 → E1M9 → E1M4 → E1M5 → E1M6 → E1M7 → E1M8 → Episode 1 finale`

A normal completion is enough; 100% kills, items, and secrets are not required. The finish point is the E1 finale screen (`E1TEXT` / `CREDIT`).

## Build and launch

The current handoff is the clean local development package pwshDoom-0.1.0-dev.20260929.r17.zip. Its implementation source is commit 00405deebef6b4e8477c9c9316987b82fbc9064d. The package contains 543 manifest-verified files and excludes WADs, soundfonts, reports, and the local research PDF. It is not a tagged or published release. The exact package source commit, ZIP checksum, and verification are in the R17 candidate receipt.

Extract it to C:\projects\pwshDoom\local\episode1-r17-final-extracted. The package root will be C:\projects\pwshDoom\local\episode1-r17-final-extracted\pwshDoom-0.1.0-dev.20260929.r17. Use the package from that exact implementation source.

Use 64-bit PowerShell 7.6.x and Windows Terminal. Play.ps1 -Check passes on the extracted package with the Steam Ultimate Doom IWAD and the locally prepared eleven-track Episode 1 catalog. The required IWAD is user-supplied and must match SHA-256 6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F. The catalog and soundfont remain outside the archive; if the catalog is unavailable, omit -MusicCatalog to play with sound effects and no music. Audio startup rechecks the payload and IWAD score identity.

The R17 source passes 144 complete automap-bitset comparisons across all 36 IWAD map starts, the eight-check automap worker fixture, and a 9/9 Episode 1 load/idle/render smoke. The four-second packaged E1M1 audio run advances 139 tics, returns all 175,140 submitted audio frames, selects D_E1M1, and closes the device without errors. One queue-starvation observation occurs after the final packet, with no rebuffer resume. Its 42.49 headless updates/sec are not terminal writes or displayed frames. These checks do not establish a completed map route, sustained audio continuity, or display pacing.

The focused chainsaw, campaign-transition, boss-progression, and menu-input checks remain valid from R16: their gameplay/session source files are unchanged in R17. They cover the former E1M2 chainsaw exception, 69 transitions, 97 boss checks, and 10 menu-input checks; none substitutes for the human route. The complete R17 source and package evidence is in results/episode1-current-human-candidate-20260929-r17.json and results/r17-playtest-package-validation-20260929.json in the repository checkout.

From PowerShell, set these fresh output paths, then launch:

~~~powershell
$root = 'C:\projects\pwshDoom\local\episode1-r17-final-extracted\pwshDoom-0.1.0-dev.20260929.r17'
$wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD'
$local = 'C:\projects\pwshDoom\local'
$catalog = Join-Path $local 'music-prepared-episode1.json'
$record = Join-Path $local 'episode1-human-input-r17.json'
$report = Join-Path $local 'episode1-human-session-r17.json'
$saves = Join-Path $local 'episode1-human-saves-r17'
$settings = Join-Path $local 'episode1-human-settings-r17.json'
pwsh -NoProfile -File (Join-Path $root 'Start-Doom.ps1') -Wad $wad -Workers 16 -Episode 1 -Map 1 -Skill 3 -Style Classic -Sound -MusicCatalog $catalog -RecordInput $record -Report $report -SaveRoot $saves -SettingsPath $settings -Maximized -FontSize 5
~~~

Allow up to 60 seconds for a cold start. Keep the 16 renderer workers and fit at least 320 columns by 100 rows; maximized with a 5-point font is the tested setting. If the viewport is short, enlarge the window or press Ctrl+- to reduce the font. Blank space around the centered image in a larger terminal is expected. Keep the generated input, report, saves, and settings under C:\projects\pwshDoom\local; the input/report and save/settings locations above are fresh for R17.

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

Use brief movement presses, release before changing direction, and tap switches. Report delayed controls or visible stalls.

## What to report

At the end, send **all clear** if you reached the finale. Otherwise report the last map, what you pressed or expected, what happened, and whether you died, reloaded, paused, or resized the window. Mention any audio dropout or prolonged stall. Keep the input recording and session report until the result is written down; they can help reproduce a problem. Do not send WAD files.

Your report will be recorded only for the scope and outcomes you state. Automated fixtures and route replays are not substitutes for this human playthrough.

## Current evidence and limits

The R17 candidate receipt pins implementation commit 00405deebef6b4e8477c9c9316987b82fbc9064d and the Steam IWAD hash. The exact package passes its manifest, launcher preflight, and four-second E1M1 actual-device startup. All 175,140 submitted music frames return and the device closes cleanly; one queue-starvation observation occurs after the final packet, with no rebuffer resume. This is not a sustained audio or audible-quality qualification.

R17 adds stationary automap discovery reuse. Its focused checks match the uncached mapped-line bitsets for all 36 map starts at four headings, pass the eight-check automap worker fixture, and pass a 9/9 Episode 1 load/idle/render smoke. These tests do not finish maps. The actual simulation host records 34.79 tics/sec in an idle five-second run; the packaged audio smoke records 42.49 headless updates/sec. Neither is a 35-tic/60-displayed-frame qualification. The receipts and their limits are linked in the candidate record.

The former E1M2 chainsaw crash was caused by ordering a custom Angle value that does not implement IComparable. The current wrapped binary-angle comparison passes the focused attack regression against an E1M2 imp, which loses 4 HP after four tics. It is a mechanic check, not a route. R17 does not change that gameplay code.

The raised-floor Techpillar overlap matches the plane/sprite draw order in the two repository renderers, but original-executable parity for that view remains unverified. Jason clarified that the apparent wall leak near blue armor was the pre-placed Gibs decoration. A 64-view sweep did not reproduce a wall leak; its one candidate-only mask pixel was explained by a background-color difference. If either visual issue recurs in the human run, note the map and viewing direction.

A saved E1M3 automated replay no longer matches its older gameplay checkpoints, and the old chainsaw recording's source fingerprint also differs. Those are stale-source diagnostics, not current route evidence. The E1M1–E1M4 routes remain pinned regressions; the failed E1M5 continuation ended in player death without exposing a repeatable engine defect and was not tuned further.

The required human playthrough is still one complete HMP route: E1M1 through E1M3, take the secret exit to E1M9, finish and return to E1M4, complete E1M4–E1M8, defeat E1M8's boss, and advance to the E1 finale. The visual route, physical keyboard response, campaign-length audio, and display pacing remain unverified. Completing this route advances the Episode 1 milestone; it does not close the broader Ultimate Doom release gates, Doom II, or the MyHouse audit.

The [roadmap](roadmap.md) retains those broader gates. The [reference audit](reference-audit.md) explains the original C# Managed Doom lineage and current source references; src/ManagedDoom/ORIGIN.md records the adopted PowerShell fork and local changes.
