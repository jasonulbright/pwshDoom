# SPDX-License-Identifier: GPL-2.0-or-later
# Versioned numeric wire format. PowerShell packs/unpacks fields; standard .NET
# bulk copies transfer their bytes. No JSON/object serializer in the frame loop.
. "$PSScriptRoot/SpriteProjection.ps1"
function ConvertTo-GameSnapshotBytes {
    param($Snapshot)
    $p=$Snapshot.ConsolePlayer;$ns=$Snapshot.Sectors.Count;$nd=$Snapshot.Sides.Count;$na=$Snapshot.Actors.Count;$nw=$p.PlayerSprites.Count
    [double[]]$values=[double[]]::new(48+5*$ns+5*$nd+8*$na+4*$nw)
    $values[0]=3;$values[1]=$Snapshot.Tic;$values[2]=$Snapshot.Fraction;$values[3]=$ns;$values[4]=$nd;$values[5]=$na;$values[6]=$nw
    # Header slot 7 marks an actor array whose far-to-near fuzz order is ready.
    if($Snapshot -is [Collections.IDictionary] -and $Snapshot.Contains('ActorsDepthSortedForFuzz') -and $Snapshot.ActorsDepthSortedForFuzz){$values[7]=1}
    $values[8]=$p.Mobj.X;$values[9]=$p.Mobj.Y;$values[10]=$p.Mobj.Angle;$values[11]=$p.ViewZ
    $values[12]=$p.ExtraLight;$values[13]=$p.FixedColorMap;$values[14]=$p.FaceIndex;$values[15]=$p.AmmoType
    # Previously reserved header slot: discrete player-sector light, never interpolated.
    $values[43]=$p.SectorLight
    $values[44]=$p.Invisibility
    $values[45]=$p.PaletteNumber
    $values[16]=$p.Health;$values[17]=$p.ArmorPoints;$values[18]=$p.Kills;$values[19]=$p.Secrets
    for($i=0;$i -lt 4;$i++){$values[20+$i]=$p.Ammo[$i];$values[24+$i]=$p.MaxAmmo[$i]}
    for($i=0;$i -lt 6;$i++){$values[28+$i]=[int]$p.Cards[$i]}
    for($i=0;$i -lt 9;$i++){$values[34+$i]=[int]$p.WeaponOwned[$i]}
    [int]$n=48
    foreach($s in $Snapshot.Sectors){$values[$n++]=$s.FloorHeight;$values[$n++]=$s.CeilingHeight;$values[$n++]=$s.FloorFlat;$values[$n++]=$s.CeilingFlat;$values[$n++]=$s.LightLevel}
    foreach($s in $Snapshot.Sides){$values[$n++]=$s.TextureOffset;$values[$n++]=$s.RowOffset;$values[$n++]=$s.MiddleTexture;$values[$n++]=$s.TopTexture;$values[$n++]=$s.BottomTexture}
    foreach($s in $Snapshot.Actors){$values[$n++]=$s.X;$values[$n++]=$s.Y;$values[$n++]=$s.Z;$values[$n++]=$s.Angle;$values[$n++]=$s.Sprite;$values[$n++]=$s.Frame;$values[$n++]=$s.LightLevel}
    foreach($s in $p.PlayerSprites){$values[$n++]=$s.Sprite;$values[$n++]=$s.Frame;$values[$n++]=$s.Sx;$values[$n++]=$s.Sy}
    # Append discrete actor flags; existing position/weapon offsets stay fixed.
    foreach($s in $Snapshot.Actors){$values[$n++]=$s.Flags}
    $bytes=[byte[]]::new($values.Length*8);[Buffer]::BlockCopy($values,0,$bytes,0,$bytes.Length)
    return ,$bytes
}

