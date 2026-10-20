#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [string]$Wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay = "$PSScriptRoot/../results/e1m1-route-lineflags.json",
    [string]$TraceReceipt = "$PSScriptRoot/../results/moving-sector-reference-plane-full-call-trace-20261020.json",
    [string]$RangeTraceReceipt = "$PSScriptRoot/../results/moving-sector-reference-visible-range-trace-20261020.json",
    [string]$EngineBundle = "$PSScriptRoot/../local/engine-bundle.ps1",
    [string]$Output = "$PSScriptRoot/../results/moving-sector-visplane-mismatch-origins-rfindplane-corrected-20261020.json",
    [ValidateSet('candidate', 'reference')][string[]]$Renderers = @('candidate', 'reference')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
foreach ($pathName in 'Wad', 'Replay', 'TraceReceipt', 'RangeTraceReceipt', 'EngineBundle', 'Output') {
    Set-Variable -Name $pathName -Value ([IO.Path]::GetFullPath((Get-Variable -Name $pathName -ValueOnly)))
}
foreach ($path in $Wad, $Replay, $TraceReceipt, $RangeTraceReceipt, $EngineBundle) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required input not found: $path" }
}
$outputRelative = [IO.Path]::GetRelativePath($root, $Output)
if ([IO.Path]::IsPathRooted($outputRelative) -or $outputRelative -eq '..' -or
    $outputRelative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")) {
    throw 'Analysis output must remain inside the project.'
}
if (Test-Path -LiteralPath $Output) { throw 'Use a fresh analysis output path.' }

$trace = Get-Content -LiteralPath $TraceReceipt -Raw | ConvertFrom-Json
$rangeTraceData = Get-Content -LiteralPath $RangeTraceReceipt -Raw | ConvertFrom-Json
$replayData = Get-Content -LiteralPath $Replay -Raw | ConvertFrom-Json
$wadSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Wad).Hash
$replaySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Replay).Hash
if ($trace.WadSha256 -cne $wadSha256 -or $trace.ReplaySha256 -cne $replaySha256) {
    throw 'The trace receipt, replay and IWAD hashes do not match.'
}
if ($rangeTraceData.WadSha256 -cne $wadSha256 -or
    $rangeTraceData.ReplaySha256 -cne $replaySha256 -or
    $rangeTraceData.InputTic -ne $trace.InputTic -or
    $rangeTraceData.SectorIndex -ne $trace.SectorIndex) {
    throw 'The visible-range receipt does not match the replay, IWAD, tic and sector.'
}
$heightRecord = $trace.Heights | Where-Object CeilingHeight -eq 68 | Select-Object -First 1
if ($null -eq $heightRecord) { throw 'The trace receipt has no ceiling-height-68 sample.' }
$rangeHeightRecord = $rangeTraceData.Heights | Where-Object CeilingHeight -eq 68 | Select-Object -First 1
if ($null -eq $rangeHeightRecord -or @($rangeHeightRecord.ReferencePlaneRangeTrace).Count -eq 0) {
    throw 'The visible-range receipt has no height-68 reference intervals.'
}
$rangeReferenceCalls = @($rangeHeightRecord.ReferencePlaneCallTrace)
$rangeEvents = @($rangeHeightRecord.ReferencePlaneRangeTrace)
if ($rangeReferenceCalls.Count -ne @($heightRecord.ReferencePlaneCallTrace).Count) {
    throw 'The visible-range receipt has a different reference plane-call count.'
}
for ([int]$callIndex = 0; $callIndex -lt $rangeReferenceCalls.Count; $callIndex++) {
    $expectedCall = $heightRecord.ReferencePlaneCallTrace[$callIndex]
    $actualCall = $rangeReferenceCalls[$callIndex]
    foreach ($field in 'Ordinal', 'X', 'Y1', 'Y2', 'SectorIndex', 'SurfaceType', 'SegmentIndex') {
        if ($actualCall.$field -cne $expectedCall.$field) {
            throw "The visible-range receipt reference call differs at index $callIndex ($field)."
        }
    }
    $matchingRanges = @($rangeEvents | Where-Object {
        $_.SegmentIndex -eq $actualCall.SegmentIndex -and
        $_.StartX -le $actualCall.X -and $_.StopXInclusive -ge $actualCall.X
    })
    if ($matchingRanges.Count -ne 1) {
        throw "Reference plane call $callIndex does not map to exactly one matching clipped range."
    }
    if ($matchingRanges[0].FrontSectorIndex -ne $actualCall.SectorIndex) {
        throw "Reference plane call $callIndex disagrees with its clipped range front sector."
    }
}
$sampleExample = @($heightRecord.SameOwnerPlaneSampleExamples | Select-Object -First 1)
if ($sampleExample.Count -ne 1) { throw 'The trace must contain a same-owner plane sample.' }
if ($trace.InputTic -gt $replayData.InputCommands.Count) { throw 'The replay does not contain the trace input tic.' }

