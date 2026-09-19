# Damage, pickup and power-up palettes

September 19, 2026. Gameplay previously chose a palette in the adopted renderer,
but our terminal path carried only PLAYPAL's base colors. Damage, item bonuses,
berserk and radiation-suit tints therefore did not reach terminal output. This
is distinct from fixed COLORMAP effects such as invulnerability.

## Implementation and scope

Reuse the attributed PowerShell `Renderer.GetPaletteNumber` selector, checked
against id Software's [ST_doPaletteStuff](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/st_stuff.c).
Damage and berserk share the red-palette branch; bonus tint follows, then the
radiation-suit timer/blink branch. The selected index remains discrete during
camera/geometry interpolation. We do not change damage, pickup, or power rules.

NumericV3 carries selection in header slot45. Disposable assets-v2 carries the
complete user-supplied PLAYPAL bytes. The simulation header carries the same
selection for indexed automap screens. Workers encode the complete selected
image, including HUD colors. This project's full-screen menus deliberately use
palette0 for readability; intermission/finale also return to palette0. The
menu choice is a presentation difference, not a claim of original-menu parity.

Classic uses uncorrected RGB from the selected PLAYPAL palette. AnsiArt applies
its existing color/brightness mapping to those RGB values. Matrix applies its
existing green mapping to their luminance: damage is a brightness/contrast
change rather than a literal red screen. These character representations are
intentional approximations. Gamma controls and original-executable visual
equivalence remain separate, unfinished work.

Each worker prepares fourteen small codec contexts. Pair-cell strings are
created only when encountered, then reused. This avoids eagerly constructing
fourteen complete65,536-string tables, but retains up to65,536 pair references
per palette per worker; it is bounded caching, not negligible memory. No lazy
context is passed to the standalone ANSI/Sixel encoders that require eager
pair/definition tables. The eager default remains available for independent
comparisons. Asset reload retains codec caches only when all PLAYPAL bytes
match; a changed palette bank rebuilds them.

Frame and worker telemetry retain PaletteNumber. Periodic indexed frame
captures now have a matching `.bin.palette.bin` companion; `local/palette.bin`
matches the final `local/game-frame.bin`. Those indexed artifacts represent
the source colors, not a rendered Matrix/AnsiArt screenshot.

## Evidence

- `results/palette-presentation-first.json`:280 checks. Explicit selector
  boundaries/precedence; real object/direct packet equality; interpolation;
  every RGB entry in all14 palettes; exhaustive65,536 Classic color pairs per
  palette; character scene/HUD/menu/map comparisons against eager tables.
- `results/palette-transport-first.json`:8 wire checks.
- `results/palette-checkpoint-first.json`:18 hash-compatibility and negative
  controls. Current V3 hashes cover palette selection; a separate named V2 hash
  permits comparison to earlier invisibility fixtures. Older evidence cannot
  retroactively verify a field it never contained. Missing/wrong compatibility
  hashes are rejected. Historical Schema1 bytes remain unchanged.
- `results/palette-replay-format-first.json`:58 replay-format checks.
- `results/palette-workers-{classic,matrix,ansiart,colorstate}-first.json`:
  each actual seven-process check compares320,000 pixels and35 encoded strips.
  Five palette selections accompany uneven strip boundaries; the first three
  also retain explicit invisibility/Spectre fixtures.
- `results/palette-direct-allmaps-first.json`:336 exact byte comparisons over
  all36 map starts and the complete3,233-command E1M2 route, preserving13 old
  checkpoints. No new campaign completion follows from this regression.
- `results/palette-headless-audit-first.json`:24 actual-host checks,700 unchanged
  commands,52 independently generated V3 checkpoints, four exact saves and
  eight automap controls. Every presented fixture frame matches the independently
  simulated palette/map state. All882,000 submitted audio frames return.

The explicit fixture loads separate damage, bonus, late-berserk and radiation
timer states into E1M1. Each advances through normal idle updates to a living
base-palette restoration, opening and closing the automap while the effect is
active. This isolates presentation and save/transport behavior; it is not
ordinary pickup/damage acquisition or campaign-route evidence. Initial
headless worker working set is5,239,996,416 bytes across16 processes, excluding
simulation, coordinator and Terminal. It is a workload observation, not a
matched before/after memory comparison.

## Recorded validation

Classic, Matrix and AnsiArt each pass55 capture/integration checks, including all52
checkpoints, every presented frame's independently predicted palette/map state,
complete input, all882,000 returned audio frames, unchanged pinned sources,
movie decoding and owned-process/window cleanup. Their five extracted frames
were inspected: damage, bonus-colored automap, late berserk, radiation and base
restoration are present. Matrix remains green and loses substantial contrast in
the strongest damage tint; readability still needs human play review.

