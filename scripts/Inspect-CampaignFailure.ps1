#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$RouteResult,[Parameter(Mandatory)][string]$Output,
    [string]$StartingReplay,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh diagnostic report.'}
$reference=Get-Content $RouteResult -Raw|ConvertFrom-Json
if($reference.WadSha256 -cne (Get-FileHash $Wad).Hash){throw 'IWAD differs from recorded input.'}
$startingReplayData=$null;$startingReplayHash=$null
if($reference.StartMode -eq 'QualifiedCampaignContinuation'){
    if(-not $StartingReplay){throw 'This route failure requires its qualified StartingReplay.'}
    $startingReplayHash=(Get-FileHash -LiteralPath $StartingReplay).Hash
    if($startingReplayHash -cne $reference.StartingReplaySha256){throw 'Starting replay differs from the route receipt.'}
    $startingReplayData=Get-Content -LiteralPath $StartingReplay -Raw|ConvertFrom-Json
    if($startingReplayData.Format -cne 'pwshDoom.InputReplay' -or -not $startingReplayData.Passed -or $startingReplayData.Error -or
       -not $startingReplayData.ContinueCampaign -or $startingReplayData.WadSha256 -cne $reference.WadSha256 -or
       $startingReplayData.Skill -ne $reference.Skill -or $startingReplayData.Episode -ne $reference.Episode -or
       $startingReplayData.ExpectedNextMap -ne $reference.Map -or $startingReplayData.Checkpoints[-1].Tic -ne $startingReplayData.InputCommands.Count){
        throw 'Starting replay is not a qualified same-IWAD, same-skill continuation into this route.'
    }
}elseif($StartingReplay){throw 'StartingReplay was supplied for a pistol-start route receipt.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$content=$null;$failure=$null;$events=[Collections.Generic.List[object]]::new();$n=0;$traceChecks=0
$nearbyActors=[Collections.Generic.List[object]]::new();$finalPlayer=$null
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    if($startingReplayData){
        $game.DeferedInitNew([GameSkill]([int]$startingReplayData.Skill-1),$startingReplayData.Episode,$startingReplayData.Map);$null=$game.Update($commands)
        foreach($entry in $startingReplayData.InputCommands){
            for($i=0;$i -lt 4;$i++){$commands[$i].Clear()}
            $commands[0].ForwardMove=$entry[0];$commands[0].SideMove=$entry[1];$commands[0].AngleTurn=$entry[2];$commands[0].Buttons=$entry[3]
            $null=$game.Update($commands)
        }
        $expectedCheckpoint=$startingReplayData.Checkpoints[-1];$actualCheckpoint=Get-DoomReplayCheckpoint $game $startingReplayData.InputCommands.Count
        $comparison=Compare-DoomReplayCheckpoints @($expectedCheckpoint) @($actualCheckpoint) $startingReplayData.InputCommands.Count
        if($game.State -ne [GameState]::Level -or $game.Options.Episode -ne $reference.Episode -or $game.Options.Map -ne $reference.Map -or
           $game.World.LevelTime -ne $expectedCheckpoint.State.LevelTime -or -not $comparison.Matched){throw 'Starting replay no longer reaches its recorded destination checkpoint.'}
        for($i=0;$i -lt 4;$i++){$commands[$i].Clear()}
    }else{$game.DeferedInitNew([GameSkill]([int]$reference.Skill-1),$reference.Episode,$reference.Map);$null=$game.Update($commands)}
    $expected=@{};foreach($sample in $reference.Trace){$expected[[int]$sample.Command]=$sample}
    foreach($entry in $reference.InputCommands){
        $p=$game.World.ConsolePlayer;$health=$p.Health;$preX=$p.Mobj.X.Data/65536.0;$preY=$p.Mobj.Y.Data/65536.0;$preZ=$p.Mobj.Z.Data
        $cmd=$commands[0];$cmd.Clear();$cmd.ForwardMove=$entry[0];$cmd.SideMove=$entry[1];$cmd.AngleTurn=$entry[2];$cmd.Buttons=$entry[3]
        $null=$game.Update($commands);$n++;$p=$game.World.ConsolePlayer;$s=$p.Mobj.Subsector.Sector
        if($p.Health -ne $health -or $p.Mobj.Z.Data -ne $preZ -or $n%35 -eq 0){
            $events.Add(@{Command=$n;LevelTime=$game.World.LevelTime;Input=$entry;HealthBefore=$health;Health=$p.Health;Armor=$p.ArmorPoints;X=$p.Mobj.X.Data/65536.0;Y=$p.Mobj.Y.Data/65536.0;Z=$p.Mobj.Z.Data/65536.0;Floor=$s.FloorHeight.Data/65536.0;Sector=[Array]::IndexOf($game.World.Map.Sectors,$s);Special=[int]$s.Special;Attacker=$(if($null -ne $p.Attacker){$p.Attacker.Type.ToString()}else{$null})})
        }
        if($expected.ContainsKey($n)){
            $e=$expected[$n]
            if($preX -ne $e.X -or $preY -ne $e.Y -or $p.Health -ne $e.Health -or $p.Mobj.Z.Data/65536.0 -ne $e.Z){throw "Recorded failure differs at command $n."}
            $traceChecks++
        }
    }
    # Read the final live actors, rather than assuming initial map things still
    # occupy their spawn positions. This does not advance or modify the world.
    $p=$game.World.ConsolePlayer;$mo=$p.Mobj;$s=$mo.Subsector.Sector
    $finalPlayer=@{X=$mo.X.Data/65536.0;Y=$mo.Y.Data/65536.0;Z=$mo.Z.Data/65536.0;Sector=$s.Number;Floor=$s.FloorHeight.Data/65536.0;Ceiling=$s.CeilingHeight.Data/65536.0;Health=$p.Health;Armor=$p.ArmorPoints;Weapon=$p.ReadyWeapon.ToString();Ammo=$p.Ammo.Clone()}
    $cap=$game.World.Thinkers.Cap;$actor=$cap.Next
    while(-not [object]::ReferenceEquals($actor,$cap)){
        if($actor -is [Mobj] -and -not [object]::ReferenceEquals($actor,$mo)){
            $dx=($actor.X.Data-$mo.X.Data)/65536.0;$dy=($actor.Y.Data-$mo.Y.Data)/65536.0
            if($dx*$dx+$dy*$dy -le 192*192){
                $nearbyActors.Add(@{Type=$actor.Type.ToString();X=$actor.X.Data/65536.0;Y=$actor.Y.Data/65536.0;Z=$actor.Z.Data/65536.0;Radius=$actor.Radius.Data/65536.0;Height=$actor.Height.Data/65536.0;Health=$actor.Health;Flags=[int]$actor.Flags;Solid=[bool]($actor.Flags -band [MobjFlags]::Solid);Shootable=[bool]($actor.Flags -band [MobjFlags]::Shootable);CountKill=[bool]($actor.Flags -band [MobjFlags]::CountKill)})
            }
        };$actor=$actor.Next
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Commands=$n;TraceChecks=$traceChecks;Events=$events.ToArray();FinalPlayer=$finalPlayer;FinalActorsWithin192=$nearbyActors.ToArray();StartMode=$reference.StartMode;StartingReplaySha256=$startingReplayHash;RouteResultSha256=(Get-FileHash $RouteResult).Hash;WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Fixed ordinary-command replay of a retained failure. Qualified campaign continuations are reconstructed from their source input replay and full destination checkpoint before suffix inputs are applied. End-of-tic attacker identifies the last damage source only; multiple same-tic sources are not separately instrumented. Selected original trace positions/health/height must match. Final nearby actors are read from the live thinker list without advancing or changing the world; proximity alone does not prove collision.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
if($failure){throw $failure}
"Reproduced $n commands and $traceChecks failure trace samples."
