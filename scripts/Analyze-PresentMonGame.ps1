#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Prefix="$PSScriptRoot/../results/presentmon-e1m1")
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$Prefix=[IO.Path]::GetFullPath($Prefix)
$capture=Get-Content -LiteralPath ($Prefix+'-capture.json') -Raw | ConvertFrom-Json
$game=Get-Content -LiteralPath ($Prefix+'-game.json') -Raw | ConvertFrom-Json
$raw=@(Import-Csv -LiteralPath ($Prefix+'-frames.csv'))
if($capture.Error -or $game.Error -or $game.ExitReason -ne 'LevelComplete'){throw 'Capture or replay did not complete successfully.'}
if($capture.FrameRows -ne $raw.Count -or $capture.QpcFrequency -ne $game.QpcFrequency){throw 'Report row count/clock frequency mismatch.'}
[long]$start=$game.FrameStats[0].EndQpc;[long]$end=$game.FrameStats[-1].EndQpc;[double]$frequency=$capture.QpcFrequency
[double]$seconds=($end-$start)/$frequency
$chains=[Collections.Generic.List[object]]::new()
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
    $chains.Add(@{SwapChain=$group.Name;AllCapturedRows=$group.Count;SubmittedWithinWindow=$submitted.Count;
        SubmittedPerSecond=$submitted.Count/$seconds;DroppedAmongSubmitted=@($submitted | Where-Object Dropped).Count;
        MissingDisplayTimestampForNonDropped=@($submitted | Where-Object {-not $_.Dropped -and $null -eq $_.DisplayQpc}).Count;
        DisplayTransitionsWithinWindow=$displayed.Count;DisplayedTransitionsPerSecond=$displayed.Count/$seconds;
        PresentIntervalMs=(Get-SampleStats $presentIntervals);DisplayIntervalMs=(Get-SampleStats $displayIntervals);
        DisplayIntervalsOver33_333ms=$over33;DisplayIntervalsOver50ms=$over50;
        PresentToDisplayMs=(Get-SampleStats ([double[]]@($shownSubmissions | ForEach-Object {$_.UntilDisplayedMs})));
        GpuBusyMs=(Get-SampleStats $gpuTimes);PresentModes=@($submitted | Group-Object Mode | ForEach-Object {@{Mode=[int]$_.Name;Count=$_.Count}});
        MaximumPresentIntervalCheckErrorMs=$maxPresentDifference;MaximumDisplayIntervalCheckErrorMs=$maxDisplayDifference})
}
$report=@{AnalyzedUtc=[DateTime]::UtcNow.ToString('o');TerminalPid=$capture.TerminalPid;SwapChains=$chains.ToArray();
    WindowStartQpc=$start;WindowEndQpc=$end;WindowSeconds=$seconds;QpcFrequency=$frequency;
    GameCompletedUpdatesPerSecond=$game.CompletedUpdatesPerSecond;GameSimulationTicsPerSecond=$game.TicsPerSecond;
    GameDurationSeconds=$game.DurationSeconds;GameFrames=$game.CompletedFrames;GameTics=$game.SimulationTics;
    GameKills=$game.Simulation.Kills;GameHealth=$game.Simulation.Health;GameExit=$game.ExitReason;
    CaptureSha256=(Get-FileHash -LiteralPath ($Prefix+'-capture.json')).Hash;
    FramesSha256=(Get-FileHash -LiteralPath ($Prefix+'-frames.csv')).Hash;GameSha256=(Get-FileHash -LiteralPath ($Prefix+'-game.json')).Hash;
    Method='Clip to the interval between first and last completed game writes. Group by swapchain. Present events use PresentStartQpc; display events use PresentStartQpc + UntilDisplayedMs * QpcFrequency / 1000 for non-dropped rows. Rates are event counts / window duration. Intervals use consecutive in-window timestamps, excluding boundary-crossing startup intervals; verify against native interval metrics.';
    Meaning='Independent ETW-based Terminal presentation/display timing from the installed PresentMon service. This is not an optical measurement or a one-to-one identification of distinct Doom framebuffers. Presentation/display latency here starts at Terminal Present(), not user input or Doom rendering. Windows compositor scheduling and the active desktop affect cadence.'}
$report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath ($Prefix+'-summary.json')
$report | ConvertTo-Json -Depth 7
