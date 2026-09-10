# SPDX-License-Identifier: GPL-2.0-or-later
# Versioned numeric wire format. PowerShell packs/unpacks fields; standard .NET
# bulk copies transfer their bytes. No JSON/object serializer in the frame loop.
function ConvertTo-GameSnapshotBytes {
    param($Snapshot)
    $p=$Snapshot.ConsolePlayer;$ns=$Snapshot.Sectors.Count;$nd=$Snapshot.Sides.Count;$na=$Snapshot.Actors.Count;$nw=$p.PlayerSprites.Count
    [double[]]$values=[double[]]::new(48+5*$ns+5*$nd+7*$na+4*$nw)
    $values[0]=1;$values[1]=$Snapshot.Tic;$values[2]=$Snapshot.Fraction;$values[3]=$ns;$values[4]=$nd;$values[5]=$na;$values[6]=$nw
    $values[8]=$p.Mobj.X;$values[9]=$p.Mobj.Y;$values[10]=$p.Mobj.Angle;$values[11]=$p.ViewZ
    $values[12]=$p.ExtraLight;$values[13]=$p.FixedColorMap;$values[14]=$p.FaceIndex;$values[15]=$p.AmmoType
    $values[16]=$p.Health;$values[17]=$p.ArmorPoints;$values[18]=$p.Kills;$values[19]=$p.Secrets
    for($i=0;$i -lt 4;$i++){$values[20+$i]=$p.Ammo[$i];$values[24+$i]=$p.MaxAmmo[$i]}
    for($i=0;$i -lt 6;$i++){$values[28+$i]=[int]$p.Cards[$i]}
    for($i=0;$i -lt 9;$i++){$values[34+$i]=[int]$p.WeaponOwned[$i]}
    [int]$n=48
    foreach($s in $Snapshot.Sectors){$values[$n++]=$s.FloorHeight;$values[$n++]=$s.CeilingHeight;$values[$n++]=$s.FloorFlat;$values[$n++]=$s.CeilingFlat;$values[$n++]=$s.LightLevel}
    foreach($s in $Snapshot.Sides){$values[$n++]=$s.TextureOffset;$values[$n++]=$s.RowOffset;$values[$n++]=$s.MiddleTexture;$values[$n++]=$s.TopTexture;$values[$n++]=$s.BottomTexture}
    foreach($s in $Snapshot.Actors){$values[$n++]=$s.X;$values[$n++]=$s.Y;$values[$n++]=$s.Z;$values[$n++]=$s.Angle;$values[$n++]=$s.Sprite;$values[$n++]=$s.Frame;$values[$n++]=$s.LightLevel}
    foreach($s in $p.PlayerSprites){$values[$n++]=$s.Sprite;$values[$n++]=$s.Frame;$values[$n++]=$s.Sx;$values[$n++]=$s.Sy}
    $bytes=[byte[]]::new($values.Length*8);[Buffer]::BlockCopy($values,0,$bytes,0,$bytes.Length)
    return ,$bytes
}

