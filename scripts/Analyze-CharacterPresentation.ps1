#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string[]]$Prefixes=@('presentmon-matrix-prototype','presentmon-ansiart-prototype',
    'presentmon-character-classic-control','presentmon-ansiart-repeat','presentmon-matrix-repeat'),
    [string]$Directory="$PSScriptRoot/../results",
    [string]$Report="$PSScriptRoot/../results/character-presentation-comparison.json")
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$runs=[Collections.Generic.List[object]]::new()
foreach($name in $Prefixes) {
    $prefix=Join-Path $Directory $name
    $game=Get-Content -LiteralPath ($prefix+'-game.json') -Raw | ConvertFrom-Json
    $summary=Get-Content -LiteralPath ($prefix+'-summary.json') -Raw | ConvertFrom-Json
    $capture=Get-Content -LiteralPath ($prefix+'-capture.json') -Raw | ConvertFrom-Json
    if($summary.GameSha256 -ne (Get-FileHash -LiteralPath ($prefix+'-game.json')).Hash -or
        $summary.CaptureSha256 -ne (Get-FileHash -LiteralPath ($prefix+'-capture.json')).Hash -or
        $summary.FramesSha256 -ne (Get-FileHash -LiteralPath ($prefix+'-frames.csv')).Hash){throw 'Analysis input hashes no longer match.'}
    if($game.ExitReason -ne 'LevelComplete' -or $game.Error -or $capture.Error -or $summary.SwapChains.Count -ne 1){throw 'Only successful single-swapchain replays may be summarized here.'}
    if($capture.LaunchStyle -ne $game.OutputStyle){throw 'Launch and game styles disagree.'}
    $render=[Collections.Generic.List[double]]::new();$encode=[Collections.Generic.List[double]]::new()
    foreach($frame in $game.FrameStats) {
        $maxRender=0.0;$maxEncode=0.0
        foreach($worker in $frame.Workers){$maxRender=[Math]::Max($maxRender,$worker[0]);$maxEncode=[Math]::Max($maxEncode,$worker[1])}
        $render.Add($maxRender);$encode.Add($maxEncode)
    }
    $drops=@(Import-Csv -LiteralPath ($prefix+'-frames.csv') | Where-Object {$_.Dropped -eq 'True' -and
        [long]$_.PresentStartQpc -ge $summary.WindowStartQpc -and [long]$_.PresentStartQpc -le $summary.WindowEndQpc} | Sort-Object {[long]$_.PresentStartQpc})
    $chain=$summary.SwapChains[0]
    $runs.Add([ordered]@{Prefix=$name;Style=$game.OutputStyle;FontSize=$capture.LaunchFontSize;Maximized=$capture.LaunchMaximized;
        SourceWidth=$game.SourceWidth;SourceHeight=$game.SourceHeight;OutputColumns=$game.OutputColumns;OutputRows=$game.OutputRows;
        ActualTerminalColumns=$game.TerminalColumns;ActualTerminalRows=$game.TerminalRows;Workers=$game.Workers;
        DurationSeconds=$game.DurationSeconds;WriteWindowSeconds=$summary.WindowSeconds;Writes=$game.CompletedFrames;
        WritesPerSecond=$game.CompletedUpdatesPerSecond;Tics=$game.SimulationTics;TicsPerSecond=$game.TicsPerSecond;
        Kills=$game.Simulation.Kills;Health=$game.Simulation.Health;ViewportPauses=$game.ViewportPauseCount;
        DisplayTransitions=$chain.DisplayTransitionsWithinWindow;DisplayedTransitionsPerSecond=$chain.DisplayedTransitionsPerSecond;
        Submissions=$chain.SubmittedWithinWindow;DroppedSubmissions=$chain.DroppedAmongSubmitted;DisplayIntervalMs=$chain.DisplayIntervalMs;
        FirstDropSeconds=if($drops.Count){([long]$drops[0].PresentStartQpc-$summary.WindowStartQpc)/$summary.QpcFrequency}else{$null};
        LastDropSeconds=if($drops.Count){([long]$drops[-1].PresentStartQpc-$summary.WindowStartQpc)/$summary.QpcFrequency}else{$null};
        DropsInFirstThreeSeconds=@($drops | Where-Object {([long]$_.PresentStartQpc-$summary.WindowStartQpc)/$summary.QpcFrequency -lt 3}).Count;
        SlowestWorkerRenderMs=(Get-SampleStats $render.ToArray());SlowestWorkerEncodeMs=(Get-SampleStats $encode.ToArray());
        OutputWriteMs=(Get-SampleStats ([double[]]$game.FrameStats.OutputMs));
        WorkerAndSimulationWorkingSetBytes=$game.WorkerWorkingSetBytes+$game.SimulationWorkingSetBytes;
        SummarySha256=(Get-FileHash -LiteralPath ($prefix+'-summary.json')).Hash})
}
@{AnalyzedUtc=[DateTime]::UtcNow.ToString('o');Runs=$runs.ToArray();SourceManifest='character-sources.json';
    SourceManifestSha256=(Get-FileHash -LiteralPath (Join-Path $Directory 'character-sources.json')).Hash;
    Meaning='Five sequential exploratory full E1M1 replays, preserving every capture. Same source rasterization and input route; styles intentionally differ in output representation and default font, so this is not a same-output encoder speed contest. Per-frame slowest-worker stage times are separate distributions and cannot be added to recover pipelined frame time. PresentMon display transitions do not identify unique Doom frame contents. No study benchmarks ran concurrently with these captures.'} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Report
$runs | ForEach-Object {[pscustomobject]@{Run=$_.Prefix;Writes=$_.WritesPerSecond;Tics=$_.TicsPerSecond;
    Display=$_.DisplayedTransitionsPerSecond;Drops=$_.DroppedSubmissions;P95=$_.DisplayIntervalMs.P95;Max=$_.DisplayIntervalMs.Max;
    EncodeP95=$_.SlowestWorkerEncodeMs.P95}} | ConvertTo-Json -Depth 3
