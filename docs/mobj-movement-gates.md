# Movement decisions must compare numeric values

The adopted `Mobj.Run` checked momentum and floor height with PowerShell equality on `Fixed` objects. Two separately allocated instances containing the same integer compare unequal; the type's explicitly callable `op_Equality` method does not make PowerShell `-eq` a numeric comparison. Allocation identity could therefore change whether XY or Z movement ran.

Original id Software [`P_MobjThinker`, lines 395–415](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/p_mobj.c#L395-L415) gates movement on numeric momentum, height and the skull-charge flag. The authored fix reads the existing `Data` integers in those four comparisons. Movement, collision, gravity, state actions and the skull-charge exception otherwise retain their existing implementation.

The defect has an observable consequence beyond wasted calls. `scripts/Test-MobjMovementGates.ps1` creates actual missiles in a real E1M1 world, invokes `Mobj.Run`, and varies whether equal height/zero-momentum values share an object. Six of eight stationary variants incorrectly explode and advance RNG before the fix. Eighteen of 27 assertions fail in `results/mobj-movement-gates-before.json`. All 27 pass in `mobj-movement-gates-after.json`, including nonzero downward movement/explosion, one fixed-point unit upward movement and a zero-momentum skull charge.

These are direct behavioral fixtures, not campaign routes. A grounded stationary missile should advance its ordinary state timer without moving or exploding, irrespective of Fixed allocation identity. The assertions check state, flags, tic countdown, position and RNG, not only a reproduced conditional expression.

The [profiling investigation](simulation-profiling.md) found only thirteen unnecessary Z calls in the 1,200-command prefix, so this fix is not presented as the solution to the performance target. Full original route regressions are a separate gate. Other Fixed comparisons, including sentinel and intersection handling, remain outside this narrow repair and require a semantic audit; no global comparison rewrite was made.

The ordinary-input regressions all pass after the repair:

| Receipt (`results/`) | Verified scope |
| --- | --- |
| `e1m3-movement-gates-regression.json` | All 7,118 commands and 24 original checkpoints, including normal intermission and E1M4 entry at 66 health. |
| `e1m2-movement-gates-regression.json` | All 3,233 commands and 13 original checkpoints through E1M3 entry. |
| `e1m1-movement-gates-regression.json` | Existing 1,747-command normal session through E1M2 entry with inventory preserved. |

These regressions preserve prior route behavior while the direct fixtures prove the previously untested allocation case. They do not qualify other maps/difficulties, live display pacing or the entire fixed-point implementation.

`results/save-state-movement-gates.json` also passes the existing 24-check save fixture: save at command 700, restore, then compare 140 subsequent commands with the unsaved control. Allocation-sensitive behavior warrants this separate restore check; broader save/menu qualification remains governed by the release roadmap.
