# Ultimate Doom Episode 1 human playthrough

This is one complete human playthrough milestone, not a request for separate map-by-map reports. It advances the broader release roadmap without closing the remaining Ultimate Doom, Doom II, performance, fidelity, or MyHouse gates.

## Playthrough scope

Start a new game on HMP (skill 3) in Episode 1. Take E1M3's secret exit to E1M9, finish that map, verify the return to E1M4, then complete E1M4 through E1M8. In E1M8, defeat the boss to open the exit. Advance the ending intermission until the Episode 1 finale appears.

`E1M1 → E1M2 → E1M3 → E1M9 → E1M4 → E1M5 → E1M6 → E1M7 → E1M8 → Episode 1 finale`

A normal completion is enough; 100% kills, items, and secrets are not required. The finish point is the E1 finale screen (`E1TEXT` / `CREDIT`).

## Exact build and launch

Run the extracted, unpublished Preview.3 package candidate built from commit
`aeb6772a3ddac78b24782d95b4c7f1b738136ab6` at
`C:\projects\pwshDoom\local\preview3-package-aeb6772-extracted\pwshDoom-0.1.0-preview.3`.
Its ZIP SHA-256 is
`DAFC42D13D9D754C26CB7EDC92CAED8D51DB2109A65D2081B6078A6F44C59579`.
The [package receipt](../results/preview3-current-candidate-validation-aeb6772-20260928.json)
records 537 verified source files, both article SVG figures, and exclusion of
the research PDF and game assets. Its raw gameplay/session fingerprint is
`861FA06A414183D7753C8EEF840FB402D0E8D3E8A12139D95772D67F461A6CF6`; it differs
from the prior `r7` receipt only because of checkout line endings. All 216
fingerprinted gameplay/session files have identical text after line-ending
normalization. The [r7 candidate receipt](../results/episode1-human-playthrough-candidate-20260927-r7.json)
records the focused game checks and their limits.

Start it with this command:

```powershell
pwsh -NoProfile -File 'C:\projects\pwshDoom\local\preview3-package-aeb6772-extracted\pwshDoom-0.1.0-preview.3\Start-Doom.ps1' `
  -Wad 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD' `
  -Episode 1 -Map 1 -Skill 3 -Style Classic -Sound `
  -MusicCatalog 'C:\projects\pwshDoom\local\music-prepared-episode1.json' `
  -RecordInput 'C:\projects\pwshDoom\local\episode1-human-playthrough-r6.json' `
  -Report 'C:\projects\pwshDoom\local\episode1-human-session-r6.json' -Maximized -FontSize 5
```

Use 64-bit PowerShell 7.6.x and Windows Terminal; PowerShell 7.4 or later is the project minimum. The clean package passed `Play.ps1 -Check` with the installed 36-map Steam IWAD and music-catalog path, then a two-second sound-enabled host startup under PowerShell 7.6.5. The reader accepts matching 7.6.x qualification reports, and its current-package regression passes 22 checks. The required Steam IWAD is `DOOM.WAD`, SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`; the prepared local Episode 1 music catalog has SHA-256 `0E9C9542C75F4D5E2D7FC71E42FAFBB58F94321C3B8A49BA0C9AC5A93752EE58`. Neither asset is included in the package. At the latest preflight, `%LOCALAPPDATA%\pwshDoom\settings.json` was absent, so game defaults apply. The [preflight and startup evidence](../results/preview3-current-candidate-validation-aeb6772-20260928.json) records the detected paths and hashes.

The startup failure reported under PowerShell 7.6.6 came from overly strict runtime-version and line-ending checks in qualified music reports. The reader now accepts equivalent PowerShell text across LF/CRLF checkouts and compatible 7.6.x patch versions while still rejecting changed source text. The current package passes 22 reader checks and starts the 11-track Episode 1 catalog in a two-second, sound-enabled headless run under PowerShell 7.6.5, advancing 69 tics with no host error or audio-backpressure sample. This brief run does not verify full-session music continuity, audible quality, or playback under visible Terminal load.

On a cold start, allow up to 60 seconds for simulation and music workers to initialize. Keep the default 16 renderer workers. A prior measurement used about 4 GB combined worker memory. The Classic view needs at least 320 columns by 100 rows; the 5-point font and maximized window are set to help fit it. If the viewport is short, enlarge the window or press Ctrl+- to reduce the font. Blank space around the centered image in a larger terminal is expected.

Both output paths must be unused before launch. They are new (`r6`) names. Preserve the generated input and report under `C:\projects\pwshDoom\local`; they are local evidence and must not be committed or shared with the WAD.

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

The [r7 candidate receipt](../results/episode1-human-playthrough-candidate-20260927-r7.json) records the current gameplay checks: 36-map smoke, 69 campaign transitions including the secret return and finale state, 97 boss checks, 125 menu/session checks with 46 screen fixtures, 15 save/load/audio-worker checks, the chainsaw regression, and exact serial/16-worker output for Classic, Matrix/Katakana, and AnsiArt/Katakana. The fresh package preflight and sound-enabled startup pass on the package candidate as recorded in the [current package receipt](../results/preview3-current-candidate-validation-aeb6772-20260928.json). These establish startup and focused behavior, not full map completion.

The earlier chainsaw crash happened after collecting the saw in E1M2 and pressing Ctrl against an imp. A focused real-world hit check passes on this build. The previous 26,731-command recording predates the math corrections and no longer reproduces the old exact route; its replay is documented as stale-source evidence, not as a new human test or confirmed defect. Existing E1M1–E1M4 automated route receipts are retained at their original source pins. One E1M3 waypoint driver stalled without exposing a reproducible product defect, and it was not tuned further.

The raised-floor columns in Jason's E1M1 screenshot were lower-sector Techpillar sprites whose overlap matches classic Doom's plane/sprite draw order in both repository renderers. Jason clarified that the object seen through a wall near the blue armor is the pre-existing Gibs pile (DoomEdNum 24), not a corpse from a killed enemy. The prior 16-view sample includes a camera 35 map units from the blue armor and several pile-adjacent views; the exact reported angle was not reproduced. A current-source rerender at recorded input tics 8400 and 8750 found no visible `POL5` Gibs sprite in the reference view and no affected `POL5` pixels in the candidate; the isolated actor-mask results are in [`human-pool-gibs-actor-audit-current-source-20260927.json`](../results/human-pool-gibs-actor-audit-current-source-20260927.json). If the sighting recurs during the complete human run, note the location and viewing direction. Whole-episode audio continuity, audible quality under sustained renderer load, physical keyboard response, 35-tic simulation pacing, and 60 displayed updates/sec are not certified. Rendering remains an approximation; no independent original-executable parity is claimed.

The [roadmap](roadmap.md) keeps the broader release gates open. The [reference audit](reference-audit.md) explains the original C# Managed Doom lineage and current source references; [`src/ManagedDoom/ORIGIN.md`](../src/ManagedDoom/ORIGIN.md) records the adopted PowerShell fork and local changes.
