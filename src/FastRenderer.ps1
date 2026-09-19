# SPDX-License-Identifier: GPL-2.0-or-later
# pwshDoom numeric renderer. Geometry, rasterization, sprites and HUD are PowerShell.
# Uses the adopted GPL Doom data model; see ManagedDoom/ORIGIN.md for attribution.
Set-StrictMode -Version Latest

. "$PSScriptRoot/RenderLighting.ps1"
. "$PSScriptRoot/RenderFuzz.ps1"

function ConvertTo-RenderPatch {
    param($Patch)
    $data=[int[]]::new($Patch.Width*$Patch.Height)
    [Array]::Fill($data,-1)
    for($x=0;$x -lt $Patch.Width;$x++) {
        foreach($post in $Patch.Columns[$x]) {
            if($post.TopDelta -eq 255){continue}
            for($y=0;$y -lt $post.Length;$y++) {
                $row=$post.TopDelta+$y
                if($row -ge 0 -and $row -lt $Patch.Height){$data[$x*$Patch.Height+$row]=$post.Data[$post.Offset+$y]}
            }
        }
    }
    return @{Width=$Patch.Width;Height=$Patch.Height;Left=$Patch.LeftOffset;Top=$Patch.TopOffset;Data=$data}
}

function Get-RenderPatch {
    param($Context,$Patch)
    if(-not $Context.Patches.ContainsKey($Patch.Name)){$Context.Patches[$Patch.Name]=ConvertTo-RenderPatch $Patch}
    return $Context.Patches[$Patch.Name]
}

