#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [string]$InputRenderer = "$PSScriptRoot/../src/FastRenderer.ps1",
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
$functionMarker = 'function Invoke-FastRender {'
if (([regex]::Matches($source, [regex]::Escape($functionMarker))).Count -ne 1) {
    throw 'Expected one fast-render entry point.'
}

$function = @'
function Draw-FastHorizontalPlaneSpanCounterfactual {
    param(
        [hashtable]$Context,
        [int]$ViewXData,
        [int]$ViewYData,
        [int]$ViewZData,
        [int]$PlaneBaseX,
        [int]$PlaneBaseY,
        [int]$ExtraLight,
        [int]$FixedColorMap,
        [int]$FirstColumn,
        [int]$EndColumn
    )

    [int[]]$planes = $Context.Planes
    [byte[]]$pixels = $Context.Pixels
    [int[]]$materialIds = [int[]]::new($Context.SectorFloorHeightData.Length * 2 + 1)
    [int[]]$planeHeights = [int[]]::new($materialIds.Length)
    [int[]]$planeFlats = [int[]]::new($materialIds.Length)
    [int[]]$planeLights = [int[]]::new($materialIds.Length)
    [Collections.Generic.Dictionary[string, int]]$materials = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)

    for ([int]$planeId = 1; $planeId -lt $materialIds.Length; $planeId++) {
        [int]$sectorIndex = ($planeId - 1) -shr 1
        [bool]$isFloor = ($planeId -band 1) -eq 0
        if ($isFloor) {
            [int]$heightData = $Context.SectorFloorHeightData[$sectorIndex]
            [int]$flatIndex = $Context.SectorFloorFlatIndex[$sectorIndex]
        } else {
            [int]$heightData = $Context.SectorCeilingHeightData[$sectorIndex]
            [int]$flatIndex = $Context.SectorCeilingFlatIndex[$sectorIndex]
        }
        [int]$lightLevel = [Math]::Clamp(($Context.SectorLightLevels[$sectorIndex] -shr 4) + $ExtraLight, 0, 15)
        [string]$key = "$heightData`:$flatIndex`:$lightLevel"
        if (-not $materials.ContainsKey($key)) { $materials.Add($key, $materials.Count) }
        $materialIds[$planeId] = $materials[$key]
        $planeHeights[$planeId] = $heightData
        $planeFlats[$planeId] = $flatIndex
        $planeLights[$planeId] = $lightLevel
    }

    [int[]]$raySin = $Context.RaySin
    [int[]]$rayCos = $Context.RayCos
    [int[]]$rowSlopes = $Context.PlaneRowSlopes
    [int[]]$distanceScales = $Context.PlaneDistanceScales
    [bool]$captureSampleDetails = $Context.ContainsKey('PlaneSampleXFracData') -and
        $Context.ContainsKey('PlaneSampleYFracData') -and $Context.ContainsKey('PlaneSampleOriginX') -and
        $Context.ContainsKey('PlaneSampleReusedPreviousColumn')
    [int[]]$sampleXFracData = $null
    [int[]]$sampleYFracData = $null
    [int[]]$sampleOriginX = $null
    [byte[]]$sampleReusedPreviousColumn = $null
    if ($captureSampleDetails) {
        $sampleXFracData = $Context.PlaneSampleXFracData
        $sampleYFracData = $Context.PlaneSampleYFracData
        $sampleOriginX = $Context.PlaneSampleOriginX
        $sampleReusedPreviousColumn = $Context.PlaneSampleReusedPreviousColumn
    }

    for ([int]$y = 0; $y -lt 168; $y++) {
        [int]$row = $y * 320
        [int]$x = $FirstColumn
        while ($x -lt $EndColumn) {
            [int]$pixelIndex = $row + $x
            [int]$planeId = $planes[$pixelIndex]
            if ($planeId -le 0 -or $planeId -ge $materialIds.Length) { $x++; continue }
            [int]$materialId = $materialIds[$planeId]
            if ($materialId -lt 0) { $x++; continue }
            [int]$spanStart = $x
            [int]$spanEnd = $x + 1
            while ($spanEnd -lt $EndColumn) {
                [int]$nextPlaneId = $planes[$row + $spanEnd]
                if ($nextPlaneId -le 0 -or $nextPlaneId -ge $materialIds.Length -or
                    $materialIds[$nextPlaneId] -ne $materialId) { break }
                $spanEnd++
            }

            [int]$sectorIndex = ($planeId - 1) -shr 1
            [int]$heightData = $planeHeights[$planeId]
            [int]$flatIndex = $planeFlats[$planeId]
            [int]$lightLevel = $planeLights[$planeId]
            [long]$heightDelta = [long]$heightData - [long]$ViewZData
            if ($heightDelta -lt 0) { $heightDelta = -$heightDelta }
            [long]$distanceWide = ($heightDelta * [long]$rowSlopes[$y]) -shr 16
            $distanceWide = $distanceWide -band 0xffffffffL
            if ($distanceWide -ge 0x80000000L) { $distanceWide -= 0x100000000L }
            [int]$distanceData = $distanceWide
            [int]$stepX = ([long]$distanceData * [long]$PlaneBaseX) -shr 16
            [int]$stepY = ([long]$distanceData * [long]$PlaneBaseY) -shr 16
            [int]$lengthData = ([long]$distanceData * [long]$distanceScales[$spanStart]) -shr 16
            [long]$xFrac = [long]$ViewXData + (([long]$rayCos[$spanStart] * [long]$lengthData) -shr 16)
            [long]$yFrac = -[long]$ViewYData - (([long]$raySin[$spanStart] * [long]$lengthData) -shr 16)
            [int[]]$distanceLights = $Context.Lighting.Distance[$lightLevel]
            [int]$light = $distanceLights[[Math]::Clamp(($distanceData -shr 20), 0, 127)]
            if ($FixedColorMap -gt 0) { $light = $FixedColorMap }
            [byte[]]$flatData = $Context.PlaneFlatData[$flatIndex]
            [byte[]]$colors = $Context.Colors[$light]

            for ([int]$spanX = $spanStart; $spanX -lt $spanEnd; $spanX++) {
                [int]$u = ($xFrac -shr 16) -band 63
                [int]$v = ($yFrac -shr 10) -band 4032
                [int]$spanPixelIndex = $row + $spanX
                $pixels[$spanPixelIndex] = $colors[$flatData[$v + $u]]
                if ($captureSampleDetails) {
                    $sampleXFracData[$spanPixelIndex] = [int]($xFrac -band 0xffffffffL)
                    $sampleYFracData[$spanPixelIndex] = [int]($yFrac -band 0xffffffffL)
                    $sampleOriginX[$spanPixelIndex] = $spanStart
                    $sampleReusedPreviousColumn[$spanPixelIndex] = [byte]([int]($spanX -gt $spanStart))
                }
                $xFrac += $stepX
                $yFrac += $stepY
            }
            $x = $spanEnd
        }
    }
}
'@.TrimEnd([char]13, [char]10).Replace("`n", $newline) + $newline

