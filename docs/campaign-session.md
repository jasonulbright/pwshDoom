# Campaign session foundation — 2026-09-11

Interactive play now continues from a completed map through the native intermission and into the next map. The same simulation process owns the session, and the same rendering processes reload the destination map's immutable assets. Ultimate Doom episode endings select the correct finale text, flat and end artwork. This is session foundation work; only E1M1 has a complete ordinary-input route, and the wider campaign remains unqualified.

```powershell
.\Start-Doom.ps1
.\Start-Doom.ps1 -Replay .\results\e1m1-e1m2-session-route.json -Seconds 90
.\Start-Doom.ps1 -Style Matrix -Replay .\results\e1m1-e1m2-session-route.json -Seconds 90
.\Start-Doom.ps1 -Style AnsiArt -Replay .\results\e1m1-e1m2-session-route.json -Seconds 90
```

Ctrl or E/Space/Enter advances the intermission stages. The legacy E1M1 benchmark replay retains its first-exit stop. Session replays include `ContinueCampaign=true`; their commands continue across intermission and map changes. These replays require the documented Ultimate Doom IWAD hash and skill 3 / episode 1 / map 1. Interactive episode/difficulty menus, pause UI, save/load and automap are the next session milestone. Escape still quits directly.

## Controller behavior and evidence

`Test-CampaignTransitions.ps1` first reproduced 13 failures in 54 checks. Targeted corrections route map-8 endings to the finale, return E4M9 to E4M3, retain secret-visit history, and convert par seconds to tics for the intermission. Episodes 2–4 now use their own text/flat. The fixture suite now has 57 passing checks including lethal damage followed by use-button rebirth, fresh world creation, reset pistol inventory, and level-to-level carryover. See [before](../results/campaign-transitions-before.json) and [current](../results/campaign-transitions-session.json). These tests deliberately set routing/inventory/damage conditions; they are not playthroughs.

The behavioral reference is id Software's [game controller](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/g_game.c) and [finale code](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/f_finale.c). The existing adopted episode-4 par table is retained; the study does not reproduce or claim compatibility with the original episode-4 out-of-bounds lookup.

The separate [1,747-command session route](../results/e1m1-e1m2-session-route.json) uses only ordinary `TicCmd` inputs. E1M1 exits at command 1,560 with five kills and 75 health. Three spaced use presses advance intermission; E1M2 starts at command 1,676 with matching health/armor/ammo and runs through command 1,747. This qualifies entry and continued simulation/rendering of E1M2, not its completion.

## Map and screen transport

World snapshots retain the existing paired numeric data for 3D interpolation. Their consistent slot header now includes game state, episode/map, health/kills and a monotonically increasing world generation. Intermission/finale pixels use a separate declared representation in the same snapshot slots: a 320×200 indexed, column-major framebuffer. Each renderer transposes only its own screen strip before using the selected PowerShell encoder. Classic, Matrix and AnsiArt retain their existing dimensions; a full-screen character view does not reserve a gameplay HUD region.

When the simulation creates a new world, it reports asset preparation, writes the new cache and publishes a matching generation. It then waits for an acknowledgment. The host drains old rendering, discards obsolete pending frames, asks every persistent worker to reload the new cache, verifies the snapshot generation, and acknowledges. This also covers world replacement on single-player respawn. No destination snapshot is deliberately rendered against the previous map's geometry.

The host stops its active scheduling clock during asset handoff and records the pause under `MapReloadPausedSeconds` / `MapReloads`. Wall duration includes this pause. Map loading that occurs inside the controller's update remains in the measured simulation tick cost, and queued commands are retained. The current handoff can visibly hold the prior screen; a loading indicator and further latency work remain usability tasks. A headless lifecycle run completed all 1,747 commands with one 0.909-second handoff and no error: [report](../results/session-host-buffer-fixed.json). The [first host attempt](../results/session-host-first.json) failed at intermission because an untyped PowerShell `if` result expanded the pixel buffer; the buffer is now explicitly `byte[]`.

## Session graphics

Native WAD intermission/finale graphics are drawn by the adopted PowerShell 2D renderer, with attribution preserved. The custom PowerShell 3D rasterizer remains the gameplay renderer. All image sampling, text drawing, character conversion and animation remain within PowerShell; Windows Terminal draws the emitted glyphs, and the external screen recorder encodes the video.

