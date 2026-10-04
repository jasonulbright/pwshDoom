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
    Check 'Missing settings returns defaults without writing a file' (-not (Test-Path $path) -and -not $read.Values.AlwaysRun -and $read.Values.TurnSpeed -eq 100 -and $read.Values.MusicVolume -eq 100 -and $read.Values.GammaLevel -eq 2 -and $null -eq $read.Sha256)
    $values=$read.Values;$copy=Copy-DoomUserSettings $values;$copy.AlwaysRun=$true;$copy.TurnSpeed=150;$copy.Bindings.Forward=82
    Check 'Copy does not alias live preferences' (-not $values.AlwaysRun -and $values.TurnSpeed -eq 100)
    $hash=Write-DoomUserSettings $path $copy $null;$read=Read-DoomUserSettings $path
    Check 'File round trip retains typed preferences, gamma, custom keys and exact byte hash' ($read.Values.AlwaysRun -and $read.Values.TurnSpeed -eq 150 -and $read.Values.MusicVolume -eq 100 -and $read.Values.GammaLevel -eq 2 -and $read.Values.Bindings.Forward -eq 82 -and $read.Sha256 -ceq $hash -and $hash -ceq (Get-FileHash $path).Hash)
    $wire=$copy|ConvertTo-Json|ConvertFrom-Json;$wireCopy=Copy-DoomUserSettings $wire
    Check 'Menu IPC object preserves typed preferences' ($wireCopy.AlwaysRun -and $wireCopy.TurnSpeed -eq 150)
    $legacy=Join-Path $directory legacy.json;[IO.File]::WriteAllText($legacy,'{"Version":1,"AlwaysRun":true,"TurnSpeed":150}');$legacyHash=(Get-FileHash $legacy).Hash
    $migrated=Read-DoomUserSettings $legacy
    Check 'Version-one preferences migrate in memory without rewriting user file' ($migrated.Values.Version -eq 5 -and $migrated.Values.AlwaysRun -and $migrated.Values.SoundVolume -eq 100 -and $migrated.Values.MusicVolume -eq 100 -and $migrated.Values.GammaLevel -eq 2 -and $migrated.Values.Bindings.Forward -eq 87 -and -not $migrated.Values.SoundMuted -and (Get-FileHash $legacy).Hash -eq $legacyHash)
    $migrated.Values.SoundVolume=40;$migrated.Values.SoundMuted=$true;$null=Write-DoomUserSettings $legacy $migrated.Values $legacyHash
    $soundRead=Read-DoomUserSettings $legacy
    Check 'Sound gain and mute persist alongside default keys' ($soundRead.Values.SoundVolume -eq 40 -and $soundRead.Values.SoundMuted -and (Get-Content $legacy -Raw|ConvertFrom-Json).Version -eq 5)
    $legacyV2=Join-Path $directory legacy-v2.json;[IO.File]::WriteAllText($legacyV2,'{"Version":2,"AlwaysRun":false,"TurnSpeed":100,"SoundVolume":40,"SoundMuted":true}');$legacyV2Hash=(Get-FileHash $legacyV2).Hash
    $migratedV2=Read-DoomUserSettings $legacyV2
    Check 'Version-two gain migrates to both levels without rewrite' ($migratedV2.Values.Version -eq 5 -and $migratedV2.Values.SoundVolume -eq 40 -and $migratedV2.Values.MusicVolume -eq 40 -and $migratedV2.Values.GammaLevel -eq 2 -and (Get-FileHash $legacyV2).Hash -eq $legacyV2Hash)
    $migratedV2.Values.MusicVolume=70;$null=Write-DoomUserSettings $legacyV2 $migratedV2.Values $legacyV2Hash;$independent=Read-DoomUserSettings $legacyV2
    Check 'Effects and music levels persist independently' ($independent.Values.SoundVolume -eq 40 -and $independent.Values.MusicVolume -eq 70 -and $independent.Values.SoundMuted)
    $legacyV4=Join-Path $directory legacy-v4.json;$legacyV4Json='{"Version":4,"AlwaysRun":false,"TurnSpeed":100,"SoundVolume":100,"MusicVolume":100,"SoundMuted":false,"Bindings":{"Forward":87,"Backward":83,"StrafeLeft":65,"StrafeRight":68,"TurnLeft":37,"TurnRight":39,"Fire":17,"Use":69,"Run":16}}';[IO.File]::WriteAllText($legacyV4,$legacyV4Json);$legacyV4Hash=(Get-FileHash $legacyV4).Hash
    $migratedV4=Read-DoomUserSettings $legacyV4
    Check 'Version-four key preferences gain default gamma in memory without rewrite' ($migratedV4.Values.Version -eq 5 -and $migratedV4.Values.GammaLevel -eq 2 -and $migratedV4.Values.Bindings.Forward -eq 87 -and (Get-FileHash $legacyV4).Hash -ceq $legacyV4Hash)
    foreach($badVolume in -1,101,'50',50.5,$true){$invalid=New-DoomUserSettings;$invalid.SoundVolume=$badVolume;$rejected=$false;try{$null=Copy-DoomUserSettings $invalid}catch{$rejected=$true};Check "Reject invalid sound volume $badVolume" $rejected}
    $invalid=New-DoomUserSettings;$invalid.Bindings.Fire=$invalid.Bindings.Forward;$rejected=$false;try{$null=Copy-DoomUserSettings $invalid}catch{$rejected=$true};Check 'Reject conflicting persisted game keys' $rejected
    foreach($badVolume in -1,101,'50',50.5,$true){$invalid=New-DoomUserSettings;$invalid.MusicVolume=$badVolume;$rejected=$false;try{$null=Copy-DoomUserSettings $invalid}catch{$rejected=$true};Check "Reject invalid music volume $badVolume" $rejected}
    foreach($badGamma in -1,11,'2',2.5,$true){$invalid=New-DoomUserSettings;$invalid.GammaLevel=$badGamma;$rejected=$false;try{$null=Copy-DoomUserSettings $invalid}catch{$rejected=$true};Check "Reject invalid gamma level $badGamma" $rejected}
    $invalid=New-DoomUserSettings;$invalid.SoundMuted='false';$rejected=$false;try{$null=Copy-DoomUserSettings $invalid}catch{$rejected=$true};Check 'Reject string mute value' $rejected
    $aliasCollision=New-DoomUserSettings;$aliasCollision.Version=4;$aliasCollision.Remove('GammaLevel');$aliasCollision.Bindings.Forward=32;$compatible=Copy-DoomUserSettings $aliasCollision
    Check 'Migrate version-four Space movement binding with default gamma' ($compatible.Bindings.Forward -eq 32 -and $compatible.Version -eq 5 -and $compatible.GammaLevel -eq 2)
    $hash2=Write-DoomUserSettings $path $values $hash;$rejected=$false
    try{$null=Write-DoomUserSettings $path $copy $hash}catch{$rejected=$true}
    Check 'Stale writer rejected without changing newer file' ($rejected -and (Get-FileHash $path).Hash -ceq $hash2)
    $cases=@('{','null','[]','{"Version":2,"AlwaysRun":false,"TurnSpeed":100}','{"Version":3,"AlwaysRun":false,"TurnSpeed":100,"SoundVolume":100,"SoundMuted":false}', '{"Version":1,"AlwaysRun":"false","TurnSpeed":100}',
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
    $null=Invoke-DoomMenuKey $menu Down;$action=Invoke-DoomMenuKey $menu Left
    Check 'Volume steps down by ten percent' ($menu.Settings.SoundVolume -eq 90 -and $action.SettingsChanged)
    for($i=0;$i -lt 12;$i++){$null=Invoke-DoomMenuKey $menu Left};$action=Invoke-DoomMenuKey $menu Left
    Check 'Volume clamps to zero without redundant persistence' ($menu.Settings.SoundVolume -eq 0 -and -not $action.SettingsChanged)
    for($i=0;$i -lt 12;$i++){$null=Invoke-DoomMenuKey $menu Right};Check 'Volume clamps to one hundred' ($menu.Settings.SoundVolume -eq 100)
    $null=Invoke-DoomMenuKey $menu Down;$action=Invoke-DoomMenuKey $menu Left
    Check 'Music volume steps down independently' ($menu.Settings.MusicVolume -eq 90 -and $action.SettingsChanged -and $menu.Settings.SoundVolume -eq 100)
    for($i=0;$i -lt 12;$i++){$null=Invoke-DoomMenuKey $menu Left};$action=Invoke-DoomMenuKey $menu Left
    Check 'Music volume clamps to zero without redundant persistence' ($menu.Settings.MusicVolume -eq 0 -and -not $action.SettingsChanged)
    for($i=0;$i -lt 12;$i++){$null=Invoke-DoomMenuKey $menu Right};Check 'Music volume clamps to one hundred' ($menu.Settings.MusicVolume -eq 100)
    $null=Invoke-DoomMenuKey $menu Down;$null=Invoke-DoomMenuKey $menu Enter
    Check 'Mute effects keeps independent levels' ($menu.Settings.SoundMuted -and $menu.Settings.SoundVolume -eq 100 -and $menu.Settings.MusicVolume -eq 100)
    $null=Invoke-DoomMenuKey $menu Down;$action=Invoke-DoomMenuKey $menu Left
    Check 'Gamma level changes and requests persistence' ($menu.Settings.GammaLevel -eq 1 -and $action.SettingsChanged)
    $null=Invoke-DoomMenuKey $menu Right;Check 'Gamma level returns to its saved default' ($menu.Settings.GammaLevel -eq 2)
    $null=Invoke-DoomMenuKey $menu Down;$action=Invoke-DoomMenuKey $menu Enter
    Check 'Settings opens the key configuration screen' ($menu.Screen -eq 15 -and -not $action.SettingsChanged)
    $null=Invoke-DoomMenuKey $menu Enter;Check 'Selected action enters key capture mode' $menu.AwaitingBinding
    $action=Invoke-DoomMenuKey $menu Capture -CaptureVirtualKey 82
    Check 'Captured key remaps Forward and requests persistence' ($menu.Settings.Bindings.Forward -eq 82 -and $action.SettingsChanged -and -not $menu.AwaitingBinding)
    $null=Invoke-DoomMenuKey $menu Enter;$action=Invoke-DoomMenuKey $menu Capture -CaptureVirtualKey 68
    Check 'Conflicting key leaves both actions unchanged' ($menu.Settings.Bindings.Forward -eq 82 -and $menu.Settings.Bindings.StrafeRight -eq 68 -and -not $action.SettingsChanged)
    $null=Invoke-DoomMenuKey $menu Enter;$action=Invoke-DoomMenuKey $menu Capture -CaptureVirtualKey 80
    Check 'Pause key remains reserved' ($menu.Settings.Bindings.Forward -eq 82 -and -not $action.SettingsChanged -and $menu.MessageTitle -eq 'KEY NOT AVAILABLE')
    $f11Menu=New-DoomMenuState;$f11Menu.Screen=15;$f11Menu.Choice=0;$f11Menu.AwaitingBinding=$true
    $action=Invoke-DoomMenuKey $f11Menu Capture -CaptureVirtualKey 122
    Check 'F11 stays reserved for gamma controls' (-not $action.SettingsChanged -and $f11Menu.MessageTitle -eq 'KEY NOT AVAILABLE')
    $aliasMenu=New-DoomMenuState;$aliasMenu.Screen=15;$aliasMenu.Choice=0;$aliasMenu.AwaitingBinding=$true
    $action=Invoke-DoomMenuKey $aliasMenu Capture -CaptureVirtualKey 32
    Check 'Allow Space as a custom movement binding' ($aliasMenu.Settings.Bindings.Forward -eq 32 -and $action.SettingsChanged -and $aliasMenu.MessageTitle -eq 'KEY ASSIGNED')
    $runMenu=New-DoomMenuState;$runMenu.Screen=15;$runMenu.Choice=8;$runMenu.AwaitingBinding=$true
    $action=Invoke-DoomMenuKey $runMenu Capture -CaptureVirtualKey 16
    Check 'Keep Shift as the Run binding' ($runMenu.Settings.Bindings.Run -eq 16 -and -not $action.SettingsChanged -and $runMenu.MessageTitle -eq 'KEY ASSIGNED')
    $null=Invoke-DoomMenuKey $menu Escape
    Check 'Key screen returns to settings' ($menu.Screen -eq 14 -and $menu.Choice -eq 6)
    $null=Invoke-DoomMenuKey $menu Down;$action=Invoke-DoomMenuKey $menu Enter
    Check 'Reset restores keyboard and gameplay option defaults' (-not $menu.Settings.AlwaysRun -and $menu.Settings.TurnSpeed -eq 100 -and $menu.Settings.Bindings.Forward -eq 87 -and $action.SettingsChanged)
    Check 'Reset also restores independent audio and gamma defaults' ($menu.Settings.SoundVolume -eq 100 -and $menu.Settings.MusicVolume -eq 100 -and -not $menu.Settings.SoundMuted -and $menu.Settings.GammaLevel -eq 2)
    $null=Invoke-DoomMenuKey $menu Down;$action=Invoke-DoomMenuKey $menu Enter
    Check 'Back returns to selected settings item' ($menu.Screen -eq 1 -and $menu.Choice -eq 5 -and -not $action.SettingsChanged)
    $gammaShortcut=New-DoomMenuState;$action=Invoke-DoomMenuKey $gammaShortcut F11
    Check 'F11 advances and persists the gamma level during play' ($gammaShortcut.Settings.GammaLevel -eq 3 -and $action.SettingsChanged)
    for($i=0;$i -lt 8;$i++){$action=Invoke-DoomMenuKey $gammaShortcut F11}
    Check 'F11 wraps gamma correction through all eleven levels' ($gammaShortcut.Settings.GammaLevel -eq 0 -and $action.SettingsChanged)
    $state=@{Keys=[bool[]]::new(256);Pressed=[bool[]]::new(256);Suppressed=[bool[]]::new(256)};$cmd=[SettingsTestCommand]::new()
    $custom=New-DoomKeyBindings;$custom.Forward=82;$state.Keys[82]=$true;Set-DoomInputCommand $state $cmd -Bindings $custom
    Check 'Custom key reaches gameplay command generation' ($cmd.ForwardMove -eq 25)
    $aliasState=@{Keys=[bool[]]::new(256);Pressed=[bool[]]::new(256);Suppressed=[bool[]]::new(256)};$aliasCommand=[SettingsTestCommand]::new()
    $aliasState.Keys[32]=$true;$spaceBindings=New-DoomKeyBindings;$spaceBindings.Forward=32
    Set-DoomInputCommand $aliasState $aliasCommand -Bindings $spaceBindings
    Check 'Custom Space movement does not also invoke Use' ($aliasCommand.ForwardMove -eq 25 -and ($aliasCommand.Buttons -band 2) -eq 0)
    [Array]::Clear($aliasState.Keys);$aliasState.Keys[87]=$true;$aliasState.Keys[16]=$true
    $shiftBindings=New-DoomKeyBindings;$shiftBindings.Fire=16;$shiftBindings.Run=82
    Set-DoomInputCommand $aliasState $aliasCommand -Bindings $shiftBindings
    Check 'Custom Shift fire does not also activate the Run alias' ($aliasCommand.ForwardMove -eq 25 -and ($aliasCommand.Buttons -band 1) -ne 0)
    $state.Keys[82]=$false
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