. $EngineBundle
. "$PSScriptRoot/../src/FastRenderer.ps1"

function New-VisplaneRecord([int]$Id, [string]$MaterialKey) {
    [int[]]$top = [int[]]::new(320)
    [Array]::Fill($top, 255)
    [int[]]$bottom = [int[]]::new(320)
    [Array]::Fill($bottom, -1)
    return [pscustomobject]@{
        Id = $Id
        MaterialKey = $MaterialKey
        MinX = 320
        MaxX = -1
        Top = $top
        Bottom = $bottom
    }
}

function Get-VisplaneSpanPrediction {
    param(
        [object[]]$Calls,
        $Map,
        [hashtable]$ProjectedRanges,
        [int]$SkyFlatNumber,
        [string]$RangeMode,
        [object[]]$Samples,
        [object[]]$ExactRanges,
        [int]$ViewZData
    )

    $events = [Collections.Generic.List[object]]::new()
    if ($RangeMode -eq 'DoomClipIntervals') {
        foreach ($range in $ExactRanges | Sort-Object Ordinal) {
            [int]$frontSectorIndex = $range.FrontSectorIndex
            [int]$backSectorIndex = $range.BackSectorIndex
            if ($frontSectorIndex -lt 0 -or $frontSectorIndex -ge $Map.Sectors.Length) {
                throw "Clipped range $($range.Ordinal) has an invalid front sector."
            }
            $frontSector = $Map.Sectors[$frontSectorIndex]
            [int]$frontFloor = $frontSector.FloorHeight.Data
            [int]$frontCeiling = $frontSector.CeilingHeight.Data
            [bool]$markFloor = $backSectorIndex -lt 0
            [bool]$markCeiling = $backSectorIndex -lt 0

            if ($backSectorIndex -ge 0) {
                if ($backSectorIndex -ge $Map.Sectors.Length) {
                    throw "Clipped range $($range.Ordinal) has an invalid back sector."
                }
                $backSector = $Map.Sectors[$backSectorIndex]
                [int]$backFloor = $backSector.FloorHeight.Data
                [int]$backCeiling = $backSector.CeilingHeight.Data
                [int]$worldBottom = $frontFloor - $ViewZData
                [int]$worldLow = $backFloor - $ViewZData
                [int]$worldTop = $frontCeiling - $ViewZData
                [int]$worldHigh = $backCeiling - $ViewZData
                if ($frontSector.CeilingFlat -eq $SkyFlatNumber -and
                    $backSector.CeilingFlat -eq $SkyFlatNumber) {
                    $worldTop = $worldHigh
                }

                $markFloor = $worldLow -ne $worldBottom -or
                    $backSector.FloorFlat -ne $frontSector.FloorFlat -or
                    $backSector.LightLevel -ne $frontSector.LightLevel
                $markCeiling = $worldHigh -ne $worldTop -or
                    $backSector.CeilingFlat -ne $frontSector.CeilingFlat -or
                    $backSector.LightLevel -ne $frontSector.LightLevel
                if ($backCeiling -le $frontFloor -or $backFloor -ge $frontCeiling) {
                    $markFloor = $true
                    $markCeiling = $true
                }
            }

            if ($frontFloor -ge $ViewZData) { $markFloor = $false }
            if ($frontCeiling -le $ViewZData -and $frontSector.CeilingFlat -ne $SkyFlatNumber) {
                $markCeiling = $false
            }

            foreach ($surfaceType in 'Ceiling', 'Floor') {
                $marked = if ($surfaceType -eq 'Floor') { $markFloor } else { $markCeiling }
                if (-not $marked) { continue }
                [int]$surfaceOrder = if ($surfaceType -eq 'Ceiling') { 0 } else { 1 }
                $rangeCalls = @($Calls | Where-Object {
                    $_.SegmentIndex -eq $range.SegmentIndex -and
                    $_.SurfaceType -eq $surfaceType -and
                    $_.X -ge $range.StartX -and $_.X -le $range.StopXInclusive
                })
                foreach ($rangeCall in $rangeCalls) {
                    if ($rangeCall.SectorIndex -ne $frontSectorIndex) {
                        throw "Clipped range $($range.Ordinal) disagrees with its plane-call front sector."
                    }
                }
                $events.Add([pscustomobject]@{
                    FirstOrdinal = ([int]$range.Ordinal * 2) + $surfaceOrder
                    SegmentIndex = [int]$range.SegmentIndex
                    SectorIndex = $frontSectorIndex
                    SurfaceType = $surfaceType
                    Calls = $rangeCalls
                    StartX = [int]$range.StartX
                    StopX = [int]$range.StopXInclusive
                    RangeOrdinal = [int]$range.Ordinal
                })
            }
        }
    } else {
        $callsBySegmentSurface = @{}
        foreach ($call in $Calls) {
            if ($call.SurfaceType -notin 'Floor', 'Ceiling') { continue }
            $bucketKey = "$($call.SegmentIndex)|$($call.SurfaceType)"
            if (-not $callsBySegmentSurface.ContainsKey($bucketKey)) {
                $callsBySegmentSurface[$bucketKey] = [Collections.Generic.List[object]]::new()
            }
            $callsBySegmentSurface[$bucketKey].Add($call)
        }
        foreach ($bucketKey in $callsBySegmentSurface.Keys) {
            $bucket = $callsBySegmentSurface[$bucketKey]
            $first = $bucket[0]
            $events.Add([pscustomobject]@{
                FirstOrdinal = [int]$first.Ordinal
                SegmentIndex = [int]$first.SegmentIndex
                SectorIndex = [int]$first.SectorIndex
                SurfaceType = [string]$first.SurfaceType
                Calls = $bucket
            })
        }
    }
    $events = @($events | Sort-Object FirstOrdinal)

    $visplanes = [Collections.Generic.List[object]]::new()
    [int]$nextVisplaneId = 0
    foreach ($event in $events) {
        $sector = $Map.Sectors[$event.SectorIndex]
        if ($event.SurfaceType -eq 'Floor') {
            [int]$heightData = $sector.FloorHeight.Data
            [int]$flatIndex = $sector.FloorFlat
        } else {
            [int]$heightData = $sector.CeilingHeight.Data
            [int]$flatIndex = $sector.CeilingFlat
        }
        [int]$lightLevel = $sector.LightLevel
        if ($flatIndex -eq $SkyFlatNumber) {
            $heightData = 0
            $lightLevel = 0
        }
        $materialKey = "$heightData|$flatIndex|$lightLevel"
        # Doom's R_FindPlane scans from the first visplane and reuses the first
        # matching height/flat/light key, including after R_CheckPlane has split it.
        $plane = $null
        foreach ($knownPlane in $visplanes) {
            if ($knownPlane.MaterialKey -ceq $materialKey) { $plane = $knownPlane; break }
        }
        if ($null -eq $plane) {
            $plane = New-VisplaneRecord $nextVisplaneId $materialKey
            $nextVisplaneId++
            $visplanes.Add($plane)
        }

        if ($RangeMode -eq 'DoomClipIntervals') {
            [int]$startX = $event.StartX
            [int]$stopX = $event.StopX
        } else {
            $callXs = @($event.Calls | ForEach-Object { [int]$_.X })
            if ($RangeMode -eq 'ObservedCalls') {
                [int]$startX = ($callXs | Measure-Object -Minimum).Minimum
                [int]$stopX = ($callXs | Measure-Object -Maximum).Maximum
            } else {
                $projectedRange = $ProjectedRanges[[string]$event.SegmentIndex]
                if ($null -eq $projectedRange) { throw "No projected range for segment $($event.SegmentIndex)." }
                [int]$startX = $projectedRange[0]
                [int]$stopX = $projectedRange[1]
            }
        }

        [int]$overlapStart = [Math]::Max($startX, [int]$plane.MinX)
        [int]$overlapEnd = [Math]::Min($stopX, [int]$plane.MaxX)
        [bool]$overlapsOccupiedColumn = $false
        if ($overlapStart -le $overlapEnd) {
            for ([int]$x = $overlapStart; $x -le $overlapEnd; $x++) {
                if ($plane.Top[$x] -ne 255) { $overlapsOccupiedColumn = $true; break }
            }
        }

        if ($overlapsOccupiedColumn) {
            $plane = New-VisplaneRecord $nextVisplaneId $materialKey
            $nextVisplaneId++
            $plane.MinX = $startX
            $plane.MaxX = $stopX
            $visplanes.Add($plane)
        } else {
            $plane.MinX = [Math]::Min([int]$plane.MinX, $startX)
            $plane.MaxX = [Math]::Max([int]$plane.MaxX, $stopX)
        }

        foreach ($call in $event.Calls) {
            [int]$x = $call.X
            $plane.Top[$x] = [int]$call.Y1
            $plane.Bottom[$x] = [int]$call.Y2
        }
    }

    $spansAtSamples = [Collections.Generic.List[object]]::new()
    foreach ($sample in $Samples) {
        foreach ($plane in $visplanes) {
            if ($plane.MaterialKey -cne $sample.MaterialKey) { continue }
            [int]$sampleX = $sample.X
            [int]$sampleY = $sample.Y
            if ($plane.Top[$sampleX] -gt $sampleY -or $plane.Bottom[$sampleX] -lt $sampleY) { continue }
            [int]$spanStart = $sampleX
            while ($spanStart -gt 0 -and $plane.Top[$spanStart - 1] -le $sampleY -and
                $plane.Bottom[$spanStart - 1] -ge $sampleY) { $spanStart-- }
            $spansAtSamples.Add([pscustomobject]@{
                SampleId = $sample.Id
                X = $sampleX
                Y = $sampleY
                SurfaceType = $sample.SurfaceType
                MaterialKey = $plane.MaterialKey
                VisplaneId = $plane.Id
                PredictedSpanStartX = $spanStart
                CandidateObservedOriginX = $sample.CandidateObservedOriginX
                ReferenceObservedOriginX = $sample.ReferenceObservedOriginX
                CandidateReferencePlaneKeyMatches = $sample.CandidateReferencePlaneKeyMatches
                MinX = $plane.MinX
                MaxX = $plane.MaxX
            })
        }
    }

    return [pscustomobject]@{
        RangeMode = $RangeMode
        PlaneEvents = $events.Count
        VisplaneInstances = $visplanes.Count
        SamplesAtPoints = @($spansAtSamples)
    }
}

