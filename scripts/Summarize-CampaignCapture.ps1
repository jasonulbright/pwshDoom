#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Prefix,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh summary path.'}
$prefix=[IO.Path]::GetFullPath($Prefix)
$g=Get-Content ($prefix+'-game.json') -Raw|ConvertFrom-Json
$m=Get-Content ($prefix+'-av.json') -Raw|ConvertFrom-Json
if($g.Error -or $g.Simulation.Error -or $m.Error){throw 'Only summarize a completed error-free host/capture; preserve failed reports separately.'}
$gaps=[Collections.Generic.List[object]]::new()
for($i=1;$i -lt $g.FrameStats.Count;$i++){
    $a=$g.FrameStats[$i-1];$b=$g.FrameStats[$i]
    $ms=($b.EndQpc-$a.EndQpc)*1000.0/$g.QpcFrequency
    if($ms -lt 0){throw 'Console completion timestamps are not monotonic.'}
    $gaps.Add(@{Milliseconds=$ms;AfterWrite=$i;PreviousTic=$a.Tic;Tic=$b.Tic;PreviousMap=$a.Map;Map=$b.Map;
        SameWorld=($a.Generation -eq $b.Generation -and $a.State -eq 0 -and $b.State -eq 0)})
}
function Stats($Values){
    $sorted=@($Values|Sort-Object)
    if($sorted.Count -eq 0){return @{Count=0}}
    return @{Count=$sorted.Count;Mean=($sorted|Measure-Object -Average).Average;P50=$sorted[[Math]::Ceiling(.50*$sorted.Count)-1];
        P95=$sorted[[Math]::Ceiling(.95*$sorted.Count)-1];P99=$sorted[[Math]::Ceiling(.99*$sorted.Count)-1];Max=$sorted[-1]}
}
$audio=$g.Simulation.Audio
$internalFills=@($m.Timeline.ZeroFilledIntervals|Where-Object {$_.Frame -gt 0 -and $_.Frame+$_.Frames -lt $m.Timeline.Frames})
$report=@{Error=$null;Commands=$g.SimulationTics;ConsoleWrites=$g.CompletedFrames;ActiveSeconds=$g.DurationSeconds;WallSeconds=$g.WallDurationSeconds;
    SimulationTicsPerActiveSecond=$g.TicsPerSecond;ConsoleWritesPerActiveSecond=$g.CompletedUpdatesPerSecond;
    AllConsecutiveWriteGapsMs=(Stats @($gaps|ForEach-Object {$_.Milliseconds}));SameWorldWriteGapsMs=(Stats @($gaps|Where-Object SameWorld|ForEach-Object {$_.Milliseconds}));
    LargestGaps=@($gaps|Sort-Object Milliseconds -Descending|Select-Object -First 10);
    SimulationUpdateMs=$g.Simulation.SimulationMs;DiscoveryMs=$g.Simulation.AutomapDiscoveryMs;SnapshotMs=$g.Simulation.SnapshotPublishMs;SimulationLatenessMs=$g.Simulation.TickLatenessMs;
    Audio=@{SubmittedFrames=$audio.SubmittedFrames;ReturnedFrames=$audio.ReturnedCompletedFrames;QueueEmptyObservations=$audio.QueueStarvationObservations.Count;
        CancelledFramesUpperBound=$audio.CancelledQueuedFramesUpperBound;ApiDiscontinuityPackets=$m.Timeline.ApiDiscontinuityPackets;
        TimelineZeroFilledFrames=$m.Timeline.ZeroFilledFrames;InternalTimelineZeroFilledFrames=($internalFills|Measure-Object Frames -Sum).Sum;InternalTimelineFills=$internalFills};
    Video=@{DurationSeconds=[double]$m.Validation.MergedContainerVideoDuration;Width=$m.Validation.VideoStream.width;Height=$m.Validation.VideoStream.height};
    Receipts=@(($prefix+'-game.json'),($prefix+'-av.json')|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash $_).Hash}});SourceSha256=(Get-FileHash $PSCommandPath).Hash;
    Meaning='One recorded run, not an isolated benchmark or causal before/after comparison. Gaps are consecutive console-write completion QPC differences, not frame pipeline latency or displayed images. All gaps include transitions; SameWorld is an explicitly filtered companion series. Percentiles use nearest rank. No warm-up exclusions. Timeline zero fill reflects capture alignment; software empty-queue observations and returned buffers do not prove uninterrupted acoustic playback.'}
$report|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $Output
$report|Select-Object Commands,ConsoleWrites,SimulationTicsPerActiveSecond,ConsoleWritesPerActiveSecond,AllConsecutiveWriteGapsMs,SameWorldWriteGapsMs|ConvertTo-Json -Depth 3
