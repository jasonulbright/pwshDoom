# Doom in PowerShell: how far can a terminal go?

Working article, September 19, 2026. This is a research prototype with a playable foundation and substantial unfinished qualification. Numbers below belong to named experiments; the release comparison and final conclusions are still open.

## The experiment

The question began with Doom, matrix transforms and a fast desktop: could PowerShell itself run the game and draw it inside a modern terminal? The target was a 320×200 source image, Doom's 35 simulation tics per second, and 60 displayed updates per second. Then came another request: make it look like the Matrix, with Japanese characters. Both questions now have working implementations to investigate.

The language boundary matters. Gameplay, software rendering, terminal encoding, and audio synthesis/mixing algorithms remain PowerShell. Standard .NET collections, file operations, synchronization and Windows playback APIs provide the surrounding machinery. Small compiled declarations expose operating-system APIs. They do not contain a replacement game engine or renderer. The [source lineage](../src/ManagedDoom/ORIGIN.md) records what was adopted and changed.

There was already real prior work. Our dated [survey](existing-implementations.md) identified a PowerShell translation of ManagedDoom, a separate PowerShell ANSI Doom implementation, and compiled terminal ports. This project adopts the attributed GPL PowerShell gameplay foundation and builds its terminal renderer and host around it. A final comparison must refresh those projects and test equivalent workloads. We have no basis for claiming a worldwide first or declaring a universal winner.

## Where the terminal fits

PowerShell runs the program; Windows Terminal presents its output. Terminal's GPU acceleration helps draw and compose the terminal surface. It does not automatically run the PowerShell geometry, enemy thinking or pixel loops on the GPU. Those costs still have to be paid before output reaches the terminal. The [terminal investigation](terminal-architecture.md) separates those responsibilities.

Classic mode packs two vertically adjacent pixels into one upper-half-block character, using separate foreground and background colors. A 320×200 framebuffer therefore needs 320 columns and 100 rows. Font size and display scaling determine its physical size. When a resized test window had only 98 rows, the missing rows exposed a sizing problem, not a fundamental 1080p restriction. The launcher now checks the available grid, centers the image, and pauses when it cannot fit. See the [viewport evidence](viewport.md).

Matrix and AnsiArt consume the same 320×200 scene and produce a deliberately lossy 160×50 character view. Matrix combines green intensity, stable katakana and moving highlights. AnsiArt retains image colors and selects glyphs from brightness and edges. A block HUD preserves more detail where it matters. These are PowerShell encoders; their [recordings and codec checks](character-modes.md) show what they do. Dark menus and small text still need fidelity work.

## Four clocks, four different claims

The simulation clock, completed framebuffer count, console-write count and displayed terminal presentations measure different events. A 60 fps movie adds another clock: it can contain repeated pictures. Finishing 60 writes per second does not prove the user saw 60 distinct game frames.

Early E1M1 runs approached 35 simulation tics and 60 output updates per second. The newer loaded campaign workload is harder. After snapshot, numeric visibility and indexed automap improvements, a fixed 1,200-command E1M3 headless prefix completed at **30.829 tics/sec** and **53.925 completed images/sec**, returning every submitted audio frame. That result remains below the target and has no displayed-FPS claim. The [raw comparisons and scope](automap-discovery-performance.md) are retained.

A separate full E1M3 Matrix recording completed the route and passed 47 integration checks, but averaged **29.983 tics/sec** and **47.965 console writes/sec**. It also recorded 77 pre-final empty-audio-queue observations. Those observations are useful software evidence; they are not measurements of what reached the speakers. The [shutdown and capture investigation](audio-shutdown.md) records the earlier failed run as well as the repair.

## Completing a level changes the test

Loading a map and rendering a room is a useful smoke test. Campaign play exercises keys, doors, floor triggers, lifts, intermission, asset replacement, and inventory carryover. All 36 Ultimate Doom maps pass a short smoke sweep. E1M1 through E1M4 additionally have independently replayed HMP pistol-start normal exits and continuation into the next map. Those separate runs still do not constitute a continuous episode. The [campaign matrix](campaign-matrix.md) keeps that distinction explicit.

E1M5 illustrates why route failures need diagnosis. The first candidate collected armor and a dropped shotgun, then stopped beside a barrel. A fresh fixed-input replay reproduced all 52 recorded samples. Combat had moved the barrel just far enough to obstruct the static plan. A wider path solved that obstacle. The next attempt reached a passage that only opens after a later switch. The following plan followed the key and moving-floor dependencies but exhausted its ammunition in the western area. These were planning failures, not reasons to weaken collision or enemy damage. The [investigation](campaign-e1m5-investigation.md) retains the commands and evidence.

Other campaign failures did reveal engine defects: damaging-floor dispatch and stair-building logic required fixes, each followed by focused checks and route regressions. Keeping both kinds of failure prevents a successful bot run from becoming an excuse to change Doom's rules.

## Audio and the remaining release work

PowerShell synthesizes dry music from the user's IWAD and a separately supplied soundfont. Preparing a reusable loop means rendering continuous periods and checking both synthesizer state and output recurrence. An attractive eight-second opening is insufficient. Seven tracks currently have qualified loops, including the completed 164-second E1M5 loop. The [preparation workflow](music-preparation.md) publishes its catalog only after every requested track passes.

The complete release still needs more campaign routes and endings, continuous play, physical control checks, reference-image comparisons, acoustic review, repeated pacing measurements, display/DPI checks, a second hardware configuration, and clean-checkout packaging. Commercial WADs and generated media remain outside the source repository.

The contribution so far is a working PowerShell terminal implementation with three visual styles and a growing body of reproducible evidence. Choosing it today means wanting this particular language-and-terminal experiment, with its measured costs and unfinished work visible. The final article will judge its advantages against maintained alternatives after the remaining comparisons are actually run.

The first same-state comparison against the adopted PowerShell renderer exposed concrete HUD defects: missing weapon indicators, ignored patch offsets and incorrect number spacing. Those repairs now match the reference HUD across 64 varied states, including cached assets and split rendering. The 3D scene still differs substantially, so this is a bounded correctness improvement rather than a vanilla-fidelity claim. The [rendering investigation](rendering-fidelity.md) retains before/after results and the reference's limitations.
The later E1M4 color-art recording completes all 6,348 commands and matches 22 checkpoints through E1M5. Its seven-track catalog changes scores correctly and all submitted audio frames return. At 34.250 simulation tics and 50.491 console writes per second, it remains below the intended targets; its worst same-world write gap is 215 ms. The [recording evidence](campaign-e1m4.md) retains six queue-empty observations and the audio alignment gaps as well as the successful progression. A cropped viewing excerpt makes the character effect easier to see, while the full original capture remains available locally.
Lighting comparisons also caught a defect in the adopted reference itself: PowerShell object equality skipped Doom's wall-orientation shading. Checking numeric coordinate values against id Software's original algorithm corrected that reference. Our new numeric lighting then reduced E1M1 scene disagreements from roughly 68–78% to 32% across three views, with exact HUDs; that remains far from full pixel equivalence. After repairing a host import dependency, a recorded Classic E1M2 replay passes all 53 integration checks and averages 34.98 simulation ticks and 50.50 terminal writes per second. The [lighting investigation](rendering-fidelity.md) preserves the source-level evidence, failed startup, successful recording, mixed timing results and remaining visual limitations.