function New-FastRenderContext {
    param($Content,$World)
    $map=$World.Map
    $ctx=@{Content=$Content;World=$World;Lighting=(New-FastLightingTables);Pixels=[byte[]]::new(64000);Depth=[double[]]::new(64000);
        TopClip=[int[]]::new(320);BottomClip=[int[]]::new(320);Planes=[int[]]::new(53760);Patches=@{};Textures=@{};Hud=@{};
        Stack=[int[]]::new($map.Nodes.Length*2+4);Segments=[object[]]::new($map.Segs.Length);
        Nodes=[object[]]::new($map.Nodes.Length);Subsectors=$map.Subsectors;
        Flats=$Content.Flats.Flats;Colors=$Content.ColorMap.Data;SkyFlat=$Content.Flats.SkyFlatNumber;Sectors=$map.Sectors;Sides=$map.Sides;SpriteAtlas=[object[]]::new($Content.Sprites.spriteDefs.Length)}
    $sectorIndex=[Collections.Generic.Dictionary[object,int]]::new()
    for($i=0;$i -lt $map.Sectors.Length;$i++){$sectorIndex[$map.Sectors[$i]]=$i}
    $sideIndex=[Collections.Generic.Dictionary[object,int]]::new()
    for($i=0;$i -lt $map.Sides.Length;$i++){$sideIndex[$map.Sides[$i]]=$i}
    for($i=0;$i -lt $map.Segs.Length;$i++) {
        $seg=$map.Segs[$i];$ax=$seg.Vertex1.X.Data/65536.0;$ay=$seg.Vertex1.Y.Data/65536.0
        $bx=$seg.Vertex2.X.Data/65536.0;$by=$seg.Vertex2.Y.Data/65536.0
        $ctx.Segments[$i]=@{AX=$ax;AY=$ay;BX=$bx;BY=$by;Length=[Math]::Sqrt(($bx-$ax)*($bx-$ax)+($by-$ay)*($by-$ay));
            Offset=$seg.Offset.Data/65536.0;Side=$sideIndex[$seg.SideDef];Front=$sectorIndex[$seg.FrontSector];Back=$(if($null -eq $seg.BackSector){-1}else{$sectorIndex[$seg.BackSector]});Flags=[int]$seg.LineDef.Flags;Sector=$sectorIndex[$seg.FrontSector]}
    }
    for($i=0;$i -lt $map.Nodes.Length;$i++) {
        $node=$map.Nodes[$i]
        $ctx.Nodes[$i]=@{X=$node.X.Data/65536.0;Y=$node.Y.Data/65536.0;DX=$node.DX.Data/65536.0;DY=$node.DY.Data/65536.0;
            C0=$node.Children[0];C1=$node.Children[1]}
        for($child=0;$child -lt 2;$child++) {
            $b=$node.BoundingBox[$child]
            $ctx.Nodes[$i]['B'+$child]=@((($b[2].Data+$b[3].Data)/131072.0),(($b[0].Data+$b[1].Data)/131072.0),
                (($b[3].Data-$b[2].Data)/131072.0),(($b[0].Data-$b[1].Data)/131072.0))
        }
    }
    # Prepare all wall textures once. No object-valued fixed point operations in pixel loops.
    for($i=0;$i -lt $Content.Textures.Textures.Count;$i++) {
        $ctx.Textures[$i]=ConvertTo-RenderPatch $Content.Textures.Textures[$i].Composite
    }
    $ctx.Sky=ConvertTo-RenderPatch $map.SkyTexture.Composite
    $hudPatches=[Patches]::new($Content.Wad)
    $ctx.Hud.Background=Get-RenderPatch $ctx $hudPatches.Background
    $ctx.Hud.ArmsBackground=Get-RenderPatch $ctx $hudPatches.ArmsBackground
    foreach($field in 'TallNumbers','ShortNumbers','Faces','Keys') {
        $ctx.Hud[$field]=@($hudPatches.$field | ForEach-Object {Get-RenderPatch $ctx $_})
    }
    $ctx.Hud.Arms=@(foreach($pair in $hudPatches.Arms){foreach($patch in $pair){Get-RenderPatch $ctx $patch}})
    for($i=0;$i -lt $ctx.SpriteAtlas.Length;$i++){
        if($null -eq $Content.Sprites.spriteDefs[$i]){continue}
        $ctx.SpriteAtlas[$i]=@($Content.Sprites.spriteDefs[$i].Frames | ForEach-Object {
            @{Rotate=$_.Rotate;Flip=$_.Flip;Patches=@($_.Patches | ForEach-Object {Get-RenderPatch $ctx $_})}
        })
    }
    $ctx.Hud.Percent=Get-RenderPatch $ctx $hudPatches.TallPercent
    $ctx.Hud.Minus=Get-RenderPatch $ctx $hudPatches.TallMinus
    return $ctx
}

function Draw-FastPatch {
    param($Context,$Patch,[double]$Left,[double]$Top,[double]$Scale=1,[double]$Distance=0,
        [bool]$Flip=$false,[int]$Light=0,[int]$FirstColumn=0,[int]$EndColumn=320,[int]$MaxY=200)
    [int]$pw=$Patch.Width;[int]$ph=$Patch.Height;[int[]]$texels=$Patch.Data
    [byte[]]$pixels=$Context.Pixels;[double[]]$depth=$Context.Depth;[byte[]]$colors=$Context.Colors[$Light]
    [int]$x0=[Math]::Max($FirstColumn,[Math]::Ceiling($Left));[int]$x1=[Math]::Min($EndColumn,[Math]::Ceiling($Left+$pw*$Scale))
    [int]$y0=[Math]::Max(0,[Math]::Ceiling($Top));[int]$y1=[Math]::Min($MaxY,[Math]::Ceiling($Top+$ph*$Scale))
    if($Scale -eq 1 -and $Distance -eq 0) {
        for([int]$x=$x0;$x -lt $x1;$x++) {
            [int]$u=[Math]::Floor($x-$Left);if($Flip){$u=$pw-1-$u}
            [int]$t=$u*$ph+[int][Math]::Floor($y0-$Top);[int]$p=$y0*320+$x
            for([int]$y=$y0;$y -lt $y1;$y++) {
                [int]$color=$texels[$t++];if($color -ge 0){$pixels[$p]=$colors[$color]};$p+=320
            }
        }
        return
    }
    for([int]$x=$x0;$x -lt $x1;$x++) {
        [double]$uf=($x-$Left)/$Scale;[int]$u=$uf;if($u -gt $uf){$u--};if($u -ge $pw){$u=$pw-1};if($Flip){$u=$pw-1-$u}
        for([int]$y=$y0;$y -lt $y1;$y++) {
            [int]$p=$y*320+$x
            if($Distance -gt 0 -and $Distance -ge $depth[$p]){continue}
            [double]$vf=($y-$Top)/$Scale;[int]$v=$vf;if($v -gt $vf){$v--};if($v -ge $ph){$v=$ph-1};[int]$color=$texels[$u*$ph+$v]
            if($color -ge 0){$pixels[$p]=$colors[$color];$depth[$p]=$Distance}
        }
    }
}

