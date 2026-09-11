#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$directory=Join-Path "$PSScriptRoot/../local" ('sound-settings-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
$settings=Join-Path $directory settings.json;$schedule=Join-Path $directory schedule.json;$gamePath=Join-Path $directory game.json;$restartPath=Join-Path $directory restart.json
$runtime=(Get-Process -Id $PID).Path;$checks=[Collections.Generic.List[object]]::new();$failure=$null;$game=$null;$restart=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $keys=[Collections.Generic.List[object]]::new()
    foreach($sequence in @(@{Start=12;Keys=@('Escape','Up','Up','Enter','Down','Down','Left','Left','Left','Down','Enter','Escape','Escape')},@{Start=18;Keys=@('Escape','Up','Up','Enter','Down','Down','Down','Enter','Escape','Escape')},@{Start=25;Keys=@('Escape','Up','Up','Enter','Down','Down','Down','Enter','Escape','Escape')})){
        for($i=0;$i -lt $sequence.Keys.Count;$i++){$keys.Add(@{AtSeconds=$sequence.Start+.25*$i;Key=$sequence.Keys[$i]})}
    }
    ConvertTo-Json -InputObject $keys.ToArray()|Set-Content $schedule
    & $runtime -NoProfile -File "$PSScriptRoot/Invoke-Doom.ps1" -Wad $Wad -Sound -Headless -Replay "$PSScriptRoot/../results/input-session-replay.json" -SessionSchedule $schedule -SettingsPath $settings -Seconds 90 -Report $gamePath|Out-Host
    if($LASTEXITCODE -ne 0){throw "Host failed; inspect $gamePath"}
    $game=Get-Content $gamePath -Raw|ConvertFrom-Json
    Check 'Full route and all eight checkpoints preserved' ($game.ExitReason -eq 'ReplayEnd' -and $game.ReplayVerification.Matched -and $game.ReplayVerification.Checked -eq 8)
    Check 'Six settings changes persisted successfully' ($game.SettingsEvents.Count -eq 6 -and @($game.SettingsEvents|Where-Object {-not $_.Success -or -not $_.Persisted}).Count -eq 0)
    Check 'Sound volume and mute finish at independently chosen values' ($game.FinalSettings.SoundVolume -eq 70 -and $game.FinalSettings.SoundMuted)
    $a=$game.Simulation.Audio
    Check 'Worker applies each effective volume including mute/unmute' (($a.VolumeChanges.Volume -join ',') -eq '0.9,0.8,0.7,0,0.7,0' -and $a.MutedPackets -gt 0 -and $a.FinalVolume -eq 0)
    Check 'Audio consumes full packet stream and closes' ($a.Packets -eq 1747 -and $null -eq $a.Error -and $null -eq $a.CleanupError -and $a.DeviceClosed)
    & $runtime -NoProfile -File "$PSScriptRoot/Invoke-Doom.ps1" -Wad $Wad -Sound -Headless -Workers 4 -SettingsPath $settings -Seconds 1 -Report $restartPath|Out-Host
    if($LASTEXITCODE -ne 0){throw "Restart failed; inspect $restartPath"}
    $restart=Get-Content $restartPath -Raw|ConvertFrom-Json
    Check 'Fresh host loads persistent version-two sound preferences' ($restart.InitialSettings.Version -eq 2 -and $restart.InitialSettings.SoundVolume -eq 70 -and $restart.InitialSettings.SoundMuted -and -not $restart.SettingsLoadError)
    Check 'Fresh audio worker starts muted and closes' ($restart.Simulation.Audio.FinalVolume -eq 0 -and $restart.Simulation.Audio.MutedPackets -gt 0 -and $restart.Simulation.Audio.DeviceClosed)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Directory=$directory;Settings=$settings;Schedule=$schedule;ScheduleSha256=if(Test-Path $schedule){(Get-FileHash $schedule).Hash}else{$null};
      Game=@{Path=$gamePath;Sha256=if(Test-Path $gamePath){(Get-FileHash $gamePath).Hash}else{$null};Audio=if($game){$game.Simulation.Audio}else{$null};SettingsEvents=if($game){$game.SettingsEvents}else{$null}};
      Restart=@{Path=$restartPath;Sha256=if(Test-Path $restartPath){(Get-FileHash $restartPath).Hash}else{$null};InitialSettings=if($restart){$restart.InitialSettings}else{$null};Audio=if($restart){$restart.Simulation.Audio}else{$null}};
      Sources=@('src/UserSettings.ps1','src/SessionMenu.ps1','src/AudioRunspace.ps1','scripts/Invoke-AudioWorker.ps1','scripts/Invoke-Doom.ps1','scripts/Invoke-SimulationWorker.ps1','scripts/Test-SoundSettingsHost.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
      Meaning='Isolated persistent sound settings through two real hosts. First uses ordinary campaign replay and three menu holds; second verifies process restart. Live device completion is not acoustic timing or human listening evidence.'}|ConvertTo-Json -Depth 10|Set-Content $Output
}
"PASS: $($checks.Count) sound settings host checks."
