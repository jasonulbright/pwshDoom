#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [ValidateRange(1,4)][int]$Episode=1,[ValidateRange(1,9)][int]$Map=1,
    [int[]]$Angles=@(0,90,180),
    [ValidateRange(0,32)][int]$FixedColorMap=0,
    [string]$Renderer="$PSScriptRoot/../src/FastRenderer.ps1",
    [Parameter(Mandatory)][string]$Images,
    [Parameter(Mandatory)][string]$Output
)
$ErrorActionPreference='Stop'
if((Test-Path -LiteralPath $Output) -or (Test-Path -LiteralPath $Images)){throw 'Use fresh report and image directory paths.'}
$null=New-Item -ItemType Directory -Path $Images
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. $Renderer;. "$PSScriptRoot/../src/GameHost.ps1"
Add-Type -AssemblyName System.Drawing
$rendererRelative=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath("$PSScriptRoot/.."),[IO.Path]::GetFullPath($Renderer)).Replace('\','/')
$sources=@('scripts/Compare-RendererReference.ps1',$rendererRelative,'src/GameHost.ps1','src/RenderLighting.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}})
$content=$null;$failure=$null;$views=[Collections.Generic.List[object]]::new()
function PixelHash([byte[]]$Pixels){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Pixels))}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,$Episode,$Map);$null=$game.Update($commands)
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    # A nonzero map is an explicit diagnostic override on both renderers. It
    # removes distance/sector lighting variation without changing the textures.
    $game.World.ConsolePlayer.FixedColorMap=$FixedColorMap
    $config=[Config]::new();$config.video_highresolution=$false;$config.video_gamescreensize=7;$config.video_gammacorrection=0
    $reference=[Renderer]::new($config,$content);$context=New-FastRenderContext $content $game.World
    foreach($angle in $Angles){
        if($angle -lt 0 -or $angle -ge 360){throw 'Fixture headings must be within 0..359 degrees.'}
        # An explicit static camera fixture, not an ordinary-input completion claim.
        $game.World.ConsolePlayer.Mobj.Angle=[Angle]::new([uint32]([Math]::Floor($angle*4294967296.0/360)))
        $snapshot=New-GameRenderSnapshot $game 1
        Set-GameRenderSnapshot $context $snapshot;Invoke-FastRender $context
        $actual=[byte[]]$context.Pixels.Clone()
        $reference.RenderGame($game,[Fixed]::One)
        $expected=[byte[]]::new(64000);$mask=[byte[]]::new(64000)
        $sceneDifferences=0;$hudDifferences=0;[long]$absoluteRgbError=0
        $bitmap=[Drawing.Bitmap]::new(960,200)
        try{
            for($y=0;$y -lt 200;$y++){for($x=0;$x -lt 320;$x++){
                $i=$y*320+$x;$expected[$i]=$reference.Screen.Data[$x*200+$y]
                $a=[int]$actual[$i];$b=[int]$expected[$i]
                if($a -ne $b){$mask[$i]=255;if($y -lt 168){$sceneDifferences++}else{$hudDifferences++}}
                $rgbA=@(0,0,0);$rgbB=@(0,0,0)
                for($c=0;$c -lt 3;$c++){$rgbA[$c]=[int]$content.Palette.Data[3*$a+$c];$rgbB[$c]=[int]$content.Palette.Data[3*$b+$c];$absoluteRgbError+=[Math]::Abs($rgbA[$c]-$rgbB[$c])}
                $bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb($rgbB[0],$rgbB[1],$rgbB[2]))
                $bitmap.SetPixel($x+320,$y,[Drawing.Color]::FromArgb($rgbA[0],$rgbA[1],$rgbA[2]))
                $bitmap.SetPixel($x+640,$y,[Drawing.Color]::FromArgb($mask[$i],$mask[$i],$mask[$i]))
            }}
            $path=Join-Path $Images "e${Episode}m${Map}-${angle}.png";$bitmap.Save($path,[Drawing.Imaging.ImageFormat]::Png)
        }finally{$bitmap.Dispose()}
        $views.Add(@{Angle=$angle;Tic=$snapshot.Tic;Camera=$snapshot.ConsolePlayer.Mobj;ViewZ=$snapshot.ConsolePlayer.ViewZ;Fraction=1;
            SceneComparedPixels=53760;SceneDifferentIndices=$sceneDifferences;HudComparedPixels=10240;HudDifferentIndices=$hudDifferences;
            MeanAbsoluteRgbChannelError=$absoluteRgbError/192000.0;ReferencePixelSha256=(PixelHash $expected);CurrentPixelSha256=(PixelHash $actual);
            ImagePath=[IO.Path]::GetFullPath($path);ImageSha256=(Get-FileHash $path).Hash})
        "Compared E${Episode}M${Map} heading ${angle}: scene $sceneDifferences/53760; HUD $hudDifferences/10240 differing palette indices."
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Episode=$Episode;Map=$Map;FixedColorMap=$FixedColorMap;Views=$views.ToArray();WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;
      Sources=$sources;SourcesChangedDuringRun=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash "$PSScriptRoot/../$($_.Path)").Hash}|ForEach-Object {$_.Path});
      Meaning='Diagnostic comparison against the adopted, locally adapted PowerShell reference renderer at the same static simulation endpoint. This reference is not independently validated original Doom output. No fidelity pass threshold or performance claim. Images show reference, current, then white differing-index mask; base palette, square pixels, 320x168 scene plus HUD. Fixture changes camera heading and optionally the explicitly reported fixed colormap after 35 idle updates.'}|
      ConvertTo-Json -Depth 7|Set-Content -LiteralPath $Output
}
