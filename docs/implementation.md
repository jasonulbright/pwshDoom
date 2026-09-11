# E1M1 implementation, 2026-09-10

The architecture and performance observations below describe the original E1M1 baseline. The 2026-09-11 [campaign session follow-up](campaign-session.md) adds live intermission/finale screens, map-generation handoff, and persistent-worker asset refresh. Its recordings and game timings are separate from the earlier PresentMon measurements.

The repository contains an executable E1M1 prototype and reproducible tests. Three full-level Windows Terminal replays at 320×200 completed **60.0 rendered image writes/sec and 34.9 simulation tics/sec**. Game logic, rasterization, interpolation, and terminal encoding are PowerShell algorithms. This establishes average throughput and one level's tested behavior; it does not establish a complete Doom source port or perfectly steady presentation.

## Play and reproduce

```powershell
pwsh -NoProfile -File C:\projects\pwshDoom\Start-Doom.ps1
```

The default IWAD is the user's Steam Ultimate Doom installation; use `-Wad` for another location. No WAD or extracted assets are distributed. The launcher creates a separate removable Terminal profile with a 6-point font and requests a 320×100 character window. Use `-FontSize` to change its physical size, `-Maximized` for maximization, or `-Here` for the current tab and font. The image centers in extra space and pauses when fewer than 320 columns or 100 rows fit. `-Diagnostics` adds two status rows. User defaults and `settings.json` are not edited. See [viewport behavior and tests](viewport.md) and Terminal's documented [command-line options](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments).

W/S move, A/D strafe, arrows turn or move, Ctrl fires, E/Space uses doors and switches, Shift runs, 1–7 select weapons, Enter uses/respawns, and Escape exits. Interactive sessions continue through intermission; the original single-map benchmark replay retains its first-exit stop. The session report defaults to ignored `local/game-session.json`.

To reproduce the full-level test:

```powershell
.\Start-Doom.ps1 -Workers 16 -Skill 3 -Episode 1 -Map 1 `
    -Replay .\results\e1m1-route.json -Seconds 90 -CaptureEveryTics 350 `
    -Report .\local\my-e1m1-session.json
```

The recording contains ordinary input commands, not rendered frames. Every update renders the live world. The IWAD SHA-256 is `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`. Use E1M1/HMP settings: the launcher verifies the asset hash but does not infer map/difficulty from the route file. Other IWADs/maps are not qualified.

## Architecture

The coordinator (`scripts/Invoke-Doom.ps1`) handles input, sends commands against an anchored 35 Hz clock, obtains consistent simulation snapshots, and manages rendering/presentation. The gameplay classes live in a **separate persistent PowerShell simulation process**. Late simulation tics are queued and caught up, never discarded to inflate rendering throughput. A disposable level warms for 140 tics and is reset; four initial render jobs also run outside measurement.

Only the simulation mutates the world. After each tic it publishes paired old/current continuous state for that same update, sharing current actor membership and discrete fields. The coordinator interpolates camera position/angle, view height, actor positions, and moving sector heights. Camera angle endpoints take the short wrapped path; initial view height follows the reference first-tic rule. Late snapshots can clamp interpolation to the current state, so simulation stalls can remain visible.

`src/SnapshotTransport.ps1` packs a versioned numeric array into bytes with standard .NET bulk copies. No JSON is serialized in the frame loop. Alternating shared-memory slots use odd/even version checks to reject torn reads. A bounded ring carries input commands. Each renderer gets a private snapshot and never reads live gameplay objects.

Sixteen persistent PowerShell rendering processes draw disjoint vertical strips. `src/FastRenderer.ps1` implements BSP traversal, projection, clipping, textured walls, horizontal floor/ceiling spans, sky, masked walls, depth-tested actors, weapon sprites, and a HUD. The view is 320×168 plus a 32-pixel HUD, with no adaptive resolution. Floor coordinates follow Doom's world-to-flat Y orientation.

Immutable map, texture, sprite, HUD, and palette data are transferred once through an ignored binary asset cache. Standard .NET memory-mapped files and events carry work/results. Workers decode snapshots into private reusable arrays/hashtables. The coordinator normally fetches only encoded strips; raw indexed pixels are fetched for captures and the final framebuffer.

The encoder creates true-color UTF-8 upper-half-block cells: 320 columns × 100 rows, with two optional diagnostic rows, bracketed by synchronized-output sequences. Each render job carries its viewport origin. The host discards a completed image if the grid changed while it was being encoded, and clears/recenters on the next valid image. An undersized window stops the active clock and new input-command issuance; restoring it resumes without queuing the paused time. Already issued simulation commands may finish. Reports preserve both active time and wall time, plus viewport history. A finite `-Seconds` limit uses wall time even while paused.

The host **dispatches the next render before writing the completed image**, overlapping rendering with console I/O. Completed bytes have already been copied out of shared memory. At most one render and one harvested image are pending. The anchored 60 Hz output schedule catches up after processing stalls.

