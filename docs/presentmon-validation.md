# PresentMon validation, 2026-09-10

**Measured:** the installed PresentMon service reports **59.960 displayed Windows Terminal updates/sec** during the E1M1 replay. The game independently completed 60.005 rendered writes/sec and 34.915 simulation tics/sec. This supplies independent ETW-based presentation evidence, beyond the earlier console-write measurements. It is not an optical measurement or a one-to-one identification of the Doom framebuffer in each presentation.

## Access and method

The user installed Intel PresentMon 2.5.1, including its running shared service and SDK. The standalone ETW console probe in the earlier investigation had failed for lack of privileges. Directly launching the installed capture application also returned a Windows elevation requirement. The documented service API connected successfully from the existing non-elevated PowerShell process, reporting API 3.3.0. No elevation, access-group changes, service reconfiguration, or overlay was used.

Intel documents this client architecture and loading the service's installed `PresentMonAPI2.dll` in its [service/SDK guide](https://github.com/GameTechDev/PresentMon/blob/v2.5.1/README-Service.md). The adapter uses that DLL, with declarations derived from the installed SDK header and runtime metric introspection. C# contains only ABI declarations; collection, marshaling decisions, filtering, and analysis are PowerShell. This external measurement tool is not part of the Doom engine or rendering path.

`scripts/Measure-PresentMonGame.ps1` requires no existing Windows Terminal process, opens a new game window, tracks that process, and drains events for three seconds after the game report appears. The finite capture recorded 2,714 events from PID 11480 and exactly one swapchain. Startup/shutdown events remain in the raw CSV. The game window used a 688×123 grid on the RTX 4070 Ti SUPER; Windows reported 3440×1440 at 165 Hz. Foreground/occlusion was not separately instrumented.

`scripts/Analyze-PresentMonGame.ps1` clips analysis to the interval between the first and last completed game writes: **44.6127496 seconds**. Present events use `PresentStartQpc`. Non-dropped display events use `PresentStartQpc + UntilDisplayedMs × QpcFrequency / 1000`, following Intel's [metric definitions](https://github.com/GameTechDev/PresentMon/blob/v2.5.1/README-CaptureApplication.md#metric-and-csv-column-definitions). Event rates divide in-window counts by that window's duration. Game throughput uses the game's entire 44.6793978-second measured interval, so its denominator differs slightly.

Interval statistics use consecutive timestamps wholly inside the selected window. The first native interval crossed a 12.7-second startup pause and is excluded from interval statistics by this rule; the raw data is preserved. Derived present/display intervals match the native PresentMon interval fields to within `7.2e-15` ms, checking timestamp units and decoding. Runtime field sizes/offsets are validated against the registered query.

## Result

| Measurement | Result |
| --- | ---: |
| Game outcome | E1M1 complete; 5 kills; 75 health; no error |
| Entire game run | 2,681 writes; 1,560 simulation tics |
| Game completed-write rate | 60.005/sec |
| Simulation rate | 34.915 tics/sec |
| Terminal Present calls in selected window | 2,678 / 60.028 per second |
| ETW-reported display transitions in window | 2,675 / **59.960 per second** |
| Dropped among in-window submitted presents | 3 |
| Non-dropped submissions lacking display timestamps | 0 |
| Present interval: median / p95 / max | 16.285 / 22.907 / 63.898 ms |
| Display interval: median / p95 / max | 18.174 / 24.279 / 60.616 ms |
| Display intervals above 33.333 / 50 ms | 27 / 1 |
| Terminal Present-to-display: median / p95 / max | 5.450 / 9.530 / 19.377 ms |

Of the in-window presents, 2,576 used mode 8 (hardware-composed independent flip) and 102 mode 4 (composed flip), as defined by the installed SDK. The median 18.174 ms display interval is consistent with roughly three refresh periods at 165 Hz; this is an inference from the measured cadence and reported refresh rate, not evidence of an engine cap at 55 FPS. An average near 60 can have alternating shorter/longer intervals and occasional stalls.

The 5.450 ms median Present-to-display value starts at Terminal's graphics Present call. It excludes earlier PowerShell simulation, rendering, encoding, and console transport; it is **not input-to-photon latency**. The capture does not map each OS presentation to a unique Doom frame ID. It therefore supports an approximately 60 Hz displayed Terminal update rate with the game running, while leaving frame identity and physical keyboard latency unverified.

## Evidence and reproduction

- `results/presentmon-service-probe.json`: successful API connection, version and DLL hash.
- `results/presentmon-e1m1-capture.json`: process, query layout, timestamps, DLL hash and capture outcome.
- `results/presentmon-e1m1-frames.csv`: all 2,714 frame events, including startup/shutdown.
- `results/presentmon-e1m1-game.json`: the simultaneous full game report.
- `results/presentmon-e1m1-summary.json`: analysis and hashes of the raw evidence.

With the user's PresentMon service/SDK installed at their default paths, run from a **non-Terminal automation host**, with other Windows Terminal processes closed. This isolation requirement prevents attributing another tab/window's presents to the game. The harness refuses an ambiguous existing Terminal process rather than closing it.

```powershell
.\scripts\Measure-PresentMonGame.ps1 -OutputPrefix .\local\my-presentmon-run
.\scripts\Analyze-PresentMonGame.ps1 -Prefix .\local\my-presentmon-run
```

Choose a fresh prefix to preserve previous captures. The default replay requires the previously validated Ultimate Doom IWAD. The adapter stops only its own tracking session, frees its query/session handles, and leaves the installed shared service running. The game retains its finite duration and owned-worker cleanup. The native measurement dependency adds instrumentation overhead; one successful capture is not a statistical estimate of that overhead.

## Subsequent viewport comparison

The original results above precede the centered viewport and optional status rows. Three captures of the updated runtime retained about 60 completed image writes/sec: two 6-point/windowed launches measured 57.604 and 57.664 displayed updates/sec, while a 6-point/maximized launch measured 59.733/sec. The windowed captures include initial dropped presents that are not removed from the analysis. See [viewport comparison](viewport.md#live-terminal-and-presentmon-comparison) for the parameters, raw evidence, and limits. The collector now accepts explicit `-FontSize` and `-Maximized` options and records them in new captures.
