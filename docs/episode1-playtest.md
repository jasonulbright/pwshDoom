# Ultimate Doom Episode 1 human playthrough

This is one complete human playthrough milestone, not a request for separate map-by-map reports. It advances the broader release roadmap without closing the remaining Ultimate Doom, Doom II, performance, fidelity, or MyHouse gates.

## Playthrough scope

Start a new game on HMP (skill 3) in Episode 1. Take E1M3's secret exit to E1M9, finish that map, verify the return to E1M4, then complete E1M4 through E1M8. In E1M8, defeat the boss to open the exit. Advance the ending intermission until the Episode 1 finale appears.

`E1M1 → E1M2 → E1M3 → E1M9 → E1M4 → E1M5 → E1M6 → E1M7 → E1M8 → Episode 1 finale`

A normal completion is enough; 100% kills, items, and secrets are not required. The finish point is the E1 finale screen (`E1TEXT` / `CREDIT`).

## Build and launch

Use the current development checkout on branch `codex/feasibility-study`, at implementation commit `c31186896628a9ee9a4ea3b635c0d19fac65b40d`. The [r6 candidate receipt](../results/episode1-current-human-candidate-20260928-r6.json) pins this build and links the [performance receipt](../results/renderer-projection-cache-20260928.json). Dense scenes use typed cached actor projections in NumericV5 worker packets; sparse scenes retain NumericV4. Current-source checks pass for all 36 Ultimate Doom map loads, 69 Episode 1 secret/intermission/finale transitions, 97 boss progression cases, and exact E1M3 HMP output across sixteen workers in Classic, Matrix/Katakana, and AnsiArt/Katakana. The dense E3M6 stress profile improved sequential CPU work, while the E1M3 HMP timing comparison was inconclusive. No displayed-frame-rate gain is claimed. The public [Preview.3 release](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.3) remains available for community testing; this handoff uses the newer development candidate.

From PowerShell, use the existing checkout and your Steam Ultimate Doom `DOOM.WAD`:

```powershell
$root = 'C:\projects\pwshDoom'
$wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD'
$local = Join-Path $root 'local'
$catalog = Join-Path $local 'music-prepared-episode1.json'
$record = Join-Path $local 'episode1-human-input-r7.json'
$report = Join-Path $local 'episode1-human-session-r7.json'
$saves = Join-Path $local 'episode1-human-saves-r7'
$settings = Join-Path $local 'episode1-human-settings-r7.json'
pwsh -NoProfile -File (Join-Path $root 'Start-Doom.ps1') `
  -Wad $wad -Workers 16 -Episode 1 -Map 1 -Skill 3 -Style Classic -Sound `
  -MusicCatalog $catalog -RecordInput $record -Report $report `
  -SaveRoot $saves -SettingsPath $settings -Maximized -FontSize 5
```

Use 64-bit PowerShell 7.6.x and Windows Terminal. The required Ultimate Doom IWAD is user-supplied and must match SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`. Sound effects and the prepared eleven-track Episode 1 music catalog are enabled. The catalog is local, built from the user's IWAD and soundfont; it is not included in the repository. If it is unavailable, omit `-MusicCatalog $catalog` to keep sound effects and play without background music. A current-source five-second headless E1M3 run under PowerShell 7.6.5 selected D_E1M3 and shut down without an audio worker error; it recorded one rebuffer with real-time mode disabled. This is startup evidence, not an acoustic or full-session continuity check. In an interactive `-Sound` session, the audio worker advances music/effects through temporary simulation-packet gaps; headless sessions remain packet-exact unless `-RealtimeAudio` is selected.

The r3 audio receipt is pinned to implementation commit `41e167f` and records eight actual-waveOut continuity checks, a four-second E3M6 host run, and a save/load/new-game audio-worker run. The r6 receipt adds a current-source E1M3 sound-enabled host check along with map, route-transition, boss, and renderer-worker results. These bounded checks do not measure audible quality, physical device underruns, input-to-speaker latency, full-session continuity, or game/display pacing.

The startup failure reported under PowerShell 7.6.6 came from overly strict runtime-version and line-ending checks in qualified music reports. The reader now accepts equivalent PowerShell text across LF/CRLF checkouts and compatible 7.6.x patch versions while still rejecting changed source text. The Preview.3 package passes 22 reader checks and starts the 11-track Episode 1 catalog in a two-second, sound-enabled headless run under PowerShell 7.6.5, advancing 69 tics with no host error or audio-backpressure sample. The five-second startup run is pinned to the earlier audio implementation commit `41e167f`; the r5 renderer change has separate all-map, three-style worker, and persistent-worker reload checks. Neither brief host run verifies full-session music continuity, audible quality, or playback under visible Terminal load.

