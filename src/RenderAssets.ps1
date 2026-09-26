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
    $meta=@{Segments=$Context.Segments;Nodes=$Context.Nodes;SkyFlat=$Context.SkyFlat;Sky=$patchIds[$Context.Sky];
        PlaneColumnAngles=$Context.PlaneColumnAngles;PlaneDistanceScales=$Context.PlaneDistanceScales;PlaneRowSlopes=$Context.PlaneRowSlopes;PlaneFineSine=$Context.PlaneFineSine;
        PlaneSpanBoundaries=$planeSpanBoundaries;
        Subsectors=@($Context.Subsectors | ForEach-Object {@{FirstSeg=$_.FirstSeg;SegCount=$_.SegCount}});
        Palette=$Palette;PlayPal=if($Context.ContainsKey('PlayPal')){$Context.PlayPal}else{$Context.Content.Palette.Data};Hud=@{};Textures=@{};SpriteAtlas=[object[]]::new($Context.SpriteAtlas.Length)}
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
    $writer=[IO.BinaryWriter]::new([IO.File]::Create($Path))
    try {
        $writer.Write('pwshDoom-assets-v5');$writer.Write(($meta | ConvertTo-Json -Depth 12 -Compress));$writer.Write($patches.Count)
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
    } finally {$writer.Dispose()}
}

function Read-GameRenderAssets {
    param([string]$Path)
    $reader=[IO.BinaryReader]::new([IO.File]::OpenRead($Path))
    try {
        if($reader.ReadString() -ne 'pwshDoom-assets-v5'){throw 'Unknown render asset format.'}
        $meta=$reader.ReadString() | ConvertFrom-Json -AsHashtable
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
        $ctx=@{Segments=$meta.Segments;Nodes=$meta.Nodes;Subsectors=$meta.Subsectors;SkyFlat=$meta.SkyFlat;Sky=$patches[[int]$meta.Sky];Lighting=(New-FastLightingTables);
            Pixels=[byte[]]::new(64000);Depth=[double[]]::new(64000);Planes=[int[]]::new(53760);TopClip=[int[]]::new(320);BottomClip=[int[]]::new(320);
            Stack=[int[]]::new($meta.Nodes.Count*2+4);Textures=@{};Hud=@{};SpriteAtlas=[object[]]::new($meta.SpriteAtlas.Count);Palette=[int[][]]$meta.Palette;PlayPal=[byte[]]$meta.PlayPal}
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
        $ctx.Flats=[object[]]::new($reader.ReadInt32())
        for($i=0;$i -lt $ctx.Flats.Length;$i++){$ctx.Flats[$i]=@{Data=$reader.ReadBytes($reader.ReadInt32())}}
        $ctx.Colors=[byte[][]]::new($reader.ReadInt32())
        for($i=0;$i -lt $ctx.Colors.Length;$i++){$ctx.Colors[$i]=$reader.ReadBytes($reader.ReadInt32())}
        [uint32[]]$ctx.PlaneColumnAngles=$meta.PlaneColumnAngles
        [int[]]$ctx.PlaneDistanceScales=$meta.PlaneDistanceScales
        [int[]]$ctx.PlaneRowSlopes=$meta.PlaneRowSlopes
        [int[]]$ctx.PlaneFineSine=$meta.PlaneFineSine
        [int[]]$ctx.PlaneSpanBoundaries=[int[]]::new(0)
        if($meta.ContainsKey('PlaneSpanBoundaries') -and $null -ne $meta.PlaneSpanBoundaries){$ctx.PlaneSpanBoundaries=[int[]]$meta.PlaneSpanBoundaries}
        if($ctx.PlaneColumnAngles.Length -ne 320 -or $ctx.PlaneDistanceScales.Length -ne 320 -or $ctx.PlaneRowSlopes.Length -ne 168 -or $ctx.PlaneFineSine.Length -lt 10240){throw 'Invalid fixed-point plane lookup tables.'}
        if($ctx.PlaneSpanBoundaries.Length -gt 320 -or @($ctx.PlaneSpanBoundaries|Where-Object {$_ -lt 0 -or $_ -gt 320}).Count -gt 0){throw 'Invalid plane span boundaries.'}
        for([int]$i=1;$i -lt $ctx.PlaneSpanBoundaries.Length;$i++){if($ctx.PlaneSpanBoundaries[$i] -lt $ctx.PlaneSpanBoundaries[$i-1]){throw 'Plane span boundaries must be ordered.'}}
        return $ctx
    } finally {$reader.Dispose()}
}
