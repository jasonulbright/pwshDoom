#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/SimulationProcess.ps1";. "$PSScriptRoot/../src/SessionMenu.ps1"
. "$PSScriptRoot/../src/InputReplay.ps1"
Set-StrictMode -Version Latest
$simulation=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new();$actions=[Collections.Generic.List[object]]::new();$tick=0
$saveRoot=Join-Path "$PSScriptRoot/../local" ('save-worker-'+[guid]::NewGuid().ToString('N'));$wadHash=(Get-FileHash $Wad).Hash
$directory=Get-DoomSaveDirectory $saveRoot $wadHash;$snapshot=$null;$reportData=$null
function Assert-Worker([string]$Name,[bool]$Condition){$checks.Add(@{Name=$Name;Passed=$Condition});if(-not $Condition){throw $Name}}
function Snapshot-Hash($Snapshot){return [Convert]::ToBase64String([byte[]][Text.Encoding]::UTF8.GetBytes(($Snapshot.Current|ConvertTo-Json -Compress)))}
function Wait-Boundary {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($simulation.View.ReadInt32(20) -ne $script:tick){if($watch.Elapsed.TotalSeconds -gt 25 -or $simulation.View.ReadInt32(12) -eq 3){throw 'Simulation command boundary failed.'};[Threading.Thread]::Sleep(10)}
    $script:snapshot=Read-DoomSimulationSnapshot $simulation $null
}
function Advance-Commands([int]$Count,[int]$Forward=0){
    for($i=0;$i -lt $Count;$i++){Send-DoomSimulationCommand $simulation $script:tick @($Forward,0,0,0);$script:tick++};Wait-Boundary
}
function Send-Action($Action){
    $sequence=Send-DoomSessionAction $simulation $Action $script:tick;$watch=[Diagnostics.Stopwatch]::StartNew();$generations=[Collections.Generic.List[object]]::new()
    while($simulation.View.ReadInt32(52) -ne $sequence){
        if($watch.Elapsed.TotalSeconds -gt 30 -or $simulation.View.ReadInt32(12) -eq 3){throw 'Simulation session action failed.'}
        if($simulation.View.ReadInt32(12) -eq 4){
            $generation=$simulation.View.ReadInt32(24);$published=Read-DoomSimulationSnapshot $simulation $null
            if($published.Generation -ne $generation){throw 'Asset generation and snapshot differ.'}
            $generations.Add(@{Generation=$generation;Episode=$published.Episode;Map=$published.Map;AssetSha256=(Get-FileHash $simulation.Assets).Hash})
            $simulation.View.Write(28,$generation);[void]$simulation.Go.Set()
        }
        [Threading.Thread]::Sleep(10)
    }
    $script:snapshot=Read-DoomSimulationSnapshot $simulation $null;$reply=Read-DoomSessionPayload $simulation.View 65536
    $actions.Add(@{Action=$Action;Response=$reply;Milliseconds=$watch.Elapsed.TotalMilliseconds;Generations=$generations.ToArray()})
    return $reply
}
function Resume-Game {$null=Send-Action @{Action='ShowMenu';Screen=0;Choice=0;Episode=1;Skill=3}}
try{
    $simulation=New-DoomSimulation $Wad 3 1 1 -ReplayCheckpoints -SaveRoot $saveRoot
    Advance-Commands 35 25;$savedSnapshot=Snapshot-Hash $snapshot
    $reply=Send-Action @{Action='SaveGame';Slot=1;ExpectedHash=$null}
    Assert-Worker 'Empty slot saves and resumes without changing the command index' ($reply.Success -and $snapshot.Tic -eq 35 -and $snapshot.MenuScreen -eq 0)
    $path=Get-DoomSlotPath $directory 1;$originalHash=(Get-FileHash $path).Hash
    Advance-Commands 35 25;$beforeRejectedLoad=Snapshot-Hash $snapshot
    $reply=Send-Action @{Action='LoadGame';Slot=1;ExpectedHash=('A'*64);AllowSourceMismatch=$false}
    Assert-Worker 'Stale load selection shows a recoverable error' (-not $reply.Success -and $reply.Screen -eq 12)
    Resume-Game;Assert-Worker 'Rejected load leaves current numeric game snapshot intact' ((Snapshot-Hash $snapshot) -ceq $beforeRejectedLoad)
    $reply=Send-Action @{Action='SaveGame';Slot=1;ExpectedHash=('A'*64)}
    Assert-Worker 'Stale save confirmation preserves the prior slot' (-not $reply.Success -and (Get-FileHash $path).Hash -eq $originalHash)
    Resume-Game
    $reply=Send-Action @{Action='NewGame';Skill=3;Episode=2;Map=1}
    Assert-Worker 'Different episode installs generation two' ($reply.Success -and $snapshot.Episode -eq 2 -and $snapshot.Generation -eq 2)
    $reply=Send-Action @{Action='LoadGame';Slot=1;ExpectedHash=$originalHash;AllowSourceMismatch=$false}
    Assert-Worker 'Slot load restores E1M1 at the monotonic input boundary' ($reply.Success -and $snapshot.Episode -eq 1 -and $snapshot.Generation -eq 3 -and $snapshot.Tic -eq 70)
    Assert-Worker 'Loaded numeric state equals the earlier saved state' ((Snapshot-Hash $snapshot) -ceq $savedSnapshot)
    $archive=Get-DoomReplaySavePath $directory $originalHash
    Assert-Worker 'Load archives the exact selected bytes for replay' ((Get-FileHash $archive).Hash -eq $originalHash)
    Advance-Commands 7
    $reply=Send-Action @{Action='SaveGame';Slot=1;ExpectedHash=$originalHash};$newHash=(Get-FileHash $path).Hash
    Assert-Worker 'Confirmed replacement creates a changed save' ($reply.Success -and $newHash -ne $originalHash)
    $backups=@(Get-ChildItem -LiteralPath $directory -Filter 'slot-01.pds.*.bak')
    Assert-Worker 'Replacement retains exact previous save as backup' ($backups.Count -eq 1 -and (Get-FileHash $backups[0].FullName).Hash -eq $originalHash)
    $reply=Send-Action @{Action='LoadGame';SaveHash=$originalHash}
    Assert-Worker 'Replay load restores the old state after slot overwrite' ($reply.Success -and $snapshot.Tic -eq 77 -and $snapshot.Generation -eq 4 -and (Snapshot-Hash $snapshot) -ceq $savedSnapshot)
    Assert-Worker 'Replay load does not modify the slot' ((Get-FileHash $path).Hash -eq $newHash)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($null -ne $simulation){Close-DoomSimulation $simulation;if(Test-Path $simulation.Report){$reportData=Get-Content $simulation.Report -Raw|ConvertFrom-Json}}
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Actions=$actions.ToArray();Simulation=$reportData;SaveRoot=$saveRoot;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Actual simulation process and bounded session IPC. Numeric snapshots, command indices, asset generation handshake, failed candidate isolation, atomic replacement/backup and immutable replay saves. Rendering workers and live menus are qualified separately.'}|ConvertTo-Json -Depth 12|Set-Content $Output
}
"PASS: $($checks.Count) save worker checks."
