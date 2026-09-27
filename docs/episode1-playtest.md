# Ultimate Doom Episode 1 human playthrough

This is one complete human playthrough milestone, not a request for separate map-by-map reports. It advances the broader release roadmap without closing the remaining Ultimate Doom, Doom II, performance, fidelity, or MyHouse gates.

## Playthrough scope

Start a new game on HMP (skill 3) in Episode 1. Take E1M3's secret exit to E1M9, finish that map, verify the return to E1M4, then complete E1M4 through E1M8. In E1M8, defeat the boss to open the exit. Advance the ending intermission until the Episode 1 finale appears.

`E1M1 → E1M2 → E1M3 → E1M9 → E1M4 → E1M5 → E1M6 → E1M7 → E1M8 → Episode 1 finale`

A normal completion is enough; 100% kills, items, and secrets are not required. The finish point is the E1 finale screen (`E1TEXT` / `CREDIT`).

## Exact build and launch

Run commit `d86ec2e1017edccad564764224c7d9e768453384` from `C:\projects\pwshDoom`. The source fingerprint is `D627BDF3D3605093095D9185EA564487ECE49A1FE2186134F2257191AB631682`. The full [candidate receipt](../results/episode1-human-playthrough-candidate-20260927-r7.json) lists current-source checks and their limits.

If your checkout is at another revision, select the tested build from the repository root:

```powershell
git switch --detach d86ec2e1017edccad564764224c7d9e768453384
```

Then start it with this command:

```powershell
pwsh -NoProfile -File .\Start-Doom.ps1 `
  -Wad 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD' `
  -Episode 1 -Map 1 -Skill 3 -Style Classic -Sound `
  -MusicCatalog .\local\music-prepared-episode1.json `
  -RecordInput .\local\episode1-human-playthrough-r4.json `
  -Report .\local\episode1-human-session-r4.json -Maximized -FontSize 5
```

Use 64-bit PowerShell 7.4 or later and Windows Terminal. This exact source was checked with PowerShell 7.6.5. The required Steam IWAD is `DOOM.WAD`, SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`; the prepared local Episode 1 music catalog has SHA-256 `0E9C9542C75F4D5E2D7FC71E42FAFBB58F94321C3B8A49BA0C9AC5A93752EE58`. The IWAD and audio catalog are not included in Git. At preflight, `%LOCALAPPDATA%\pwshDoom\settings.json` was absent, so the game's defaults apply. The [preflight receipt](../results/episode1-launch-preflight-current-candidate-20260927.json) records the detected paths and hashes.

On a cold start, allow up to 60 seconds for simulation and music workers to initialize. Keep the default 16 renderer workers. A prior measurement used about 4 GB combined worker memory. The Classic view needs at least 320 columns by 100 rows; the 5-point font and maximized window are set to help fit it. If the viewport is short, enlarge the window or press Ctrl+- to reduce the font. Blank space around the centered image in a larger terminal is expected.

Both output paths must be unused before launch. They are new (`r4`) names. After preserving the two generated files under `local/`, return to the development branch with `git switch codex/feasibility-study`.

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

The [r7 candidate receipt](../results/episode1-human-playthrough-candidate-20260927-r7.json) pins this build and records the current-source checks: 36-map smoke, 69 campaign transitions including the secret return and finale state, 97 boss checks, 125 menu/session checks with 46 screen fixtures, 15 save/load/audio-worker checks, the chainsaw regression, and exact serial/16-worker output for Classic, Matrix/Katakana, and AnsiArt/Katakana. A current-source short sound-enabled host run and the fresh launcher preflight also pass. These establish startup and focused behavior, not full map completion.

The earlier chainsaw crash happened after collecting the saw in E1M2 and pressing Ctrl against an imp. A focused real-world hit check passes on this build. The previous 26,731-command recording predates the math corrections and no longer reproduces the old exact route; its replay is documented as stale-source evidence, not as a new human test or confirmed defect. Existing E1M1–E1M4 automated route receipts are retained at their original source pins. One E1M3 waypoint driver stalled without exposing a reproducible product defect, and it was not tuned further.

The raised-floor columns in Jason's E1M1 screenshot were lower-sector Techpillar sprites whose overlap matches classic Doom's plane/sprite draw order in both repository renderers. Jason clarified that the object seen through a wall near the blue armor is a pre-placed Gibs decoration (DoomEdNum 24), not an enemy killed during play. The prior 16-view sample includes a camera 35 map units from the blue armor and several pile-adjacent views; the exact reported angle was not reproduced. If it recurs during the complete human run, note the location and viewing direction. Whole-episode audio continuity, audible quality under sustained renderer load, physical keyboard response, 35-tic simulation pacing, and 60 displayed updates/sec are not certified. Rendering remains an approximation; no independent original-executable parity is claimed.

The [roadmap](roadmap.md) keeps the broader release gates open. The [reference audit](reference-audit.md) explains the original C# Managed Doom lineage and current source references; [`src/ManagedDoom/ORIGIN.md`](../src/ManagedDoom/ORIGIN.md) records the adopted PowerShell fork and local changes.
