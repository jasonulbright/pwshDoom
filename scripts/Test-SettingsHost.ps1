#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',[switch]$Sound)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$directory=Join-Path "$PSScriptRoot/../local" ('settings-host-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
$runtime=(Get-Process -Id $PID).Path;$checks=[Collections.Generic.List[object]]::new();$runs=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Run-SettingsHost([string]$Name,[string]$Settings,[string[]]$Keys,[switch]$Replay){
    $report=Join-Path $directory "$Name-game.json";$schedule=Join-Path $directory "$Name-schedule.json"
    $arguments=@('-NoProfile','-File',"$PSScriptRoot/Invoke-Doom.ps1",'-Wad',$Wad,'-Headless','-Workers','4','-Style','Matrix','-SettingsPath',$Settings,'-Report',$report)
    if($Sound){$arguments+='-Sound'}
    if($Keys.Count){
        $entries=@(for($i=0;$i -lt $Keys.Count;$i++){@{AtSeconds=.5+.35*$i;Key=$Keys[$i]}})
        ConvertTo-Json -InputObject $entries|Set-Content $schedule;$arguments+=@('-SessionSchedule',$schedule)
    }
    if($Replay){$arguments+=@('-Seconds','35','-Replay',"$PSScriptRoot/../results/automap-host-recorded.json")}else{$arguments+=@('-Seconds','1')}
    & $runtime @arguments | Out-Host
    if($LASTEXITCODE -ne 0){throw "$Name host failed; inspect $report"}
    $r=Get-Content $report -Raw|ConvertFrom-Json -AsHashtable
    $runs.Add(@{Name=$Name;Report=$report;Sha256=(Get-FileHash $report).Hash;Arguments=$arguments;InitialSettings=$r.InitialSettings;FinalSettings=$r.FinalSettings;SettingsEvents=$r.SettingsEvents;SettingsLoadError=$r.SettingsLoadError;ReplayVerification=$r.ReplayVerification;SessionEvents=$r.SessionEvents;ExitReason=$r.ExitReason})
    return $r
}
try{
    $settings=Join-Path $directory preferences.json
    # Toggle, change speed, reset, then choose on/150 as the persisted endpoint.
    $r=Run-SettingsHost 'save' $settings @('Escape','Up','Up','Enter','Enter','Down','Right','Down','Down','Down','Enter','Up','Up','Up','Right','Up','Enter','Escape','Escape') -Replay
    Check 'Settings host preserves both gameplay/map checkpoints' ($r.ReplayVerification.Matched -and $r.ReplayVerification.Checked -eq 2)
    Check 'All five edits saved through the real host' ($r.SettingsEvents.Count -eq 5 -and @($r.SettingsEvents|Where-Object {-not $_.Success -or -not $_.Persisted}).Count -eq 0)
    Check 'Final host preferences reflect post-reset choices' ($r.FinalSettings.AlwaysRun -and $r.FinalSettings.TurnSpeed -eq 150)
    Check 'Actual simulation worker acknowledges settings screen' (@($r.SessionEvents|Where-Object {$_.Phase -eq 'Acknowledged' -and $_.MenuScreen -eq 14}).Count -gt 0)
    $r=Run-SettingsHost 'restart' $settings @()
    Check 'Fresh host loads saved preferences' ($r.InitialSettings.AlwaysRun -and $r.InitialSettings.TurnSpeed -eq 150 -and -not $r.SettingsLoadError)
    if($Sound){Check 'Input edits/reset preserve default sound gain' ($r.InitialSettings.SoundVolume -eq 100 -and -not $r.InitialSettings.SoundMuted -and $r.Simulation.Audio.FinalVolume -eq 1 -and $r.Simulation.Audio.DeviceClosed)}
    $invalid=Join-Path $directory invalid.json;[IO.File]::WriteAllText($invalid,'{"Version":900}');$hash=(Get-FileHash $invalid).Hash
    $r=Run-SettingsHost 'invalid' $invalid @('Escape','Up','Up','Enter','Enter','Escape','Escape','Escape') -Replay
    Check 'Malformed existing preferences fall back to defaults' ([bool]$r.SettingsLoadError -and -not $r.InitialSettings.AlwaysRun -and $r.InitialSettings.TurnSpeed -eq 100)
    Check 'Failed save leaves file and active preferences unchanged' ((Get-FileHash $invalid).Hash -ceq $hash -and -not $r.FinalSettings.AlwaysRun -and $r.SettingsEvents.Count -eq 1 -and -not $r.SettingsEvents[0].Success)
    Check 'Save failure reaches recoverable message screen' (@($r.SessionEvents|Where-Object {$_.Phase -eq 'Acknowledged' -and $_.MenuScreen -eq 12}).Count -eq 1)
    Check 'Recovered session reaches replay end with matching checkpoints' ($r.ExitReason -eq 'ReplayEnd' -and $r.ReplayVerification.Matched -and $r.ReplayVerification.Checked -eq 2)
    if($Sound){Check 'Settings failure preserves active sound gain and cleanup' ($r.FinalSettings.SoundVolume -eq 100 -and -not $r.FinalSettings.SoundMuted -and $r.Simulation.Audio.FinalVolume -eq 1 -and $r.Simulation.Audio.DeviceClosed)}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Directory=$directory;Runs=$runs.ToArray();HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Three real isolated headless hosts: menu edits/reset/persistence, process restart, and malformed-file/save-failure recovery while preserving replay checkpoints. No user settings file is read or written.'}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Output
}
"PASS: $($checks.Count) settings host checks."
