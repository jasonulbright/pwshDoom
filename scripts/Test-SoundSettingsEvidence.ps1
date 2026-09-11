#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$failure=$null;$named=0
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Read-Report([string]$Name){Get-Content (Join-Path $root "results/$Name.json") -Raw|ConvertFrom-Json}
$sources=@('src/UserSettings.ps1','src/SessionMenu.ps1','src/SimulationProcess.ps1','src/AudioRunspace.ps1','scripts/Invoke-Doom.ps1','scripts/Invoke-SimulationWorker.ps1','scripts/Invoke-AudioWorker.ps1','scripts/Render-AudioReplay.ps1','scripts/Test-UserSettings.ps1','scripts/Test-SessionMenu.ps1','scripts/Test-SettingsHost.ps1','scripts/Test-AudioVolume.ps1','scripts/Test-SoundSettingsHost.ps1','scripts/Test-SoundSettingsEvidence.ps1')
$reports=@('sound-settings-unit','sound-settings-menus','sound-settings-menus-fit','sound-volume-worker','sound-settings-host','sound-settings-audio-replay','sound-settings-recovery','sound-settings-recording')
try{
    foreach($name in 'sound-settings-unit','sound-settings-menus-fit','sound-volume-worker','sound-settings-host','sound-settings-recovery'){
        $r=Read-Report $name;Check "$name named checks pass" ($null -eq $r.Error -and @($r.Checks|Where-Object {-not $_.Passed}).Count -eq 0);$named+=$r.Checks.Count
    }
    Check '207 accepted named checks' ($named -eq 207)
    $hostResult=Read-Report sound-settings-host;$offline=Read-Report sound-settings-audio-replay
    Check 'Offline audio replay retains all checkpoints' ($null -eq $offline.Error -and $offline.CheckpointComparison.Matched -and $offline.CheckpointComparison.Checked -eq 8)
    $wave=[IO.File]::ReadAllBytes($offline.Wave);Check 'Derived WAV matches retained hash' ((Get-FileHash $offline.Wave).Hash -eq $offline.WaveSha256)
    $pcm=[byte[]]::new($wave.Length-44);[Array]::Copy($wave,44,$pcm,0,$pcm.Length)
    Check 'Whole submitted PCM matches volume-controlled offline replay' ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($pcm)) -eq $hostResult.Game.Audio.PcmSha256)
    $recording=Read-Report sound-settings-recording
    Check 'Successful recorded controls with eight gameplay checkpoints' ($null -eq $recording.Recording.Error -and $recording.Game.ReplayVerification.Matched -and $recording.Game.ReplayVerification.Checked -eq 8 -and $recording.Game.SettingsEvents.Count -eq 6 -and @($recording.Game.SettingsEvents|Where-Object {-not $_.Success}).Count -eq 0)
    Check 'Recorded audio worker closes; video explicitly has no captured audio' ($recording.Game.Audio.DeviceClosed -and $null -eq $recording.Game.Audio.Error -and -not $recording.Recording.AudioCaptured)
    Check 'Original and viewing copy retain recorded hashes' ((Get-FileHash $recording.Recording.Video).Hash -eq $recording.Recording.VideoSha256 -and (Get-FileHash $recording.ViewingCopy.Output).Hash -eq $recording.ViewingCopy.OutputSha256)
    foreach($path in $sources){$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$errors);Check "Parse $path" ($errors.Count -eq 0)}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();AcceptedNamedChecks=$named;
      Sources=@($sources|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path $root $_)).Hash}});
      Reports=@($reports|ForEach-Object {@{Path="results/$_.json";Sha256=(Get-FileHash (Join-Path $root "results/$_.json")).Hash}});
      Meaning='Current source/evidence audit for persistent sound volume and mute. Failed first menu report retained separately. Submitted PCM includes subsequently cancelled device tails; no acoustic latency, physical keyboard or full release qualification.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) evidence checks; $named accepted named checks."
