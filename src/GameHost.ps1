# SPDX-License-Identifier: GPL-2.0-or-later
# Snapshots cross the process boundary as numeric data. Workers never
# invoke PowerShell class methods or read the live simulation while it is changing.
function New-GameRenderSnapshot {
    param($Game,[double]$Fraction=1)
    $Fraction=[Math]::Clamp($Fraction,[double]0,[double]1)
    $world=$Game.World;$player=$world.ConsolePlayer;$camera=$player.Mobj
    $sectors=[object[]]::new($world.Map.Sectors.Length)
    for($i=0;$i -lt $sectors.Length;$i++) {
        $s=$world.Map.Sectors[$i]
        $sectors[$i]=@{FloorHeight=($s.OldFloorHeight.Data+($s.FloorHeight.Data-$s.OldFloorHeight.Data)*$Fraction)/65536.0;
            CeilingHeight=($s.OldCeilingHeight.Data+($s.CeilingHeight.Data-$s.OldCeilingHeight.Data)*$Fraction)/65536.0;
            FloorFlat=$world.Specials.FlatTranslation[$s.FloorFlat];CeilingFlat=$world.Specials.FlatTranslation[$s.CeilingFlat];LightLevel=$s.LightLevel}
    }
    $sides=[object[]]::new($world.Map.Sides.Length)
    for($i=0;$i -lt $sides.Length;$i++) {
        $s=$world.Map.Sides[$i]
        $sides[$i]=@{TextureOffset=$s.TextureOffset.Data/65536.0;RowOffset=$s.RowOffset.Data/65536.0;
            MiddleTexture=$world.Specials.TextureTranslation[$s.MiddleTexture];TopTexture=$world.Specials.TextureTranslation[$s.TopTexture];BottomTexture=$world.Specials.TextureTranslation[$s.BottomTexture]}
    }
    $actors=[Collections.Generic.List[object]]::new();$cap=$world.Thinkers.Cap;$actor=$cap.Next
    while(-not [object]::ReferenceEquals($actor,$cap)) {
        if($actor -is [Mobj] -and -not [object]::ReferenceEquals($actor,$camera)) {
            $f=if($actor.Interpolate){$Fraction}else{1}
            $actors.Add(@{X=($actor.OldX.Data+($actor.X.Data-$actor.OldX.Data)*$f)/65536.0;
                Y=($actor.OldY.Data+($actor.Y.Data-$actor.OldY.Data)*$f)/65536.0;Z=($actor.OldZ.Data+($actor.Z.Data-$actor.OldZ.Data)*$f)/65536.0;
                Angle=$actor.Angle.Data*(2*[Math]::PI/4294967296.0);Sprite=[int]$actor.Sprite;Frame=$actor.Frame;LightLevel=$actor.Subsector.Sector.LightLevel})
        }
        $actor=$actor.Next
    }
    $weapon=[Collections.Generic.List[object]]::new()
    foreach($psp in $player.PlayerSprites) {
        if($null -ne $psp.State){$weapon.Add(@{Sprite=[int]$psp.State.Sprite;Frame=$psp.State.Frame;Sx=$psp.Sx.Data/65536.0;Sy=$psp.Sy.Data/65536.0})}
    }
    $f=if($camera.Interpolate){$Fraction}else{1}
    $angleDelta=(([double]$camera.Angle.Data-$player.OldAngle.Data+6442450944.0)%4294967296.0)-2147483648.0
    $angleValue=if($player.Interpolate){$player.OldAngle.Data+$angleDelta*$Fraction}else{$camera.Angle.Data}
    $viewZ=if($player.Interpolate -and $world.LevelTime -gt 1){($player.OldViewZ.Data+($player.ViewZ.Data-$player.OldViewZ.Data)*$Fraction)/65536.0}else{$player.ViewZ.Data/65536.0}
    return @{Tic=$world.LevelTime;Fraction=$Fraction;Sectors=$sectors;Sides=$sides;Actors=$actors.ToArray();ConsolePlayer=@{
        Mobj=@{X=($camera.OldX.Data+($camera.X.Data-$camera.OldX.Data)*$f)/65536.0;Y=($camera.OldY.Data+($camera.Y.Data-$camera.OldY.Data)*$f)/65536.0;Angle=$angleValue*(2*[Math]::PI/4294967296.0)};
        ViewZ=$viewZ;ExtraLight=$player.ExtraLight;FixedColorMap=$player.FixedColorMap;
        PlayerSprites=$weapon.ToArray();FaceIndex=$world.StatusBar.FaceIndex;AmmoType=[int][DoomInfo]::WeaponInfos[[int]$player.ReadyWeapon].Ammo;
        Ammo=$player.Ammo.Clone();MaxAmmo=$player.MaxAmmo.Clone();Cards=$player.Cards.Clone();WeaponOwned=$player.WeaponOwned.Clone();
        Health=$player.Health;ArmorPoints=$player.ArmorPoints;Kills=$player.KillCount;Secrets=$player.SecretCount}}
}

function Set-GameRenderSnapshot {
    param($Context,$Snapshot)
    $Context.World=$Snapshot;$Context.Sectors=$Snapshot.Sectors;$Context.Sides=$Snapshot.Sides
}

