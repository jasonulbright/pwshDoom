# SPDX-License-Identifier: GPL-2.0-or-later
# pwshDoom numeric renderer. Geometry, rasterization, sprites and HUD are PowerShell.
# Uses the adopted GPL Doom data model; see ManagedDoom/ORIGIN.md for attribution.
Set-StrictMode -Version Latest

. "$PSScriptRoot/RenderLighting.ps1"
. "$PSScriptRoot/RenderFuzz.ps1"
. "$PSScriptRoot/SpriteProjection.ps1"

$script:FastPlaneTables=$null
function Get-FastPlaneTables {
    if($null -ne $script:FastPlaneTables){return $script:FastPlaneTables}
    [int[]]$angleToX=[int[]]::new([Trig]::FineAngleCount/2)
    [int]$focalFine=([Trig]::FineAngleCount/4)+([ThreeDRenderer]::fineFov/2)
    $focalAngle=[Angle]::new([uint32]($focalFine -shl [Trig]::AngleToFineShift))
    $focalLength=[Fixed]::FromInt(160)/[Trig]::Tan($focalAngle)
    for([int]$i=0;$i -lt $angleToX.Length;$i++){
        $tan=[Trig]::TanFromInt($i);[int]$screenX=0
        if($tan.Data -gt [Fixed]::FromInt(2).Data){$screenX=-1}
        elseif($tan.Data -lt [Fixed]::FromInt(-2).Data){$screenX=321}
        else{$screenX=[Math]::Clamp(([Fixed]::FromInt(160)-($tan*$focalLength)).ToIntCeiling(),-1,321)}
        $angleToX[$i]=$screenX
    }
    [uint32[]]$columnAngle=[uint32[]]::new(320);[int[]]$distanceScale=[int[]]::new(320)
    for([int]$x=0;$x -lt 320;$x++){
        [int]$i=0;while($angleToX[$i] -gt $x){$i++}
        $column=[Angle]::new([uint32]($i -shl [Trig]::AngleToFineShift))-[Angle]::Ang90
        $columnAngle[$x]=$column.Data
        $cos=[Fixed]::Abs([Trig]::Cos($column))
        $distanceScale[$x]=([Fixed]::One/$cos).Data
    }
    # Match Doom's viewangletox fencepost normalization after deriving
    # xtoviewangle; both tables describe the same fixed-point projection.
    for([int]$i=0;$i -lt $angleToX.Length;$i++){
        if($angleToX[$i] -eq -1){$angleToX[$i]=0}
        elseif($angleToX[$i] -eq 321){$angleToX[$i]=320}
    }
    [int[]]$rowSlope=[int[]]::new(168)
    for([int]$y=0;$y -lt 168;$y++){
        $dy=[Fixed]::Abs([Fixed]::FromInt($y-84)+([Fixed]::One/2))
        $rowSlope[$y]=([Fixed]::FromInt(160)/$dy).Data
    }
    $script:FastPlaneTables=@{ColumnAngles=$columnAngle;AngleToX=$angleToX;DistanceScales=$distanceScale;RowSlopes=$rowSlope;FineSine=[int[]][Trig]::fineSine;FineTangent=[int[]][Trig]::fineTangent;TanToAngle=[uint32[]][Trig]::tanToAngleTable}
    return $script:FastPlaneTables
}

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
    return @{Width=$Patch.Width;Height=$Patch.Height;Left=$Patch.LeftOffset;Top=$Patch.TopOffset;Data=$data;Columns=$Patch.Columns}
}

function Get-RenderPatch {
    param($Context,$Patch)
    if(-not $Context.Patches.ContainsKey($Patch.Name)){$Context.Patches[$Patch.Name]=ConvertTo-RenderPatch $Patch}
    return $Context.Patches[$Patch.Name]
}

function New-FastRenderContext {
    param($Content,$World,$Resources,[switch]$CacheResources)
    # Resource reuse is opt-in: callers must treat this WAD-derived graph as
    # immutable. Map geometry, sector state and all raster scratch stay private.
    if($null -ne $Resources -and -not [object]::ReferenceEquals($Resources.Content,$Content)){
        throw 'Render resources must belong to the same GameContent instance.'
    }
    $map=$World.Map
    [byte[][]]$planeFlatData=[byte[][]]::new($Content.Flats.Flats.Length)
    for([int]$i=0;$i -lt $planeFlatData.Length;$i++){
        if($null -ne $Content.Flats.Flats[$i]){$planeFlatData[$i]=[byte[]]$Content.Flats.Flats[$i].Data}
    }
    $ctx=@{Content=$Content;World=$World;Lighting=(New-FastLightingTables);Pixels=[byte[]]::new(64000);Depth=[double[]]::new(64000);
        TopClip=[int[]]::new(320);BottomClip=[int[]]::new(320);Planes=[int[]]::new(53760);Patches=@{};Textures=@{};Hud=@{};
        Stack=[int[]]::new($map.Nodes.Length*2+4);SkyColumns=[int[]]::new(320);RaySin=[int[]]::new(320);RayCos=[int[]]::new(320);
        WallPointScratch=[long[]]::new(2);WallParameterScratch=[long[]]::new(3);
        SpriteClipWalls=[object[]]::new(320);SpriteClipCounts=[int[]]::new(320);ActorClipTop=[int[]]::new(320);ActorClipBottom=[int[]]::new(320);
        MaskedColumns=[Collections.Generic.List[hashtable]]::new();SegmentGeometry=[double[]]::new($map.Segs.Length*6);
        SegmentWallUData=[int[]]::new($map.Segs.Length*4);
        SegmentAngles=[uint32[]]::new($map.Segs.Length);
        SegmentMetadata=[int[]]::new($map.Segs.Length*4);NodeGeometry=[double[]]::new($map.Nodes.Length*12);
        NodeChildren=[int[]]::new($map.Nodes.Length*2);Subsectors=$map.Subsectors;
        Flats=$Content.Flats.Flats;PlaneFlatData=$planeFlatData;
        SectorFloorHeightData=[int[]]::new($map.Sectors.Length);SectorCeilingHeightData=[int[]]::new($map.Sectors.Length);
        SectorFloorFlatIndex=[int[]]::new($map.Sectors.Length);SectorCeilingFlatIndex=[int[]]::new($map.Sectors.Length);
        SectorLightLevels=[int[]]::new($map.Sectors.Length);SectorRenderDataReady=$false;
        Colors=$Content.ColorMap.Data;SkyFlat=$Content.Flats.SkyFlatNumber;Sectors=$map.Sectors;Sides=$map.Sides;SpriteAtlas=[object[]]::new($Content.Sprites.spriteDefs.Length)}
    for([int]$x=0;$x -lt 320;$x++){$ctx.SpriteClipWalls[$x]=[Collections.Generic.List[object[]]]::new()}
    $sectorIndex=[Collections.Generic.Dictionary[object,int]]::new()
    for($i=0;$i -lt $map.Sectors.Length;$i++){$sectorIndex[$map.Sectors[$i]]=$i}
    $sideIndex=[Collections.Generic.Dictionary[object,int]]::new()
    for($i=0;$i -lt $map.Sides.Length;$i++){$sideIndex[$map.Sides[$i]]=$i}
    for($i=0;$i -lt $map.Segs.Length;$i++) {
        $seg=$map.Segs[$i];$ax=$seg.Vertex1.X.Data/65536.0;$ay=$seg.Vertex1.Y.Data/65536.0
        $ctx.SegmentAngles[$i]=$seg.Angle.Data
        $bx=$seg.Vertex2.X.Data/65536.0;$by=$seg.Vertex2.Y.Data/65536.0
        [int]$geometryOffset=$i*6;[int]$metadataOffset=$i*4
        $ctx.SegmentGeometry[$geometryOffset]=$ax;$ctx.SegmentGeometry[$geometryOffset+1]=$ay
        $ctx.SegmentGeometry[$geometryOffset+2]=$bx;$ctx.SegmentGeometry[$geometryOffset+3]=$by
        $ctx.SegmentGeometry[$geometryOffset+4]=[Math]::Sqrt(($bx-$ax)*($bx-$ax)+($by-$ay)*($by-$ay))
        $ctx.SegmentGeometry[$geometryOffset+5]=$seg.Offset.Data/65536.0
        [int]$wallUOffset=$i*4
        $ctx.SegmentWallUData[$wallUOffset]=$seg.Vertex1.X.Data;$ctx.SegmentWallUData[$wallUOffset+1]=$seg.Vertex1.Y.Data
        $ctx.SegmentWallUData[$wallUOffset+2]=$seg.Offset.Data;$ctx.SegmentWallUData[$wallUOffset+3]=$seg.SideDef.TextureOffset.Data
        $ctx.SegmentMetadata[$metadataOffset]=$sideIndex[$seg.SideDef]
        $ctx.SegmentMetadata[$metadataOffset+1]=$sectorIndex[$seg.FrontSector]
        $ctx.SegmentMetadata[$metadataOffset+2]=if($null -eq $seg.BackSector){-1}else{$sectorIndex[$seg.BackSector]}
        $ctx.SegmentMetadata[$metadataOffset+3]=[int]$seg.LineDef.Flags
    }
    for($i=0;$i -lt $map.Nodes.Length;$i++) {
        $node=$map.Nodes[$i];[int]$geometryOffset=$i*12;[int]$childrenOffset=$i*2
        $ctx.NodeGeometry[$geometryOffset]=$node.X.Data/65536.0;$ctx.NodeGeometry[$geometryOffset+1]=$node.Y.Data/65536.0
        $ctx.NodeGeometry[$geometryOffset+2]=$node.DX.Data/65536.0;$ctx.NodeGeometry[$geometryOffset+3]=$node.DY.Data/65536.0
        $ctx.NodeChildren[$childrenOffset]=$node.Children[0];$ctx.NodeChildren[$childrenOffset+1]=$node.Children[1]
        for($child=0;$child -lt 2;$child++) {
            $b=$node.BoundingBox[$child]
            [int]$boxOffset=$geometryOffset+4+($child*4)
            $ctx.NodeGeometry[$boxOffset]=($b[2].Data+$b[3].Data)/131072.0
            $ctx.NodeGeometry[$boxOffset+1]=($b[0].Data+$b[1].Data)/131072.0
            $ctx.NodeGeometry[$boxOffset+2]=($b[3].Data-$b[2].Data)/131072.0
            $ctx.NodeGeometry[$boxOffset+3]=($b[0].Data-$b[1].Data)/131072.0
        }
    }
    if($null -ne $Resources){
        foreach($field in 'Patches','Textures','Hud','SpriteAtlas','Lighting','PlaneFlatData'){$ctx[$field]=$Resources[$field]}
        $ctx.Sky=if($Resources.ContainsKey('SkyTextureReference') -and [object]::ReferenceEquals($Resources.SkyTextureReference,$map.SkyTexture)){
            $Resources.Sky
        }else{ConvertTo-RenderPatch $map.SkyTexture.Composite}
    }else{
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
    }
    $ctx.SkyTextureReference=$map.SkyTexture
    if($CacheResources -or $null -ne $Resources){
        $ctx.RenderAssetCache=if($null -ne $Resources -and $Resources.ContainsKey('RenderAssetCache')){$Resources.RenderAssetCache}else{@{}}
    }
    $planeTables=Get-FastPlaneTables
    $ctx.PlaneColumnAngles=$planeTables.ColumnAngles;$ctx.ViewAngleToX=$planeTables.AngleToX;$ctx.PlaneDistanceScales=$planeTables.DistanceScales;$ctx.PlaneRowSlopes=$planeTables.RowSlopes;$ctx.PlaneFineSine=$planeTables.FineSine;$ctx.TanToAngleTable=$planeTables.TanToAngle;$ctx.WallFineTangent=$planeTables.FineTangent
    return $ctx
}

