# SPDX-License-Identifier: GPL-2.0-or-later
# Offset table from the adopted GPL ManagedDoom PowerShell renderer; see
# ManagedDoom/ORIGIN.md. Rasterization and per-column phase below are adaptations.
[int[]]$script:DoomFuzzOffsets=@(
    1,-1,1,-1,1,1,-1,1,1,-1,1,1,1,-1,1,1,1,-1,-1,-1,-1,
    1,-1,-1,1,1,1,1,-1,1,-1,1,1,-1,-1,1,1,-1,-1,-1,-1,1,1,
    1,1,-1,1,1,-1,1)

function Draw-FastFuzzPatch {
    param($Context,$Patch,[double]$Left,[double]$Top,[double]$Scale=1,[double]$Distance=0,
        [bool]$Flip=$false,[int]$FirstColumn=0,[int]$EndColumn=320,[int]$MaxY=168,[int[]]$ClipTopByColumn,[int[]]$ClipBottomByColumn)
    [int]$pw=$Patch.Width;[int]$ph=$Patch.Height;[int[]]$texels=$Patch.Data
    [byte[]]$pixels=$Context.Pixels;[double[]]$depth=$Context.Depth;[byte[]]$colors=$Context.Colors[6]
    [int]$x0=[Math]::Max($FirstColumn,[Math]::Ceiling($Left));[int]$x1=[Math]::Min($EndColumn,[Math]::Ceiling($Left+$pw*$Scale))
    [int]$y0=[Math]::Max(1,[Math]::Ceiling($Top));[int]$y1=[Math]::Min($MaxY-1,[Math]::Ceiling($Top+$ph*$Scale))
    if($x0 -ge $x1 -or $y0 -ge $y1){return}
    # Source row is independent of screen column. Compute its exact original
    # division/floor once per row, avoiding two dynamic Math calls per pixel.
    [int[]]$sourceRows=[int[]]::new($y1-$y0)
    for([int]$y=$y0;$y -lt $y1;$y++){$sourceRows[$y-$y0]=[Math]::Min($ph-1,[Math]::Floor(($y-$Top)/$Scale))}
    [int[]]$offsets=$script:DoomFuzzOffsets
    # Vertical neighbours are in the same worker's column. Seed from game time
    # and absolute column, never worker order or wall time. This is deliberately
    # not vanilla's one global phase advanced by every drawn fuzz pixel.
    [int]$tic=$Context.World.Tic
    for([int]$x=$x0;$x -lt $x1;$x++){
        [int]$u=[Math]::Min($pw-1,[Math]::Floor(($x-$Left)/$Scale));if($Flip){$u=$pw-1-$u}
        [int]$phase=([long]$tic*7+[long]$x*168)%50
        [int]$textureColumn=$u*$ph
        for([int]$y=$y0;$y -lt $y1;$y++){
            if($null -ne $ClipTopByColumn -and $y -lt $ClipTopByColumn[$x]){continue}
            if($null -ne $ClipBottomByColumn -and $y -gt $ClipBottomByColumn[$x]){continue}
            [int]$p=$y*320+$x
            if($Distance -gt 0 -and $Distance -ge $depth[$p]){continue}
            if($texels[$textureColumn+$sourceRows[$y-$y0]] -lt 0){continue}
            $pixels[$p]=$colors[$pixels[$p+320*$offsets[$phase]]]
            if($Distance -gt 0){$depth[$p]=$Distance}
            if(++$phase -eq 50){$phase=0}
        }
    }
}
