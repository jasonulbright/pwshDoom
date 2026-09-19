#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Route,[Parameter(Mandatory)][string]$Output,[int]$MaxTics=10000,[ValidateRange(1,32)][double]$ArrivalDistance=18,[switch]$CombatStrafe,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Use a fresh route result.'}
$plan=Get-Content $Route -Raw|ConvertFrom-Json;$waypoints=$plan.Waypoints
$planSha256=(Get-FileHash $Route).Hash;$driverSha256=(Get-FileHash $PSCommandPath).Hash
if($waypoints.Count -lt 1){throw 'Expected at least one waypoint.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$bundleSha256=(Get-FileHash $bundle).Hash
Set-StrictMode -Version Latest
$content=$null;$game=$null;$failure=$null;$passed=$false;$waypoint=0;$reachedAt=0;$tic=0;$holdStarted=-1
$commandsLog=[Collections.Generic.List[object]]::new();$trace=[Collections.Generic.List[object]]::new();$reached=[Collections.Generic.List[object]]::new()
$completedUpdates=0
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]([int]$plan.Skill-1),$plan.Episode,$plan.Map);$null=$game.Update($commands)
    for($tic=0;$tic -lt $MaxTics;$tic++){
        $world=$game.World;$player=$world.ConsolePlayer;$mo=$player.Mobj
        $x=$mo.X.Data/65536.0;$y=$mo.Y.Data/65536.0;$angle=$mo.Angle.Data*(2*[Math]::PI/4294967296.0)
        $target=$waypoints[$waypoint];$dx=$target[0]-$x;$dy=$target[1]-$y;$distance=[Math]::Sqrt($dx*$dx+$dy*$dy)
        $holding=$false
        if($distance -lt $ArrivalDistance -and $target.Count -ge 3){if($holdStarted -lt 0){$holdStarted=$commandsLog.Count};$holding=$commandsLog.Count-$holdStarted -lt $target[2]}
        if($distance -lt $ArrivalDistance -and -not $holding -and $waypoint -lt $waypoints.Count-1){$reached.Add(@{Waypoint=$waypoint;Command=$commandsLog.Count;X=$x;Y=$y});$waypoint++;$reachedAt=$tic;$holdStarted=-1;"Waypoint $waypoint at command $($commandsLog.Count)";continue}
        $aim=[Math]::Atan2($dy,$dx);$attack=$false;$cap=$world.Thinkers.Cap;$enemy=$cap.Next;$nearest=300.0
        while(-not [object]::ReferenceEquals($enemy,$cap)){
            if($enemy -is [Mobj] -and ($enemy.Flags -band [MobjFlags]::CountKill) -and $enemy.Health -gt 0){
                $ex=$enemy.X.Data/65536.0-$x;$ey=$enemy.Y.Data/65536.0-$y;$ed=[Math]::Sqrt($ex*$ex+$ey*$ey)
                if($ed -lt $nearest -and ($player.Ammo|Measure-Object -Sum).Sum -gt 0 -and $world.VisibilityCheck.CheckSight($mo,$enemy)){$nearest=$ed;$aim=[Math]::Atan2($ey,$ex);$attack=$true}
            }
            $enemy=$enemy.Next
        }
        if($holding -and $target.Count -ge 4){$aim=$target[3]*[Math]::PI/180;$attack=$false}
        $delta=($aim-$angle+3*[Math]::PI)%(2*[Math]::PI)-[Math]::PI
        $cmd=$commands[0];$cmd.Clear();$cmd.AngleTurn=[int16][Math]::Clamp([Math]::Round($delta*65536/(2*[Math]::PI)),-2048,2048)
        if([Math]::Abs($delta) -lt .18 -and -not $attack -and -not $holding){$cmd.ForwardMove=if($distance -gt 70){25}else{8}}
        if($attack -and [Math]::Abs($delta) -lt .08){$cmd.Buttons=1}
        if($CombatStrafe -and $attack -and -not $holding -and [Math]::Abs($delta) -lt .18){$cmd.SideMove=if(($commandsLog.Count%140) -lt 70){24}else{-24}}
        if(($commandsLog.Count%35) -eq 0){$cmd.Buttons=$cmd.Buttons -bor 2}
        $commandsLog.Add(@($cmd.ForwardMove,$cmd.SideMove,$cmd.AngleTurn,$cmd.Buttons));$null=$game.Update($commands);$completedUpdates++
        if(($commandsLog.Count%35) -eq 0){$trace.Add(@{Command=$commandsLog.Count;Waypoint=$waypoint;X=$x;Y=$y;Z=$mo.Z.Data/65536.0;Health=$player.Health;Armor=$player.ArmorPoints;Kills=$player.KillCount;Ammo=$player.Ammo.Clone();Cards=$player.Cards.Clone();Weapon=$player.ReadyWeapon.ToString();Sector=$mo.Subsector.Sector.Number;SectorSpecial=[int]$mo.Subsector.Sector.Special;Floor=$mo.Subsector.Sector.FloorHeight.Data/65536.0})}
        if($game.State -eq [GameState]::Intermission){$passed=$true;break}
        if($player.Health -le 0){throw "Player died at waypoint $waypoint ($x,$y)."}
        if($tic-$reachedAt -gt 900){throw "Route stalled at waypoint $waypoint ($x,$y), target $($target -join ',')."}
    }
    if(-not $passed){throw 'Route did not complete within its tic budget.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    $finalPlayer=if($game -and $game.World){$p=$game.World.ConsolePlayer;$m=$p.Mobj;@{X=$m.X.Data/65536.0;Y=$m.Y.Data/65536.0;Z=$m.Z.Data/65536.0;Sector=$m.Subsector.Sector.Number;SectorSpecial=[int]$m.Subsector.Sector.Special;Floor=$m.Subsector.Sector.FloorHeight.Data/65536.0;Health=$p.Health;Armor=$p.ArmorPoints;LastAttacker=if($p.Attacker){$p.Attacker.Type.ToString()}else{$null}}}
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Passed=$passed;Error=$failure;Episode=$plan.Episode;Map=$plan.Map;Skill=$plan.Skill;ArrivalDistance=$ArrivalDistance;CombatStrafe=[bool]$CombatStrafe;MaxIterations=$MaxTics;DriverIterations=$tic;SimulationCommands=$commandsLog.Count;CompletedUpdates=$completedUpdates;FailedUpdateCommand=if($completedUpdates -lt $commandsLog.Count){$commandsLog.Count}else{$null};Route=$waypoints;Reached=$reached.ToArray();Trace=$trace.ToArray();InputCommands=$commandsLog.ToArray();WadSha256=(Get-FileHash $Wad).Hash;PlanSha256=$planSha256;DriverSha256=$driverSha256;BundleSha256=$bundleSha256;FinalState=if($game){$game.State.ToString()};FinalHealth=if($game){$game.World.ConsolePlayer.Health};FinalPlayer=$finalPlayer;Meaning='Unpaced waypoint/combat driver with ordinary TicCmd movement, turns, attacks and use only. Optional combat strafing uses declared alternating player sidemove commands. No teleport, god mode, direct damage, direct specials or state edits. SimulationCommands counts attempted inputs; CompletedUpdates excludes a throwing update. Trace X/Y precede the update; other trace state and FinalPlayer follow it. LastAttacker is the most recent damage source, not necessarily from the final tic. Route planning reads geometry; view tests require separate recorded host replay.'}|ConvertTo-Json -Depth 8|Set-Content $Output
    if($content){$content.Dispose()}
}
"PASS: E$($plan.Episode)M$($plan.Map) with $($commandsLog.Count) commands."
