#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# -AllowReplayEnd permits timing analysis of a clean finite input sample that
# exhausted before level completion. The report always retains the actual exit.
param([string]$Prefix="$PSScriptRoot/../results/presentmon-e1m1",[switch]$AllowReplayEnd)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$Prefix=[IO.Path]::GetFullPath($Prefix)
$capture=Get-Content -LiteralPath ($Prefix+'-capture.json') -Raw | ConvertFrom-Json
$game=Get-Content -LiteralPath ($Prefix+'-game.json') -Raw | ConvertFrom-Json
$raw=@(Import-Csv -LiteralPath ($Prefix+'-frames.csv'))
if($capture.Error){throw "PresentMon capture failed: $($capture.Error)"}
if($game.Error){throw "Game run failed: $($game.Error)"}
$acceptedExitReasons=if($AllowReplayEnd){@('LevelComplete','ReplayEnd')}else{@('LevelComplete')}
if($game.ExitReason -notin $acceptedExitReasons){throw "Game exit reason '$($game.ExitReason)' is not accepted for this analysis."}
if($capture.FrameRows -ne $raw.Count -or $capture.QpcFrequency -ne $game.QpcFrequency){throw 'Report row count/clock frequency mismatch.'}
[long]$start=$game.FrameStats[0].EndQpc;[long]$end=$game.FrameStats[-1].EndQpc;[double]$frequency=$capture.QpcFrequency
[double]$seconds=($end-$start)/$frequency
if($seconds -le 0){throw 'At least two timestamp-separated completed writes are needed.'}
$chains=[Collections.Generic.List[object]]::new()
function Get-PacingStats([double[]]$Values) {
    if($null -eq $Values){return $null}
    $stats=Get-SampleStats $Values
    if($null -ne $stats){$sorted=[double[]]$Values.Clone();[Array]::Sort($sorted);$stats.P99=$sorted[[Math]::Max(0,[int][Math]::Ceiling($sorted.Length*.99)-1)]}
    return $stats
}
# Keep contiguous world/screen spans distinct, including repeated visits. The
# global window above still includes every boundary hold between those spans.
$windows=[Collections.Generic.List[object]]::new();$lastKey=$null;$priorFrame=$null
$windowMetadataAvailable=@('Generation','State','Episode','Map','ScreenKind','MenuScreen'|Where-Object {-not $game.FrameStats[0].PSObject.Properties[$_]}).Count -eq 0
foreach($frame in $(if($windowMetadataAvailable){$game.FrameStats}else{@()})){
    $key="$($frame.Generation)|$($frame.State)|$($frame.Episode)|$($frame.Map)|$($frame.ScreenKind)|$($frame.MenuScreen)"
    if($key -cne $lastKey){
        $window=@{Generation=$frame.Generation;State=$frame.State;Episode=$frame.Episode;Map=$frame.Map;ScreenKind=$frame.ScreenKind;MenuScreen=$frame.MenuScreen;
            StartQpc=[long]$frame.EndQpc;EndQpc=[long]$frame.EndQpc;FirstTic=$frame.Tic;LastTic=$frame.Tic;CompletedWrites=0;
            BoundaryGapMs=if($null -ne $priorFrame){($frame.EndQpc-$priorFrame.EndQpc)*1000.0/$frequency}else{$null};SwapChains=[Collections.Generic.List[object]]::new()}
        $windows.Add($window);$lastKey=$key
    }
    $window.EndQpc=[long]$frame.EndQpc;$window.LastTic=$frame.Tic;$window.CompletedWrites++;$priorFrame=$frame
}
function Get-PointIntervals($Points,[string]$Field) {
    $intervals=[Collections.Generic.List[double]]::new()
    for($i=1;$i -lt $Points.Count;$i++){$intervals.Add(($Points[$i].$Field-$Points[$i-1].$Field)*1000.0/$frequency)}
    return ,$intervals.ToArray()
}
foreach($group in ($raw | Group-Object SwapChain)) {
    $points=@(foreach($row in $group.Group) {
        if([int]$row.ProcessId -ne $capture.TerminalPid){throw 'Unexpected process in capture.'}
        [long]$present=$row.PresentStartQpc;[bool]$dropped=[bool]::Parse($row.Dropped);[double]$until=$row.UntilDisplayedMs
        $display=$null
        if(-not $dropped -and [double]::IsFinite($until)){$display=$present+$until*$frequency/1000.0}
        [pscustomobject]@{PresentQpc=$present;DisplayQpc=$display;Dropped=$dropped;UntilDisplayedMs=$until;
            GpuBusyMs=[double]$row.GpuBusyMs;BetweenPresentsMs=[double]$row.BetweenPresentsMs;
            BetweenDisplayChangesMs=[double]$row.BetweenDisplayChangesMs;Mode=[int]$row.PresentMode}
    })
    $points=@($points | Sort-Object PresentQpc)
    $submitted=@($points | Where-Object {$_.PresentQpc -ge $start -and $_.PresentQpc -le $end})
    $displayed=@($points | Where-Object {$null -ne $_.DisplayQpc -and $_.DisplayQpc -ge $start -and $_.DisplayQpc -le $end} | Sort-Object DisplayQpc)
    if($submitted.Count -eq 0 -and $displayed.Count -eq 0){continue}
    $presentIntervals=Get-PointIntervals $submitted 'PresentQpc';$displayIntervals=Get-PointIntervals $displayed 'DisplayQpc'
    # Check SDK decoding/units against independent timestamp differences. Omit
    # the first interval because it can begin before the selected game window.
    $maxPresentDifference=0.0;$maxDisplayDifference=0.0
    for($i=1;$i -lt $submitted.Count;$i++){$maxPresentDifference=[Math]::Max($maxPresentDifference,[Math]::Abs($presentIntervals[$i-1]-$submitted[$i].BetweenPresentsMs))}
    for($i=1;$i -lt $displayed.Count;$i++){$maxDisplayDifference=[Math]::Max($maxDisplayDifference,[Math]::Abs($displayIntervals[$i-1]-$displayed[$i].BetweenDisplayChangesMs))}
    if($maxPresentDifference -gt 0.01 -or $maxDisplayDifference -gt 0.01){throw 'PresentMon timestamp/interval consistency check failed.'}
    $over33=0;$over50=0
    foreach($ms in $displayIntervals){if($ms -gt 1000.0/30){$over33++};if($ms -gt 50){$over50++}}
    $shownSubmissions=@($submitted | Where-Object {$null -ne $_.DisplayQpc})
    $gpuTimes=[double[]]@($submitted | ForEach-Object {$_.GpuBusyMs} | Where-Object {[double]::IsFinite($_)})
    foreach($window in $windows){
        $spanSeconds=($window.EndQpc-$window.StartQpc)/$frequency
        $window.Seconds=$spanSeconds
        $window.ObservedTicProgressPerSecond=if($spanSeconds -gt 0){($window.LastTic-$window.FirstTic)/$spanSeconds}else{$null}
        $wp=@($points | Where-Object {$_.PresentQpc -ge $window.StartQpc -and $_.PresentQpc -le $window.EndQpc})
        $wd=@($points | Where-Object {$null -ne $_.DisplayQpc -and $_.DisplayQpc -ge $window.StartQpc -and $_.DisplayQpc -le $window.EndQpc} | Sort-Object DisplayQpc)
        $window.SwapChains.Add(@{SwapChain=$group.Name;Submitted=$wp.Count;Dropped=@($wp|Where-Object Dropped).Count;DisplayTransitions=$wd.Count;
            DisplayTransitionsPerSecond=if($spanSeconds -gt 0){$wd.Count/$spanSeconds}else{$null};DisplayIntervalMs=(Get-PacingStats (Get-PointIntervals $wd 'DisplayQpc'))})
    }
    $chains.Add(@{SwapChain=$group.Name;AllCapturedRows=$group.Count;SubmittedWithinWindow=$submitted.Count;
        SubmittedPerSecond=$submitted.Count/$seconds;DroppedAmongSubmitted=@($submitted | Where-Object Dropped).Count;
        MissingDisplayTimestampForNonDropped=@($submitted | Where-Object {-not $_.Dropped -and $null -eq $_.DisplayQpc}).Count;
        DisplayTransitionsWithinWindow=$displayed.Count;DisplayedTransitionsPerSecond=$displayed.Count/$seconds;
        PresentIntervalMs=(Get-PacingStats $presentIntervals);DisplayIntervalMs=(Get-PacingStats $displayIntervals);
        DisplayIntervalsOver33_333ms=$over33;DisplayIntervalsOver50ms=$over50;
        PresentToDisplayMs=(Get-SampleStats ([double[]]@($shownSubmissions | ForEach-Object {$_.UntilDisplayedMs})));
        GpuBusyMs=(Get-SampleStats $gpuTimes);PresentModes=@($submitted | Group-Object Mode | ForEach-Object {@{Mode=[int]$_.Name;Count=$_.Count}});
        MaximumPresentIntervalCheckErrorMs=$maxPresentDifference;MaximumDisplayIntervalCheckErrorMs=$maxDisplayDifference})
}
$report=@{AnalyzedUtc=[DateTime]::UtcNow.ToString('o');TerminalPid=$capture.TerminalPid;SwapChains=$chains.ToArray();
    ContiguousWindowMetadataAvailable=$windowMetadataAvailable;
    ContiguousWindows=$windows.ToArray();ContiguousWindowMeaning='First-to-last completed write for each contiguous generation/state/map/screen span. BoundaryGapMs retains the gap since the preceding span. Observed tic progress uses rendered snapshot tics, not an independent simulation start clock. Single-write spans have null rates. Global timing above includes all holds.';
    LaunchToFirstCompletedWriteSeconds=if($capture.PSObject.Properties['LaunchQpc'] -and $capture.LaunchQpc){($start-$capture.LaunchQpc)/$frequency}else{$null};
    TickLatenessMs=if($game.Simulation.PSObject.Properties['TickLatenessSamplesMs']){Get-PacingStats ([double[]]$game.Simulation.TickLatenessSamplesMs)}else{$null};
    MaximumPendingCommands=if($game.PSObject.Properties['MaximumPendingCommands']){$game.MaximumPendingCommands}else{$null};
    WindowStartQpc=$start;WindowEndQpc=$end;WindowSeconds=$seconds;QpcFrequency=$frequency;
    GameCompletedUpdatesPerSecond=$game.CompletedUpdatesPerSecond;GameSimulationTicsPerSecond=$game.TicsPerSecond;
    GameDurationSeconds=$game.DurationSeconds;GameFrames=$game.CompletedFrames;GameTics=$game.SimulationTics;
    GameKills=$game.Simulation.Kills;GameHealth=$game.Simulation.Health;GameExit=$game.ExitReason;
    CaptureSha256=(Get-FileHash -LiteralPath ($Prefix+'-capture.json')).Hash;
    FramesSha256=(Get-FileHash -LiteralPath ($Prefix+'-frames.csv')).Hash;GameSha256=(Get-FileHash -LiteralPath ($Prefix+'-game.json')).Hash;
    Method='Clip to the interval between first and last completed game writes; also report contiguous generation/state/map/screen spans and boundary gaps. Group by swapchain. Present events use PresentStartQpc; display events use PresentStartQpc + UntilDisplayedMs * QpcFrequency / 1000 for non-dropped rows. Rates are event counts / window duration. Intervals use consecutive in-window timestamps, excluding boundary-crossing startup intervals; verify global intervals against native interval metrics. P99 uses the nearest-rank sample percentile.';
    Meaning='Independent ETW-based Terminal presentation/display timing from the installed PresentMon service. This is not an optical measurement or a one-to-one identification of distinct Doom framebuffers. Presentation/display latency here starts at Terminal Present(), not user input or Doom rendering. Windows compositor scheduling and the active desktop affect cadence.'}
$report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath ($Prefix+'-summary.json')
$report | ConvertTo-Json -Depth 7
