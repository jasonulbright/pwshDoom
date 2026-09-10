# Window sizing and resize behavior

The image remains 320×200 pixels. The current ANSI encoder puts two independently colored vertical pixels in each upper-half-block character, so it needs **320 columns × 100 rows**. The previous 102-row minimum included two diagnostic text rows. Those rows are now optional with `-Diagnostics`.

The old image started in the upper-left corner, leaving all surplus space below and to the right. The host now centers the image, checks the terminal grid every 100 ms, and clears/recenters after a size change. It does not stretch the image to fill an arbitrary window. A render encoded for an old placement is discarded. A resize between grid checks can still cause a transient misplaced write, corrected after detection.

The user clarified that they resized the earlier failed window to 98 rows. The saved `game-terminal-input-window-too-short.json` accurately reports that grid, but the earlier attribution to a fresh-window sizing problem was unsupported. That observation does not establish a monitor resolution requirement or a Terminal launcher bug.

## Font size and 1080p

Terminal's font size is in points. Physical cell size depends on the font, DPI scaling, and zoom; available rows also depend on window chrome and size. A character-grid limit is therefore not a minimum monitor resolution. The launcher now uses 6 points instead of 7, and maximization is optional. These settings apply to the game's separate profile. [Microsoft profile appearance reference](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-appearance).

```powershell
# Default: 6 points, windowed, no diagnostic rows
.\Start-Doom.ps1

# Smaller physical image when more rows need to fit
.\Start-Doom.ps1 -FontSize 5

# Larger physical image on a display with room for it
.\Start-Doom.ps1 -FontSize 8 -Maximized
```

`-Here` keeps the current tab's font and window. `-FontSize` and `-Maximized` affect only a newly launched window. `wt --size` requests columns and rows; the actual grid is measured and recorded rather than assumed from the request. [Microsoft command-line reference](https://learn.microsoft.com/en-us/windows/terminal/command-line-arguments).

For example, cells 5 physical pixels wide and 9 high would make the image 1600×900 physical pixels, before window chrome. This is sizing arithmetic, not a measured font metric or a claim that 6 points always produces those cells. A 1080p display is not excluded by the design, but no physical 1080p monitor has been tested here. DPI/zoom can require a smaller font. The framebuffer never silently drops rows or reduces resolution to fit.

## When the window is too small

The game pauses and shows the measured grid plus resize guidance. It continues reading input so Escape can quit. Once the window fits, rendering and the active game clock resume. No new simulation commands are issued during the pause; commands already issued can finish. The simulation timing reference is adjusted so paused time does not produce a burst of catch-up tics.

Session reports include `ViewportChanges`, `ViewportPauseCount`, `ViewportPausedSeconds`, and `DiscardedResizeFrames`. `DurationSeconds` and the existing throughput fields count active time. `WallDurationSeconds` and `CompletedUpdatesPerWallSecond` include pauses. Finite experiments still stop after the requested wall time. PresentMon's independent display timeline includes any pauses in its measurement window.

## Verification

- `scripts/Test-Viewport.ps1`: nine layout cases, including 320×100, 589×98, large windows, and diagnostic rows; three narrow pause-message cases. A five-second integration run uses real simulation/render workers with synthetic dimensions: undersized startup → exact fit → enlargement → shrink → restore. Both pauses preserve issued-command count and active time. Raw results are `results/viewport-tests.json` and `results/viewport-resize-session.json`.
- `scripts/Test-AnsiStrips.ps1`: 24 independently decoded pixel round trips across two origins, both color modes, odd dimensions, and uneven strips.
- `scripts/Test-RenderPartitions.ps1`: 320,000 exact pixels across five E1M1 views and seven uneven process strips, with a translated cursor origin checked in each worker's output. Reference comparison uses the saved pre-cast renderer. This establishes positioning/partition correctness, not vanilla pixel equivalence.

The automated resize sequence is explicitly headless and synthetic; it cannot be enabled in a visible game. Physical drag-resizing has not been automated or visually verified by the agent.

## Live Terminal and PresentMon comparison

All three runs used 16 workers, skill 3/E1M1, the same input-only route and IWAD, a 6-point game profile, and the installed PresentMon service. Each completed 1,560 tics with five kills and 75 health; none recorded a resize or viewport pause. These captures include the whole first-to-last completed-write window, without removing initial display delays.

| Launch | Actual grid | Image writes/sec | Simulation tics/sec | Display transitions/sec | Dropped presents |
| --- | --- | ---: | ---: | ---: | ---: |
| Windowed | 582×156 | 59.997 | 34.911 | 57.604 | 101 |
| Windowed repeat | 582×156 | 60.010 | 34.918 | 57.664 | 102 |
| Maximized | 688×151 | 59.997 | 34.924 | 59.733 | 6 |

The windowed drops cluster in the first three seconds; in the repeat all 102 are composed-flip mode 4 presents. The first run has a 2,751.539 ms gap between display transitions; the repeat has no interval above 50 ms *between its displayed events*, but that statistic excludes the initial period before the first displayed event. Its full-window rate still counts that lost time. The maximized run's display intervals have a 24.266 ms p95 and 54.552 ms maximum. The display timing difference warrants further investigation; these three observations do not establish its cause. Maximization is an available option with better observed presentation in this comparison.

Raw capture/game/CSV/summary files use prefixes `results/presentmon-viewport-e1m1`, `results/presentmon-viewport-repeat`, and `results/presentmon-viewport-maximized`. Reproduce the comparison with a fresh output prefix, adding `-Maximized` to `scripts/Measure-PresentMonGame.ps1` for that condition. `results/viewport-sources.json` records the 221 runtime file hashes shared by all three captures; `viewport-validation.json` records the final 55-file parse check, ANSI checks, capture outcomes, and absence of remaining owned game processes. Earlier captures and their source manifests remain historical evidence.
