# Ultimate Doom Episode 1 human playthrough

This is one complete human playthrough milestone, not a request for separate
map-by-map reports. It advances the wider roadmap toward the first release;
it does not close the remaining Ultimate Doom, Doom II, performance, fidelity,
or MyHouse audit gates.

## Scope

Start a new game at HMP (skill 3) in Episode 1 and play through the finale. Take
the E1M3 secret exit to E1M9, complete that secret map, and verify its return to
E1M4. Continue E1M4 through E1M8, including the boss-triggered opening in
E1M8, and advance the ending intermission until the Episode 1 finale appears.
The expected map sequence is:

`E1M1 -> E1M2 -> E1M3 -> E1M9 -> E1M4 -> E1M5 -> E1M6 -> E1M7 -> E1M8 -> Episode 1 finale`

This asks for a normal completion, not 100% kills, items, or secrets. Note any
deaths, reloads, deviations from the route, or places where progress stopped.
The endpoint is the Episode 1 finale screen (`E1TEXT` / `CREDIT`), after the
E1M8 exit and intermission.

## Build and launch

Run exact source build commit `68b1b82be1a1fcda0401fd454204e52f870e54d7` from
the `codex/feasibility-study` branch. Its gameplay, renderer, session/menu and
input source match the verified baseline `693cc061a2caa1fac36fc8a0e6d2e6830a6a4577`;
the production change since that baseline is the separately qualified finite
music playback path. The earlier baseline's 295 focused campaign,
boss-trigger, session, menu and synthetic-input checks passed, as did its
36-map smoke, 16-worker style checks, exact tangent-angle parity and launcher
check. The [readiness receipt](../results/episode1-playtest-readiness.json)
links that evidence and the current audio update. Fresh D_INTRO and Episode 1
worker receipts verify finite playback and save/load compatibility on this
build. No recorded or bot-driven full-campaign route is being treated as human
playthrough evidence.
Run from the repository root in 64-bit PowerShell 7.4 or later on Windows,
with Windows Terminal, the legally obtained Ultimate Doom `DOOM.WAD`, and the
prepared local music catalog `local/music-prepared-episode1.json`. The tested Steam IWAD is
`C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD`,
SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`.
The catalog SHA-256 is `0E9C9542C75F4D5E2D7FC71E42FAFBB58F94321C3B8A49BA0C9AC5A93752EE58`;
it and its prepared audio files remain local and are not included in Git.
Commercial game files are not included.

```powershell
pwsh -NoProfile -File .\Start-Doom.ps1 `
  -Wad 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD' `
  -Episode 1 -Map 1 -Skill 3 -Style Classic -Sound `
  -MusicCatalog .\local\music-prepared-episode1.json `
  -RecordInput .\local\episode1-human-playthrough.json `
  -Report .\local\episode1-human-session.json -Maximized
```

The build uses sixteen renderer processes by default. Leave that setting in
place for this handoff. The current disposable worker-asset format is v6; the
readiness receipt records current-format worker checks. A focused E1M1-to-E1M2
reload writes new v6 assets, keeps all sixteen render workers alive, and
matches 256,000 pixels and 64 encoded strips against serial output
([receipt](../results/session-worker-sprite-rotation-classic.json)). An earlier
headless host transition used v4 and wrote no terminal frames, so it does not
certify visible frame rate or full-campaign audio continuity. Its sixteen
workers used about 4.0 GB of combined working memory; mention any memory
pressure or sluggish response during play.

At the final preflight, `%LOCALAPPDATA%\pwshDoom\settings.json` did not exist,
so built-in defaults apply: Always Run off, turn speed 100%, sound volume 100%,
and mute off. The session report records the preferences actually loaded.

If Steam installed the IWAD elsewhere, replace only the `-Wad` value with the
path to that same Ultimate Doom IWAD. The recording and session report paths
must not already exist.

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

Hold the key briefly for movement, release it before changing direction, and
use short discrete presses for switches. Classic needs a Terminal viewport of
at least 320 columns by 100 rows. The game pauses if it is smaller; reduce the
font size or enlarge the window if needed. Larger viewports center the game
image, so blank space around it is expected. The 11-track Episode 1 catalog is
enabled. Its actual simulation/audio worker passed 15 save/load/new-game checks,
including 97,020 music frames and clean device shutdown; the updated worker also
passes on the current build. Whole-campaign music continuity, 35-tic/60-display
pacing, and audible review of every track are not certified.
Report visible stalls, delayed controls, or missing/dropout sound. Rendering
remains an approximation rather than vanilla pixel/demo compatibility.

