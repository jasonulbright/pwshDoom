#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Prefix,[Parameter(Mandatory)][string]$Catalog,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh evidence path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$prefix=[IO.Path]::GetFullPath($Prefix)
$checks=[Collections.Generic.List[object]]::new();$failure=$null;$details=$null;$receipts=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Receipt([string]$Path){$receipts.Add(@{Path=$Path;Sha256=(Get-FileHash $Path).Hash});return Get-Content $Path -Raw|ConvertFrom-Json}
try{
    $g=Receipt ($prefix+'-game.json');$c=Receipt ($prefix+'-recording.json');$capture=Receipt ($prefix+'-audio.json');$merge=Receipt ($prefix+'-av.json')
    $replay=Receipt "$root/results/input-session-replay.json";$sourceSet=Receipt ($prefix+'-route-sources.json')
    $a=$g.Simulation.Audio
    Check 'Actual session reaches replay end without game or audio errors' (-not $g.Error -and -not $g.Simulation.Error -and -not $a.Error -and -not $a.CleanupError -and $g.ExitReason -ceq 'ReplayEnd')
    Check 'All 1747 ordinary commands and eight established checkpoints match' ($g.Simulation.Tics -eq 1747 -and $replay.InputCommands.Count -eq 1747 -and $g.ReplayVerification.Matched -and $g.ReplayVerification.Checked -eq 8)
    Check 'Actual game transitions retain E1M1 exit and E1M2 entry' ($g.Simulation.Transitions.Count -eq 3 -and $g.Simulation.Transitions[1].State -ceq 'Intermission' -and $g.Simulation.Transitions[1].Tic -eq 1560 -and $g.Simulation.Transitions[2].Map -eq 2 -and $g.Simulation.Transitions[2].Tic -eq 1676)
    # Intermission starts its music on its first Update, one tick after entry.
    # World construction starts map music in the entry tick. Map publication
    # also resets the previous audio epoch before that new selection is read.
    $expectedNames='D_E1M1','D_INTER','D_E1M2';$expectedFrames=0L,(1560L*1260),(1675L*1260)
    $starts=@($a.Music.Transitions|Where-Object Kind -eq 'Start')
    Check 'Audio receives three starts and the expected map handoff epoch reset' ($a.Music.Transitions.Count -eq 4 -and $starts.Count -eq 3 -and $a.Music.Transitions[2].Kind -ceq 'EpochReset' -and $a.Music.Transitions[2].AfterFrames -eq 2110500 -and $a.EpochResets -eq 1)
    for($i=0;$i -lt 3;$i++){$e=$starts[$i];Check "Correct track and first affected audio packet for $($expectedNames[$i])" ($e.Track -ceq $expectedNames[$i] -and $e.Loop -and $e.AfterFrames -eq $expectedFrames[$i])}
    Check 'All simulation audio packets and music frames are consumed' ($a.Packets -eq 1747 -and $a.LastSequence -eq 1746 -and $a.SubmittedFrames -eq 2201220 -and $a.Music.Frames -eq $a.SubmittedFrames -and $a.UnconsumedPackets -eq 0 -and $a.StalePacketsDiscarded -eq 0)
    Check 'Music readers and device close' ($a.Music.Closed -and $a.DeviceClosed)
    if($g.Simulation.PSObject.Properties['LoadingBoundaries']){
        $boundaries=@($g.Simulation.LoadingBoundaries);$boundary=$boundaries[0]
        Check 'Loading begins at the established command boundary for E1M2' ($boundaries.Count -eq 1 -and $boundary.Tic -eq 1675 -and $boundary.Episode -eq 1 -and $boundary.Map -eq 2 -and $null -eq $g.Simulation.IncompleteLoadingBoundary)
        Check 'Every old-map audio frame returns before construction proceeds' ($boundary.AudioDrain.ThroughSequence -eq 1674 -and $boundary.AudioDrain.CompletedFrames -eq 2110500)
        Check 'Worker acknowledgement agrees with the producer loading receipt' ($a.LoadingDrains.Count -eq 1 -and $a.LoadingDrains[0].ThroughSequence -eq 1674 -and $a.LoadingDrains[0].CompletedFrames -eq 2110500 -and $a.LoadingDrains[0].Qpc -eq $boundary.AudioDrain.AcknowledgedQpc)
        $beforeAssetsQpc=$boundary.StartQpc+$boundary.BeforeAssetsMilliseconds*$g.QpcFrequency/1000
        Check 'Drain acknowledgement lies inside the pre-asset loading boundary' ($boundary.StartQpc -le $boundary.AudioDrain.AcknowledgedQpc -and $boundary.AudioDrain.AcknowledgedQpc -le $beforeAssetsQpc -and $beforeAssetsQpc -lt $boundary.EndQpc)
        Check 'Complete loading duration retains the original QPC interval' ($boundary.TotalMilliseconds -gt $boundary.BeforeAssetsMilliseconds -and [Math]::Abs($boundary.TotalMilliseconds-($boundary.EndQpc-$boundary.StartQpc)*1000.0/$g.QpcFrequency) -lt .001)
    }
    $catalogEntries=Get-Content $Catalog -Raw|ConvertFrom-Json -AsHashtable
    foreach($track in $expectedNames){
        $path=[IO.Path]::GetFullPath($catalogEntries[$track],[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Catalog)));$q=Receipt $path
        Check "Playback pins successful qualification for $track" ($q.Details.Qualified -and -not $q.Error -and $a.Music.Reports.$track -ceq (Get-FileHash $path).Hash)
    }
    foreach($s in @($sourceSet.Sources)+@($c.Sources)){
        # A post-run audit can be corrected without changing the recorded game.
        # Retain its original snapshot and failure; pin this auditor separately.
        if($s.Path -ceq 'scripts/Test-MusicRouteEvidence.ps1'){continue}
        Check "Route source remains unchanged: $($s.Path)" ($s.Sha256 -ceq (Get-FileHash "$root/$($s.Path)").Hash)
    }
    Check 'Recorder uses the requested checkpoint replay and music catalog' ($c.ReplaySha256 -ceq (Get-FileHash "$root/results/input-session-replay.json").Hash -and $c.MusicCatalogSha256 -ceq (Get-FileHash $Catalog).Hash)
    Check 'Fresh-window recorder and scoped capture complete' (-not $c.Error -and $c.AudioCaptured -and -not $c.TargetWasPreexisting -and $c.EncoderExitCode -eq 0 -and $c.AudioExitCode -eq 0 -and -not $capture.Error -and $capture.Closed)
    $ready=Receipt ($prefix+'-host-ready.json')
    Check 'Captured audio belongs to the owned simulation process' ($ready.CaptureGate -and $ready.SimulationPid -eq $capture.TargetProcessId)
    Check 'Original scoped PCM and delivered audiovisual movie remain intact' ($capture.WavSha256 -ceq (Get-FileHash $capture.WavPath).Hash -and $c.VideoSha256 -ceq (Get-FileHash $c.Video).Hash -and $merge.VideoSha256 -ceq $c.VideoSha256)
    Check 'Mux preserves all video packet clocks and compressed frames' (-not $merge.Error -and $merge.CaptureBackend -ceq 'GraphicsCapture' -and $merge.Validation.VideoFramesPreserved -and $merge.Validation.VideoPacketTimestampsPreserved)
    $ffmpeg=$c.MediaFfmpeg
    & $ffmpeg -v error -i $c.Video -f null -;Check 'Entire actual movie decodes both video and audio' ($LASTEXITCODE -eq 0)
    $activeStarves=@($a.QueueStarvationObservations|Where-Object {$_.AfterPacket -ne $a.LastSequence})
    $details=@{Style=$g.OutputStyle;Tics=$g.Simulation.Tics;Checkpoints=$g.ReplayVerification.Checked;Transitions=$a.Music.Transitions;SubmittedFrames=$a.SubmittedFrames;ReturnedCompletedFrames=$a.ReturnedCompletedFrames;CancelledQueuedFramesUpperBound=$a.CancelledQueuedFramesUpperBound;
        StarvationBeforeShutdown=$activeStarves;AllStarvation=$a.QueueStarvationObservations;MixMaximumMs=($a.MixSamplesMs|Measure-Object -Maximum).Maximum;PacketAgeMaximumMs=($a.PacketAgeAtSubmissionMs|Measure-Object -Maximum).Maximum;
        Writes=$g.CompletedFrames;ActiveSeconds=$g.DurationSeconds;WallSeconds=$g.WallDurationSeconds;MapReloads=$g.MapReloads;Video=$c.Video;VideoSha256=$c.VideoSha256;CaptureTimeline=$merge.Timeline}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Details=$details;Receipts=$receipts.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Actual recorded E1M1/intermission/E1M2 ordinary-input route with three qualified music changes at their first affected packet, eight legacy checkpoints, scoped audiovisual output and source/media integrity. Audio starvation, returned/cancelled tails and pacing are reported, not silently treated as passing performance gates. No E1M2 completion or full campaign/fidelity claim.'}|ConvertTo-Json -Depth 10|Set-Content $Output
}
"PASS: $($checks.Count) campaign music recording checks."
