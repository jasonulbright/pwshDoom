#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRenderer,
    [Parameter(Mandatory)][string]$Output
)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath=[IO.Path]::GetFullPath($InputRenderer)
$outputPath=[IO.Path]::GetFullPath($Output)
$srcRoot=[IO.Path]::GetFullPath((Join-Path $repo 'src'))
$outputRelative=[IO.Path]::GetRelativePath($srcRoot,$outputPath)
if([IO.Path]::IsPathRooted($outputRelative) -or $outputRelative -eq '..' -or $outputRelative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")){
    throw 'Counterfactual renderer output must remain inside src so its relative imports resolve.'
}
if($sourcePath -eq $outputPath){throw 'Counterfactual renderer cannot overwrite its source.'}
if(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)){throw "Renderer source not found: $sourcePath"}
if(Test-Path -LiteralPath $outputPath){throw 'Use a fresh output path.'}

$source=[IO.File]::ReadAllText($sourcePath)
$source=$source.Replace("`r`n","`n").Replace("`r","`n")
$portalMarker='[int]$portalT=[Math]::Ceiling(84-160*($bc-$cz)/$distance-0.5)'
$portalReplacement=@'
[int]$portalT=[Math]::Ceiling(84-160*($bc-$cz)/$distance-0.5)
                if($wallBoundaryReady -and -not $solid -and $bc -lt $ch -and -not $joinedSky -and $side.TopTexture -gt 0){
                    [int]$portalBackCeilingWorldData=[int](([long]$Context.SectorCeilingHeightData[$segBack]-[long]$viewZData) -shr 4)
                    [int]$portalFrontFloorWorldData=[int](([long]$Context.SectorFloorHeightData[$segFront]-[long]$viewZData) -shr 4)
                    [int]$portalTopWorldData=[Math]::Max($portalBackCeilingWorldData,$portalFrontFloorWorldData)
                    [int]$portalTopFracData=[int]([long](84 -shl 12)-((([long]$portalTopWorldData*[long]$wallScaleData) -shr 16)))
                    $portalT=$portalTopFracData -shr 12
                }
'@.TrimEnd()
if(([regex]::Matches($source,[regex]::Escape($portalMarker))).Count -ne 1){throw 'Expected one projected portal-top marker.'}
$source=$source.Replace($portalMarker,$portalReplacement)
$upperBandMarker='$tex=$side.TopTexture;$wy0=$wallT;$wy1=$portalT-1'
if(([regex]::Matches($source,[regex]::Escape($upperBandMarker))).Count -ne 1){throw 'Expected one portal upper-band endpoint.'}
$source=$source.Replace($upperBandMarker,'$tex=$side.TopTexture;$wy0=$wallT;$wy1=$portalT')

$clipMarker=@'
                if(-not $solid){
                    $nextTop=[Math]::Max($clipT,[Math]::Max($wallT,$portalT))
                    $nextBottom=[Math]::Min($clipB,[Math]::Min($wallB,$portalB))
                }
'@.TrimEnd()
$clipReplacement=@'
                if(-not $solid){
                    $nextTop=[Math]::Max($clipT,[Math]::Max($wallT,$portalT))
                    if($bc -lt $ch -and -not $joinedSky -and $side.TopTexture -gt 0){$nextTop=[Math]::Max($clipT,[Math]::Max($wallT,$portalT+1))}
                    $nextBottom=[Math]::Min($clipB,[Math]::Min($wallB,$portalB))
                }
'@.TrimEnd()
if(([regex]::Matches($source,[regex]::Escape($clipMarker))).Count -ne 1){throw 'Expected one complete portal clipping block.'}
$source=$source.Replace($clipMarker,$clipReplacement)

[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath))
[IO.File]::WriteAllText($outputPath,$source,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    InputRenderer=[IO.Path]::GetRelativePath($repo,$sourcePath).Replace('\','/')
    CounterfactualRenderer=[IO.Path]::GetRelativePath($repo,$outputPath).Replace('\','/')
    InputRendererSha256=(Get-FileHash -LiteralPath $sourcePath).Hash
    CounterfactualRendererSha256=(Get-FileHash -LiteralPath $outputPath).Hash
    Meaning='Disposable source copy only. For a visible textured upper wall, derives the portal top with reference fixed-point operands, includes that projected edge row in the wall span, and advances the next segment clip past it; production source is not edited.'
}
