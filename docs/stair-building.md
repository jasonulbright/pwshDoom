# E1M3 exit-stair correction

Measured 2026-09-12. The sixteenth HMP E1M3 input candidate survives the upper walkway, obtains the blue key, and reaches the exit area with 58 health and 43 kills. Crossing the stair trigger then throws in `SectorAction.BuildStairs`: the target has no `Number` property. The receipt retains 6,261 attempted commands, including the throwing update: the driver appends its input before calling Game.Update. This run is a retained failure, not a completion.

The adopted guard was:

```powershell
if (($sector.Lines[$i]).Flags -band [LineFlags]::TwoSided -eq 0)
```

PowerShell binds the comparison before the bitwise operation here. For example, `1 -band 4 -eq 0` produces zero rather than the intended true comparison. The guard therefore fails to skip one-sided boundaries and accesses an absent sector during traversal. Parenthesizing the bitwise result restores the intended condition:

```powershell
if ((($sector.Lines[$i]).Flags -band [LineFlags]::TwoSided) -eq 0)
```

Original id Software [EV_BuildStairs](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/p_floor.c#L431-L529) skips boundaries without the two-sided flag, then follows their front-to-back sector orientation and matching floor texture. The repair changes only the guard; it does not change step sizes, speed, ordering or the handling of active floors.

`scripts/Test-StairBuild.ps1` loads the actual installed E1M3 map and invokes its tag-14 staircase as an isolated fixture. It checks both Build8 and Turbo16, ten sectors' intended destinations and speeds, rejection of an active retrigger, and bounded execution of their real floor thinkers to their final heights with ownership released. The fixture directly invokes the special and is not campaign completion evidence.

| Receipt | Result |
| --- | --- |
| `results/e1m3-route-sixteenth.json` | Ordinary-input route exposes the exception after blue-key collection. |
| `results/stair-build-before.json` | Both stair types reproduce the same exception in the unchanged handler. |
| `results/stair-build-after.json` | Same fixture after the parenthesis repair: all 86 checks pass. |

The existing E1M1 continuation passes again: 1,747 commands and all recorded transitions match the prior session. E1M2 again passes 87 trace samples, 3,233 commands, 13 checkpoints and inventory-preserving E1M3 entry. Receipts are `results/e1m1-session-stair-build.json` and `results/e1m2-qualified-stair-build.json`; source/report pins are in `results/stair-build-regression-provenance.json`. The full [E1M3 normal route](campaign-e1m3.md) now completes and independently passes 198 trace samples, 7,118 commands and 24 checkpoints through E1M4 entry. Earlier recordings retain their original source identity. No new live recording or performance claim follows from these headless checks.
