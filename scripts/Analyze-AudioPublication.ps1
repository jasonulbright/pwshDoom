#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$GameReport,[Parameter(Mandatory)][string]$Baseline,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh publication report.'}
$g=Get-Content $GameReport -Raw|ConvertFrom-Json;$b=Get-Content $Baseline -Raw|ConvertFrom-Json
$checks=[Collections.Generic.List[object]]::new();$failure=$null;$details=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Stats($Samples){$sorted=@($Samples|Sort-Object);return @{Count=$sorted.Count;Mean=($sorted|Measure-Object -Average).Average;P95=$sorted[[int][Math]::Floor(($sorted.Count-1)*.95)];Maximum=$sorted[-1]}}
try{
    Check 'Both complete routes preserve the same IWAD and recorded commands' (-not $g.Error -and -not $b.Error -and $g.ExitReason -ceq 'ReplayEnd' -and $b.ExitReason -ceq 'ReplayEnd' -and $g.WadSha256 -ceq $b.WadSha256 -and ($g.Simulation.InputCommands|ConvertTo-Json -Depth 4 -Compress) -ceq ($b.Simulation.InputCommands|ConvertTo-Json -Depth 4 -Compress))
    Check 'All eight established checkpoints match in both routes' ($g.ReplayVerification.Matched -and $b.ReplayVerification.Matched -and $g.ReplayVerification.Checked -eq 8 -and $b.ReplayVerification.Checked -eq 8)
    $a=$g.Simulation.Audio;$prior=$b.Simulation.Audio;$trace=@($g.Simulation.AudioPublicationTrace)
    Check 'Every consumed tic has one audio packet and publication trace' (-not $a.Error -and $trace.Count -eq $g.Simulation.Tics -and $a.Packets -eq $trace.Count -and $trace.Count -eq 1747)
    Check 'Moving publication preserves every submitted PCM sample' ($a.PcmSha256 -ceq $prior.PcmSha256 -and $a.SubmittedFrames -eq $prior.SubmittedFrames -and $a.SubmittedFrames -eq 2201220)
    $valid=$true
    for($n=0;$n -lt $trace.Count;$n++){
        $t=$trace[$n]
        $ordered=if($t.MapChanged){$t.UpdateEndQpc -le $t.PresentationStartQpc -and $t.PresentationStartQpc -le $t.PresentationEndQpc -and $t.PresentationEndQpc -le $t.EnqueuedQpc}else{$t.UpdateEndQpc -le $t.EnqueuedQpc -and $t.EnqueuedQpc -le $t.PresentationStartQpc -and $t.PresentationStartQpc -le $t.PresentationEndQpc}
        if($t.Sequence -ne $n -or -not $ordered){$valid=$false;break}
    }
    Check 'QPC proves publication precedes presentation work except map epoch handoff' $valid
    $map=@($trace|Where-Object MapChanged);$early=@($trace|Where-Object {-not $_.MapChanged});$ui=@($early|Where-Object {$_.State -ne 0})
    Check 'The sole deferred packet is the established new-world tic' ($map.Count -eq 1 -and $map[0].Sequence -eq 1675 -and $early.Count -eq 1746 -and $ui.Count -gt 0)
    $factor=1000.0/$g.QpcFrequency
    $details=@{EarlyPackets=$early.Count;EarlyUiPackets=$ui.Count;DeferredMapPackets=$map.Count;UpdateToEnqueueMs=Stats @($early|ForEach-Object {($_.EnqueuedQpc-$_.UpdateEndQpc)*$factor});PresentationWorkAfterEnqueueMs=Stats @($early|ForEach-Object {($_.PresentationEndQpc-$_.EnqueuedQpc)*$factor});UiPresentationWorkAfterEnqueueMs=Stats @($ui|ForEach-Object {($_.PresentationEndQpc-$_.EnqueuedQpc)*$factor});
      SubmittedPcmSha256=$a.PcmSha256;ReturnedFrames=$a.ReturnedCompletedFrames;CancelledFramesUpperBound=$a.CancelledQueuedFramesUpperBound;Starvation=$a.QueueStarvationObservations;Writes=$g.CompletedFrames;WallSeconds=$g.WallDurationSeconds;ActiveSeconds=$g.DurationSeconds;Loading=$g.Simulation.LoadingBoundaries}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Details=$details;GameReportSha256=(Get-FileHash $GameReport).Hash;BaselineSha256=(Get-FileHash $Baseline).Hash;SourceSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Actual QPC ordering around completed simulation tics and presentation work, with independent retained-route command/checkpoint/PCM identity. Time overlapped with presentation is not a measured improvement in physical speaker latency; starvation and wall time remain visible.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) audio publication checks."
