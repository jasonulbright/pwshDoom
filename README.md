# pwshDoom

A PowerShell Doom prototype for Windows Terminal, with a retained investigation and measurement ledger. Game logic, software rendering, and terminal encoding are PowerShell. User-supplied IWADs stay outside the repository.

September 19 status: E1M1–E1M4 have independently replayed HMP normal-exit routes, with inventory-preserving entry into the following map. E1M5 route development is underway. Full-episode continuity and the release gates remain open. With the newer gameplay, automap and music load, the measured E1M3 headless prefix averages **30.829 simulation tics/sec**; sustained 35-tic/60-display performance remains a target. Four newer captured E1M2 continuations reach 34.69–34.99 tics/sec but vary from 38.52–57.17 completed image writes/sec. [Output batching](docs/terminal-output.md) lowers host output time without a consistent whole-game improvement, so the default is unchanged. These are different workloads and are not a causal before/after comparison. Read the [working article](docs/article-draft.md), [campaign matrix](docs/campaign-matrix.md) and [E1M3 performance evidence](docs/automap-discovery-performance.md).

The E1M1 test completes the level through normal movement, turning, shooting, and use commands, with five kills and no cheats. Earlier builds completed full-level Windows Terminal runs at **320×200 with about 60 image updates/sec and 34.9 simulation tics/sec**. Their PresentMon captures measured 57.60–59.96 displayed Terminal updates/sec, without identifying the Doom framebuffer contents of every presentation. The automap integration initially regressed pacing to 13.48 seconds for ten seconds of simulation. Numeric discovery and lower-allocation encoding recover **350 tics in 10.03 seconds and 59.8 headless completed updates/sec** in the sixteen-worker control test. Timing spikes and broader workloads remain unqualified; the earlier display measurements do not qualify this build. See [automap findings](docs/automap.md), [implementation and validation](docs/implementation.md), [viewport findings](docs/viewport.md), and [PresentMon findings](docs/presentmon-validation.md).

## Play

Run in PowerShell 7.4 or later on Windows with Windows Terminal:

```powershell
pwsh -NoProfile -File C:\projects\pwshDoom\Start-Doom.ps1
```

The launcher finds the classic Steam Ultimate Doom IWAD at its usual location. For another location:

```powershell
.\Start-Doom.ps1 -Wad 'D:\Games\DOOM.WAD'
```

Startup loads the WAD, warms a disposable level, resets the game, and starts a simulation process and persistent rendering workers. The launcher adds a separate `pwshDoom` Terminal profile with a 6-point font and opens a window. The full 320×200 image occupies **320 columns × 100 rows** and is centered in any extra space. Shrinking below that size pauses the game; enlarging it resumes. `-FontSize 5` makes the image smaller physically; a larger value makes it larger. `-Maximized` is optional, and `-Diagnostics` adds two status rows (102 required). `-Here` uses the current tab and its existing font. These are character-grid requirements, not a minimum monitor resolution; see [window sizing and resize behavior](docs/viewport.md).

For Doom made of characters, choose an optional style:

```powershell
.\Start-Doom.ps1 -Style Matrix
.\Start-Doom.ps1 -Style AnsiArt
```

Matrix uses green code and animated falling highlights; AnsiArt uses full-color brightness/edge glyphs. Both now default to **half-width Japanese katakana**, using MS Gothic at 12 points and **160×50 cells**, with a block HUD. `-GlyphSet Ascii` restores the earlier alphabet and Cascadia Mono font; `-FontFace` permits an explicit font choice. They encode the same 320×200 rendered scene into a deliberately lossy character view. `-Style Classic` retains the default half-block output. See [character modes and measurements](docs/character-modes.md) and [screen recordings](docs/recordings.md).

`-Workers 16` is the tested default. All 36 classic Ultimate Doom maps pass a short headless loading/simulation/rendering sweep at skill 3; E1M1–E1M4 also have independently qualified normal-exit input routes. See the [campaign matrix](docs/campaign-matrix.md) for the distinction and remaining work. The earlier measured setup used PowerShell 7.6.5, Windows Terminal 1.24, and a Core Ultra 7 265K; renderer and simulation working sets totaled about 3.3 GiB, excluding the coordinator and Terminal.

Classic has an experimental `-AnsiEncoding ColorState` option that preserves pixel colors while sending fewer color instructions. It reduces bytes in the tested scenes and recorded routes, but a consistent whole-game speedup is not established; `Pairs` remains the default. See the [encoder comparison](docs/ansi-color-state.md). Matrix and AnsiArt keep their existing encoders.

| Key | Action |
| --- | --- |
| W / S, up / down | Forward / backward |
| A / D | Strafe |
| Left / right arrows | Turn |
| Ctrl | Fire |
| E / Space | Use doors and switches |
| Shift | Run |
| 1–7 | Select weapon |
| Enter | Use / respawn after death |
| P / Pause | Pause; P, Enter or Escape resumes |
| Escape | Open menu / go back |
| Tab | Open / close automap; gameplay continues |
| + / − while map is open | Zoom in / out |
| F while map is open | Toggle following the player |
| Arrows while map is open | Pan when follow is off |
| M / C while map is open | Mark location / clear marks |

