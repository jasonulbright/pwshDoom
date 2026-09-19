# Sending fewer truecolor instructions

September 19, 2026. This is a Classic encoding experiment under the unchanged Ultimate Doom release goal.

Classic draws two pixels per upper-half-block character. Its original `Pairs` encoder emits both foreground and background colors whenever the pair changes. `ColorState` instead emits just one component when the other remains unchanged. Both modes emit the same glyph at every position. Every strip begins with unknown color state and explicitly sets both colors for its first cell; there is no dependence on previous frames, a previous worker, or an undiscarded resize frame. Source pixels, resolution, palettes, gameplay and character-style algorithms are unchanged.

`src/AnsiColorState.ps1` contains the PowerShell algorithm and its small foreground/background string caches. Standard .NET UTF-8 conversion still produces the output bytes. `-AnsiEncoding ColorState` selects it for Classic through the normal launcher; `Pairs` remains the default while qualification is in progress. Matrix and AnsiArt ignore this Classic-only selection and retain their current encoders. `-TerminalOutput` independently controls write batching.

## Correctness and bounded encoding measurements

The [first receipt](../results/ansi-color-state-first.json) passes 13 cases. A separate strict decoder consumes the entire ANSI stream, handles individual SGR color instructions, rejects unrecognized sequences and repeated painting, and checks each RGB pixel against the source palette. Coverage includes odd dimensions, one/three/seven uneven strips, a nonzero viewport origin, explicit foreground-only/background-only transitions, and six actual E1M1/E1M3 views through sixteen strips. It also verifies that source pixels are unchanged and output bytes never increase in those cases. These checks establish encoding semantics for the supplied fixtures; they do not establish original-Doom rasterization fidelity.

After correctness, four alternating-order rounds retain 24 serial encoding samples per version, including UTF-8 conversion and stream assembly. Both functions have already run during validation; setup/rendering is outside timing and no timed sample is excluded. Baseline/candidate mean is 36.474/31.125 ms, median 35.982/30.036 ms and p95 38.489/33.823 ms. Total sampled output decreases from 16,147,500 to 13,406,496 bytes, approximately 17%. This is an isolated serial encoder comparison, not sixteen-worker live throughput or displayed FPS.

The actual seven-worker Classic test additionally matches 320,000 pixels and 35 encoded strips across five headings against serial rendering/encoding. A Matrix/katakana worker test checks that selecting this Classic option preserves its character path.

## Declared live comparison

Record four complete E1M2 ordinary-input routes through intermission into E1M3 in order Pairs/ColorState/ColorState/Pairs. Keep Strips output, Classic, sixteen workers, the same maximized font/viewport, exact replay and seven-track audio catalog throughout. No other study experiment runs concurrently. Freeze the game/capture sources through all runs. Each recording must independently retain all commands, checkpoints, inventory transitions and audio frames before it enters the comparison. Preserve original footage and report source/media hashes.

```powershell
./scripts/Invoke-TerminalOutputTrial.ps1 -Mode Strips -AnsiEncoding Pairs -Name ansi-pairs-first
./scripts/Invoke-TerminalOutputTrial.ps1 -Mode Strips -AnsiEncoding ColorState -Name ansi-state-first
./scripts/Invoke-TerminalOutputTrial.ps1 -Mode Strips -AnsiEncoding ColorState -Name ansi-state-second
./scripts/Invoke-TerminalOutputTrial.ps1 -Mode Strips -AnsiEncoding Pairs -Name ansi-pairs-second
./scripts/Compare-TerminalOutputTrials.ps1 -Dimension Encoding -Names ansi-pairs-first,ansi-state-first,ansi-state-second,ansi-pairs-second -Output results/ansi-state-four-trials.json
```

Use fresh names/paths for subsequent runs. Report output bytes, per-frame maximum worker encoding times, host output timing, image completion rate, same-world and all-frame gaps, simulation rate and audio queue observations. Active desktop conditions remain an uncontrolled source of variation. No whole-game speedup follows from the serial encoder result alone.

## Recorded results and decision

All four trials pass 65 integration checks apiece, including all 3,233 commands, 13 checkpoints, inventory-preserving E1M3 entry, exact matching synthesized PCM and return of all 4,073,580 audio frames. The [comparison](../results/ansi-state-four-trials.json) passes 160 source/workload/configuration/timing checks. No game or capture source changed between the runs. Full movies decode; a frame at 60 seconds in each movie was inspected and shows centered Classic gameplay/HUD without visible external occlusion. Startup offsets differ, so those screenshots are not comparisons of the same world state.

| Order | Encoder | Tics/sec | Image writes/sec | Mean bytes/image | Level output mean ms | Same-world gap p95 ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | Pairs | 34.371 | 35.190 | 620,625 | 21.537 | 38.838 |
| 2 | ColorState | 34.470 | 39.513 | 526,202 | 18.670 | 34.264 |
| 3 | ColorState | 34.743 | 42.298 | 525,570 | 17.257 | 31.880 |
| 4 | Pairs | 34.977 | 54.612 | 614,145 | 11.670 | 24.955 |

The candidate cuts approximately 15% of average live output bytes in these captures. Exact same-frame savings come from the separate static-fixture comparison; live runs sample different interpolated poses and must not be described as identical frame sequences. Whole-game rate improves approximately 12.3% in the first pair and is approximately 22.5% lower than the baseline in the reversed pair. This is not a consistent speedup. Keep **Pairs as default** and retain ColorState as the tested lower-bandwidth option.

Timing varies beyond encoding: the mean of each level frame's slowest renderer-worker duration is 16.202, 14.534, 13.756 and 10.543 ms in order, even though the rasterization code is unchanged. The corresponding maximum-worker encoding means are 5.104, 4.029, 3.839 and 3.215 ms. Scheduling/background load, focus, clocks and temperatures were not independently logged or controlled, and the sample mixes also differ with frame timing. Do not assign the temporal trend a cause. Another uninstrumented long ABBA sequence would not resolve it; future full-game performance comparisons need better condition telemetry or closer time pairing. Continue remaining gameplay/fidelity work in parallel with that investigation.

Audio has 6/6/7/2 software queue-empty observations and 13,530/10,449/1,583/1,156 interior alignment-fill frames respectively. All buffers return and API discontinuity counts remain zero, but neither fact establishes uninterrupted acoustic output. The all-frame gap reports include multi-second level handoffs. No stable 35-tic/60-display guarantee follows from these runs. Raw recordings, PCM and reviewed screenshots remain in ignored `local/recordings`, with portable evidence and hashes in `results/`.
