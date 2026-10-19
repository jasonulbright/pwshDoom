#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay = "$PSScriptRoot/../results/e1m1-route-lineflags.json",
    [Parameter(Mandatory)][string]$Output,
    [string]$Images,
    [string]$Renderer = "$PSScriptRoot/../src/FastRenderer.ps1",
    [string]$EngineSourceRoot = "$PSScriptRoot/../src/ManagedDoom",
    [string]$EngineBundleOutput = "$PSScriptRoot/../local/engine-bundle.ps1",
    [switch]$CaptureReferencePlaneOwners,
    [ValidateRange(2,100000)][int]$InputTic = 315,
    [ValidateRange(0,32767)][int]$SectorIndex = 26,
    [ValidateRange(-4096,4096)][int[]]$Heights = @(0, 6, 34, 68)
)

function Get-FastPlaneSample {
    param(
        [hashtable]$Context,
        [int]$X,
        [int]$Y,
        [int]$PlaneId,
        [int]$ViewXData,
        [int]$ViewYData,
        [int]$ViewZData,
        [uint32]$ViewAngleData,
        [int]$ExtraLight,
        [int]$FixedColorMap
    )

    [int]$sectorIndex = ($PlaneId - 1) -shr 1
    if (($PlaneId - 1) -band 1) {
        [int]$heightData = $Context.SectorFloorHeightData[$sectorIndex]
        [int]$flatIndex = $Context.SectorFloorFlatIndex[$sectorIndex]
    } else {
        [int]$heightData = $Context.SectorCeilingHeightData[$sectorIndex]
        [int]$flatIndex = $Context.SectorCeilingFlatIndex[$sectorIndex]
    }
    [long]$heightDelta = [long]$heightData - [long]$ViewZData
    if ($heightDelta -lt 0) { $heightDelta = -$heightDelta }
    [long]$distanceWide = ([long]$heightDelta * [long]$Context.PlaneRowSlopes[$Y]) -shr 16
    $distanceWide = $distanceWide -band 0xFFFFFFFFL
    if ($distanceWide -ge 0x80000000L) { $distanceWide -= 0x100000000L }
    [int]$distanceData = $distanceWide

    [uint32]$planeBaseAngleData = ([long]$ViewAngleData - 0x40000000L) -band 0xFFFFFFFFL
    [int]$planeBaseFine = $planeBaseAngleData -shr 19
    [int[]]$fineSine = $Context.PlaneFineSine
    [int]$planeBaseX = [Math]::Truncate($fineSine[$planeBaseFine + 2048] / 160.0)
    [int]$planeBaseY = -[Math]::Truncate($fineSine[$planeBaseFine] / 160.0)
    [int]$stepX = ([long]$distanceData * [long]$planeBaseX) -shr 16
    [int]$stepY = ([long]$distanceData * [long]$planeBaseY) -shr 16

    [int]$row = $Y * 320
    [int]$samplePosition = $row + $X
    [int]$startX = $X
    [long]$xFracWide = 0
    [long]$yFracWide = 0
    [bool]$hasCapturedSample = $Context.ContainsKey('PlaneSampleXFracData') -and
        $Context.ContainsKey('PlaneSampleYFracData') -and $Context.ContainsKey('PlaneSampleOriginX') -and
        $Context.ContainsKey('PlaneSampleReusedPreviousColumn')
    if ($hasCapturedSample) {
        $startX = [int]$Context.PlaneSampleOriginX[$samplePosition]
        if ($startX -lt 0 -or $startX -gt $X) { throw "Invalid candidate plane sample origin $startX at ($X,$Y)." }
        $xFracWide = [long][int]$Context.PlaneSampleXFracData[$samplePosition]
        $yFracWide = [long][int]$Context.PlaneSampleYFracData[$samplePosition]
    } else {
        if ($Context.ContainsKey('PlaneSampleOriginX')) {
            $startX = [int]$Context.PlaneSampleOriginX[$samplePosition]
            if ($startX -lt 0 -or $startX -gt $X) { throw "Invalid candidate plane sample origin $startX at ($X,$Y)." }
        } else {
            [int]$spanStart = 0
            if ($Context.ContainsKey('PlaneSpanBoundaries')) {
                foreach ($boundary in $Context.PlaneSpanBoundaries) {
                    if ($boundary -gt $X) { break }
                    $spanStart = [int]$boundary
                }
            }
            while ($startX -gt $spanStart -and $Context.Planes[$row + $startX - 1] -eq $PlaneId) { $startX-- }
        }
        [int]$lengthData = ([long]$distanceData * [long]$Context.PlaneDistanceScales[$startX]) -shr 16
        $xFracWide = [long]$ViewXData + (([long]$Context.RayCos[$startX] * [long]$lengthData) -shr 16)
        $yFracWide = -[long]$ViewYData - (([long]$Context.RaySin[$startX] * [long]$lengthData) -shr 16)
        $xFracWide += [long]$stepX * ($X - $startX)
        $yFracWide += [long]$stepY * ($X - $startX)
    }
    [int]$textureX = ($xFracWide -shr 16) -band 63
    [int]$textureY = ($yFracWide -shr 10) -band 4032
    [int]$spot = $textureY + $textureX
    [int]$flatTexelIndex = $Context.PlaneFlatData[$flatIndex][$spot]
    [int]$lightRow = [Math]::Clamp(($Context.SectorLightLevels[$sectorIndex] -shr 4) + $ExtraLight, 0, $Context.Lighting.Distance.Length - 1)
    [int]$distanceLightBin = [Math]::Clamp(($distanceData -shr 20), 0, $Context.Lighting.Distance[$lightRow].Length - 1)
    [int]$lightMapIndex = $Context.Lighting.Distance[$lightRow][$distanceLightBin]
    if ($FixedColorMap -gt 0) { $lightMapIndex = $FixedColorMap }
    [byte]$color = $Context.Colors[$lightMapIndex][$flatTexelIndex]
    [int]$directLengthData = ([long]$distanceData * [long]$Context.PlaneDistanceScales[$X]) -shr 16
    [long]$directXFracWide = [long]$ViewXData + (([long]$Context.RayCos[$X] * [long]$directLengthData) -shr 16)
    [long]$directYFracWide = -[long]$ViewYData - (([long]$Context.RaySin[$X] * [long]$directLengthData) -shr 16)
    [int]$directTextureX = ($directXFracWide -shr 16) -band 63
    [int]$directTextureY = ((($directYFracWide -shr 10) -band 4032) -shr 6)
    [int]$directSpot = ($directTextureY -shl 6) + $directTextureX
    [int]$directFlatTexelIndex = $Context.PlaneFlatData[$flatIndex][$directSpot]
    [byte]$directColor = $Context.Colors[$lightMapIndex][$directFlatTexelIndex]

    return [ordered]@{
        SectorIndex = $sectorIndex
        SurfaceType = if (($PlaneId - 1) -band 1) { 1 } else { 2 }
        FlatIndex = $flatIndex
        DistanceData = $distanceData
        StepX = $stepX
        StepY = $stepY
        DistanceLightBin = $distanceLightBin
        XFracData = [int]($xFracWide -band 0xFFFFFFFFL)
        YFracData = [int]($yFracWide -band 0xFFFFFFFFL)
        TextureX = $textureX
        TextureY = $textureY -shr 6
        SampleOriginX = $startX
        ReusedPreviousColumn = $hasCapturedSample -and $Context.PlaneSampleReusedPreviousColumn[$samplePosition] -eq 1
        FlatTexelIndex = $flatTexelIndex
        LightRow = $lightRow
        LightMapIndex = $lightMapIndex
        Color = $color
        DirectXFracData = [int]($directXFracWide -band 0xFFFFFFFFL)
        DirectYFracData = [int]($directYFracWide -band 0xFFFFFFFFL)
        DirectTextureX = $directTextureX
        DirectTextureY = $directTextureY
        DirectFlatTexelIndex = $directFlatTexelIndex
        DirectColor = $directColor
    }
}

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$Wad = [IO.Path]::GetFullPath($Wad)
$Replay = [IO.Path]::GetFullPath($Replay)
$Output = [IO.Path]::GetFullPath($Output)
$EngineSourceRoot = [IO.Path]::GetFullPath($EngineSourceRoot)
$EngineBundleOutput = [IO.Path]::GetFullPath($EngineBundleOutput)
$engineRelative = [IO.Path]::GetRelativePath($root, $EngineSourceRoot)
$bundleRelative = [IO.Path]::GetRelativePath($root, $EngineBundleOutput)
if ([IO.Path]::IsPathRooted($engineRelative) -or $engineRelative -eq '..' -or $engineRelative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)") -or
    [IO.Path]::IsPathRooted($bundleRelative) -or $bundleRelative -eq '..' -or $bundleRelative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")) {
    throw 'Engine source and bundle output must remain inside the project.'
}
$referenceRendererSource = Join-Path $EngineSourceRoot 'Video/ThreeDRenderer.sb.ps1'
if (-not (Test-Path -LiteralPath $referenceRendererSource -PathType Leaf)) { throw "Reference renderer source not found: $referenceRendererSource" }
if (-not (Test-Path -LiteralPath $Wad -PathType Leaf)) { throw "IWAD not found: $Wad" }
if (-not (Test-Path -LiteralPath $Replay -PathType Leaf)) { throw "Replay not found: $Replay" }
if (Test-Path -LiteralPath $Output) { throw 'Use a fresh output path.' }
if ($Heights.Count -lt 2 -or @($Heights | Sort-Object -Unique).Count -ne $Heights.Count) {
    throw 'Specify at least two distinct ceiling heights.'
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Output))
if ($Images) {
    $Images = [IO.Path]::GetFullPath($Images)
    if (Test-Path -LiteralPath $Images) { throw 'Use a fresh image directory.' }
    [void][IO.Directory]::CreateDirectory($Images)
    Add-Type -AssemblyName System.Drawing
}

