#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Output="$PSScriptRoot/../results/menu-input.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Choose a fresh report path.'}
. "$PSScriptRoot/../src/ConsoleInput.ps1";Initialize-DoomConsoleApi
class MenuInputTestCommand {
    [sbyte]$ForwardMove;[sbyte]$SideMove;[int16]$AngleTurn;[byte]$Buttons
    [void]Clear(){$this.ForwardMove=0;$this.SideMove=0;$this.AngleTurn=0;$this.Buttons=0}
}
$checks=[Collections.Generic.List[object]]::new();$state=@{Keys=[bool[]]::new(256);Pressed=[bool[]]::new(256)};$cmd=[MenuInputTestCommand]::new()
function Send-Key([int]$Key,[bool]$Down,[int]$Type=1){
    $record=[PwshDoomPlatform.InputRecord]::new();$record.EventType=$Type;$record.VirtualKey=$Key;$record.KeyDown=[int]$Down
    Update-DoomInputRecords $state ([PwshDoomPlatform.InputRecord[]]@($record)) 1
}
function Reset-ForMenu {
    if(Get-Command Reset-DoomInputForMenu -ErrorAction SilentlyContinue){Reset-DoomInputForMenu $state}
    else{[Array]::Clear($state.Keys);[Array]::Clear($state.Pressed)}
}
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed})}
Send-Key 80 $true;Check 'Pause physical key press is available' $state.Pressed[80]
Reset-ForMenu;Send-Key 80 $true;Check 'Held pause repeat does not toggle again' (-not $state.Pressed[80])
Send-Key 80 $false;Send-Key 80 $true;Check 'Released and repressed pause toggles again' $state.Pressed[80]
Send-Key 80 $false
Send-Key 87 $true;Reset-ForMenu;Send-Key 87 $true;Set-DoomInputCommand $state $cmd
Check 'Held movement remains suppressed after menu' ($cmd.ForwardMove -eq 0)
Send-Key 87 $false;Send-Key 87 $true;Set-DoomInputCommand $state $cmd
Check 'New movement press works after release' ($cmd.ForwardMove -eq 25)
Send-Key 87 $false
Send-Key 13 $true;Reset-ForMenu;Send-Key 13 $true;Set-DoomInputCommand $state $cmd
Check 'Held menu Enter does not leak into use' ($cmd.Buttons -eq 0)
Send-Key 13 $false;Send-Key 13 $true;Set-DoomInputCommand $state $cmd
Check 'A new Enter press can use in gameplay' ($cmd.Buttons -eq 2)
Reset-ForMenu;Send-Key 0 $false 16;Set-DoomInputCommand $state $cmd
Check 'Focus loss clears menu input state' ($cmd.ForwardMove -eq 0 -and $cmd.Buttons -eq 0)
function Read-DoomConsoleInput {param($State) Send-Key 13 $true;Send-Key 13 $false;Send-Key 87 $true}
Reset-DoomInputAfterSessionAction $state;Set-DoomInputCommand $state $cmd
Check 'Completed action drains a queued use tap and masks held movement' ($cmd.Buttons -eq 0 -and $cmd.ForwardMove -eq 0 -and $state.Keys[87])
Send-Key 87 $false;Send-Key 87 $true;Set-DoomInputCommand $state $cmd
Check 'Movement works after releasing a key held during the action' ($cmd.ForwardMove -eq 25)
$failed=@($checks|Where-Object Passed -eq $false).Count
@{FinishedUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks.ToArray();Failures=$failed;SourceSha256=(Get-FileHash "$PSScriptRoot/../src/ConsoleInput.ps1").Hash;
    Meaning='Synthetic native KEY_EVENT records including repeated key-down events. Uses the current menu-reset helper when present, otherwise reproduces the original host reset. No desktop input is injected.'}|ConvertTo-Json -Depth 5|Set-Content $Output
if($failed){throw "$failed menu input checks failed."}
"PASS: $($checks.Count) menu input checks."