Interactive sessions continue through intermission into the next map, refreshing map assets in the same rendering workers. Use Ctrl or E/Space/Enter to advance intermission. Episode endings select their own finale text and art. Escape opens [menus](docs/menus.md) for resuming, starting an episode/difficulty, saving/loading, viewing controls and confirming quit. Menu arrows choose and Enter selects. Held gameplay keys must be released before they act again after a menu. The report is `local/game-session.json`. [Automap controls](docs/automap.md), save state and replay are integrated, with pacing and broader discovery qualification unfinished. [Input settings](docs/settings.md) provide persistent always-run and keyboard turn speed. Opt-in `-Sound` enables [PowerShell sound effects](docs/audio.md); persistent volume and mute are available, while music and audio timing qualification remain unfinished. Multiplayer is unfinished. The new renderer approximates some visual effects and does not claim vanilla pixel or demo compatibility. Keyboard state handling has automated synthetic-record tests; physical keyboard play has not been observed by the agent. See [campaign session work](docs/campaign-session.md).

[Save/load](docs/save-load.md) provides six slots per IWAD, with confirmation before loading or replacing an occupied slot. The previous save is retained as a backup. Saves default to `%LOCALAPPDATA%\pwshDoom\saves\<IWAD SHA-256>`; `-SaveRoot 'D:\DoomSaves'` chooses another root. Saving/loading pauses the game for a few seconds with a progress screen. A changed engine version is shown before attempting a load; incompatible or corrupt files are rejected.

Add `-RecordInput .\local\my-play-session.json` to retain a replay of your commands at orderly exit. Play it back with `-Replay .\local\my-play-session.json`; starting skill/episode/map are selected from the recording. Replays containing loads also require their archived saves under the original `-SaveRoot`. Existing recording files are never overwritten. See [input recording and checkpoint limits](docs/input-recording.md).

To watch the reproducible E1M1 test in Terminal:

```powershell
.\Start-Doom.ps1 -Replay .\results\e1m1-route.json -Seconds 90
.\Start-Doom.ps1 -Replay .\results\e1m1-e1m2-session-route.json -Seconds 90
```

These recordings require the same IWAD hash as the test and the default skill 3 / episode 1 / map 1. The first retains its historical stop at the E1M1 exit; the second advances through intermission and renders E1M2. Remove the added profile with `scripts/Remove-GameProfile.ps1`. Session workers and their disposable asset cache are cleaned up on normal exit and handled failures; abrupt coordinator termination also has an automated cleanup test.

## Source and tests

The gameplay core is an attributed GPL PowerShell translation of ManagedDoom, with integration fixes. See [source provenance](src/ManagedDoom/ORIGIN.md) and [LICENSE](LICENSE). No unlicensed third-party engine, compiled rendering helper, WAD, or native game binary is distributed. The game's custom C# text declares Windows console/timer API signatures and an input record layout; it contains no algorithm bodies. A process-local 1 ms timer request is paired with its release on handled exit. Optional PresentMon measurement scripts also declare API signatures for the installed external tool; the game does not load PresentMon.

```powershell
pwsh -NoProfile -File scripts/Test-GameActions.ps1
pwsh -NoProfile -File scripts/Test-E1M1Route.ps1
pwsh -NoProfile -File scripts/Test-RenderPartitions.ps1
pwsh -NoProfile -File scripts/Test-ConsoleInput.ps1
pwsh -NoProfile -File scripts/Test-AnsiStrips.ps1
pwsh -NoProfile -File scripts/Test-CharacterCodec.ps1
pwsh -NoProfile -File scripts/Test-Viewport.ps1
pwsh -NoProfile -File scripts/Test-SnapshotTransport.ps1
pwsh -NoProfile -File scripts/Test-GameLifecycle.ps1
```

The game tests need the user's matching Ultimate Doom IWAD. The input and codec tests do not. Existing PowerShell Doom projects are acknowledged explicitly; this repository makes no worldwide-first claim.

## Read the investigation

- [Release and research roadmap](docs/roadmap.md): milestones, completion criteria, alternatives, and the write-up plan.
- [Campaign qualification matrix](docs/campaign-matrix.md): per-map smoke versus actual completion evidence and current blockers.
- [PowerShell-only 60 FPS rendering investigation](docs/sixty-fps-investigation.md): the new parallel renderer, measured 60-update pacing, and remaining gameplay/display work.
- [First findings](docs/findings-2026-09-10.md): measured outcomes, limitations, and the next useful experiment.
- [Ledger](docs/ledger.md): dated decisions, observations, corrections, and experiment outcomes.
- [Existing implementations](docs/existing-implementations.md): evidence and gaps in current offerings.
- [Terminal architecture](docs/terminal-architecture.md): the PowerShell/ConPTY/Terminal boundary and relevant features.
- [Experiment protocol](docs/experiment-protocol.md): measurements, controls, and interpretation.
- [Reproduction steps](docs/reproduce.md): run the finite benchmarks and clean up the study profile.
- `results/`: portable summaries and machine-readable measurements.
- `local/`: ignored machine-specific inventories, downloaded tools, external checkouts, and copyrighted test material.

## Rules of evidence

Use **measured**, **source-inspected**, **author-reported**, **hypothesis**, or **not tested** when recording a finding. A script's completed writes are not proof of displayed frames. A screenshot is not proof of frame rate. A working map is not proof of a complete Doom implementation.

Commercial WAD files remain user supplied. Do not commit game assets, extracted frames, downloaded binaries, or external source trees. Preserve upstream license terms before incorporating upstream code; inspection alone is not an adoption decision.

All experiments must be finite and write their results to disk. Keep security settings unchanged. Record failures and changes to the protocol, including environment interference.