function Read-GameSnapshotBytes {
    param([byte[]]$Bytes,$Previous)
    if($Bytes.Length -lt 384 -or $Bytes.Length%8 -ne 0){throw 'Malformed snapshot byte length.'}
    [double[]]$v=[double[]]::new($Bytes.Length/8);[Buffer]::BlockCopy($Bytes,0,$v,0,$Bytes.Length)
    [int]$ns=$v[3];[int]$nd=$v[4];[int]$na=$v[5];[int]$nw=$v[6]
    if($v[0] -ne 1 -or $ns -lt 0 -or $nd -lt 0 -or $na -lt 0 -or $nw -lt 0 -or 48L+5L*$ns+5L*$nd+7L*$na+4L*$nw -ne $v.Length){throw 'Malformed snapshot header.'}
    $state=$Previous
    if($null -eq $state) {$state=@{Sectors=@();Sides=@();Actors=@();ConsolePlayer=@{Mobj=@{};Ammo=[int[]]::new(4);MaxAmmo=[int[]]::new(4);Cards=[bool[]]::new(6);WeaponOwned=[bool[]]::new(9);PlayerSprites=@()}}}
    foreach($entry in @(@('Sectors',$ns),@('Sides',$nd),@('Actors',$na))) {
        if($state[$entry[0]].Count -ne $entry[1]) {
            $items=[object[]]::new($entry[1]);for($i=0;$i -lt $items.Length;$i++){$items[$i]=@{}}
            $state[$entry[0]]=$items
        }
    }
    $p=$state.ConsolePlayer
    if($p.PlayerSprites.Count -ne $nw){$p.PlayerSprites=[object[]]::new($nw);for($i=0;$i -lt $nw;$i++){$p.PlayerSprites[$i]=@{}}}
    $state.Tic=[int]$v[1];$state.Fraction=$v[2]
    $p.Mobj.X=$v[8];$p.Mobj.Y=$v[9];$p.Mobj.Angle=$v[10];$p.ViewZ=$v[11]
    $p.ExtraLight=[int]$v[12];$p.FixedColorMap=[int]$v[13];$p.FaceIndex=[int]$v[14];$p.AmmoType=[int]$v[15]
    $p.Health=[int]$v[16];$p.ArmorPoints=[int]$v[17];$p.Kills=[int]$v[18];$p.Secrets=[int]$v[19]
    for($i=0;$i -lt 4;$i++){$p.Ammo[$i]=$v[20+$i];$p.MaxAmmo[$i]=$v[24+$i]}
    for($i=0;$i -lt 6;$i++){$p.Cards[$i]=$v[28+$i] -ne 0}
    for($i=0;$i -lt 9;$i++){$p.WeaponOwned[$i]=$v[34+$i] -ne 0}
    [int]$n=48
    foreach($s in $state.Sectors){$s.FloorHeight=$v[$n++];$s.CeilingHeight=$v[$n++];$s.FloorFlat=[int]$v[$n++];$s.CeilingFlat=[int]$v[$n++];$s.LightLevel=[int]$v[$n++]}
    foreach($s in $state.Sides){$s.TextureOffset=$v[$n++];$s.RowOffset=$v[$n++];$s.MiddleTexture=[int]$v[$n++];$s.TopTexture=[int]$v[$n++];$s.BottomTexture=[int]$v[$n++]}
    foreach($s in $state.Actors){$s.X=$v[$n++];$s.Y=$v[$n++];$s.Z=$v[$n++];$s.Angle=$v[$n++];$s.Sprite=[int]$v[$n++];$s.Frame=[int]$v[$n++];$s.LightLevel=[int]$v[$n++]}
    foreach($s in $p.PlayerSprites){$s.Sprite=[int]$v[$n++];$s.Frame=[int]$v[$n++];$s.Sx=$v[$n++];$s.Sy=$v[$n++]}
    return $state
}

function Get-InterpolatedSnapshotBytes {
    param([double[]]$Previous,[double[]]$Current,[double]$Fraction)
    if($Previous.Length -ne $Current.Length){throw 'Interpolation snapshot sizes differ.'}
    $Fraction=[Math]::Clamp($Fraction,[double]0,[double]1)
    [double[]]$v=$Current.Clone();$v[2]=$Fraction
    for($i=8;$i -le 11;$i++){$v[$i]=$Previous[$i]+($Current[$i]-$Previous[$i])*$Fraction}
    [int]$n=48
    for($i=0;$i -lt [int]$v[3];$i++) {
        $v[$n]=$Previous[$n]+($Current[$n]-$Previous[$n])*$Fraction;$n++
        $v[$n]=$Previous[$n]+($Current[$n]-$Previous[$n])*$Fraction;$n+=4
    }
    $n+=5*[int]$v[4]
    for($i=0;$i -lt [int]$v[5];$i++) {
        for($axis=0;$axis -lt 3;$axis++){$v[$n]=$Previous[$n]+($Current[$n]-$Previous[$n])*$Fraction;$n++}
        $n+=4
    }
    $bytes=[byte[]]::new($v.Length*8);[Buffer]::BlockCopy($v,0,$bytes,0,$bytes.Length)
    return ,$bytes
}