# A live renderer sends the same interpolated world snapshot to every process
# stripe. Prepare a conservative, exact projected-column mask once in the host
# so each stripe can skip actors that cannot touch its columns. Keep ordinary
# simulation/object snapshots as NumericV3; the worker-only extension is V4.
function Add-GameRenderActorWorkerMasks {
    param([byte[]]$Bytes,$Pool)
    if($Bytes.Length -lt 384 -or $Bytes.Length%8 -ne 0 -or $Bytes.Length -eq 64000 -or
       $null -eq $Pool.SpriteAtlas -or $null -eq $Pool.PlaneFineSine -or $null -eq $Pool.TanToAngleTable -or
       -not (Get-Command Get-FastSpriteRotation -ErrorAction SilentlyContinue)) { return ,$Bytes }
    [double[]]$source=[double[]]::new($Bytes.Length/8);[Buffer]::BlockCopy($Bytes,0,$source,0,$Bytes.Length)
    if($source[0] -ne 3){return ,$Bytes}
    [int]$sectorCount=$source[3];[int]$sideCount=$source[4];[int]$actorCount=$source[5];[int]$weaponCount=$source[6]
    [long]$expected=48L+5L*$sectorCount+5L*$sideCount+8L*$actorCount+4L*$weaponCount
    if($sectorCount -lt 0 -or $sideCount -lt 0 -or $actorCount -lt 0 -or $weaponCount -lt 0 -or $expected -ne $source.Length){
        throw 'Malformed NumericV3 render snapshot.'
    }
    [double[]]$values=[double[]]::new($source.Length+$actorCount)
    [Array]::Copy($source,$values,$source.Length);$values[0]=4
    [int]$actorStart=48+5*$sectorCount+5*$sideCount
    [int]$actorFlagsStart=$actorStart+7*$actorCount+4*$weaponCount
    [int]$workerMaskStart=$source.Length
    [int[]]$fineSine=$Pool.PlaneFineSine
    [uint32]$viewAngleData=[uint32]([long][Math]::Round(4294967296.0*($source[10]/(2*[Math]::PI))) -band 0xFFFFFFFFL)
    [int]$spriteFineIndex=$viewAngleData -shr 19
    [int]$viewSinData=$fineSine[$spriteFineIndex];[int]$viewCosData=$fineSine[$spriteFineIndex+2048]
    [int]$viewXData=[Math]::Truncate(65536.0*$source[8]);[int]$viewYData=[Math]::Truncate(65536.0*$source[9])
    [int]$spriteFracBits=16;[int]$spriteMinZData=4 -shl 16
    [long]$allWorkersMask=0
    for([int]$i=0;$i -lt $Pool.Workers.Count;$i++){$allWorkersMask=$allWorkersMask -bor (1L -shl $i)}
    for([int]$i=0;$i -lt $actorCount;$i++){
        [int]$actorOffset=$actorStart+7*$i
        [int]$actorXData=[Math]::Truncate($source[$actorOffset]*65536.0);[int]$actorYData=[Math]::Truncate($source[$actorOffset+1]*65536.0)
        [int]$trXData=$actorXData-$viewXData;[int]$trYData=$actorYData-$viewYData
        [int]$gxtData=(([long]$trXData*[long]$viewCosData)-shr $spriteFracBits)
        [int]$gytData=(([long]$trYData*[long]$viewSinData)-shr $spriteFracBits)
        [int]$tzData=$gxtData+$gytData;[long]$workerMask=0
        if($tzData -ge $spriteMinZData){
            [int]$gxtLateralData=-(([long]$trXData*[long]$viewSinData)-shr $spriteFracBits)
            [int]$gytLateralData=(([long]$trYData*[long]$viewCosData)-shr $spriteFracBits)
            [int]$txData=-($gytLateralData+$gxtLateralData)
            [long]$tzLimitRaw=(([long]$tzData -shl 2) -band 0xFFFFFFFFL)
            if($tzLimitRaw -ge 0x80000000L){$tzLimitRaw-=0x100000000L}
            [int]$tzLimitData=$tzLimitRaw
            if([Math]::Abs([long]$txData) -le $tzLimitData){
                [int]$xScaleData=[Math]::Truncate((10485760.0/[double]$tzData)*65536.0)
                if($xScaleData -gt 0){
                    [int]$sprite=[int]$source[$actorOffset+4];[int]$frameIndex=([int]$source[$actorOffset+5] -band 0x7F)
                    $frame=$null
                    if($sprite -ge 0 -and $sprite -lt $Pool.SpriteAtlas.Length -and $frameIndex -ge 0 -and $frameIndex -lt $Pool.SpriteAtlas[$sprite].Length){$frame=$Pool.SpriteAtlas[$sprite][$frameIndex]}
                    if($null -eq $frame -or $null -eq $frame.Patches -or $frame.Patches.Count -eq 0){$workerMask=$allWorkersMask}
                    else{
                        [int]$rotation=0
                        if($frame.Rotate){$rotation=Get-FastSpriteRotation $viewXData $viewYData $actorXData $actorYData $source[$actorOffset+3] $Pool.TanToAngleTable}
                        if($rotation -lt 0 -or $rotation -ge $frame.Patches.Count -or $null -eq $frame.Patches[$rotation]){$workerMask=$allWorkersMask}
                        else{
                            $patch=$frame.Patches[$rotation]
                            [int]$leftOffsetData=$txData-($patch.Left -shl $spriteFracBits)
                            [int]$leftFracData=(160 -shl $spriteFracBits)+([long]$leftOffsetData*[long]$xScaleData -shr $spriteFracBits)
                            [int]$rightOffsetData=$leftOffsetData+($patch.Width -shl $spriteFracBits)
                            [int]$rightFracData=(160 -shl $spriteFracBits)+([long]$rightOffsetData*[long]$xScaleData -shr $spriteFracBits)
                            [int]$firstSpriteColumn=$leftFracData -shr $spriteFracBits
                            [int]$lastSpriteColumn=($rightFracData -shr $spriteFracBits)-1
                            foreach($worker in $Pool.Workers){
                                if($firstSpriteColumn -lt $worker.End -and $lastSpriteColumn -ge $worker.First){$workerMask=$workerMask -bor (1L -shl $worker.Index)}
                            }
                        }
                    }
                }
            }
        }
        $values[$workerMaskStart+$i]=$workerMask
    }
    [byte[]]$result=[byte[]]::new($values.Length*8);[Buffer]::BlockCopy($values,0,$result,0,$result.Length)
    return ,$result
}

