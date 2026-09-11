#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$RecordingPrefix="$PSScriptRoot/../local/recordings/audio-matrix-first")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$failure=$null;$rawHash=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Read-Report([string]$Name){Get-Content (Join-Path $root "results/$Name.json") -Raw|ConvertFrom-Json}
$sources=@('Start-Doom.ps1','src/AudioMixer.ps1','src/AudioEvents.ps1','src/AudioPackets.ps1','src/AudioRunspace.ps1','src/WaveOutDevice.ps1','src/SimulationProcess.ps1','scripts/Invoke-AudioWorker.ps1','scripts/Invoke-SimulationWorker.ps1','scripts/Invoke-Doom.ps1','scripts/Record-DoomReplay.ps1','scripts/Render-AudioReplay.ps1','scripts/Test-AudioPackets.ps1','scripts/Test-AudioRunspace.ps1','scripts/Test-SaveWorker.ps1','scripts/Test-AudioIntegration.ps1')
$reports=@('audio-packets-unit','audio-runspace-future-epoch','audio-save-worker','audio-host-first','audio-host-controls','audio-packets-replay')
try{
    foreach($name in 'audio-packets-unit','audio-runspace-future-epoch','audio-save-worker'){
        $r=Read-Report $name;Check "$name named checks" ($null -eq $r.Error -and @($r.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
    }
    $baseline=Read-Report audio-replay-cast;$wave=[IO.File]::ReadAllBytes($baseline.Wave)
    Check 'Reference WAV retains its recorded hash' ((Get-FileHash $baseline.Wave).Hash -eq $baseline.WaveSha256)
    $pcm=[byte[]]::new($wave.Length-44);[Array]::Copy($wave,44,$pcm,0,$pcm.Length);$rawHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($pcm))
    $recording=Get-Content ($RecordingPrefix+'-recording.json') -Raw|ConvertFrom-Json
    $captured=Get-Content ($RecordingPrefix+'-game.json') -Raw|ConvertFrom-Json
    Check 'Successful actual video capture, explicitly no recorded audio' ($null -eq $recording.Error -and $recording.EncoderExitCode -eq 0 -and $recording.SoundRequested -and -not $recording.AudioCaptured -and (Get-FileHash $recording.Video).Hash -eq $recording.VideoSha256)
    $controlled=Read-Report audio-host-controls
    foreach($entry in @(@{Name='Headless controls';Report=$controlled},@{Name='Recorded Matrix';Report=$captured})){
        $r=$entry.Report;$a=$r.Simulation.Audio
        Check "$($entry.Name) complete game route" ($null -eq $r.Error -and $r.ExitReason -eq 'ReplayEnd' -and $r.SimulationTics -eq 1747 -and $r.ReplayVerification.Matched -and $r.ReplayVerification.Checked -eq 8)
        Check "$($entry.Name) exact submitted PCM" ($a.PcmSha256 -eq $rawHash -and $a.Packets -eq 1747 -and $a.StalePacketsDiscarded -eq 0 -and $a.UnconsumedPackets -eq 0)
        Check "$($entry.Name) device completion and cleanup" ($null -eq $a.Error -and $null -eq $a.CleanupError -and $a.DeviceClosed -and $a.ReturnedCompletedFrames -eq 2201220 -and $a.SubmittedFrames -eq 2201220)
    }
    Check 'Menu and synthetic resize pause observed' ($controlled.Simulation.Audio.PauseTransitions -eq 2 -and @($controlled.ViewportChanges|Where-Object {-not $_.Fits -and $_.Rows -eq 98}).Count -eq 1)
    foreach($path in $sources){
        if($path -eq 'src/AudioEvents.ps1'){continue} # Loaded against the real engine in every accepted host.
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$errors)
        Check "Parse $path" ($errors.Count -eq 0)
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();ReferencePcmSha256=$rawHash;
      Sources=@($sources|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path $root $_)).Hash}});
      Reports=@($reports|ForEach-Object {@{Path="results/$_.json";Sha256=(Get-FileHash (Join-Path $root "results/$_.json")).Hash}});
      Recording=@{Metadata=$RecordingPrefix+'-recording.json';MetadataSha256=(Get-FileHash ($RecordingPrefix+'-recording.json')).Hash;Game=$RecordingPrefix+'-game.json';GameSha256=(Get-FileHash ($RecordingPrefix+'-game.json')).Hash};
      Meaning='Current source snapshot and accepted integration evidence. First host/replay reports precede documented corrections. Full submitted-PCM identity is not acoustic latency, waveform loopback or physical listening evidence. Music/volume and full release remain unfinished.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) integration evidence checks."
