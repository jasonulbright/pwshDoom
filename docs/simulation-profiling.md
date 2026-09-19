# Gameplay stage investigation

Measured 2026-09-19 after shared snapshot packing. The loaded E1M3 host still spent 26.929 ms per gameplay update and ran at 23.765 ticks/sec on its 1,200-command prefix. This investigation isolates gameplay before changing its hot paths.

`scripts/Measure-SimulationStages.ps1` builds a unique local bundle. Diagnostic mode adds timers only to that owned copy; production source and the live host do not acquire profiling overhead. Timed runs are sequential, without another study workload. Every command and cold sample is retained. All four original prefix checkpoints and the additional final selected-state hash agree across all four runs; see `results/simulation-profiling-audit.json`. These are selected-state checks, not complete vanilla compatibility.

| Stage-profiled mean per update | Milliseconds |
| --- | ---: |
| Entire Game.Update | 21.372 |
| Thinkers.Run | 18.316 |
| PlayerThink | 1.494 |
| Thinker interpolation bookkeeping | 0.746 |
| Sector interpolation bookkeeping | 0.627 |
| Specials | 0.051 |
| Automap | 0.042 |
| Status bar | 0.039 |

The uninstrumented baseline averages 21.217 ms. Receipts: `results/simulation-stages-profile-first.json` and `simulation-stages-baseline-first.json`; their exact harness is retained as `simulation-stages-first-harness.ps1`. Startup/world construction precedes the measured replay commands. These simulation-only timings are not loaded-host costs or displayed FPS.

The first actor profile records 1,666 XY and 637 Z movement calls. None of the XY calls and thirteen Z calls were unnecessary under numeric momentum/height predicates. Movement averages 1.897/0.024 ms per tick. This rules out redundant movement as the main measured bottleneck, while exposing a separate [numeric comparison defect](mobj-movement-gates.md).

The second actor profile also instruments state-action dispatch and `CheckSight`, retaining the existing control flow and return values. It records 9,339 state actions and 15,841 sight checks. Inclusive means are 16.190 ms for state actions and 13.902 ms for sight checks, versus 23.111 ms for the whole update. **These intervals overlap and must not be added.** The deeper instrumentation has visible overhead. Earlier harness versions remain alongside their receipts.

Sight checks are the next performance target. `VisibilityCheck` traverses the BSP and tests div-line sides using repeated Fixed wrapper arithmetic. Investigate numeric operations that preserve signed 32-bit wrapping, endpoint/on-line behavior, traversal order, dynamic sector heights, valid-count mutations and slope clipping. Compare actual side/sight results, original route checkpoints and loaded-host timings before adopting a replacement. Do not skip sleeping monsters, reduce sight-check frequency, suppress actors or replace the PowerShell algorithms with a compiled helper.

Raw receipts: `results/simulation-actors-first.json`, `simulation-actors-second.json`. Instrumented bundle locations and hashes are recorded in each result and remain under ignored `local/`. The current harness can reproduce baseline, stage and deeper actor modes with fresh output paths.
