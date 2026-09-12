#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Prefix,[Parameter(Mandatory)][string]$Replay,[Parameter(Mandatory)][string]$Catalog,[Parameter(Mandatory)][string]$StartTrack,[Parameter(Mandatory)][string]$EndTrack,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh evidence report.'}
. "$PSScriptRoot/../src/InputReplay.ps1"
$prefix=[IO.Path]::GetFullPath($Prefix);$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$receipts=[Collections.Generic.List[object]]::new();$failure=$null;$details=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Read-Receipt([string]$Path){$receipts.Add(@{Path=[IO.Path]::GetFullPath($Path);Sha256=(Get-FileHash $Path).Hash});return Get-Content $Path -Raw|ConvertFrom-Json}
try{
    $r=Read-Receipt $Replay;$g=Read-Receipt ($prefix+'-game.json');$c=Read-Receipt ($prefix+'-recording.json');$a=$g.Simulation.Audio
    $capture=Read-Receipt ($prefix+'-audio.json');$merge=Read-Receipt ($prefix+'-av.json');$sourceSet=Read-Receipt ($prefix+'-route-sources.json');$ready=Read-Receipt ($prefix+'-host-ready.json')
    Check 'Reference is a successful independently qualified two-level route' ($r.Passed -and -not $r.Error -and $r.TraceChecks -gt 0 -and $r.Transitions.Count -eq 3 -and $r.Transitions[1].State -ceq 'Intermission' -and $r.Transitions[2].State -ceq 'Level')
    Check 'Actual host and audio reach replay end without error' (-not $g.Error -and -not $g.Simulation.Error -and -not $a.Error -and -not $a.CleanupError -and $g.ExitReason -ceq 'ReplayEnd')
    $count=$r.InputCommands.Count
    Check 'Every ordinary command is consumed unchanged' ($g.Simulation.Tics -eq $count -and ($g.Simulation.InputCommands|ConvertTo-Json -Compress -Depth 4) -ceq ($r.InputCommands|ConvertTo-Json -Compress -Depth 4))
    $comparison=Compare-DoomReplayCheckpoints $r.Checkpoints $g.Simulation.ReplayCheckpoints $count
    Check 'Every independent selected-state checkpoint matches directly' ($comparison.Matched -and $comparison.Checked -eq $r.Checkpoints.Count -and $g.ReplayVerification.Checked -eq $comparison.Checked -and $g.ReplayVerification.Matched)
    $fields='Tic','State','Episode','Map','Health','Armor','Ammo'
    $transitionsMatch=$g.Simulation.Transitions.Count -eq $r.Transitions.Count
    if($transitionsMatch){for($i=0;$i -lt $r.Transitions.Count;$i++){foreach($field in $fields){if(($g.Simulation.Transitions[$i].$field|ConvertTo-Json -Compress) -cne ($r.Transitions[$i].$field|ConvertTo-Json -Compress)){$transitionsMatch=$false}}}}
    Check 'Exit and destination transitions retain command timing and inventory' $transitionsMatch
    $last=$g.Simulation.Transitions[-1]
    Check 'Destination generation is actually submitted by the terminal host' (@($g.FrameStats|Where-Object {$_.Generation -eq $last.Generation -and $_.State -eq 0}).Count -gt 0)
    $names=$StartTrack,'D_INTER',$EndTrack;$frames=0L,([long]$r.Transitions[1].Tic*1260),(([long]$r.Transitions[2].Tic-1)*1260)
    $starts=@($a.Music.Transitions|Where-Object Kind -eq 'Start');$resets=@($a.Music.Transitions|Where-Object Kind -eq 'EpochReset')
    Check 'Three score starts and one epoch reset are recorded' ($starts.Count -eq 3 -and $resets.Count -eq 1 -and $a.Music.Transitions.Count -eq 4 -and $resets[0].AfterFrames -eq $frames[2])
    $entries=Get-Content $Catalog -Raw|ConvertFrom-Json -AsHashtable
    for($i=0;$i -lt 3;$i++){
        Check "Score $($names[$i]) begins at its expected packet" ($starts[$i].Track -ceq $names[$i] -and $starts[$i].AfterFrames -eq $frames[$i])
        $path=[IO.Path]::GetFullPath($entries[$names[$i]],[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Catalog)));$q=Read-Receipt $path
        Check "Score $($names[$i]) pins a successful qualification" (-not $q.Error -and $q.Details.Qualified -and $a.Music.Reports.($names[$i]) -ceq (Get-FileHash $path).Hash)
    }
    Check 'All tic audio is consumed with no stale or unconsumed packet' ($a.Packets -eq $count -and $a.LastSequence -eq $count-1 -and $a.SubmittedFrames -eq $count*1260 -and $a.Music.Frames -eq $a.SubmittedFrames -and $a.UnconsumedPackets -eq 0 -and $a.StalePacketsDiscarded -eq 0)
    Check 'Music readers and the device close cleanly' ($a.Music.Closed -and $a.DeviceClosed)
    $b=$g.Simulation.LoadingBoundaries
    Check 'Old audio completes before the new world and asset handoff' ($b.Count -eq 1 -and $b[0].AudioDrain.ThroughSequence -eq $r.Transitions[2].Tic-2 -and $b[0].AudioDrain.CompletedFrames -eq $frames[2] -and $b[0].StartQpc -le $b[0].AudioDrain.AcknowledgedQpc -and $b[0].AudioDrain.AcknowledgedQpc -lt $b[0].EndQpc)
    foreach($source in @($sourceSet.Sources)+@($c.Sources)){Check "Source is unchanged: $($source.Path)" ($source.Sha256 -ceq (Get-FileHash "$root/$($source.Path)").Hash)}
    Check 'Capture pins the requested IWAD, replay and music catalog' ($g.WadSha256 -ceq $r.WadSha256 -and $c.ReplaySha256 -ceq (Get-FileHash $Replay).Hash -and $c.MusicCatalogSha256 -ceq (Get-FileHash $Catalog).Hash)
    Check 'Fresh owned window and process-scoped audio capture complete' (-not $c.Error -and -not $c.TargetWasPreexisting -and $c.AudioCaptured -and $c.EncoderExitCode -eq 0 -and $c.AudioExitCode -eq 0 -and -not $capture.Error -and $capture.Closed -and $capture.TargetProcessId -eq $ready.SimulationPid -and $ready.CaptureGate)
    Check 'Original PCM and delivered movie hashes remain intact' ($capture.WavSha256 -ceq (Get-FileHash $capture.WavPath).Hash -and $c.VideoSha256 -ceq (Get-FileHash $c.Video).Hash -and $merge.VideoSha256 -ceq $c.VideoSha256)
    Check 'Mux preserves original video packet timing and compressed frames' (-not $merge.Error -and $merge.Validation.VideoFramesPreserved -and $merge.Validation.VideoPacketTimestampsPreserved)
    $ffmpeg=$c.MediaFfmpeg;& $ffmpeg -v error -i $c.Video -f null -
    Check 'Full delivered audiovisual movie decodes' ($LASTEXITCODE -eq 0)
    $recordedInput=Read-Receipt ($prefix+'-input.json')
    Check 'Captured input recording retains all original commands and start settings' ($recordedInput.Episode -eq $r.Episode -and $recordedInput.Map -eq $r.Map -and $recordedInput.Skill -eq $r.Skill -and ($recordedInput.InputCommands|ConvertTo-Json -Compress -Depth 4) -ceq ($r.InputCommands|ConvertTo-Json -Compress -Depth 4))
    $details=@{Commands=$count;Checkpoints=$comparison.Checked;Transitions=$g.Simulation.Transitions;MusicTransitions=$a.Music.Transitions;SubmittedFrames=$a.SubmittedFrames;ReturnedFrames=$a.ReturnedCompletedFrames;CancelledFramesUpperBound=$a.CancelledQueuedFramesUpperBound;PcmSha256=$a.PcmSha256;Starvation=$a.QueueStarvationObservations;Writes=$g.CompletedFrames;WallSeconds=$g.WallDurationSeconds;ActiveSeconds=$g.DurationSeconds;Loading=$b;Video=$c.Video;VideoSha256=$c.VideoSha256}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Details=$details;Receipts=$receipts.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Recorded independently qualified ordinary-input level/intermission/next-level route. Caller declares expected map scores; reference checkpoints and commands are compared directly. Buffer return, starvation, canceled tails and pacing are reported rather than treated as universal performance success. No full campaign or physical listening claim.'}|ConvertTo-Json -Depth 9|Set-Content $Output
}
"PASS: $($checks.Count) recorded campaign checks."
