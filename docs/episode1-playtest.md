# Ultimate Doom Episode 1 human playthrough

This is one complete human playthrough milestone, not a request for separate map-by-map reports. It advances the broader release roadmap without closing the remaining Ultimate Doom, Doom II, performance, fidelity, or MyHouse gates.

## Playthrough scope

Start a new game on HMP (skill 3) in Episode 1. Take E1M3's secret exit to E1M9, finish that map, verify the return to E1M4, then complete E1M4 through E1M8. In E1M8, defeat the boss to open the exit. Advance the ending intermission until the Episode 1 finale appears.

`E1M1 → E1M2 → E1M3 → E1M9 → E1M4 → E1M5 → E1M6 → E1M7 → E1M8 → Episode 1 finale`

A normal completion is enough; 100% kills, items, and secrets are not required. The finish point is the E1 finale screen (`E1TEXT` / `CREDIT`).

## Build and launch

Use the development build with game source at commit `cdd5fdd68734dbc663367f44117fd8a49ac17694` on branch `codex/feasibility-study`. R14 adds same-emitter sound replacement across sound categories to R13; gameplay and rasterizer behavior are unchanged. The source-pinned [R14 candidate receipt](../results/episode1-current-human-candidate-20260929-r14.json) records focused checks and carried-forward Episode 1 readiness evidence.

The focused worker tests pass 12 checks on same-map save/new-game paths, 12 on changed-map paths, and four session-worker cases with exact screen/menu/automap output and persistent workers. One sequential PresentMon pair measured the same-map reload pause at 0.358 seconds versus 6.178 seconds before the change; overall update rate did not improve, and the observed display rate remains below 60. This is a targeted reset improvement, not a pacing qualification. See the [measurement receipt](../results/renderer-same-map-reset-presentmon-20260929.json).