| Recorded mode | Game tics/sec | Image writes/sec | Same-world p95 / max gap | Worker working set |
| --- | ---: | ---: | ---: | ---: |
| Classic | 34.940 | 58.999 | 25.329 / 508.240 ms | 5,216,206,848 bytes |
| Matrix | 34.948 | 59.810 | 23.216 / 571.803 ms | 5,426,847,744 bytes |
| AnsiArt (candidate recorder, first) | 34.937 | 55.051 | 27.284 / 550.397 ms | 5,400,592,384 bytes |
| AnsiArt (candidate recorder, second) | 22.898 | 25.384 | 113.792 / 714.486 ms | 3,934,695,424 bytes |

All-gap maxima including save handoffs are2.888/3.014 seconds. Both have three
software audio queue-empty observations; interior capture alignment fills
1,152/1,158 frames. These are recorded isolated-effect workloads, not a causal
speedup, uninterrupted audio or60-display certification. Receipts are
`results/palette-{classic,matrix}-third-{recorded,timing,review}.json`; movies
remain in `local/recordings/palette-{classic,matrix}-third-av.mp4`.

The first candidate-recorder AnsiArt run passes all55 checks and full movie
decoding. All five extracted frames were inspected: red damage, gold automap,
late berserk, radiation and base restoration are present. Strong damage greatly
reduces scene/HUD contrast; large surrounding margins remain. The run retains
three audio queue-empty observations,1,114 internal alignment-fill frames and
a3.010-second maximum gap including save handoffs. No60-display or acoustic
continuity claim follows. Receipts: `results/palette-ansiart-pinned-first-{recorded,timing,review}.json`;
movie: `local/recordings/palette-ansiart-pinned-first-av.mp4`.

The already-started repeat also passes55 integrity checks, but is substantially
slower:22.898tics/25.384writes per active second,63 queue-empty observations,
66,025 interior alignment-fill frames and5.895seconds maximum gap including
handoffs. Retain `results/palette-ansiart-pinned-second-{recorded,timing}.json`
and its original movie. Correct state/input/media accounting is not a pacing
or playability pass. The cause of the run-to-run slowdown is not established.

Two earlier captures (Classic second, AnsiArt third) crashed in external FFmpeg
after receiving q; their failed media/logs remain. Both original and candidate
recorders pass the subsequent short lifecycle trials, which do not reproduce
the fault. The candidate pins the capture library until process exit, but a
causal fix is unproven. See [capture disposition](capture-shutdown.md). This
recording-tool issue no longer blocks gameplay or rendering work.

The first Classic recording completes all700 commands at an actual688x151 grid,
but its audit rejects missing expected transition metadata in the new fixture.
Preserve the failed receipt and original media. A preliminary font-size diagnosis
was incorrect: the recorded grid fitted Classic and the host reached ReplayEnd.
Add the independently known four save-load transitions to the fixture; use
explicit style-appropriate font sizes in subsequent invocations.

The additional headless menu test completes the same700 commands and52
checkpoints while opening/resuming the menu during an active effect. Its menu
frames select palette0; gameplay resumes its correct state. This is a control
and presentation regression, not a physical keyboard playthrough.

## Reproduce

Use fresh paths; WADs, saves and movies remain user-local and ignored by Git.

```powershell
./scripts/Test-PalettePresentation.ps1 -Output local/my-palette-checks.json
./scripts/New-PaletteRecordingFixture.ps1 -Output local/my-palette-replay.json -SaveRoot local/my-palette-saves
./scripts/Record-DoomReplay.ps1 -Style Classic -FontSize 6 -Maximized `
  -Replay local/my-palette-replay.json -SaveRoot local/my-palette-saves `
  -OutputPrefix local/recordings/my-palette-classic -RecordInput -CaptureAudio `
  -Ffmpeg local/tools/capture-build/FFmpeg-n9.0.1/ffmpeg.exe `
  -MediaFfmpeg local/tools/ffmpeg/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe `
  -StartupTimeoutSeconds 180 -Seconds 100 -ExpectedExit ReplayEnd
./scripts/Test-PaletteSession.ps1 -Replay local/my-palette-replay.json `
  -Prefix local/recordings/my-palette-classic -Output local/my-palette-audit.json
```

Use Matrix/AnsiArt with12-point MS Gothic and Katakana for their established
character view. Record each live effect run. Movie cadence and console writes
do not prove distinct displayed game frames or acoustic continuity.