$content = $null
try {
    $null = [DoomInfo]::SwitchNames
    $content = [GameContent]::new(@('-iwad', $Wad))
    $options = [GameOptions]::new()
    $options.GameMode = $content.Wad.GameMode
    $options.GameVersion = $content.Wad.GameVersion
    $options.MissionPack = $content.Wad.MissionPack
    $game = [DoomGame]::new($content, $options)
    [TicCmd[]]$commands = [TicCmd[]]::new(4)
    for ([int]$i = 0; $i -lt $commands.Length; $i++) { $commands[$i] = [TicCmd]::new() }
    $game.DeferedInitNew([GameSkill]::Medium, 1, 1)
    $null = $game.Update($commands)
    for ([int]$tic = 2; $tic -le $trace.InputTic; $tic++) {
        $commands[0].Clear()
        $entry = $replayData.InputCommands[$tic - 2]
        $commands[0].ForwardMove = [sbyte][int]$entry[0]
        $commands[0].SideMove = [sbyte][int]$entry[1]
        $commands[0].AngleTurn = [int16][int]$entry[2]
        $commands[0].Buttons = [byte][int]$entry[3]
        $null = $game.Update($commands)
    }

    [int]$sectorIndex = $trace.SectorIndex
    $game.World.Map.Sectors[$sectorIndex].CeilingHeight = [Fixed]::FromInt([int]$heightRecord.CeilingHeight)
    $player = $game.World.ConsolePlayer.Mobj
    [int]$viewZData = $game.World.ConsolePlayer.ViewZ.Data
    $tables = Get-FastPlaneTables
    $calls = @($heightRecord.CandidatePlaneCallTrace) + @($heightRecord.ReferencePlaneCallTrace)
    $segmentIndexes = @($calls | ForEach-Object { [int]$_.SegmentIndex } | Sort-Object -Unique)
    $projectedRanges = @{}
    foreach ($segmentIndex in $segmentIndexes) {
        $segment = $game.World.Map.Segs[$segmentIndex]
        [int[]]$range = [int[]]::new(2)
        $hasRange = Get-FastWallScreenRange ([int]$player.X.Data) ([int]$player.Y.Data) `
            ([int]$segment.Vertex1.X.Data) ([int]$segment.Vertex1.Y.Data) `
            ([int]$segment.Vertex2.X.Data) ([int]$segment.Vertex2.Y.Data) `
            ([uint32]$player.Angle.Data) ([uint32]$tables.ColumnAngles[0]) `
            $tables.TanToAngle $tables.AngleToX $range
        if ($hasRange) {
            $projectedRanges[[string]$segmentIndex] = @([Math]::Max(0, $range[0]), [Math]::Min(319, $range[1] - 1))
        }
    }

    $targetSector = $game.World.Map.Sectors[18]
    $targetMaterialKey = "$($targetSector.FloorHeight.Data)|$($targetSector.FloorFlat)|$($targetSector.LightLevel)"
    $samples = [Collections.Generic.List[object]]::new()
    $seedSample = $sampleExample[0]
    $samples.Add([pscustomobject]@{
        Id = 'same-owner-floor'
        X = [int]$seedSample.X
        Y = [int]$seedSample.Y
        SurfaceType = 'Floor'
        MaterialKey = $targetMaterialKey
        CandidateObservedOriginX = [int]$seedSample.CandidateSampleOriginX
        ReferenceObservedOriginX = [int]$seedSample.ReferenceSampleOriginX
        CandidateReferencePlaneKeyMatches = $true
    })
    foreach ($example in $heightRecord.CandidatePlaneMismatchDifferentOwnerExamples) {
        $referenceMaterialKey = "$($example.ReferencePlaneHeightData)|$($example.ReferencePlaneFlatIndex)|$($example.ReferencePlaneLightLevel)"
        $candidateMaterialKey = "$($example.CandidatePlaneHeightData)|$($example.CandidatePlaneFlatIndex)|$($example.CandidatePlaneLightLevel)"
        $samples.Add([pscustomobject]@{
            Id = "different-owner-$($example.X)-$($example.Y)"
            X = [int]$example.X
            Y = [int]$example.Y
            SurfaceType = [string]$example.CandidatePlaneSurface
            MaterialKey = $referenceMaterialKey
            CandidateMaterialKey = $candidateMaterialKey
            CandidateObservedOriginX = [int]$example.CandidatePlaneSampleOriginX
            ReferenceObservedOriginX = [int]$example.ReferencePlaneSampleOriginX
            CandidateReferencePlaneKeyMatches = [bool]$example.CandidateReferencePlaneKeyMatches
        })
    }
    $results = [Collections.Generic.List[object]]::new()
    foreach ($renderer in $Renderers) {
        $rendererCalls = if ($renderer -eq 'candidate') { $heightRecord.CandidatePlaneCallTrace } else { $heightRecord.ReferencePlaneCallTrace }
        $rangeModes = @('ObservedCalls', 'Projected')
        if ($renderer -eq 'reference') { $rangeModes += 'DoomClipIntervals' }
        foreach ($rangeMode in $rangeModes) {
            $predictionCalls = if ($rangeMode -eq 'DoomClipIntervals') { $rangeReferenceCalls } else { $rendererCalls }
            $predictionRanges = if ($rangeMode -eq 'DoomClipIntervals') { $rangeEvents } else { @() }
            $prediction = Get-VisplaneSpanPrediction @($predictionCalls) $game.World.Map $projectedRanges $content.Flats.SkyFlatNumber $rangeMode @($samples) @($predictionRanges) $viewZData
            $candidateOriginMatches = @($prediction.SamplesAtPoints | Where-Object {
                $_.PredictedSpanStartX -eq $_.CandidateObservedOriginX
            }).Count
            $referenceOriginMatches = @($prediction.SamplesAtPoints | Where-Object {
                $_.PredictedSpanStartX -eq $_.ReferenceObservedOriginX
            }).Count
            $referenceOriginDeltas = @($prediction.SamplesAtPoints | ForEach-Object {
                [Math]::Abs($_.PredictedSpanStartX - $_.ReferenceObservedOriginX)
            })
            $matchedSampleIds = @($prediction.SamplesAtPoints | ForEach-Object SampleId | Sort-Object -Unique)
            $unmatchedSampleCount = @($samples | Where-Object { $_.Id -notin $matchedSampleIds }).Count
            $meanReferenceOriginDelta = if ($referenceOriginDeltas.Count -eq 0) {
                $null
            } else {
                [Math]::Round(($referenceOriginDeltas | Measure-Object -Average).Average, 2)
            }
            $results.Add([pscustomobject]@{
                Renderer = $renderer
                RangeMode = $rangeMode
                PlaneEvents = $prediction.PlaneEvents
                VisplaneInstances = $prediction.VisplaneInstances
                SampleCount = $samples.Count
                UnmatchedSampleCount = $unmatchedSampleCount
                CandidateObservedOriginMatches = $candidateOriginMatches
                ReferenceObservedOriginMatches = $referenceOriginMatches
                MeanAbsoluteReferenceOriginDelta = $meanReferenceOriginDelta
                SamplesAtPoints = $prediction.SamplesAtPoints
            })
        }
    }

    $report = [ordered]@{
        SchemaVersion = 3
        FinishedUtc = [DateTime]::UtcNow.ToString('o')
        Experiment = 'Reconstruct first-match Doom R_FindPlane lookup, overlap-splitting R_CheckPlane ranges, and horizontal span starts for recorded mismatch samples.'
        InputTic = [int]$trace.InputTic
        SectorIndex = $sectorIndex
        CeilingHeight = [int]$heightRecord.CeilingHeight
        SampleCount = $samples.Count
        Samples = @($samples)
        Camera = [ordered]@{
            X = [Math]::Round($player.X.Data / 65536.0, 5)
            Y = [Math]::Round($player.Y.Data / 65536.0, 5)
            Z = [Math]::Round($player.Z.Data / 65536.0, 5)
            AngleData = [uint32]$player.Angle.Data
        }
        SameOwnerFloorMaterialKey = $targetMaterialKey
        ReferenceClipRangeCount = $rangeEvents.Count
        ReferencePlaneCallCount = $rangeReferenceCalls.Count
        RangeTracePath = [IO.Path]::GetRelativePath($root, $RangeTraceReceipt).Replace('\', '/')
        RangeTraceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $RangeTraceReceipt).Hash
        RFindPlaneLookupRule = 'Search visplanes from first to last and reuse the first matching height/flat/light key; do not cache the selected plane by subsector.'
        SameOwnerFloorSegments = @(
            foreach ($segmentIndex in 137, 141) {
                $segment = $game.World.Map.Segs[$segmentIndex]
                [ordered]@{
                    SegmentIndex = $segmentIndex
                    FrontSector = [int]$segment.FrontSector.Number
                    BackSector = if ($null -eq $segment.BackSector) { -1 } else { [int]$segment.BackSector.Number }
                    ProjectedRange = $projectedRanges[[string]$segmentIndex]
                }
            }
        )
        RangeModels = @($results)
        MethodLimit = 'ObservedCalls and Projected remain approximate models. DoomClipIntervals applies the original R_FindPlane/R_CheckPlane ordering and mark-floor/ceiling rules to exact clipped ranges captured from the adapted renderer; adapted geometry and clipping can differ from the original executable, so this does not prove original-executable parity.'
        ReferenceSource = @(
            'https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_plane.c',
            'https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_segs.c'
        )
        ReplayPath = [IO.Path]::GetRelativePath($root, $Replay).Replace('\', '/')
        ReplaySha256 = $replaySha256
        TracePath = [IO.Path]::GetRelativePath($root, $TraceReceipt).Replace('\', '/')
        TraceSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $TraceReceipt).Hash
        WadSha256 = $wadSha256
        EngineBundleSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $EngineBundle).Hash
        AnalysisScriptSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath).Hash
        ProductionRendererChanged = $false
        LiveTestsRun = $false
        DeviceInteraction = $false
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output -Encoding utf8
    [pscustomobject]@{
        Output = [IO.Path]::GetRelativePath($root, $Output).Replace('\', '/')
        SampleCount = $samples.Count
        RangeModels = @($results | Select-Object Renderer, RangeMode, PlaneEvents, VisplaneInstances,
            SampleCount, UnmatchedSampleCount, CandidateObservedOriginMatches,
            ReferenceObservedOriginMatches, MeanAbsoluteReferenceOriginDelta)
        LiveTestsRun = $false
        DeviceInteraction = $false
    } | ConvertTo-Json -Depth 6
} finally {
    if ($null -ne $content) { $content.Dispose() }
}
