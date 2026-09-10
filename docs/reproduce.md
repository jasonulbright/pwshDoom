# Reproducing the first batch

Use Windows Terminal 1.24 or newer and PowerShell 7.4 or newer; the measured run used Terminal 1.24.11911.0 and PowerShell 7.6.5. Run the commands below from PowerShell 7 in `C:\projects\pwshDoom`. The launcher uses the executable running it, so Windows PowerShell 5.1 is not a substitute. Exact measured paths are in the JSON reports.

The scripts run finite cases and overwrite their selected JSON output. Save earlier results or pass another `-Output` path when making comparisons. Run one benchmark at a time. Terminal runs launch a separate window and return immediately; wait for that benchmark window to finish before launching the next experiment. The first synthetic replay takes roughly three minutes. Resizing or covering the window and other desktop activity may change results.

## Correctness and synthetic encoding

```powershell
Set-Location C:\projects\pwshDoom
.\scripts\Test-Codecs.ps1
.\scripts\Test-SixelRoundTrip.ps1
.\scripts\Measure-Encoding.ps1
.\scripts\Measure-AnsiOptimization.ps1
.\scripts\Measure-SixelOptimization.ps1
```

The first measurement builds eight-frame caches in ignored `local/frames/` and a manifest used by replay. The correctness tests check known fixtures and independently decode all pixel indices in 24 Sixel cases. They do not implement an entire terminal emulator or verify physical display colors. Sixel RGB percentages quantize the palette components; the pixel-index checks do not claim exact RGB equality with ANSI.

## Synthetic replay and live output

```powershell
.\scripts\New-ReplayPlan.ps1 -Dataset Synthetic -Output .\local\plan.json
.\scripts\Start-BenchmarkWindow.ps1 -Plan .\local\plan.json -Output .\results\terminal-replay.json
# Wait for that window to finish before starting the next command.
.\scripts\Start-BenchmarkWindow.ps1 -Live -Output .\results\terminal-live.json
```

The launcher adds one study profile through a JSON fragment. It requests an opaque, aliased, 7pt Cascadia Mono display and enough cells for the ANSI experiment. It preserves the normal profiles and default settings. Replay reports `TargetFps` for historical parameter naming; it is a **write pacing target**, not measured display FPS. Current runs use 165.

The harness explicitly sets the console output encoding to UTF-8 and records `OutputCodePage: 65001`, restoring the original value on exit. Initial terminal runs omitted this and are preserved under `results/pre-utf8-fix/`; do not use those for correct-output performance claims.

For a short separate console decoding check, run `Start-BenchmarkWindow.ps1 -Probe -Output .\results\terminal-utf8-check.json`. It compares cursor-column advancement after emitting the same three UTF-8 bytes for a half-block under the inherited encoding and explicit UTF-8. It does not check physical pixels or FPS. Run it separately from performance measurements.

## Real Doom scene

Supply your own original Doom/Ultimate Doom IWAD containing E1M1. This particular adapter does not select Doom II maps or load modern rerelease expansion resources. It does not redistribute a WAD or external renderer implementation.

Acquire the inspected external script at its pinned revision:

```powershell
$revision = '6b0072973cd08fb83edc521e834e4070cda4b0a5'
New-Item -ItemType Directory -Force .\local\upstream | Out-Null
Invoke-WebRequest "https://raw.githubusercontent.com/nick0451/doom-powershell/$revision/doom.ps1" -OutFile .\local\upstream\nick-doom.ps1
Get-FileHash .\local\upstream\nick-doom.ps1
```

Expected SHA-256: `30624D2F6878FE6832997C1F2B65858E7C26BAC9A54A1C920BC06E649471E943`. The adapter rejects any different file and imports only 13 inspected definitions. It does not execute upstream's main game or networking code. Source acquisition is separate from a decision to adopt upstream implementation code; licensing must be resolved before incorporation.

```powershell
$wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD'
.\scripts\Measure-DoomScene.ps1 -Wad $wad -Output .\results\doom-scene.json
.\scripts\New-ReplayPlan.ps1 -Dataset Doom -Output .\local\doom-plan.json
.\scripts\Start-BenchmarkWindow.ps1 -Plan .\local\doom-plan.json -Output .\results\doom-replay.json
# Wait for replay to finish, then run the combined renderer/encoder/write loop.
.\scripts\Start-BenchmarkWindow.ps1 -DoomWad $wad -Output .\results\doom-live.json
```

Change `$wad` to your file location. The report records its filename, size, and SHA-256, not its contents. This is a stationary camera rotating through eight headings with geometry and textures only. The live script also repeats the headless measurements before each resolution's live tests. Offline PNGs stay under ignored `local/`.

## Cleanup and interpretation

After all benchmark windows have finished:

```powershell
.\scripts\Remove-BenchmarkProfile.ps1
```

This removes only the matching study fragment and its empty directory. Downloaded tools, local source, frame caches, and images remain in ignored `local/` for repeatability. No scheduled tasks, background services, or security changes are installed.

Interpret `CompletedWritesPerSecond` as the loop's successful output operations, not a displayed frame count. The first batch could not collect PresentMon ETW telemetry and could not inspect the Terminal window through the available computer-use inventory. These are outstanding measurement limits, not checks that passed. The offline Doom PNG verifies only the renderer buffer. Consult the [findings](findings-2026-09-10.md) before comparing rates.
