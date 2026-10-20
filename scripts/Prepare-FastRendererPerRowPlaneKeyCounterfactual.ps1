#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRenderer,
    [Parameter(Mandatory)][string]$Output
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath = [IO.Path]::GetFullPath($InputRenderer)
$outputPath = [IO.Path]::GetFullPath($Output)
$srcRoot = [IO.Path]::GetFullPath((Join-Path $repo 'src'))
$outputRelative = [IO.Path]::GetRelativePath($srcRoot, $outputPath)
if ([IO.Path]::IsPathRooted($outputRelative) -or $outputRelative -eq '..' -or
    $outputRelative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")) {
    throw 'Counterfactual renderer output must remain inside src so its relative imports resolve.'
}
if ($sourcePath -eq $outputPath) { throw 'Counterfactual renderer cannot overwrite its input.' }
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Renderer source not found: $sourcePath" }
if (Test-Path -LiteralPath $outputPath) { throw 'Use a fresh output path.' }

$source = [IO.File]::ReadAllText($sourcePath)
$newline = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }

$contextMarker = '    [bool]$captureSampleDetails = $Context.ContainsKey('
if (([regex]::Matches($source, [regex]::Escape($contextMarker))).Count -ne 1) {
    throw 'Expected one plane sample detail declaration.'
}
$rowState = @'
    [int[]]$ceilingLastXRows = [int[]]::new(168)
    [int[]]$ceilingLastHeightRows = [int[]]::new(168)
    [int[]]$ceilingLastFlatRows = [int[]]::new(168)
    [int[]]$ceilingLastLightRows = [int[]]::new(168)
    [int[]]$floorLastXRows = [int[]]::new(168)
    [int[]]$floorLastHeightRows = [int[]]::new(168)
    [int[]]$floorLastFlatRows = [int[]]::new(168)
    [int[]]$floorLastLightRows = [int[]]::new(168)
'@.TrimEnd([char]13, [char]10).Replace("`n", $newline) + $newline
$source = $source.Replace($contextMarker, $rowState + $contextMarker)

$stripeMarker = '    foreach ($stripeEnd in $stripeEnds) {' + $newline + '        if ($stripeEnd -le $stripeStart) { continue }'
if (([regex]::Matches($source, [regex]::Escape($stripeMarker))).Count -ne 1) {
    throw 'Expected one plane stripe loop.'
}
$stripeState = $stripeMarker + $newline +
    '        [Array]::Fill($ceilingLastXRows, -2)' + $newline +
    '        [Array]::Fill($floorLastXRows, -2)'
$source = $source.Replace($stripeMarker, $stripeState)

$reuseMarker = '                [bool]$reuseCurrentRow = $reusePrevious -and $y -ge $overlapStart -and $y -le $overlapEnd'
if (([regex]::Matches($source, [regex]::Escape($reuseMarker))).Count -ne 1) {
    throw 'Expected one plane row reuse decision.'
}
$reuseByRowKey = @'
                if ($isFloor) {
                    [bool]$reuseCurrentRow = $floorLastXRows[$y] -eq ($x - 1) -and
                        $floorLastHeightRows[$y] -eq $heightData -and
                        $floorLastFlatRows[$y] -eq $flatIndex -and
                        $floorLastLightRows[$y] -eq $Context.SectorLightLevels[$sectorIndex]
                } else {
                    [bool]$reuseCurrentRow = $ceilingLastXRows[$y] -eq ($x - 1) -and
                        $ceilingLastHeightRows[$y] -eq $heightData -and
                        $ceilingLastFlatRows[$y] -eq $flatIndex -and
                        $ceilingLastLightRows[$y] -eq $Context.SectorLightLevels[$sectorIndex]
                }
'@.TrimEnd([char]13, [char]10).Replace("`n", $newline)
$source = $source.Replace($reuseMarker, $reuseByRowKey)

$rowWriteMarker = '                $lightRows[$y] = $light'
if (([regex]::Matches($source, [regex]::Escape($rowWriteMarker))).Count -ne 1) {
    throw 'Expected one per-row plane sample state write.'
}
$rowWrites = @'
                if ($isFloor) {
                    $floorLastXRows[$y] = $x
                    $floorLastHeightRows[$y] = $heightData
                    $floorLastFlatRows[$y] = $flatIndex
                    $floorLastLightRows[$y] = $Context.SectorLightLevels[$sectorIndex]
                } else {
                    $ceilingLastXRows[$y] = $x
                    $ceilingLastHeightRows[$y] = $heightData
                    $ceilingLastFlatRows[$y] = $flatIndex
                    $ceilingLastLightRows[$y] = $Context.SectorLightLevels[$sectorIndex]
                }
'@.TrimEnd([char]13, [char]10).Replace("`n", $newline)
$source = $source.Replace($rowWriteMarker, $rowWriteMarker + $newline + $rowWrites)

[IO.File]::WriteAllText($outputPath, $source, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    InputRenderer = [IO.Path]::GetRelativePath($repo, $sourcePath).Replace('\', '/')
    InputRendererSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
    CounterfactualRenderer = [IO.Path]::GetRelativePath($repo, $outputPath).Replace('\', '/')
    CounterfactualRendererSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
    Meaning = 'Disposable renderer only. Keeps the previous fixed-point sample per row and plane material key, so a same-key call that excludes a row does not erase adjacent-column recurrence state for that row.'
}