function Draw-FastHudPatch {
    param($Context,$Patch,[int]$X,[int]$Y,[int]$FirstColumn,[int]$EndColumn)
    # HUD coordinates name the patch origin, including WAD offsets. HUD pixels
    # retain their palette indices rather than passing through world lighting.
    [int]$left=$X-$Patch.Left;[int]$top=$Y-$Patch.Top;[int]$height=$Patch.Height
    [int]$x0=[Math]::Max($FirstColumn,$left);[int]$x1=[Math]::Min($EndColumn,$left+$Patch.Width)
    [int]$y0=[Math]::Max(0,$top);[int]$y1=[Math]::Min(200,$top+$height)
    [int[]]$texels=$Patch.Data;[byte[]]$pixels=$Context.Pixels
    for([int]$column=$x0;$column -lt $x1;$column++){
        [int]$source=($column-$left)*$height+$y0-$top;[int]$destination=$y0*320+$column
        for([int]$row=$y0;$row -lt $y1;$row++){
            [int]$color=$texels[$source++];if($color -ge 0){$pixels[$destination]=$color};$destination+=320
        }
    }
}

function Draw-FastNumber {
    param($Context,[int]$Number,[int]$Right,[int]$Y,[bool]$Small,[int]$FirstColumn,[int]$EndColumn)
    $digits=if($Small){$Context.Hud.ShortNumbers}else{$Context.Hud.TallNumbers}
    if($Number -eq 1994){return}
    $negative=$Number -lt 0
    if($negative){$Number=-[Math]::Max(-99,$Number)}
    $remaining=3;$width=$digits[0].Width
    do {
        $patch=$digits[$Number%10];$Right-=$width
        Draw-FastHudPatch $Context $patch $Right $Y $FirstColumn $EndColumn
        $Number=[Math]::Floor($Number/10)
    } while($Number -gt 0 -and --$remaining -gt 0)
    if($negative){Draw-FastHudPatch $Context $Context.Hud.Minus ($Right-8) $Y $FirstColumn $EndColumn}
}

