#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$GameReport,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh timing report path.'}
$g=Get-Content $GameReport -Raw|ConvertFrom-Json;$s=$g.Simulation;$a=$s.Audio
if($g.Error -or $s.Error -or $a.Error -or $a.Packets -ne $s.Tics){throw 'Expected a successful route with every audio packet consumed.'}
foreach($samples in @($s.SimulationSamplesMs),@($s.SnapshotSamplesMs),@($s.TickLatenessSamplesMs),@($s.AudioPacketSamplesMs),@($a.MixSamplesMs),@($a.PacketAgeAtSubmissionMs)){
    if($samples.Count -ne $s.Tics){throw 'Sample arrays are not aligned one-to-one with consumed commands.'}
}
function Stats($Samples){$sorted=@($Samples|Sort-Object);return @{Count=$sorted.Count;Mean=($sorted|Measure-Object -Average).Average;P95=$sorted[[int][Math]::Floor(($sorted.Count-1)*.95)];Maximum=$sorted[-1]}}
$windows=@(foreach($event in $a.QueueStarvationObservations){
    $rows=@(for($n=[Math]::Max(0,$event.AfterPacket-4);$n -le [Math]::Min($s.Tics-1,$event.AfterPacket+10);$n++){
        @{Sequence=$n;SimulationMs=$s.SimulationSamplesMs[$n];SnapshotMs=$s.SnapshotSamplesMs[$n];PacketBuildMs=$s.AudioPacketSamplesMs[$n];TickStartLatenessMs=$s.TickLatenessSamplesMs[$n];AudioMixMs=$a.MixSamplesMs[$n];PacketSubmissionAgeMs=$a.PacketAgeAtSubmissionMs[$n]}
    })
    @{AfterPacket=$event.AfterPacket;AudioWorkerWallMs=$event.WallMs;AfterFinalPacket=($event.AfterPacket -eq $a.LastSequence);Samples=$rows}
})
@{Error=$null;GameReport=[IO.Path]::GetFullPath($GameReport);GameReportSha256=(Get-FileHash $GameReport).Hash;SourceSha256=(Get-FileHash $PSCommandPath).Hash;
  Tics=$s.Tics;CheckpointMatches=$g.ReplayVerification.Checked;SubmittedFrames=$a.SubmittedFrames;ReturnedFrames=$a.ReturnedCompletedFrames;CancelledFramesUpperBound=$a.CancelledQueuedFramesUpperBound;
  Simulation=Stats $s.SimulationSamplesMs;Snapshots=Stats $s.SnapshotSamplesMs;AudioMix=Stats $a.MixSamplesMs;SubmissionAge=Stats $a.PacketAgeAtSubmissionMs;
  ActiveStarves=@($windows|Where-Object {-not $_.AfterFinalPacket}).Count;StarvationWindows=$windows;Transitions=$s.Transitions;MusicTransitions=$a.Music.Transitions;MapReloads=$g.MapReloads;
  ActiveSeconds=$g.DurationSeconds;WallSeconds=$g.WallDurationSeconds;Writes=$g.CompletedFrames;RebufferResumes=if($a.PSObject.Properties['RebufferResumes']){$a.RebufferResumes}else{@()};
  Meaning='Sequence-aligned retained route measurements after asserting all six arrays and audio packet counts equal consumed commands. Starvation polling is not hardware telemetry. Tick-start lateness and submission age have different origins; no sum is presented as acoustic latency. Map/UI transitions and initial work remain in their recorded timing windows.'}|ConvertTo-Json -Depth 8|Set-Content $Output
"Analyzed $($s.Tics) command/audio sequences."