$replayData = Get-Content -LiteralPath $Replay -Raw | ConvertFrom-Json
if ($replayData.PSObject.Properties.Name -notcontains 'InputCommands' -or
    $replayData.InputCommands.Count -lt $InputTic -or
    ($replayData.PSObject.Properties.Name -contains 'WadSha256' -and
        $replayData.WadSha256 -cne (Get-FileHash -LiteralPath $Wad).Hash)) {
    throw 'Replay must contain the requested commands and match the selected IWAD.'
}

$bundle = & "$PSScriptRoot/Build-EngineBundle.ps1" -SourceRoot $EngineSourceRoot -Output $EngineBundleOutput
. $bundle
. $Renderer
. "$PSScriptRoot/../src/GameHost.ps1"
$sourcePaths = @(
    [IO.Path]::GetRelativePath($root, [IO.Path]::GetFullPath($Renderer)).Replace('\', '/'),
    'src/GameHost.ps1',
    [IO.Path]::GetRelativePath($root, $referenceRendererSource).Replace('\', '/'),
    'src/ManagedDoom/Video/ThreeDRenderer.sb.ps1',
    'scripts/Compare-MovingSectorHeightSweep.ps1'
)
$sourceHashes = @{}
foreach ($path in $sourcePaths) {
    $sourceHashes[$path] = (Get-FileHash -LiteralPath (Join-Path $root $path)).Hash
}

$content = $null
$frames = @{}
$heightResults = [Collections.Generic.List[object]]::new()
try {
    $null = [DoomInfo]::SwitchNames
    $content = [GameContent]::new(@('-iwad', $Wad))
    $options = [GameOptions]::new()
    $options.GameMode = $content.Wad.GameMode
    $options.GameVersion = $content.Wad.GameVersion
    $options.MissionPack = $content.Wad.MissionPack
    $game = [DoomGame]::new($content, $options)
    $commands = [TicCmd[]]::new(4)
    for ($i = 0; $i -lt $commands.Length; $i++) { $commands[$i] = [TicCmd]::new() }
    $game.DeferedInitNew([GameSkill]::Medium, 1, 1)
    $null = $game.Update($commands)
    for ($tic = 2; $tic -le $InputTic; $tic++) {
        $commands[0].Clear()
        $entry = $replayData.InputCommands[$tic - 2]
        $commands[0].ForwardMove = [sbyte][int]$entry[0]
        $commands[0].SideMove = [sbyte][int]$entry[1]
        $commands[0].AngleTurn = [int16][int]$entry[2]
        $commands[0].Buttons = [byte][int]$entry[3]
        $null = $game.Update($commands)
    }

    if ($SectorIndex -ge $game.World.Map.Sectors.Length) { throw "Sector index $SectorIndex is outside the loaded map." }
    $sector = $game.World.Map.Sectors[$SectorIndex]
    $actualHeight = $sector.CeilingHeight.Data / 65536.0
    $config = [Config]::new()
    $config.video_highresolution = $false
    $config.video_gamescreensize = 7
    $config.video_gammacorrection = 0
    $reference = [Renderer]::new($config, $content)
    $reference3D = $reference.ThreeD
    $hasReferencePlaneOwnerFields = $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneOwners') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneSurfaceTypes') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalWriterTypes') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneDistanceData') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneXFracData') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneYFracData') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneLightIndices') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneTexelIndices') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneLightMaps') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneSampleOriginX') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticPlaneSampleReusedPreviousColumn') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticCeilingSampleOriginX') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFloorSampleOriginX')
    if ($CaptureReferencePlaneOwners -and -not $hasReferencePlaneOwnerFields) {
        throw 'The selected engine source does not contain reference plane-owner diagnostics.'
    }
    if ($hasReferencePlaneOwnerFields) {
        $CaptureReferencePlaneOwners = $true
        $reference3D.DiagnosticPlaneOwners = [Sector[]]::new(320 * 200)
        $reference3D.DiagnosticPlaneSurfaceTypes = [byte[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWriterTypes = [byte[]]::new(320 * 200)
        $reference3D.DiagnosticPlaneDistanceData = [int[]]::new(320 * 200)
        $reference3D.DiagnosticPlaneXFracData = [int[]]::new(320 * 200)
        $reference3D.DiagnosticPlaneYFracData = [int[]]::new(320 * 200)
        $reference3D.DiagnosticPlaneLightIndices = [int[]]::new(320 * 200)
        $reference3D.DiagnosticPlaneTexelIndices = [int[]]::new(320 * 200)
        $reference3D.DiagnosticPlaneLightMaps = [byte[][]]::new(320 * 200)
        $reference3D.DiagnosticPlaneSampleOriginX = [int[]]::new(320 * 200)
        $reference3D.DiagnosticPlaneSampleReusedPreviousColumn = [byte[]]::new(320 * 200)
        $reference3D.DiagnosticCeilingSampleOriginX = [int[]]::new(200)
        $reference3D.DiagnosticFloorSampleOriginX = [int[]]::new(200)
    }
        $context = New-FastRenderContext $content $game.World
    $context.PlaneSampleXFracData = [int[]]::new(320 * 168)
    $context.PlaneSampleYFracData = [int[]]::new(320 * 168)
    $context.PlaneSampleOriginX = [int[]]::new(320 * 168)
    $context.PlaneSampleReusedPreviousColumn = [byte[]]::new(320 * 168)
    $context.PlaneCeilingSampleOriginX = [int[]]::new(168)
    $context.PlaneFloorSampleOriginX = [int[]]::new(168)
    [Array]::Fill($context.PlaneSampleOriginX, -1)
    [Array]::Fill($context.PlaneCeilingSampleOriginX, -1)
    [Array]::Fill($context.PlaneFloorSampleOriginX, -1)
    $baseSnapshot = New-GameRenderSnapshot $game 1

    foreach ($height in $Heights) {
        $sector.CeilingHeight = [Fixed]::FromInt($height)
        $sector.OldCeilingHeight = [Fixed]::FromInt($height)
        $snapshot = $baseSnapshot.Clone()
        $snapshotSectors = [object[]]::new($baseSnapshot.Sectors.Length)
        for ($i = 0; $i -lt $snapshotSectors.Length; $i++) {
            $snapshotSectors[$i] = $baseSnapshot.Sectors[$i].Clone()
        }
        $snapshotSectors[$SectorIndex].CeilingHeight = [double]$height
        $snapshot.Sectors = $snapshotSectors

        Set-GameRenderSnapshot $context $snapshot
        $candidateCamera = $snapshot.ConsolePlayer.Mobj
        [int]$candidateViewXData = [Math]::Truncate(65536.0 * $candidateCamera.X)
        [int]$candidateViewYData = [Math]::Truncate(65536.0 * $candidateCamera.Y)
        [int]$candidateViewZData = [Math]::Truncate(65536.0 * $snapshot.ConsolePlayer.ViewZ)
        [uint32]$candidateViewAngleData = [uint32]([long][Math]::Round(4294967296.0 * ($candidateCamera.Angle / (2 * [Math]::PI))) -band 0xFFFFFFFFL)
        [int]$candidateExtraLight = $snapshot.ConsolePlayer.ExtraLight
        [int]$candidateFixedColorMap = $snapshot.ConsolePlayer.FixedColorMap
        [Array]::Clear($context.PlaneSampleXFracData)
        [Array]::Clear($context.PlaneSampleYFracData)
        [Array]::Fill($context.PlaneSampleOriginX, -1)
        [Array]::Clear($context.PlaneSampleReusedPreviousColumn)
        [Array]::Fill($context.PlaneCeilingSampleOriginX, -1)
        [Array]::Fill($context.PlaneFloorSampleOriginX, -1)
        Invoke-FastRender $context
        [byte[]]$candidate = $context.Pixels.Clone()
        if ($CaptureReferencePlaneOwners) {
            [Array]::Clear($reference3D.DiagnosticPlaneOwners, 0, $reference3D.DiagnosticPlaneOwners.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneSurfaceTypes, 0, $reference3D.DiagnosticPlaneSurfaceTypes.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWriterTypes, 0, $reference3D.DiagnosticFinalWriterTypes.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneDistanceData, 0, $reference3D.DiagnosticPlaneDistanceData.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneXFracData, 0, $reference3D.DiagnosticPlaneXFracData.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneYFracData, 0, $reference3D.DiagnosticPlaneYFracData.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneLightIndices, 0, $reference3D.DiagnosticPlaneLightIndices.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneTexelIndices, 0, $reference3D.DiagnosticPlaneTexelIndices.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneLightMaps, 0, $reference3D.DiagnosticPlaneLightMaps.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneSampleOriginX, 0, $reference3D.DiagnosticPlaneSampleOriginX.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneSampleReusedPreviousColumn, 0, $reference3D.DiagnosticPlaneSampleReusedPreviousColumn.Length)
            [Array]::Clear($reference3D.DiagnosticCeilingSampleOriginX, 0, $reference3D.DiagnosticCeilingSampleOriginX.Length)
            [Array]::Clear($reference3D.DiagnosticFloorSampleOriginX, 0, $reference3D.DiagnosticFloorSampleOriginX.Length)
        }
        $reference.RenderGame($game, [Fixed]::One)
        [byte[]]$referencePixels = $reference.Screen.Data.Clone()

        $sceneDifferences = 0
        $hudDifferences = 0
        $candidatePlaneMismatchPixels = 0
        $candidatePlaneNoDepthMismatchPixels = 0
        $candidateNonPlaneMismatchPixels = 0
        $candidateDepthWrittenMismatchPixels = 0
        $candidatePlaneMismatchCounts = @{}
        $referencePlaneWriteMismatchPixels = 0
        $candidatePlaneMismatchReferencePlaneWrites = 0
        $candidatePlaneMismatchSameOwnerWrites = 0
        $candidatePlaneMismatchDifferentOwnerWrites = 0
        $candidatePlaneMismatchNoReferencePlaneWrite = 0
        $candidatePlaneMismatchUnknownReferenceOwner = 0
        $candidateNonPlaneMismatchReferencePlaneWrites = 0
        $candidatePlaneMismatchReferenceFinalPlaneWrites = 0
        $candidatePlaneMismatchReferenceFinalColumnWrites = 0
        $candidatePlaneMismatchReferenceFinalFuzzWrites = 0
        $candidatePlaneMismatchReferenceFinalUnmarkedWrites = 0
        $candidatePlaneMismatchSameOwnerFinalPlaneWrites = 0
        $referencePlaneOwnerPairCounts = @{}
        $planeSampleCounts = [ordered]@{
            SameOwnerSamples = 0
            SameDistanceData = 0
            SameDistanceLightBin = 0
            SameXFraction = 0
            SameYFraction = 0
            SameTextureX = 0
            SameTextureY = 0
            SameTextureCoordinates = 0
            SameFlatTexelIndex = 0
            SameLightMapIndex = 0
            SamePlaneColor = 0
            ReferenceOriginAlignedSameXFraction = 0
            ReferenceOriginAlignedSameYFraction = 0
            ReferenceOriginAlignedSameTextureCoordinates = 0
            ReferenceOriginAlignedSameFlatTexelIndex = 0
            ReferenceOriginAlignedSamePlaneColor = 0
            DirectSameXFraction = 0
            DirectSameYFraction = 0
            DirectSameTextureX = 0
            DirectSameTextureY = 0
            DirectSameFlatTexelIndex = 0
            DirectSamePlaneColor = 0
            CandidateFramebufferMatchesPlaneSample = 0
            ReferenceFramebufferMatchesPlaneSample = 0
            TextureXDeltaCounts = @{}
            TextureYDeltaCounts = @{}
            CandidateSampleAgeCounts = @{}
            CandidateSampleReusedPreviousColumn = 0
            CandidateSampleInitializedAtCurrentColumn = 0
            ReferenceSampleReusedPreviousColumn = 0
            ReferenceSampleInitializedAtCurrentColumn = 0
            CandidateSampleOriginBeforeReferenceOrigin = 0
            CandidateSampleOriginDeltaCounts = @{}
            DirectTexelMatchesWithReferenceReuse = 0
            DirectTexelMatchesAfterReferenceInitialize = 0
        }
        $planeSampleExamples = [Collections.Generic.List[object]]::new()
        $bounds = [int[]]@(320, 168, -1, -1)
        for ($y = 0; $y -lt 200; $y++) {
            for ($x = 0; $x -lt 320; $x++) {
                $candidateIndex = $y * 320 + $x
                if ($candidate[$candidateIndex] -eq $referencePixels[$x * 200 + $y]) { continue }
                if ($y -lt 168) {
                    $sceneDifferences++
                    [int]$planeId = $context.Planes[$candidateIndex]
                    if ($CaptureReferencePlaneOwners) {
                        $referencePosition = $x * 200 + $y
                        $referenceOwner = $reference3D.DiagnosticPlaneOwners[$referencePosition]
                        if ($planeId -gt 0) {
                            switch ([int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition]) {
                                1 { $candidatePlaneMismatchReferenceFinalPlaneWrites++ }
                                2 { $candidatePlaneMismatchReferenceFinalColumnWrites++ }
                                3 { $candidatePlaneMismatchReferenceFinalFuzzWrites++ }
                                default { $candidatePlaneMismatchReferenceFinalUnmarkedWrites++ }
                            }
                        }
                        if ($null -eq $referenceOwner) {
                            if ($planeId -gt 0) { $candidatePlaneMismatchNoReferencePlaneWrite++ }
                        } else {
                            $referencePlaneWriteMismatchPixels++
                            if ($planeId -gt 0) {
                                $referenceOwnerSectorIndex = -1
                                for ($referenceSectorIndex = 0; $referenceSectorIndex -lt $game.World.Map.Sectors.Length; $referenceSectorIndex++) {
                                    if ([object]::ReferenceEquals($referenceOwner, $game.World.Map.Sectors[$referenceSectorIndex])) {
                                        $referenceOwnerSectorIndex = $referenceSectorIndex
                                        break
                                    }
                                }
                                if ($referenceOwnerSectorIndex -lt 0) {
                                    $candidatePlaneMismatchUnknownReferenceOwner++
                                } else {
                                    $candidatePlaneMismatchReferencePlaneWrites++
                                    $candidateSectorIndex = ($planeId - 1) -shr 1
                                    $candidateSurfaceType = if ((($planeId - 1) -band 1) -ne 0) { 1 } else { 2 }
                                    $referenceSurfaceType = [int]$reference3D.DiagnosticPlaneSurfaceTypes[$referencePosition]
                                    $candidateSurfaceName = if ($candidateSurfaceType -eq 1) { 'Floor' } else { 'Ceiling' }
                                    $referenceSurfaceName = if ($referenceSurfaceType -eq 1) { 'Floor' } else { 'Ceiling' }
                                    $pairKey = 'Candidate S{0} {1} -> reference S{2} {3}' -f $candidateSectorIndex,$candidateSurfaceName,$referenceOwnerSectorIndex,$referenceSurfaceName
                                    if ($referencePlaneOwnerPairCounts.ContainsKey($pairKey)) { $referencePlaneOwnerPairCounts[$pairKey]++ }
                                    else { $referencePlaneOwnerPairCounts[$pairKey] = 1 }
                                    if ($candidateSectorIndex -eq $referenceOwnerSectorIndex -and $candidateSurfaceType -eq $referenceSurfaceType) {
                                        $candidatePlaneMismatchSameOwnerWrites++
                                        if ([int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition] -eq 1) {
                                            $candidatePlaneMismatchSameOwnerFinalPlaneWrites++
                                            $planeSampleCounts.SameOwnerSamples++
                                            $candidateSample = Get-FastPlaneSample $context $x $y $planeId $candidateViewXData $candidateViewYData $candidateViewZData $candidateViewAngleData $candidateExtraLight $candidateFixedColorMap
                                            [int]$referenceSampleOriginX = $reference3D.DiagnosticPlaneSampleOriginX[$referencePosition]
                                            [bool]$referenceSampleReusedPreviousColumn = $reference3D.DiagnosticPlaneSampleReusedPreviousColumn[$referencePosition] -eq 1
                                            if ($referenceSampleReusedPreviousColumn) { $planeSampleCounts.ReferenceSampleReusedPreviousColumn++ } else { $planeSampleCounts.ReferenceSampleInitializedAtCurrentColumn++ }
                                            [int]$candidateSampleAge = $x - $candidateSample.SampleOriginX
                                            $candidateSampleAgeKey = [string]$candidateSampleAge
                                            if ($planeSampleCounts.CandidateSampleAgeCounts.ContainsKey($candidateSampleAgeKey)) { $planeSampleCounts.CandidateSampleAgeCounts[$candidateSampleAgeKey]++ } else { $planeSampleCounts.CandidateSampleAgeCounts[$candidateSampleAgeKey] = 1 }
                                            if ($candidateSample.ReusedPreviousColumn) { $planeSampleCounts.CandidateSampleReusedPreviousColumn++ } else { $planeSampleCounts.CandidateSampleInitializedAtCurrentColumn++ }
                                            [int]$candidateReferenceOriginDelta = $candidateSample.SampleOriginX - $referenceSampleOriginX
                                            if ($candidateReferenceOriginDelta -lt 0) { $planeSampleCounts.CandidateSampleOriginBeforeReferenceOrigin++ }
                                            $candidateReferenceOriginDeltaKey = [string]$candidateReferenceOriginDelta
                                            if ($planeSampleCounts.CandidateSampleOriginDeltaCounts.ContainsKey($candidateReferenceOriginDeltaKey)) { $planeSampleCounts.CandidateSampleOriginDeltaCounts[$candidateReferenceOriginDeltaKey]++ } else { $planeSampleCounts.CandidateSampleOriginDeltaCounts[$candidateReferenceOriginDeltaKey] = 1 }
                                            [int]$referenceDistanceData = $reference3D.DiagnosticPlaneDistanceData[$referencePosition]
                                            [int]$referenceLightBin = $reference3D.DiagnosticPlaneLightIndices[$referencePosition]
                                            [int]$referenceXFracData = $reference3D.DiagnosticPlaneXFracData[$referencePosition]
                                            [int]$referenceYFracData = $reference3D.DiagnosticPlaneYFracData[$referencePosition]
                                            [int]$referenceTexelIndex = $reference3D.DiagnosticPlaneTexelIndices[$referencePosition]
                                            [int]$referenceOriginLengthData = ([long]$candidateSample.DistanceData * [long]$context.PlaneDistanceScales[$referenceSampleOriginX]) -shr 16
                                            [long]$referenceOriginXFracWide = [long]$candidateViewXData + (([long]$context.RayCos[$referenceSampleOriginX] * [long]$referenceOriginLengthData) -shr 16)
                                            [long]$referenceOriginYFracWide = -[long]$candidateViewYData - (([long]$context.RaySin[$referenceSampleOriginX] * [long]$referenceOriginLengthData) -shr 16)
                                            $referenceOriginXFracWide += [long]$candidateSample.StepX * ($x - $referenceSampleOriginX)
                                            $referenceOriginYFracWide += [long]$candidateSample.StepY * ($x - $referenceSampleOriginX)
                                            [int]$referenceOriginXFrac = [int]($referenceOriginXFracWide -band 0xFFFFFFFFL)
                                            [int]$referenceOriginYFrac = [int]($referenceOriginYFracWide -band 0xFFFFFFFFL)
                                            [int]$referenceOriginTextureX = ($referenceOriginXFrac -shr 16) -band 63
                                            [int]$referenceOriginTextureY = ((($referenceOriginYFrac -shr 10) -band 4032) -shr 6)
                                            [int]$referenceOriginTexel = $context.PlaneFlatData[$candidateSample.FlatIndex][($referenceOriginTextureY -shl 6) + $referenceOriginTextureX]
                                            [byte]$referenceOriginColor = $context.Colors[$candidateSample.LightMapIndex][$referenceOriginTexel]
                                            [int]$referenceTextureX = ($referenceXFracData -shr 16) -band 63
                                            [int]$referenceTextureY = ((($referenceYFracData -shr 10) -band 4032) -shr 6)
                                            $referenceColorMap = $reference3D.DiagnosticPlaneLightMaps[$referencePosition]
                                            [int]$referenceLightMapIndex = -1
                                            for ($mapIndex = 0; $mapIndex -lt $content.ColorMap.Data.Length; $mapIndex++) {
                                                if ([object]::ReferenceEquals($referenceColorMap, $content.ColorMap.Data[$mapIndex])) {
                                                    $referenceLightMapIndex = $mapIndex
                                                    break
                                                }
                                            }
                                            [byte]$referencePlaneColor = $referenceColorMap[$referenceTexelIndex]
                                            if ($candidateSample.DistanceData -eq $referenceDistanceData) { $planeSampleCounts.SameDistanceData++ }
                                            if ($candidateSample.DistanceLightBin -eq $referenceLightBin) { $planeSampleCounts.SameDistanceLightBin++ }
                                            if ($candidateSample.XFracData -eq $referenceXFracData) { $planeSampleCounts.SameXFraction++ }
                                            if ($candidateSample.YFracData -eq $referenceYFracData) { $planeSampleCounts.SameYFraction++ }
                                            if ($candidateSample.TextureX -eq $referenceTextureX) { $planeSampleCounts.SameTextureX++ }
                                            if ($candidateSample.TextureY -eq $referenceTextureY) { $planeSampleCounts.SameTextureY++ }
                                            if ($candidateSample.TextureX -eq $referenceTextureX -and $candidateSample.TextureY -eq $referenceTextureY) { $planeSampleCounts.SameTextureCoordinates++ }
                                            if ($candidateSample.FlatTexelIndex -eq $referenceTexelIndex) { $planeSampleCounts.SameFlatTexelIndex++ }
                                            if ($candidateSample.LightMapIndex -eq $referenceLightMapIndex) { $planeSampleCounts.SameLightMapIndex++ }
                                            if ($candidateSample.Color -eq $referencePlaneColor) { $planeSampleCounts.SamePlaneColor++ }
                                            if ($referenceOriginXFrac -eq $referenceXFracData) { $planeSampleCounts.ReferenceOriginAlignedSameXFraction++ }
                                            if ($referenceOriginYFrac -eq $referenceYFracData) { $planeSampleCounts.ReferenceOriginAlignedSameYFraction++ }
                                            if ($referenceOriginTextureX -eq $referenceTextureX -and $referenceOriginTextureY -eq $referenceTextureY) { $planeSampleCounts.ReferenceOriginAlignedSameTextureCoordinates++ }
                                            if ($referenceOriginTexel -eq $referenceTexelIndex) { $planeSampleCounts.ReferenceOriginAlignedSameFlatTexelIndex++ }
                                            if ($referenceOriginColor -eq $referencePlaneColor) { $planeSampleCounts.ReferenceOriginAlignedSamePlaneColor++ }
                                            if ($candidateSample.DirectXFracData -eq $referenceXFracData) { $planeSampleCounts.DirectSameXFraction++ }
                                            if ($candidateSample.DirectYFracData -eq $referenceYFracData) { $planeSampleCounts.DirectSameYFraction++ }
                                            if ($candidateSample.DirectTextureX -eq $referenceTextureX) { $planeSampleCounts.DirectSameTextureX++ }
                                            if ($candidateSample.DirectTextureY -eq $referenceTextureY) { $planeSampleCounts.DirectSameTextureY++ }
                                            if ($candidateSample.DirectFlatTexelIndex -eq $referenceTexelIndex) {
                                                $planeSampleCounts.DirectSameFlatTexelIndex++
                                                if ($referenceSampleReusedPreviousColumn) { $planeSampleCounts.DirectTexelMatchesWithReferenceReuse++ } else { $planeSampleCounts.DirectTexelMatchesAfterReferenceInitialize++ }
                                            }
                                            if ($candidateSample.DirectColor -eq $referencePlaneColor) { $planeSampleCounts.DirectSamePlaneColor++ }
                                            if ($candidate[$candidateIndex] -eq $candidateSample.Color) { $planeSampleCounts.CandidateFramebufferMatchesPlaneSample++ }
                                            if ($referencePixels[$referencePosition] -eq $referencePlaneColor) { $planeSampleCounts.ReferenceFramebufferMatchesPlaneSample++ }
                                            [int]$textureXDelta = (($candidateSample.TextureX - $referenceTextureX + 32) -band 63) - 32
                                            [int]$textureYDelta = (($candidateSample.TextureY - $referenceTextureY + 32) -band 63) - 32
                                            $textureXDeltaKey = [string]$textureXDelta
                                            $textureYDeltaKey = [string]$textureYDelta
                                            if ($planeSampleCounts.TextureXDeltaCounts.ContainsKey($textureXDeltaKey)) { $planeSampleCounts.TextureXDeltaCounts[$textureXDeltaKey]++ }
                                            else { $planeSampleCounts.TextureXDeltaCounts[$textureXDeltaKey] = 1 }
                                            if ($planeSampleCounts.TextureYDeltaCounts.ContainsKey($textureYDeltaKey)) { $planeSampleCounts.TextureYDeltaCounts[$textureYDeltaKey]++ }
                                            else { $planeSampleCounts.TextureYDeltaCounts[$textureYDeltaKey] = 1 }
                                            if ($planeSampleExamples.Count -lt 16) {
                                                $planeSampleExamples.Add([ordered]@{
                                                    X = $x
                                                    Y = $y
                                                    CandidateSampleOriginX = $candidateSample.SampleOriginX
                                                    CandidateSampleReusedPreviousColumn = $candidateSample.ReusedPreviousColumn
                                                    ReferenceOriginAlignedXFracData = $referenceOriginXFrac
                                                    ReferenceOriginAlignedYFracData = $referenceOriginYFrac
                                                    ReferenceOriginAlignedFlatTexelIndex = $referenceOriginTexel
                                                    ReferenceOriginAlignedPlaneColor = $referenceOriginColor
                                                    ReferenceSampleOriginX = $referenceSampleOriginX
                                                    ReferenceSampleReusedPreviousColumn = $referenceSampleReusedPreviousColumn
                                                    CandidateDistanceData = $candidateSample.DistanceData
                                                    ReferenceDistanceData = $referenceDistanceData
                                                    CandidateDistanceLightBin = $candidateSample.DistanceLightBin
                                                    ReferenceDistanceLightBin = $referenceLightBin
                                                    CandidateXFracData = $candidateSample.XFracData
                                                    ReferenceXFracData = $referenceXFracData
                                                    CandidateYFracData = $candidateSample.YFracData
                                                    ReferenceYFracData = $referenceYFracData
                                                    CandidateTextureX = $candidateSample.TextureX
                                                    ReferenceTextureX = $referenceTextureX
                                                    CandidateTextureY = $candidateSample.TextureY
                                                    ReferenceTextureY = $referenceTextureY
                                                    CandidateFlatTexelIndex = $candidateSample.FlatTexelIndex
                                                    ReferenceFlatTexelIndex = $referenceTexelIndex
                                                    CandidateLightMapIndex = $candidateSample.LightMapIndex
                                                    ReferenceLightMapIndex = $referenceLightMapIndex
                                                    CandidatePlaneColor = $candidateSample.Color
                                                    ReferencePlaneColor = $referencePlaneColor
                                                    DirectXFracData = $candidateSample.DirectXFracData
                                                    DirectYFracData = $candidateSample.DirectYFracData
                                                    DirectTextureX = $candidateSample.DirectTextureX
                                                    DirectTextureY = $candidateSample.DirectTextureY
                                                    DirectFlatTexelIndex = $candidateSample.DirectFlatTexelIndex
                                                    DirectPlaneColor = $candidateSample.DirectColor
                                                    CandidateFramebufferMatchesPlaneSample = ($candidate[$candidateIndex] -eq $candidateSample.Color)
                                                    ReferenceFramebufferMatchesPlaneSample = ($referencePixels[$referencePosition] -eq $referencePlaneColor)
                                                })
                                            }
                                        }
                                    } else {
                                        $candidatePlaneMismatchDifferentOwnerWrites++
                                    }
                                }
                            } else {
                                $candidateNonPlaneMismatchReferencePlaneWrites++
                            }
                        }
                    }
                    if ($planeId -gt 0) {
                        $candidatePlaneMismatchPixels++
                        if ($context.Depth[$candidateIndex] -eq [double]::PositiveInfinity) { $candidatePlaneNoDepthMismatchPixels++ }
                        if ($candidatePlaneMismatchCounts.ContainsKey($planeId)) { $candidatePlaneMismatchCounts[$planeId]++ }
                        else { $candidatePlaneMismatchCounts[$planeId] = 1 }
                    } else { $candidateNonPlaneMismatchPixels++ }
                    if ($context.Depth[$candidateIndex] -ne [double]::PositiveInfinity) { $candidateDepthWrittenMismatchPixels++ }
                    $bounds[0] = [Math]::Min($bounds[0], $x)
                    $bounds[1] = [Math]::Min($bounds[1], $y)
                    $bounds[2] = [Math]::Max($bounds[2], $x)
                    $bounds[3] = [Math]::Max($bounds[3], $y)
                } else { $hudDifferences++ }
            }
        }
        if ($candidatePlaneMismatchPixels + $candidateNonPlaneMismatchPixels -ne $sceneDifferences) {
            throw "Candidate plane ownership did not reconcile at ceiling height $height."
        }
        if ($CaptureReferencePlaneOwners) {
            if ($candidatePlaneMismatchReferencePlaneWrites + $candidatePlaneMismatchUnknownReferenceOwner + $candidatePlaneMismatchNoReferencePlaneWrite -ne $candidatePlaneMismatchPixels) {
                throw "Reference plane-write ownership did not reconcile for candidate planes at ceiling height $height."
            }
            if ($candidatePlaneMismatchReferenceFinalPlaneWrites + $candidatePlaneMismatchReferenceFinalColumnWrites + $candidatePlaneMismatchReferenceFinalFuzzWrites + $candidatePlaneMismatchReferenceFinalUnmarkedWrites -ne $candidatePlaneMismatchPixels) {
                throw "Reference final-writer classes did not reconcile at ceiling height $height."
            }
            if ($planeSampleCounts.SameOwnerSamples -ne $candidatePlaneMismatchSameOwnerFinalPlaneWrites) {
                throw "Same-owner plane sample counts did not reconcile at ceiling height $height."
            }
            if ($candidatePlaneMismatchSameOwnerWrites + $candidatePlaneMismatchDifferentOwnerWrites -ne $candidatePlaneMismatchReferencePlaneWrites) {
                throw "Reference owner pairs did not reconcile at ceiling height $height."
            }
            if ($candidatePlaneMismatchReferencePlaneWrites + $candidatePlaneMismatchUnknownReferenceOwner + $candidateNonPlaneMismatchReferencePlaneWrites -ne $referencePlaneWriteMismatchPixels) {
                throw "Reference plane-write mismatch counts did not reconcile at ceiling height $height."
            }
        }
        $candidatePlaneMismatchSurfaces = @(
            foreach ($planeId in @($candidatePlaneMismatchCounts.Keys | Sort-Object)) {
                $candidateSectorIndex = ([int]$planeId - 1) -shr 1
                [ordered]@{
                    PlaneId = [int]$planeId
                    SectorIndex = $candidateSectorIndex
                    Surface = if (([int]$planeId - 1) -band 1) { 'Floor' } else { 'Ceiling' }
                    MismatchPixels = $candidatePlaneMismatchCounts[$planeId]
                }
            }
        )
        $heightResults.Add([ordered]@{
            CeilingHeight = $height
            CandidateFrameSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($candidate))
            ReferenceFrameSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($referencePixels))
            SceneDifferentIndices = $sceneDifferences
            HudDifferentIndices = $hudDifferences
            SceneMismatchBounds = if ($sceneDifferences) { $bounds } else { @() }
            CandidatePlaneBufferMismatchPixels = $candidatePlaneMismatchPixels
            CandidatePlaneBufferAndNoDepthMismatchPixels = $candidatePlaneNoDepthMismatchPixels
            CandidateNonPlaneBufferMismatchPixels = $candidateNonPlaneMismatchPixels
            CandidateDepthWrittenMismatchPixels = $candidateDepthWrittenMismatchPixels
            CandidatePlaneBufferMismatchBySurface = $candidatePlaneMismatchSurfaces
            ReferencePlaneWriteMismatchPixels = $referencePlaneWriteMismatchPixels
            CandidatePlaneMismatchReferencePlaneWrites = $candidatePlaneMismatchReferencePlaneWrites
            CandidatePlaneMismatchSameOwnerWrites = $candidatePlaneMismatchSameOwnerWrites
            CandidatePlaneMismatchDifferentOwnerWrites = $candidatePlaneMismatchDifferentOwnerWrites
            CandidatePlaneMismatchNoReferencePlaneWrite = $candidatePlaneMismatchNoReferencePlaneWrite
            CandidatePlaneMismatchUnknownReferenceOwner = $candidatePlaneMismatchUnknownReferenceOwner
            CandidateNonPlaneMismatchReferencePlaneWrites = $candidateNonPlaneMismatchReferencePlaneWrites
            CandidatePlaneMismatchReferenceFinalPlaneWrites = $candidatePlaneMismatchReferenceFinalPlaneWrites
            CandidatePlaneMismatchReferenceFinalColumnWrites = $candidatePlaneMismatchReferenceFinalColumnWrites
            CandidatePlaneMismatchReferenceFinalFuzzWrites = $candidatePlaneMismatchReferenceFinalFuzzWrites
            CandidatePlaneMismatchReferenceFinalUnmarkedWrites = $candidatePlaneMismatchReferenceFinalUnmarkedWrites
            CandidatePlaneMismatchSameOwnerFinalPlaneWrites = $candidatePlaneMismatchSameOwnerFinalPlaneWrites
            SameOwnerPlaneSampleComparisons = $planeSampleCounts
            SameOwnerPlaneSampleExamples = $planeSampleExamples.ToArray()
            ReferencePlaneWriteOwnerPairs = @(
                foreach ($pairKey in @($referencePlaneOwnerPairCounts.Keys | Sort-Object)) {
                    [ordered]@{ Pair = $pairKey; MismatchPixels = $referencePlaneOwnerPairCounts[$pairKey] }
                }
            )
        })
        $frames[[int]$height] = @{ Candidate = $candidate; Reference = $referencePixels }
    }

    $firstHeight = [int]($Heights | Select-Object -First 1)
    $lastHeight = [int]($Heights | Select-Object -Last 1)
    $maskLocationsChanged = 0
    $candidateChanges = 0
    $referenceChanges = 0
    for ($y = 0; $y -lt 168; $y++) {
        for ($x = 0; $x -lt 320; $x++) {
            $index = $y * 320 + $x
            $firstMismatch = $frames[$firstHeight].Candidate[$index] -ne $frames[$firstHeight].Reference[$x * 200 + $y]
            $lastMismatch = $frames[$lastHeight].Candidate[$index] -ne $frames[$lastHeight].Reference[$x * 200 + $y]
            if ($firstMismatch -ne $lastMismatch) { $maskLocationsChanged++ }
            if ($frames[$firstHeight].Candidate[$index] -ne $frames[$lastHeight].Candidate[$index]) { $candidateChanges++ }
            if ($frames[$firstHeight].Reference[$x * 200 + $y] -ne $frames[$lastHeight].Reference[$x * 200 + $y]) { $referenceChanges++ }
        }
    }

    $planeDistanceScaleMismatchXs = [Collections.Generic.List[int]]::new()
    $planeColumnAngleMismatchXs = [Collections.Generic.List[int]]::new()
    $viewColumnCosMismatchXs = [Collections.Generic.List[int]]::new()
    $viewColumnSinMismatchXs = [Collections.Generic.List[int]]::new()
    $reference3D = $reference.ThreeD
    for ([int]$x = 0; $x -lt 320; $x++) {
        if ($context.PlaneColumnAngles[$x] -ne $reference3D.xToAngleData[$x]) { $planeColumnAngleMismatchXs.Add($x) }
        if ($context.PlaneDistanceScales[$x] -ne $reference3D.planeDistScale[$x]) { $planeDistanceScaleMismatchXs.Add($x) }
        if ($context.RayCos[$x] -ne $reference3D.viewColumnCosData[$x]) { $viewColumnCosMismatchXs.Add($x) }
        if ($context.RaySin[$x] -ne $reference3D.viewColumnSinData[$x]) { $viewColumnSinMismatchXs.Add($x) }
    }
    $planeRowSlopeMismatchYs = [Collections.Generic.List[int]]::new()
    for ([int]$y = 0; $y -lt 168; $y++) {
        if ($context.PlaneRowSlopes[$y] -ne $reference3D.planeYSlope[$y]) { $planeRowSlopeMismatchYs.Add($y) }
    }
    [uint32]$cameraAngleData = $game.World.ConsolePlayer.Mobj.Angle.Data
    [uint32]$planeBaseAngleData = ([long]$cameraAngleData - 0x40000000L) -band 0xFFFFFFFFL
    [int]$planeBaseFine = $planeBaseAngleData -shr 19
    [int[]]$fineSine = $context.PlaneFineSine
    [int]$candidatePlaneBaseXScale = [Math]::Truncate([double]$fineSine[$planeBaseFine + 2048] / 160.0)
    [int]$candidatePlaneBaseYScale = -[Math]::Truncate([double]$fineSine[$planeBaseFine] / 160.0)
    $planeMathParity = [ordered]@{
        PlaneColumnAngleMismatchXs = $planeColumnAngleMismatchXs.ToArray()
        PlaneDistanceScaleMismatchXs = $planeDistanceScaleMismatchXs.ToArray()
        PlaneRowSlopeMismatchYs = $planeRowSlopeMismatchYs.ToArray()
        ViewColumnCosMismatchXs = $viewColumnCosMismatchXs.ToArray()
        ViewColumnSinMismatchXs = $viewColumnSinMismatchXs.ToArray()
        CandidatePlaneBaseXScale = $candidatePlaneBaseXScale
        ReferencePlaneBaseXScale = $reference3D.planeBaseXScale
        CandidatePlaneBaseYScale = $candidatePlaneBaseYScale
        ReferencePlaneBaseYScale = $reference3D.planeBaseYScale
    }

    $diagnosticImages = [Collections.Generic.List[object]]::new()
    if ($Images) {
        foreach ($height in @($firstHeight, $lastHeight) | Select-Object -Unique) {
            $frame = $frames[$height]
            $bitmap = [Drawing.Bitmap]::new(960, 168)
            try {
                for ($y = 0; $y -lt 168; $y++) {
                    for ($x = 0; $x -lt 320; $x++) {
                        $index = $y * 320 + $x
                        $referenceColor = [int]$frame.Reference[$x * 200 + $y]
                        $candidateColor = [int]$frame.Candidate[$index]
                        $paletteIndex = 3 * $referenceColor
                        $bitmap.SetPixel($x, $y, [Drawing.Color]::FromArgb(
                            [int]$content.Palette.Data[$paletteIndex],
                            [int]$content.Palette.Data[$paletteIndex + 1],
                            [int]$content.Palette.Data[$paletteIndex + 2]))
                        $paletteIndex = 3 * $candidateColor
                        $bitmap.SetPixel($x + 320, $y, [Drawing.Color]::FromArgb(
                            [int]$content.Palette.Data[$paletteIndex],
                            [int]$content.Palette.Data[$paletteIndex + 1],
                            [int]$content.Palette.Data[$paletteIndex + 2]))
                        $maskValue = if ($candidateColor -eq $referenceColor) { 0 } else { 255 }
                        $bitmap.SetPixel($x + 640, $y, [Drawing.Color]::FromArgb($maskValue, $maskValue, $maskValue))
                    }
                }
                $imagePath = Join-Path $Images ("e1m1-tic{0}-ceiling{1}.png" -f $InputTic, $height)
                $bitmap.Save($imagePath, [Drawing.Imaging.ImageFormat]::Png)
                $relativePath = [IO.Path]::GetRelativePath($root, $imagePath).Replace('\', '/')
                $diagnosticImages.Add(@{ Path = $relativePath; Sha256 = (Get-FileHash $imagePath).Hash })
            } finally { $bitmap.Dispose() }
        }
    }

    $result = [ordered]@{
        SchemaVersion = 1
        FinishedUtc = [DateTime]::UtcNow.ToString('o')
        Experiment = 'Counterfactual render sweep of the E1M1 moving ceiling at one frozen replay-derived game state'
        SourceCommit = (git -C $root rev-parse HEAD).Trim()
        Episode = 1
        Map = 1
        Skill = 3
        InputTic = $InputTic
        LevelTic = $game.World.LevelTime
        SectorIndex = $SectorIndex
        ActualCeilingHeight = $actualHeight
        ReplayPath = [IO.Path]::GetRelativePath($root, $Replay).Replace('\', '/')
        ReplaySha256 = (Get-FileHash -LiteralPath $Replay).Hash
        WadSha256 = (Get-FileHash -LiteralPath $Wad).Hash
        Heights = $heightResults.ToArray()
        ComparedScenePixels = 53760
        ComparedHudPixels = 10240
        MismatchMaskLocationsChangedFirstToLast = $maskLocationsChanged
        CandidatePixelsChangedFirstToLast = $candidateChanges
        ReferencePixelsChangedFirstToLast = $referenceChanges
        PlaneMathParity = $planeMathParity
        ReferenceEngineSourceRoot = [IO.Path]::GetRelativePath($root, $EngineSourceRoot).Replace('\', '/')
        ReferenceEngineBundlePath = [IO.Path]::GetRelativePath($root, $bundle).Replace('\', '/')
        ReferenceEngineBundleSha256 = (Get-FileHash -LiteralPath $bundle).Hash
        ReferencePlaneOwnershipCaptured = [bool]$CaptureReferencePlaneOwners
        OnlyChangedSectorCeiling = $true
        OtherSimulationStateHeldFixed = $true
        Reference = 'Locally adapted PowerShell ManagedDoom ThreeDRenderer'
        OriginalExecutableComparison = $false
        Sources = @(
            foreach ($path in $sourcePaths) {
                @{ Path = $path; Sha256 = $sourceHashes[$path] }
            }
        )
        DiagnosticImages = $diagnosticImages.ToArray()
        Error = $null
        Interpretation = 'A counterfactual surface-fidelity comparison, not a movement/progression test, original-executable parity result, or performance measurement.'
        CandidateOwnershipInterpretation = 'Plane-buffer counts classify the candidate plane ID at mismatch coordinates; a later actor may overlay that plane. The finite-depth count does not distinguish walls from sprites.'
        ReferencePlaneWritesInterpretation = 'Plane ownership records the last reference floor/ceiling write. Final-writer tags distinguish that plane write from later mapped-column writes or fuzz writes; unmarked writers may include other compositor paths.'
        PlaneSampleInterpretation = 'Candidate plane fractions, recurrence origins and reuse flags are captured from the production per-call plane sampler. Reference fractions, distance, light bin and flat texel are recorded at writes. Candidate frame bytes may include later overlays.'
        PlaneMathInterpretation = 'Plane table and per-column fixed sine parity are compared after the final full-width candidate/reference render; this does not compare per-pixel plane fraction recurrence or light selection.'
    }
    $currentHashes = @{}
    foreach ($path in $sourcePaths) {
        $currentHashes[$path] = (Get-FileHash -LiteralPath (Join-Path $root $path)).Hash
    }
    foreach ($path in $sourcePaths) {
        if ($sourceHashes[$path] -cne $currentHashes[$path]) {
            throw "Source file changed during the experiment: $path"
        }
    }
    [IO.File]::WriteAllText($Output, ($result | ConvertTo-Json -Depth 10), [Text.UTF8Encoding]::new($false))
} finally {
    if ($content) { $content.Dispose() }
}

"Wrote current moving-sector comparison to $Output"
