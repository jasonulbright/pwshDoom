#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string[]]$Reports,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh comparison path.'}
function Stats([double[]]$Values){
    if($Values.Count -eq 0){return $null}
    $sorted=$Values.Clone();[Array]::Sort($sorted)
    return [ordered]@{Count=$sorted.Count;Mean=($Values|Measure-Object -Average).Average;
        P50=$sorted[[Math]::Ceiling(.5*$sorted.Count)-1];P95=$sorted[[Math]::Ceiling(.95*$sorted.Count)-1];
        P99=$sorted[[Math]::Ceiling(.99*$sorted.Count)-1];Maximum=$sorted[-1]}
}
$runs=@(foreach($path in $Reports){
    $g=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($g.Error -or $g.ExitReason -ne 'ReplayEnd' -or $g.FrameStats.Count -ne $g.CompletedFrames){throw "Incomplete gameplay report: $path"}
    $frames=@($g.FrameStats);$frequency=[double]$g.QpcFrequency
    $derived=@(for($i=0;$i -lt $frames.Count;$i++){
        $f=$frames[$i];$end=0L
        foreach($worker in $f.Workers){$end=[Math]::Max($end,[long]$worker[4])}
        [pscustomobject]@{Tic=$f.Tic;Generation=$f.Generation;State=$f.State;OutputMs=$f.OutputMs;
            SubmitMs=$f.SubmitMs;HarvestMs=$f.HarvestMs;LifetimeMs=($f.EndQpc-$f.StartQpc)*1000.0/$frequency;
            LastWorkerFromDispatchMs=($end-$f.StartQpc)*1000.0/$frequency;
            CompletionGapMs=if($i -gt 0){($f.EndQpc-$frames[$i-1].EndQpc)*1000.0/$frequency}else{$null}}
    })
    $groups=@([pscustomobject]@{Name='EntireRoute';Frames=$derived})
    foreach($range in @(@(1,1200),@(1201,2400),@(2401,3600),@(3601,4800),@(4801,6000),@(6001,7118))){
        $selected=@($derived|Where-Object {$_.Tic -ge $range[0] -and $_.Tic -le $range[1]})
        $groups+=[pscustomobject]@{Name="Tics$($range[0])To$($range[1])";Frames=$selected}
    }
    $summaries=@(foreach($group in $groups){
        $summary=[ordered]@{Window=$group.Name;Frames=$group.Frames.Count}
        foreach($field in 'OutputMs','SubmitMs','HarvestMs','LifetimeMs','LastWorkerFromDispatchMs','CompletionGapMs'){
            $summary[$field]=Stats @($group.Frames|ForEach-Object {if($null -ne $_.$field){[double]$_.$field}})
        }
        $summary
    })
    [ordered]@{Report=$path;Sha256=(Get-FileHash -LiteralPath $path).Hash;SimulationTics=$g.SimulationTics;
        CompletedFrames=$g.CompletedFrames;ActiveSeconds=$g.DurationSeconds;WallSeconds=$g.WallDurationSeconds;
        TicsPerSecond=$g.TicsPerSecond;WritesPerActiveSecond=$g.CompletedUpdatesPerSecond;WritesPerWallSecond=$g.CompletedUpdatesPerWallSecond;
        Style=$g.OutputStyle;Workers=$g.Workers;TerminalColumns=$g.TerminalColumns;TerminalRows=$g.TerminalRows;
        ViewportPausedSeconds=$g.ViewportPausedSeconds;MapReloadPausedSeconds=$g.MapReloadPausedSeconds;
        SimulationMs=$g.Simulation.SimulationMs;SnapshotMs=$g.Simulation.SnapshotPublishMs;
        AutomapDiscoveryMs=$g.Simulation.AutomapDiscoveryMs;Windows=$summaries}
})
[ordered]@{CreatedUtc=[datetime]::UtcNow.ToString('o');HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Runs=$runs;
    Meaning='Descriptive comparison of retained recorded runs, not a controlled paired benchmark or displayed-FPS measurement. All frames retained in EntireRoute, including initial work and transition gaps. Tic windows select completed frame snapshots; output samples need not represent identical interpolated images. Completion gaps use monotonic QPC and include loading. Frame lifetimes and worker delays overlap pipelined output; do not add these means. No cause is established by correlation.'}|
    ConvertTo-Json -Depth 10|Set-Content -LiteralPath $Output
"Compared $($runs.Count) complete route reports."
