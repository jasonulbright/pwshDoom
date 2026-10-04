# SPDX-License-Identifier: GPL-2.0-or-later
# Private, disposable asset transport. Standard .NET bulk copies, no compiled algorithms.
. "$PSScriptRoot/RenderLighting.ps1"
function Write-GameRenderAssets {
    param($Context,[int[][]]$Palette,[string]$Path)
    [int[]]$planeSpanBoundaries=[int[]]::new(0)
    if($Context.ContainsKey('PlaneSpanBoundaries') -and $null -ne $Context.PlaneSpanBoundaries){$planeSpanBoundaries=[int[]]$Context.PlaneSpanBoundaries}
    $patchIds=[Collections.Generic.Dictionary[object,string]]::new();$patches=[Collections.Generic.List[object]]::new()
    foreach($patch in @($Context.Patches.Values)+@($Context.Textures.Values)+@($Context.Sky)) {
        if(-not $patchIds.ContainsKey($patch)){$patchIds[$patch]=$patches.Count.ToString();$patches.Add($patch)}
    }
    $meta=@{SegmentGeometry=$Context.SegmentGeometry;SegmentMetadata=$Context.SegmentMetadata;NodeGeometry=$Context.NodeGeometry;NodeChildren=$Context.NodeChildren;
        SkyFlat=$Context.SkyFlat;Sky=$patchIds[$Context.Sky];
        PlaneColumnAngles=$Context.PlaneColumnAngles;PlaneDistanceScales=$Context.PlaneDistanceScales;PlaneRowSlopes=$Context.PlaneRowSlopes;PlaneFineSine=$Context.PlaneFineSine;TanToAngleTable=$Context.TanToAngleTable;
        PlaneSpanBoundaries=$planeSpanBoundaries;
        Subsectors=@($Context.Subsectors | ForEach-Object {@{FirstSeg=$_.FirstSeg;SegCount=$_.SegCount}});
        Palette=$Palette;PlayPal=if($Context.ContainsKey('PlayPal')){$Context.PlayPal}else{$Context.Content.Palette.Data};Hud=@{};Textures=@{};SpriteAtlas=[object[]]::new($Context.SpriteAtlas.Length)}
    if($Context.ContainsKey('ViewAngleToX')){$meta.ViewAngleToX=$Context.ViewAngleToX}
    # Original WAD segment angles drive quantized wall texture coordinates.
    # Authored contexts without these angles retain the analytic fallback.
    if($Context.ContainsKey('SegmentAngles')){$meta.SegmentAngles=$Context.SegmentAngles;$meta.WallFineTangent=$Context.WallFineTangent}
    foreach($key in $Context.Textures.Keys){$meta.Textures[$key.ToString()]=$patchIds[$Context.Textures[$key]]}
    foreach($key in $Context.Hud.get_Keys()) {
        $value=$Context.Hud[$key]
        if($value -is [array]){$meta.Hud[$key]=@($value | ForEach-Object {$patchIds[$_]})}
        else{$meta.Hud[$key]=$patchIds[$value]}
    }
    for($i=0;$i -lt $meta.SpriteAtlas.Length;$i++) {
        if($null -eq $Context.SpriteAtlas[$i]){continue}
        $meta.SpriteAtlas[$i]=@($Context.SpriteAtlas[$i] | ForEach-Object {
            @{Rotate=$_.Rotate;Flip=$_.Flip;Patches=@($_.Patches | ForEach-Object {$patchIds[$_]})}
        })
    }
    # Only contexts explicitly opting into immutable resource reuse may cache.
    # Preserve v7 transport: regenerate map metadata, bulk-copy the static body.
    $cache=if($Context.ContainsKey('RenderAssetCache')){$Context.RenderAssetCache}else{$null}
    $hit=$null -ne $cache -and $cache.ContainsKey('Body') -and
        [object]::ReferenceEquals($cache.Flats,$Context.Flats) -and
        [object]::ReferenceEquals($cache.Colors,$Context.Colors) -and $cache.Patches.Count -eq $patches.Count
    if($hit){for($i=0;$i -lt $patches.Count;$i++){
        if(-not [object]::ReferenceEquals($cache.Patches[$i],$patches[$i])){$hit=$false;break}
    }}
    if($null -ne $cache -and -not $hit){
        $stream=[IO.MemoryStream]::new();$bodyWriter=[IO.BinaryWriter]::new($stream)
        try{
            Write-GameRenderAssetBody $Context $patches $bodyWriter
            $bodyWriter.Flush();$cache.Body=$stream.ToArray()
            $cache.Patches=$patches.ToArray();$cache.Flats=$Context.Flats;$cache.Colors=$Context.Colors
        }finally{$bodyWriter.Dispose();$stream.Dispose()}
    }
    $writer=[IO.BinaryWriter]::new([IO.File]::Create($Path))
    try {
        $writer.Write('pwshDoom-assets-v7');$writer.Write(($meta | ConvertTo-Json -Depth 12 -Compress))
        if($null -ne $cache){$writer.Write([byte[]]$cache.Body)}else{Write-GameRenderAssetBody $Context $patches $writer}
    } finally {$writer.Dispose()}
}

