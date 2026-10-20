#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [string]$Wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay = "$PSScriptRoot/../results/e1m1-route-lineflags.json",
    [string]$TraceReceipt = "$PSScriptRoot/../results/moving-sector-reference-plane-full-call-trace-20261020.json",
    [string]$EngineBundle = "$PSScriptRoot/../local/engine-bundle.ps1",
    [string]$Output = "$PSScriptRoot/../results/moving-sector-visplane-span-origin-20261020.json",
    [ValidateSet('candidate', 'reference')][string[]]$Renderers = @('candidate', 'reference')
)

$ErrorActionPreference = 'Stop'
$TargetX = 226
$TargetY = 105
$root = Split-Path $PSScriptRoot
foreach ($pathName in 'Wad', 'Replay', 'TraceReceipt', 'EngineBundle', 'Output') {
    Set-Variable -Name $pathName -Value ([IO.Path]::GetFullPath((Get-Variable -Name $pathName -ValueOnly)))
}
foreach ($path in $Wad, $Replay, $TraceReceipt, $EngineBundle) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required input not found: $path" }
}
$outputRelative = [IO.Path]::GetRelativePath($root, $Output)
if ([IO.Path]::IsPathRooted($outputRelative) -or $outputRelative -eq '..' -or
    $outputRelative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")) {
    throw 'Analysis output must remain inside the project.'
}
if (Test-Path -LiteralPath $Output) { throw 'Use a fresh analysis output path.' }

