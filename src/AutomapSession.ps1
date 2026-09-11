# SPDX-License-Identifier: GPL-2.0-or-later
# Simulation-owned discovery and controls; inherited PowerShell map/HUD drawing.
function New-DoomAutomapGraphics {
    param($Content)
    $screen=[DrawScreen]::new($Content.Wad,320,200)
    $hudScreen=[DrawScreen]::new($Content.Wad,320,200)
    return @{Screen=$screen;HudScreen=$hudScreen;Renderer=[AutoMapRenderer]::new($Content.Wad,$screen);
        Hud=[StatusBarRenderer]::new($Content.Wad,$hudScreen);HudKey='';
        Discovery=[ThreeDRenderer]::new($Content,[DrawScreen]::new($Content.Wad,320,200),7)}
}

function Set-DoomAutomapCommand {
    param($Game,[ValidateRange(0,1023)][int]$Mask)
    if([int]$Game.State -ne 0){return}
    $am=$Game.World.AutoMap
    if($Mask -band 1){if($am.Visible){$am.Close()}else{$am.Open()}}
    if(-not $am.Visible){return}
    foreach($pair in @(@(2,'F'),@(4,'M'),@(8,'C'))){
        if($Mask -band $pair[0]){$null=$am.DoEvent([DoomEvent]::new([EventType]::KeyDown,[DoomKey]::$($pair[1])))}
    }
    # Every command carries held state, including releases; no synthetic key-up
    # events can be lost when presentation is paused or a save is loaded.
    $am.ZoomIn=($Mask -band 16) -ne 0;$am.ZoomOut=($Mask -band 32) -ne 0
    $am.Left=($Mask -band 64) -ne 0;$am.Right=($Mask -band 128) -ne 0
    $am.Up=($Mask -band 256) -ne 0;$am.Down=($Mask -band 512) -ne 0
}

function Get-DoomAutomapScreen {
    param($Graphics,$Game)
    $p=$Game.World.ConsolePlayer;$options=$Game.Options
    $Graphics.Renderer.Render($p)
    # Key every input read by StatusBarRenderer.Render. Cache only presentation;
    # world state and face animation continue at the normal simulation rate.
    $key=@($p.Health,$p.ArmorPoints,[int]$p.ReadyWeapon,$Game.World.StatusBar.FaceIndex,
        $p.Number,$options.Deathmatch,$options.NetGame,($p.Ammo -join ','),($p.MaxAmmo -join ','),
        ($p.WeaponOwned -join ','),($p.Cards -join ','),($p.Frags -join ',')) -join '|'
    if($key -cne $Graphics.HudKey){$Graphics.Hud.Render($p,$true);$Graphics.HudKey=$key}
    for($x=0;$x -lt 320;$x++){[Buffer]::BlockCopy($Graphics.HudScreen.Data,$x*200+168,$Graphics.Screen.Data,$x*200+168,32)}
    return ,$Graphics.Screen.Data
}

function Get-DoomAutomapCheckpoint {
    param($Game)
    $am=$Game.World.AutoMap
    $state=[ordered]@{Visible=$am.Visible;Follow=$am.Follow;State=[int]$am.State;Zoom=$am.Zoom.Data;
        X=$am.ViewX.Data;Y=$am.ViewY.Data;NextMark=$am.NextMarkNumber;
        Held=@($am.ZoomIn,$am.ZoomOut,$am.Left,$am.Right,$am.Up,$am.Down);
        Marks=@(foreach($mark in $am.Marks){@($mark.X.Data,$mark.Y.Data)});
        Mapped=@(for($i=0;$i -lt $Game.World.Map.Lines.Length;$i++){if($Game.World.Map.Lines[$i].Flags -band 256){$i}})}
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($state|ConvertTo-Json -Depth 5 -Compress))))
}
