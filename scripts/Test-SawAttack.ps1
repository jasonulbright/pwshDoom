#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. "$PSScriptRoot/../src/GameHost.ps1"
$checks=[Collections.Generic.List[object]]::new()
$content=$null
try {
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode
    $options.GameVersion=$content.Wad.GameVersion
    $options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options)
    $commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt $commands.Length;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,2)
    $null=$game.Update($commands)

    $world=$game.World
    $player=$world.ConsolePlayer
    $cap=$world.Thinkers.Cap
    $node=$cap.Next
    $target=$null
    $playerZ=$player.Mobj.Z.Data
    $bestDistance=[double]::PositiveInfinity
    while(-not [object]::ReferenceEquals($node,$cap)) {
        if($node -is [Mobj] -and $node.Type -eq [MobjType]::Troop -and $node.Health -gt 0 -and [Math]::Abs($node.Z.Data-$playerZ) -le 32*65536) {
            $dx=[double]($node.X.Data-$player.Mobj.X.Data)
            $dy=[double]($node.Y.Data-$player.Mobj.Y.Data)
            $distance=$dx*$dx+$dy*$dy
            if($distance -lt $bestDistance){$bestDistance=$distance;$target=$node}
        }
        $node=$node.Next
    }
    if($null -eq $target){throw 'E1M2 test fixture could not find a living, floor-aligned imp.'}

    # Put the player 40 map units west of a living imp, facing it. This isolates
    # the real chainsaw melee action without relying on a long human navigation route.
    $mobj=$player.Mobj
    $world.ThingMovement.UnsetThingPosition($mobj)
    $mobj.X=[Fixed]::new([int]($target.X.Data-40*65536))
    $mobj.Y=$target.Y
    $mobj.MomX=[Fixed]::Zero
    $mobj.MomY=[Fixed]::Zero
    $world.ThingMovement.SetThingPosition($mobj)
    $mobj.Z=$mobj.Subsector.Sector.FloorHeight
    $mobj.FloorZ=$mobj.Z
    $mobj.CeilingZ=$mobj.Subsector.Sector.CeilingHeight
    $mobj.Angle=[Geometry]::PointToAngle($mobj.X,$mobj.Y,$target.X,$target.Y)

    $initialHealth=$target.Health
    $player.ReadyWeapon=[WeaponType]::Chainsaw
    $player.PendingWeapon=[WeaponType]::NoChange
    $player.WeaponOwned[[int][WeaponType]::Chainsaw]=$true
    $player.AttackDown=$false
    $player.Cmd.Buttons=0
    $readyState=[DoomInfo]::WeaponInfos[[int][WeaponType]::Chainsaw].ReadyState
    $world.PlayerBehavior.SetPlayerSprite($player,[int][PlayerSprite]::Weapon,$readyState)
    $commands[0].Buttons=[TicCmdButtons]::Attack
    $hit=$target.Health -lt $initialHealth
    for($tic=1;$tic -le 32 -and -not $hit;$tic++) {
        $null=$game.Update($commands)
        $hit=$target.Health -lt $initialHealth
    }
    if(-not $hit){throw "Chainsaw attack-button path did not hit its E1M2 imp in 32 simulation tics (HP $initialHealth)."}
    $checks.Add(@{Check='E1M2 chainsaw attack-button path executes the player weapon action without comparison failure';Evidence=@{TargetType=$target.Type.ToString();TargetHealthBefore=$initialHealth;TargetHealthAfter=$target.Health;SimulationTicsToHit=$tic-1;PlayerAngleDegrees=$mobj.Angle.ToDegree()}})

    # The same PowerShell comparison limitation affected Doom II's homing turn.
    $target.Tracer=$mobj
    $mobj.X=$target.X
    $mobj.Y=[Fixed]::new([int]($target.Y.Data-128*65536))
    $target.Angle=[Angle]::Ang0
    while(($world.GameTic -band 3) -ne 0){$null=$game.Update($commands)}
    $beforeHomingAngle=$target.Angle.Data
    $world.MonsterBehavior.Tracer($target)
    if($target.Angle.Data -eq $beforeHomingAngle){throw 'Homing tracer fixture failed to turn toward its target.'}
    $checks.Add(@{Check='Doom II homing tracer angle adjustment executes';Evidence=@{TargetType=$target.Type.ToString();AngleBefore=$beforeHomingAngle;AngleAfter=$target.Angle.Data}})

    $result=@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o')
        Checks=$checks.ToArray()
        WadSha256=(Get-FileHash $Wad).Hash
        Scope='Input-to-player-weapon-state integration check with a fixed E1M2 player/imp position; not a campaign route or replay of the human crash session.'
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$PSScriptRoot/../results/saw-attack.json"
    "PASS: $($checks.Count) gameplay action checks."
} finally {if($null -ne $content){$content.Dispose()}}
