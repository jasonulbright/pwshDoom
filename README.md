# pwshDoom

A PowerShell Doom prototype for Windows Terminal, with a retained investigation and measurement ledger. Game logic, software rendering, and terminal encoding are PowerShell. User-supplied IWADs stay outside the repository.

The E1M1 test completes the level through normal movement, turning, shooting, and use commands, with five kills and no cheats. A full-level Windows Terminal run at **320×200 completed 60.0 image updates/sec and 34.9 simulation tics/sec** over 44.68 seconds. This meets the average throughput target on the tested machine; timing spikes remain. Completed writes are not measured monitor presentations. See [implementation and validation](docs/implementation.md) for the measurements, reproducible route, and limits.

## Play

Run in PowerShell 7.4 or later on Windows with Windows Terminal:

```powershell
pwsh -NoProfile -File C:\projects\pwshDoom\Start-Doom.ps1
```

The launcher finds the classic Steam Ultimate Doom IWAD at its usual location. For another location:

```powershell
.\Start-Doom.ps1 -Wad 'D:\Games\DOOM.WAD'
```

Startup loads the WAD, warms a disposable level, resets the game, and starts a simulation process and persistent rendering workers. The launcher adds a separate `pwshDoom` Terminal profile with a small font and opens a maximized window; the image requires 320 columns and 102 rows. `-Here` uses the current tab if it is large enough. `-Workers 16` is the tested default. Only classic Ultimate Doom E1M1 on skill 3 is validated so far. The measured setup used PowerShell 7.6.5, Windows Terminal 1.24, and a Core Ultra 7 265K; renderer and simulation working sets totaled about 3.3 GiB, excluding the coordinator and Terminal.

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
| Escape | Quit |

The prototype ends at level completion and writes `local/game-session.json`. It currently has no audio, menus, save/load, automap interface, or multiplayer interface. The new renderer approximates some visual effects and does not claim vanilla pixel or demo compatibility. Keyboard state handling has automated synthetic-record tests; physical keyboard play has not been observed by the agent.

To watch the reproducible E1M1 test in Terminal:

```powershell
.\Start-Doom.ps1 -Replay .\results\e1m1-route.json -Seconds 90
```

That recording requires the same IWAD hash as the test and the default skill 3 / episode 1 / map 1. Remove the added profile with `scripts/Remove-GameProfile.ps1`. Session workers and their disposable asset cache are cleaned up on normal exit and handled failures; abrupt coordinator termination also has an automated cleanup test.

## Source and tests

The gameplay core is an attributed GPL PowerShell translation of ManagedDoom, with integration fixes. See [source provenance](src/ManagedDoom/ORIGIN.md) and [LICENSE](LICENSE). No unlicensed third-party engine, compiled rendering helper, WAD, or native game binary is distributed. The only custom C# text declares Windows console/timer API signatures and an input record layout; it contains no algorithm bodies. A process-local 1 ms timer request is paired with its release on handled exit.

```powershell
pwsh -NoProfile -File scripts/Test-GameActions.ps1
pwsh -NoProfile -File scripts/Test-E1M1Route.ps1
pwsh -NoProfile -File scripts/Test-RenderPartitions.ps1
pwsh -NoProfile -File scripts/Test-ConsoleInput.ps1
pwsh -NoProfile -File scripts/Test-AnsiStrips.ps1
pwsh -NoProfile -File scripts/Test-SnapshotTransport.ps1
pwsh -NoProfile -File scripts/Test-GameLifecycle.ps1
```

The game tests need the user's matching Ultimate Doom IWAD. The input and codec tests do not. Existing PowerShell Doom projects are acknowledged explicitly; this repository makes no worldwide-first claim.

## Read the investigation

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
