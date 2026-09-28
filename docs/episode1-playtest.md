# Ultimate Doom Episode 1 human playthrough

This is one complete human playthrough milestone, not a request for separate map-by-map reports. It advances the broader release roadmap without closing the remaining Ultimate Doom, Doom II, performance, fidelity, or MyHouse gates.

## Playthrough scope

Start a new game on HMP (skill 3) in Episode 1. Take E1M3's secret exit to E1M9, finish that map, verify the return to E1M4, then complete E1M4 through E1M8. In E1M8, defeat the boss to open the exit. Advance the ending intermission until the Episode 1 finale appears.

`E1M1 → E1M2 → E1M3 → E1M9 → E1M4 → E1M5 → E1M6 → E1M7 → E1M8 → Episode 1 finale`

A normal completion is enough; 100% kills, items, and secrets are not required. The finish point is the E1 finale screen (`E1TEXT` / `CREDIT`).

## Build and launch

Download **pwshDoom 0.1.0-preview.3** from the [public GitHub release](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.3), extract the ZIP, and verify it against the attached `SHA256SUMS.txt`. Preview.3 is released for community testing before a complete human Episode 1 playthrough has been recorded. It includes focused campaign, session, renderer, music-reader and startup checks, but does not claim that a full episode route or the broader campaign release gates have passed. The [publication receipt](../results/preview3-publication-20260928.json) verifies the uploaded ZIP against a fresh public download and records the package checks; the earlier [candidate receipt](../results/preview3-current-candidate-validation-aeb6772-20260928.json) documents its predecessor's more detailed test outputs.

From PowerShell, set the extracted folder and the path to your own Ultimate Doom `DOOM.WAD`, then run:

```powershell
$installRoot = 'C:\Games\pwshDoom-0.1.0-preview.3'
$wad = 'C:\Games\DOOM.WAD'
$evidence = Join-Path $installRoot 'local'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
pwsh -NoProfile -File (Join-Path $installRoot 'Start-Doom.ps1') `
  -Wad $wad -Episode 1 -Map 1 -Skill 3 -Style Classic -Sound `
  -RecordInput (Join-Path $evidence 'episode1-human-input.json') `
  -Report (Join-Path $evidence 'episode1-human-session.json') -Maximized -FontSize 5
```

Use 64-bit PowerShell 7.6.x and Windows Terminal; PowerShell 7.4 or later is the project minimum. The required IWAD is `DOOM.WAD`; it is not included. Sound effects are enabled. Music is optional and requires a catalog you prepare from your own IWAD and soundfont; see [music preparation](music-preparation.md). Add `-MusicCatalog '<path-to-your-prepared-catalog.json>'` to the launch command if you have one, otherwise the game runs without background music. The package smoke test and earlier candidate evidence are linked from the [release notes](../CHANGELOG.md); they do not certify full-session music continuity or a full campaign route.

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

The raised-floor columns in Jason's E1M1 screenshot were lower-sector Techpillar sprites whose overlap matches classic Doom's plane/sprite draw order in both repository renderers. Jason clarified that the object seen through a wall near the blue armor is the pre-existing Gibs pile (DoomEdNum 24), not a corpse from a killed enemy. A later two-camera sweep at the recorded input states nearest the blue armor (tic 8400) and a nearby Gibs pile (tic 8750) compares both documented `POL5` actors at sixteen headings per camera, for 64 isolated actor/view comparisons. Its only candidate-only actor-mask pixel is on a floor plane; detail shows the reference draws the same actor palette index as that pixel's background, while the candidate floor differs. This is a one-pixel background/mask disagreement, not evidence of a sprite drawn through a wall. The sweep does not establish the exact view Jason saw or original-executable parity. See the [angle-sweep receipt](../results/episode1-pool-gibs-angle-sweep-20260928.json) and the [single-pixel detail](../results/episode1-pool-gibs-angle0-detail-20260928.json). If the sighting recurs during the complete human run, note the location and viewing direction. Whole-episode audio continuity, audible quality under sustained renderer load, physical keyboard response, 35-tic simulation pacing, and 60 displayed updates/sec are not certified. Rendering remains an approximation; no independent original-executable parity is claimed.

The [roadmap](roadmap.md) keeps the broader release gates open. The [reference audit](reference-audit.md) explains the original C# Managed Doom lineage and current source references; [`src/ManagedDoom/ORIGIN.md`](../src/ManagedDoom/ORIGIN.md) records the adopted PowerShell fork and local changes.
