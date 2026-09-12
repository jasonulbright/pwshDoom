#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$RouteResult,[Parameter(Mandatory)][string]$Output,
    [ValidateRange(0,9)][int]$ExpectedNextMap=0,[switch]$SecretExit,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Use a fresh qualification/replay path.'}
$reference=Get-Content $RouteResult -Raw|ConvertFrom-Json;$wadHash=(Get-FileHash $Wad).Hash
if(-not $reference.Passed -or $reference.Error -or $reference.WadSha256 -cne $wadHash){throw 'Expected a successful route for this IWAD.'}
if($ExpectedNextMap -eq 0){if($SecretExit){throw 'Declare the expected secret destination map.'};$ExpectedNextMap=$reference.Map+1}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$content=$null;$game=$null;$failure=$null;$commands=$null;$lastTransition='';$traceChecks=0;$continued=$false
$log=[Collections.Generic.List[object]]::new();$points=[Collections.Generic.List[object]]::new();$transitions=[Collections.Generic.List[object]]::new()
function Record-Point {
    if($points.Count -eq 0 -or $points[-1].Tic -ne $log.Count){$points.Add((Get-DoomReplayCheckpoint $game $log.Count))}
}
function Record-Transition {
    $key="$($game.State):$($game.Options.Episode):$($game.Options.Map)"
    if($key -ne $script:lastTransition){$p=$game.World.ConsolePlayer;$transitions.Add(@{Tic=$log.Count;State=$game.State.ToString();Episode=$game.Options.Episode;Map=$game.Options.Map;Health=$p.Health;Armor=$p.ArmorPoints;Ammo=$p.Ammo.Clone();DidSecret=$p.DidSecret});$script:lastTransition=$key;Record-Point}
}
function Advance($Entry){
    $p=$game.World.ConsolePlayer;$pre=@{X=$p.Mobj.X.Data/65536.0;Y=$p.Mobj.Y.Data/65536.0}
    $cmd=$commands[0];$cmd.Clear();$cmd.ForwardMove=$Entry[0];$cmd.SideMove=$Entry[1];$cmd.AngleTurn=$Entry[2];$cmd.Buttons=$Entry[3]
    $null=$game.Update($commands);$log.Add(@($cmd.ForwardMove,$cmd.SideMove,$cmd.AngleTurn,$cmd.Buttons));Record-Transition
    if($log.Count%350 -eq 0){Record-Point};return $pre
}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]([int]$reference.Skill-1),$reference.Episode,$reference.Map);$null=$game.Update($commands);Record-Transition
    $expected=@{};foreach($sample in $reference.Trace){$expected[[int]$sample.Command]=$sample}
    foreach($entry in $reference.InputCommands){
        $pre=Advance $entry;$p=$game.World.ConsolePlayer
        if($expected.ContainsKey($log.Count)){
            $e=$expected[$log.Count]
            if($e.PSObject.Properties['Armor'] -and $p.ArmorPoints -ne $e.Armor){throw "Independent armor differs at command $($log.Count)."}
            if($pre.X -ne $e.X -or $pre.Y -ne $e.Y -or $p.Mobj.Z.Data/65536.0 -ne $e.Z -or $p.Health -ne $e.Health -or $p.KillCount -ne $e.Kills -or ($p.Ammo -join ',') -cne ($e.Ammo -join ',') -or ($p.Cards -join ',') -cne ($e.Cards -join ',') -or $p.ReadyWeapon.ToString() -cne $e.Weapon){throw "Independent route trace differs at command $($log.Count)."};$traceChecks++
        }
    }
    if($game.State -ne [GameState]::Intermission -or $game.World.ConsolePlayer.Health -ne $reference.FinalHealth -or $traceChecks -ne $reference.Trace.Count){throw 'Independent replay did not reproduce route completion.'}
    if($game.World.SecretExit -ne [bool]$SecretExit -or $game.Options.IntermissionInfo.NextLevel+1 -ne $ExpectedNextMap){throw 'Exit kind or advertised destination differs from the declared route.'}
    $exitInventory=@($game.World.ConsolePlayer.Health,$game.World.ConsolePlayer.ArmorPoints)+$game.World.ConsolePlayer.Ammo.Clone()
    for($n=0;$n -lt 700;$n++){
        $null=Advance @(0,0,0,$(if($n -in 35,70,105){2}else{0}))
        if($game.State -eq [GameState]::Level -and $game.Options.Episode -eq $reference.Episode -and $game.Options.Map -eq $ExpectedNextMap -and $game.World.LevelTime -ge 71){$continued=$true;break}
    }
    if(-not $continued){throw 'Ordinary use-button continuation did not enter the next map.'}
    $entryInventory=@($transitions[2].Health,$transitions[2].Armor)+$transitions[2].Ammo
    if(($exitInventory -join ',') -cne ($entryInventory -join ',')){throw 'Exit inventory changed before next-map spawn.'}
    if($SecretExit -and -not $transitions[2].DidSecret){throw 'Secret exit history was not retained at destination spawn.'}
    Record-Point
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    $data=@{Format='pwshDoom.InputReplay';Version=1;ContinueCampaign=$true;Episode=$reference.Episode;Map=$reference.Map;Skill=$reference.Skill;ExpectedNextMap=$ExpectedNextMap;SecretExit=[bool]$SecretExit;WadSha256=$wadHash;SourceFingerprint=Get-DoomReplaySourceFingerprint;InputCommands=$log.ToArray();Checkpoints=$points.ToArray();Transitions=$transitions.ToArray();Error=$failure;Passed=($null -eq $failure -and $continued);TraceChecks=$traceChecks;RouteResultSha256=(Get-FileHash $RouteResult).Hash;QualificationSourceSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Fresh independent fixed-command replay, compared with original driver position/inventory/combat samples; declared exit kind/destination checked before ordinary use presses through intermission and 71 tics in the destination with spawn inventory preserved. Secret routes also check retained secret history. Checkpoints are selected state/render data, not complete vanilla demo compatibility.'}
    Write-DoomInputReplay $Output $data
    if($content){$content.Dispose()}
}
"PASS: $traceChecks independent route samples; $($log.Count) commands; $($points.Count) checkpoints; next map entered."
