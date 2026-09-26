#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Output,
    [switch]$AllowMismatch
)
$ErrorActionPreference='Stop'
if(-not $Output){throw 'Pass a fresh -Output path.'}
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"
$content=$null;$failure=$null;$cases=[Collections.Generic.List[object]]::new();$passed=$false
$scaleInputs=@(0.18,0.25,0.33333,0.5,0.75,1.0,1.125,1.5,2.25,3.875)
$textureAltInputs=@(20.0,20.125,50.75,100.0)
$background=[byte]31;$originX=40;$centerY=84;$viewHeight=168
try{
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode
    $options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt $commands.Length;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $context=New-FastRenderContext -Content $content -World $game.World
    $config=[Config]::new();$config.video_highresolution=$false
    $config.video_gamescreensize=7;$config.video_gammacorrection=0
    $reference=[Renderer]::new($config,$content)
    $patch=$content.Sprites.spriteDefs[0].Frames[0].Patches[0]
    if($patch.Name -cne 'TROOA1' -or $patch.Width -le 0 -or $patch.Height -le 0){throw 'Expected the installed Ultimate Doom TROOA1 sprite fixture.'}
    $flat=ConvertTo-RenderPatch -Patch $patch
    $colorMap=$reference.ThreeD.colorMap.get_Item(0)
    # Isolate sampling and clipping: both renderers use the exact same palette
    # lookup even if their normal gamma/lighting tables differ.
    $context.Colors[0]=$colorMap
    [int]$transparentColumns=@($patch.Columns|Where-Object {@($_).Count -eq 0}).Count
    [int]$multiPostColumns=@($patch.Columns|Where-Object {@($_).Count -gt 1}).Count
    foreach($scaleInput in $scaleInputs){
        $scale=[Fixed]::FromDouble($scaleInput);$scaleValue=$scale.ToDouble()
        if($scale.Data -le 0){continue}
        $invScale=[Fixed]::One/$scale
        $xEnd=[Math]::Floor($originX+$patch.Width*$scaleValue)
        foreach($altInput in $textureAltInputs){
            $textureAlt=[Fixed]::FromDouble($altInput)
            $topY=$reference.ThreeD.centerYFrac-($textureAlt*$scale)
            [Array]::Fill($context.Pixels,$background)
            [Array]::Fill($context.Depth,[double]2)
            [Array]::Fill($reference.Screen.Data,$background)
            Draw-FastPatch -Context $context -Patch $flat -Left $originX -Top $topY.ToDouble() `
                -Scale $scaleValue -Distance 1 -Flip:$false -Light 0 -FirstColumn 0 `
                -EndColumn 320 -MaxY $viewHeight -TextureAltData $textureAlt.Data `
                -CenterY $centerY -FixedVerticalSampling
            [long]$sourceFrac=0
            for([int]$x=$originX;$x -lt $xEnd;$x++){
                [int]$textureColumn=$sourceFrac -shr [Fixed]::FracBits
                $textureColumn=[Math]::Clamp($textureColumn,0,$patch.Width-1)
                $reference.ThreeD.DrawMaskedColumn(
                    $patch.Columns[$textureColumn],$colorMap,$x,$topY,$scale,$invScale,
                    $textureAlt,-1,$viewHeight
                )
                $sourceFrac+=$invScale.Data
            }
            [int]$different=0;[int]$candidatePixels=0;[int]$referencePixels=0
            $examples=[Collections.Generic.List[object]]::new()
            for([int]$y=0;$y -lt $viewHeight;$y++){
                for([int]$x=$originX;$x -lt $xEnd;$x++){
                    [int]$candidate=$context.Pixels[$y*320+$x]
                    [int]$original=$reference.Screen.Data[$x*200+$y]
                    if($candidate -ne $background){$candidatePixels++}
                    if($original -ne $background){$referencePixels++}
                    if($candidate -ne $original){
                        $different++
                        if($examples.Count -lt 24){$examples.Add(@{X=$x;Y=$y;Candidate=$candidate;Reference=$original})}
                    }
                }
            }
            $cases.Add([ordered]@{
                ScaleInput=$scaleInput;ScaleData=$scale.Data;TextureAltInput=$altInput
                TextureAltData=$textureAlt.Data;TopYData=$topY.Data;ProjectedColumns=($xEnd-$originX)
                CandidateOpaquePixels=$candidatePixels;ReferenceOpaquePixels=$referencePixels
                PixelMismatches=$different;FirstMismatchExamples=$examples.ToArray()
            })
        }
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}
finally{
    if($content){$content.Dispose()}
    $passed=$cases.Count -gt 0 -and @($cases|Where-Object {$_.PixelMismatches -ne 0}).Count -eq 0
    [ordered]@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o');Wad=(Resolve-Path -LiteralPath $Wad).Path
        WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;RendererSha256=(Get-FileHash "$PSScriptRoot/../src/FastRenderer.ps1").Hash
        ReferenceSha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Video/ThreeDRenderer.sb.ps1").Hash
        PowerShell=$PSVersionTable.PSVersion.ToString();Patch=$patch.Name;PatchWidth=$patch.Width;PatchHeight=$patch.Height
        EmptyColumns=$transparentColumns;MultiPostColumns=$multiPostColumns;HorizontalOrigin=$originX
        CenterY=$centerY;ViewHeight=$viewHeight;ScaleInputs=$scaleInputs;TextureAltInputs=$textureAltInputs
        FixedVerticalSampling=$true;Passed=$passed;MismatchCases=@($cases|Where-Object {$_.PixelMismatches -ne 0}).Count
        Cases=$cases.ToArray();Error=$failure;AllowMismatch=[bool]$AllowMismatch
        Meaning='Isolated real-IWAD TROOA1 masked-post rasterization at fixed-point perspective scales and vertical origins. The PowerShell candidate and adopted PowerShell reference use the same patch, colormap, screen bounds, and integer projected columns. This tests patch vertical sampling/clipping only; it is not a world projection, occlusion, map-completion, or original-executable parity claim.'
    }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
}
if(-not $passed -and -not $AllowMismatch){throw 'World-sprite vertical sampling differs from the adopted PowerShell reference.'}
"$($cases.Count) sprite projection cases; mismatching cases: $(@($cases|Where-Object {$_.PixelMismatches -ne 0}).Count)."
