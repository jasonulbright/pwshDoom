#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Choose a fresh output path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/automap-session-$PID.ps1";. $bundle
. "$PSScriptRoot/../src/AutomapSession.ps1";. "$PSScriptRoot/../src/ConsoleInput.ps1"
. "$PSScriptRoot/../src/SaveState.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1";. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/FrameCodec.ps1"
$checks=[Collections.Generic.List[object]]::new();$samples=[Collections.Generic.List[double]]::new();$failure=$null;$content=$null
$directory=Join-Path "$PSScriptRoot/../local" ('automap-session-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Hash([byte[]]$Bytes){return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $graphics=New-DoomAutomapGraphics $content;$p=$game.World.ConsolePlayer;$am=$game.World.AutoMap
    $graphics.Discovery.DiscoverMap($p)
    Set-DoomAutomapCommand $game 1;$null=$game.Update($commands)
    Check 'Tab opens map without pausing gameplay' ($am.Visible -and -not $game.Paused)
    Set-DoomAutomapCommand $game 2;$null=$game.Update($commands);$x=$am.ViewX.Data
    Set-DoomAutomapCommand $game (16+128);$null=$game.Update($commands)
    Check 'Follow toggle permits right pan and zoom' (-not $am.Follow -and $am.ViewX.Data -gt $x -and $am.Zoom.Data -gt 65536)
    $x=$am.ViewX.Data;$zoom=$am.Zoom.Data;Set-DoomAutomapCommand $game 0;$null=$game.Update($commands)
    Check 'Zero mask releases held pan and zoom' ($am.ViewX.Data -eq $x -and $am.Zoom.Data -eq $zoom -and -not $am.Right -and -not $am.ZoomIn)
    for($i=0;$i -lt 12;$i++){Set-DoomAutomapCommand $game 4}
    Check 'Marks wrap at ten slots' ($am.Marks.Count -eq 10 -and $am.NextMarkNumber -eq 2)
    $reference=[DrawScreen]::new($content.Wad,320,200);$mapRenderer=[AutoMapRenderer]::new($content.Wad,$reference);$hud=[StatusBarRenderer]::new($content.Wad,$reference)
    foreach($case in 'Initial','Health','Armor','Ammo','Capacity','Weapons','Keys','Face','ReadyWeapon','Frags','Network','PlayerNumber','NegativeHealth','ClearKeys'){
        switch($case){
            Health {$p.Health=52};Armor {$p.ArmorPoints=78};Ammo {$p.Ammo[0]=19};Capacity {$p.MaxAmmo[0]=400}
            Weapons {$p.WeaponOwned[2]=$true};Keys {$p.Cards[0]=$true;$p.Cards[4]=$true}
            Face {$game.World.StatusBar.FaceIndex=5};ReadyWeapon {$p.ReadyWeapon=[WeaponType]::Fist}
            Frags {$options.Deathmatch=1;$p.Frags[1]=12};Network {$options.NetGame=$true}
            PlayerNumber {$p.Number=1};NegativeHealth {$p.Health=-17};ClearKeys {[Array]::Clear($p.Cards)}
        }
        $mapRenderer.Render($p);$hud.Render($p,$true);$actual=Get-DoomAutomapScreen $graphics $game
        Check "$case cached composition matches direct map/HUD" ((Hash $actual) -eq (Hash $reference.Data))
        $actual=Get-DoomAutomapScreen $graphics $game
        Check "$case warm cache preserves direct pixels" ((Hash $actual) -eq (Hash $reference.Data))
    }
    $options.NetGame=$false;$options.Deathmatch=0;$p.Number=0;$p.Health=100
    foreach($mode in 0,1,2){$am.State=[AutoMapState]$mode;$mapRenderer.Render($p);$hud.Render($p,$true);Check "Automap state $mode direct pixels" ((Hash (Get-DoomAutomapScreen $graphics $game)) -eq (Hash $reference.Data))}
    $am.State=[AutoMapState]::None;$p.Powers[[int][PowerType]::AllMap]=1;$mapRenderer.Render($p);$hud.Render($p,$true)
    Check 'All-map power direct pixels' ((Hash (Get-DoomAutomapScreen $graphics $game)) -eq (Hash $reference.Data))
    $p.Powers[[int][PowerType]::AllMap]=0
    for($i=0;$i -lt 10;$i++){$watch=[Diagnostics.Stopwatch]::StartNew();$null=Get-DoomAutomapScreen $graphics $game;$samples.Add($watch.Elapsed.TotalMilliseconds)}
    [IO.File]::WriteAllBytes((Join-Path $directory 'automap.raw'),$graphics.Screen.Data)
    Set-DoomAutomapCommand $game 8;Check 'Clear removes markers and resets ring' ($am.Marks.Count -eq 0 -and $am.NextMarkNumber -eq 0)
    Set-DoomAutomapCommand $game 4;Set-DoomAutomapCommand $game (16+64)
    $before=Get-DoomAutomapCheckpoint $game
    $savePath=Join-Path $directory 'automap.pds';$wadHash=(Get-FileHash $Wad).Hash;$null=Write-DoomSaveState $game $savePath $wadHash
    $saved=Read-DoomSaveState $savePath $wadHash;$loaded=New-DoomGameFromSave $saved $content
    Check 'Save restores discovery, visibility, view, marks and held controls' ((Get-DoomAutomapCheckpoint $loaded) -eq $before)
    Set-DoomAutomapCommand $loaded 0;Check 'First post-load command releases held map controls' (-not $loaded.World.AutoMap.Left -and -not $loaded.World.AutoMap.ZoomIn)
    Set-DoomAutomapCommand $game 1;Check 'Close resets held map controls' (-not $am.Visible -and -not $am.ZoomIn -and -not $am.Left)
    $state=@{Keys=[bool[]]::new(256);Pressed=[bool[]]::new(256);Suppressed=[bool[]]::new(256)}
    $state.Pressed[9]=$true;$state.Keys[37]=$true;$state.Keys[87]=$true
    $mask=Get-DoomAutomapInputMask $state $false;Set-DoomInputCommand $state $commands[0] -AutomapVisible:$state.AutomapVisible
    Check 'Opening map captures arrows while WASD still moves' ($mask -eq 65 -and $commands[0].AngleTurn -eq 0 -and $commands[0].ForwardMove -eq 25)
    $state.Pressed[9]=$true;$mask=Get-DoomAutomapInputMask $state $true;Set-DoomInputCommand $state $commands[0] -AutomapVisible:$state.AutomapVisible
    Check 'Closing map restores arrow turning' ($mask -eq 1 -and $commands[0].AngleTurn -eq 640)
    $state.Pressed[77]=$true;$state.Suppressed[77]=$true;$mask=Get-DoomAutomapInputMask $state $true
    Check 'Menu-suppressed mark key cannot add a mark' (($mask -band 4) -eq 0)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();WarmMapMs=(Get-SampleStats $samples.ToArray());WarmMapSamplesMs=$samples.ToArray();Directory=$directory;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;SourceFingerprint=(Get-DoomReplaySourceFingerprint);Meaning='Simulation object, cached composition, save restoration and synthetic key checks. No physical keyboard or live display pacing claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($checks.Count) automap session checks."
