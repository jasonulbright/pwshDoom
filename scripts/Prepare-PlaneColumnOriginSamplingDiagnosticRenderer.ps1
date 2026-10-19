#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceRoot = Join-Path $repo 'src'
$outputRoot = [IO.Path]::GetFullPath($OutputRoot)
$relative = [IO.Path]::GetRelativePath($repo, $outputRoot)
if ([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")) {
    throw 'Diagnostic renderer must remain inside the project.'
}
if (Test-Path -LiteralPath $outputRoot) { throw 'Use a fresh diagnostic renderer directory.' }
[void][IO.Directory]::CreateDirectory($outputRoot)
foreach ($name in @('FastRenderer.ps1', 'RenderLighting.ps1', 'RenderFuzz.ps1', 'SpriteProjection.ps1')) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination (Join-Path $outputRoot $name)
}

$renderer = Join-Path $outputRoot 'FastRenderer.ps1'
$source = [IO.File]::ReadAllText($renderer)
function Replace-Once([string]$text, [string]$old, [string]$new, [string]$label) {
    if ($text.IndexOf($old, [StringComparison]::Ordinal) -lt 0 -or
        $text.LastIndexOf($old, [StringComparison]::Ordinal) -ne $text.IndexOf($old, [StringComparison]::Ordinal)) {
        throw "Expected exactly one $label."
    }
    return $text.Replace($old, $new)
}

$source = Replace-Once $source 'Planes=[int[]]::new(53760);Patches=@{};' 'Planes=[int[]]::new(53760);PlaneSampleOriginX=[int[]]::new(53760);Patches=@{};' 'plane context field'
$source = Replace-Once $source '[Array]::Clear($pixels);[Array]::Clear($planes);[Array]::Fill($depthBuffer,[double]::PositiveInfinity)' '[Array]::Clear($pixels);[Array]::Clear($planes);[Array]::Clear($Context.PlaneSampleOriginX);[Array]::Fill($depthBuffer,[double]::PositiveInfinity)' 'plane origin reset'

$nl = [Environment]::NewLine
$originPass = @'
    # Reconstruct per-column plane call boundaries from the final candidate
    # plane mask. This diagnostic origin model is isolated from production.
    [int[]]$planeSampleOrigins=$Context.PlaneSampleOriginX
    [int]$ceilingPreviousPlaneId=0;[int]$ceilingPreviousX=[int]::MinValue
    [int]$ceilingPreviousY1=0;[int]$ceilingPreviousY2=-1
    [int]$floorPreviousPlaneId=0;[int]$floorPreviousX=[int]::MinValue
    [int]$floorPreviousY1=0;[int]$floorPreviousY2=-1
    [int[]]$ceilingOriginByY=[int[]]::new(168)
    [int[]]$floorOriginByY=[int[]]::new(168)
    for([int]$originColumn=$FirstColumn;$originColumn -lt $EndColumn;$originColumn++){
        [int]$originY=0
        while($originY -lt 168){
            [int]$originRow=$originY*320+$originColumn
            [int]$originPlaneId=$planes[$originRow]
            if($originPlaneId -eq 0){$originY++;continue}
            [int]$originY1=$originY
            do{$originY++}while($originY -lt 168 -and $planes[$originY*320+$originColumn] -eq $originPlaneId)
            [int]$originY2=$originY-1
            [bool]$originIsFloor=(($originPlaneId-1)-band 1) -ne 0
            if($originIsFloor){
                [bool]$originCanReuse=$originPlaneId -eq $floorPreviousPlaneId -and $floorPreviousX -eq ($originColumn-1)
                [int]$reuseY1=[Math]::Max($originY1,$floorPreviousY1)
                [int]$reuseY2=[Math]::Min($originY2,$floorPreviousY2)
                for([int]$originSampleY=$originY1;$originSampleY -le $originY2;$originSampleY++){
                    if($originCanReuse -and $originSampleY -ge $reuseY1 -and $originSampleY -le $reuseY2){
                        [int]$originX=$floorOriginByY[$originSampleY]
                    }else{
                        [int]$originX=$originColumn
                        $floorOriginByY[$originSampleY]=$originX
                    }
                    $planeSampleOrigins[$originSampleY*320+$originColumn]=$originX
                }
                $floorPreviousPlaneId=$originPlaneId;$floorPreviousX=$originColumn
                $floorPreviousY1=$originY1;$floorPreviousY2=$originY2
            }else{
                [bool]$originCanReuse=$originPlaneId -eq $ceilingPreviousPlaneId -and $ceilingPreviousX -eq ($originColumn-1)
                [int]$reuseY1=[Math]::Max($originY1,$ceilingPreviousY1)
                [int]$reuseY2=[Math]::Min($originY2,$ceilingPreviousY2)
                for([int]$originSampleY=$originY1;$originSampleY -le $originY2;$originSampleY++){
                    if($originCanReuse -and $originSampleY -ge $reuseY1 -and $originSampleY -le $reuseY2){
                        [int]$originX=$ceilingOriginByY[$originSampleY]
                    }else{
                        [int]$originX=$originColumn
                        $ceilingOriginByY[$originSampleY]=$originX
                    }
                    $planeSampleOrigins[$originSampleY*320+$originColumn]=$originX
                }
                $ceilingPreviousPlaneId=$originPlaneId;$ceilingPreviousX=$originColumn
                $ceilingPreviousY1=$originY1;$ceilingPreviousY2=$originY2
            }
        }
    }