function Invoke-FastRender {
    param($Context,[int]$FirstColumn=0,[int]$EndColumn=320)
    $phaseWatch=[Diagnostics.Stopwatch]::StartNew();$world=$Context.World;$player=$world.ConsolePlayer;$camera=$player.Mobj
    [double]$cx=$camera.X;[double]$cy=$camera.Y;[double]$cz=$player.ViewZ
    [double]$angle=$camera.Angle
    [double]$co=[Math]::Cos($angle);[double]$si=[Math]::Sin($angle)
    [double]$ls=($FirstColumn-161)/160.0;[double]$rs=($EndColumn-159)/160.0
    [double]$lx=$si-$ls*$co;[double]$ly=-$co-$ls*$si;[double]$rx=$rs*$co-$si;[double]$ry=$rs*$si+$co
    [double]$alx=[Math]::Abs($lx);[double]$aly=[Math]::Abs($ly);[double]$arx=[Math]::Abs($rx);[double]$ary=[Math]::Abs($ry)
    [double]$aco=[Math]::Abs($co);[double]$asi=[Math]::Abs($si)
    [byte[]]$pixels=$Context.Pixels;[double[]]$depthBuffer=$Context.Depth
    [int[]]$planes=$Context.Planes
    [int[]]$topClip=$Context.TopClip;[int[]]$bottomClip=$Context.BottomClip
    $maskedColumns=[Collections.Generic.List[object]]::new()
    [Array]::Clear($pixels);[Array]::Clear($planes);[Array]::Fill($depthBuffer,[double]::PositiveInfinity)
    [Array]::Clear($topClip);[Array]::Fill($bottomClip,167)
    [int]$open=$EndColumn-$FirstColumn
    $stack=$Context.Stack;[int]$sp=1;$stack[0]=$Context.Nodes.Length-1
    $sky=$Context.Sky;[int[]]$skyData=$sky.Data;[int]$skyW=$sky.Width;[int]$skyH=$sky.Height
    while($sp -gt 0 -and $open -gt 0) {
        [int]$nodeIndex=$stack[--$sp]
        if($nodeIndex -ge 0 -and $nodeIndex -lt 32768) {
            $node=$Context.Nodes[$nodeIndex]
            # Doom child 0 is on the right of the partition vector.
            [int]$near=0;if(($cx-$node.X)*$node.DY-($cy-$node.Y)*$node.DX -lt 0){$near=1}
            for([int]$order=1;$order -ge 0;$order--) {
                [int]$child=$near -bxor $order;$box=$node['B'+$child]
                [double]$ox=$box[0]-$cx;[double]$oy=$box[1]-$cy;[double]$hw=$box[2];[double]$hh=$box[3]
                if($ox*$co+$oy*$si+$hw*$aco+$hh*$asi -lt 1){continue}
                if($ox*$lx+$oy*$ly+$hw*$alx+$hh*$aly -lt 0){continue}
                if($ox*$rx+$oy*$ry+$hw*$arx+$hh*$ary -lt 0){continue}
                $stack[$sp++]=$node['C'+$child]
            }
            continue
        }
        $ss=$Context.Subsectors[$nodeIndex -band 32767]
        for([int]$segIndex=$ss.FirstSeg;$segIndex -lt ($ss.FirstSeg+$ss.SegCount);$segIndex++) {
            $seg=$Context.Segments[$segIndex]
            [double]$ax=$seg.AX-$cx;[double]$ay=$seg.AY-$cy;[double]$bx=$seg.BX-$cx;[double]$by=$seg.BY-$cy
            if($ax*$by-$ay*$bx -ge 0){continue}
            [double]$z1=$ax*$co+$ay*$si;[double]$z2=$bx*$co+$by*$si
            if($z1 -lt 1 -and $z2 -lt 1){continue}
            [double]$r1=$ax*$si-$ay*$co;[double]$r2=$bx*$si-$by*$co
            [double]$u1=$seg.Offset;[double]$u2=$u1+$seg.Length
            if($z1 -lt 1){$f=(1-$z1)/($z2-$z1);$r1+=($r2-$r1)*$f;$u1+=($u2-$u1)*$f;$z1=1}
            if($z2 -lt 1){$f=(1-$z2)/($z1-$z2);$r2+=($r1-$r2)*$f;$u2+=($u1-$u2)*$f;$z2=1}
            [double]$sx1=160+160*$r1/$z1;[double]$sx2=160+160*$r2/$z2
            if($sx2 -le $sx1 -or $sx1 -ge $EndColumn -or $sx2 -le $FirstColumn){continue}
            [int]$x0=[Math]::Max($FirstColumn,[Math]::Ceiling($sx1-0.5));[int]$x1=[Math]::Min($EndColumn,[Math]::Ceiling($sx2-0.5))
            $front=$Context.Sectors[$seg.Front];$back=if($seg.Back -ge 0){$Context.Sectors[$seg.Back]}else{$null};$side=$Context.Sides[$seg.Side]
            [double]$fh=$front.FloorHeight;[double]$ch=$front.CeilingHeight
            [bool]$solid=$null -eq $back;[double]$bf=$fh;[double]$bc=$ch
            if(-not $solid){$bf=$back.FloorHeight;$bc=$back.CeilingHeight}
            [bool]$isSky=$front.CeilingFlat -eq $Context.SkyFlat
            [bool]$joinedSky=$isSky -and -not $solid -and $back.CeilingFlat -eq $Context.SkyFlat
            if($joinedSky){$ch=$bc}
            [int]$contrast=if($seg.AY -eq $seg.BY){-1}elseif($seg.AX -eq $seg.BX){1}else{0}
            [int]$baseLight=[Math]::Clamp(($front.LightLevel -shr 4)+$player.ExtraLight+$contrast,0,15)
            [int[]]$wallLightTable=$Context.Lighting.Scale[$baseLight]
            [double]$iz1=1/$z1;[double]$iz2=1/$z2;[double]$uz1=$u1/$z1;[double]$uz2=$u2/$z2
            for([int]$x=$x0;$x -lt $x1;$x++) {
                [int]$clipT=$topClip[$x];[int]$clipB=$bottomClip[$x];if($clipT -gt $clipB){continue}
                [double]$f=($x+0.5-$sx1)/($sx2-$sx1);[double]$distance=1/($iz1+($iz2-$iz1)*$f)
                [double]$texU=($uz1+($uz2-$uz1)*$f)*$distance+$side.TextureOffset
                [double]$ray=($x+0.5-160)/160;[double]$rayX=$co+$si*$ray;[double]$rayY=$si-$co*$ray
                [int]$wallT=[Math]::Ceiling(84-160*($ch-$cz)/$distance-0.5)
                [int]$wallB=[Math]::Floor(84-160*($fh-$cz)/$distance-0.5)
                # Draw the floor/ceiling exposed before this boundary. Near-first clip intervals
                # keep each opaque world pixel owned by a single segment.
                for([int]$plane=0;$plane -lt 2;$plane++) {
                    if($plane -eq 0){$py0=$clipT;$py1=[Math]::Min($clipB,$wallT-1)}
                    else{$py0=[Math]::Max($clipT,$wallB+1);$py1=$clipB}
                    [int]$planeId=1+$seg.Sector*2+$plane
                    if($plane -eq 0 -and $isSky){[int]$skyU=([int][Math]::Floor(($angle-[Math]::Atan($ray))*1024/(2*[Math]::PI))%$skyW+$skyW)%$skyW}
                    for([int]$y=$py0;$y -le $py1;$y++) {
                        [int]$p=$y*320+$x
                        if($plane -eq 0 -and $isSky){$pixels[$p]=$skyData[$skyU*$skyH+[Math]::Clamp($y+16,0,$skyH-1)];continue}
                        $planes[$p]=$planeId
                    }
                }
                [int]$portalT=[Math]::Ceiling(84-160*($bc-$cz)/$distance-0.5)
                [int]$portalB=[Math]::Floor(84-160*($bf-$cz)/$distance-0.5)
                [int]$wallLight=$wallLightTable[[Math]::Min(47,[int][Math]::Floor(2560.0/$distance))]
                if($player.FixedColorMap -gt 0){$wallLight=$player.FixedColorMap}
                [byte[]]$wallColors=$Context.Colors[$wallLight]
                for([int]$band=0;$band -lt 3;$band++) {
                    [int]$tex=0;[double]$textureTop=$ch
                    if($solid) {
                        if($band -gt 0){break};$tex=$side.MiddleTexture;$wy0=$wallT;$wy1=$wallB
                        if($tex -gt 0 -and ($seg.Flags -band 16)){$textureTop=$fh+$Context.Textures[$tex].Height}
                    } elseif($band -eq 0) {
                        if($bc -ge $ch -or $joinedSky){continue};$tex=$side.TopTexture;$wy0=$wallT;$wy1=$portalT-1
                        if($tex -gt 0 -and -not ($seg.Flags -band 8)){$textureTop=$bc+$Context.Textures[$tex].Height}
                    } elseif($band -eq 1) {
                        if($bf -le $fh){continue};$tex=$side.BottomTexture;$wy0=$portalB+1;$wy1=$wallB;$textureTop=$bf
                        if($seg.Flags -band 16){$textureTop=$ch}
                    } else {
                        $tex=$side.MiddleTexture;$wy0=[Math]::Max($wallT,$portalT);$wy1=[Math]::Min($wallB,$portalB)
                        $textureTop=[Math]::Min($ch,$bc)
                        if($tex -gt 0 -and ($seg.Flags -band 16)){$textureTop=[Math]::Max($fh,$bf)+$Context.Textures[$tex].Height}
                    }
                    if($tex -le 0){continue}
                    $texture=$Context.Textures[$tex];[int]$tw=$texture.Width;[int]$th=$texture.Height;[int[]]$td=$texture.Data
                    [int]$tu=([int][Math]::Floor($texU)%$tw+$tw)%$tw
                    [double]$vOrigin=$textureTop-$cz+$side.RowOffset
                    [int]$y0=[Math]::Max($clipT,$wy0);[int]$y1=[Math]::Min($clipB,$wy1)
                    if(-not $solid -and $band -eq 2){
                        # Portal openings remain visible to later geometry. Defer
                        # their transparent textures so that geometry cannot erase them.
                        if($y0 -le $y1){$maskedColumns.Add(@{X=$x;Y0=$y0;Y1=$y1;Distance=$distance;Origin=$vOrigin;U=$tu;Height=$th;Texels=$td;Colors=$wallColors})}
                        continue
                    }
                    for([int]$y=$y0;$y -le $y1;$y++) {
                        [double]$vf=$vOrigin+($y+0.5-84)*$distance/160;[int]$v=$vf;if($v -gt $vf){$v--}
                        $v=($v%$th+$th)%$th;[int]$color=$td[$tu*$th+$v]
                        if($color -ge 0){$p=$y*320+$x;$pixels[$p]=$wallColors[$color];$depthBuffer[$p]=$distance}
                    }
                }
                if($solid){$topClip[$x]=168;$bottomClip[$x]=-1;$open--}
                else {
                    $topClip[$x]=[Math]::Max($clipT,[Math]::Max($wallT,$portalT))
                    $bottomClip[$x]=[Math]::Min($clipB,[Math]::Min($wallB,$portalB))
                    if($topClip[$x] -gt $bottomClip[$x]){$open--}
                }
            }
        }
    }
    # PowerShell integer casts round to even. Correcting downward yields floor for
    # these finite Int32-range texture coordinates, avoiding a method binder per pixel.
    # Visplane-style horizontal spans: distance and light are constant on each row.
    # The ownership pass above handles clipping; this pass advances UV coordinates.
    for([int]$y=0;$y -lt 168;$y++) {
        [int]$row=$y*320;[int]$x=$FirstColumn
        while($x -lt $EndColumn) {
            [int]$id=$planes[$row+$x]
            if($id -eq 0){$x++;continue}
            $sector=$Context.Sectors[($id-1) -shr 1]
            if(($id-1) -band 1){$height=$sector.FloorHeight;$flat=$Context.Flats[$sector.FloorFlat].Data}
            else{$height=$sector.CeilingHeight;$flat=$Context.Flats[$sector.CeilingFlat].Data}
            [double]$d=($cz-$height)*160/($y+0.5-84)
            [int]$light=$Context.Lighting.Distance[[Math]::Clamp(($sector.LightLevel -shr 4)+$player.ExtraLight,0,15)][[Math]::Clamp([int][Math]::Floor($d/16),0,127)]
            if($player.FixedColorMap -gt 0){$light=$player.FixedColorMap}
            [byte[]]$colors=$Context.Colors[$light];[byte[]]$flatData=$flat
            [double]$du=$si*$d/160;[double]$dv=-$co*$d/160
            [double]$wu=$cx+$co*$d;[double]$wv=$cy+$si*$d
            do {
                [double]$uf=$wu+($x+0.5-160)*$du;[int]$u=$uf;if($u -gt $uf){$u--};$u=$u -band 63
                [double]$vf=-($wv+($x+0.5-160)*$dv);[int]$v=$vf;if($v -gt $vf){$v--};$v=$v -band 63
                [int]$p=$row+$x;$pixels[$p]=$colors[$flatData[$v*64+$u]];$depthBuffer[$p]=$d
                $x++
            } while($x -lt $EndColumn -and $planes[$row+$x] -eq $id)
        }
    }
    foreach($column in $maskedColumns){
        [int]$x=$column.X;[int]$height=$column.Height;[int]$source=$column.U*$height
        [double]$distance=$column.Distance;[double]$origin=$column.Origin
        [int[]]$texels=$column.Texels;[byte[]]$colors=$column.Colors
        for([int]$y=$column.Y0;$y -le $column.Y1;$y++){
            [int]$p=$y*320+$x;if($distance -ge $depthBuffer[$p]){continue}
            [double]$vf=$origin+($y+0.5-84)*$distance/160;[int]$v=$vf;if($v -gt $vf){$v--}
            if($v -lt 0 -or $v -ge $height){continue}
            [int]$color=$texels[$source+$v]
            if($color -ge 0){$pixels[$p]=$colors[$color];$depthBuffer[$p]=$distance}
        }
    }
    $geometryMs=$phaseWatch.Elapsed.TotalMilliseconds;$phaseWatch.Restart()
    # Actor sprites share the geometry depth buffer, including masked wall holes.
    $drawActors=$world.Actors
    foreach($candidate in $drawActors){
        if($candidate.Flags -band 0x40000){
            # Fuzz samples the actors behind it: draw farther sprites first.
            $drawActors=@($world.Actors|Sort-Object {($_.X-$cx)*$co+($_.Y-$cy)*$si} -Descending -Stable)
            break
        }
    }
    foreach($actor in $drawActors) {
        if($true) {
            [double]$dx=$actor.X-$cx;[double]$dy=$actor.Y-$cy
            [double]$d=$dx*$co+$dy*$si
            if($d -gt 1) {
                $frame=$Context.SpriteAtlas[$actor.Sprite][$actor.Frame -band 32767];[int]$rotation=0
                if($frame.Rotate){$a=[Math]::Atan2($dy,$dx)-$actor.Angle+9*[Math]::PI/8;$a=($a%(2*[Math]::PI)+2*[Math]::PI)%(2*[Math]::PI);$rotation=[Math]::Floor($a/( [Math]::PI/4))}
                $patch=$frame.Patches[$rotation];[double]$scale=160/$d
                [double]$left=160+($dx*$si-$dy*$co-$patch.Left)*$scale
                if($left -lt $EndColumn -and $left+$patch.Width*$scale -gt $FirstColumn) {
                    $light=if($actor.Frame -band 32768){0}else{$Context.Lighting.Scale[[Math]::Clamp(($actor.LightLevel -shr 4)+$player.ExtraLight,0,15)][[Math]::Min(47,[int][Math]::Floor(2560.0/$d))]}
                    if($player.FixedColorMap -gt 0){$light=$player.FixedColorMap}
                    if($actor.Flags -band 0x40000){
                        Draw-FastFuzzPatch $Context $patch $left (84-($actor.Z+$patch.Top-$cz)*$scale) $scale $d $frame.Flip[$rotation] $FirstColumn $EndColumn 168
                    }else{
                        Draw-FastPatch $Context $patch $left (84-($actor.Z+$patch.Top-$cz)*$scale) $scale $d $frame.Flip[$rotation] $light $FirstColumn $EndColumn 168
                    }
                }
            }
        }

    }
    $actorMs=$phaseWatch.Elapsed.TotalMilliseconds;$phaseWatch.Restart()
    Draw-FastPlayerSprites $Context $FirstColumn $EndColumn
    $weaponMs=$phaseWatch.Elapsed.TotalMilliseconds;$phaseWatch.Restart()
    Draw-FastHud $Context $FirstColumn $EndColumn
    $Context.Profile=@{GeometryMs=$geometryMs;ActorsMs=$actorMs;WeaponMs=$weaponMs;HudMs=$phaseWatch.Elapsed.TotalMilliseconds}
}