# Same NumericV1 layout as ConvertTo-GameSnapshotBytes, packed directly from the
# simulation-owned world. Keep the object path as an independent field oracle.
function Get-GameRenderSnapshotBytes {
    param($Game,[double]$Fraction=1)
    $Fraction=[Math]::Clamp($Fraction,[double]0,[double]1)
    $world=$Game.World;$player=$world.ConsolePlayer;$camera=$player.Mobj
    $actors=[Collections.Generic.List[object]]::new();$cap=$world.Thinkers.Cap;$actor=$cap.Next
    while(-not [object]::ReferenceEquals($actor,$cap)){
        if($actor -is [Mobj] -and -not [object]::ReferenceEquals($actor,$camera)){$actors.Add($actor)}
        $actor=$actor.Next
    }
    $weapon=[Collections.Generic.List[object]]::new()
    foreach($psp in $player.PlayerSprites){if($null -ne $psp.State){$weapon.Add($psp)}}
    $ns=$world.Map.Sectors.Length;$nd=$world.Map.Sides.Length
    [double[]]$v=[double[]]::new(48+5*$ns+5*$nd+7*$actors.Count+4*$weapon.Count)
    $v[0]=1;$v[1]=$world.LevelTime;$v[2]=$Fraction;$v[3]=$ns;$v[4]=$nd;$v[5]=$actors.Count;$v[6]=$weapon.Count
    $f=if($camera.Interpolate){$Fraction}else{1}
    $v[8]=($camera.OldX.Data+($camera.X.Data-$camera.OldX.Data)*$f)/65536.0
    $v[9]=($camera.OldY.Data+($camera.Y.Data-$camera.OldY.Data)*$f)/65536.0
    $angleDelta=(([double]$camera.Angle.Data-$player.OldAngle.Data+6442450944.0)%4294967296.0)-2147483648.0
    $angleValue=if($player.Interpolate){$player.OldAngle.Data+$angleDelta*$Fraction}else{$camera.Angle.Data}
    $v[10]=$angleValue*(2*[Math]::PI/4294967296.0)
    $v[11]=if($player.Interpolate -and $world.LevelTime -gt 1){($player.OldViewZ.Data+($player.ViewZ.Data-$player.OldViewZ.Data)*$Fraction)/65536.0}else{$player.ViewZ.Data/65536.0}
    $v[12]=$player.ExtraLight;$v[13]=$player.FixedColorMap;$v[14]=$world.StatusBar.FaceIndex
    $v[15]=[int][DoomInfo]::WeaponInfos[[int]$player.ReadyWeapon].Ammo
    $v[16]=$player.Health;$v[17]=$player.ArmorPoints;$v[18]=$player.KillCount;$v[19]=$player.SecretCount
    for($i=0;$i -lt 4;$i++){$v[20+$i]=$player.Ammo[$i];$v[24+$i]=$player.MaxAmmo[$i]}
    for($i=0;$i -lt 6;$i++){$v[28+$i]=[int]$player.Cards[$i]}
    for($i=0;$i -lt 9;$i++){$v[34+$i]=[int]$player.WeaponOwned[$i]}
    [int]$n=48
    foreach($s in $world.Map.Sectors){
        $v[$n++]=($s.OldFloorHeight.Data+($s.FloorHeight.Data-$s.OldFloorHeight.Data)*$Fraction)/65536.0
        $v[$n++]=($s.OldCeilingHeight.Data+($s.CeilingHeight.Data-$s.OldCeilingHeight.Data)*$Fraction)/65536.0
        $v[$n++]=$world.Specials.FlatTranslation[$s.FloorFlat];$v[$n++]=$world.Specials.FlatTranslation[$s.CeilingFlat];$v[$n++]=$s.LightLevel
    }
    foreach($s in $world.Map.Sides){
        $v[$n++]=$s.TextureOffset.Data/65536.0;$v[$n++]=$s.RowOffset.Data/65536.0
        $v[$n++]=$world.Specials.TextureTranslation[$s.MiddleTexture];$v[$n++]=$world.Specials.TextureTranslation[$s.TopTexture];$v[$n++]=$world.Specials.TextureTranslation[$s.BottomTexture]
    }
    foreach($s in $actors){
        $f=if($s.Interpolate){$Fraction}else{1}
        $v[$n++]=($s.OldX.Data+($s.X.Data-$s.OldX.Data)*$f)/65536.0
        $v[$n++]=($s.OldY.Data+($s.Y.Data-$s.OldY.Data)*$f)/65536.0
        $v[$n++]=($s.OldZ.Data+($s.Z.Data-$s.OldZ.Data)*$f)/65536.0
        $v[$n++]=$s.Angle.Data*(2*[Math]::PI/4294967296.0);$v[$n++]=[int]$s.Sprite;$v[$n++]=$s.Frame;$v[$n++]=$s.Subsector.Sector.LightLevel
    }
    foreach($s in $weapon){$v[$n++]=[int]$s.State.Sprite;$v[$n++]=$s.State.Frame;$v[$n++]=$s.Sx.Data/65536.0;$v[$n++]=$s.Sy.Data/65536.0}
    $bytes=[byte[]]::new($v.Length*8);[Buffer]::BlockCopy($v,0,$bytes,0,$bytes.Length)
    return ,$bytes
}
