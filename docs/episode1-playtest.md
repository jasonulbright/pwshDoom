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

Engine/source baseline: commit `9b5a7b45f9b5d299f8f1bbebc866abc84eee30a4`.
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
use short discrete presses for switches. The game pauses when the Terminal
viewport is too small; increase its usable rows/columns or reduce font size if
the image does not fit. The 11-track Episode 1 catalog is enabled. Its actual
simulation/audio worker passed 15 save/load/new-game checks, including 97,020
music frames and clean device shutdown; whole-campaign music continuity,
35-tic/60-display pacing, and audible review of every track are not certified.
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

### Jason's human result

Pending. Record only the maps reached, whether E1M9 returned to E1M4, finale
reached/not reached, and any deaths, reloads, deviations, or reported defects.