function Write-GameRenderAssetBody {
    param($Context,$Patches,[IO.BinaryWriter]$Writer)
        $writer.Write([int]$patches.Count)
        [byte[]]$sampleBlock=[byte[]]::new(128)
        foreach($p in $patches) {
            $writer.Write([int]$p.Width);$writer.Write([int]$p.Height);$writer.Write([int]$p.Left);$writer.Write([int]$p.Top)
            $bytes=[byte[]]::new($p.Data.Length*4);[Buffer]::BlockCopy($p.Data,0,$bytes,0,$bytes.Length);$writer.Write($bytes)
            $columns=if($null -ne $p.Columns){$p.Columns}else{@()}
            $sourceIds=[Collections.Generic.Dictionary[byte[],int]]::new()
            $sources=[Collections.Generic.List[byte[]]]::new()
            foreach($column in $columns){
                foreach($post in $column){
                    if($post.TopDelta -eq 255){continue}
                    if(-not $sourceIds.ContainsKey($post.Data)){$sourceIds.Add($post.Data,$sources.Count);$sources.Add($post.Data)}
                }
            }
            $writer.Write([int]$sources.Count)
            foreach($source in $sources){$writer.Write([int]$source.Length);$writer.Write($source)}
            $writer.Write([int]$columns.Length)
            foreach($column in $columns){
                $posts=@($column|Where-Object {$_.TopDelta -ne 255})
                $writer.Write([int]$posts.Count)
                foreach($post in $posts){
                    $writer.Write([int]$post.TopDelta);$writer.Write([int]$post.Length)
                    $writer.Write([int]$sourceIds[$post.Data]);$writer.Write([int]$post.Offset)
                }
            }
        }
        $writer.Write($Context.Flats.Length)
        foreach($flat in $Context.Flats) {
            if($null -eq $flat){$writer.Write(0)}else{$writer.Write($flat.Data.Length);$writer.Write($flat.Data)}
        }
        $writer.Write($Context.Colors.Length)
        foreach($colors in $Context.Colors){$writer.Write($colors.Length);$writer.Write($colors)}
}

