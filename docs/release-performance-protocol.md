# Ultimate Doom release pacing protocol

Frozen September 29, 2026, before the new candidate's live comparisons. These are proposed release acceptance thresholds, not claims that the build passes. Keep every run and failure. Change thresholds only in a new documented protocol revision.

## Matrix

Pin source, IWAD, input/save fixtures, music catalog and soundfont hashes, exact executable versions, CPU/RAM/GPU/display/refresh/DPI and Terminal font/grid. First machine is the installed Windows test host inventoried in `results/environment.json` and `results/presentmon-display-config.json`; refresh any changed components. A second configuration and actual 1920×1080/DPI tests remain required for portability claims.

Use Classic, Matrix/Katakana and AnsiArt/Katakana, 320×200 source pixels, 16 workers, truecolor Pairs and Strips as the primary configuration. Include maximized and windowed trials at matched physical image size. Keep alternative worker counts, ASCII, Ansi256 and Batch as separately named experiments. No omitted actors, skipped simulation tics, resolution reductions or hidden startup exclusions.

Workloads: an ordinary-input E1M1 combat/door/exit route; a dense E3M6 combat input stream; moving lifts/doors/stairs; palettes/invisibility and automap; menus/save/load/new-game; a secret-map return and finale. Artificial save fixtures qualify their specific effects, not map navigation. Every workload needs three sequential repeats with no concurrent qualification/export work. Pair alternatives A-B-B-A; include all windows and initial runs. Recordings are separate runs.

## Thresholds and measurement boundaries

| Metric | Primary acceptance threshold |
| --- | --- |
| Simulation | At least 34.9 active tics/sec; zero discarded commands/tics; p99 start lateness ≤57.2 ms, max ≤250 ms; backlog ≤4 commands |
| Display | At least 59 display transitions/sec on the main game swapchain, p95 gap ≤25 ms, p99 ≤50 ms, max ≤250 ms; ≤1% dropped presents |
| Frame identity | Independently distinguish game-frame content from Terminal chrome/repeated presents before claiming 60 distinct displayed game frames/sec |
| Startup | First interactive frame ≤60 sec, measured from launch; report cold and repeated startup separately |
| Session load | Report every asset, save/load and menu hold separately; no hold silently excluded from wall-clock behavior |
| Memory | Report sampled private/working-set totals for host, simulation, workers and Terminal; no allocation failure; primary host budget ≤8 GiB for game processes |
| CPU | Report per-process cumulative CPU and interval deltas; compare against logical-core capacity, without a universal CPU budget |
| Audio | Zero active software starvation/rebuffer events, zero packet losses, clean shutdown; separate shutdown-empty polls; report device-buffer latency and canceled/reset tails |

The numerical pacing thresholds permit ordinary jitter around the 35/60 goals; they do not relax frame identity, campaign completion or audio evidence. Terminal completion gaps are always reported separately from display transitions. A missing counter is unqualified, never a pass. Hardware/headless updates and encoded movie frame rate cannot substitute for display evidence.

`Measure-PresentMonGame.ps1` now accepts sound, a prepared catalog, save/settings roots, session schedules, worker count and duration. It retains startup/cleanup events and samples only the attributed game/Terminal processes once per second. Sampled memory is a lower bound on peak usage. PresentMon cannot identify game content by itself. Its analysis reports all swapchains and both global and per-world windows; retain raw captures.

Publication requires the full roadmap gates. This protocol supplies reproducible pacing decisions while physical input, acoustic review, campaign routes and reference-rendering comparisons remain separate evidence.