function Get-FastFixedDivData {
    param([int]$Numerator,[int]$Denominator)
    # Preserve Fixed's saturation, truncation and int32-minimum error behavior.
    [int]$absoluteNumerator=[Math]::Abs([long]$Numerator)
    [int]$absoluteDenominator=[Math]::Abs([long]$Denominator)
    if(($absoluteNumerator -shr 14) -ge $absoluteDenominator){
        if(($Numerator -bxor $Denominator) -lt 0){return [int]::MinValue}
        return [int]::MaxValue
    }
    return [int][Math]::Truncate([double]$Numerator/$Denominator*65536.0)
}

function Get-FastPointDistData {
    param([int]$FromX,[int]$FromY,[int]$ToX,[int]$ToY,[uint32[]]$TanToAngle,[int[]]$FineSine)
    [long]$dx=([long]$ToX-$FromX) -band 0xffffffffL
    [long]$dy=([long]$ToY-$FromY) -band 0xffffffffL
    if($dx -ge 0x80000000L){$dx-=0x100000000L};if($dy -ge 0x80000000L){$dy-=0x100000000L}
    # Fixed.Abs wraps negation at int.MinValue rather than widening its result.
    if($dx -lt 0 -and $dx -ne -2147483648L){$dx=-$dx}
    if($dy -lt 0 -and $dy -ne -2147483648L){$dy=-$dy}
    if($dy -gt $dx){$swap=$dx;$dx=$dy;$dy=$swap}
    [int]$fraction=0;if($dx -ne 0){$fraction=Get-FastFixedDivData $dy $dx}
    [uint32]$fractionUnsigned=$fraction
    [uint32]$angleData=([long]$TanToAngle[$fractionUnsigned -shr 5]+0x40000000L) -band 0xffffffffL
    return Get-FastFixedDivData $dx $FineSine[$angleData -shr 19]
}

function Get-FastWallUParameters {
    param([int]$ViewX,[int]$ViewY,[int]$VertexX,[int]$VertexY,[uint32]$SegmentAngle,
        [uint32]$ViewAngle,[int]$SegmentOffset,[int]$SideOffset,[uint32[]]$TanToAngle,[int[]]$FineSine,[long[]]$PointResult,[long[]]$Result)
    [bool]$ownsPointResult=$null -eq $PointResult;[bool]$ownsResult=$null -eq $Result
    if($ownsPointResult){$PointResult=[long[]]::new(2)}
    if($ownsResult){$Result=[long[]]::new(3)}
    # Numeric equivalent of the pinned GPL ThreeDRenderer wall-U formula.
    # Worker processes consume transported tables and need no engine classes.
    [uint32]$normal=([long]$SegmentAngle+0x40000000L) -band 0xffffffffL
    Get-FastPointAngleDistanceData $ViewX $ViewY $VertexX $VertexY $TanToAngle $FineSine -Result $PointResult
    [uint32]$angle1=$PointResult[0];[int]$hyp=$PointResult[1]
    [uint32]$difference=([long]$normal-$angle1) -band 0xffffffffL
    [long]$absoluteAngle=$difference
    if($absoluteAngle -gt 0x80000000L){$absoluteAngle=0x100000000L-$absoluteAngle}
    if($absoluteAngle -gt 0x40000000L){$absoluteAngle=0x40000000L}
    [long]$perp=(([long]$hyp*$FineSine[(0x40000000L-$absoluteAngle) -shr 19]) -shr 16) -band 0xffffffffL
    if($perp -ge 0x80000000L){$perp-=0x100000000L}
    [long]$offset=([long]$hyp*$FineSine[$absoluteAngle -shr 19]) -shr 16
    if($difference -lt 0x80000000L){$offset=-$offset}
    $offset=($offset+$SegmentOffset+[long]$SideOffset) -band 0xffffffffL
    if($offset -ge 0x80000000L){$offset-=0x100000000L}
    [uint32]$center=(0x40000000L+[long]$ViewAngle-$normal) -band 0xffffffffL
    $Result[0]=$perp;$Result[1]=$offset;$Result[2]=$center
    if($ownsResult){return ,$Result}
}

function Get-FastWallScaleData {
    param([int]$PerpendicularDistance,[uint32]$CenterAngle,[uint32]$ColumnAngle,[int[]]$FineSine)
    [uint32]$numeratorAngle=([long]$CenterAngle+$ColumnAngle) -band 0xffffffffL
    [uint32]$denominatorAngle=(0x40000000L+[long]$ColumnAngle) -band 0xffffffffL
    [int]$numerator=160*$FineSine[$numeratorAngle -shr 19]
    [long]$denominatorWrapped=((([long]$PerpendicularDistance*$FineSine[$denominatorAngle -shr 19]) -shr 16) -band 0xffffffffL)
    if($denominatorWrapped -ge 0x80000000L){$denominatorWrapped-=0x100000000L}
    [int]$denominator=$denominatorWrapped
    if($denominator -gt ($numerator -shr 16)){$scale=Get-FastFixedDivData $numerator $denominator}
    else{$scale=4194304}
    return [Math]::Clamp([int]$scale,256,4194304)
}

