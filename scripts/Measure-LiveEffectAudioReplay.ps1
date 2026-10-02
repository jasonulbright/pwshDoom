#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Wad,
    [Parameter(Mandatory)][string]$Replay,
    [Parameter(Mandatory)][string]$Prefix,
    [Parameter(Mandatory)][string]$Output,
    [ValidateRange(1,660)][int]$CaptureSeconds=20,
    [ValidateRange(1,100)][int]$SoundVolume=15
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Wad=(Resolve-Path -LiteralPath $Wad).Path;$Replay=(Resolve-Path -LiteralPath $Replay).Path
$Prefix=[IO.Path]::GetFullPath($Prefix);$Output=[IO.Path]::GetFullPath($Output)
$suffixes=@('-game.json','-host-ready.json','-capture-ready.json','-capture-start','-settings.json','-audio.wav','-audio.json')
foreach($path in @($Output)+@($suffixes|ForEach-Object {$Prefix+$_})){if(Test-Path -LiteralPath $path){throw "Use a fresh output path: $path"}}
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Prefix));$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Output))
$gameReport=$Prefix+'-game.json';$hostReady=$Prefix+'-host-ready.json';$captureReady=$Prefix+'-capture-ready.json'
$captureStart=$Prefix+'-capture-start';$settingsPath=$Prefix+'-settings.json';$audioPrefix=$Prefix+'-audio'
$settings=[ordered]@{Version=2;AlwaysRun=$false;TurnSpeed=100;SoundVolume=$SoundVolume;SoundMuted=$false}
[IO.File]::WriteAllText($settingsPath,($settings|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
$owned=[Collections.Generic.List[object]]::new();$checks=[Collections.Generic.List[object]]::new();$failure=$null;$details=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Launch-PowerShell([string[]]$Arguments){
    $runtime=(Get-Process -Id $PID).Path;$psi=[Diagnostics.ProcessStartInfo]::new($runtime)
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.WorkingDirectory=$root
    $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    foreach($argument in $Arguments){$psi.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($psi)
    $entry=[pscustomobject]@{Process=$process;Stdout=$process.StandardOutput.ReadToEndAsync();Stderr=$process.StandardError.ReadToEndAsync()}
    $owned.Add($entry);return $entry
}
function Wait-File([string]$Path,[int]$Seconds,$Owner){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not (Test-Path -LiteralPath $Path)){
        if($Owner -and $Owner.Process.HasExited -and $Owner.Process.ExitCode -ne 0){throw "Owned process failed before publishing $Path`n$($Owner.Stderr.Result)"}
        if($watch.Elapsed.TotalSeconds -ge $Seconds){throw "Timed out waiting for $Path"}
        Start-Sleep -Milliseconds 50
    }
}
try{
    $hostArgs=@('-NoProfile','-File',"$root/scripts/Invoke-Doom.ps1",'-Wad',$Wad,'-Workers','1','-Headless','-RealtimeAudio','-Sound','-Replay',$Replay,
        '-SettingsPath',$settingsPath,'-Report',$gameReport,'-ReadyFile',$hostReady,'-CaptureStartFile',$captureStart)
    $gameHost=Launch-PowerShell $hostArgs
    Wait-File $hostReady 120 $gameHost
    $ready=Get-Content -LiteralPath $hostReady -Raw|ConvertFrom-Json
    if(-not $ready.CaptureGate -or $ready.SimulationPid -le 0){throw 'Headless host did not expose a live simulation capture target.'}
    $captureArgs=@('-NoProfile','-File',"$root/scripts/Record-ProcessAudio.ps1",'-TargetProcessId',"$($ready.SimulationPid)",'-OutputPrefix',$audioPrefix,
        '-Seconds',"$CaptureSeconds",'-ReadyFile',$captureReady)
    $capture=Launch-PowerShell $captureArgs
    Wait-File $captureReady 60 $capture
    $captureReadyData=Get-Content -LiteralPath $captureReady -Raw|ConvertFrom-Json
    if($captureReadyData.TargetProcessId -ne $ready.SimulationPid){throw 'Process-audio recorder targeted a different process.'}
    [IO.File]::WriteAllText($captureStart,'capture-ready',[Text.UTF8Encoding]::new($false))
    if(-not $gameHost.Process.WaitForExit(120000)){throw 'Headless live-effect replay did not finish within two minutes.'}
    if($gameHost.Process.ExitCode -ne 0){throw "Headless live-effect replay failed.`n$($gameHost.Stderr.Result)"}
    if(-not $capture.Process.WaitForExit(($CaptureSeconds+60)*1000)){throw 'Process-audio capture did not finish within its bound.'}
    if($capture.Process.ExitCode -ne 0){throw "Process-audio capture failed.`n$($capture.Stderr.Result)"}

    $game=Get-Content -LiteralPath $gameReport -Raw|ConvertFrom-Json
    $audioCapture=Get-Content -LiteralPath ($audioPrefix+'.json') -Raw|ConvertFrom-Json
    $replayData=Get-Content -LiteralPath $Replay -Raw|ConvertFrom-Json
    $simulation=$game.Simulation;$device=$simulation.Audio
    Check 'Complete captured input replay exits normally' (-not $game.Error -and $game.ExitReason -ceq 'ReplayEnd' -and $simulation.Tics -eq $replayData.InputCommands.Count)
    Check 'Every recorded state checkpoint still matches' ($game.ReplayVerification.Matched -and $game.ReplayVerification.Checked -eq $replayData.Checkpoints.Count)
    Check 'Live PowerShell sound worker schedules effect events' ($simulation.SoundEnabled -and $simulation.AudioEvents -gt 0 -and $device.Realtime)
    Check 'All submitted device frames return and audio shuts down cleanly' (-not $device.Error -and -not $device.CleanupError -and $device.SubmittedFrames -gt 0 -and $device.ReturnedCompletedFrames -eq $device.SubmittedFrames -and $device.DeviceClosed)
    Check 'Process-loopback capture closes for only the simulation process' (-not $audioCapture.Error -and $audioCapture.Closed -and $audioCapture.TargetProcessId -eq $ready.SimulationPid)
    $wav=[IO.File]::ReadAllBytes($audioCapture.WavPath)
    $wavValid=$wav.Length -ge 44
    if($wavValid){
        $wavValid=[Text.Encoding]::ASCII.GetString($wav,0,4) -ceq 'RIFF' -and [Text.Encoding]::ASCII.GetString($wav,8,4) -ceq 'WAVE' -and
            [BitConverter]::ToUInt32($wav,4) -eq ($wav.Length-8) -and [BitConverter]::ToUInt16($wav,20) -eq 1 -and
            [BitConverter]::ToUInt16($wav,22) -eq 2 -and [BitConverter]::ToUInt32($wav,24) -eq 44100 -and
            [BitConverter]::ToUInt16($wav,34) -eq 16 -and [BitConverter]::ToUInt32($wav,40) -eq ($wav.Length-44) -and (($wav.Length-44)%4 -eq 0)
    }
    Check 'Capture is a complete 44.1 kHz stereo PCM16 WAV' $wavValid
    $sampleCount=[int](($wav.Length-44)/2)
    $samples=[int16[]]::new($sampleCount);[Buffer]::BlockCopy($wav,44,$samples,0,$wav.Length-44)
    $nonzero=0L;$peak=0.0;$squares=0.0
    foreach($sample in $samples){$value=[double]$sample;if($value -ne 0){$nonzero++};$peak=[Math]::Max($peak,[Math]::Abs($value));$squares+=$value*$value}
    $rms=if($sampleCount){[Math]::Sqrt($squares/$sampleCount)}else{0.0}
    $frames=[long]($sampleCount/2)
    Check 'Captured process PCM contains non-silent sound effects' ($frames -gt 0 -and $nonzero -gt 0 -and $peak -gt 1 -and $rms -gt 0)
    $sourceFiles=@('scripts/Invoke-Doom.ps1','scripts/Invoke-SimulationWorker.ps1','scripts/Record-ProcessAudio.ps1','src/AudioMixer.ps1','src/AudioEvents.ps1','src/AudioRunspace.ps1','src/ProcessAudioCapture.ps1','src/CaptureClock.ps1')
    $pins=@(foreach($path in $sourceFiles){[pscustomobject]@{Path=$path;Sha256=(Get-FileHash (Join-Path $root $path) -Algorithm SHA256).Hash}})
    $details=[ordered]@{RepositoryCommit=(& git -C $root rev-parse HEAD).Trim();WadSha256=(Get-FileHash $Wad -Algorithm SHA256).Hash;ReplaySha256=(Get-FileHash $Replay -Algorithm SHA256).Hash;
        CommandCount=$simulation.Tics;Checkpoints=$game.ReplayVerification.Checked;AudioEvents=$simulation.AudioEvents;AudioSourcePeak=$simulation.AudioSourcePeak;
        SoundVolume=$SoundVolume;SubmittedFrames=$device.SubmittedFrames;ReturnedCompletedFrames=$device.ReturnedCompletedFrames;DeviceClosed=$device.DeviceClosed;
        CapturedFrames=$frames;CapturedSeconds=$frames/44100.0;NonzeroSamples=$nonzero;PcmPeak=$peak;PcmRms=$rms;PcmSha256=$audioCapture.WavSha256;
        CapturePackets=$audioCapture.Packets.Count;CaptureDiscontinuities=@($audioCapture.Packets|Where-Object {$_.Flags -band 1}).Count;
        HostProcessId=$gameHost.Process.Id;SimulationProcessId=$ready.SimulationPid;CaptureProcessId=$capture.Process.Id;SourcePins=$pins;
        LocalGameReportSha256=(Get-FileHash $gameReport -Algorithm SHA256).Hash;LocalCaptureReportSha256=(Get-FileHash ($audioPrefix+'.json') -Algorithm SHA256).Hash;
        LocalWavPath=$audioCapture.WavPath;Meaning='Headless current-source E3M6 replay with the actual PowerShell sound mixer and Windows output device. Process-tree WASAPI loopback captures mixed PCM without opening a Terminal window. It does not capture video, qualify acoustic identity/listening, or measure normal interactive pacing.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    foreach($entry in $owned){if(-not $entry.Process.HasExited){try{$entry.Process.Kill($true);$entry.Process.WaitForExit(5000)}catch{}}}
    $logs=@(foreach($entry in $owned){@{ProcessId=$entry.Process.Id;ExitCode=if($entry.Process.HasExited){$entry.Process.ExitCode}else{$null};Stdout=if($entry.Stdout.IsCompleted){$entry.Stdout.Result}else{''};Stderr=if($entry.Stderr.IsCompleted){$entry.Stderr.Result}else{''}};$entry.Process.Dispose()})
    $scriptHash=if(Test-Path -LiteralPath $PSCommandPath){(Get-FileHash $PSCommandPath -Algorithm SHA256).Hash}else{$null}
    [ordered]@{Error=$failure;Passed=($null -eq $failure -and $checks.Count -eq 7 -and @($checks|Where-Object {-not $_.Passed}).Count -eq 0);Checks=$checks.ToArray();Details=$details;Logs=$logs;HarnessSha256=$scriptHash;
        Meaning='Source-pinned headless live effect/audio replay. Audio is captured digitally from the simulation process tree with Windows WASAPI loopback. No display recording, microphone/acoustic listening, hardware portability, or normal-display performance claim.'}|
        ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Output -Encoding utf8
}
if($failure){throw $failure}
"PASS: $($checks.Count) headless live-effect audio checks."