function Read-GameSnapshotBytes {
    param([byte[]]$Bytes,$Previous)
    if($Bytes.Length -lt 384 -or $Bytes.Length%8 -ne 0){throw 'Malformed snapshot byte length.'}
    [double[]]$v=[double[]]::new($Bytes.Length/8);[Buffer]::BlockCopy($Bytes,0,$v,0,$Bytes.Length)
    [int]$ns=$v[3];[int]$nd=$v[4];[int]$na=$v[5];[int]$nw=$v[6]
    [double]$version=$v[0]
    [long]$expectedLength=if($version -eq 4){48L+5L*$ns+5L*$nd+9L*$na+4L*$nw}else{48L+5L*$ns+5L*$nd+8L*$na+4L*$nw}
    if($version -notin 3,4 -or $v[7] -notin 0,1 -or $ns -lt 0 -or $nd -lt 0 -or $na -lt 0 -or $nw -lt 0 -or $expectedLength -ne $v.Length){throw 'Malformed snapshot header.'}
    if(-not [double]::IsFinite($v[45]) -or $v[45] -lt 0 -or $v[45] -gt 13 -or $v[45] -ne [Math]::Floor($v[45])){throw 'Invalid snapshot palette.'}
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
    $state.Tic=[int]$v[1];$state.Fraction=$v[2];$state.ActorsDepthSortedForFuzz=($v[7] -eq 1)
    $p.Mobj.X=$v[8];$p.Mobj.Y=$v[9];$p.Mobj.Angle=$v[10];$p.ViewZ=$v[11]
    $p.ExtraLight=[int]$v[12];$p.FixedColorMap=[int]$v[13];$p.FaceIndex=[int]$v[14];$p.AmmoType=[int]$v[15]
    $p.SectorLight=[int]$v[43]
    $p.Invisibility=[int]$v[44]
    $p.PaletteNumber=[int]$v[45]
    $p.Health=[int]$v[16];$p.ArmorPoints=[int]$v[17];$p.Kills=[int]$v[18];$p.Secrets=[int]$v[19]
    for($i=0;$i -lt 4;$i++){$p.Ammo[$i]=$v[20+$i];$p.MaxAmmo[$i]=$v[24+$i]}
    for($i=0;$i -lt 6;$i++){$p.Cards[$i]=$v[28+$i] -ne 0}
    for($i=0;$i -lt 9;$i++){$p.WeaponOwned[$i]=$v[34+$i] -ne 0}
    [int]$n=48
    foreach($s in $state.Sectors){$s.FloorHeight=$v[$n++];$s.CeilingHeight=$v[$n++];$s.FloorFlat=[int]$v[$n++];$s.CeilingFlat=[int]$v[$n++];$s.LightLevel=[int]$v[$n++]}
    foreach($s in $state.Sides){$s.TextureOffset=$v[$n++];$s.RowOffset=$v[$n++];$s.MiddleTexture=[int]$v[$n++];$s.TopTexture=[int]$v[$n++];$s.BottomTexture=[int]$v[$n++]}
    foreach($s in $state.Actors){$s.X=$v[$n++];$s.Y=$v[$n++];$s.Z=$v[$n++];$s.Angle=$v[$n++];$s.Sprite=[int]$v[$n++];$s.Frame=[int]$v[$n++];$s.LightLevel=[int]$v[$n++]}
    foreach($s in $p.PlayerSprites){$s.Sprite=[int]$v[$n++];$s.Frame=[int]$v[$n++];$s.Sx=$v[$n++];$s.Sy=$v[$n++]}
    foreach($s in $state.Actors){$s.Flags=[int]$v[$n++]}
    if($version -eq 4){
        for($i=0;$i -lt $na;$i++){
            [double]$workerMask=$v[$n++]
            if(-not [double]::IsFinite($workerMask) -or $workerMask -lt 0 -or $workerMask -gt 4294967295 -or $workerMask -ne [Math]::Floor($workerMask)){throw 'Invalid actor worker mask.'}
            $state.Actors[$i].WorkerMask=[long]$workerMask
        }
    }
    else{foreach($s in $state.Actors){$s.WorkerMask=-1L}}
    if($n -ne $v.Length){throw 'Malformed snapshot payload length.'}
    return $state
}

