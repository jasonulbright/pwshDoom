# SPDX-License-Identifier: GPL-2.0-or-later
# Offset table from the adopted GPL ManagedDoom PowerShell renderer; see
# ManagedDoom/ORIGIN.md. Rasterization and per-column phase below are adaptations.
[int[]]$script:DoomFuzzOffsets=@(
    1,-1,1,-1,1,1,-1,1,1,-1,1,1,1,-1,1,1,1,-1,-1,-1,-1,
    1,-1,-1,1,1,1,1,-1,1,-1,1,1,-1,-1,1,1,-1,-1,-1,-1,1,1,
    1,1,-1,1,1,-1,1)

function Draw-FastFuzzPatch {
    param($Context,$Patch,[double]$Left,[double]$Top,[double]$Scale=1,[double]$Distance=0,
        [bool]$Flip=$false,[int]$FirstColumn=0,[int]$EndColumn=320,[int]$MaxY=168)
    [int]$pw=$Patch.Width;[int]$ph=$Patch.Height;[int[]]$texels=$Patch.Data
    [byte[]]$pixels=$Context.Pixels;[double[]]$depth=$Context.Depth;[byte[]]$colors=$Context.Colors[6]
    [int]$x0=[Math]::Max($FirstColumn,[Math]::Ceiling($Left));[int]$x1=[Math]::Min($EndColumn,[Math]::Ceiling($Left+$pw*$Scale))
    [int]$y0=[Math]::Max(1,[Math]::Ceiling($Top));[int]$y1=[Math]::Min($MaxY-1,[Math]::Ceiling($Top+$ph*$Scale))
    # Vertical neighbours are in the same worker's column. Seed from game time
    # and absolute column, never worker order or wall time. This is deliberately
    # not vanilla's one global phase advanced by every drawn fuzz pixel.
    [int]$tic=$Context.World.Tic
    for([int]$x=$x0;$x -lt $x1;$x++){
        [int]$u=[Math]::Min($pw-1,[Math]::Floor(($x-$Left)/$Scale));if($Flip){$u=$pw-1-$u}
        [int]$phase=([long]$tic*7+[long]$x*168)%50
        for([int]$y=$y0;$y -lt $y1;$y++){
            [int]$p=$y*320+$x
            if($Distance -gt 0 -and $Distance -ge $depth[$p]){continue}
            [int]$v=[Math]::Min($ph-1,[Math]::Floor(($y-$Top)/$Scale))
            if($texels[$u*$ph+$v] -lt 0){continue}
            $pixels[$p]=$colors[$pixels[$p+320*$script:DoomFuzzOffsets[$phase]]]
            if($Distance -gt 0){$depth[$p]=$Distance}
            if(++$phase -eq 50){$phase=0}
        }
    }
}
