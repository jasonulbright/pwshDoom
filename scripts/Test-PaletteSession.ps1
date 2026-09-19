#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Replay,[Parameter(Mandatory)][string]$Output,[string]$Prefix,[string]$GameFile)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh evidence path.'}
if(-not $GameFile){if(-not $Prefix){throw 'Supply a game report or recording prefix.'};$GameFile=$Prefix+'-game.json'}
. "$PSScriptRoot/../src/InputReplay.ps1"
$checks=[Collections.Generic.List[object]]::new();$receipts=[Collections.Generic.List[object]]::new();$failure=$null;$details=$null
function Check([string]$Name,[bool]$Pass){$checks.Add(@{Name=$Name;Passed=$Pass});if(-not $Pass){throw $Name}}
function Read-Receipt([string]$Path){$receipts.Add(@{Path=$Path;Sha256=(Get-FileHash $Path).Hash});return Get-Content $Path -Raw|ConvertFrom-Json}
try{
    $r=Read-Receipt $Replay;$g=Read-Receipt $GameFile;$a=$g.Simulation.Audio;$count=$r.InputCommands.Count
    Check 'Explicit four-state visual fixture' ($r.Version -eq 4 -and $r.ControlEvents.Count -eq 4 -and $r.FixtureSegments.Count -eq 4 -and $r.Meaning -match 'not ordinary')
    Check 'Successful host and sound shutdown' (-not $g.Error -and -not $g.Simulation.Error -and -not $a.Error -and -not $a.CleanupError -and $g.ExitReason -eq 'ReplayEnd')
    Check 'All 700 commands preserved' ($count -eq 700 -and $g.SimulationTics -eq $count -and ($g.Simulation.InputCommands|ConvertTo-Json -Depth 4 -Compress) -ceq ($r.InputCommands|ConvertTo-Json -Depth 4 -Compress))
    $comparison=Compare-DoomReplayCheckpoints $r.Checkpoints $g.Simulation.ReplayCheckpoints $count
    Check 'All 52 independent NumericV3 checkpoints match' ($comparison.Matched -and $comparison.Checked -eq 52 -and $g.ReplayVerification.Matched -and $g.ReplaySourceMatches -and @($r.Checkpoints|Where-Object CurrentRenderSnapshotVersion -ne 3).Count -eq 0)
    Check 'Four exact saves loaded' ($g.Simulation.SaveOperations.Count -eq 4)
    for($i=0;$i -lt 4;$i++){Check "Save hash $i" ($g.Simulation.SaveOperations[$i].Success -and $g.Simulation.SaveOperations[$i].Result.Sha256 -ceq $r.ControlEvents[$i].SaveHash)}
    Check 'All eight automap controls preserved' (($g.Simulation.AutomapCommands|Select-Object Tic,Mask|ConvertTo-Json -Depth 4 -Compress) -ceq ($r.AutomapCommands|Select-Object Tic,Mask|ConvertTo-Json -Depth 4 -Compress) -and $r.AutomapCommands.Count -eq 8)
    $matchedFrames=0;$badFrames=[Collections.Generic.List[object]]::new();$paletteCounts=@{}
    for($index=0;$index -lt 4;$index++){
        $segment=$r.FixtureSegments[$index];$expected=@{}
        foreach($state in $r.FixtureStates|Where-Object Segment -eq $segment.Name){$expected[[int]$state.Tic]=$state}
        $expected[[int]$segment.StartTic]=@{PaletteNumber=$segment.InitialPalette;Automap=$false}
        $frames=@($g.FrameStats|Where-Object Generation -eq ($index+2))
        foreach($frame in $frames){
            $state=$expected[[int]$frame.Tic]
            if($frame.ScreenKind -eq 2){$wantedPalette=0;$wantedKind=2}
            elseif($state){$wantedPalette=$state.PaletteNumber;$wantedKind=if($state.Automap){3}else{0}}
            else{$badFrames.Add(@{Tic=$frame.Tic;Generation=$frame.Generation;Reason='No independently simulated state'});continue}
            if($frame.PaletteNumber -ne $wantedPalette -or $frame.ScreenKind -ne $wantedKind){$badFrames.Add(@{Tic=$frame.Tic;Generation=$frame.Generation;Actual=$frame.PaletteNumber;Expected=$wantedPalette})}else{$matchedFrames++}
        }
        Check "$($segment.Name): active world effect presented" (@($frames|Where-Object {$_.ScreenKind -eq 0 -and $_.PaletteNumber -gt 0}).Count -gt 0)
        Check "$($segment.Name): active automap effect presented" (@($frames|Where-Object {$_.ScreenKind -eq 3 -and $_.PaletteNumber -gt 0}).Count -gt 0)
        Check "$($segment.Name): world base palette restored" (@($frames|Where-Object {$_.ScreenKind -eq 0 -and $_.PaletteNumber -eq 0 -and $_.Tic -gt $segment.StartTic}).Count -gt 0)
        $paletteCounts[$segment.Name]=@($frames|Group-Object PaletteNumber|ForEach-Object {@{Palette=[int]$_.Name;Frames=$_.Count}})
    }
    Check 'Every presented fixture frame agrees with independent palette and automap state' ($matchedFrames -gt 0 -and $badFrames.Count -eq 0)
    Check 'All effects audio frames consumed and returned' ($a.Packets -eq $count -and $a.SubmittedFrames -eq $count*1260 -and $a.ReturnedCompletedFrames -eq $a.SubmittedFrames -and $a.UnconsumedPackets -eq 0 -and $a.CancelledQueuedFramesUpperBound -eq 0 -and $a.DeviceClosed)
    if($Prefix){
        . "$PSScriptRoot/WindowCaptureTargets.ps1"
        $c=Read-Receipt ($Prefix+'-recording.json');$ready=Read-Receipt ($Prefix+'-host-ready.json');$capture=Read-Receipt ($Prefix+'-audio.json')
        $merge=Read-Receipt ($Prefix+'-av.json');$input=Read-Receipt ($Prefix+'-input.json')
        Check 'Fresh window and scoped audio capture completed' (-not $c.Error -and -not $c.TargetWasPreexisting -and $c.AudioCaptured -and $c.EncoderExitCode -eq 0 -and $c.AudioExitCode -eq 0 -and -not $capture.Error -and $capture.Closed -and $capture.TargetProcessId -eq $ready.SimulationPid -and $ready.CaptureGate)
        Check 'Recorded commands controls and automap retained' (($input.InputCommands|ConvertTo-Json -Depth 4 -Compress) -ceq ($r.InputCommands|ConvertTo-Json -Depth 4 -Compress) -and ($input.ControlEvents|Select-Object Tic,Action,SaveHash|ConvertTo-Json -Depth 4 -Compress) -ceq ($r.ControlEvents|Select-Object Tic,Action,SaveHash|ConvertTo-Json -Depth 4 -Compress) -and ($input.AutomapCommands|Select-Object Tic,Mask|ConvertTo-Json -Depth 4 -Compress) -ceq ($r.AutomapCommands|Select-Object Tic,Mask|ConvertTo-Json -Depth 4 -Compress))
        Check 'Original media and replay hashes match' ($c.ReplaySha256 -ceq (Get-FileHash $Replay).Hash -and $capture.WavSha256 -ceq (Get-FileHash $capture.WavPath).Hash -and $c.VideoSha256 -ceq (Get-FileHash $c.Video).Hash -and $merge.VideoSha256 -ceq $c.VideoSha256)
        Check 'Mux preserves source video and timing' (-not $merge.Error -and $merge.Validation.VideoFramesPreserved -and $merge.Validation.VideoPacketTimestampsPreserved)
        foreach($source in $c.Sources){Check "Pinned source: $($source.Path)" ($source.Sha256 -ceq (Get-FileHash "$PSScriptRoot/../$($source.Path)").Hash)}
        & $c.MediaFfmpeg -v error -i $c.Video -f null -;Check 'Complete delivered movie decodes' ($LASTEXITCODE -eq 0)
        Check 'Owned window absent' (@(Get-DoomTerminalWindows|Where-Object {$_.MainWindowHandle.ToInt64() -eq $c.WindowHandle}).Count -eq 0)
        $alive=@(foreach($processId in @($ready.HostPid,$ready.SimulationPid)+@($ready.WorkerPids)){
            $process=Get-Process -Id $processId -ErrorAction SilentlyContinue
            if($process -and $process.StartTime.ToUniversalTime() -le ([datetime]$g.FinishedUtc).ToUniversalTime()){$processId}
        })
        Check 'Original processes absent (PID reuse excluded)' ($alive.Count -eq 0)
    }
    $details=@{Style=$g.OutputStyle;Commands=$count;Checkpoints=$comparison.Checked;VerifiedFrames=$matchedFrames;PaletteCounts=$paletteCounts;
        TicsPerSecond=$count/$g.DurationSeconds;WritesPerSecond=$g.CompletedFrames/$g.DurationSeconds;WorkerWorkingSetBytes=$g.WorkerWorkingSetBytes;
        AudioFrames=$a.ReturnedCompletedFrames;QueueEmptyObservations=$a.QueueStarvationObservations}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Details=$details;Receipts=$receipts.ToArray();HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        Meaning='Actual-host palette transport, effect expiry and automap checked against independently simulated fixture states and NumericV3 checkpoints. Optional recording adds source/media/audio/ownership checks. Artificial saves do not prove pickup mechanics, campaign completion, distinct displayed FPS or acoustic continuity.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) palette session checks."