function Get-FastWallScreenRange {
    param([int]$ViewXData,[int]$ViewYData,[int]$Vertex1XData,[int]$Vertex1YData,
        [int]$Vertex2XData,[int]$Vertex2YData,[uint32]$ViewAngleData,[uint32]$ClipAngleData,
        [uint32[]]$TanToAngleTable,[int[]]$AngleToX,[int[]]$Range)
    if($AngleToX.Length -ne 4096){throw 'Wall projection requires the 4096-entry viewangletox table.'}
    if($Range.Length -ne 2){throw 'Wall projection requires a two-column result buffer.'}
    [uint32]$angle1=Get-FastPointAngleData $ViewXData $ViewYData $Vertex1XData $Vertex1YData $TanToAngleTable
    [uint32]$angle2=Get-FastPointAngleData $ViewXData $ViewYData $Vertex2XData $Vertex2YData $TanToAngleTable
    [uint32]$span=([long]$angle1-[long]$angle2) -band 0xFFFFFFFFL
    if($span -ge 0x80000000L){return $false}

    [uint32]$angle1=([long]$angle1-[long]$ViewAngleData) -band 0xFFFFFFFFL
    [uint32]$angle2=([long]$angle2-[long]$ViewAngleData) -band 0xFFFFFFFFL
    [uint32]$doubleClip=([long]$ClipAngleData*2) -band 0xFFFFFFFFL
    [uint32]$tspan=([long]$angle1+[long]$ClipAngleData) -band 0xFFFFFFFFL
    if($tspan -gt $doubleClip){
        $tspan=([long]$tspan-[long]$doubleClip) -band 0xFFFFFFFFL
        if($tspan -ge $span){return $false}
        $angle1=$ClipAngleData
    }
    [uint32]$tspan=([long]$ClipAngleData-[long]$angle2) -band 0xFFFFFFFFL
    if($tspan -gt $doubleClip){
        $tspan=([long]$tspan-[long]$doubleClip) -band 0xFFFFFFFFL
        if($tspan -ge $span){return $false}
        $angle2=([long]0-[long]$ClipAngleData) -band 0xFFFFFFFFL
    }

    [int]$fineIndex1=(([long]$angle1+0x40000000L) -band 0xFFFFFFFFL) -shr 19
    [int]$fineIndex2=(([long]$angle2+0x40000000L) -band 0xFFFFFFFFL) -shr 19
    if($fineIndex1 -lt 0 -or $fineIndex1 -ge $AngleToX.Length -or $fineIndex2 -lt 0 -or $fineIndex2 -ge $AngleToX.Length){
        throw 'Clipped wall angle fell outside the viewangletox table.'
    }
    [int]$x1=$AngleToX[$fineIndex1];[int]$x2=$AngleToX[$fineIndex2]
    if($x1 -lt 0 -or $x1 -gt 320 -or $x2 -lt 0 -or $x2 -gt 320 -or $x1 -ge $x2){return $false}
    $Range[0]=$x1;$Range[1]=$x2
    return $true
}

function Update-FastRenderSectorData {
    param($Context,[object[]]$Sectors)
    if(-not $Context.ContainsKey('PlaneFlatData') -or $null -eq $Context.PlaneFlatData) {
        [byte[][]]$Context.PlaneFlatData=[byte[][]]::new($Context.Flats.Length)
        for([int]$i=0;$i -lt $Context.Flats.Length;$i++) {
            if($null -ne $Context.Flats[$i]){$Context.PlaneFlatData[$i]=[byte[]]$Context.Flats[$i].Data}
        }
    }
    if(-not $Context.ContainsKey('SectorFloorHeightData') -or $null -eq $Context.SectorFloorHeightData -or $Context.SectorFloorHeightData.Length -ne $Sectors.Length) {
        $Context.SectorFloorHeightData=[int[]]::new($Sectors.Length)
        $Context.SectorCeilingHeightData=[int[]]::new($Sectors.Length)
        $Context.SectorFloorFlatIndex=[int[]]::new($Sectors.Length)
        $Context.SectorCeilingFlatIndex=[int[]]::new($Sectors.Length)
        $Context.SectorLightLevels=[int[]]::new($Sectors.Length)
    }
    for([int]$i=0;$i -lt $Sectors.Length;$i++) {
        $sector=$Sectors[$i]
        $Context.SectorFloorHeightData[$i]=[int][Math]::Truncate(65536.0*$sector.FloorHeight)
        $Context.SectorCeilingHeightData[$i]=[int][Math]::Truncate(65536.0*$sector.CeilingHeight)
        $Context.SectorFloorFlatIndex[$i]=[int]$sector.FloorFlat
        $Context.SectorCeilingFlatIndex[$i]=[int]$sector.CeilingFlat
        $Context.SectorLightLevels[$i]=[int]$sector.LightLevel
    }
    $Context.SectorRenderDataReady=$true
}