`Play.ps1 -Check` reports `Ready` for the Steam IWAD's 36 maps and all 11 catalog reports under PowerShell 7.6.5. R14 passes 27 deterministic mixer checks and 7 production packet-path checks for same-emitter replacement across sound categories. A five-second current-source headless scripted-attack run produced 14 audio events and a peak of one active voice through the real audio worker while D_E1M1 played; the device closed cleanly with no reported software queue-starvation or rebuffer observations. It submitted 230,580 frames and completed 225,540, with a 5,040-frame shutdown-cancellation upper bound. This verifies a short effect/mixer/device path, not sound quality or same-emitter cross-category playback at the device. The music-only startup check is also recorded [here](../results/episode1-current-audio-startup-r14-20260929.json). A saved audio replay diverges from the current gameplay state at tic 350, so its output cannot qualify this build's rendered audio. See the [scripted effect receipt](../results/episode1-current-audio-effects-r14-20260929.json). The chainsaw crash report and verified fix are recorded under [current evidence and limits](#current-evidence-and-limits); 35-tic/60-display pacing is not qualified.

From PowerShell, use the existing checkout and your Steam Ultimate Doom `DOOM.WAD`:

```powershell
$root = 'C:\projects\pwshDoom'
$wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD'
$local = Join-Path $root 'local'
$catalog = Join-Path $local 'music-prepared-episode1.json'
$record = Join-Path $local 'episode1-human-input-r14.json'
$report = Join-Path $local 'episode1-human-session-r14.json'
$saves = Join-Path $local 'episode1-human-saves-r14'
$settings = Join-Path $local 'episode1-human-settings-r14.json'
pwsh -NoProfile -File (Join-Path $root 'Start-Doom.ps1') `
  -Wad $wad -Workers 16 -Episode 1 -Map 1 -Skill 3 -Style Classic -Sound `
  -MusicCatalog $catalog -RecordInput $record -Report $report `
  -SaveRoot $saves -SettingsPath $settings -Maximized -FontSize 5
```

Use 64-bit PowerShell 7.6.x and Windows Terminal. The required Ultimate Doom IWAD is user-supplied and must match SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`. Sound effects and the prepared eleven-track Episode 1 music catalog are enabled. The catalog is local, built from the user's IWAD and soundfont; it is not included in the repository. If it is unavailable, omit `-MusicCatalog $catalog` to keep sound effects and play without background music. The current R9 five-second headless E1M1 run under PowerShell 7.6.5 selected D_E1M1, submitted and completed 220,500 audio frames, and shut down cleanly. Its one queue-empty observation followed the final packet; no rebuffer resume occurred. The equivalent 7.6.6 run completed 174 tics, returned 219,240 of 219,240 audio frames, selected D_E1M1, and closed cleanly; one queue-starvation poll after packet 173 had no resume. These are brief startup checks, not acoustic or full-session continuity evidence. In an interactive `-Sound` session, the audio worker advances music/effects through temporary simulation-packet gaps; headless sessions remain packet-exact unless `-RealtimeAudio` is selected. See the [7.6.5 host receipt](../results/episode1-r9-audio-smoke-20260929.json), [7.6.6 host receipt](../results/episode1-r9-audio-smoke-7.6.6-20260929.json), and [7.6.6 playback checks](../results/music-playback-runtime-7.6.6-20260929.json).

Before it opens Windows Terminal, `Start-Doom.ps1` checks that every music catalog report is qualified for the current PowerShell runtime and synthesis source. This quick check does not hash the large PCM payloads or confirm the active IWAD's score lumps; the audio and simulation workers repeat those full checks during startup. `Play.ps1 -Check` runs the same metadata preflight without starting the game.

The r3 audio receipt is pinned to implementation commit `41e167f` and records eight actual-waveOut continuity checks, a four-second E3M6 host run, and a save/load/new-game audio-worker run. The r6 receipt adds a current-source E1M3 sound-enabled host check along with map, route-transition, boss, and renderer-worker results. These bounded checks do not measure audible quality, physical device underruns, input-to-speaker latency, full-session continuity, or game/display pacing.

The startup failure reported under PowerShell 7.6.6 came from overly strict runtime-version and line-ending checks in qualified music reports. The reader now accepts equivalent PowerShell text across LF/CRLF checkouts and compatible 7.6.x patch versions while still rejecting changed source text. The Preview.3 package passes 22 reader checks and starts the 11-track Episode 1 catalog in a two-second, sound-enabled headless run under PowerShell 7.6.5, advancing 69 tics with no host error or audio-backpressure sample. The five-second startup run is pinned to the earlier audio implementation commit `41e167f`; the r5 renderer change has separate all-map, three-style worker, and persistent-worker reload checks. Neither brief host run verifies full-session music continuity, audible quality, or playback under visible Terminal load.

On a cold start, allow up to 60 seconds for simulation and music workers to initialize. Keep the 16 renderer workers. One r7 60-second headless run sampled a 3.77 GiB worker working set at shutdown; this is not a peak or time average. The Classic view needs at least 320 columns by 100 rows; the 5-point font and maximized window help fit it. If the viewport is short, enlarge the window or press Ctrl+- to reduce the font. Blank space around the centered image in a larger terminal is expected. The raw human input, session report, saves, and settings use fresh `r14` paths so earlier attempts remain intact.

The `r14` input/report paths and dedicated save/settings locations preserve earlier attempts. Confirm that the two output files do not already exist before launch; keep all generated data under `C:\projects\pwshDoom\local` and do not share it with the WAD.

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

The R12 source passed the 36-map smoke and five-view 16-worker comparisons in Classic, Matrix/Katakana, and AnsiArt/Katakana (320,000 pixels per style), along with 20 masked-wall checks and the occluded-BON1 scene regression. All 120 paired E1M1/E3M6 renderer frames match the previous source exactly; fixed-state serial medians improve 10.68% and 5.70% in two E1M1 repeats, while E3M6 is effectively unchanged. These are not live-game or display-rate measurements. R13 added host/simulation map-asset reuse, and its current-source tests exercise same-map reuse and changed-map asset loading. R14 changes sound arbitration only. Earlier campaign evidence remains in the [R9 candidate receipt](../results/episode1-current-human-candidate-20260929-r9.json), [music-open measurement](../results/music-catalog-open-parallel-20260929.json), and [7.6.5/7.6.6 audio smoke receipts](../results/episode1-r9-audio-smoke-20260929.json). The old 7,118-command E1M3 replay diverges at 23 checkpoints against both pre-change and r8 source, starting at tic 350; its mismatch cause is unknown, so it is not current route evidence. No map smoke or fixture completes any map; Jason's complete route and finale remain pending.

The earlier E1M2 chainsaw crash has a saved simulation exception: PowerShell attempted an ordered comparison on a custom `Angle` instance (reported as 16.8992 degrees), which does not implement `IComparable`, inside `WeaponBehavior.Saw` while the chainsaw turned toward its target. The current code compares the wrapped binary-angle `.Data` values explicitly, with a signed conversion where needed. The focused regression selects the Chainsaw ready state, supplies the Attack command through `DoomGame.Update`, and reaches the player weapon action against a living E1M2 imp without the exception; the imp falls from 60 to 56 HP after four simulation tics. This uses a fixed test position and is not a campaign route. Replaying the saved 26,731-command human input against current source consumes every command without a simulation exception, but its recorded source fingerprint differs and the first of 79 checkpoints diverges at tic 350; the replay remains in E1M1, so it does not reach or independently verify the former E1M2 crash state. Treat that attempt as stale-source diagnostic evidence, not a current full-route regression or a new human test. The current chainsaw and homing-turn checks are recorded at [saw-attack.json](../results/saw-attack.json); replay limits are recorded in the [ledger](ledger.md#2026-09-28--recheck-the-chainsaw-fix-against-current-source). Existing E1M1–E1M4 automated route receipts are retained at their original source pins. One E1M3 waypoint driver stalled without exposing a reproducible product defect, and it was not tuned further.

The raised-floor columns in Jason's E1M1 screenshot were lower-sector Techpillar sprites whose overlap matches classic Doom's plane/sprite draw order in both repository renderers. Jason clarified that the object seen through a wall near the blue armor is the pre-existing Gibs pile (DoomEdNum 24), not a corpse from a killed enemy. A later two-camera sweep at the recorded input states nearest the blue armor (tic 8400) and a nearby Gibs pile (tic 8750) compares both documented `POL5` actors at sixteen headings per camera, for 64 isolated actor/view comparisons. Its only candidate-only actor-mask pixel is on a floor plane; detail shows the reference draws the same actor palette index as that pixel's background, while the candidate floor differs. This is a one-pixel background/mask disagreement, not evidence of a sprite drawn through a wall. The sweep does not establish the exact view Jason saw or original-executable parity. See the [angle-sweep receipt](../results/episode1-pool-gibs-angle-sweep-20260928.json) and the [single-pixel detail](../results/episode1-pool-gibs-angle0-detail-20260928.json). If the sighting recurs during the complete human run, note the location and viewing direction. Whole-episode audio continuity, audible quality under sustained renderer load, physical keyboard response, 35-tic simulation pacing, and 60 displayed updates/sec are not certified. Rendering remains an approximation; no independent original-executable parity is claimed.

The [roadmap](roadmap.md) keeps the broader release gates open. The [reference audit](reference-audit.md) explains the original C# Managed Doom lineage and current source references; [`src/ManagedDoom/ORIGIN.md`](../src/ManagedDoom/ORIGIN.md) records the adopted PowerShell fork and local changes.
