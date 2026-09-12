#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$receipts=[Collections.Generic.List[object]]::new();$failure=$null;$sources=@()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Read-Receipt([string]$Path){$full=Join-Path $root $Path;$receipts.Add(@{Path=$Path;Sha256=(Get-FileHash $full).Hash});return Get-Content $full -Raw|ConvertFrom-Json}
try{
    foreach($case in @(@('music-playback-unit-first',13),@('music-events-unit-backing-field',11),@('music-audio-worker-first',10),@('audio-runspace-music-compatible',6),@('audio-volume-music-compatible',4),@('music-save-worker-first',15))){
        $r=Read-Receipt "results/$($case[0]).json";Check "$($case[0]) targeted checks pass" (-not $r.Error -and $r.Checks.Count -eq $case[1] -and @($r.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
        if($r.PSObject.Properties['Sources']){foreach($s in $r.Sources){Check "Current source in $($case[0]): $($s.Path)" ((Get-FileHash (Join-Path $root $s.Path)).Hash -ceq $s.Sha256)}}
    }
    foreach($name in 'music-events-unit-first','music-events-unit-fixed'){$r=Read-Receipt "results/$name.json";Check 'Failed adapter dispatch attempts remain recorded' ($r.Error -match 'volume clamps')}
    $r=Read-Receipt 'results/music-events-unit-backing-field.json';Check 'Current event adapter is the corrected source' ($r.SourceSha256 -ceq (Get-FileHash "$root/src/MusicEvents.ps1").Hash)
    $device=Read-Receipt 'results/music-audio-worker-first.json'
    Check 'Complete worker PCM matches independent offline fixture' ($device.Audio.PcmSha256 -ceq $device.ExpectedPcmSha256 -and $device.Audio.SubmittedFrames -eq 176400 -and $device.Audio.Music.Frames -eq 161280)
    $headless=Read-Receipt 'results/music-host-first.json';$live=Read-Receipt 'local/recordings/music-matrix-first-game.json'
    foreach($entry in @(@{Name='Headless';Game=$headless},@{Name='Recorded';Game=$live})){
        $g=$entry.Game;$a=$g.Simulation.Audio
        Check "$($entry.Name) host/music closes successfully" (-not $g.Error -and -not $g.Simulation.Error -and -not $a.Error -and -not $a.CleanupError -and $a.DeviceClosed -and $a.Music.Closed -and $g.ExitReason -ceq 'Duration')
        Check "$($entry.Name) all simulation audio frames consumed and returned" ($a.Packets -eq $g.Simulation.Tics -and $a.SubmittedFrames -eq $a.Packets*1260 -and $a.ReturnedCompletedFrames -eq $a.SubmittedFrames -and $a.Music.Frames -eq $a.SubmittedFrames -and $a.UnconsumedPackets -eq 0)
        Check "$($entry.Name) receives one actual starting-map music command" ($a.Music.Transitions.Count -eq 1 -and $a.Music.Transitions[0].Track -ceq 'D_E1M1' -and $a.Music.Transitions[0].AfterFrames -eq 0)
        Check "$($entry.Name) starvation polls are confined to final packet shutdown" (@($a.QueueStarvationObservations|Where-Object {$_.AfterPacket -ne $a.LastSequence}).Count -eq 0)
    }
    $recording=Read-Receipt 'local/recordings/music-matrix-first-recording.json';$qa=Read-Receipt 'results/music-live-recording.json'
    Check 'Capture selected a new window while an existing Terminal remained open' (-not $recording.Error -and $recording.EncoderExitCode -eq 0 -and $recording.PreexistingTerminalWindows -eq 1 -and -not $recording.TargetWasPreexisting)
    Check 'Original video and viewing copy match retained hashes' ((Get-FileHash $recording.Video).Hash -ceq $recording.VideoSha256 -and $qa.SourceSha256 -ceq $recording.VideoSha256 -and (Get-FileHash $qa.ViewingCopy).Hash -ceq $qa.ViewingSha256)
    Check 'Recording explicitly distinguishes enabled playback from silent footage' ($recording.SoundRequested -and -not $recording.AudioCaptured -and -not $qa.AudioCaptured -and $qa.OriginalDecodeExitCode -eq 0)
    $sources='Start-Doom.ps1','src/MusicEvents.ps1','src/MusicPlayback.ps1','src/AudioRunspace.ps1','src/SimulationProcess.ps1','scripts/Invoke-AudioWorker.ps1','scripts/Invoke-SimulationWorker.ps1','scripts/Invoke-Doom.ps1','scripts/Record-DoomReplay.ps1','scripts/WindowCaptureTargets.ps1','scripts/Test-SaveWorker.ps1','scripts/Test-MusicIntegrationEvidence.ps1'
    foreach($path in $sources){
        if($path -eq 'src/MusicEvents.ps1'){continue} # Engine-dependent base class exercised by real worker/tests.
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$errors);Check "Parse $path" ($errors.Count -eq 0)
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Receipts=$receipts.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;
      Sources=@($sources|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path $root $_)).Hash}});
      Meaning='Current integration source snapshot with unit/device/save/headless/actual-window evidence. Complete worker-fixture submitted PCM has an independent offline control schedule. Host audio frame accounting is not waveform equivalence or acoustic capture; video is silent. E1M1 only, no full campaign or sustained presentation-rate qualification.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) music integration evidence checks."