On a cold start, allow up to 60 seconds for simulation and music workers to initialize. Keep the 16 renderer workers. An earlier five-second headless 16-worker run used about 4.16 GB combined worker memory; memory has not been remeasured for the r6 build. The Classic view needs at least 320 columns by 100 rows; the 5-point font and maximized window help fit it. If the viewport is short, enlarge the window or press Ctrl+- to reduce the font. Blank space around the centered image in a larger terminal is expected. The raw human input, session report, saves, and settings use fresh `r7` paths so earlier attempts remain intact.

The `r7` input/report paths and dedicated save/settings locations preserve the earlier attempts. The local directory currently has no `r7` outputs. Confirm that the two output files do not already exist before launch; keep all generated data under `C:\projects\pwshDoom\local` and do not share it with the WAD.

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

The r6 implementation passes 21 current snapshot checks, a 36-map smoke, 69 current Episode 1 transition fixtures including the E1M3→E1M9→E1M4 secret path and finale state, 97 current boss progression checks, and exact five-view 16-worker E1M3 output in all three styles. A five-second current-source headless E1M3 run starts with sound and the episode catalog, selects D_E1M3, and reaches 174 tics; it reports 155 completed headless updates (30.95/sec), not displayed frames, plus one rebuffer observation. These fixtures do not complete any map or the human route. Menu, screen, save/load, and new-game checks are carried forward from the earlier candidate receipt chain; those engine/session files were not changed in r6.

The earlier chainsaw crash happened after collecting the saw in E1M2 and pressing Ctrl against an imp. The current focused real-world hit check passes: the saw damages a living E1M2 imp (60 to 56 HP) on its first attempt, and the homing-turn check passes. Replaying the saved 26,731-command human input against current source consumes every command without a simulation exception, but its recorded source fingerprint differs and the first of 79 checkpoints diverges at tic 350; the replay remains in E1M1, so it does not reach or independently verify the former E1M2 crash state. Treat that attempt as stale-source diagnostic evidence, not a current full-route regression or a new human test. The focused chainsaw check was rerun against the current checkout; its report remains at [saw-attack.json](../results/saw-attack.json), and replay limits are recorded in the [ledger](ledger.md#2026-09-28--recheck-the-chainsaw-fix-against-current-source). Existing E1M1–E1M4 automated route receipts are retained at their original source pins. One E1M3 waypoint driver stalled without exposing a reproducible product defect, and it was not tuned further.

The raised-floor columns in Jason's E1M1 screenshot were lower-sector Techpillar sprites whose overlap matches classic Doom's plane/sprite draw order in both repository renderers. Jason clarified that the object seen through a wall near the blue armor is the pre-existing Gibs pile (DoomEdNum 24), not a corpse from a killed enemy. A later two-camera sweep at the recorded input states nearest the blue armor (tic 8400) and a nearby Gibs pile (tic 8750) compares both documented `POL5` actors at sixteen headings per camera, for 64 isolated actor/view comparisons. Its only candidate-only actor-mask pixel is on a floor plane; detail shows the reference draws the same actor palette index as that pixel's background, while the candidate floor differs. This is a one-pixel background/mask disagreement, not evidence of a sprite drawn through a wall. The sweep does not establish the exact view Jason saw or original-executable parity. See the [angle-sweep receipt](../results/episode1-pool-gibs-angle-sweep-20260928.json) and the [single-pixel detail](../results/episode1-pool-gibs-angle0-detail-20260928.json). If the sighting recurs during the complete human run, note the location and viewing direction. Whole-episode audio continuity, audible quality under sustained renderer load, physical keyboard response, 35-tic simulation pacing, and 60 displayed updates/sec are not certified. Rendering remains an approximation; no independent original-executable parity is claimed.

The [roadmap](roadmap.md) keeps the broader release gates open. The [reference audit](reference-audit.md) explains the original C# Managed Doom lineage and current source references; [`src/ManagedDoom/ORIGIN.md`](../src/ManagedDoom/ORIGIN.md) records the adopted PowerShell fork and local changes.
