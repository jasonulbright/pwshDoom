# SPDX-License-Identifier: GPL-2.0-or-later
# Shared fixed-point PowerShell sprite-angle helpers for the host and renderer.
function Get-FastSlopeDiv {
    param([long]$Numerator,[long]$Denominator)
    if($Denominator -lt 512){return [uint32]2048}
    [uint64]$numUnsigned=[uint32]$Numerator;[uint64]$denUnsigned=[uint32]$Denominator
    [uint64]$scaledDen=$denUnsigned -shr 8
    [uint64]$answer=($numUnsigned -shl 3)/$scaledDen
    if($answer -gt 2048){return [uint32]2048}
    return [uint32]$answer
}

function Get-FastPointAngleData {
    param([int]$FromX,[int]$FromY,[int]$ToX,[int]$ToY,[uint32[]]$TanToAngleTable)
    [long]$x=(([long]$ToX-[long]$FromX)-band 0xFFFFFFFFL)
    [long]$y=(([long]$ToY-[long]$FromY)-band 0xFFFFFFFFL)
    if($x -ge 0x80000000L){$x-=0x100000000L}
    if($y -ge 0x80000000L){$y-=0x100000000L}
    if($x -eq 0 -and $y -eq 0){return [long]0}

    # Match Geometry.PointToAngleData's rare Fixed fallback, including 32-bit
    # negation wrap at int.MinValue. Stock Ultimate Doom maps do not approach it.
    if($x -eq -2147483648L -or $y -eq -2147483648L){
        if($x -ge 0){
            if($y -ge 0){
                if($x -gt $y){$slope=Get-FastSlopeDiv $y $x;return [long]$TanToAngleTable[$slope]}
                $slope=Get-FastSlopeDiv $x $y;return 0x40000000L-1-[long]$TanToAngleTable[$slope]
            }
            if($y -eq -2147483648L){$y=-2147483648L}else{$y=-$y}
            if($x -gt $y){$slope=Get-FastSlopeDiv $y $x;return ((-[long]$TanToAngleTable[$slope])-band 0xFFFFFFFFL)}
            $slope=Get-FastSlopeDiv $x $y;return 0xC0000000L+[long]$TanToAngleTable[$slope]
        }
        if($x -eq -2147483648L){$x=-2147483648L}else{$x=-$x}
        if($y -ge 0){
            if($x -gt $y){$slope=Get-FastSlopeDiv $y $x;return 0x80000000L-1-[long]$TanToAngleTable[$slope]}
            $slope=Get-FastSlopeDiv $x $y;return 0x40000000L+[long]$TanToAngleTable[$slope]
        }
        if($y -eq -2147483648L){$y=-2147483648L}else{$y=-$y}
        if($x -gt $y){$slope=Get-FastSlopeDiv $y $x;return 0x80000000L+[long]$TanToAngleTable[$slope]}
        $slope=Get-FastSlopeDiv $x $y;return 0xC0000000L-1-[long]$TanToAngleTable[$slope]
    }

    [bool]$negativeX=$x -lt 0;[bool]$negativeY=$y -lt 0
    if($negativeX){$x=-$x};if($negativeY){$y=-$y}
    [bool]$wide=$x -gt $y
    [uint32]$slope=if($wide){Get-FastSlopeDiv $y $x}else{Get-FastSlopeDiv $x $y}
    [long]$angle=$TanToAngleTable[$slope]
    if(-not $negativeX){
        if(-not $negativeY){if($wide){return $angle};return 0x40000000L-1-$angle}
        if($wide){return ((-$angle)-band 0xFFFFFFFFL)}
        return 0xC0000000L+$angle
    }
    if(-not $negativeY){if($wide){return 0x80000000L-1-$angle};return 0x40000000L+$angle}
    if($wide){return 0x80000000L+$angle}
    return 0xC0000000L-1-$angle
}

function Get-FastSpriteRotation {
    param([int]$ViewXData,[int]$ViewYData,[int]$ActorXData,[int]$ActorYData,[double]$ActorAngle,[uint32[]]$TanToAngleTable)
    [long]$viewToActorAngle=Get-FastPointAngleData $ViewXData $ViewYData $ActorXData $ActorYData $TanToAngleTable
    [uint32]$actorAngleData=[uint32][Math]::Round($ActorAngle*(4294967296.0/(2*[Math]::PI)))
    [uint64]$rotationBase=[uint64]$viewToActorAngle+0x90000000L+0x100000000L-[uint64]$actorAngleData
    [uint32]$rotationData=[uint32]($rotationBase%0x100000000L)
    return [int]($rotationData -shr 29)
}