function Draw-FastPlayerSprites {
    param($Context,[int]$FirstColumn=0,[int]$EndColumn=320)
    $player=$Context.World.ConsolePlayer
    [int]$sectorLight=$Context.Lighting.Scale[[Math]::Clamp(($player.SectorLight -shr 4)+$player.ExtraLight,0,15)][47]
    [bool]$fuzz=$player.Invisibility -gt 128 -or ($player.Invisibility -band 8) -ne 0
    foreach($psp in $player.PlayerSprites){
        $frame=$Context.SpriteAtlas[$psp.Sprite][$psp.Frame -band 32767];$patch=$frame.Patches[0]
        [int]$light=$sectorLight
        if($psp.Frame -band 32768){$light=0}
        if($player.FixedColorMap -gt 0){$light=$player.FixedColorMap}
        if($fuzz){
            Draw-FastFuzzPatch $Context $patch ($psp.Sx-$patch.Left) ($psp.Sy-$patch.Top-16.25) 1 0 $frame.Flip[0] $FirstColumn $EndColumn 168
        }else{
            Draw-FastPatch $Context $patch ($psp.Sx-$patch.Left) ($psp.Sy-$patch.Top-16.25) 1 0 $frame.Flip[0] $light $FirstColumn $EndColumn 168
        }
    }
}