Windows Terminal handles terminal parsing, glyph rasterization, and GPU composition; it does not execute Doom's renderer. The measured gains came from reducing PowerShell method-dispatch/serialization work, separating simulation, and overlapping stages.

Keyboard input uses `ReadConsoleInputW` records for held/released keys and short taps. Key state and TicCmd generation are PowerShell. The C# text in `src/ConsoleInput.ps1` contains only P/Invoke declarations and structure fields, with no algorithm bodies. Paired `timeBeginPeriod(1)` / `timeEndPeriod(1)` calls improve short waits without a persistent setting change. Microsoft documents process-specific behavior on current Windows and reduced guarantees for occluded applications. [Timer API contract](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod).

Handled exit restores input mode, encoding, cursor, and alternate screen, then closes owned workers and deletes their asset cache. Workers check for owner death while waiting; the simulation removes its cache on abrupt owner termination. `scripts/Remove-GameProfile.ps1` removes only the validated game fragment.

## Measurements

Machine: Core Ultra 7 265K, 20 cores/20 threads, 32 GiB DDR5-7200, RTX 4070 Ti SUPER, Windows 11, PowerShell 7.6.5 / .NET 10.0.11, Windows Terminal 1.24.11911.0. Actual terminal grid: 589×128. No security, power-plan, or default Terminal settings were changed. Scripts require PowerShell 7.4+, but older runtimes have not been benchmarked here.

The first complete pipelined run is in `results/game-terminal-pipelined-e1m1.json`; analysis is in `results/game-terminal-pipelined-cadence.json`:

| Measurement | Result |
| --- | ---: |
| Duration, excluding startup/shutdown | 44.679 s |
| Simulation commands / completed image writes | 1,560 / 2,681 |
| Simulation / completed-update throughput | 34.916 / 60.006 per second |
| Write interval: median / p95 / max | 16.290 / 22.738 / 74.010 ms |
| Intervals longer than 33.333 ms | 27 of 2,680 |
| Simulation work: median / p95 / max | 5.753 / 18.373 / 109.890 ms |
| Snapshot publication: median / p95 | 5.147 / 7.842 ms |
| Simulation-start lateness: p95 / max | 21.046 / 214.240 ms |
| Render-to-write latency: median / p95 | 27.011 / 37.549 ms |
| Outcome | Level complete, 5 kills, 75 health, no error |

The final repeat after initial-camera and cleanup fixes also completed 1,560 tics and 2,681 image writes in 44.680 seconds: **60.004 updates/sec, 34.915 tics/sec**, five kills, 75 health, no error. See `results/game-terminal-final-e1m1.json` and its cadence report. Exact runtime source hashes are in `results/implementation-sources.json`.

The release launcher was then checked with maximization enabled. At a 688×123 grid, it again completed 1,560 tics and 2,681 writes in 44.685 seconds: **59.998 updates/sec, 34.911 tics/sec**, the same kills/health/exit, and no error. Write intervals were median 16.162 ms, p95 24.406 ms, maximum 64.507 ms, with 28 above 33.333 ms. This historical run is `results/game-terminal-maximized-e1m1.json`, with `game-terminal-maximized-cadence.json` and `implementation-release-sources.json`. Since the preceding run, only launcher maximization, attribution comments, and trailing blank lines changed; source hashes describe exact worktree bytes, which Git line-ending normalization can alter.

After adding centered placement and resize pauses, two full routes with the new 6-point/windowed launch measured 59.997 and 60.010 completed writes/sec, and 34.911 and 34.918 tics/sec. Both had a stable 582×156 grid and no viewport pauses. PresentMon measured **57.604 and 57.664 displayed updates/sec**, including 101 and 102 dropped presents concentrated in the first three seconds. A 6-point maximized comparison reached **59.733 displayed updates/sec**, six dropped presents, and 59.997 writes/sec at 688×151. All completed the route with five kills and 75 health. The earlier 59.96 displayed result must not be relabeled as a result of this layout. See [viewport evidence](viewport.md) for raw reports, exact runtime hashes, and remaining uncertainty about window presentation.

`FrameMs` means **render submission to completed write latency**, not time between frames. Stages overlap, so 27 ms latency can coexist with 60 updates/sec. Consecutive `FrameStats[].EndQpc` values establish output intervals. A pending job finished during shutdown is not counted as a completed image update. New reports count simulation tics published at clock stop, excluding commands drained during cleanup.

Catch-up contributes to the average. Neither a 60 Hz average nor 35 tics/sec establishes that every deadline was met. The initial standalone PresentMon probe was denied access. After the user installed PresentMon, its documented service API became accessible: a full replay measured **59.96 ETW-reported displayed Terminal updates/sec**, with 24.279 ms p95 displayed-frame spacing and a 60.616 ms maximum. See [PresentMon validation](presentmon-validation.md) for the raw capture, windowing method, and limitations. Security/access settings were not changed. Input-to-display latency, optical measurement, and identification of each displayed Doom framebuffer remain untested. In the first pipelined run, renderer working sets totaled 2.99 GiB and simulation 0.30 GiB, excluding the coordinator and Terminal.

