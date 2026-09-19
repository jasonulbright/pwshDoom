# Vanilla demo input investigation

2026-09-19. Recorded human inputs offer a way to exercise gameplay without extending the waypoint bot. The adopted engine already has a version-109 demo decoder and playback controller, but the shipped terminal launcher does not expose `.lmp` playback. Compatibility with original Doom remains unverified.

## Two confirmed defects

The external-file `Demo` constructor called `$this.new(...)`, which is not a PowerShell constructor-chaining mechanism. Loading the installed WAD's DEMO1 as a local `.lmp` fails with “Demo does not contain a method named new.” Both constructors now call a shared initializer; the parsing algorithm is unchanged. `results/vanilla-demo-reader-before.json` preserves the original failure. Nineteen checks in `vanilla-demo-reader-after.json` verify authored signed movement/turn/button values and matching file/byte-stream options and commands for all three installed demos (1,710, 2,347 and 3,863 commands).

Executing DEMO1 through `DoomGame` then exposed an actual gameplay exception after 687 completed commands: `ThingMovement.XYMovement` accessed nonexistent `Map.SkyFlatNumber` during blocked missile movement. The flat number belongs to `Map.Flats.SkyFlatNumber`, as already used by hitscan code. Correcting that lookup allows all 1,710 commands to execute. Preserve `results/vanilla-demo1-gameplay-first.json` and `-second.json` as the failure and corrected run. This path is gameplay code shared with normal play, not a recorder or terminal effect.

## Evidence boundaries

The second built-in demo executes all 2,347 commands on E2M2 without an exception or observed player death (`results/vanilla-demo2-gameplay-first.json`). All 19 retained pre-crash E1M5 samples also match after the sky-flat fix (`vanilla-demo1-prefix-parity.json`). Neither result establishes original-engine synchronization. DEMO3 was decoded for file parity but has not been simulated in this investigation.

DEMO1 starts E1M5. The corrected run observes the player's first death at command 1,632. No original-engine trace has been compared, so completion of the input stream is not proof of synchronization, a successful map route, or intended player survival. Do not add it to the campaign completion column. The decoder's handling of malformed input is also not qualified by these valid-input checks.

`scripts/Inspect-WadDemo.ps1` reads a user-owned IWAD demo, initializes its original options including DemoPlayback, and passes its commands to the real game. It records transitions, selected state every 35 commands, first death and final state. It makes no world-state edits, opens no terminal window or audio device, and has a 20,000-command cap. The resulting runtime is not a performance benchmark. `scripts/Test-DemoReader.ps1` removes its uniquely named extracted temporary demo; no demo bytes or WAD assets enter Git.

```powershell
.\scripts\Test-DemoReader.ps1 -Output .\local\my-demo-reader.json
.\scripts\Inspect-WadDemo.ps1 -Name DEMO1 -Output .\local\my-demo1.json
```

Original-engine state comparison is needed before using external completion demos as campaign evidence. These initial runs establish useful defect discovery, not an alternative definition of completed gameplay.