The first finale renderer probe divided by zero because it addressed instance text speed as a static field. Fixing that exposed expensive immutable flat/background redraw work and source-code indentation embedded in the translated finale strings. Backgrounds are now cached, text is revealed incrementally, and finale lines are de-indented with consistent line endings. E4 text that was visibly clipped now fits the screen. The initial cache change preserves all 24 tested indexed screen hashes; de-indenting intentionally changes the text snapshots. Each episode's line widths are checked against the actual WAD font. See [initial screens](../results/session-screens-first.json), [cache equivalence](../results/session-screens-cached.json), and [text correction](../results/session-screens-text-fixed.json).

Offline images were inspected for E1 stats/next-map and E2–E4 text/E4 artwork. They remain under ignored `local/`. These samples and successful rendering are not a complete vanilla visual comparison: finale timing/bunny animation, all stats/animation phases, alternate IWAD editions and broad campaign visuals still need qualification. The full original text timing no longer includes accidental source indentation.

## Actual Terminal recordings

All three styles completed the same 1,747-command session with no game error, no viewport pause, and E1M2 frames rendered with generation 2. Captures ran sequentially with unchanged runtime source and no concurrent study benchmark or video export. They are silent while audio remains unfinished.

| Style | Viewing copy under `local/recordings/` | Video duration | Active tics/sec | Completed writes/sec | Asset handoff |
| --- | --- | ---: | ---: | ---: | ---: |
| Classic | `session-classic.mp4` | 51.5 s | 34.712 | 58.217 | 0.910 s |
| Matrix / Katakana | `session-matrix.mp4` | 51.6 s | 34.718 | 59.421 | 0.938 s |
| Color art / Katakana | `session-ansiart.mp4` | 51.7 s | 34.706 | 58.307 | 0.887 s |

These recorded-run rates include UI/map-transition work. The explicitly paused asset handoff is excluded from the active denominator and included in wall duration. The lower write rates remain an open pacing issue; neither these console-write rates nor encoded 60 FPS certify displayed FPS. No new PresentMon capture accompanies these runs.

Viewing copies retain the handoff at its actual speed. Originals retain startup/chrome/margins and console return. Classic's 1600×902 crop includes a one-pixel alignment margin above and below the 1600×900 game image; character copies are 1280×800. Full decode counted 3,090 / 3,096 / 3,102 frames, including possible capture duplicates. Samples at 45.5, 47.5 and 50.5 seconds show stats, next-map screens, and the destination geometry/HUD. Classic's text is readable; character conversion obscures small intermission text, particularly in Matrix. Menu readability is a concrete M2 requirement.

The [recording manifest](../results/session-recordings.json) retains hashes, crop/trim parameters, raw game-report links and inspection scope. The [source manifest](../results/session-sources.json) freezes 224 runtime/capture files. The [final audit](../results/session-validation.json) verifies those hashes, 69 script/bundle parses, six video hashes, the functional result set and zero remaining owned game/recorder processes. Videos and extracted QA images remain ignored/local.

## Reproduce targeted checks

Use fresh report paths:

```powershell
.\scripts\Test-CampaignTransitions.ps1 -Output .\local\my-transitions.json
.\scripts\Test-SessionProgression.ps1 -Output .\local\my-session-route.json
.\scripts\Test-SessionScreens.ps1 -Output .\local\my-session-screens.json
.\scripts\Test-SessionWorker.ps1 -Style Classic -Output .\local\my-classic-worker.json
.\scripts\Test-SessionWorker.ps1 -Style Matrix -Output .\local\my-matrix-worker.json
.\scripts\Test-SessionWorker.ps1 -Style AnsiArt -Output .\local\my-art-worker.json
```

Each worker test checks 128,000 pixels and 14 encoded strips: independent row/column-major screen data, then real E1M2 rasterization after asset reload, using seven uneven workers whose process IDs must remain unchanged. Across three styles that is 384,000 pixels and 42 strips. Classic's 24 ANSI round trips and the character codec's 144 cases also pass. The first Classic worker harness attempt omitted the codec import; its failure report is retained separately.

Run one engine-building test at a time: current harnesses share the generated engine-bundle cache. The two initial unpaced route/screen probes overlapped and are not clean paired performance measurements. Later host/capture runs are serialized.

## Remaining release work

M2 now includes [versioned input recording](input-recording.md), with menus, pause/resume, save/load and automap next. M3 adds PowerShell audio decoding/mixing and music with measured device playback. M4–M7 retain reference fidelity, every-map ordinary-input completion, difficult workloads, actual human/1080p checks, a clean-checkout release candidate and the evidence-based article. No full-campaign or new 60-displayed-FPS claim follows from this session handoff.