## Correctness evidence

- `results/game-actions.json`: nine checks for spawn, independently counted HMP monsters, initial camera height, movement/collision, ammunition, door motion, armor fixture/collection, and exit. Door/armor/exit fixtures explicitly reposition the player; these checks alone do not prove navigation.
- `results/e1m1-route.json`: input-only E1M1/HMP completion, 1,560 TicCmd updates and five kills. No teleports, direct damage, cheats, or direct special activation. Waypoint-only driver iterations do not advance simulation. Both earlier and current Terminal hosts replay it successfully.
- `results/render-partitions.json`: 320,000 pixels match across five views and seven uneven process strips, including bright-sector gunflash. Comparison against the pre-cast renderer also exercises the current asset cache and numeric transport. This is not vanilla pixel equivalence.
- `results/snapshot-correctness.json`: all-field wire round trips, interpolation endpoints/midpoint, private state reuse, actor removal, and malformed packet rejection. The transport benchmark also verifies exact real-E1M1 snapshot bytes.
- `scripts/Test-ConsoleInput.ps1`: six synthetic-record checks for native layout, simultaneous movement/fire, independent release, quick use, weapon selection, and focus loss. Physical keyboard gameplay has not been observed by the agent; no desktop keys were injected.
- `results/game-terminal-input-idle.json`: a five-second non-scripted Terminal session opened the real console input handle, polled native records, and exited normally. It completed 174 tics and 228 image updates in a 688×119 grid. This startup smoke test is not a steady-state throughput measurement or a physical key-action test. Its first attempt failed the old minimum-height guard at 589×98; the user subsequently clarified that they resized that window. The raw failure is preserved. It is not evidence of a Terminal launch defect.
- `results/viewport-tests.json` and `viewport-resize-session.json`: nine layout cases, three bounded pause messages, and real headless engine/render workers following synthetic resize dimensions. Two pauses stop new commands and active time; restoration resumes. This tests the resize logic, not physical desktop resizing or a 1080p monitor.
- Codec checks independently decode pixels: 24 ANSI strip cases across default and translated origins, 24 Sixel cases, and original goldens. The actual runtime ANSI encoder is tested. The process partition check also verifies cursor origins. Sixel remains an experiment.
- `results/game-lifecycle.json`: all owned child processes and asset caches disappear after finite normal exit and abrupt coordinator termination. This does not test physical terminal restoration after a crash.
- `scripts/Save-FramePreview.ps1`: optional offline contact sheets from captures. Rooms, enemies, weapon, and HUD were visually inspected. User-derived images stay ignored under `local/`; they are not monitor screenshots or presentation telemetry.

## Remaining limits

Only Ultimate Doom E1M1 on skill 3 has a complete route test. A subsequent 36-map load/35-idle-tic/two-frame smoke sweep found and fixed E2M7 line-flag enum conversion; all maps now pass that narrow sweep. It does not establish campaign completion, transitions, or visual-reference fidelity. See the [campaign matrix](campaign-matrix.md) and [completion roadmap](roadmap.md). Other IWADs, difficulties, lifts, denser combat, and campaigns need qualification. The interface stops at level completion. Audio, menus, save/load, automap, and multiplayer interfaces are absent. Vanilla demo synchronization is unverified.

Lighting is approximate; sky sampling, texture alignment, and sprite edges need reference comparisons. Damage/bonus palette effects and spectre fuzz are absent; the HUD weapon inventory indicator is incomplete. The GPL reference renderer remains available for comparisons. Physical keyboard play and input latency need direct testing.

Next work is consistent pacing and campaign correctness across more maps, with input/presentation measurements where available. Existing PowerShell Doom projects are acknowledged. The demonstrated combination is a reproducible complete E1M1 route with concurrent PowerShell simulation and full-color terminal rendering at these measured rates; this is not a worldwide-first or full-campaign superiority claim.

## Sources

Engine: [Oleyska's ManagedDoomPowershell](https://github.com/oleyska/ManagedDoomPowershell), pinned and attributed in `src/ManagedDoom/ORIGIN.md`. Original Doom defines [TICRATE as 35](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/doomdef.h).

Input follows Microsoft's [KEY_EVENT_RECORD](https://learn.microsoft.com/en-us/windows/console/key-event-record-str), [ReadConsoleInput](https://learn.microsoft.com/en-us/windows/console/readconsoleinput), and [console mode](https://learn.microsoft.com/en-us/windows/console/setconsolemode) contracts. The [ConPTY keyboard design](https://github.com/microsoft/terminal/blob/main/doc/specs/%234999%20-%20Improved%20keyboard%20handling%20in%20Conpty.md) explains key-down/up transport. These references support implementation choices, not an unperformed physical-input test.