function Draw-FastPatch {
    param($Context,$Patch,[double]$Left,[double]$Top,[double]$Scale=1,[double]$Distance=0,
        [bool]$Flip=$false,[int]$Light=0,[int]$FirstColumn=0,[int]$EndColumn=320,[int]$MaxY=200,
    [int]$TextureAltData=0,[int]$CenterY=84,[switch]$FixedVerticalSampling,[int[]]$ClipTopByColumn,[int[]]$ClipBottomByColumn)
    [int]$pw=$Patch.Width;[int]$ph=$Patch.Height;[int[]]$texels=$Patch.Data
    [byte[]]$pixels=$Context.Pixels;[double[]]$depth=$Context.Depth;[byte[]]$colors=$Context.Colors[$Light]
    if($pw -le 0 -or $ph -le 0 -or $Scale -le 0){return}
    # Doom projects the left edge with a signed fixed-point shift, which floors
    # it to the first screen column. Source stepping begins at that integer
    # column rather than at the subpixel world-space edge.
    [int]$screenLeft=[Math]::Floor($Left);[int]$screenEnd=[Math]::Floor($Left+$pw*$Scale)
    [int]$x0=[Math]::Max($FirstColumn,$screenLeft);[int]$x1=[Math]::Min($EndColumn,$screenEnd)
    [int]$y0=[Math]::Max(0,[Math]::Ceiling($Top));[int]$y1=[Math]::Min($MaxY,[Math]::Ceiling($Top+$ph*$Scale))
    if($x0 -ge $x1 -or (-not $FixedVerticalSampling -and $y0 -ge $y1)){return}
    [int]$scaleData=[Math]::Truncate($Scale*65536.0)
    if($scaleData -le 0){return}
    [long]$invScaleData=[Math]::Truncate(4294967296.0/$scaleData)
    [long]$fracStep=if($Flip){-$invScaleData}else{$invScaleData}
    [long]$fracData=if($Flip){([long]$pw -shl 16)-1L}else{0L}
    $fracData+=([long]$x0-$screenLeft)*$fracStep
    if($FixedVerticalSampling){
        # Masked sprites are a sequence of posts, not a solid rectangle. Keep
        # each post's fixed-point start/end so a texel ending exactly on a row
        # boundary does not leak into the following transparent row.
        if($null -eq $Patch.Columns){throw 'Fixed sprite sampling requires the original post columns.'}
        [int]$topYData=[int](([long]$CenterY*65536)-(([long]$TextureAltData*$scaleData)-shr 16))
        for([int]$x=$x0;$x -lt $x1;$x++) {
            [int]$u=[Math]::Clamp([int]($fracData -shr 16),0,$pw-1)
            foreach($post in $Patch.Columns[$u]){
                if($post.TopDelta -eq 255){continue}
                [long]$postTopData=$topYData+([long]$scaleData*$post.TopDelta)
                [long]$postBottomData=$postTopData+([long]$scaleData*$post.Length)
                [int]$postY0=[int](($postTopData+65535)-shr 16)
                [int]$postY1=[int](($postBottomData-1)-shr 16)
                $postY0=[Math]::Max(0,$postY0);$postY1=[Math]::Min($MaxY-1,$postY1)
                if($null -ne $ClipTopByColumn){$postY0=[Math]::Max($postY0,$ClipTopByColumn[$x])}
                if($null -ne $ClipBottomByColumn){$postY1=[Math]::Min($postY1,$ClipBottomByColumn[$x])}
                if($postY0 -le $postY1){
                    [long]$postAltData=[long]$TextureAltData-([long]$post.TopDelta -shl 16)
                    [long]$verticalFracData=$postAltData+([long]($postY0-$CenterY)*$invScaleData)
                    for([int]$y=$postY0;$y -le $postY1;$y++){
                        [int]$p=$y*320+$x
                        if($Distance -lt $depth[$p]){
                            [int]$postRow=[int](($verticalFracData -shr 16) -band 127)
                            [int]$color=$post.Data[$post.Offset+$postRow]
                            if($color -ge 0){$pixels[$p]=$colors[$color];$depth[$p]=$Distance}
                        }
                        $verticalFracData+=$invScaleData
                    }
                }
            }
            $fracData+=$fracStep
        }
        return
    }
    if($Scale -eq 1 -and $Distance -eq 0) {
        for([int]$x=$x0;$x -lt $x1;$x++) {
            [int]$u=[Math]::Clamp([int]($fracData -shr 16),0,$pw-1)
            [int]$t=$u*$ph+[int][Math]::Floor($y0-$Top);[int]$p=$y0*320+$x
            for([int]$y=$y0;$y -lt $y1;$y++) {
                [int]$color=$texels[$t++];if($color -ge 0){$pixels[$p]=$colors[$color]};$p+=320
            }
            $fracData+=$fracStep
        }
        return
    }
    for([int]$x=$x0;$x -lt $x1;$x++) {
        [int]$u=[Math]::Clamp([int]($fracData -shr 16),0,$pw-1)
        [int]$columnY0=$y0;[int]$columnY1=$y1
        if($null -ne $ClipTopByColumn){$columnY0=[Math]::Max($columnY0,$ClipTopByColumn[$x])}
        if($null -ne $ClipBottomByColumn){$columnY1=[Math]::Min($columnY1,$ClipBottomByColumn[$x]+1)}
        for([int]$y=$columnY0;$y -lt $columnY1;$y++) {
            [int]$p=$y*320+$x
            if($Distance -gt 0 -and $Distance -ge $depth[$p]){continue}
            [double]$vf=($y-$Top)/$Scale;[int]$v=$vf;if($v -gt $vf){$v--};if($v -ge $ph){$v=$ph-1};[int]$color=$texels[$u*$ph+$v]
            if($color -ge 0){$pixels[$p]=$colors[$color];$depth[$p]=$Distance}
        }
        $fracData+=$fracStep
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
    param($Context,[int]$FirstColumn=0,[int]$EndColumn=320,[switch]$GeometryDetails)
    if(-not $Context.ContainsKey('SectorRenderDataReady') -or -not $Context.SectorRenderDataReady){throw 'Update the render-sector cache for the current snapshot before rendering.'}
    $phaseWatch=[Diagnostics.Stopwatch]::StartNew();$world=$Context.World;$player=$world.ConsolePlayer;$camera=$player.Mobj
    if($GeometryDetails){$geometryStartedQpc=[Diagnostics.Stopwatch]::GetTimestamp()}
    $cameraXValue=$camera.X;$cameraYValue=$camera.Y;$cameraViewZValue=$player.ViewZ
    if($cameraXValue -is [Fixed]){
        [double]$cx=$cameraXValue.ToDouble();[int]$viewXData=$cameraXValue.Data
    }else{
        [double]$cx=$cameraXValue;[int]$viewXData=[Math]::Truncate(65536.0*$cx)
    }
    if($cameraYValue -is [Fixed]){
        [double]$cy=$cameraYValue.ToDouble();[int]$viewYData=$cameraYValue.Data
    }else{
        [double]$cy=$cameraYValue;[int]$viewYData=[Math]::Truncate(65536.0*$cy)
    }
    if($cameraViewZValue -is [Fixed]){
        [double]$cz=$cameraViewZValue.ToDouble();[int]$viewZData=$cameraViewZValue.Data
    }else{
        [double]$cz=$cameraViewZValue;[int]$viewZData=[Math]::Truncate(65536.0*$cz)
    }
    $cameraAngleValue=$camera.Angle
    if($cameraAngleValue -is [Angle]){
        [double]$angle=$cameraAngleValue.ToRadian();[uint32]$viewAngleData=$cameraAngleValue.Data
    }else{
        [double]$angle=$cameraAngleValue
        [uint32]$viewAngleData=[uint32]([long][Math]::Round(4294967296.0*($angle/(2*[Math]::PI))) -band 0xFFFFFFFFL)
    }
    [uint32]$planeBaseAngleData=([long]$viewAngleData-0x40000000L) -band 0xFFFFFFFFL
    # Actor projection follows Doom's 16.16 transform. Keep the floating-point
    # camera values above for the PowerShell BSP/plane path, but use the same
    # angle lookup and fixed-point products as the adopted sprite projector.
    [int[]]$spriteFineSine=$Context.PlaneFineSine
    [int]$spriteFineIndex=$viewAngleData -shr 19
    [int]$spriteViewSinData=$spriteFineSine[$spriteFineIndex]
    [int]$spriteViewCosData=$spriteFineSine[$spriteFineIndex+2048]
    [int]$spriteFracBits=16;[int]$spriteMinZData=4 -shl 16;[int]$spriteScaleLightShift=12
    [int]$planeBaseFine=$planeBaseAngleData -shr 19
    [int[]]$fineSine=$Context.PlaneFineSine
    [int]$planeBaseX=[Math]::Truncate($fineSine[$planeBaseFine+2048]/160.0)
    [int]$planeBaseY=-[Math]::Truncate($fineSine[$planeBaseFine]/160.0)
    [int[]]$raySin=$Context.RaySin;[int[]]$rayCos=$Context.RayCos
    $sky=$Context.Sky;[int[]]$skyData=$sky.Data;[int]$skyW=$sky.Width;[int]$skyH=$sky.Height
    [int[]]$skyColumns=$Context.SkyColumns
    for([int]$x=$FirstColumn;$x -lt $EndColumn;$x++){
        [uint32]$rayData=([long]$viewAngleData+[long]$Context.PlaneColumnAngles[$x]) -band 0xFFFFFFFFL
        [int]$fineIndex=$rayData -shr 19
        $raySin[$x]=$fineSine[$fineIndex];$rayCos[$x]=$fineSine[$fineIndex+2048]
        [int]$skyAngle=$rayData -shr 22
        if(($skyW -band ($skyW-1)) -eq 0){$skyColumns[$x]=$skyAngle -band ($skyW-1)}
        else{$skyColumns[$x]=$skyAngle%$skyW}
    }
    [uint32[]]$wallSegmentAngles=[uint32[]]::new(0)
    if($Context.ContainsKey('SegmentAngles')){$wallSegmentAngles=$Context.SegmentAngles}
    [bool]$wallAnglesReady=$wallSegmentAngles.Length -eq ($Context.SegmentMetadata.Length/4)
    [int[]]$wallAngleToX=[int[]]::new(0)
    if($Context.ContainsKey('ViewAngleToX')){$wallAngleToX=[int[]]$Context.ViewAngleToX}
    [bool]$wallProjectionReady=$wallAnglesReady -and $wallAngleToX.Length -eq 4096
    [int[]]$wallFineTangent=$null
    if($wallAnglesReady){$wallFineTangent=$Context.WallFineTangent}
    [double]$co=[Math]::Cos($angle);[double]$si=[Math]::Sin($angle)
    [double]$ls=($FirstColumn-161)/160.0;[double]$rs=($EndColumn-159)/160.0
    [double]$lx=$si-$ls*$co;[double]$ly=-$co-$ls*$si;[double]$rx=$rs*$co-$si;[double]$ry=$rs*$si+$co
    [double]$alx=[Math]::Abs($lx);[double]$aly=[Math]::Abs($ly);[double]$arx=[Math]::Abs($rx);[double]$ary=[Math]::Abs($ry)
    [double]$aco=[Math]::Abs($co);[double]$asi=[Math]::Abs($si)
    [byte[]]$pixels=$Context.Pixels;[double[]]$depthBuffer=$Context.Depth
    [int[]]$planes=$Context.Planes
    if(-not $Context.ContainsKey('SpriteClipWalls')){
        [object[]]$spriteClipWalls=[object[]]::new(320)
        for([int]$x=0;$x -lt 320;$x++){$spriteClipWalls[$x]=[Collections.Generic.List[object[]]]::new()}
        $Context.SpriteClipWalls=$spriteClipWalls
        $Context.SpriteClipCounts=[int[]]::new(320)
        $Context.ActorClipTop=[int[]]::new(320)
        $Context.ActorClipBottom=[int[]]::new(320)
    }
    [object[]]$spriteClipWalls=$Context.SpriteClipWalls
    [int[]]$spriteClipCounts=$Context.SpriteClipCounts
    [int[]]$wallColumnRange=[int[]]::new(2)
    for([int]$x=$FirstColumn;$x -lt $EndColumn;$x++){$spriteClipCounts[$x]=0}
    [int[]]$planeSpanBoundaries=[int[]]::new(0)
    if($Context.ContainsKey('PlaneSpanBoundaries')){$planeSpanBoundaries=[int[]]$Context.PlaneSpanBoundaries}
    [int[]]$topClip=$Context.TopClip;[int[]]$bottomClip=$Context.BottomClip
    [Collections.Generic.List[hashtable]]$maskedColumns=$Context.MaskedColumns;[int]$maskedColumnCount=0
    [Array]::Clear($pixels);[Array]::Clear($planes);[Array]::Fill($depthBuffer,[double]::PositiveInfinity)
    [Array]::Clear($topClip);[Array]::Fill($bottomClip,167)
    [int]$open=$EndColumn-$FirstColumn
    [double[]]$nodeGeometry=$Context.NodeGeometry;[int[]]$nodeChildren=$Context.NodeChildren
    $stack=$Context.Stack;[int]$sp=1;$stack[0]=($nodeGeometry.Length/12)-1
    # Reuse segment-local scratch across this non-recursive BSP walk.
    [int[]]$activeWallBandsScratch=[int[]]::new(3)
    [double[]]$wallBandOriginsScratch=[double[]]::new(3)
    if($GeometryDetails){$wallsStartedQpc=[Diagnostics.Stopwatch]::GetTimestamp()}
    while($sp -gt 0 -and $open -gt 0) {
        [int]$nodeIndex=$stack[--$sp]
        if($nodeIndex -ge 0 -and $nodeIndex -lt 32768) {
            [int]$nodeGeometryOffset=$nodeIndex*12;[int]$nodeChildrenOffset=$nodeIndex*2
            # Doom child 0 is on the right of the partition vector.
            [int]$near=0;if(($cx-$nodeGeometry[$nodeGeometryOffset])*$nodeGeometry[$nodeGeometryOffset+3]-($cy-$nodeGeometry[$nodeGeometryOffset+1])*$nodeGeometry[$nodeGeometryOffset+2] -lt 0){$near=1}
            for([int]$order=1;$order -ge 0;$order--) {
                [int]$child=$near -bxor $order;[int]$boxOffset=$nodeGeometryOffset+4+($child*4)
                [double]$ox=$nodeGeometry[$boxOffset]-$cx;[double]$oy=$nodeGeometry[$boxOffset+1]-$cy
                [double]$hw=$nodeGeometry[$boxOffset+2];[double]$hh=$nodeGeometry[$boxOffset+3]
                if($ox*$co+$oy*$si+$hw*$aco+$hh*$asi -lt 1){continue}
                if($ox*$lx+$oy*$ly+$hw*$alx+$hh*$aly -lt 0){continue}
                if($ox*$rx+$oy*$ry+$hw*$arx+$hh*$ary -lt 0){continue}
                $stack[$sp++]=$nodeChildren[$nodeChildrenOffset+$child]
            }
            continue
        }
        $ss=$Context.Subsectors[$nodeIndex -band 32767]
        for([int]$segIndex=$ss.FirstSeg;$segIndex -lt ($ss.FirstSeg+$ss.SegCount);$segIndex++) {
            [int]$geometryOffset=$segIndex*6;[int]$metadataOffset=$segIndex*4;[int]$wallUOffset=$segIndex*4
            [double]$segAX=$Context.SegmentGeometry[$geometryOffset];[double]$segAY=$Context.SegmentGeometry[$geometryOffset+1]
            [double]$segBX=$Context.SegmentGeometry[$geometryOffset+2];[double]$segBY=$Context.SegmentGeometry[$geometryOffset+3]
            [int]$segSide=$Context.SegmentMetadata[$metadataOffset];[int]$segFront=$Context.SegmentMetadata[$metadataOffset+1]
            [int]$segBack=$Context.SegmentMetadata[$metadataOffset+2];[int]$segFlags=$Context.SegmentMetadata[$metadataOffset+3]
            [double]$ax=$segAX-$cx;[double]$ay=$segAY-$cy;[double]$bx=$segBX-$cx;[double]$by=$segBY-$cy
            [int]$screenScaleX0=0;[int]$screenScaleX1=-1
            if($wallProjectionReady){
                # SegmentGeometry stores exact 16.16 WAD coordinates as doubles;
                # multiplying by 65536 recovers the original integer endpoints.
                [int]$segAXData=[Math]::Truncate($segAX*65536.0);[int]$segAYData=[Math]::Truncate($segAY*65536.0)
                [int]$segBXData=[Math]::Truncate($segBX*65536.0);[int]$segBYData=[Math]::Truncate($segBY*65536.0)
                $hasWallColumnRange=Get-FastWallScreenRange $viewXData $viewYData $segAXData $segAYData $segBXData $segBYData $viewAngleData $Context.PlaneColumnAngles[0] $Context.TanToAngleTable $wallAngleToX $wallColumnRange
                if(-not $hasWallColumnRange){continue}
                $screenScaleX0=$wallColumnRange[0];$screenScaleX1=$wallColumnRange[1]-1
                if($screenScaleX1 -lt $screenScaleX0 -or $screenScaleX0 -ge $EndColumn -or ($screenScaleX1+1) -le $FirstColumn){continue}
            }elseif($ax*$by-$ay*$bx -ge 0){continue}
            [double]$z1=$ax*$co+$ay*$si;[double]$z2=$bx*$co+$by*$si
            if($z1 -lt 1 -and $z2 -lt 1){continue}
            [double]$r1=$ax*$si-$ay*$co;[double]$r2=$bx*$si-$by*$co
            [double]$u1=$Context.SegmentGeometry[$geometryOffset+5];[double]$u2=$u1+$Context.SegmentGeometry[$geometryOffset+4]
            if($z1 -lt 1){$f=(1-$z1)/($z2-$z1);$r1+=($r2-$r1)*$f;$u1+=($u2-$u1)*$f;$z1=1}
            if($z2 -lt 1){$f=(1-$z2)/($z1-$z2);$r2+=($r1-$r2)*$f;$u2+=($u1-$u2)*$f;$z2=1}
            [double]$sx1=160+160*$r1/$z1;[double]$sx2=160+160*$r2/$z2
            if($wallProjectionReady){
                [int]$x0=[Math]::Max($FirstColumn,$screenScaleX0);[int]$x1=[Math]::Min($EndColumn,$screenScaleX1+1)
            }else{
                if($sx2 -le $sx1 -or $sx1 -ge $EndColumn -or $sx2 -le $FirstColumn){continue}
                $screenScaleX0=[Math]::Clamp([int][Math]::Ceiling($sx1-0.5),0,319)
                $screenScaleX1=[Math]::Clamp([int][Math]::Ceiling($sx2-0.5)-1,0,319)
                [int]$x0=[Math]::Max($FirstColumn,[Math]::Ceiling($sx1-0.5));[int]$x1=[Math]::Min($EndColumn,[Math]::Ceiling($sx2-0.5))
            }
            if($x1 -le $x0){continue}
            $front=$Context.Sectors[$segFront];$back=if($segBack -ge 0){$Context.Sectors[$segBack]}else{$null};$side=$Context.Sides[$segSide]
            [double]$fh=$front.FloorHeight;[double]$ch=$front.CeilingHeight
            [bool]$solid=$null -eq $back;[double]$bf=$fh;[double]$bc=$ch
            if(-not $solid){$bf=$back.FloorHeight;$bc=$back.CeilingHeight}
            [bool]$lowerSilhouette=$solid;[double]$lowerSilHeight=[double]::PositiveInfinity
            [bool]$upperSilhouette=$solid;[double]$upperSilHeight=[double]::NegativeInfinity
            if(-not $solid){
                if($fh -gt $bf){$lowerSilhouette=$true;$lowerSilHeight=$fh}
                elseif($bf -gt $cz){$lowerSilhouette=$true;$lowerSilHeight=[double]::PositiveInfinity}
                if($front.CeilingHeight -lt $bc){$upperSilhouette=$true;$upperSilHeight=$front.CeilingHeight}
                elseif($bc -lt $cz){$upperSilhouette=$true;$upperSilHeight=[double]::NegativeInfinity}
                if($bc -le $fh){$lowerSilhouette=$true;$lowerSilHeight=[double]::PositiveInfinity}
                if($bf -ge $front.CeilingHeight){$upperSilhouette=$true;$upperSilHeight=[double]::NegativeInfinity}
            }
            [bool]$isSky=$front.CeilingFlat -eq $Context.SkyFlat
            [int]$upperPlaneId=1+($segFront*2);[int]$lowerPlaneId=$upperPlaneId+1
            [bool]$joinedSky=$isSky -and -not $solid -and $back.CeilingFlat -eq $Context.SkyFlat
            if($joinedSky){$ch=$bc}
            [int]$contrast=if($segAY -eq $segBY){-1}elseif($segAX -eq $segBX){1}else{0}
            [int]$baseLight=[Math]::Clamp(($front.LightLevel -shr 4)+$player.ExtraLight+$contrast,0,15)
            [int[]]$wallLightTable=$Context.Lighting.Scale[$baseLight]
            [double]$iz1=1/$z1;[double]$iz2=1/$z2;[double]$uz1=$u1/$z1;[double]$uz2=$u2/$z2
            [bool]$wallUReady=$false;[int]$wallPerpData=0;[int]$wallOffsetData=0;[uint32]$wallCenterAngleData=0
            [bool]$wallScaleReady=$false;[int]$wallScaleStart=0;[int]$wallScaleStep=0
            [double[]]$wallBandOrigins=$wallBandOriginsScratch;[int]$wallOriginBits=0
            [bool]$constantWallScale=$iz1 -eq $iz2;[double]$segmentTexelStep=0
            # Select eligible textured bands once per segment instead of
            # repeating all three eligibility branches for every column.
            [int[]]$activeWallBands=$activeWallBandsScratch;[int]$activeWallBandCount=0
            if($solid){if($side.MiddleTexture -gt 0){$activeWallBands[$activeWallBandCount++]=0}}
            else{
                if($bc -lt $ch -and -not $joinedSky -and $side.TopTexture -gt 0){$activeWallBands[$activeWallBandCount++]=0}
                if($bf -gt $fh -and $side.BottomTexture -gt 0){$activeWallBands[$activeWallBandCount++]=1}
                if($side.MiddleTexture -gt 0){$activeWallBands[$activeWallBandCount++]=2}
            }
            for([int]$x=$x0;$x -lt $x1;$x++) {
                [int]$clipT=$topClip[$x];[int]$clipB=$bottomClip[$x];if($clipT -gt $clipB){continue}
                if($wallAnglesReady -and -not $wallScaleReady){
                    if(-not $wallUReady){
                        [int]$wallAXData=$Context.SegmentWallUData[$wallUOffset];[int]$wallAYData=$Context.SegmentWallUData[$wallUOffset+1]
                        [int]$wallSegOffset=$Context.SegmentWallUData[$wallUOffset+2];[int]$wallSideOffset=$Context.SegmentWallUData[$wallUOffset+3]
                        Get-FastWallUParameters $viewXData $viewYData $wallAXData $wallAYData $wallSegmentAngles[$segIndex] $viewAngleData $wallSegOffset $wallSideOffset $Context.TanToAngleTable $fineSine -PointResult $Context.WallPointScratch -Result $Context.WallParameterScratch
                        [long[]]$wallParameters=$Context.WallParameterScratch
                        $wallPerpData=$wallParameters[0];$wallOffsetData=$wallParameters[1];$wallCenterAngleData=$wallParameters[2];$wallUReady=$true
                    }
                    [int]$wallScaleStart=Get-FastWallScaleData $wallPerpData $wallCenterAngleData $Context.PlaneColumnAngles[$screenScaleX0] $fineSine
                    if($screenScaleX1 -gt $screenScaleX0){
                        [int]$wallScaleEnd=Get-FastWallScaleData $wallPerpData $wallCenterAngleData $Context.PlaneColumnAngles[$screenScaleX1] $fineSine
                        $wallScaleStep=[int][Math]::Truncate(($wallScaleEnd-$wallScaleStart)/[double]($screenScaleX1-$screenScaleX0))
                    }
                    $wallScaleReady=$true
                }
                # Match Doom's xToAngle lookup: wall rays are defined at integer
                # screen columns, not at the half-pixel used for edge coverage.
                [double]$texU=0
                if($wallAnglesReady){[int]$wallScaleData=$wallScaleStart+($x-$screenScaleX0)*$wallScaleStep;$distance=10485760.0/$wallScaleData}
                else{$f=($x-$sx1)/($sx2-$sx1);$distance=1/($iz1+($iz2-$iz1)*$f);$texU=($uz1+($uz2-$uz1)*$f)*$distance+$side.TextureOffset}
                [double]$ray=($x-160)/160;[double]$rayX=$co+$si*$ray;[double]$rayY=$si-$co*$ray
                [int]$wallT=[Math]::Ceiling(84-160*($ch-$cz)/$distance-0.5)
                [int]$wallB=[Math]::Floor(84-160*($fh-$cz)/$distance-0.5)
                # Draw the floor/ceiling exposed before this boundary. Near-first clip intervals
                # keep each opaque world pixel owned by a single segment.
                [int]$upperPlaneEnd=[Math]::Min($clipB,$wallT-1)
                if($isSky){
                    for([int]$y=$clipT;$y -le $upperPlaneEnd;$y++){
                        [int]$p=$y*320+$x;$pixels[$p]=$skyData[$skyColumns[$x]*$skyH+(($y+16)-band 127)]
                    }
                }else{
                    for([int]$y=$clipT;$y -le $upperPlaneEnd;$y++){$planes[$y*320+$x]=$upperPlaneId}
                }
                [int]$lowerPlaneStart=[Math]::Max($clipT,$wallB+1)
                for([int]$y=$lowerPlaneStart;$y -le $clipB;$y++){$planes[$y*320+$x]=$lowerPlaneId}
                [int]$portalT=[Math]::Ceiling(84-160*($bc-$cz)/$distance-0.5)
                [int]$portalB=[Math]::Floor(84-160*($bf-$cz)/$distance-0.5)
                [int]$wallLightIndex=47
                if($distance -gt 0){
                    [double]$wallLightScale=2560.0/$distance
                    if($wallLightScale -ge 0 -and $wallLightScale -lt 47){$wallLightIndex=[int][Math]::Floor($wallLightScale)}
                }
                [int]$wallLight=$wallLightTable[$wallLightIndex]
                if($player.FixedColorMap -gt 0){$wallLight=$player.FixedColorMap}
                [byte[]]$wallColors=$Context.Colors[$wallLight]
                [bool]$wallStepReady=$false;[double]$wallTexelStep=0
                [bool]$columnUReady=$false;[int]$wallTextureColumn=0
                for([int]$bandIndex=0;$bandIndex -lt $activeWallBandCount;$bandIndex++) {
                    [int]$band=$activeWallBands[$bandIndex]
                    [int]$tex=0;[double]$textureTop=$ch
                    if($solid) {
                        if($band -gt 0){break};$tex=$side.MiddleTexture;$wy0=$wallT;$wy1=$wallB
                        if($tex -gt 0 -and ($segFlags -band 16)){$textureTop=$fh+$Context.Textures[$tex].Height}
                    } elseif($band -eq 0) {
                        if($bc -ge $ch -or $joinedSky){continue};$tex=$side.TopTexture;$wy0=$wallT;$wy1=$portalT-1
                        if($tex -gt 0 -and -not ($segFlags -band 8)){$textureTop=$bc+$Context.Textures[$tex].Height}
                    } elseif($band -eq 1) {
                        if($bf -le $fh){continue};$tex=$side.BottomTexture;$wy0=$portalB+1;$wy1=$wallB;$textureTop=$bf
                        if($segFlags -band 16){$textureTop=$ch}
                    } else {
                        $tex=$side.MiddleTexture;$wy0=[Math]::Max($wallT,$portalT);$wy1=[Math]::Min($wallB,$portalB)
                        $textureTop=[Math]::Min($ch,$bc)
                        if($tex -gt 0 -and ($segFlags -band 16)){$textureTop=[Math]::Max($fh,$bf)+$Context.Textures[$tex].Height}
                    }
                    if($tex -le 0){continue}
                    $texture=$Context.Textures[$tex];[int]$tw=$texture.Width;[int]$th=$texture.Height;[int[]]$td=$texture.Data
                    [int]$y0=[Math]::Max($clipT,$wy0);[int]$y1=[Math]::Min($clipB,$wy1)
                    if($y0 -gt $y1){continue}
                    [int]$tu=0
                    if($wallAnglesReady){
                        if(-not $wallUReady){
                            [int]$wallAXData=$Context.SegmentWallUData[$wallUOffset];[int]$wallAYData=$Context.SegmentWallUData[$wallUOffset+1]
                            [int]$wallSegOffset=$Context.SegmentWallUData[$wallUOffset+2];[int]$wallSideOffset=$Context.SegmentWallUData[$wallUOffset+3]
                            Get-FastWallUParameters $viewXData $viewYData $wallAXData $wallAYData $wallSegmentAngles[$segIndex] $viewAngleData $wallSegOffset $wallSideOffset $Context.TanToAngleTable $fineSine -PointResult $Context.WallPointScratch -Result $Context.WallParameterScratch
                            [long[]]$wallParameters=$Context.WallParameterScratch
                            $wallPerpData=$wallParameters[0];$wallOffsetData=$wallParameters[1];$wallCenterAngleData=$wallParameters[2];$wallUReady=$true
                        }
                        if(-not $columnUReady){
                            [uint32]$wallTanAngleData=([long]$wallCenterAngleData+$Context.PlaneColumnAngles[$x]) -band 0x7fffffffL
                            [int]$wallTanData=$wallFineTangent[$wallTanAngleData -shr 19]
                            [long]$wallUData=[long]$wallOffsetData-(([long]$wallTanData*$wallPerpData) -shr 16)
                            # Signed high16 bits of the wrapped 32-bit fixed result.
                            $wallTextureColumn=($wallUData -shr 16) -band 65535
                            if($wallTextureColumn -ge 32768){$wallTextureColumn-=65536}
                            $columnUReady=$true
                        }
                        $tu=($wallTextureColumn%$tw+$tw)%$tw
                    }else{$tu=([int][Math]::Floor($texU)%$tw+$tw)%$tw}
                    # Only prepare sampling for a visible textured band. Empty
                    # portals and clipped walls need neither anchors nor scale.
                    if(-not $wallStepReady){
                        if($constantWallScale -and $segmentTexelStep -gt 0){$wallTexelStep=$segmentTexelStep}
                        else{
                            [int]$wallScaleData=[Math]::Clamp([int][Math]::Truncate(10485760.0/$distance),256,4194304)
                            $wallTexelStep=[Math]::Truncate(4294967295.0/$wallScaleData)/65536.0
                            if($constantWallScale){$segmentTexelStep=$wallTexelStep}
                        }
                        $wallStepReady=$true
                    }
                    [int]$originBit=1 -shl $band
                    if(($wallOriginBits -band $originBit) -eq 0){
                        $wallBandOrigins[$band]=[Math]::Truncate(($textureTop-$cz+$side.RowOffset)*65536.0)/65536.0
                        $wallOriginBits=$wallOriginBits -bor $originBit
                    }
                    [double]$vOrigin=$wallBandOrigins[$band]
                    if(-not $solid -and $band -eq 2){
                        # Portal openings remain visible to later geometry. Defer
                        # their transparent textures so that geometry cannot erase them.
                        if($y0 -le $y1){
                            if($maskedColumnCount -lt $maskedColumns.Count){
                                $maskedColumn=$maskedColumns[$maskedColumnCount]
                                $maskedColumn.X=$x;$maskedColumn.Y0=$y0;$maskedColumn.Y1=$y1;$maskedColumn.Distance=$distance
                                $maskedColumn.TexelStep=$wallTexelStep;$maskedColumn.Origin=$vOrigin;$maskedColumn.U=$tu;$maskedColumn.Height=$th;$maskedColumn.Texels=$td;$maskedColumn.Colors=$wallColors
                            }else{
                                $maskedColumns.Add(@{X=$x;Y0=$y0;Y1=$y1;Distance=$distance;TexelStep=$wallTexelStep;Origin=$vOrigin;U=$tu;Height=$th;Texels=$td;Colors=$wallColors})
                            }
                            $maskedColumnCount++
                        }
                        continue
                    }
                    for([int]$y=$y0;$y -le $y1;$y++) {
                        # Binary fractions of 1/65536 are exact here: this evaluates
                        # the integer column fraction without accumulating roundoff.
                        [double]$vf=$vOrigin+($y-84)*$wallTexelStep;[int]$v=$vf;if($v -gt $vf){$v--}
                        $v=($v%$th+$th)%$th;[int]$color=$td[$tu*$th+$v]
                        if($color -ge 0){$p=$y*320+$x;$pixels[$p]=$wallColors[$color];$depthBuffer[$p]=$distance}
                    }
                }
                [int]$nextTop=168;[int]$nextBottom=-1
                if(-not $solid){
                    $nextTop=[Math]::Max($clipT,[Math]::Max($wallT,$portalT))
                    $nextBottom=[Math]::Min($clipB,[Math]::Min($wallB,$portalB))
                }
                # Missing wall textures still close the BSP silhouette. Preserve
                # those untextured wall bands for sprites without spending a second
                # raster pass over wall textures that already wrote their depth.
                if($solid){
                    if($side.MiddleTexture -le 0){
                        [int]$occTop=[Math]::Max($clipT,$wallT);[int]$occBottom=[Math]::Min($clipB,$wallB)
                        for([int]$y=$occTop;$y -le $occBottom;$y++){
                            [int]$p=$y*320+$x;if($distance -lt $depthBuffer[$p]){$depthBuffer[$p]=$distance}
                        }
                    }
                }else{
                    if($side.TopTexture -le 0){
                        [int]$upperTop=[Math]::Max($clipT,$wallT);[int]$upperBottom=[Math]::Min($clipB,$portalT-1)
                        for([int]$y=$upperTop;$y -le $upperBottom;$y++){
                            [int]$p=$y*320+$x;if($distance -lt $depthBuffer[$p]){$depthBuffer[$p]=$distance}
                        }
                    }
                    if($side.BottomTexture -le 0){
                        [int]$lowerTop=[Math]::Max($clipT,$portalB+1);[int]$lowerBottom=[Math]::Min($clipB,$wallB)
                        for([int]$y=$lowerTop;$y -le $lowerBottom;$y++){
                            [int]$p=$y*320+$x;if($distance -lt $depthBuffer[$p]){$depthBuffer[$p]=$distance}
                        }
                    }
                }
                $topClip[$x]=$nextTop;$bottomClip[$x]=$nextBottom
                if($lowerSilhouette -or $upperSilhouette){
                    [int]$recordIndex=$spriteClipCounts[$x];$wallClips=$spriteClipWalls[$x]
                    if($recordIndex -lt $wallClips.Count){$wallClip=$wallClips[$recordIndex]}
                    else{$wallClip=[object[]]::new(6);$wallClips.Add($wallClip)}
                    [int]$silhouetteFlags=0
                    if($lowerSilhouette){$silhouetteFlags=$silhouetteFlags -bor 1}
                    if($upperSilhouette){$silhouetteFlags=$silhouetteFlags -bor 2}
                    $wallClip[0]=$distance;$wallClip[1]=$nextTop;$wallClip[2]=$nextBottom;$wallClip[3]=$silhouetteFlags
                    $wallClip[4]=$lowerSilHeight;$wallClip[5]=$upperSilHeight
                    $spriteClipCounts[$x]=$recordIndex+1
                }
                if($nextTop -gt $nextBottom){$open--}
            }
        }
    }
    if($GeometryDetails){$planesStartedQpc=[Diagnostics.Stopwatch]::GetTimestamp()}
    # PowerShell integer casts round to even. Correcting downward yields floor for
    # these finite Int32-range texture coordinates, avoiding a method binder per pixel.
    # Visplane-style horizontal spans with Doom's fixed-point plane rays. The
    # standalone renderer also honors the process pool's strip boundaries so
    # its spans begin at the same columns as independent render workers.
    for([int]$y=0;$y -lt 168;$y++) {
        [int]$row=$y*320;[int]$x=$FirstColumn;[int]$boundaryIndex=0
        while($boundaryIndex -lt $planeSpanBoundaries.Length -and $planeSpanBoundaries[$boundaryIndex] -le $x){$boundaryIndex++}
        [int]$planeSpanEnd=$EndColumn
        if($boundaryIndex -lt $planeSpanBoundaries.Length -and $planeSpanBoundaries[$boundaryIndex] -lt $planeSpanEnd){$planeSpanEnd=$planeSpanBoundaries[$boundaryIndex]}
        while($x -lt $EndColumn) {
            if($x -ge $planeSpanEnd){
                while($boundaryIndex -lt $planeSpanBoundaries.Length -and $planeSpanBoundaries[$boundaryIndex] -le $x){$boundaryIndex++}
                $planeSpanEnd=$EndColumn
                if($boundaryIndex -lt $planeSpanBoundaries.Length -and $planeSpanBoundaries[$boundaryIndex] -lt $planeSpanEnd){$planeSpanEnd=$planeSpanBoundaries[$boundaryIndex]}
            }
            [int]$id=$planes[$row+$x]
            if($id -eq 0){$x++;continue}
            [int]$sectorIndex=($id-1) -shr 1
            if(($id-1) -band 1){$heightData=$Context.SectorFloorHeightData[$sectorIndex];$flatIndex=$Context.SectorFloorFlatIndex[$sectorIndex]}
            else{$heightData=$Context.SectorCeilingHeightData[$sectorIndex];$flatIndex=$Context.SectorCeilingFlatIndex[$sectorIndex]}
            [byte[]]$flat=$Context.PlaneFlatData[$flatIndex];[int]$sectorLightLevel=$Context.SectorLightLevels[$sectorIndex]
            [long]$heightDelta=[long]$heightData-[long]$viewZData;if($heightDelta -lt 0){$heightDelta=-$heightDelta}
            [long]$distanceDataWide=([long]$heightDelta*[long]$Context.PlaneRowSlopes[$y]) -shr 16
            $distanceDataWide=$distanceDataWide -band 0xFFFFFFFFL
            if($distanceDataWide -ge 0x80000000L){$distanceDataWide-=0x100000000L}
            [int]$distanceData=$distanceDataWide
            [int]$stepX=([long]$distanceData*[long]$planeBaseX) -shr 16
            [int]$stepY=([long]$distanceData*[long]$planeBaseY) -shr 16
            [int]$light=$Context.Lighting.Distance[[Math]::Clamp(($sectorLightLevel -shr 4)+$player.ExtraLight,0,15)][[Math]::Clamp(($distanceData -shr 20),0,127)]
            if($player.FixedColorMap -gt 0){$light=$player.FixedColorMap}
            [byte[]]$colors=$Context.Colors[$light];[byte[]]$flatData=$flat
            [int]$lengthData=([long]$distanceData*[long]$Context.PlaneDistanceScales[$x]) -shr 16
            [long]$xFracWide=[long]$viewXData+(([long]$rayCos[$x]*[long]$lengthData) -shr 16)
            [long]$negViewY=-[long]$viewYData
            [long]$yFracWide=$negViewY-(([long]$raySin[$x]*[long]$lengthData) -shr 16)
            # Flats repeat every 64 map units. The texel lookup consumes only
            # coordinate bits 16..21 for X and 10..15 for Y. Carry the fixed
            # coordinates in Int64 and select those bits at lookup time rather
            # than masking the wrapped 22-bit phase after every pixel. Doom's
            # signed 32-bit wrap cannot change these selected bits because the
            # flat period (2^22) divides the fixed-point word size (2^32).
            [long]$xFrac=$xFracWide
            [long]$yFrac=$yFracWide
            do {
                [int]$u=($xFrac -shr 16) -band 63;[int]$v=($yFrac -shr 10) -band 4032
                [int]$p=$row+$x
                # Planes are background surfaces in Doom's renderer. They fill
                # uncovered pixels but do not occlude world sprites or masked
                # walls drawn later; the depth buffer remains for opaque walls
                # and already-composited sprites only.
                $pixels[$p]=$colors[$flatData[$v+$u]]
                $xFrac+=$stepX
                $yFrac+=$stepY
                $x++
            } while($x -lt $planeSpanEnd -and $planes[$row+$x] -eq $id)
        }
    }
    if($GeometryDetails){$maskedStartedQpc=[Diagnostics.Stopwatch]::GetTimestamp()}
    for([int]$columnIndex=0;$columnIndex -lt $maskedColumnCount;$columnIndex++){
        $column=$maskedColumns[$columnIndex]
        [int]$x=$column.X;[int]$height=$column.Height;[int]$source=$column.U*$height
        [double]$distance=$column.Distance;[double]$origin=$column.Origin
        [int[]]$texels=$column.Texels;[byte[]]$colors=$column.Colors
        [double]$maskedTexelStep=$column.TexelStep
        for([int]$y=$column.Y0;$y -le $column.Y1;$y++){
            [int]$p=$y*320+$x;if($distance -ge $depthBuffer[$p]){continue}
            [double]$vf=$origin+($y-84)*$maskedTexelStep;[int]$v=$vf;if($v -gt $vf){$v--}
            if($v -lt 0 -or $v -ge $height){continue}
            [int]$color=$texels[$source+$v]
            if($color -ge 0){$pixels[$p]=$colors[$color];$depthBuffer[$p]=$distance}
        }
    }
    if($GeometryDetails){$geometryDoneQpc=[Diagnostics.Stopwatch]::GetTimestamp()}
    $geometryMs=$phaseWatch.Elapsed.TotalMilliseconds;$phaseWatch.Restart()
    # Actor sprites share the geometry depth buffer, including masked wall holes.
    $drawActors=$world.Actors
    # Interpolated worker packets explicitly mark their actors as sorted when
    # they contain a Spectre. Avoid scanning the full actor list again in every
    # renderer process; direct snapshots still detect and sort the fallback.
    $actorsPrepared=$world -is [Collections.IDictionary] -and $world.Contains('ActorsDepthSortedForFuzz') -and $world.ActorsDepthSortedForFuzz
    if(-not $actorsPrepared){
        foreach($candidate in $drawActors){
            if($candidate.Flags -band 0x40000){
                $drawActors=@($world.Actors|Sort-Object {($_.X-$cx)*$co+($_.Y-$cy)*$si} -Descending -Stable)
                break
            }
        }
    }
    [bool]$actorsAlreadyFiltered=$world -is [Collections.IDictionary] -and $world.Contains('RenderActorsFiltered') -and $world.RenderActorsFiltered
    if($actorsAlreadyFiltered){$drawActors=$world.RenderActors}
    [int[]]$preparedProjectionData=[int[]]::new(0)
    if($world -is [Collections.IDictionary] -and $world.Contains('RenderProjectionPrepared') -and $world.RenderProjectionPrepared){$preparedProjectionData=$world.RenderProjectionData}
    foreach($actor in $drawActors) {
        if(-not $actorsAlreadyFiltered -and $world -is [Collections.IDictionary] -and $world.Contains('RenderWorkerBit') -and
           (($actor.WorkerMask -band $world.RenderWorkerBit) -eq 0)){continue}
        # The host prepares this fixed-point transform once in its worker
        # visibility pass. Direct snapshots retain the local calculation.
            [int]$projectionOffset=0
            [bool]$projectionCached=$preparedProjectionData.Length -gt 0
            if($projectionCached){$projectionOffset=5*[int]$actor.ProjectionIndex;$projectionCached=$preparedProjectionData[$projectionOffset] -eq 1}
            if($projectionCached){
                [int]$tzData=$preparedProjectionData[$projectionOffset+1];[int]$txData=$preparedProjectionData[$projectionOffset+2];[int]$xScaleData=$preparedProjectionData[$projectionOffset+3]
            }else{
                [int]$actorXData=[Math]::Truncate($actor.X*65536.0);[int]$actorYData=[Math]::Truncate($actor.Y*65536.0)
                [int]$trXData=$actorXData-$viewXData;[int]$trYData=$actorYData-$viewYData
                [int]$gxtData=(([long]$trXData*[long]$spriteViewCosData)-shr $spriteFracBits)
                [int]$gytData=(([long]$trYData*[long]$spriteViewSinData)-shr $spriteFracBits)
                [int]$tzData=$gxtData+$gytData
                if($tzData -lt $spriteMinZData){continue}
                [int]$xScaleData=[Math]::Truncate((10485760.0/[double]$tzData)*65536.0)
                [int]$gxtLateralData=-(([long]$trXData*[long]$spriteViewSinData)-shr $spriteFracBits)
                [int]$gytLateralData=(([long]$trYData*[long]$spriteViewCosData)-shr $spriteFracBits)
                [int]$txData=-($gytLateralData+$gxtLateralData)
                [long]$tzLimitRaw=(([long]$tzData -shl 2) -band 0xFFFFFFFFL)
                if($tzLimitRaw -ge 0x80000000L){$tzLimitRaw-=0x100000000L}
                [int]$tzLimitData=$tzLimitRaw
                if([Math]::Abs([long]$txData) -gt $tzLimitData){continue}
            }

            $frame=$Context.SpriteAtlas[$actor.Sprite][$actor.Frame -band 0x7F]
            [int]$rotation=if($projectionCached){$preparedProjectionData[$projectionOffset+4]}else{0}
            if($null -eq $frame){continue}
            if($frame.Rotate -and -not $projectionCached){
                $rotation=Get-FastSpriteRotation $viewXData $viewYData $actorXData $actorYData $actor.Angle $Context.TanToAngleTable
            }
            $patch=$frame.Patches[$rotation]
            if($null -eq $patch){continue}
            [int]$leftOffsetData=$txData-($patch.Left -shl $spriteFracBits)
            [int]$leftFracData=(160 -shl $spriteFracBits)+([long]$leftOffsetData*[long]$xScaleData -shr $spriteFracBits)
            [int]$rightOffsetData=$leftOffsetData+($patch.Width -shl $spriteFracBits)
            [int]$rightFracData=(160 -shl $spriteFracBits)+([long]$rightOffsetData*[long]$xScaleData -shr $spriteFracBits)
            [int]$firstSpriteColumn=$leftFracData -shr $spriteFracBits
            [int]$lastSpriteColumn=($rightFracData -shr $spriteFracBits)-1
            if($firstSpriteColumn -lt $EndColumn -and $lastSpriteColumn -ge $FirstColumn){
                [double]$scale=$xScaleData/65536.0;[double]$distance=$tzData/65536.0
                [int]$lightIndex=($xScaleData -shr $spriteScaleLightShift)
                $light=if($actor.Frame -band 32768){0}else{$Context.Lighting.Scale[[Math]::Clamp(($actor.LightLevel -shr 4)+$player.ExtraLight,0,15)][[Math]::Min(47,$lightIndex)]}
                if($player.FixedColorMap -gt 0){$light=$player.FixedColorMap}
                [int]$actorZData=[Math]::Truncate($actor.Z*65536.0)
                [int]$textureAltData=$actorZData+($patch.Top -shl $spriteFracBits)-$viewZData
                [int]$topData=(84 -shl $spriteFracBits)-([long]$textureAltData*[long]$xScaleData -shr $spriteFracBits)
                [double]$left=$leftFracData/65536.0;[double]$top=$topData/65536.0
                # Doom clips sprite silhouettes using the world-object base Z
                # and the patch top offset; patch pixel height is not its floor Z.
                [double]$actorTopZ=$actorZData/65536.0+$patch.Top
                [double]$actorBottomZ=$actorZData/65536.0
                [int[]]$actorClipTop=$Context.ActorClipTop;[int[]]$actorClipBottom=$Context.ActorClipBottom
                [int]$clipFirst=[Math]::Max($FirstColumn,$firstSpriteColumn)
                [int]$clipEnd=[Math]::Min($EndColumn,$lastSpriteColumn+1)
                for([int]$x=$clipFirst;$x -lt $clipEnd;$x++){
                    $actorClipTop[$x]=0;$actorClipBottom[$x]=167
                    [int]$clipCount=$spriteClipCounts[$x];$wallClips=$spriteClipWalls[$x]
                    for([int]$clipIndex=0;$clipIndex -lt $clipCount;$clipIndex++){
                        $wallClip=$wallClips[$clipIndex]
                        if([double]$wallClip[0] -ge $distance){continue}
                        [int]$silhouetteFlags=$wallClip[3]
                        if(($silhouetteFlags -band 1) -ne 0 -and $actorBottomZ -lt [double]$wallClip[4]){
                            $actorClipBottom[$x]=[Math]::Min($actorClipBottom[$x],[int]$wallClip[2])
                        }
                        if(($silhouetteFlags -band 2) -ne 0 -and $actorTopZ -gt [double]$wallClip[5]){
                            $actorClipTop[$x]=[Math]::Max($actorClipTop[$x],[int]$wallClip[1]+1)
                        }
                    }
                }
                if($actor.Flags -band 0x40000){
                    Draw-FastFuzzPatch $Context $patch $left $top $scale $distance $frame.Flip[$rotation] $FirstColumn $EndColumn 168 $actorClipTop $actorClipBottom
                }else{
                    Draw-FastPatch $Context $patch $left $top $scale $distance $frame.Flip[$rotation] $light $FirstColumn $EndColumn 168 `
                        -TextureAltData $textureAltData -CenterY 84 -FixedVerticalSampling -ClipTopByColumn $actorClipTop -ClipBottomByColumn $actorClipBottom
                }
            }
    }
    $actorMs=$phaseWatch.Elapsed.TotalMilliseconds;$phaseWatch.Restart()
    Draw-FastPlayerSprites $Context $FirstColumn $EndColumn
    $weaponMs=$phaseWatch.Elapsed.TotalMilliseconds;$phaseWatch.Restart()
    Draw-FastHud $Context $FirstColumn $EndColumn
    $Context.Profile=@{GeometryMs=$geometryMs;ActorsMs=$actorMs;WeaponMs=$weaponMs;HudMs=$phaseWatch.Elapsed.TotalMilliseconds}
    if($GeometryDetails){
        $qpcToMs=1000.0/[Diagnostics.Stopwatch]::Frequency
        $Context.Profile.GeometryDetails=@{
            SetupMs=($wallsStartedQpc-$geometryStartedQpc)*$qpcToMs
            WallsMs=($planesStartedQpc-$wallsStartedQpc)*$qpcToMs
            PlanesMs=($maskedStartedQpc-$planesStartedQpc)*$qpcToMs
            MaskedWallsMs=($geometryDoneQpc-$maskedStartedQpc)*$qpcToMs
        }
    }
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
