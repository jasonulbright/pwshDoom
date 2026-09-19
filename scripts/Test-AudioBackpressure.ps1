#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[switch]$DrainOnClose,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/SimulationProcess.ps1"
. "$PSScriptRoot/../src/SessionMenu.ps1"
$simulation=$null;$failure=$null;$report=$null
$checks=[Collections.Generic.List[object]]::new();$actions=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Wait-Action([int]$Sequence){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($simulation.View.ReadInt32(52) -ne $Sequence){
        if($watch.Elapsed.TotalSeconds -gt 20 -or $simulation.View.ReadInt32(12) -eq 3){throw 'Bounded control acknowledgement failed.'}
        [Threading.Thread]::Sleep(10)
    }
    $reply=Read-DoomSessionPayload $simulation.View 65536
    $actions.Add(@{Response=$reply;Tic=$simulation.View.ReadInt32(20);WaitMilliseconds=$watch.Elapsed.TotalMilliseconds})
    return $reply
}
try{
    $simulation=New-DoomSimulation $Wad 3 1 1 -Sound
    $simulation.View.Write(84,0);[void]$simulation.Go.Set()
    $sequence=Send-DoomSessionAction $simulation @{Action='ShowMenu';Screen=1;Choice=0;Episode=1;Skill=3} 150
    # Deliberately outrun device playback. Stay below the 1024-command input ring.
    for($i=0;$i -lt 150;$i++){Send-DoomSimulationCommand $simulation $i @(0,0,0,0)}
    $reply=Wait-Action $sequence
    Check 'Menu acknowledges the first burst at its exact boundary' ($reply.Success -and $reply.Screen -eq 1 -and $simulation.View.ReadInt32(20) -eq 150)
    [Threading.Thread]::Sleep(100)
    Check 'Command index remains fixed while no further input is issued' ($simulation.View.ReadInt32(20) -eq 150)
    $sequence=Send-DoomSessionAction $simulation @{Action='ShowMenu';Screen=0;Choice=0;Episode=1;Skill=3} 150
    $reply=Wait-Action $sequence
    Check 'Resume acknowledges without advancing a command' ($reply.Success -and $reply.Screen -eq 0 -and $simulation.View.ReadInt32(20) -eq 150)
    for($i=150;$i -lt 300;$i++){Send-DoomSimulationCommand $simulation $i @(0,0,0,0)}
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($simulation.View.ReadInt32(20) -lt 300){
        if($watch.Elapsed.TotalSeconds -gt 20 -or $simulation.View.ReadInt32(12) -eq 3){throw 'Second burst failed.'}
        [Threading.Thread]::Sleep(10)
    }
    Check 'Second burst reaches the exact final command' ($simulation.View.ReadInt32(20) -eq 300)
    # A bounded tail allows the 31-packet reserve and device buffers to return.
    if(-not $DrainOnClose){[Threading.Thread]::Sleep(2000)}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($null -ne $simulation){Close-DoomSimulation $simulation -DrainAudio:($DrainOnClose -and -not $failure);if(Test-Path $simulation.Report){$report=Get-Content $simulation.Report -Raw|ConvertFrom-Json}}
    if(-not $failure){try{
        Check 'Simulation and audio close without error' (-not $report.Error -and -not $report.Audio.Error -and -not $report.Audio.CleanupError -and $report.Audio.DeviceClosed)
        Check 'Actual queue pressure was exercised and stayed bounded' ($report.AudioBackpressure.Count -gt 0 -and $report.Audio.MaxPacketQueue -eq 31 -and $report.IncompleteAudioBackpressureStartQpc -eq 0)
        Check 'Every ordinary command survives the two bursts unchanged' ($report.InputCommands.Count -eq 300 -and @($report.InputCommands|Where-Object {($_ -join ',') -cne '0,0,0,0'}).Count -eq 0)
        Check 'All ordered audio packets are consumed and returned' ($report.Audio.Packets -eq 300 -and $report.Audio.LastSequence -eq 299 -and $report.Audio.UnconsumedPackets -eq 0 -and $report.Audio.StalePacketsDiscarded -eq 0 -and $report.Audio.SubmittedFrames -eq 378000 -and $report.Audio.ReturnedCompletedFrames -eq 378000 -and $report.Audio.CancelledQueuedFramesUpperBound -eq 0)
        if($DrainOnClose){Check 'Shutdown drains an actually pending queue through the exact final packet' ($report.ShutdownAudioDrain.PendingPacketsBefore -gt 0 -and $report.ShutdownAudioDrain.ThroughSequence -eq 299 -and $report.ShutdownAudioDrain.CompletedFrames -eq 378000)}
    }catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}}
    @{Error=$failure;DrainOnClose=[bool]$DrainOnClose;Checks=$checks.ToArray();Actions=$actions.ToArray();Simulation=$report;WadSha256=(Get-FileHash $Wad).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;WorkerSha256=(Get-FileHash "$PSScriptRoot/Invoke-SimulationWorker.ps1").Hash;Meaning='Two unpaced 150-command bursts through the real simulation and audio device with menu/resume between them. DrainOnClose removes the artificial two-second tail sleep and requests actual bounded shutdown draining. No terminal renderer or live effect window. Bounded-queue/control regression, not a gameplay pacing or physical listening qualification.'}|ConvertTo-Json -Depth 12|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $($checks.Count) audio backpressure checks."
