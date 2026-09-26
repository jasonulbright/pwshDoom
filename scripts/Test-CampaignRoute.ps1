#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Route,[Parameter(Mandatory)][string]$Output,[int]$MaxTics=10000,[ValidateRange(1,32)][double]$ArrivalDistance=18,[switch]$CombatStrafe,[switch]$CollectDroppedWeapons,[switch]$ClearBarrels,[string]$StartingReplay,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Use a fresh route result.'}
$plan=Get-Content $Route -Raw|ConvertFrom-Json;$waypoints=$plan.Waypoints
$planSha256=(Get-FileHash $Route).Hash;$driverSha256=(Get-FileHash $PSCommandPath).Hash
if($waypoints.Count -lt 1){throw 'Expected at least one waypoint.'}
$prior=$null;$priorHash=$null
if($StartingReplay){
    $prior=Get-Content -LiteralPath $StartingReplay -Raw|ConvertFrom-Json
    $priorHash=(Get-FileHash -LiteralPath $StartingReplay).Hash
    if($prior.Format -cne 'pwshDoom.InputReplay' -or -not $prior.Passed -or $prior.Error -or -not $prior.ContinueCampaign -or
       $prior.Episode -ne $plan.Episode -or $prior.ExpectedNextMap -ne $plan.Map -or $prior.Skill -ne $plan.Skill -or
       $prior.WadSha256 -cne (Get-FileHash -LiteralPath $Wad).Hash -or $prior.InputCommands.Count -lt 1 -or
       $prior.Checkpoints.Count -lt 1 -or $prior.Checkpoints[-1].Tic -ne $prior.InputCommands.Count){throw 'Starting replay must be a qualified same-IWAD, same-skill continuation into this map.'}
}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$bundleSha256=(Get-FileHash $bundle).Hash
Set-StrictMode -Version Latest
$content=$null;$game=$null;$failure=$null;$passed=$false;$waypoint=0;$reachedAt=0;$tic=0;$holdStarted=-1
$commandsLog=[Collections.Generic.List[object]]::new();$trace=[Collections.Generic.List[object]]::new();$reached=[Collections.Generic.List[object]]::new()
$completedUpdates=0
$pickupAttempts=[Collections.Generic.Dictionary[object,int]]::new();$pickupEvents=[Collections.Generic.List[object]]::new();$lastPickup=$null
$barrelAttempts=[Collections.Generic.Dictionary[object,int]]::new();$barrelEvents=[Collections.Generic.List[object]]::new();$barrelHoldUntil=0
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    if($prior){
        $game.DeferedInitNew([GameSkill]([int]$prior.Skill-1),$prior.Episode,$prior.Map);$null=$game.Update($commands)
        foreach($entry in $prior.InputCommands){
            for($i=0;$i -lt 4;$i++){$commands[$i].Clear()}
            $commands[0].ForwardMove=$entry[0];$commands[0].SideMove=$entry[1];$commands[0].AngleTurn=$entry[2];$commands[0].Buttons=$entry[3]
            $null=$game.Update($commands)
        }
        $expected=$prior.Checkpoints[-1];$actual=Get-DoomReplayCheckpoint $game $prior.InputCommands.Count
        $comparison=Compare-DoomReplayCheckpoints @($expected) @($actual) $prior.InputCommands.Count
        if($game.State -ne [GameState]::Level -or $game.Options.Episode -ne $plan.Episode -or $game.Options.Map -ne $plan.Map -or
           $game.World.LevelTime -ne $expected.State.LevelTime -or -not $comparison.Matched){throw 'Starting replay no longer reaches its recorded destination checkpoint.'}
        for($i=0;$i -lt 4;$i++){$commands[$i].Clear()}
    }else{$game.DeferedInitNew([GameSkill]([int]$plan.Skill-1),$plan.Episode,$plan.Map);$null=$game.Update($commands)}
    for($tic=0;$tic -lt $MaxTics;$tic++){
        $world=$game.World;$player=$world.ConsolePlayer;$mo=$player.Mobj
        $x=$mo.X.Data/65536.0;$y=$mo.Y.Data/65536.0;$angle=$mo.Angle.Data*(2*[Math]::PI/4294967296.0)
        $target=$waypoints[$waypoint];$dx=$target[0]-$x;$dy=$target[1]-$y;$distance=[Math]::Sqrt($dx*$dx+$dy*$dy)
        $holding=$false
        if($distance -lt $ArrivalDistance -and $target.Count -ge 3){if($holdStarted -lt 0){$holdStarted=$commandsLog.Count};$holding=$commandsLog.Count-$holdStarted -lt $target[2]}
        if($distance -lt $ArrivalDistance -and -not $holding -and $waypoint -lt $waypoints.Count-1){$reached.Add(@{Waypoint=$waypoint;Command=$commandsLog.Count;X=$x;Y=$y});$waypoint++;$reachedAt=$tic;$holdStarted=-1;"Waypoint $waypoint at command $($commandsLog.Count)";continue}
        $aim=[Math]::Atan2($dy,$dx);$attack=$false;$cap=$world.Thinkers.Cap;$enemy=$cap.Next;$nearest=300.0
        $pickup=$null;$pickupDistance=160.0;$pickupWeapon=-1
        $barrel=$null;$barrelDistance=300.0;$nearBarrel=$false
        while(-not [object]::ReferenceEquals($enemy,$cap)){
            if($ClearBarrels -and $enemy -is [Mobj] -and $enemy.Type -eq [MobjType]::Barrel -and ($enemy.Flags -band [MobjFlags]::Shootable)){
                $bx=$enemy.X.Data/65536.0-$x;$by=$enemy.Y.Data/65536.0-$y;$bd=[Math]::Sqrt($bx*$bx+$by*$by)
                if($bd -lt 160){$nearBarrel=$true}
                elseif($bd -lt $barrelDistance -and $enemy.Health -gt 0 -and (-not $barrelAttempts.ContainsKey($enemy) -or $barrelAttempts[$enemy] -lt 140) -and $world.VisibilityCheck.CheckSight($mo,$enemy)){$barrel=$enemy;$barrelDistance=$bd}
            }
            if($enemy -is [Mobj] -and ($enemy.Flags -band [MobjFlags]::CountKill) -and $enemy.Health -gt 0){
                $ex=$enemy.X.Data/65536.0-$x;$ey=$enemy.Y.Data/65536.0-$y;$ed=[Math]::Sqrt($ex*$ex+$ey*$ey)
                if($ed -lt $nearest -and ($player.Ammo|Measure-Object -Sum).Sum -gt 0 -and $world.VisibilityCheck.CheckSight($mo,$enemy)){$nearest=$ed;$aim=[Math]::Atan2($ey,$ex);$attack=$true}
            }
            if($CollectDroppedWeapons -and -not $holding -and $enemy -is [Mobj] -and ($enemy.Flags -band [MobjFlags]::Dropped) -and ($enemy.Flags -band [MobjFlags]::Special)){
                $weapon=if($enemy.Type -eq [MobjType]::Shotgun){[int][WeaponType]::Shotgun}elseif($enemy.Type -eq [MobjType]::Chaingun){[int][WeaponType]::Chaingun}else{-1}
                if($weapon -ge 0 -and -not $player.WeaponOwned[$weapon] -and (-not $pickupAttempts.ContainsKey($enemy) -or $pickupAttempts[$enemy] -lt 140)){
                    $px=$enemy.X.Data/65536.0-$x;$py=$enemy.Y.Data/65536.0-$y;$pd=[Math]::Sqrt($px*$px+$py*$py)
                    if($pd -lt $pickupDistance -and [Math]::Abs(($enemy.Z.Data-$mo.Z.Data)/65536.0) -le 24 -and $world.VisibilityCheck.CheckSight($mo,$enemy)){$pickup=$enemy;$pickupDistance=$pd;$pickupWeapon=$weapon}
                }
            }
            $enemy=$enemy.Next
        }
        # The route driver may steer toward a nearby unowned drop. It never
        # grants inventory; normal movement/collision performs the pickup.
        $seekingPickup=$null -ne $pickup -and $nearest -ge 64
        if($seekingPickup){
            if(-not $pickupAttempts.ContainsKey($pickup)){$pickupAttempts.Add($pickup,0)}
            if(-not [object]::ReferenceEquals($pickup,$lastPickup)){$pickupEvents.Add(@{Event='Approach';Command=$commandsLog.Count;Type=$pickup.Type.ToString();X=$pickup.X.Data/65536.0;Y=$pickup.Y.Data/65536.0;Distance=$pickupDistance;Health=$player.Health;Waypoint=$waypoint})}
            $pickupAttempts[$pickup]++;$lastPickup=$pickup
            $aim=[Math]::Atan2($pickup.Y.Data/65536.0-$y,$pickup.X.Data/65536.0-$x);$distance=$pickupDistance;$attack=$false
        }else{$lastPickup=$null}
        # Optional driver strategy: shoot visible barrels before walking into
        # their blast radius, and wait through the explosion animation. This
        # emits ordinary attacks only; nearby barrels/close enemies take priority
        # over attempting this clearance. The game still computes all damage.
        $clearingBarrel=$null -ne $barrel -and -not $nearBarrel -and -not $holding -and -not $seekingPickup -and $nearest -ge 64 -and ($player.Ammo|Measure-Object -Sum).Sum -gt 0 -and $commandsLog.Count -ge $barrelHoldUntil
        if($clearingBarrel){
            if(-not $barrelAttempts.ContainsKey($barrel)){$barrelAttempts.Add($barrel,0);$barrelEvents.Add(@{Event='Target';Command=$commandsLog.Count;X=$barrel.X.Data/65536.0;Y=$barrel.Y.Data/65536.0;Distance=$barrelDistance;Health=$player.Health})}
            $barrelAttempts[$barrel]++;$aim=[Math]::Atan2($barrel.Y.Data/65536.0-$y,$barrel.X.Data/65536.0-$x);$attack=$true
        }
        if($holding -and $target.Count -ge 4){$aim=$target[3]*[Math]::PI/180;$attack=$false}
        $delta=($aim-$angle+3*[Math]::PI)%(2*[Math]::PI)-[Math]::PI
        $cmd=$commands[0];$cmd.Clear();$cmd.AngleTurn=[int16][Math]::Clamp([Math]::Round($delta*65536/(2*[Math]::PI)),-2048,2048)
        if([Math]::Abs($delta) -lt .18 -and -not $attack -and -not $holding -and $commandsLog.Count -ge $barrelHoldUntil){$cmd.ForwardMove=if($distance -gt 70){25}else{8}}
        if($attack -and [Math]::Abs($delta) -lt .08){$cmd.Buttons=1}
        if($CombatStrafe -and $attack -and -not $holding -and -not $clearingBarrel -and $commandsLog.Count -ge $barrelHoldUntil -and [Math]::Abs($delta) -lt .18){$cmd.SideMove=if(($commandsLog.Count%140) -lt 70){24}else{-24}}
        if(($commandsLog.Count%35) -eq 0){$cmd.Buttons=$cmd.Buttons -bor 2}
        $commandsLog.Add(@($cmd.ForwardMove,$cmd.SideMove,$cmd.AngleTurn,$cmd.Buttons));$null=$game.Update($commands);$completedUpdates++
        if($clearingBarrel -and $barrel.Health -le 0){$barrelHoldUntil=$commandsLog.Count+35;$barrelEvents.Add(@{Event='DestroyedAfterAttack';Command=$commandsLog.Count;Attempts=$barrelAttempts[$barrel];Health=$player.Health;HoldUntil=$barrelHoldUntil})}
        if($seekingPickup -and $player.WeaponOwned[$pickupWeapon]){$pickupEvents.Add(@{Event='OwnedAfterMove';Command=$commandsLog.Count;Type=$pickup.Type.ToString();Health=$player.Health;Attempts=$pickupAttempts[$pickup]});$lastPickup=$null}
        elseif($seekingPickup -and $pickupAttempts[$pickup] -eq 140){$pickupEvents.Add(@{Event='AttemptLimit';Command=$commandsLog.Count;Type=$pickup.Type.ToString();Health=$player.Health});$lastPickup=$null}
        if(($commandsLog.Count%35) -eq 0){$trace.Add(@{Command=$commandsLog.Count;Waypoint=$waypoint;X=$x;Y=$y;Z=$mo.Z.Data/65536.0;Health=$player.Health;Armor=$player.ArmorPoints;Kills=$player.KillCount;Ammo=$player.Ammo.Clone();Cards=$player.Cards.Clone();Weapon=$player.ReadyWeapon.ToString();Sector=$mo.Subsector.Sector.Number;SectorSpecial=[int]$mo.Subsector.Sector.Special;Floor=$mo.Subsector.Sector.FloorHeight.Data/65536.0})}
        if($game.State -eq [GameState]::Intermission){$passed=$true;break}
        if($player.Health -le 0){throw "Player died at waypoint $waypoint ($x,$y)."}
        if($tic-$reachedAt -gt 900){throw "Route stalled at waypoint $waypoint ($x,$y), target $($target -join ',')."}
    }
    if(-not $passed){throw 'Route did not complete within its tic budget.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    # Strategy observations are separate from the fixed-input state checks;
    # proximity/targeting alone does not certify a safe explosion.
    $barrelStrategy=@{Enabled=[bool]$ClearBarrels;Events=$barrelEvents.ToArray();MinimumTargetDistance=160;MaximumTargetDistance=300;MaximumCommandsPerBarrel=140;PostDestructionHoldCommands=35}
    $finalPlayer=if($game -and $game.World){$p=$game.World.ConsolePlayer;$m=$p.Mobj;@{X=$m.X.Data/65536.0;Y=$m.Y.Data/65536.0;Z=$m.Z.Data/65536.0;Sector=$m.Subsector.Sector.Number;SectorSpecial=[int]$m.Subsector.Sector.Special;Floor=$m.Subsector.Sector.FloorHeight.Data/65536.0;Health=$p.Health;Armor=$p.ArmorPoints;LastAttacker=if($p.Attacker){$p.Attacker.Type.ToString()}else{$null}}}
    @{StartingReplaySha256=$priorHash;StartingReplayCommands=if($prior){$prior.InputCommands.Count}else{0};StartMode=if($prior){'QualifiedCampaignContinuation'}else{'PistolStart'};BarrelStrategy=$barrelStrategy;FinishedUtc=[DateTime]::UtcNow.ToString('o');Passed=$passed;Error=$failure;Episode=$plan.Episode;Map=$plan.Map;Skill=$plan.Skill;ArrivalDistance=$ArrivalDistance;CombatStrafe=[bool]$CombatStrafe;CollectDroppedWeapons=[bool]$CollectDroppedWeapons;PickupEvents=$pickupEvents.ToArray();MaxIterations=$MaxTics;DriverIterations=$tic;SimulationCommands=$commandsLog.Count;CompletedUpdates=$completedUpdates;FailedUpdateCommand=if($completedUpdates -lt $commandsLog.Count){$commandsLog.Count}else{$null};Route=$waypoints;Reached=$reached.ToArray();Trace=$trace.ToArray();InputCommands=$commandsLog.ToArray();WadSha256=(Get-FileHash $Wad).Hash;PlanSha256=$planSha256;DriverSha256=$driverSha256;BundleSha256=$bundleSha256;FinalState=if($game){$game.State.ToString()};FinalHealth=if($game){$game.World.ConsolePlayer.Health};FinalPlayer=$finalPlayer;Meaning='Unpaced waypoint/combat driver with ordinary TicCmd movement, turns, attacks and use only. Optional qualified starting replay uses real preceding-map commands and verifies its destination state before driving this map; recorded InputCommands contain only this map suffix and cannot independently reproduce a continuation without StartingReplaySha256. Optional combat strafing uses declared alternating player sidemove commands. Optional dropped-weapon collection seeks visible unowned shotgun/chaingun drops within 160 units and 24 height units, through ordinary movement only, at most 140 steering commands per drop; enemies closer than 64 units retain combat priority. No teleport, god mode, direct damage, direct specials or state edits. SimulationCommands counts attempted suffix inputs; CompletedUpdates excludes a throwing update. Trace X/Y precede the update; other trace state and FinalPlayer follow it. LastAttacker is the most recent damage source, not necessarily from the final tic. Route planning reads geometry; view tests require separate recorded host replay.'}|ConvertTo-Json -Depth 8|Set-Content $Output
    if($content){$content.Dispose()}
}
"PASS: E$($plan.Episode)M$($plan.Map) with $($commandsLog.Count) commands."