'@
$originPass = $originPass.Trim([char]13, [char]10).Replace([string][char]10, $nl)
$source = Replace-Once $source '    # Visplane-style horizontal spans with Doom''s fixed-point plane rays.' ($originPass + $nl + '    # Visplane-style horizontal spans with Doom''s fixed-point plane rays.') 'plane origin pass insertion point'
$source = Replace-Once $source '[int]$lengthData=([long]$distanceData*[long]$Context.PlaneDistanceScales[$x]) -shr 16' '[int]$sampleOriginX=$planeSampleOrigins[$row+$x]' 'plane sample origin read'
$source = Replace-Once $source '[int]$sampleOriginX=$planeSampleOrigins[$row+$x]' ('[int]$sampleOriginX=$planeSampleOrigins[$row+$x]'+$nl+'                [int]$lengthData=([long]$distanceData*[long]$Context.PlaneDistanceScales[$sampleOriginX]) -shr 16') 'plane origin distance scale'
$source = Replace-Once $source '[long]$xFracWide=[long]$viewXData+(([long]$rayCos[$x]*[long]$lengthData) -shr 16)' '[long]$xFracWide=[long]$viewXData+(([long]$rayCos[$sampleOriginX]*[long]$lengthData) -shr 16)' 'plane origin X fraction'
$source = Replace-Once $source '[long]$yFracWide=$negViewY-(([long]$raySin[$x]*[long]$lengthData) -shr 16)' '[long]$yFracWide=$negViewY-(([long]$raySin[$sampleOriginX]*[long]$lengthData) -shr 16)' 'plane origin Y fraction'
$source = Replace-Once $source '[long]$yFracWide=$negViewY-(([long]$raySin[$sampleOriginX]*[long]$lengthData) -shr 16)' ('[long]$yFracWide=$negViewY-(([long]$raySin[$sampleOriginX]*[long]$lengthData) -shr 16)'+$nl+'                $xFracWide += [long]$stepX * ($x - $sampleOriginX)'+$nl+'                $yFracWide += [long]$stepY * ($x - $sampleOriginX)') 'plane origin recurrence offsets'
$source = Replace-Once $source 'while($x -lt $planeSpanEnd -and $planes[$row+$x] -eq $id)' 'while($x -lt $planeSpanEnd -and $planes[$row+$x] -eq $id -and $planeSampleOrigins[$row+$x] -eq $sampleOriginX)' 'plane origin span boundary'
[IO.File]::WriteAllText($renderer, $source, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    OutputRoot = $outputRoot
    Renderer = [IO.Path]::GetRelativePath($repo, $renderer).Replace('\', '/')
    RendererSha256 = (Get-FileHash -LiteralPath $renderer -Algorithm SHA256).Hash
    Variant = 'Experimental candidate plane calls reconstructed as vertical column runs with reference-style previous-column recurrence; production source is untouched.'
}
