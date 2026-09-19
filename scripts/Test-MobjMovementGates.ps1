#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Use a fresh movement-gate receipt.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new();$cases=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed})}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $world=$game.World;$camera=$world.ConsolePlayer.Mobj
    # Equal numbers must select the same path whether Fixed instances are shared
    # or separately allocated. A grounded zero-momentum missile must not explode.
    foreach($mask in 0..7){
        $actor=$world.ThingAllocation.SpawnMobj($camera.X,$camera.Y,[Mobj]::OnFloorZ,[MobjType]::Rocket)
        $actor.Tics=10
        if($mask -band 1){$actor.Z=[Fixed]::new($actor.FloorZ.Data)}
        if($mask -band 2){$actor.MomZ=[Fixed]::new(0)}
        if($mask -band 4){$actor.MomX=[Fixed]::new(0);$actor.MomY=[Fixed]::new(0)}
        $random=$world.Random.Index;$state=$actor.State.Number;$z=$actor.Z.Data
        $actor.Run()
        $cases.Add(@{Mask=$mask;State=$actor.State.Number;Tics=$actor.Tics;Z=$actor.Z.Data;Flags=[int]$actor.Flags;RandomBefore=$random;RandomAfter=$world.Random.Index})
        Check "Stationary missile keeps state and flags, allocation mask $mask" ($actor.State.Number -eq $state -and ($actor.Flags -band [MobjFlags]::Missile) -ne 0)
        Check "Stationary missile advances state clock once, allocation mask $mask" ($actor.Tics -eq 9)
        Check "Stationary missile keeps position and RNG, allocation mask $mask" ($actor.Z.Data -eq $z -and $world.Random.Index -eq $random)
        $world.ThingAllocation.RemoveMobj($actor)
    }
    foreach($momentum in -1,1){
        $actor=$world.ThingAllocation.SpawnMobj($camera.X,$camera.Y,[Mobj]::OnFloorZ,[MobjType]::Rocket);$actor.Tics=10
        $actor.MomZ=[Fixed]::new($momentum);$floor=$actor.FloorZ.Data;$actor.Run()
        if($momentum -lt 0){Check 'Nonzero downward momentum still hits floor and explodes' (($actor.Flags -band [MobjFlags]::Missile) -eq 0)}
        else{Check 'One fixed-point unit upward still moves and remains a missile' ($actor.Z.Data -eq $floor+1 -and ($actor.Flags -band [MobjFlags]::Missile) -ne 0)}
        $world.ThingAllocation.RemoveMobj($actor)
    }
    $actor=$world.ThingAllocation.SpawnMobj($camera.X,$camera.Y,[Mobj]::OnFloorZ,[MobjType]::Skull)
    $actor.Flags=$actor.Flags -bor [MobjFlags]::SkullFly;$actor.MomX=[Fixed]::new(0);$actor.MomY=[Fixed]::new(0);$actor.Run()
    Check 'Zero-momentum skull charge still enters movement and clears charge flag' (($actor.Flags -band [MobjFlags]::SkullFly) -eq 0)
    if(@($checks|Where-Object {-not $_.Passed}).Count){throw 'Numeric movement-gate assertions failed.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();Cases=$cases.ToArray();WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;MobjSha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Doom/World/Mobj.sb.ps1").Hash;
        Meaning='Real E1M1 world and actual Mobj.Run/ThingMovement. Eight allocation-identity variants of a stationary grounded missile, nonzero vertical movement and zero-momentum skull charge. Direct test fixtures, not campaign completion. Numeric gate expectation follows id Software P_MobjThinker.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $($checks.Count) movement-gate assertions."