function Get-InterpolatedSnapshotBytes {
    # DeferFuzzSort reproduces the previous worker-side sort only for paired profiling.
    param([double[]]$Previous,[double[]]$Current,[double]$Fraction,[switch]$DeferFuzzSort)
    if($Previous.Length -ne $Current.Length){throw 'Interpolation snapshot sizes differ.'}
    if($Previous.Length -lt 48){throw 'Malformed interpolation snapshot length.'}
    if($Previous[0] -ne 3 -or $Current[0] -ne 3 -or $Previous[7] -ne 0 -or $Current[7] -ne 0){throw 'Interpolation endpoints must be unsorted NumericV3 snapshots.'}
    if($Previous[3] -ne $Current[3] -or $Previous[4] -ne $Current[4] -or $Previous[5] -ne $Current[5] -or $Previous[6] -ne $Current[6]){throw 'Interpolation snapshot layouts differ.'}
    [int]$expectedLength=48+5*[int]$Previous[3]+5*[int]$Previous[4]+8*[int]$Previous[5]+4*[int]$Previous[6]
    if($Previous.Length -ne $expectedLength){throw 'Malformed interpolation snapshot length.'}
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
    # Spectre fuzz samples the already-rendered framebuffer, so its actor must
    # be drawn after the actors behind it. All renderer processes receive this
    # same final interpolated packet; sort once here instead of once per worker.
    [int]$actorCount=$v[5];[int]$weaponCount=$v[6]
    [int]$actorStart=48+5*[int]$v[3]+5*[int]$v[4]
    [int]$actorFlagsStart=$actorStart+7*$actorCount+4*$weaponCount
    [bool]$hasFuzzActor=$false
    for([int]$i=0;$i -lt $actorCount;$i++){if(([int]$v[$actorFlagsStart+$i] -band 0x40000) -ne 0){$hasFuzzActor=$true;break}}
    if($hasFuzzActor -and -not $DeferFuzzSort){
        if($actorCount -gt 1){
            [double]$viewX=$v[8];[double]$viewY=$v[9];[double]$viewAngle=$v[10]
            [double]$cos=[Math]::Cos($viewAngle);[double]$sin=[Math]::Sin($viewAngle)
            [double[]]$sortDepths=[double[]]::new($actorCount)
            [int[]]$actorOrder=[int[]]::new($actorCount)
            for([int]$i=0;$i -lt $actorCount;$i++){
                [int]$actorOffset=$actorStart+7*$i
                $sortDepths[$i]=($v[$actorOffset]-$viewX)*$cos+($v[$actorOffset+1]-$viewY)*$sin
                $actorOrder[$i]=$i
            }
            $ordered=@($actorOrder|Sort-Object { $sortDepths[$_] } -Descending -Stable)
            [double[]]$unsorted=$v.Clone()
            for([int]$destination=0;$destination -lt $actorCount;$destination++){
                [int]$source=[int]$ordered[$destination]
                [Array]::Copy($unsorted,$actorStart+7*$source,$v,$actorStart+7*$destination,7)
                $v[$actorFlagsStart+$destination]=$unsorted[$actorFlagsStart+$source]
            }
        }
        $v[7]=1
    }
    $bytes=[byte[]]::new($v.Length*8);[Buffer]::BlockCopy($v,0,$bytes,0,$bytes.Length)
    return ,$bytes
}