## Reporting

At the end, report either **all clear** or the last map and what happened.
For an issue, include the map, what you pressed or expected, what the game did,
and whether you died, reloaded, paused, or resized the window. Preserve the
input recording and session report until the result is documented; they can
make a reported issue reproducible. Do not send WAD files.

The human result will be recorded below with only the scope and outcomes Jason
reports. Automated smoke, controller fixtures, synthetic keyboard records,
and boss-trigger checks are separate evidence and are not substitutes for this
playthrough.

## Readiness evidence

The machine-readable [readiness receipt](../results/episode1-playtest-readiness.json)
and [campaign matrix](campaign-matrix.md) link the fresh map smoke, transition,
boss, menu/session, synthetic input, and music receipts. The latest
visibility-fix regression index records all four existing E1M1–E1M4 route
replays and the nine-map smoke; full raw replay reports remain under ignored
`local/visibility-intercept-regressions/`. The failed E1M5 automated route is recorded in
[`campaign-e1m5-investigation.md`](campaign-e1m5-investigation.md); it ended in
player death and did not establish a repeatable engine defect.

The current renderer passes a 36-map Ultimate Doom smoke on the same IWAD:
each map advances 35 idle tics and renders two full frames with sixteen strips.
This covers E1M1–E1M9 as startup/render cases, not map completion. Focused
engine/session/input checks also pass: 57 campaign transition/finale
checks, 97 boss checks, 125 menu/session checks with 46 screen fixtures, six
synthetic console-input checks, and ten menu-key checks. All were freshly
rerun on the pinned source; their individual receipts and limits are in the
[readiness receipt](../results/episode1-playtest-readiness.json). The current
IWAD/music-catalog preflight passes in
[`episode1-launch-preflight-sprite-rotation.json`](../results/episode1-launch-preflight-sprite-rotation.json).
The latest fixed-point floor/ceiling mapping brings the six-view scene-index
mismatch against the adopted PowerShell reference from 101,971 to 37,798
(62.9% fewer than the original numeric baseline); 7.38–14.19% still differ.
All three output styles match serial output exactly across 16 worker processes.
Serial render medians increased 6–10.5% in the two measured maps, and the
headless replay averaged 34.97 simulation tics/sec. These are not displayed-FPS
measurements; they set realistic expectations for Jason's run. This does not
establish original-executable parity. A subsequent sprite/weapon sampling fix
matches the adopted reference at seven fractional pistol offsets and reduces
scene disagreement in ten E1M1/E1M2 views by a further 3.78%; it raises serial
render medians slightly in the two measured maps. The readiness receipt links
raw reports with source hashes and exact test scope.

On 2026-09-26, a further world-sprite correction matched fixed-point masked
post sampling in 40 real-IWAD scale/origin cases (838 differences before,
zero after). The current source then passed the full 36-map smoke, exact
16-worker output for Classic, Matrix/Katakana and AnsiArt/Katakana, 138 weapon
lighting fixtures through asset format v5, and a live E1M1-to-E1M2 worker
asset reload. This improves a low-level sprite raster path; it does not certify
original-executable fidelity or map completion. The linked readiness receipt
pins the source commit and raw reports. The current-source Classic launcher
preflight also detects the installed IWAD, Windows Terminal, PowerShell 7.6.5,
and prepared Episode 1 catalog; the source-pinned path check is in the readiness
receipt, while the separate audio-worker checks qualify catalog contents and
playback integration.

The pinned source applies Doom-style 16.16 actor depth, scale, projected bounds,
lighting, and vertical texture origin. Across six static E1M1/E1M2 views it
reduces full-scene differences against the adopted PowerShell renderer by 538
indices. Rotated-frame selection now matches the adopted Doom binary-angle rule:
16,392 direction cases, 393,408 frame boundaries, six signed-int edge cases,
and 100,000 angle conversions pass with no mismatches. The former floating
calculation selected the wrong frame in 172,724 of the same boundary fixtures.
This is synthetic math parity; moving-actor visuals, occlusion parity, and an
independent original-executable comparison remain open. Classic,
Matrix/Katakana, and AnsiArt/Katakana each match serial output across 16 workers
(320,000 pixels and 80 encoded strips per style), and the exact source passes
the 36-map smoke and launcher preflight. Isolated paired timings are mixed and
do not establish a speedup or visible frame rate.

### Jason's human result

Pending. Record only the maps reached, whether E1M9 returned to E1M4, finale
reached/not reached, and any deaths, reloads, deviations, or reported defects.