$source = $source.Replace($functionMarker, $function + $functionMarker)
$callMarker = '    Draw-FastPlaneColumnCalls $Context $planeSampleCallCount $viewXData $viewYData $viewZData $planeBaseX $planeBaseY $player.ExtraLight $player.FixedColorMap $planeSpanBoundaries'
if (([regex]::Matches($source, [regex]::Escape($callMarker))).Count -ne 1) {
    throw 'Expected one production plane renderer call.'
}
$callReplacement = '    Draw-FastHorizontalPlaneSpanCounterfactual $Context $viewXData $viewYData $viewZData $planeBaseX $planeBaseY $player.ExtraLight $player.FixedColorMap $FirstColumn $EndColumn'
$source = $source.Replace($callMarker, $callReplacement)

[IO.File]::WriteAllText($outputPath, $source, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    InputRenderer = [IO.Path]::GetRelativePath($repo, $sourcePath).Replace('\', '/')
    InputRendererSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
    CounterfactualRenderer = [IO.Path]::GetRelativePath($repo, $outputPath).Replace('\', '/')
    CounterfactualRendererSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
    Meaning = 'Disposable plane rasterizer. Uses each final visible row run with the same plane height, flat and light key as a horizontal span; starts the fixed-point mapping at the run origin and increments across columns. It tests span sampling over the existing per-pixel ownership buffer, not the full Doom R_FindPlane/R_CheckPlane visibility algorithm.'
}
