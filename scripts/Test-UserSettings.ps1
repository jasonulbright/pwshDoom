#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/SessionMenu.ps1";. "$PSScriptRoot/../src/ConsoleInput.ps1"
class SettingsTestCommand {
    [sbyte]$ForwardMove;[sbyte]$SideMove;[int16]$AngleTurn;[byte]$Buttons
    [void]Clear(){$this.ForwardMove=0;$this.SideMove=0;$this.AngleTurn=0;$this.Buttons=0}
}
$directory=Join-Path "$PSScriptRoot/../local" ('settings-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory);$path=Join-Path $directory settings.json
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $read=Read-DoomUserSettings $path
    Check 'Missing settings returns defaults without writing a file' (-not (Test-Path $path) -and -not $read.Values.AlwaysRun -and $read.Values.TurnSpeed -eq 100 -and $null -eq $read.Sha256)
    $values=$read.Values;$copy=Copy-DoomUserSettings $values;$copy.AlwaysRun=$true;$copy.TurnSpeed=150
    Check 'Copy does not alias live preferences' (-not $values.AlwaysRun -and $values.TurnSpeed -eq 100)
    $hash=Write-DoomUserSettings $path $copy $null;$read=Read-DoomUserSettings $path
    Check 'File round trip retains typed preferences and exact byte hash' ($read.Values.AlwaysRun -and $read.Values.TurnSpeed -eq 150 -and $read.Sha256 -ceq $hash -and $hash -ceq (Get-FileHash $path).Hash)
    $wire=$copy|ConvertTo-Json|ConvertFrom-Json;$wireCopy=Copy-DoomUserSettings $wire
    Check 'Menu IPC object preserves typed preferences' ($wireCopy.AlwaysRun -and $wireCopy.TurnSpeed -eq 150)
    $hash2=Write-DoomUserSettings $path $values $hash;$rejected=$false
    try{$null=Write-DoomUserSettings $path $copy $hash}catch{$rejected=$true}
    Check 'Stale writer rejected without changing newer file' ($rejected -and (Get-FileHash $path).Hash -ceq $hash2)
    $cases=@('{','null','[]','{"Version":2,"AlwaysRun":false,"TurnSpeed":100}','{"Version":1,"AlwaysRun":"false","TurnSpeed":100}',
        '{"Version":1,"AlwaysRun":false,"TurnSpeed":101}','{"Version":1,"AlwaysRun":false,"TurnSpeed":"100"}',
        '{"Version":1,"AlwaysRun":false}','{"Version":1,"AlwaysRun":false,"TurnSpeed":100,"Extra":0}',(' '*4097))
    for($i=0;$i -lt $cases.Count;$i++){
        $bad=Join-Path $directory "bad-$i.json";[IO.File]::WriteAllText($bad,$cases[$i]);$before=(Get-FileHash $bad).Hash;$rejected=$false
        try{$null=Read-DoomUserSettings $bad}catch{$rejected=$true}
        Check "Invalid file $i rejected" $rejected
        $rejected=$false;try{$null=Write-DoomUserSettings $bad $values $before}catch{$rejected=$true}
        Check "Invalid file $i preserved on attempted save" ($rejected -and (Get-FileHash $bad).Hash -ceq $before)
    }
    Check 'No temporary settings files left' (@(Get-ChildItem $directory -Filter '*.tmp' -Force).Count -eq 0)
    $menu=New-DoomMenuState;foreach($key in 'Escape','Up','Up','Enter'){$action=Invoke-DoomMenuKey $menu $key}
    Check 'Main menu reaches settings' ($menu.Screen -eq 14 -and -not $action.SettingsChanged)
    $action=Invoke-DoomMenuKey $menu Enter;Check 'Always-run toggle is marked for persistence' ($menu.Settings.AlwaysRun -and $action.SettingsChanged)
    $null=Invoke-DoomMenuKey $menu Down;$null=Invoke-DoomMenuKey $menu Right
    Check 'Turn speed moves to 150 percent' ($menu.Settings.TurnSpeed -eq 150)
    $null=Invoke-DoomMenuKey $menu Right;Check 'Turn speed wraps to 50 percent' ($menu.Settings.TurnSpeed -eq 50)
    $null=Invoke-DoomMenuKey $menu Left;Check 'Reverse cycling returns to 150 percent' ($menu.Settings.TurnSpeed -eq 150)
    $null=Invoke-DoomMenuKey $menu Down;$action=Invoke-DoomMenuKey $menu Enter
    Check 'Reset restores both input defaults' (-not $menu.Settings.AlwaysRun -and $menu.Settings.TurnSpeed -eq 100 -and $action.SettingsChanged)
    $null=Invoke-DoomMenuKey $menu Down;$action=Invoke-DoomMenuKey $menu Enter
    Check 'Back returns to selected settings item' ($menu.Screen -eq 1 -and $menu.Choice -eq 5 -and -not $action.SettingsChanged)
    $state=@{Keys=[bool[]]::new(256);Pressed=[bool[]]::new(256);Suppressed=[bool[]]::new(256)};$cmd=[SettingsTestCommand]::new()
    $state.Keys[87]=$true;$state.Keys[68]=$true;$state.Keys[37]=$true
    foreach($always in $false,$true){foreach($shift in $false,$true){foreach($turn in 50,100,150){
        $state.Keys[16]=$shift;Set-DoomInputCommand $state $cmd -AlwaysRun:$always -TurnSpeed $turn
        $run=$always -xor $shift;$forward=if($run){50}else{25};$strafe=if($run){40}else{24};$angle=if($run){1280}else{640}
        Check "Commands always=$always shift=$shift turn=$turn" ($cmd.ForwardMove -eq $forward -and $cmd.SideMove -eq $strafe -and $cmd.AngleTurn -eq $angle*$turn/100)
    }}}
    Set-DoomInputCommand $state $cmd -AlwaysRun -TurnSpeed 150 -AutomapVisible
    Check 'Automap captures turn arrows while preserving configured WASD movement' ($cmd.AngleTurn -eq 0 -and $cmd.ForwardMove -eq 25)
    Reset-DoomInputForMenu $state;Set-DoomInputCommand $state $cmd -AlwaysRun
    Check 'Held movement suppressed after settings menu despite always-run' ($cmd.ForwardMove -eq 0 -and $cmd.SideMove -eq 0 -and $cmd.AngleTurn -eq 0)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Fixtures=$directory;Sources=@('src/UserSettings.ps1','src/SessionMenu.ps1','src/ConsoleInput.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Isolated file validation, typed persistence, stale-edit rejection, menu settings navigation and synthetic command generation. No physical keyboard observation or audio/display settings qualification.'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $Output
}
"PASS: $($checks.Count) input settings checks."
