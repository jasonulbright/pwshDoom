#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Renderer="$PSScriptRoot/../src/FastRenderer.ps1")
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh result.'}
. $Renderer
# Test geometry with authored solid colors; no WAD or session is needed.
function Draw-FastHud {}
function Draw-FastPlayerSprites {}
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check($Name,$Actual,$Expected){$checks.Add(@{Name=$Name;Actual=$Actual;Expected=$Expected;Passed=($Actual -eq $Expected)});if($Actual -ne $Expected){throw "$Name : $Actual != $Expected"}}
$mask=[int[]]::new(64*128);for($u=0;$u -lt 64;$u++){for($v=0;$v -lt 128;$v++){$mask[$u*128+$v]=if(($u%8) -lt 4){200}else{-1}}}
$wall=[int[]]::new(64*128);[Array]::Fill($wall,100)
$flat=[byte[]]::new(4096);[Array]::Fill($flat,[byte]55)
$colors=@(for($i=0;$i -lt 33;$i++){,[byte[]](0..255)})
$ctx=@{Pixels=[byte[]]::new(64000);Depth=[double[]]::new(64000);Planes=[int[]]::new(53760);TopClip=[int[]]::new(320);BottomClip=[int[]]::new(320);Stack=[int[]]::new(4);Nodes=@();
    Subsectors=@{32767=@{FirstSeg=0;SegCount=2}};Lighting=(New-FastLightingTables);Colors=$colors;SkyFlat=1;Sky=@{Data=[int[]]@(0);Width=1;Height=1};
    Sectors=@(@{FloorHeight=0;CeilingHeight=128;FloorFlat=0;CeilingFlat=0;LightLevel=255});Flats=@(@{Data=$flat});
    Sides=@(@{MiddleTexture=1;TopTexture=0;BottomTexture=0;TextureOffset=0;RowOffset=0},@{MiddleTexture=2;TopTexture=0;BottomTexture=0;TextureOffset=0;RowOffset=0});
    Textures=@{1=@{Width=64;Height=128;Data=$mask};2=@{Width=64;Height=128;Data=$wall}};
    Segments=@(@{AX=64;AY=32;BX=64;BY=-32;Length=64;Offset=0;Side=0;Front=0;Back=0;Flags=0;Sector=0},@{AX=128;AY=128;BX=128;BY=-128;Length=256;Offset=0;Side=1;Front=0;Back=-1;Flags=0;Sector=0});
    World=@{Actors=@();ConsolePlayer=@{Mobj=@{X=0;Y=0;Angle=0};ViewZ=41;ExtraLight=0;FixedColorMap=0}}}
try{
    Invoke-FastRender $ctx
    Check 'Fence survives later opaque wall drawing' $ctx.Pixels[25760] 200 # (160,80)
    Check 'Fence depth survives later wall drawing' $ctx.Depth[25760] 64
    Check 'Fence hole reveals far wall' $ctx.Pixels[25774] 100 # (174,80)
    Check 'Fence survives later floor drawing' $ctx.Pixels[48160] 200 # (160,150)
    Check 'Fence hole reveals floor' $ctx.Pixels[48174] 55
    $serial=$ctx.Pixels.Clone();$serialDepth=$ctx.Depth.Clone();$assembled=[byte[]]::new(64000);$assembledDepth=[double[]]::new(64000)
    $bounds=0,45,91,137,182,228,274,320
    for($i=6;$i -ge 0;$i--){Invoke-FastRender $ctx $bounds[$i] $bounds[$i+1];for($y=0;$y -lt 168;$y++){[Array]::Copy($ctx.Pixels,$y*320+$bounds[$i],$assembled,$y*320+$bounds[$i],$bounds[$i+1]-$bounds[$i]);[Array]::Copy($ctx.Depth,$y*320+$bounds[$i],$assembledDepth,$y*320+$bounds[$i],$bounds[$i+1]-$bounds[$i])}}
    Check 'Seven uneven strips preserve scene pixels' ([Linq.Enumerable]::SequenceEqual[byte]([byte[]]$serial[0..53759],[byte[]]$assembled[0..53759])) $true
    Check 'Seven uneven strips preserve scene depth' ([Linq.Enumerable]::SequenceEqual[double]([double[]]$serialDepth[0..53759],[double[]]$assembledDepth[0..53759])) $true
    $patch=@{Width=32;Height=64;Left=16;Top=64;Data=[int[]]::new(2048)};[Array]::Fill($patch.Data,250)
    $ctx.SpriteAtlas=[object[]]::new(1)
    $ctx.SpriteAtlas[0]=[object[]]@(@{Rotate=$false;Patches=@($patch);Flip=@($false)})
    $actor=@{X=96;Y=0;Z=0;Sprite=0;Frame=32768;Flags=0;LightLevel=255;Angle=0};$ctx.World.Actors=@($actor)
    Invoke-FastRender $ctx
    Check 'Fence hides actor behind opaque texel' $ctx.Pixels[25760] 200
    Check 'Actor behind visible through hole' $ctx.Pixels[25774] 250
    $actor.X=32;Invoke-FastRender $ctx
    Check 'Closer actor covers fence' $ctx.Pixels[25760] 250
    $actor.X=200;Invoke-FastRender $ctx
    Check 'Far wall occludes farther actor through hole' $ctx.Pixels[25774] 100
    $ctx.World.Actors=@();$secondMask=$mask.Clone()
    for($i=0;$i -lt $secondMask.Length;$i++){if($secondMask[$i] -ge 0){$secondMask[$i]=201}}
    $ctx.Textures[3]=@{Width=64;Height=128;Data=$secondMask}
    $ctx.Sides+=@{MiddleTexture=3;TopTexture=0;BottomTexture=0;TextureOffset=0;RowOffset=0}
    $ctx.Segments=@($ctx.Segments[0],@{AX=96;AY=32;BX=96;BY=-32;Length=64;Offset=0;Side=2;Front=0;Back=0;Flags=0;Sector=0},$ctx.Segments[1])
    $ctx.Subsectors[32767].SegCount=3;Invoke-FastRender $ctx
    Check 'Nearest fence wins when masked surfaces overlap' $ctx.Pixels[25760] 200
    Check 'Second fence remains visible through nearer hole' $ctx.Pixels[25774] 201
    Check 'Second fence depth retained through nearer hole' $ctx.Depth[25774] 96
}catch{$failure=$_.ToString();throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();RendererSha256=(Get-FileHash $Renderer).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Authored synthetic geometry exercises the real whole-scene rasterizer: transparent fence before opaque wall/floor, billboard depth on either side and uneven strips. HUD/weapon calls replaced with no-ops. No game session, recording, WAD assets or performance claim.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}
"PASS: $($checks.Count) masked-wall checks."