$trace = Get-Content -LiteralPath $TraceReceipt -Raw | ConvertFrom-Json
$replayData = Get-Content -LiteralPath $Replay -Raw | ConvertFrom-Json
$wadSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Wad).Hash
$replaySha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Replay).Hash
if ($trace.WadSha256 -cne $wadSha256 -or $trace.ReplaySha256 -cne $replaySha256) {
    throw 'The trace receipt, replay and IWAD hashes do not match.'
}
$heightRecord = $trace.Heights | Where-Object CeilingHeight -eq 68 | Select-Object -First 1
if ($null -eq $heightRecord) { throw 'The trace receipt has no ceiling-height-68 sample.' }
$sampleExample = @($heightRecord.SameOwnerPlaneSampleExamples | Where-Object {
    $_.X -eq $TargetX -and $_.Y -eq $TargetY
})
if ($sampleExample.Count -ne 1) { throw 'The selected coordinate must identify one recorded same-owner plane sample.' }
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
        [int]$SampleX,
        [int]$SampleY
    )

    $segmentToSubsector = @{}
    for ([int]$subsectorIndex = 0; $subsectorIndex -lt $Map.Subsectors.Length; $subsectorIndex++) {
        $subsector = $Map.Subsectors[$subsectorIndex]
        for ([int]$segIndex = $subsector.FirstSeg; $segIndex -lt ($subsector.FirstSeg + $subsector.SegCount); $segIndex++) {
            $segmentToSubsector[[string]$segIndex] = $subsectorIndex
        }
    }

    $callsBySegmentSurface = @{}
    foreach ($call in $Calls) {
        if ($call.SurfaceType -ne 'Floor') { continue }
        $bucketKey = "$($call.SegmentIndex)|$($call.SurfaceType)"
        if (-not $callsBySegmentSurface.ContainsKey($bucketKey)) {
            $callsBySegmentSurface[$bucketKey] = [Collections.Generic.List[object]]::new()
        }
        $callsBySegmentSurface[$bucketKey].Add($call)
    }

    $events = [Collections.Generic.List[object]]::new()
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
    $events = @($events | Sort-Object FirstOrdinal)

    $visplanes = [Collections.Generic.List[object]]::new()
    $subsectorPlanes = @{}
    [int]$nextVisplaneId = 0
    foreach ($event in $events) {
        $sector = $Map.Sectors[$event.SectorIndex]
        [int]$heightData = $sector.FloorHeight.Data
        [int]$flatIndex = $sector.FloorFlat
        [int]$lightLevel = $sector.LightLevel
        if ($flatIndex -eq $SkyFlatNumber) {
            $heightData = 0
            $lightLevel = 0
        }
        $materialKey = "$heightData|$flatIndex|$lightLevel"
        $subsectorId = $segmentToSubsector[[string]$event.SegmentIndex]
        if ($null -eq $subsectorId) { throw "Segment $($event.SegmentIndex) has no subsector." }
        $subsectorKey = "$subsectorId|Floor"

        if ($subsectorPlanes.ContainsKey($subsectorKey)) {
            $plane = $subsectorPlanes[$subsectorKey]
        } else {
            $plane = $null
            foreach ($knownPlane in $visplanes) {
                if ($knownPlane.MaterialKey -ceq $materialKey) { $plane = $knownPlane; break }
            }
            if ($null -eq $plane) {
                $plane = New-VisplaneRecord $nextVisplaneId $materialKey
                $nextVisplaneId++
                $visplanes.Add($plane)
            }
            $subsectorPlanes[$subsectorKey] = $plane
        }

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
            $subsectorPlanes[$subsectorKey] = $plane
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

    $spansAtSample = [Collections.Generic.List[object]]::new()
    foreach ($plane in $visplanes) {
        if ($plane.Top[$SampleX] -gt $SampleY -or $plane.Bottom[$SampleX] -lt $SampleY) { continue }
        [int]$spanStart = $SampleX
        while ($spanStart -gt 0 -and $plane.Top[$spanStart - 1] -le $SampleY -and
            $plane.Bottom[$spanStart - 1] -ge $SampleY) { $spanStart-- }
        $spansAtSample.Add([pscustomobject]@{
            VisplaneId = $plane.Id
            MaterialKey = $plane.MaterialKey
            SpanStartX = $spanStart
            SampleX = $SampleX
            MinX = $plane.MinX
            MaxX = $plane.MaxX
        })
    }

    return [pscustomobject]@{
        RangeMode = $RangeMode
        FloorEvents = $events.Count
        VisplaneInstances = $visplanes.Count
        SpansAtSample = @($spansAtSample)
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
    $results = [Collections.Generic.List[object]]::new()
    foreach ($renderer in $Renderers) {
        $rendererCalls = if ($renderer -eq 'candidate') { $heightRecord.CandidatePlaneCallTrace } else { $heightRecord.ReferencePlaneCallTrace }
        foreach ($rangeMode in 'ObservedCalls', 'Projected') {
            $prediction = Get-VisplaneSpanPrediction @($rendererCalls) $game.World.Map $projectedRanges `
                $content.Flats.SkyFlatNumber $rangeMode $TargetX $TargetY
            $results.Add([pscustomobject]@{
                Renderer = $renderer
                RangeMode = $rangeMode
                FloorEvents = $prediction.FloorEvents
                VisplaneInstances = $prediction.VisplaneInstances
                TargetMaterialKey = $targetMaterialKey
                SpansAtSample = $prediction.SpansAtSample
            })
        }
    }

    $report = [ordered]@{
        SchemaVersion = 1
        FinishedUtc = [DateTime]::UtcNow.ToString('o')
        Experiment = 'Approximate original visplane grouping and horizontal span starts from the saved full-call trace.'
        InputTic = [int]$trace.InputTic
        SectorIndex = $sectorIndex
        CeilingHeight = [int]$heightRecord.CeilingHeight
        Sample = [ordered]@{
            X = $TargetX
            Y = $TargetY
            CandidateOriginX = [int]$sampleExample[0].CandidateSampleOriginX
            AdaptedReferenceOriginX = [int]$sampleExample[0].ReferenceSampleOriginX
        }
        Camera = [ordered]@{
            X = [Math]::Round($player.X.Data / 65536.0, 5)
            Y = [Math]::Round($player.Y.Data / 65536.0, 5)
            Z = [Math]::Round($player.Z.Data / 65536.0, 5)
            AngleData = [uint32]$player.Angle.Data
        }
        TargetFloorMaterialKey = $targetMaterialKey
        TargetSegments = @(
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
        MethodLimit = 'Projected mode uses angular segment bounds without solid-wall clipping; ObservedCalls mode uses the minimum and maximum recorded nonempty plane-call columns. Neither reconstructs exact post-clip R_CheckPlane intervals or proves original-executable parity.'
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
        TargetMaterialKey = $targetMaterialKey
        RangeModels = @($results)
        LiveTestsRun = $false
        DeviceInteraction = $false
    } | ConvertTo-Json -Depth 6
} finally {
    if ($null -ne $content) { $content.Dispose() }
}