function Draw-FastHud {
    param($Context,[int]$FirstColumn=0,[int]$EndColumn=320)
    $player=$Context.World.ConsolePlayer
    Draw-FastHudPatch $Context $Context.Hud.Background 0 168 $FirstColumn $EndColumn
    Draw-FastHudPatch $Context $Context.Hud.ArmsBackground 104 168 $FirstColumn $EndColumn
    for($i=0;$i -lt 6;$i++){
        $owned=if($player.WeaponOwned[$i+1]){1}else{0}
        Draw-FastHudPatch $Context $Context.Hud.Arms[2*$i+$owned] (111+12*($i%3)) (172+10*[Math]::Floor($i/3)) $FirstColumn $EndColumn
    }
    Draw-FastHudPatch $Context $Context.Hud.Faces[$player.FaceIndex] 143 168 $FirstColumn $EndColumn
    $ammoType=$player.AmmoType
    if($ammoType -lt 4){Draw-FastNumber $Context $player.Ammo[$ammoType] 44 171 $false $FirstColumn $EndColumn}
    Draw-FastNumber $Context $player.Health 90 171 $false $FirstColumn $EndColumn
    Draw-FastNumber $Context $player.ArmorPoints 221 171 $false $FirstColumn $EndColumn
    foreach($x in 90,221){Draw-FastHudPatch $Context $Context.Hud.Percent $x 171 $FirstColumn $EndColumn}
    for($i=0;$i -lt 4;$i++) {
        $y=@(173,179,191,185)[$i]
        Draw-FastNumber $Context $player.Ammo[$i] 288 $y $true $FirstColumn $EndColumn
        Draw-FastNumber $Context $player.MaxAmmo[$i] 314 $y $true $FirstColumn $EndColumn
    }
    for($i=0;$i -lt 3;$i++) {
        $key=-1;if($player.Cards[$i]){$key=$i};if($player.Cards[$i+3]){$key=$i+3}
        if($key -ge 0){Draw-FastHudPatch $Context $Context.Hud.Keys[$key] 239 (171+10*$i) $FirstColumn $EndColumn}
    }
}
