#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. "$PSScriptRoot/../src/GameHost.ps1"
Set-StrictMode -Version Latest
$content=$null;$checks=[Collections.Generic.List[object]]::new()
function Assert-Game([bool]$Condition,[string]$Name,$Evidence) {
    if(-not $Condition){throw "FAIL: $Name ($($Evidence | ConvertTo-Json -Compress))"}
    $checks.Add(@{Check=$Name;Evidence=$Evidence})
}
function Reset-TestLevel {
    $game.DeferedInitNew([GameSkill]::Medium,1,1)
    foreach($cmd in $commands){$cmd.Clear()};$null=$game.Update($commands)
}
function Set-TestPosition([double]$X,[double]$Y,[double]$Angle) {
    # Explicit test fixture positioning, not evidence of navigating the level.
    $mo=$game.World.ConsolePlayer.Mobj
    $game.World.ThingMovement.UnsetThingPosition($mo)
    $mo.X=[Fixed]::FromDouble($X);$mo.Y=[Fixed]::FromDouble($Y)
    $mo.Angle=[Angle]::new([uint32]($Angle*4294967296.0/360));$mo.MomX=[Fixed]::Zero;$mo.MomY=[Fixed]::Zero
    $game.World.ThingMovement.SetThingPosition($mo)
    $mo.Z=$mo.Subsector.Sector.FloorHeight;$mo.FloorZ=$mo.Z;$mo.CeilingZ=$mo.Subsector.Sector.CeilingHeight
}
try {
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()};Reset-TestLevel
    $player=$game.World.ConsolePlayer
    Assert-Game ($player.Mobj.X.Data -eq 1056*65536 -and $player.Mobj.Y.Data -eq -3616*65536) 'IWAD player spawn' @($player.Mobj.X.Data,$player.Mobj.Y.Data)
    Assert-Game ($game.World.TotalKills -eq 6) 'E1M1 HMP monsters match independently decoded THINGS flags' $game.World.TotalKills
    $spawnSnapshot=New-GameRenderSnapshot $game 0
    Assert-Game ($spawnSnapshot.ConsolePlayer.ViewZ -eq $player.GetInterpolatedViewZ([Fixed]::Zero).Data/65536.0) 'Initial camera height follows the reference first-tic rule' $spawnSnapshot.ConsolePlayer.ViewZ
    $initialY=$player.Mobj.Y.Data
    $commands[0].ForwardMove=25
    for($i=0;$i -lt 100;$i++){$null=$game.Update($commands)}
    $collisionY=$player.Mobj.Y.Data
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    Assert-Game ($collisionY -gt $initialY -and $player.Mobj.Y.Data -eq $collisionY) 'Forward input moves then stops at solid wall' @($initialY,$collisionY,$player.Mobj.Y.Data)
    $commands[0].Clear();$before=$player.Ammo[0];$commands[0].Buttons=1
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    Assert-Game ($player.Ammo[0] -lt $before) 'Pistol consumes ammunition through TicCmd attack' @($before,$player.Ammo[0])
    Reset-TestLevel;$world=$game.World;$player=$world.ConsolePlayer
    $door=@($world.Map.Lines | Where-Object {$_.Special -eq 1 -and $null -ne $_.BackSector})[0]
    $x1=$door.Vertex1.X.Data/65536.0;$y1=$door.Vertex1.Y.Data/65536.0;$x2=$door.Vertex2.X.Data/65536.0;$y2=$door.Vertex2.Y.Data/65536.0
    $dx=$x2-$x1;$dy=$y2-$y1;$length=[Math]::Sqrt($dx*$dx+$dy*$dy)
    $x=($x1+$x2)/2+$dy/$length*32;$y=($y1+$y2)/2-$dx/$length*32
    $angle=([Math]::Atan2($dx,-$dy)*180/[Math]::PI+360)%360
    Set-TestPosition $x $y $angle
    $before=$door.BackSector.CeilingHeight.Data;$commands[0].Buttons=2
    $null=$game.Update($commands);$commands[0].Clear()
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    Assert-Game ($door.BackSector.CeilingHeight.Data -gt $before) 'Use input opens a real door from a positioned fixture' @($before,$door.BackSector.CeilingHeight.Data)
    Reset-TestLevel;$world=$game.World;$player=$world.ConsolePlayer
    $cap=$world.Thinkers.Cap;$item=$cap.Next
    while(-not [object]::ReferenceEquals($item,$cap)) {if($item -is [Mobj] -and $item.Sprite -eq [Sprite]::ARM1){break};$item=$item.Next}
    Assert-Game (-not [object]::ReferenceEquals($item,$cap)) 'Green armor fixture exists' $true
    Set-TestPosition ($item.X.Data/65536.0-32) ($item.Y.Data/65536.0) 0
    $commands[0].ForwardMove=25
    for($i=0;$i -lt 8;$i++){$null=$game.Update($commands)}
    Assert-Game ($player.ArmorPoints -eq 100) 'Movement collision collects armor from a positioned fixture' $player.ArmorPoints
    Reset-TestLevel;$world=$game.World
    $exit=@($world.Map.Lines | Where-Object {$_.Special -eq 11})[0]
    $x1=$exit.Vertex1.X.Data/65536.0;$y1=$exit.Vertex1.Y.Data/65536.0;$x2=$exit.Vertex2.X.Data/65536.0;$y2=$exit.Vertex2.Y.Data/65536.0
    $dx=$x2-$x1;$dy=$y2-$y1;$length=[Math]::Sqrt($dx*$dx+$dy*$dy)
    Set-TestPosition (($x1+$x2)/2+$dy/$length*32) (($y1+$y2)/2-$dx/$length*32) (([Math]::Atan2($dx,-$dy)*180/[Math]::PI+360)%360)
    $commands[0].Buttons=2;$null=$game.Update($commands);$commands[0].Clear();$null=$game.Update($commands)
    Assert-Game ($game.State -eq [GameState]::Intermission) 'Exit switch enters intermission through Use input from a positioned fixture' $game.State.ToString()
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks.ToArray();WadSha256=(Get-FileHash $Wad).Hash;Meaning='Component integration tests. Door, pickup, and exit tests position the player explicitly; they do not establish a full input-only playthrough.'} | ConvertTo-Json -Depth 6 | Set-Content "$PSScriptRoot/../results/game-actions.json"
    "PASS: $($checks.Count) gameplay checks."
} catch {[Console]::Error.WriteLine($_.ScriptStackTrace);throw}
finally {if($null -ne $content){$content.Dispose()}}
