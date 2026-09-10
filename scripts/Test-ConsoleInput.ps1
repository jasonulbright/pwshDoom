#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/ConsoleInput.ps1"
Initialize-DoomConsoleApi
class InputTestCommand {
    [sbyte]$ForwardMove;[sbyte]$SideMove;[int16]$AngleTurn;[byte]$Buttons
    [void]Clear(){$this.ForwardMove=0;$this.SideMove=0;$this.AngleTurn=0;$this.Buttons=0}
}
$state=@{Keys=[bool[]]::new(256);Pressed=[bool[]]::new(256)};$command=[InputTestCommand]::new();$checks=0
function Send-TestKey([int]$Key,[bool]$Down,[int]$Type=1) {
    $records=[PwshDoomPlatform.InputRecord[]]::new(1)
    $record=[PwshDoomPlatform.InputRecord]::new();$record.EventType=$Type;$record.VirtualKey=$Key;$record.KeyDown=[int]$Down;$records[0]=$record
    Update-DoomInputRecords $state $records 1
}
if([Runtime.InteropServices.Marshal]::SizeOf([type][PwshDoomPlatform.InputRecord]) -ne 20){throw 'INPUT_RECORD size mismatch.'}
foreach($entry in @{EventType=0;KeyDown=4;Repeat=8;VirtualKey=10;ScanCode=12;Character=14;ControlState=16}.GetEnumerator()) {
    if([Runtime.InteropServices.Marshal]::OffsetOf([type][PwshDoomPlatform.InputRecord],$entry.Key).ToInt32() -ne $entry.Value){throw "Bad native field offset: $($entry.Key)"}
}
$checks++
Send-TestKey 87 $true;Send-TestKey 17 $true;Set-DoomInputCommand $state $command
if($command.ForwardMove -ne 25 -or $command.Buttons -ne 1){throw 'Simultaneous forward/fire failed.'};$checks++
Send-TestKey 87 $false;Set-DoomInputCommand $state $command
if($command.ForwardMove -ne 0 -or $command.Buttons -ne 1){throw 'Independent key release failed.'};$checks++
Send-TestKey 17 $false;Send-TestKey 69 $true;Send-TestKey 69 $false;Set-DoomInputCommand $state $command
if($command.Buttons -ne 2){throw 'A quick use press was lost.'};$checks++
Send-TestKey 51 $true;Set-DoomInputCommand $state $command
if($command.Buttons -ne 20){throw 'Weapon selection command failed.'};$checks++
Send-TestKey 87 $true;Send-TestKey 0 $false 16;Set-DoomInputCommand $state $command
if($command.ForwardMove -ne 0 -or $command.Buttons -ne 0){throw 'Focus loss did not clear held/pressed keys.'};$checks++
"PASS: $checks console structure and input-state checks (synthetic records; no desktop input injected)."
