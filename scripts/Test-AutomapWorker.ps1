#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Choose a fresh report path.'}
. "$PSScriptRoot/../src/SimulationProcess.ps1";. "$PSScriptRoot/../src/SessionMenu.ps1"
Set-StrictMode -Version Latest
$simulation=$null;$snapshot=$null;$tick=0;$failure=$null;$checks=[Collections.Generic.List[object]]::new();$report=$null
$saveRoot=Join-Path "$PSScriptRoot/../local" ('automap-worker-'+[guid]::NewGuid().ToString('N'))
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Wait-Command {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($simulation.View.ReadInt32(20) -ne $script:tick){if($watch.Elapsed.TotalSeconds -gt 25 -or $simulation.View.ReadInt32(12) -eq 3){throw 'Command failed.'};[Threading.Thread]::Sleep(5)}
    $script:snapshot=Read-DoomSimulationSnapshot $simulation $null
}
function Command([int]$Mask=0){Send-DoomSimulationCommand $simulation $script:tick @(0,0,0,0) -AutomapMask $Mask;$script:tick++;Wait-Command}
function Action($Request){
    $sequence=Send-DoomSessionAction $simulation $Request $script:tick;$watch=[Diagnostics.Stopwatch]::StartNew()
    while($simulation.View.ReadInt32(52) -ne $sequence){
        if($watch.Elapsed.TotalSeconds -gt 30 -or $simulation.View.ReadInt32(12) -eq 3){throw 'Session action failed.'}
        if($simulation.View.ReadInt32(12) -eq 4){$simulation.View.Write(28,$simulation.View.ReadInt32(24));[void]$simulation.Go.Set()}
        [Threading.Thread]::Sleep(5)
    }
    $script:snapshot=Read-DoomSimulationSnapshot $simulation $null
    $reply=Read-DoomSessionPayload $simulation.View 65536
    if(-not $reply.Success){throw $reply.Error}
}
function PixelsHash {return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($snapshot.Pixels))}
try{
    $simulation=New-DoomSimulation $Wad 3 1 1 -ReplayCheckpoints -SaveRoot $saveRoot
    $snapshot=Read-DoomSimulationSnapshot $simulation $null;Check 'Initial snapshot remains numeric world' ($snapshot.ScreenKind -eq 0 -and -not $snapshot.AutomapVisible)
    Command 1;Check 'Tab publishes map pixels at consumed command boundary' ($snapshot.Tic -eq 1 -and $snapshot.ScreenKind -eq 3 -and $snapshot.AutomapVisible -and $snapshot.Pixels.Length -eq 64000)
    Command 2;Command (128+16);Command 4;Command 0;$savedPixels=PixelsHash
    Action @{Action='SaveGame';Slot=1;ExpectedHash=$null}
    Check 'Save resumes the map without changing its pixels' ($snapshot.ScreenKind -eq 3 -and (PixelsHash) -eq $savedPixels)
    $directory=Get-DoomSaveDirectory $saveRoot (Get-FileHash $Wad).Hash;$saveHash=(Get-FileHash (Get-DoomSlotPath $directory 1)).Hash
    Command (64+32);Command 8;Command 1;Check 'Tab returns to numeric rendering' ($snapshot.ScreenKind -eq 0 -and -not $snapshot.AutomapVisible)
    Action @{Action='LoadGame';Slot=1;ExpectedHash=$saveHash;AllowSourceMismatch=$false}
    Check 'Load installs map pixels with a new asset generation' ($snapshot.Generation -eq 2 -and $snapshot.ScreenKind -eq 3 -and $snapshot.AutomapVisible -and (PixelsHash) -eq $savedPixels)
    Action @{Action='ShowMenu';Screen=1;Choice=0;Episode=1;Skill=3}
    Check 'Menu covers map but retains map visibility metadata' ($snapshot.ScreenKind -eq 2 -and $snapshot.AutomapVisible)
    Action @{Action='ShowMenu';Screen=0;Choice=0;Episode=1;Skill=3}
    Check 'Resume restores unchanged map pixels' ($snapshot.ScreenKind -eq 3 -and (PixelsHash) -eq $savedPixels)
    Command 0;Command 1
    Action @{Action='NewGame';Skill=3;Episode=2;Map=1}
    Check 'New game resets automap visibility' ($snapshot.Generation -eq 3 -and $snapshot.ScreenKind -eq 0 -and -not $snapshot.AutomapVisible)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($null -ne $simulation){Close-DoomSimulation $simulation;if(Test-Path $simulation.Report){$report=Get-Content $simulation.Report -Raw|ConvertFrom-Json}}
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Simulation=$report;SaveRoot=$saveRoot;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Actual simulation worker, map command ring, bitmap snapshot, save/menu/load/new-game boundaries. No presentation worker or display pacing claim.'}|ConvertTo-Json -Depth 12|Set-Content $Output
}
"PASS: $($checks.Count) automap worker checks."
