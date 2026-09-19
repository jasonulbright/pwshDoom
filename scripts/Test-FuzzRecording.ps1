#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Prefix,[Parameter(Mandatory)][string]$Replay,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/WindowCaptureTargets.ps1"
$checks=[Collections.Generic.List[object]]::new();$receipts=[Collections.Generic.List[object]]::new();$failure=$null;$details=$null
function Check([string]$Name,[bool]$Pass){$checks.Add(@{Name=$Name;Passed=$Pass});if(-not $Pass){throw $Name}}
function Read-Receipt([string]$Path){$receipts.Add(@{Path=$Path;Sha256=(Get-FileHash $Path).Hash});return Get-Content $Path -Raw|ConvertFrom-Json}
try{
    $r=Read-Receipt $Replay;$g=Read-Receipt ($Prefix+'-game.json');$c=Read-Receipt ($Prefix+'-recording.json')
    $ready=Read-Receipt ($Prefix+'-host-ready.json');$capture=Read-Receipt ($Prefix+'-audio.json');$merge=Read-Receipt ($Prefix+'-av.json');$input=Read-Receipt ($Prefix+'-input.json')
    $count=$r.InputCommands.Count;$a=$g.Simulation.Audio
    Check 'Fixture explicitly declares save load and shortened power timer' ($r.Version -eq 3 -and $r.ControlEvents.Count -eq 1 -and $r.ControlEvents[0].Action -eq 'LoadGame' -and $r.Meaning -match 'not a pickup route')
    Check 'Host and audio exit successfully' (-not $g.Error -and -not $g.Simulation.Error -and -not $a.Error -and -not $a.CleanupError -and $g.ExitReason -eq 'ReplayEnd')
    Check 'All 350 commands consumed unchanged' ($count -eq 350 -and $g.SimulationTics -eq $count -and ($g.Simulation.InputCommands|ConvertTo-Json -Depth 4 -Compress) -ceq ($r.InputCommands|ConvertTo-Json -Depth 4 -Compress))
    $comparison=Compare-DoomReplayCheckpoints $r.Checkpoints $g.Simulation.ReplayCheckpoints $count
    Check 'All 17 independent state and full packet checkpoints match' ($comparison.Matched -and $comparison.Checked -eq 17 -and $g.ReplayVerification.Matched -and $g.ReplaySourceMatches)
    Check 'Source fixture covers active, blink and expired power states' (@($r.FixtureTimers|Where-Object Invisibility -gt 128).Count -gt 0 -and @($r.FixtureTimers|Where-Object {$_.Invisibility -gt 0 -and $_.Invisibility -le 128}).Count -gt 0 -and @($r.FixtureTimers|Where-Object Invisibility -eq 0).Count -gt 0)
    Check 'Exact save loaded successfully' ($g.Simulation.SaveOperations.Count -eq 1 -and $g.Simulation.SaveOperations[0].Success -and $g.Simulation.SaveOperations[0].Result.Sha256 -ceq $r.ControlEvents[0].SaveHash)
    foreach($span in @(@(1,70),@(82,209),@(210,350))){Check "World images submitted at tics $($span[0])..$($span[1])" (@($g.FrameStats|Where-Object {$_.Generation -eq 2 -and $_.ScreenKind -eq 0 -and $_.Tic -ge $span[0] -and $_.Tic -le $span[1]}).Count -gt 0)}
    Check 'Recorded input and load control retained' (($input.InputCommands|ConvertTo-Json -Depth 4 -Compress) -ceq ($r.InputCommands|ConvertTo-Json -Depth 4 -Compress) -and $input.ControlEvents[0].SaveHash -ceq $r.ControlEvents[0].SaveHash)
    Check 'All sound frames consumed and returned' ($a.Packets -eq $count -and $a.SubmittedFrames -eq $count*1260 -and $a.ReturnedCompletedFrames -eq $a.SubmittedFrames -and $a.UnconsumedPackets -eq 0 -and $a.CancelledQueuedFramesUpperBound -eq 0 -and $a.DeviceClosed)
    Check 'Fresh window and process-scoped capture completed' (-not $c.Error -and -not $c.TargetWasPreexisting -and $c.AudioCaptured -and $c.EncoderExitCode -eq 0 -and $c.AudioExitCode -eq 0 -and -not $capture.Error -and $capture.Closed -and $capture.TargetProcessId -eq $ready.SimulationPid -and $ready.CaptureGate)
    Check 'Replay and original media hashes match' ($c.ReplaySha256 -ceq (Get-FileHash $Replay).Hash -and $capture.WavSha256 -ceq (Get-FileHash $capture.WavPath).Hash -and $c.VideoSha256 -ceq (Get-FileHash $c.Video).Hash -and $merge.VideoSha256 -ceq $c.VideoSha256)
    Check 'Mux preserves source compressed frames and timing' (-not $merge.Error -and $merge.Validation.VideoFramesPreserved -and $merge.Validation.VideoPacketTimestampsPreserved)
    foreach($source in $c.Sources){Check "Pinned source: $($source.Path)" ($source.Sha256 -ceq (Get-FileHash "$PSScriptRoot/../$($source.Path)").Hash)}
    & $c.MediaFfmpeg -v error -i $c.Video -f null -;Check 'Complete delivered movie decodes' ($LASTEXITCODE -eq 0)
    $remaining=@(Get-DoomTerminalWindows|Where-Object {$_.MainWindowHandle.ToInt64() -eq $c.WindowHandle})
    Check 'Owned window is absent' ($remaining.Count -eq 0)
    $alive=@(foreach($processId in @($ready.HostPid,$ready.SimulationPid)+@($ready.WorkerPids)){
        $p=Get-Process -Id $processId -ErrorAction SilentlyContinue
        if($p -and $p.StartTime.ToUniversalTime() -le ([datetime]$g.FinishedUtc).ToUniversalTime()){$processId}
    })
    Check 'Original game processes are absent (PID reuse excluded)' ($alive.Count -eq 0)
    $details=@{Style=$c.Style;Commands=$count;Checkpoints=$comparison.Checked;Frames=$g.CompletedFrames;ActiveSeconds=$g.DurationSeconds;WallSeconds=$g.WallDurationSeconds;
        TicsPerSecond=$count/$g.DurationSeconds;WritesPerSecond=$g.CompletedFrames/$g.DurationSeconds;SubmittedAudioFrames=$a.SubmittedFrames;ReturnedAudioFrames=$a.ReturnedCompletedFrames;
        QueueEmptyObservations=$a.QueueStarvationObservations;Video=$c.Video;VideoSha256=$c.VideoSha256;OwnedWindowRemaining=$remaining.Count;OriginalProcessesRemaining=$alive}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Details=$details;Receipts=$receipts.ToArray();HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        Meaning='Recorded explicit invisibility/Spectre save fixture, not a campaign route. Verifies complete input, independently generated full packet checkpoints, loaded-state presentation, source/media integrity, returned audio and owned-resource cleanup. Captured/write rate does not measure distinct displayed frames; no acoustic-continuity guarantee.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) recorded fuzz checks."