function Read-GameRenderAssets {
    param([string]$Path,$Resources,[switch]$CacheResources)
    if($null -ne $Resources -and (-not $Resources.ContainsKey('AssetBodySha256') -or -not $Resources.ContainsKey('AssetPatches'))){
        throw 'Render asset reuse requires an immutable cached reader context.'
    }
    $reader=[IO.BinaryReader]::new([IO.File]::OpenRead($Path))
    try {
        if($reader.ReadString() -ne 'pwshDoom-assets-v7'){throw 'Unknown render asset format.'}
        $meta=$reader.ReadString() | ConvertFrom-Json -AsHashtable
        [double[]]$segmentGeometry=$meta.SegmentGeometry;[int[]]$segmentMetadata=$meta.SegmentMetadata
        [double[]]$nodeGeometry=$meta.NodeGeometry;[int[]]$nodeChildren=$meta.NodeChildren
        if($segmentGeometry.Length%6 -ne 0 -or $segmentMetadata.Length -ne ($segmentGeometry.Length/6)*4){throw 'Invalid packed segment geometry.'}
        if($meta.ContainsKey('SegmentAngles')){
            [uint32[]]$segmentAngles=$meta.SegmentAngles
            if($segmentAngles.Length -ne $segmentGeometry.Length/6){throw 'Invalid packed segment angles.'}
            [int[]]$wallFineTangent=$meta.WallFineTangent
            if($wallFineTangent.Length -ne 4096){throw 'Invalid wall tangent table.'}
        }
        if($meta.ContainsKey('ViewAngleToX')){
            [int[]]$viewAngleToX=$meta.ViewAngleToX
            if($viewAngleToX.Length -ne 4096 -or @($viewAngleToX | Where-Object {$_ -lt 0 -or $_ -gt 320}).Count -ne 0){throw 'Invalid wall projection table.'}
        }
        if($nodeGeometry.Length%12 -ne 0 -or $nodeChildren.Length -ne ($nodeGeometry.Length/12)*2){throw 'Invalid packed BSP node geometry.'}
        $bodyHash=$null;$reuse=$false
        if($CacheResources -or $null -ne $Resources){
            # Verify the actual remaining file bytes; metadata is always decoded
            # anew, and neither a path nor a header claim can produce a hit.
            $bodyStart=$reader.BaseStream.Position
            $bodyHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($reader.BaseStream))
            $reader.BaseStream.Position=$bodyStart
            $reuse=$null -ne $Resources -and $Resources.AssetBodySha256 -ceq $bodyHash
        }
        if($reuse){$patches=$Resources.AssetPatches}else{
        $patches=[object[]]::new($reader.ReadInt32())
        for($i=0;$i -lt $patches.Length;$i++) {
            $w=$reader.ReadInt32();$h=$reader.ReadInt32();$left=$reader.ReadInt32();$top=$reader.ReadInt32()
            $data=[int[]]::new($w*$h);$bytes=$reader.ReadBytes($data.Length*4)
            if($bytes.Length -ne $data.Length*4){throw 'Truncated render asset cache.'}
            [Buffer]::BlockCopy($bytes,0,$data,0,$bytes.Length)
            $sourceBuffers=[byte[][]]::new($reader.ReadInt32())
            for([int]$sourceIndex=0;$sourceIndex -lt $sourceBuffers.Length;$sourceIndex++){
                $sourceLength=$reader.ReadInt32();$sourceBuffers[$sourceIndex]=$reader.ReadBytes($sourceLength)
                if($sourceBuffers[$sourceIndex].Length -ne $sourceLength){throw 'Truncated masked sprite source data.'}
            }
            $columnCount=$reader.ReadInt32();$columns=[object[]]::new($columnCount)
            for([int]$x=0;$x -lt $columnCount;$x++){
                $posts=[object[]]::new($reader.ReadInt32())
                for([int]$postIndex=0;$postIndex -lt $posts.Length;$postIndex++){
                    $topDelta=$reader.ReadInt32();$length=$reader.ReadInt32();$sourceIndex=$reader.ReadInt32();$offset=$reader.ReadInt32()
                    if($sourceIndex -lt 0 -or $sourceIndex -ge $sourceBuffers.Length -or $offset -lt 0 -or $offset -gt $sourceBuffers[$sourceIndex].Length){throw 'Invalid masked sprite source reference.'}
                    $posts[$postIndex]=@{TopDelta=$topDelta;Length=$length;Offset=$offset;Data=$sourceBuffers[$sourceIndex]}
                }
                $columns[$x]=$posts
            }
            $patches[$i]=@{Width=$w;Height=$h;Left=$left;Top=$top;Data=$data;Columns=$columns}
        }
        }
        $ctx=@{SegmentGeometry=$segmentGeometry;SegmentMetadata=$segmentMetadata;NodeGeometry=$nodeGeometry;NodeChildren=$nodeChildren;
            Subsectors=$meta.Subsectors;SkyFlat=$meta.SkyFlat;Sky=$patches[[int]$meta.Sky];Lighting=(New-FastLightingTables);
            Pixels=[byte[]]::new(64000);Depth=[double[]]::new(64000);Planes=[int[]]::new(53760);TopClip=[int[]]::new(320);BottomClip=[int[]]::new(320);
            Stack=[int[]]::new(($nodeGeometry.Length/12)*2+4);SkyColumns=[int[]]::new(320);RaySin=[int[]]::new(320);RayCos=[int[]]::new(320);
            MaskedColumns=[Collections.Generic.List[hashtable]]::new();Textures=@{};Hud=@{};SpriteAtlas=[object[]]::new($meta.SpriteAtlas.Count);Palette=[int[][]]$meta.Palette;PlayPal=[byte[]]$meta.PlayPal}
        if($meta.ContainsKey('ViewAngleToX')){$ctx.ViewAngleToX=$viewAngleToX}
        if($meta.ContainsKey('SegmentAngles')){$ctx.SegmentAngles=$segmentAngles;$ctx.WallFineTangent=$wallFineTangent}
        foreach($key in $meta.Textures.Keys){$ctx.Textures[[int]$key]=$patches[[int]$meta.Textures[$key]]}
        foreach($key in $meta.Hud.get_Keys()) {
            $value=$meta.Hud[$key]
            if($value -is [array]){$ctx.Hud[$key]=@($value | ForEach-Object {$patches[[int]$_]})}
            else{$ctx.Hud[$key]=$patches[[int]$value]}
        }
        for($i=0;$i -lt $ctx.SpriteAtlas.Length;$i++) {
            if($null -eq $meta.SpriteAtlas[$i]){continue}
            $ctx.SpriteAtlas[$i]=@($meta.SpriteAtlas[$i] | ForEach-Object {
                @{Rotate=$_.Rotate;Flip=[bool[]]$_.Flip;Patches=@($_.Patches | ForEach-Object {$patches[[int]$_]})}
            })
        }
        if($reuse){
            $ctx.Flats=$Resources.Flats;$ctx.Colors=$Resources.Colors;$ctx.Lighting=$Resources.Lighting
        }else{
        $ctx.Flats=[object[]]::new($reader.ReadInt32())
        for($i=0;$i -lt $ctx.Flats.Length;$i++){
            $length=$reader.ReadInt32();$data=$reader.ReadBytes($length)
            if($data.Length -ne $length){throw 'Truncated render flat data.'}
            $ctx.Flats[$i]=@{Data=$data}
        }
        $ctx.Colors=[byte[][]]::new($reader.ReadInt32())
        for($i=0;$i -lt $ctx.Colors.Length;$i++){
            $length=$reader.ReadInt32();$ctx.Colors[$i]=$reader.ReadBytes($length)
            if($ctx.Colors[$i].Length -ne $length){throw 'Truncated render color data.'}
        }
        }
        if($CacheResources -or $null -ne $Resources){$ctx.AssetBodySha256=$bodyHash;$ctx.AssetPatches=$patches;$ctx.AssetBodyReused=$reuse}
        [uint32[]]$ctx.PlaneColumnAngles=$meta.PlaneColumnAngles
        [int[]]$ctx.PlaneDistanceScales=$meta.PlaneDistanceScales
        [int[]]$ctx.PlaneRowSlopes=$meta.PlaneRowSlopes
        [int[]]$ctx.PlaneFineSine=$meta.PlaneFineSine
        [uint32[]]$ctx.TanToAngleTable=$meta.TanToAngleTable
        [int[]]$ctx.PlaneSpanBoundaries=[int[]]::new(0)
        if($meta.ContainsKey('PlaneSpanBoundaries') -and $null -ne $meta.PlaneSpanBoundaries){$ctx.PlaneSpanBoundaries=[int[]]$meta.PlaneSpanBoundaries}
        if($ctx.PlaneColumnAngles.Length -ne 320 -or $ctx.PlaneDistanceScales.Length -ne 320 -or $ctx.PlaneRowSlopes.Length -ne 168 -or $ctx.PlaneFineSine.Length -lt 10240){throw 'Invalid fixed-point plane lookup tables.'}
        if($ctx.TanToAngleTable.Length -ne 2049 -or $ctx.TanToAngleTable[0] -ne 0 -or $ctx.TanToAngleTable[2048] -ne 0x20000000){throw 'Invalid Doom tangent-to-angle lookup table.'}
        if($ctx.PlaneSpanBoundaries.Length -gt 320 -or @($ctx.PlaneSpanBoundaries|Where-Object {$_ -lt 0 -or $_ -gt 320}).Count -gt 0){throw 'Invalid plane span boundaries.'}
        for([int]$i=1;$i -lt $ctx.PlaneSpanBoundaries.Length;$i++){if($ctx.PlaneSpanBoundaries[$i] -lt $ctx.PlaneSpanBoundaries[$i-1]){throw 'Plane span boundaries must be ordered.'}}
        return $ctx
    } finally {$reader.Dispose()}
}
