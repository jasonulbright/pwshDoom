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

$diagnosticBase = Join-Path $srcRoot '.FastRenderer-visplane-span-diagnostic-base.ps1'
if (Test-Path -LiteralPath $diagnosticBase) { throw 'Temporary diagnostic renderer already exists.' }
try {
    & "$PSScriptRoot/Prepare-FastRendererWallSpanDiagnosticRenderer.ps1" -InputRenderer $sourcePath -Output $diagnosticBase | Out-Null
    $source = [IO.File]::ReadAllText($diagnosticBase)
    $newline = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
    $functionMarker = 'function Invoke-FastRender {'
    if (([regex]::Matches($source, [regex]::Escape($functionMarker))).Count -ne 1) {
        throw 'Expected one fast-render entry point.'
    }

    $functions = @'
function Get-FastCounterfactualVisplane {
    param(
        [Collections.Generic.List[object]]$Visplanes,
        [Collections.Generic.Dictionary[string, int]]$FirstPlaneByKey,
        [string]$Key,
        [int]$HeightData,
        [int]$FlatIndex,
        [int]$LightLevel
    )
    if ($FirstPlaneByKey.ContainsKey($Key)) { return $Visplanes[$FirstPlaneByKey[$Key]] }
    if ($Visplanes.Count -ge 128) { throw 'Counterfactual exceeded Doom MAXVISPLANES (128).' }
    [int[]]$top = [int[]]::new(322)
    [int[]]$bottom = [int[]]::new(322)
    [Array]::Fill($top, 255)
    $plane = [pscustomobject]@{
        Key = $Key; HeightData = $HeightData; FlatIndex = $FlatIndex; LightLevel = $LightLevel
        MinX = 320; MaxX = -1; Top = $top; Bottom = $bottom
    }
    $Visplanes.Add($plane)
    $FirstPlaneByKey.Add($Key, $Visplanes.Count - 1)
    return $plane
}

function Draw-FastVisplaneSpanCounterfactualRun {
    param(
        [hashtable]$Context,
        $Visplane,
        [int]$Y,
        [int]$X1,
        [int]$X2,
        [int]$ViewXData,
        [int]$ViewYData,
        [int]$ViewZData,
        [int]$PlaneBaseX,
        [int]$PlaneBaseY,
        [int]$FixedColorMap,
        [int]$FirstColumn,
        [int]$EndColumn
    )
    if ($X2 -lt $X1) { return }

    [long]$heightDelta = [long]$Visplane.HeightData - [long]$ViewZData
    if ($heightDelta -lt 0) { $heightDelta = -$heightDelta }
    [long]$distanceWide = ($heightDelta * [long]$Context.PlaneRowSlopes[$Y]) -shr 16
    $distanceWide = $distanceWide -band 0xffffffffL
    if ($distanceWide -ge 0x80000000L) { $distanceWide -= 0x100000000L }
    [int]$distanceData = $distanceWide
    [int]$stepX = ([long]$distanceData * [long]$PlaneBaseX) -shr 16
    [int]$stepY = ([long]$distanceData * [long]$PlaneBaseY) -shr 16
    [int]$lengthData = ([long]$distanceData * [long]$Context.PlaneDistanceScales[$X1]) -shr 16
    [long]$xFrac = [long]$ViewXData + (([long]$Context.RayCos[$X1] * [long]$lengthData) -shr 16)
    [long]$yFrac = -[long]$ViewYData - (([long]$Context.RaySin[$X1] * [long]$lengthData) -shr 16)
    [int]$light = $Context.Lighting.Distance[$Visplane.LightLevel][[Math]::Clamp(($distanceData -shr 20), 0, 127)]
    if ($FixedColorMap -gt 0) { $light = $FixedColorMap }
    [byte[]]$flatData = $Context.PlaneFlatData[$Visplane.FlatIndex]
    [byte[]]$colors = $Context.Colors[$light]

    [int]$drawStart = [Math]::Max($FirstColumn, $X1)
    [int]$drawEnd = [Math]::Min($EndColumn - 1, $X2)
    if ($drawStart -gt $drawEnd) { return }
    [long]$skip = $drawStart - $X1
    $xFrac += $stepX * $skip
    $yFrac += $stepY * $skip
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
    [byte[]]$pixels = $Context.Pixels
    for ([int]$x = $drawStart; $x -le $drawEnd; $x++) {
        [int]$u = ($xFrac -shr 16) -band 63
        [int]$v = ($yFrac -shr 10) -band 4032
        [int]$pixelIndex = $Y * 320 + $x
        $pixels[$pixelIndex] = $colors[$flatData[$v + $u]]
        if ($captureSampleDetails) {
            $sampleXFracData[$pixelIndex] = [int]($xFrac -band 0xffffffffL)
            $sampleYFracData[$pixelIndex] = [int]($yFrac -band 0xffffffffL)
            $sampleOriginX[$pixelIndex] = $X1
            $sampleReusedPreviousColumn[$pixelIndex] = [byte]([int]($x -gt $X1))
        }
        $xFrac += $stepX
        $yFrac += $stepY
    }
}

function Draw-FastVisplaneSpanCounterfactual {
    param(
        [hashtable]$Context,
        [int]$CallCount,
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

    if (-not $Context.ContainsKey('DiagnosticPlaneCallSegIndices') -or
        -not $Context.ContainsKey('DiagnosticWallSpanTraceSeen') -or
        -not $Context.ContainsKey('CounterfactualSubsectorTrace')) {
        throw 'This counterfactual requires per-segment calls, clipped wall spans and the traversed subsector sequence.'
    }
    [int[]]$calls = $Context.PlaneSampleCalls
    [int[]]$segmentIndices = $Context.DiagnosticPlaneCallSegIndices
    [byte[]]$wallSpanSeen = $Context.DiagnosticWallSpanTraceSeen
    [int]$segmentCount = $Context.SegmentMetadata.Length / 4
    [int[]]$subsectorBySegment = [int[]]::new($segmentCount)
    [Array]::Fill($subsectorBySegment, -1)
    for ([int]$subsectorIndex = 0; $subsectorIndex -lt $Context.Subsectors.Length; $subsectorIndex++) {
        $subsector = $Context.Subsectors[$subsectorIndex]
        for ([int]$segIndex = $subsector.FirstSeg; $segIndex -lt ($subsector.FirstSeg + $subsector.SegCount); $segIndex++) {
            if ($segIndex -ge 0 -and $segIndex -lt $segmentCount) { $subsectorBySegment[$segIndex] = $subsectorIndex }
        }
    }
    [int[]]$rangeIds = [int[]]::new($wallSpanSeen.Length)
    [int[]]$rangeStarts = [int[]]::new($wallSpanSeen.Length)
    [int[]]$rangeEnds = [int[]]::new($wallSpanSeen.Length)
    [Array]::Fill($rangeIds, -1)
    [Array]::Fill($rangeStarts, -1)
    [Array]::Fill($rangeEnds, -1)
    for ([int]$segmentIndex = 0; $segmentIndex -lt $segmentCount; $segmentIndex++) {
        [int]$segmentOffset = $segmentIndex * 320
        [int]$activeStart = -1
        [int]$activeEnd = -1
        [int]$rangeId = -1
        for ([int]$x = 0; $x -le 320; $x++) {
            [bool]$visible = $x -lt 320 -and $wallSpanSeen[$segmentOffset + $x] -ne 0
            if ($visible) {
                if ($activeStart -lt 0) {
                    $activeStart = $x
                    $activeEnd = $x
                    $rangeId++
                } elseif ($x -eq ($activeEnd + 1)) {
                    $activeEnd = $x
                } else {
                    for ([int]$fillX = $activeStart; $fillX -le $activeEnd; $fillX++) {
                        [int]$cell = $segmentOffset + $fillX
                        $rangeIds[$cell] = $rangeId
                        $rangeStarts[$cell] = $activeStart
                        $rangeEnds[$cell] = $activeEnd
                    }
                    $activeStart = $x
                    $activeEnd = $x
                    $rangeId++
                }
            } elseif ($activeStart -ge 0) {
                for ([int]$fillX = $activeStart; $fillX -le $activeEnd; $fillX++) {
                    [int]$cell = $segmentOffset + $fillX
                    $rangeIds[$cell] = $rangeId
                    $rangeStarts[$cell] = $activeStart
                    $rangeEnds[$cell] = $activeEnd
                }
                $activeStart = -1
                $activeEnd = -1
            }
        }
    }
    [Collections.Generic.List[object]]$segments = [Collections.Generic.List[object]]::new()
    [object]$currentSegment = $null
    [Collections.Generic.List[object]]$currentRanges = $null
    [int]$currentSegmentIndex = -1
    [int]$currentRangeId = -2

    for ([int]$callIndex = 0; $callIndex -lt ($CallCount -shr 2); $callIndex++) {
        [int]$offset = $callIndex * 4
        [int]$segmentIndex = $segmentIndices[$callIndex]
        if ($segmentIndex -lt 0 -or $segmentIndex -ge $segmentCount -or $subsectorBySegment[$segmentIndex] -lt 0) {
            throw "Plane call has no map subsector for segment $segmentIndex."
        }
        [int]$x = $calls[$offset]
        [int]$cell = $segmentIndex * 320 + $x
        [int]$rangeId = $rangeIds[$cell]
        if ($rangeId -lt 0) { throw "Plane call segment $segmentIndex at x=$x is outside its captured visible span." }
        if ($null -eq $currentSegment -or $segmentIndex -ne $currentSegmentIndex -or $rangeId -ne $currentRangeId) {
            $currentRanges = [Collections.Generic.List[object]]::new()
            $currentSegment = [pscustomobject]@{
                SegmentIndex = $segmentIndex; RangeId = $rangeId
                SubsectorIndex = $subsectorBySegment[$segmentIndex]
                StartX = $rangeStarts[$cell]; StopX = $rangeEnds[$cell]
                PlaneRanges = $currentRanges
            }
            $segments.Add($currentSegment)
            $currentSegmentIndex = $segmentIndex
            $currentRangeId = $rangeId
        }
        [int]$planeId = $calls[$offset + 3]
        $range = $null
        foreach ($candidateRange in $currentRanges) {
            if ($candidateRange.PlaneId -eq $planeId) { $range = $candidateRange; break }
        }
        if ($null -eq $range) {
            [Collections.Generic.List[object]]$rangeCalls = [Collections.Generic.List[object]]::new()
            $range = [pscustomobject]@{
                PlaneId = $planeId; MinX = $currentSegment.StartX; MaxX = $currentSegment.StopX; Calls = $rangeCalls
            }
            $currentRanges.Add($range)
        }
        $range.Calls.Add([pscustomobject]@{ X = $x; Y1 = $calls[$offset + 1]; Y2 = $calls[$offset + 2] })
    }

    [Collections.Generic.List[object]]$visplanes = [Collections.Generic.List[object]]::new()
    [Collections.Generic.Dictionary[string, int]]$firstPlaneByKey = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    [Collections.Generic.List[object][]]$segmentsBySubsector = [Collections.Generic.List[object][]]::new($Context.Subsectors.Length)
    for ([int]$i = 0; $i -lt $segmentsBySubsector.Length; $i++) {
        $segmentsBySubsector[$i] = [Collections.Generic.List[object]]::new()
    }
    foreach ($segment in $segments) { $segmentsBySubsector[$segment.SubsectorIndex].Add($segment) }

    [int]$currentSubsectorIndex = -1
    [hashtable]$currentSubsectorPlanes = @{}
    foreach ($subsectorIndexValue in $Context.CounterfactualSubsectorTrace) {
        [int]$subsectorIndex = $subsectorIndexValue
        if ($subsectorIndex -lt 0 -or $subsectorIndex -ge $Context.Subsectors.Length) { throw "Invalid traced subsector $subsectorIndex." }
        [int]$firstSeg = $Context.Subsectors[$subsectorIndex].FirstSeg
        if ($firstSeg -ge 0 -and $firstSeg -lt $segmentCount) {
            [int]$sectorIndex = $Context.SegmentMetadata[$firstSeg * 4 + 1]
        } else {
            $sectorIndex = -1
            for ([int]$candidateSector = 0; $candidateSector -lt $Context.Sectors.Length; $candidateSector++) {
                if ([object]::ReferenceEquals($Context.Subsectors[$subsectorIndex].Sector, $Context.Sectors[$candidateSector])) {
                    $sectorIndex = $candidateSector
                    break
                }
            }
            if ($sectorIndex -lt 0) { throw "Could not resolve sector for subsector $subsectorIndex." }
        }
        if ($subsectorIndex -ne $currentSubsectorIndex) {
            $currentSubsectorIndex = $subsectorIndex
            $currentSubsectorPlanes = @{}
            [int]$floorHeight = $Context.SectorFloorHeightData[$sectorIndex]
            [int]$ceilingHeight = $Context.SectorCeilingHeightData[$sectorIndex]
            [int]$lightLevel = [Math]::Clamp(($Context.SectorLightLevels[$sectorIndex] -shr 4) + $ExtraLight, 0, 15)
            if ($floorHeight -lt $ViewZData) {
                [int]$floorFlat = $Context.SectorFloorFlatIndex[$sectorIndex]
                [string]$floorKey = "$floorHeight`:$floorFlat`:$lightLevel"
                $currentSubsectorPlanes.Floor = Get-FastCounterfactualVisplane $visplanes $firstPlaneByKey $floorKey $floorHeight $floorFlat $lightLevel
            }
            [int]$ceilingFlat = $Context.SectorCeilingFlatIndex[$sectorIndex]
            if ($ceilingHeight -gt $ViewZData -or $ceilingFlat -eq $Context.SkyFlat) {
                if ($ceilingFlat -eq $Context.SkyFlat) {
                    [string]$ceilingKey = "0`:$ceilingFlat`:0"
                    $currentSubsectorPlanes.Ceiling = Get-FastCounterfactualVisplane $visplanes $firstPlaneByKey $ceilingKey 0 $ceilingFlat 0
                } else {
                    [string]$ceilingKey = "$ceilingHeight`:$ceilingFlat`:$lightLevel"
                    $currentSubsectorPlanes.Ceiling = Get-FastCounterfactualVisplane $visplanes $firstPlaneByKey $ceilingKey $ceilingHeight $ceilingFlat $lightLevel
                }
            }
        }

        foreach ($segment in $segmentsBySubsector[$subsectorIndex]) {
            foreach ($range in $segment.PlaneRanges) {
            [int]$planeId = $range.PlaneId
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
            [string]$surface = if ($isFloor) { 'Floor' } else { 'Ceiling' }
            $plane = $currentSubsectorPlanes[$surface]
            if ($null -eq $plane) {
                $plane = Get-FastCounterfactualVisplane $visplanes $firstPlaneByKey $key $heightData $flatIndex $lightLevel
                $currentSubsectorPlanes[$surface] = $plane
            }
            [int]$start = $range.MinX
            [int]$stop = $range.MaxX
            [int]$intersectLow = [Math]::Max($start, $plane.MinX)
            [int]$intersectHigh = [Math]::Min($stop, $plane.MaxX)
            [bool]$overlap = $false
            for ([int]$x = $intersectLow; $x -le $intersectHigh; $x++) {
                if ($plane.Top[$x + 1] -ne 255) { $overlap = $true; break }
            }
            if ($overlap) {
                if ($visplanes.Count -ge 128) { throw 'Counterfactual exceeded Doom MAXVISPLANES (128).' }
                [int[]]$top = [int[]]::new(322)
                [int[]]$bottom = [int[]]::new(322)
                [Array]::Fill($top, 255)
                $plane = [pscustomobject]@{
                    Key = $key; HeightData = $heightData; FlatIndex = $flatIndex; LightLevel = $lightLevel
                    MinX = $start; MaxX = $stop; Top = $top; Bottom = $bottom
                }
                $visplanes.Add($plane)
                $currentSubsectorPlanes[$surface] = $plane
            } else {
                if ($start -lt $plane.MinX) { $plane.MinX = $start }
                if ($stop -gt $plane.MaxX) { $plane.MaxX = $stop }
            }
            foreach ($call in $range.Calls) {
                [int]$index = $call.X + 1
                if ($plane.Top[$index] -ne 255) {
                    throw "Counterfactual plane already contains segment $($segment.SegmentIndex) at x=$($call.X)."
                }
                $plane.Top[$index] = $call.Y1
                $plane.Bottom[$index] = $call.Y2
            }
        }
        }
    }

    $Context.CounterfactualVisplaneInstanceCount = $visplanes.Count
    $Context.CounterfactualPlaneSegmentRangeCount = ($segments | ForEach-Object { $_.PlaneRanges.Count } | Measure-Object -Sum).Sum
    foreach ($plane in $visplanes) {
        if ($plane.MinX -gt $plane.MaxX) { continue }
        [int[]]$spanStart = [int[]]::new(168)
        for ([int]$x = $plane.MinX; $x -le ($plane.MaxX + 1); $x++) {
            [int]$t1 = $plane.Top[$x]
            [int]$b1 = $plane.Bottom[$x]
            [int]$t2 = $plane.Top[$x + 1]
            [int]$b2 = $plane.Bottom[$x + 1]
            while ($t1 -lt $t2 -and $t1 -le $b1) {
                Draw-FastVisplaneSpanCounterfactualRun $Context $plane $t1 $spanStart[$t1] ($x - 1) $ViewXData $ViewYData $ViewZData $PlaneBaseX $PlaneBaseY $FixedColorMap $FirstColumn $EndColumn
                $t1++
            }
            while ($b1 -gt $b2 -and $b1 -ge $t1) {
                Draw-FastVisplaneSpanCounterfactualRun $Context $plane $b1 $spanStart[$b1] ($x - 1) $ViewXData $ViewYData $ViewZData $PlaneBaseX $PlaneBaseY $FixedColorMap $FirstColumn $EndColumn
                $b1--
            }
            while ($t2 -lt $t1 -and $t2 -le $b2) { $spanStart[$t2] = $x; $t2++ }
            while ($b2 -gt $b1 -and $b2 -ge $t2) { $spanStart[$b2] = $x; $b2-- }
        }
    }
}
'@.TrimEnd([char]13, [char]10).Replace("`n", $newline) + $newline

    $source = $source.Replace($functionMarker, $functions + $functionMarker)
    $callMarker = '    Draw-FastPlaneColumnCalls $Context $planeSampleCallCount $viewXData $viewYData $viewZData $planeBaseX $planeBaseY $player.ExtraLight $player.FixedColorMap $planeSpanBoundaries'
    if (([regex]::Matches($source, [regex]::Escape($callMarker))).Count -ne 1) {
        throw 'Expected one production plane renderer call.'
    }
    $callReplacement = '    Draw-FastVisplaneSpanCounterfactual $Context $planeSampleCallCount $viewXData $viewYData $viewZData $planeBaseX $planeBaseY $player.ExtraLight $player.FixedColorMap $FirstColumn $EndColumn'
    $source = $source.Replace($callMarker, $callReplacement)
    $subsectorMarker = '$ss=$Context.Subsectors[$nodeIndex -band 32767]'
    if (([regex]::Matches($source, [regex]::Escape($subsectorMarker))).Count -ne 1) {
        throw 'Expected one BSP subsector selection.'
    }
    $subsectorTrace = $subsectorMarker + $newline +
        '        if($Context.ContainsKey(''CounterfactualSubsectorTrace'')){$Context.CounterfactualSubsectorTrace.Add([int]($nodeIndex -band 32767))}'
    $source = $source.Replace($subsectorMarker, $subsectorTrace)
    [IO.File]::WriteAllText($outputPath, $source, [Text.UTF8Encoding]::new($false))
} finally {
    if (Test-Path -LiteralPath $diagnosticBase) { Remove-Item -LiteralPath $diagnosticBase }
}

[pscustomobject]@{
    InputRenderer = [IO.Path]::GetRelativePath($repo, $sourcePath).Replace('\', '/')
    InputRendererSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
    DiagnosticGeneratorSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath "$PSScriptRoot/Prepare-FastRendererWallSpanDiagnosticRenderer.ps1").Hash
    CounterfactualRenderer = [IO.Path]::GetRelativePath($repo, $outputPath).Replace('\', '/')
    CounterfactualRendererSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
    Meaning = 'Disposable span rasterizer. Groups the captured per-segment plane calls by the Doom height/flat/light key, applies first-match R_FindPlane and overlap-range R_CheckPlane semantics, then draws each top/bottom transition with R_MakeSpans. The input call and clip ranges still come from the adapted renderer; this does not establish original-executable parity.'
}
