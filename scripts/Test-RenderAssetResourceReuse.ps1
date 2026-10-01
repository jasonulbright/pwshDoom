#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Output="$PSScriptRoot/../local/render-asset-reuse.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
. "$PSScriptRoot/../src/RenderAssets.ps1"
$checks=[Collections.Generic.List[string]]::new();$failure=$null
$prefix=[IO.Path]::GetFullPath("$PSScriptRoot/../local/asset-reuse-"+[guid]::NewGuid().ToString('N'))
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};$checks.Add($Name)}
try{
    $patch=@{Width=1;Height=1;Left=0;Top=0;Data=[int[]]@(11);Columns=@(,@(@{TopDelta=0;Length=1;Offset=0;Data=[byte[]]@(11)}))}
    $context=@{Patches=@{Test=$patch};Textures=@{0=$patch};Sky=$patch;SkyFlat=0;Hud=@{};SpriteAtlas=[object[]]::new(0);
        SegmentGeometry=[double[]]::new(6);SegmentMetadata=[int[]]::new(4);NodeGeometry=[double[]]::new(12);NodeChildren=[int[]]::new(2);Subsectors=@(@{FirstSeg=0;SegCount=1});
        PlaneColumnAngles=[uint32[]]::new(320);PlaneDistanceScales=[int[]]::new(320);PlaneRowSlopes=[int[]]::new(168);PlaneFineSine=[int[]]::new(10240);
        TanToAngleTable=[uint32[]]::new(2049);PlaneSpanBoundaries=[int[]]@(160,320);
        Flats=@(@{Data=[byte[]]::new(4096)});Colors=[byte[][]]@([byte[]]::new(256));PlayPal=[byte[]]::new(768);RenderAssetCache=@{}}
    $context.TanToAngleTable[2048]=0x20000000
    $palette=[int[][]]::new(256);for($i=0;$i -lt 256;$i++){$palette[$i]=[int[]]@($i,$i,$i)}
    $path=$prefix+'.assets';Write-GameRenderAssets $context $palette $path
    $first=Read-GameRenderAssets $path -CacheResources
    Check (-not $first.AssetBodyReused) 'Initial reader decodes body'
    $cached=Read-GameRenderAssets $path -Resources $first
    Check $cached.AssetBodyReused 'Identical body is reused'
    Check ([object]::ReferenceEquals($cached.AssetPatches,$first.AssetPatches)) 'Patch graph is shared'
    foreach($field in 'Pixels','Depth','Planes','TopClip','BottomClip','SegmentGeometry','NodeGeometry','Stack'){
        Check (-not [object]::ReferenceEquals($cached[$field],$first[$field])) "Private $field"
    }
    $context.SegmentGeometry[0]=123;$context.NodeGeometry[0]=456;$palette[0][0]=99;$context.PlayPal[0]=17
    Write-GameRenderAssets $context $palette $path
    $metadata=Read-GameRenderAssets $path -Resources $first
    Check $metadata.AssetBodyReused 'Metadata change preserves body reuse'
    Check ($metadata.SegmentGeometry[0] -eq 123 -and $metadata.NodeGeometry[0] -eq 456) 'New map geometry decoded'
    Check ($metadata.Palette[0][0] -eq 99 -and $metadata.PlayPal[0] -eq 17) 'New palette metadata decoded'
    $fresh=Read-GameRenderAssets $path
    Check (-not [object]::ReferenceEquals($fresh.Textures[0],$first.Textures[0])) 'Default reader remains uncached'
    $rejected=$false;try{$null=Read-GameRenderAssets $path -Resources $fresh}catch{$rejected=$_.Exception.Message -eq 'Render asset reuse requires an immutable cached reader context.'}
    Check $rejected 'Uncached reader context rejected as resources'
    # Change a valid data integer in the body without changing any metadata.
    $reader=[IO.BinaryReader]::new([IO.File]::OpenRead($path))
    try{$null=$reader.ReadString();$null=$reader.ReadString();for($i=0;$i -lt 5;$i++){$null=$reader.ReadInt32()};$dataOffset=$reader.BaseStream.Position}finally{$reader.Dispose()}
    $writer=[IO.BinaryWriter]::new([IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write))
    try{$writer.BaseStream.Position=$dataOffset;$writer.Write([int]23)}finally{$writer.Dispose()}
    $changed=Read-GameRenderAssets $path -Resources $first
    Check (-not $changed.AssetBodyReused -and $changed.AssetPatches[0].Data[0] -eq 23) 'Actual changed body invalidates the cache'
    $stream=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write)
    try{$stream.SetLength($stream.Length-1)}finally{$stream.Dispose()}
    $rejected=$false;try{$null=Read-GameRenderAssets $path -Resources $first}catch{$rejected=$true}
    Check $rejected 'Truncated color table is rejected after cache invalidation'
}catch{$failure=$_.ToString();throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Runtime=$PSVersionTable.PSVersion.ToString();
        SourceSha256=(Get-FileHash "$PSScriptRoot/../src/RenderAssets.ps1").Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        Meaning='Synthetic v7 transport: immutable body reuse, independent mutable buffers, regenerated geometry/palette metadata, actual body tamper and truncation. No IWAD pixels, campaign navigation or display timing.'}|ConvertTo-Json -Depth 4|Set-Content $Output
    if(Test-Path -LiteralPath ($prefix+'.assets')){Remove-Item -LiteralPath ($prefix+'.assets')}
}
"PASS: $($checks.Count) render asset reuse checks."
