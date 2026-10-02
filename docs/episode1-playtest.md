# Ultimate Doom Episode 1 human playthrough

This is one complete human playthrough milestone, not a request for separate map-by-map reports. It advances the broader release roadmap without closing the remaining Ultimate Doom, Doom II, performance, fidelity, or MyHouse gates.

## Playthrough scope

Start a new game on HMP (skill 3) in Episode 1. Take E1M3's secret exit to E1M9, finish that map, verify the return to E1M4, then complete E1M4 through E1M8. In E1M8, defeat the boss to open the exit. Advance the ending intermission until the Episode 1 finale appears.

`E1M1 → E1M2 → E1M3 → E1M9 → E1M4 → E1M5 → E1M6 → E1M7 → E1M8 → Episode 1 finale`

A normal completion is enough; 100% kills, items, and secrets are not required. The finish point is the E1 finale screen (`E1TEXT` / `CREDIT`).

## Build and launch

The current local playtest candidate uses repository source commit `c3d0d0c` (PowerShell state-action dispatch and iterative visibility traversal), after the public Preview.5 package. It retains the released features and routes all 52 vanilla state actions directly in PowerShell. The near-side-first BSP walk matches the recursive reference over 420 tics; all 36 maps pass load/idle/serial-render smoke. Classic, Matrix and AnsiArt retain exact internal serial/worker parity in five tested views. These do not complete maps or establish original-executable fidelity. See the [production traversal receipt](../results/visibility-iterative-integration-20261002.json). The reproducible public fallback remains [`pwshDoom-0.1.0-preview.5.zip`](release-preview5.md); its [package validation](../results/preview5-package-validation-20261002.json) and [publication receipt](../results/preview5-publication-20261002.json) remain available.

Use 64-bit PowerShell 7.6.x and Windows Terminal. The required user-owned Ultimate Doom IWAD has SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`. WADs, soundfonts, prepared music, media, tools and the research PDF are excluded. The local eleven-track Episode 1 catalog covers this route; omit `-MusicCatalog` for effects-only play. Audio startup rechecks payloads and IWAD score identity.

From PowerShell, run the current candidate checkout and use fresh output paths:

~~~powershell
$root = 'C:\projects\pwshDoom'
$wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD'
$local = 'C:\projects\pwshDoom\local'
$catalog = Join-Path $local 'music-prepared-episode1.json'
$record = Join-Path $local 'episode1-human-input-visibility-candidate.json'
$report = Join-Path $local 'episode1-human-session-visibility-candidate.json'
$saves = Join-Path $local 'episode1-human-saves-visibility-candidate'
$settings = Join-Path $local 'episode1-human-settings-visibility-candidate.json'
pwsh -NoProfile -File (Join-Path $root 'Start-Doom.ps1') -Wad $wad -Workers 16 -Episode 1 -Map 1 -Skill 3 -Style Classic -Sound -MusicCatalog $catalog -RecordInput $record -Report $report -SaveRoot $saves -SettingsPath $settings -Maximized -FontSize 5
~~~

Allow up to 60 seconds for startup. Keep the 16 renderer workers and fit at least 320 columns by 100 rows; maximized with a 5-point font is the tested Classic setting. If the viewport is short, enlarge the window or press Ctrl+- to reduce the font. Blank space around the centered image is expected. Keep generated inputs, reports, saves and settings under the local directory. The launch above uses default Strips output; optional AsyncBatch is experimental and does not close the performance gates.

R19 retains fifty focused notice checks and all-style live fixtures, each consuming 350 commands and eleven checkpoints. Later all-style reload/fault tests preserve sixteen workers and independent image comparisons. Final R20-runtime Classic routes consume all 1747 commands, return all submitted audio and have no producer-backpressure waits. They still miss the frozen pacing gates; packet age excludes the device/acoustic tail. The current candidate adds exact 421-boundary dispatch replay/render parity, a 420-tic state/render timeline for visibility traversal and all-style worker comparisons, but has no human route or clean native pacing result yet. See [notice evidence](player-notices.md), [audio recovery](audio.md), [performance evidence](performance.md), the [dispatch measurements](../results/mobj-action-dispatch-20261002.json) and the [traversal trial](../results/visibility-iterative-dispatch-20261002.json). The complete route and acoustic/physical-input review remain required.

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
