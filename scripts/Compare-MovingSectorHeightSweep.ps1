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
    [switch]$CaptureWallBoundaryTrace,
    [ValidateRange(2,100000)][int]$InputTic = 315,
    [ValidateRange(0,32767)][int]$SectorIndex = 26,
    [ValidateRange(-4096,4096)][int[]]$Heights = @(0, 6, 34, 68)
)

$referenceRenderPassNames = @{
    '0' = 'Unmarked'
    '1' = 'BSP traversal'
    '2' = 'World sprites'
    '3' = 'Masked textures'
    '4' = 'Player sprites'
    '5' = 'Back-screen fill'
    '6' = 'Sky column'
}
$referenceFinalWriterNames = @{
    '0' = 'Unmarked'
    '1' = 'Plane'
    '2' = 'Mapped column'
    '3' = 'Fuzz column'
}
$candidateDepthOwnerWriterNames = @{
    '0' = 'Unassigned'
    '1' = 'Opaque wall band'
    '2' = 'Untextured wall occlusion'
    '3' = 'Masked middle texture'
}

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
$Renderer = [IO.Path]::GetFullPath($Renderer)
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
if ($CaptureWallBoundaryTrace -and -not [IO.File]::ReadAllText($Renderer).Contains('DiagnosticWallSpanTrace')) {
    throw 'Wall-boundary tracing requires the generated diagnostic candidate renderer.'
}
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
    'src/FastRenderer.ps1',
    'src/GameHost.ps1',
    [IO.Path]::GetRelativePath($root, $referenceRendererSource).Replace('\', '/'),
    'src/ManagedDoom/Video/ThreeDRenderer.sb.ps1',
    'scripts/Compare-MovingSectorHeightSweep.ps1',
    'scripts/Prepare-ReferencePlaneOwnerDiagnosticSource.ps1',
    'scripts/Prepare-FastRendererWallSpanDiagnosticRenderer.ps1',
    'scripts/Prepare-FastRendererPortalTopBoundaryCounterfactual.ps1',
    'scripts/Prepare-FastRendererUntexturedLowerPlaneCounterfactual.ps1',
    'scripts/Prepare-FastRendererPerRowPlaneKeyCounterfactual.ps1',
    'scripts/Prepare-FastRendererDirectPlaneColumnCounterfactual.ps1'
)
$sourcePaths = @($sourcePaths | Select-Object -Unique)
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
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalRenderPassTypes') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalWallSegIndices') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalWallTopRows') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalWallBottomRows') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalWallTextureRows') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalWallTextureFractions') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalWallSourceColors') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalWallMappedColors') -and
        $null -ne $reference3D.GetType().GetProperty('DiagnosticFinalWorldSpriteDescriptions') -and
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
        $reference3D.DiagnosticPlaneCallTrace = [Collections.Generic.List[object]]::new()
        $reference3D.DiagnosticPlaneOwners = [Sector[]]::new(320 * 200)
        $reference3D.DiagnosticPlaneSurfaceTypes = [byte[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWriterTypes = [byte[]]::new(320 * 200)
        $reference3D.DiagnosticFinalRenderPassTypes = [byte[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWallSegIndices = [int[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWallTopRows = [int[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWallBottomRows = [int[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWallTextureRows = [int[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWallTextureFractions = [int[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWallSourceColors = [int[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWallMappedColors = [int[]]::new(320 * 200)
        $reference3D.DiagnosticFinalWorldSpriteDescriptions = [string[]]::new(320 * 200)
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
    if ($CaptureWallBoundaryTrace) {
        $context.DiagnosticPlaneCallSegIndices = [int[]]::new(2048)
        $context.DiagnosticWallSpanTrace = [int[]]::new($game.World.Map.Segs.Length * 320 * 12)
        $context.DiagnosticWallSpanTraceSeen = [byte[]]::new($game.World.Map.Segs.Length * 320)
        $context.DiagnosticPlaneOwnerSegIndices = [int[]]::new(320 * 168)
        $context.DiagnosticDepthOwnerSegIndices = [int[]]::new(320 * 168)
        $context.DiagnosticDepthOwnerWriterTypes = [byte[]]::new(320 * 168)
        $context.DiagnosticWallSampleTextureIds = [int[]]::new(320 * 168)
        $context.DiagnosticWallSampleBands = [int[]]::new(320 * 168)
        $context.DiagnosticWallSampleColumns = [int[]]::new(320 * 168)
        $context.DiagnosticWallSampleRows = [int[]]::new(320 * 168)
        $context.DiagnosticWallSampleFractions = [double[]]::new(320 * 168)
        $context.DiagnosticWallSampleOrigins = [double[]]::new(320 * 168)
        $context.DiagnosticWallSampleTexelSteps = [double[]]::new(320 * 168)
        $context.DiagnosticWallSampleTextureHeights = [int[]]::new(320 * 168)
        $context.DiagnosticWallSampleSourceColors = [int[]]::new(320 * 168)
        $context.DiagnosticWallSampleMappedColors = [int[]]::new(320 * 168)
        $context.DiagnosticWallSampleLightIndexes = [int[]]::new(320 * 168)
        [Array]::Fill($context.DiagnosticDepthOwnerSegIndices, -1)
    }
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
        if ($CaptureWallBoundaryTrace) {
            [Array]::Clear($context.DiagnosticWallSpanTrace)
            [Array]::Clear($context.DiagnosticWallSpanTraceSeen)
            [Array]::Clear($context.DiagnosticPlaneOwnerSegIndices)
            [Array]::Fill($context.DiagnosticDepthOwnerSegIndices, -1)
            [Array]::Fill($context.DiagnosticWallSampleTextureIds, -1)
            [Array]::Fill($context.DiagnosticWallSampleBands, -1)
            [Array]::Fill($context.DiagnosticWallSampleColumns, -1)
            [Array]::Fill($context.DiagnosticWallSampleRows, -1)
            [Array]::Fill($context.DiagnosticWallSampleFractions, [double](-1))
            [Array]::Fill($context.DiagnosticWallSampleOrigins, [double](-1))
            [Array]::Fill($context.DiagnosticWallSampleTexelSteps, [double](-1))
            [Array]::Fill($context.DiagnosticWallSampleTextureHeights, -1)
            [Array]::Fill($context.DiagnosticWallSampleSourceColors, -1)
            [Array]::Fill($context.DiagnosticWallSampleMappedColors, -1)
            [Array]::Fill($context.DiagnosticWallSampleLightIndexes, -1)
            [Array]::Clear($context.DiagnosticDepthOwnerWriterTypes)
        }
        [Array]::Fill($context.PlaneSampleOriginX, -1)
        [Array]::Clear($context.PlaneSampleReusedPreviousColumn)
        [Array]::Fill($context.PlaneCeilingSampleOriginX, -1)
        [Array]::Fill($context.PlaneFloorSampleOriginX, -1)
        Invoke-FastRender $context
        $candidatePlaneCallTrace = [Collections.Generic.List[object]]::new()
        if ($CaptureWallBoundaryTrace -and [int]$height -eq 68 -and $context.ContainsKey('PlaneSampleCallCount')) {
            [int[]]$candidatePlaneCalls = $context.PlaneSampleCalls
            [int]$candidatePlaneCallCount = [int]$context.PlaneSampleCallCount
            if (($candidatePlaneCallCount -band 3) -ne 0) { throw 'Candidate plane-call trace has a truncated record.' }
            for ([int]$callIndex = 0; $callIndex -lt ($candidatePlaneCallCount -shr 2); $callIndex++) {
                [int]$callOffset = $callIndex * 4
                [int]$callX = $candidatePlaneCalls[$callOffset]
                [int]$callY1 = $candidatePlaneCalls[$callOffset + 1]
                [int]$callY2 = $candidatePlaneCalls[$callOffset + 2]
                [int]$planeId = $candidatePlaneCalls[$callOffset + 3]
                if ($callX -lt 0 -or $callX -ge 320) { throw "Candidate plane-call trace contains out-of-frame column $callX." }
                $candidatePlaneCallTrace.Add([ordered]@{
                    Ordinal = $callIndex
                    X = $callX
                    Y1 = $callY1
                    Y2 = $callY2
                    PlaneId = $planeId
                    SectorIndex = ($planeId - 1) -shr 1
                    SurfaceType = if (($planeId -band 1) -eq 0) { 'Floor' } else { 'Ceiling' }
                    SegmentIndex = [int]$context.DiagnosticPlaneCallSegIndices[$callIndex]
                })
            }
        }
        [byte[]]$candidate = $context.Pixels.Clone()
        if ($CaptureReferencePlaneOwners) {
            $reference3D.DiagnosticPlaneCallTrace.Clear()
            [Array]::Clear($reference3D.DiagnosticPlaneOwners, 0, $reference3D.DiagnosticPlaneOwners.Length)
            [Array]::Clear($reference3D.DiagnosticPlaneSurfaceTypes, 0, $reference3D.DiagnosticPlaneSurfaceTypes.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWriterTypes, 0, $reference3D.DiagnosticFinalWriterTypes.Length)
            [Array]::Clear($reference3D.DiagnosticFinalRenderPassTypes, 0, $reference3D.DiagnosticFinalRenderPassTypes.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWallSegIndices, 0, $reference3D.DiagnosticFinalWallSegIndices.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWallTopRows, 0, $reference3D.DiagnosticFinalWallTopRows.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWallBottomRows, 0, $reference3D.DiagnosticFinalWallBottomRows.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWallTextureRows, 0, $reference3D.DiagnosticFinalWallTextureRows.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWallTextureFractions, 0, $reference3D.DiagnosticFinalWallTextureFractions.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWallSourceColors, 0, $reference3D.DiagnosticFinalWallSourceColors.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWallMappedColors, 0, $reference3D.DiagnosticFinalWallMappedColors.Length)
            [Array]::Clear($reference3D.DiagnosticFinalWorldSpriteDescriptions, 0, $reference3D.DiagnosticFinalWorldSpriteDescriptions.Length)
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
        $candidatePlaneMismatchBspColumnPixels = 0
        $candidatePlaneMismatchSameOwnerFinalPlaneWrites = 0
        $candidatePlaneMismatchFinalRenderPassCounts = @{}
        $candidateNonPlaneMismatchFinalWriterCounts = @{}
        $candidateNonPlaneMismatchFinalRenderPassCounts = @{}
        $candidateNonPlaneMismatchWriterDepthWrittenCounts = @{}
        $candidateNonPlaneMismatchWriterNoDepthCounts = @{}
        $candidateNonPlaneMismatchDepthOwnerCounts = @{}
        $candidateNonPlaneMismatchReferenceWallSegmentCounts = @{}
        $candidatePlaneMismatchWallSpanCounts = [ordered]@{
            ReferenceOpaqueWallPixels = 0
            ReferenceWallWriteIntervalContainsPixel = 0
            ReferenceWallSegmentMissing = 0
            CandidateSegmentColumnTraceMissing = 0
            CandidateSegmentColumnTraceFound = 0
            CandidateWallBoundsContainPixel = 0
            CandidateClipContainsPixel = 0
            CandidatePortalTopEqualsPixel = 0
            ReferenceWallBottomEqualsPixel = 0
            CandidatePortalTopEqualsReferenceWallBottom = 0
            CandidateUpperBandEndsImmediatelyAbovePixel = 0
            CandidateOpaqueWallBandSpanContainsPixel = 0
            CandidateMaskedMiddleSpanContainsPixel = 0
            CandidateAnyWallBandSpanContainsPixel = 0
            ReferenceWallPixelOutsideCandidateWallBounds = 0
            ReferenceWallPixelOutsideCandidateClip = 0
            ReferenceWallPixelOutsideCandidateWallBands = 0
            CandidateOpaqueBandContainsPixelWithoutCandidateDepth = 0
        }
        $candidatePlaneMismatchWallSpanExamples = [Collections.Generic.List[object]]::new()
        $candidatePlaneMismatchDifferentOwnerExamples = [Collections.Generic.List[object]]::new()
        $candidatePlaneMismatchOwnerSegmentCounts = [ordered]@{
            DifferentOwnerPlanePixels = 0
            CandidatePlaneOwnerSegmentMissing = 0
            CandidatePlaneOwnerSegmentFound = 0
            CandidatePlaneOwnerSegmentTraceMissing = 0
            CandidatePlaneOwnerSegmentTraceFound = 0
            CandidatePlaneOwnerSegmentFrontMatchesPlane = 0
            CandidatePlaneSampleOppositeOwnerSegmentSide = 0
            CandidatePlaneSampleSameOwnerSegmentSide = 0
            CandidatePlaneSampleOnOwnerSegmentLine = 0
            CandidatePlaneSampleProjectionWithinOwnerSegment = 0
            CandidatePlaneSampleProjectionOutsideOwnerSegment = 0
            CandidatePlaneSampleMapSectorMatchesPlane = 0
            CandidatePlaneSampleMapSectorMatchesReferenceOwner = 0
            CandidatePlaneSampleMapSectorMatchesNeitherOwner = 0
            ReferencePlaneSampleMapSectorMatchesPlane = 0
            ReferencePlaneSampleMapSectorMatchesReferenceOwner = 0
            ReferencePlaneSampleMapSectorMatchesNeitherOwner = 0
            CandidateReferencePlaneSameDistance = 0
            CandidateReferencePlaneSameXFraction = 0
            CandidateReferencePlaneSameYFraction = 0
            CandidateReferencePlaneSameTextureCoordinates = 0
            CandidateReferencePlaneSameFlatTexel = 0
            CandidateReferencePlaneSameColor = 0
            CandidateReferenceOriginSameXFraction = 0
            CandidateReferenceOriginSameYFraction = 0
            CandidateReferenceOriginSameTextureCoordinates = 0
            CandidateReferenceOriginSameFlatTexel = 0
            CandidateReferenceOriginSameColor = 0
        }
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
                            [string]$renderPassKey = [string][int]$reference3D.DiagnosticFinalRenderPassTypes[$referencePosition]
                            if ($candidatePlaneMismatchFinalRenderPassCounts.ContainsKey($renderPassKey)) { $candidatePlaneMismatchFinalRenderPassCounts[$renderPassKey]++ }
                            else { $candidatePlaneMismatchFinalRenderPassCounts[$renderPassKey] = 1 }
                            switch ([int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition]) {
                                1 { $candidatePlaneMismatchReferenceFinalPlaneWrites++ }
                                2 { $candidatePlaneMismatchReferenceFinalColumnWrites++ }
                                3 { $candidatePlaneMismatchReferenceFinalFuzzWrites++ }
                                default { $candidatePlaneMismatchReferenceFinalUnmarkedWrites++ }
                            }
                            if ([int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition] -eq 2 -and
                                [int]$reference3D.DiagnosticFinalRenderPassTypes[$referencePosition] -eq 1) {
                                $candidatePlaneMismatchBspColumnPixels++
                            }
                            if ($CaptureWallBoundaryTrace -and
                                [int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition] -eq 2 -and
                                [int]$reference3D.DiagnosticFinalRenderPassTypes[$referencePosition] -eq 1) {
                                $candidatePlaneMismatchWallSpanCounts.ReferenceOpaqueWallPixels++
                                [int]$referenceWallSegmentEncoded = $reference3D.DiagnosticFinalWallSegIndices[$referencePosition]
                                [int]$referenceWallTop = $reference3D.DiagnosticFinalWallTopRows[$referencePosition]
                                [int]$referenceWallBottom = $reference3D.DiagnosticFinalWallBottomRows[$referencePosition]
                                if ($y -ge $referenceWallTop -and $y -le $referenceWallBottom) {
                                    $candidatePlaneMismatchWallSpanCounts.ReferenceWallWriteIntervalContainsPixel++
                                }
                                if ($referenceWallSegmentEncoded -le 0) {
                                    $candidatePlaneMismatchWallSpanCounts.ReferenceWallSegmentMissing++
                                } else {
                                    [int]$referenceWallSegmentIndex = $referenceWallSegmentEncoded - 1
                                    [int]$candidateTraceCell = $referenceWallSegmentIndex * 320 + $x
                                    if ($referenceWallSegmentIndex -ge $game.World.Map.Segs.Length -or
                                        $candidateTraceCell -ge $context.DiagnosticWallSpanTraceSeen.Length -or
                                        $context.DiagnosticWallSpanTraceSeen[$candidateTraceCell] -eq 0) {
                                        $candidatePlaneMismatchWallSpanCounts.CandidateSegmentColumnTraceMissing++
                                    } else {
                                        $candidatePlaneMismatchWallSpanCounts.CandidateSegmentColumnTraceFound++
                                        [int]$candidateTraceOffset = $candidateTraceCell * 12
                                        [int[]]$candidateWallTrace = $context.DiagnosticWallSpanTrace
                                        [int]$candidateWallTop = $candidateWallTrace[$candidateTraceOffset]
                                        [int]$candidateWallBottom = $candidateWallTrace[$candidateTraceOffset + 1]
                                        [int]$candidateClipTop = $candidateWallTrace[$candidateTraceOffset + 2]
                                        [int]$candidateClipBottom = $candidateWallTrace[$candidateTraceOffset + 3]
                                        [int]$candidatePortalTop = $candidateWallTrace[$candidateTraceOffset + 4]
                                        [int]$candidatePortalBottom = $candidateWallTrace[$candidateTraceOffset + 5]
                                        [bool]$candidateWallBoundsContainPixel = $candidateWallTop -le $y -and $y -le $candidateWallBottom
                                        [bool]$candidateClipContainsPixel = $candidateClipTop -le $y -and $y -le $candidateClipBottom
                                        if ($candidatePortalTop -eq $y) { $candidatePlaneMismatchWallSpanCounts.CandidatePortalTopEqualsPixel++ }
                                        if ($referenceWallBottom -eq $y) { $candidatePlaneMismatchWallSpanCounts.ReferenceWallBottomEqualsPixel++ }
                                        if ($candidatePortalTop -eq $referenceWallBottom) { $candidatePlaneMismatchWallSpanCounts.CandidatePortalTopEqualsReferenceWallBottom++ }
                                        if ($candidateWallTrace[$candidateTraceOffset + 7] -eq ($y - 1)) { $candidatePlaneMismatchWallSpanCounts.CandidateUpperBandEndsImmediatelyAbovePixel++ }
                                        [bool]$candidateOpaqueWallBandContainsPixel = $false
                                        [bool]$candidateMaskedMiddleContainsPixel = $false
                                        for ([int]$candidateBand = 0; $candidateBand -lt 3; $candidateBand++) {
                                            [int]$candidateBandTop = $candidateWallTrace[$candidateTraceOffset + 6 + 2 * $candidateBand]
                                            [int]$candidateBandBottom = $candidateWallTrace[$candidateTraceOffset + 7 + 2 * $candidateBand]
                                            if ($candidateBandTop -le $y -and $y -le $candidateBandBottom) {
                                                if ($candidateBand -lt 2) { $candidateOpaqueWallBandContainsPixel = $true }
                                                else { $candidateMaskedMiddleContainsPixel = $true }
                                            }
                                        }
                                        [bool]$candidateAnyWallBandContainsPixel = $candidateOpaqueWallBandContainsPixel -or $candidateMaskedMiddleContainsPixel
                                        [bool]$candidateDepthIsInfinite = $context.Depth[$candidateIndex] -eq [double]::PositiveInfinity
                                        if ($candidateWallBoundsContainPixel) { $candidatePlaneMismatchWallSpanCounts.CandidateWallBoundsContainPixel++ }
                                        if ($candidateClipContainsPixel) { $candidatePlaneMismatchWallSpanCounts.CandidateClipContainsPixel++ }
                                        if ($candidateOpaqueWallBandContainsPixel) {
                                            $candidatePlaneMismatchWallSpanCounts.CandidateOpaqueWallBandSpanContainsPixel++
                                            if ($candidateDepthIsInfinite) { $candidatePlaneMismatchWallSpanCounts.CandidateOpaqueBandContainsPixelWithoutCandidateDepth++ }
                                        }
                                        if ($candidateMaskedMiddleContainsPixel) { $candidatePlaneMismatchWallSpanCounts.CandidateMaskedMiddleSpanContainsPixel++ }
                                        if ($candidateAnyWallBandContainsPixel) { $candidatePlaneMismatchWallSpanCounts.CandidateAnyWallBandSpanContainsPixel++ }
                                        if (-not $candidateWallBoundsContainPixel) { $candidatePlaneMismatchWallSpanCounts.ReferenceWallPixelOutsideCandidateWallBounds++ }
                                        if (-not $candidateClipContainsPixel) { $candidatePlaneMismatchWallSpanCounts.ReferenceWallPixelOutsideCandidateClip++ }
                                        if (-not $candidateAnyWallBandContainsPixel) { $candidatePlaneMismatchWallSpanCounts.ReferenceWallPixelOutsideCandidateWallBands++ }
                                        if ($candidatePlaneMismatchWallSpanExamples.Count -lt 32) {
                                            [int]$candidateMetadataOffset = $referenceWallSegmentIndex * 4
                                            $candidatePlaneMismatchWallSpanExamples.Add([ordered]@{
                                                X = $x
                                                Y = $y
                                                CandidatePlaneId = $planeId
                                                CandidateDepth = if ($candidateDepthIsInfinite) { 'PositiveInfinity' } else { $context.Depth[$candidateIndex] }
                                                ReferenceWallSegmentIndex = $referenceWallSegmentIndex
                                                ReferenceWallWriteTop = $referenceWallTop
                                                ReferenceWallWriteBottom = $referenceWallBottom
                                                ReferenceWriteIntervalContainsPixel = ($y -ge $referenceWallTop -and $y -le $referenceWallBottom)
                                                CandidateWallTop = $candidateWallTop
                                                CandidateWallBottom = $candidateWallBottom
                                                CandidateClipTop = $candidateClipTop
                                                CandidateClipBottom = $candidateClipBottom
                                                CandidatePortalTop = $candidatePortalTop
                                                CandidatePortalBottom = $candidatePortalBottom
                                                CandidateUpperOrSolidBandTop = $candidateWallTrace[$candidateTraceOffset + 6]
                                                CandidateUpperOrSolidBandBottom = $candidateWallTrace[$candidateTraceOffset + 7]
                                                CandidateLowerBandTop = $candidateWallTrace[$candidateTraceOffset + 8]
                                                CandidateLowerBandBottom = $candidateWallTrace[$candidateTraceOffset + 9]
                                                CandidateMaskedMiddleBandTop = $candidateWallTrace[$candidateTraceOffset + 10]
                                                CandidateMaskedMiddleBandBottom = $candidateWallTrace[$candidateTraceOffset + 11]
                                                CandidateWallBoundsContainPixel = $candidateWallBoundsContainPixel
                                                CandidateClipContainsPixel = $candidateClipContainsPixel
                                                CandidateOpaqueWallBandContainsPixel = $candidateOpaqueWallBandContainsPixel
                                                CandidateMaskedMiddleContainsPixel = $candidateMaskedMiddleContainsPixel
                                                CandidateSideIndex = $context.SegmentMetadata[$candidateMetadataOffset]
                                                CandidateFrontSectorIndex = $context.SegmentMetadata[$candidateMetadataOffset + 1]
                                                CandidateBackSectorIndex = $context.SegmentMetadata[$candidateMetadataOffset + 2]
                                                CandidateLineFlags = $context.SegmentMetadata[$candidateMetadataOffset + 3]
                                            })
                                        }
                                    }
                                }
                            }
                        } else {
                            [string]$writerKey = [string][int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition]
                            if ($candidateNonPlaneMismatchFinalWriterCounts.ContainsKey($writerKey)) {
                                $candidateNonPlaneMismatchFinalWriterCounts[$writerKey]++
                            } else {
                                $candidateNonPlaneMismatchFinalWriterCounts[$writerKey] = 1
                            }
                            if ($context.Depth[$candidateIndex] -eq [double]::PositiveInfinity) {
                                if ($candidateNonPlaneMismatchWriterNoDepthCounts.ContainsKey($writerKey)) {
                                    $candidateNonPlaneMismatchWriterNoDepthCounts[$writerKey]++
                                } else {
                                    $candidateNonPlaneMismatchWriterNoDepthCounts[$writerKey] = 1
                                }
                            } else {
                                if ($candidateNonPlaneMismatchWriterDepthWrittenCounts.ContainsKey($writerKey)) {
                                    $candidateNonPlaneMismatchWriterDepthWrittenCounts[$writerKey]++
                                } else {
                                    $candidateNonPlaneMismatchWriterDepthWrittenCounts[$writerKey] = 1
                                }
                            }
                            if ($CaptureWallBoundaryTrace) {
                                [int]$referenceFinalWriterType = [int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition]
                                [int]$referenceFinalRenderPassType = [int]$reference3D.DiagnosticFinalRenderPassTypes[$referencePosition]
                                [int]$referenceFinalWallSegmentEncoded = if ($referenceFinalWriterType -eq 2 -and $referenceFinalRenderPassType -eq 1) { $reference3D.DiagnosticFinalWallSegIndices[$referencePosition] } else { 0 }
                                [int]$referenceFinalWallSegmentIndex = if ($referenceFinalWallSegmentEncoded -gt 0) { $referenceFinalWallSegmentEncoded - 1 } else { -1 }
                                [int]$referenceFinalWallTop = if ($referenceFinalWallSegmentIndex -ge 0) { $reference3D.DiagnosticFinalWallTopRows[$referencePosition] } else { -1 }
                                [int]$referenceFinalWallBottom = if ($referenceFinalWallSegmentIndex -ge 0) { $reference3D.DiagnosticFinalWallBottomRows[$referencePosition] } else { -1 }
                                [int]$referenceFinalWallSideIndex = -1
                                [int]$referenceFinalWallFrontSectorIndex = -1
                                [int]$referenceFinalWallBackSectorIndex = -1
                                [int]$referenceFinalWallLineFlags = -1
                                [int]$referenceFinalWallTopTexture = -1
                                [int]$referenceFinalWallBottomTexture = -1
                                [int]$referenceFinalWallMiddleTexture = -1
                                [int]$referenceFinalWallFrontFloorHeightData = -1
                                [int]$referenceFinalWallFrontCeilingHeightData = -1
                                [int]$referenceFinalWallBackFloorHeightData = -1
                                [int]$referenceFinalWallBackCeilingHeightData = -1
                                if ($referenceFinalWallSegmentIndex -ge 0 -and $referenceFinalWallSegmentIndex -lt $game.World.Map.Segs.Length) {
                                    [int]$referenceFinalWallMetadataOffset = $referenceFinalWallSegmentIndex * 4
                                    $referenceFinalWallSideIndex = $context.SegmentMetadata[$referenceFinalWallMetadataOffset]
                                    $referenceFinalWallFrontSectorIndex = $context.SegmentMetadata[$referenceFinalWallMetadataOffset + 1]
                                    $referenceFinalWallBackSectorIndex = $context.SegmentMetadata[$referenceFinalWallMetadataOffset + 2]
                                    $referenceFinalWallLineFlags = $context.SegmentMetadata[$referenceFinalWallMetadataOffset + 3]
                                    $referenceFinalWallSide = $context.Sides[$referenceFinalWallSideIndex]
                                    $referenceFinalWallTopTexture = $referenceFinalWallSide.TopTexture
                                    $referenceFinalWallBottomTexture = $referenceFinalWallSide.BottomTexture
                                    $referenceFinalWallMiddleTexture = $referenceFinalWallSide.MiddleTexture
                                    $referenceFinalWallFrontFloorHeightData = $context.SectorFloorHeightData[$referenceFinalWallFrontSectorIndex]
                                    $referenceFinalWallFrontCeilingHeightData = $context.SectorCeilingHeightData[$referenceFinalWallFrontSectorIndex]
                                    if ($referenceFinalWallBackSectorIndex -ge 0) {
                                        $referenceFinalWallBackFloorHeightData = $context.SectorFloorHeightData[$referenceFinalWallBackSectorIndex]
                                        $referenceFinalWallBackCeilingHeightData = $context.SectorCeilingHeightData[$referenceFinalWallBackSectorIndex]
                                    }
                                }
                                [string]$referenceFinalWallSegmentKey = '{0}:{1}' -f $referenceFinalWriterType,$referenceFinalWallSegmentIndex
                                if (-not $candidateNonPlaneMismatchReferenceWallSegmentCounts.ContainsKey($referenceFinalWallSegmentKey)) {
                                    $candidateNonPlaneMismatchReferenceWallSegmentCounts[$referenceFinalWallSegmentKey] = @{
                                        ReferenceFinalWriterType = $referenceFinalWriterType
                                        ReferenceFinalWallSegmentIndex = $referenceFinalWallSegmentIndex
                                        ReferenceFinalWallSideIndex = $referenceFinalWallSideIndex
                                        ReferenceFinalWallFrontSectorIndex = $referenceFinalWallFrontSectorIndex
                                        ReferenceFinalWallBackSectorIndex = $referenceFinalWallBackSectorIndex
                                        ReferenceFinalWallLineFlags = $referenceFinalWallLineFlags
                                        ReferenceFinalWallTopTexture = $referenceFinalWallTopTexture
                                        ReferenceFinalWallBottomTexture = $referenceFinalWallBottomTexture
                                        ReferenceFinalWallMiddleTexture = $referenceFinalWallMiddleTexture
                                        ReferenceFinalWallFrontFloorHeightData = $referenceFinalWallFrontFloorHeightData
                                        ReferenceFinalWallFrontCeilingHeightData = $referenceFinalWallFrontCeilingHeightData
                                        ReferenceFinalWallBackFloorHeightData = $referenceFinalWallBackFloorHeightData
                                        ReferenceFinalWallBackCeilingHeightData = $referenceFinalWallBackCeilingHeightData
                                        MismatchPixels = 0
                                        Examples = [Collections.Generic.List[object]]::new()
                                    }
                                }
                                $referenceFinalWallEntry = $candidateNonPlaneMismatchReferenceWallSegmentCounts[$referenceFinalWallSegmentKey]
                                $referenceFinalWallEntry.MismatchPixels++
                                if ($referenceFinalWallEntry.Examples.Count -lt 8) {
                                    $referenceFinalWallEntry.Examples.Add([ordered]@{
                                        X = $x
                                        Y = $y
                                        ReferenceFinalWallWriteTop = $referenceFinalWallTop
                                        ReferenceFinalWallWriteBottom = $referenceFinalWallBottom
                                        ReferenceWriteIntervalContainsPixel = ($y -ge $referenceFinalWallTop -and $y -le $referenceFinalWallBottom)
                                    })
                                }
                                [int]$candidateDepthOwnerEncoded = $context.DiagnosticDepthOwnerSegIndices[$candidateIndex]
                                [int]$candidateDepthOwnerSegmentIndex = if ($candidateDepthOwnerEncoded -gt 0) { $candidateDepthOwnerEncoded - 1 } else { -1 }
                                [int]$candidateDepthOwnerWriterType = $context.DiagnosticDepthOwnerWriterTypes[$candidateIndex]
                                [int]$candidateDepthOwnerSideIndex = -1
                                [int]$candidateDepthOwnerFrontSectorIndex = -1
                                [int]$candidateDepthOwnerBackSectorIndex = -1
                                [int]$candidateDepthOwnerLineFlags = -1
                                [int]$candidateDepthOwnerTopTexture = -1
                                [int]$candidateDepthOwnerBottomTexture = -1
                                [int]$candidateDepthOwnerMiddleTexture = -1
                                [int]$candidateDepthOwnerFrontFloorHeightData = -1
                                [int]$candidateDepthOwnerFrontCeilingHeightData = -1
                                [int]$candidateDepthOwnerBackFloorHeightData = -1
                                [int]$candidateDepthOwnerBackCeilingHeightData = -1
                                if ($candidateDepthOwnerSegmentIndex -ge 0 -and $candidateDepthOwnerSegmentIndex -lt $game.World.Map.Segs.Length) {
                                    [int]$candidateDepthOwnerMetadataOffset = $candidateDepthOwnerSegmentIndex * 4
                                    $candidateDepthOwnerSideIndex = $context.SegmentMetadata[$candidateDepthOwnerMetadataOffset]
                                    $candidateDepthOwnerFrontSectorIndex = $context.SegmentMetadata[$candidateDepthOwnerMetadataOffset + 1]
                                    $candidateDepthOwnerBackSectorIndex = $context.SegmentMetadata[$candidateDepthOwnerMetadataOffset + 2]
                                    $candidateDepthOwnerLineFlags = $context.SegmentMetadata[$candidateDepthOwnerMetadataOffset + 3]
                                    $candidateDepthOwnerSide = $context.Sides[$candidateDepthOwnerSideIndex]
                                    $candidateDepthOwnerTopTexture = $candidateDepthOwnerSide.TopTexture
                                    $candidateDepthOwnerBottomTexture = $candidateDepthOwnerSide.BottomTexture
                                    $candidateDepthOwnerMiddleTexture = $candidateDepthOwnerSide.MiddleTexture
                                    $candidateDepthOwnerFrontFloorHeightData = $context.SectorFloorHeightData[$candidateDepthOwnerFrontSectorIndex]
                                    $candidateDepthOwnerFrontCeilingHeightData = $context.SectorCeilingHeightData[$candidateDepthOwnerFrontSectorIndex]
                                    if ($candidateDepthOwnerBackSectorIndex -ge 0) {
                                        $candidateDepthOwnerBackFloorHeightData = $context.SectorFloorHeightData[$candidateDepthOwnerBackSectorIndex]
                                        $candidateDepthOwnerBackCeilingHeightData = $context.SectorCeilingHeightData[$candidateDepthOwnerBackSectorIndex]
                                    }
                                }
                                [string]$candidateDepthOwnerKey = '{0}:{1}:{2}' -f $writerKey,$candidateDepthOwnerWriterType,$candidateDepthOwnerSegmentIndex
                                if (-not $candidateNonPlaneMismatchDepthOwnerCounts.ContainsKey($candidateDepthOwnerKey)) {
                                    $candidateNonPlaneMismatchDepthOwnerCounts[$candidateDepthOwnerKey] = @{
                                        ReferenceFinalWriterType = [int]$writerKey
                                        CandidateDepthOwnerWriterType = $candidateDepthOwnerWriterType
                                        CandidateDepthOwnerSegmentIndex = $candidateDepthOwnerSegmentIndex
                                        CandidateDepthOwnerSideIndex = $candidateDepthOwnerSideIndex
                                        CandidateDepthOwnerFrontSectorIndex = $candidateDepthOwnerFrontSectorIndex
                                        CandidateDepthOwnerBackSectorIndex = $candidateDepthOwnerBackSectorIndex
                                        CandidateDepthOwnerLineFlags = $candidateDepthOwnerLineFlags
                                        CandidateDepthOwnerTopTexture = $candidateDepthOwnerTopTexture
                                        CandidateDepthOwnerBottomTexture = $candidateDepthOwnerBottomTexture
                                        CandidateDepthOwnerMiddleTexture = $candidateDepthOwnerMiddleTexture
                                        CandidateDepthOwnerFrontFloorHeightData = $candidateDepthOwnerFrontFloorHeightData
                                        CandidateDepthOwnerFrontCeilingHeightData = $candidateDepthOwnerFrontCeilingHeightData
                                        CandidateDepthOwnerBackFloorHeightData = $candidateDepthOwnerBackFloorHeightData
                                        CandidateDepthOwnerBackCeilingHeightData = $candidateDepthOwnerBackCeilingHeightData
                                        MismatchPixels = 0
                                        Examples = [Collections.Generic.List[object]]::new()
                                    }
                                }
                                $depthOwnerEntry = $candidateNonPlaneMismatchDepthOwnerCounts[$candidateDepthOwnerKey]
                                $depthOwnerEntry.MismatchPixels++
                                if ($depthOwnerEntry.Examples.Count -lt 8) {
                                    $candidateDepthOwnerTrace = $null
                                    if ($candidateDepthOwnerSegmentIndex -ge 0 -and $candidateDepthOwnerSegmentIndex -lt $game.World.Map.Segs.Length) {
                                        [int]$candidateDepthOwnerTraceCell = $candidateDepthOwnerSegmentIndex * 320 + $x
                                        if ($candidateDepthOwnerTraceCell -lt $context.DiagnosticWallSpanTraceSeen.Length -and
                                            $context.DiagnosticWallSpanTraceSeen[$candidateDepthOwnerTraceCell] -eq 1) {
                                            [int]$candidateDepthOwnerTraceOffset = $candidateDepthOwnerTraceCell * 12
                                            [int[]]$candidateDepthOwnerTraceData = $context.DiagnosticWallSpanTrace
                                            $candidateDepthOwnerTrace = [ordered]@{
                                                WallTop = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset]
                                                WallBottom = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 1]
                                                ClipTop = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 2]
                                                ClipBottom = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 3]
                                                PortalTop = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 4]
                                                PortalBottom = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 5]
                                                UpperBandTop = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 6]
                                                UpperBandBottom = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 7]
                                                LowerBandTop = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 8]
                                                LowerBandBottom = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 9]
                                                MaskedMiddleBandTop = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 10]
                                                MaskedMiddleBandBottom = $candidateDepthOwnerTraceData[$candidateDepthOwnerTraceOffset + 11]
                                            }
                                        }
                                    }
                                    [int]$referenceOwnerSectorForExample = -1
                                    if ([int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition] -eq 1 -and $null -ne $referenceOwner) {
                                        for ($sectorForExample = 0; $sectorForExample -lt $game.World.Map.Sectors.Length; $sectorForExample++) {
                                            if ([object]::ReferenceEquals($referenceOwner, $game.World.Map.Sectors[$sectorForExample])) {
                                                $referenceOwnerSectorForExample = $sectorForExample
                                                break
                                            }
                                        }
                                    }
                                    $depthOwnerEntry.Examples.Add([ordered]@{
                                        X = $x
                                        Y = $y
                                        CandidateFramebufferColor = [byte]$candidate[$candidateIndex]
                                        ReferenceFramebufferColor = [byte]$referencePixels[$referencePosition]
                                        CandidateDepth = if ($context.Depth[$candidateIndex] -eq [double]::PositiveInfinity) { 'PositiveInfinity' } else { $context.Depth[$candidateIndex] }
                                        CandidateDepthOwnerTrace = $candidateDepthOwnerTrace
                                        CandidateWallSampleTextureId = $context.DiagnosticWallSampleTextureIds[$candidateIndex]
                                        CandidateWallSampleBand = $context.DiagnosticWallSampleBands[$candidateIndex]
                                        CandidateWallSampleColumn = $context.DiagnosticWallSampleColumns[$candidateIndex]
                                        CandidateWallSampleRow = $context.DiagnosticWallSampleRows[$candidateIndex]
                                        CandidateWallSampleFraction = $context.DiagnosticWallSampleFractions[$candidateIndex]
                                        CandidateWallSampleOrigin = $context.DiagnosticWallSampleOrigins[$candidateIndex]
                                        CandidateWallSampleTexelStep = $context.DiagnosticWallSampleTexelSteps[$candidateIndex]
                                        CandidateWallSampleTextureHeight = $context.DiagnosticWallSampleTextureHeights[$candidateIndex]
                                        CandidateWallSampleSourceColor = $context.DiagnosticWallSampleSourceColors[$candidateIndex]
                                        CandidateWallSampleMappedColor = $context.DiagnosticWallSampleMappedColors[$candidateIndex]
                                        CandidateWallSampleLightIndex = $context.DiagnosticWallSampleLightIndexes[$candidateIndex]
                                        ReferenceFinalWallWriterType = $referenceFinalWriterType
                                        ReferenceFinalRenderPassType = $referenceFinalRenderPassType
                                        ReferenceFinalWorldSpriteDescription = if ($referenceFinalRenderPassType -eq 2) { $reference3D.DiagnosticFinalWorldSpriteDescriptions[$referencePosition] } else { $null }
                                        ReferenceFinalWallSegmentIndex = $referenceFinalWallSegmentIndex
                                        ReferenceFinalWallWriteTop = $referenceFinalWallTop
                                        ReferenceFinalWallWriteBottom = $referenceFinalWallBottom
                                        ReferenceFinalWallSideIndex = $referenceFinalWallSideIndex
                                        ReferenceFinalWallFrontSectorIndex = $referenceFinalWallFrontSectorIndex
                                        ReferenceFinalWallBackSectorIndex = $referenceFinalWallBackSectorIndex
                                        ReferenceFinalWallLineFlags = $referenceFinalWallLineFlags
                                        ReferenceFinalWallTopTexture = $referenceFinalWallTopTexture
                                        ReferenceFinalWallBottomTexture = $referenceFinalWallBottomTexture
                                        ReferenceFinalWallMiddleTexture = $referenceFinalWallMiddleTexture
                                        ReferenceFinalWallFrontFloorHeightData = $referenceFinalWallFrontFloorHeightData
                                        ReferenceFinalWallFrontCeilingHeightData = $referenceFinalWallFrontCeilingHeightData
                                        ReferenceFinalWallBackFloorHeightData = $referenceFinalWallBackFloorHeightData
                                        ReferenceFinalWallBackCeilingHeightData = $referenceFinalWallBackCeilingHeightData
                                        ReferenceFinalWallTextureRow = if ($referenceFinalWallSegmentIndex -ge 0) { $reference3D.DiagnosticFinalWallTextureRows[$referencePosition] } else { -1 }
                                        ReferenceFinalWallTextureFraction = if ($referenceFinalWallSegmentIndex -ge 0) { $reference3D.DiagnosticFinalWallTextureFractions[$referencePosition] } else { -1 }
                                        ReferenceFinalWallSourceColor = if ($referenceFinalWallSegmentIndex -ge 0) { $reference3D.DiagnosticFinalWallSourceColors[$referencePosition] } else { -1 }
                                        ReferenceFinalWallMappedColor = if ($referenceFinalWallSegmentIndex -ge 0) { $reference3D.DiagnosticFinalWallMappedColors[$referencePosition] } else { -1 }
                                        ReferencePlaneOwnerSectorIndex = $referenceOwnerSectorForExample
                                        ReferencePlaneSurfaceType = if ([int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition] -eq 1) { [int]$reference3D.DiagnosticPlaneSurfaceTypes[$referencePosition] } else { 0 }
                                        ReferencePlaneSampleXFracData = if ([int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition] -eq 1) { [int]$reference3D.DiagnosticPlaneXFracData[$referencePosition] } else { 0 }
                                        ReferencePlaneSampleYFracData = if ([int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition] -eq 1) { [int]$reference3D.DiagnosticPlaneYFracData[$referencePosition] } else { 0 }
                                        ReferencePlaneSampleDistanceData = if ([int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition] -eq 1) { [int]$reference3D.DiagnosticPlaneDistanceData[$referencePosition] } else { 0 }
                                    })
                                }
                            }
                            [string]$renderPassKey = [string][int]$reference3D.DiagnosticFinalRenderPassTypes[$referencePosition]
                            if ($candidateNonPlaneMismatchFinalRenderPassCounts.ContainsKey($renderPassKey)) {
                                $candidateNonPlaneMismatchFinalRenderPassCounts[$renderPassKey]++
                            } else {
                                $candidateNonPlaneMismatchFinalRenderPassCounts[$renderPassKey] = 1
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
                                        if ($CaptureWallBoundaryTrace) {
                                            $candidatePlaneMismatchOwnerSegmentCounts.DifferentOwnerPlanePixels++
                                            [int]$ownerSegmentEncoded = $context.DiagnosticPlaneOwnerSegIndices[$candidateIndex]
                                            [int]$ownerSegmentIndex = $ownerSegmentEncoded - 1
                                            [int]$ownerSegmentSideIndex = -1
                                            [int]$ownerSegmentFrontSectorIndex = -1
                                            [int]$ownerSegmentBackSectorIndex = -1
                                            [int]$ownerSegmentLineFlags = -1
                                            $ownerSegmentTrace = $null
                                            $ownerSegmentPosition = $null
                                            $candidateMismatchPlaneSample = Get-FastPlaneSample $context $x $y $planeId $candidateViewXData $candidateViewYData $candidateViewZData $candidateViewAngleData $candidateExtraLight $candidateFixedColorMap
                                            [double]$candidatePlaneSampleWorldX = $candidateMismatchPlaneSample.XFracData / 65536.0
                                            [double]$candidatePlaneSampleWorldY = $candidateMismatchPlaneSample.YFracData / 65536.0
                                            [int]$referencePlaneSampleDistanceData = $reference3D.DiagnosticPlaneDistanceData[$referencePosition]
                                            [int]$referencePlaneSampleXFracData = $reference3D.DiagnosticPlaneXFracData[$referencePosition]
                                            [int]$referencePlaneSampleYFracData = $reference3D.DiagnosticPlaneYFracData[$referencePosition]
                                            [int]$referencePlaneSampleTexelIndex = $reference3D.DiagnosticPlaneTexelIndices[$referencePosition]
                                            [byte]$referencePlaneSampleColor = $referencePixels[$referencePosition]
                                            [int]$candidatePlaneSampleOriginX = $candidateMismatchPlaneSample.SampleOriginX
                                            [int]$referencePlaneSampleOriginX = $reference3D.DiagnosticPlaneSampleOriginX[$referencePosition]
                                            [int]$candidateReferenceOriginXFrac = $candidateMismatchPlaneSample.XFracData
                                            [int]$candidateReferenceOriginYFrac = $candidateMismatchPlaneSample.YFracData
                                            [int]$candidateReferenceOriginFlatTexelIndex = $candidateMismatchPlaneSample.FlatTexelIndex
                                            [byte]$candidateReferenceOriginColor = $candidateMismatchPlaneSample.Color
                                            if ($referencePlaneSampleOriginX -ge 0 -and $referencePlaneSampleOriginX -lt 320) {
                                                [long]$candidateReferenceOriginLengthData = ([long]$candidateMismatchPlaneSample.DistanceData *
                                                    [long]$context.PlaneDistanceScales[$referencePlaneSampleOriginX]) -shr 16
                                                [long]$candidateReferenceOriginXFracWide = [long]$candidateViewXData +
                                                    (([long]$context.RayCos[$referencePlaneSampleOriginX] * $candidateReferenceOriginLengthData) -shr 16)
                                                [long]$candidateReferenceOriginYFracWide = -[long]$candidateViewYData -
                                                    (([long]$context.RaySin[$referencePlaneSampleOriginX] * $candidateReferenceOriginLengthData) -shr 16)
                                                $candidateReferenceOriginXFracWide += [long]$candidateMismatchPlaneSample.StepX * ($x - $referencePlaneSampleOriginX)
                                                $candidateReferenceOriginYFracWide += [long]$candidateMismatchPlaneSample.StepY * ($x - $referencePlaneSampleOriginX)
                                                [int]$candidateReferenceOriginXFrac = [int]($candidateReferenceOriginXFracWide -band 0xFFFFFFFFL)
                                                [int]$candidateReferenceOriginYFrac = [int]($candidateReferenceOriginYFracWide -band 0xFFFFFFFFL)
                                                [int]$candidateReferenceTextureX = ($candidateReferenceOriginXFrac -shr 16) -band 63
                                                [int]$candidateReferenceTextureY = ((($candidateReferenceOriginYFrac -shr 10) -band 4032) -shr 6)
                                                [int]$candidateReferenceOriginFlatTexelIndex = $context.PlaneFlatData[$candidateMismatchPlaneSample.FlatIndex][($candidateReferenceTextureY -shl 6) + $candidateReferenceTextureX]
                                                [byte]$candidateReferenceOriginColor = $context.Colors[$candidateMismatchPlaneSample.LightMapIndex][$candidateReferenceOriginFlatTexelIndex]
                                            }
                                            if ($candidateMismatchPlaneSample.DistanceData -eq $referencePlaneSampleDistanceData) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferencePlaneSameDistance++
                                            }
                                            if ($candidateMismatchPlaneSample.XFracData -eq $referencePlaneSampleXFracData) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferencePlaneSameXFraction++
                                            }
                                            if ($candidateMismatchPlaneSample.YFracData -eq $referencePlaneSampleYFracData) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferencePlaneSameYFraction++
                                            }
                                            if ($candidateMismatchPlaneSample.TextureX -eq (($referencePlaneSampleXFracData -shr 16) -band 63) -and
                                                $candidateMismatchPlaneSample.TextureY -eq (((($referencePlaneSampleYFracData -shr 10) -band 4032) -shr 6))) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferencePlaneSameTextureCoordinates++
                                            }
                                            if ($candidateMismatchPlaneSample.FlatTexelIndex -eq $referencePlaneSampleTexelIndex) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferencePlaneSameFlatTexel++
                                            }
                                            if ($candidateMismatchPlaneSample.Color -eq $referencePlaneSampleColor) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferencePlaneSameColor++
                                            }
                                            if ($candidateReferenceOriginXFrac -eq $referencePlaneSampleXFracData) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferenceOriginSameXFraction++
                                            }
                                            if ($candidateReferenceOriginYFrac -eq $referencePlaneSampleYFracData) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferenceOriginSameYFraction++
                                            }
                                            if ($candidateReferenceOriginXFrac -eq $referencePlaneSampleXFracData -and
                                                $candidateReferenceOriginYFrac -eq $referencePlaneSampleYFracData) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferenceOriginSameTextureCoordinates++
                                            }
                                            if ($candidateReferenceOriginFlatTexelIndex -eq $referencePlaneSampleTexelIndex) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferenceOriginSameFlatTexel++
                                            }
                                            if ($candidateReferenceOriginColor -eq $referencePlaneSampleColor) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidateReferenceOriginSameColor++
                                            }
                                            $candidatePlaneSampleSubsector = [Geometry]::PointInSubsector(
                                                [Fixed]::new([int]$candidateMismatchPlaneSample.XFracData),
                                                [Fixed]::new([int]$candidateMismatchPlaneSample.YFracData),
                                                $game.World.Map)
                                            [int]$candidatePlaneSampleMapSectorIndex = -1
                                            for ($sampleSectorIndex = 0; $sampleSectorIndex -lt $game.World.Map.Sectors.Length; $sampleSectorIndex++) {
                                                if ([object]::ReferenceEquals($candidatePlaneSampleSubsector.Sector, $game.World.Map.Sectors[$sampleSectorIndex])) {
                                                    $candidatePlaneSampleMapSectorIndex = $sampleSectorIndex
                                                    break
                                                }
                                            }
                                            if ($candidatePlaneSampleMapSectorIndex -eq $candidateSectorIndex) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneSampleMapSectorMatchesPlane++
                                            }
                                            if ($candidatePlaneSampleMapSectorIndex -eq $referenceOwnerSectorIndex) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneSampleMapSectorMatchesReferenceOwner++
                                            }
                                            if ($candidatePlaneSampleMapSectorIndex -ne $candidateSectorIndex -and
                                                $candidatePlaneSampleMapSectorIndex -ne $referenceOwnerSectorIndex) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneSampleMapSectorMatchesNeitherOwner++
                                            }
                                            $referencePlaneSampleSubsector = [Geometry]::PointInSubsector(
                                                [Fixed]::new([int]$reference3D.DiagnosticPlaneXFracData[$referencePosition]),
                                                [Fixed]::new([int]$reference3D.DiagnosticPlaneYFracData[$referencePosition]),
                                                $game.World.Map)
                                            [int]$referencePlaneSampleMapSectorIndex = -1
                                            for ($sampleSectorIndex = 0; $sampleSectorIndex -lt $game.World.Map.Sectors.Length; $sampleSectorIndex++) {
                                                if ([object]::ReferenceEquals($referencePlaneSampleSubsector.Sector, $game.World.Map.Sectors[$sampleSectorIndex])) {
                                                    $referencePlaneSampleMapSectorIndex = $sampleSectorIndex
                                                    break
                                                }
                                            }
                                            if ($referencePlaneSampleMapSectorIndex -eq $candidateSectorIndex) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.ReferencePlaneSampleMapSectorMatchesPlane++
                                            }
                                            if ($referencePlaneSampleMapSectorIndex -eq $referenceOwnerSectorIndex) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.ReferencePlaneSampleMapSectorMatchesReferenceOwner++
                                            }
                                            if ($referencePlaneSampleMapSectorIndex -ne $candidateSectorIndex -and
                                                $referencePlaneSampleMapSectorIndex -ne $referenceOwnerSectorIndex) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.ReferencePlaneSampleMapSectorMatchesNeitherOwner++
                                            }
                                            if ($ownerSegmentEncoded -le 0 -or $ownerSegmentIndex -ge $game.World.Map.Segs.Length) {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentMissing++
                                            } else {
                                                $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentFound++
                                                [int]$ownerSegmentMetadataOffset = $ownerSegmentIndex * 4
                                                $ownerSegmentSideIndex = $context.SegmentMetadata[$ownerSegmentMetadataOffset]
                                                $ownerSegmentFrontSectorIndex = $context.SegmentMetadata[$ownerSegmentMetadataOffset + 1]
                                                $ownerSegmentBackSectorIndex = $context.SegmentMetadata[$ownerSegmentMetadataOffset + 2]
                                                $ownerSegmentLineFlags = $context.SegmentMetadata[$ownerSegmentMetadataOffset + 3]
                                                [int]$ownerSegmentGeometryOffset = $ownerSegmentIndex * 6
                                                [double]$ownerSegmentX1 = $context.SegmentGeometry[$ownerSegmentGeometryOffset]
                                                [double]$ownerSegmentY1 = $context.SegmentGeometry[$ownerSegmentGeometryOffset + 1]
                                                [double]$ownerSegmentX2 = $context.SegmentGeometry[$ownerSegmentGeometryOffset + 2]
                                                [double]$ownerSegmentY2 = $context.SegmentGeometry[$ownerSegmentGeometryOffset + 3]
                                                [double]$ownerSegmentDx = $ownerSegmentX2 - $ownerSegmentX1
                                                [double]$ownerSegmentDy = $ownerSegmentY2 - $ownerSegmentY1
                                                [double]$ownerSegmentLengthSquared = $ownerSegmentDx * $ownerSegmentDx + $ownerSegmentDy * $ownerSegmentDy
                                                [double]$ownerSegmentCameraParameter = (($candidateCamera.X - $ownerSegmentX1) * $ownerSegmentDx +
                                                    ($candidateCamera.Y - $ownerSegmentY1) * $ownerSegmentDy) / $ownerSegmentLengthSquared
                                                [double]$ownerSegmentSampleParameter = (($candidatePlaneSampleWorldX - $ownerSegmentX1) * $ownerSegmentDx +
                                                    ($candidatePlaneSampleWorldY - $ownerSegmentY1) * $ownerSegmentDy) / $ownerSegmentLengthSquared
                                                [double]$ownerSegmentCameraCross = $ownerSegmentDx * ($candidateCamera.Y - $ownerSegmentY1) -
                                                    $ownerSegmentDy * ($candidateCamera.X - $ownerSegmentX1)
                                                [double]$ownerSegmentSampleCross = $ownerSegmentDx * ($candidatePlaneSampleWorldY - $ownerSegmentY1) -
                                                    $ownerSegmentDy * ($candidatePlaneSampleWorldX - $ownerSegmentX1)
                                                [bool]$sampleOppositeOwnerSegmentSide = $ownerSegmentCameraCross * $ownerSegmentSampleCross -lt 0
                                                if ([Math]::Abs($ownerSegmentSampleCross) -lt 0.000001) {
                                                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneSampleOnOwnerSegmentLine++
                                                } elseif ($sampleOppositeOwnerSegmentSide) {
                                                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneSampleOppositeOwnerSegmentSide++
                                                } else {
                                                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneSampleSameOwnerSegmentSide++
                                                }
                                                [bool]$sampleProjectionWithinOwnerSegment = $ownerSegmentSampleParameter -ge 0 -and $ownerSegmentSampleParameter -le 1
                                                if ($sampleProjectionWithinOwnerSegment) {
                                                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneSampleProjectionWithinOwnerSegment++
                                                } else {
                                                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneSampleProjectionOutsideOwnerSegment++
                                                }
                                                $ownerSegmentPosition = [ordered]@{
                                                    Vertex1X = $ownerSegmentX1
                                                    Vertex1Y = $ownerSegmentY1
                                                    Vertex2X = $ownerSegmentX2
                                                    Vertex2Y = $ownerSegmentY2
                                                    CameraSideCrossProduct = $ownerSegmentCameraCross
                                                    PlaneSampleSideCrossProduct = $ownerSegmentSampleCross
                                                    PlaneSampleOppositeCameraSide = $sampleOppositeOwnerSegmentSide
                                                    CameraProjectionParameter = $ownerSegmentCameraParameter
                                                    PlaneSampleProjectionParameter = $ownerSegmentSampleParameter
                                                    PlaneSampleProjectionWithinSegment = $sampleProjectionWithinOwnerSegment
                                                    PlaneSampleWorldX = $candidatePlaneSampleWorldX
                                                    PlaneSampleWorldY = $candidatePlaneSampleWorldY
                                                }
                                                if ($ownerSegmentFrontSectorIndex -eq $candidateSectorIndex) {
                                                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentFrontMatchesPlane++
                                                }
                                                [int]$ownerSegmentTraceCell = $ownerSegmentIndex * 320 + $x
                                                if ($ownerSegmentTraceCell -ge $context.DiagnosticWallSpanTraceSeen.Length -or
                                                    $context.DiagnosticWallSpanTraceSeen[$ownerSegmentTraceCell] -eq 0) {
                                                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentTraceMissing++
                                                } else {
                                                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentTraceFound++
                                                    [int]$ownerSegmentTraceOffset = $ownerSegmentTraceCell * 12
                                                    [int[]]$ownerSegmentWallTrace = $context.DiagnosticWallSpanTrace
                                                    $ownerSegmentTrace = [ordered]@{
                                                        WallTop = $ownerSegmentWallTrace[$ownerSegmentTraceOffset]
                                                        WallBottom = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 1]
                                                        ClipTop = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 2]
                                                        ClipBottom = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 3]
                                                        PortalTop = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 4]
                                                        PortalBottom = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 5]
                                                        UpperBandTop = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 6]
                                                        UpperBandBottom = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 7]
                                                        LowerBandTop = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 8]
                                                        LowerBandBottom = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 9]
                                                        MiddleBandTop = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 10]
                                                        MiddleBandBottom = $ownerSegmentWallTrace[$ownerSegmentTraceOffset + 11]
                                                    }
                                                }
                                            }
                                            if ($candidatePlaneMismatchDifferentOwnerExamples.Count -lt 64) {
                                                [int]$candidatePlaneFlatIndex = if ($candidateSurfaceName -eq 'Floor') { $context.SectorFloorFlatIndex[$candidateSectorIndex] } else { $context.SectorCeilingFlatIndex[$candidateSectorIndex] }
                                                [int]$candidatePlaneHeightData = if ($candidateSurfaceName -eq 'Floor') { $context.SectorFloorHeightData[$candidateSectorIndex] } else { $context.SectorCeilingHeightData[$candidateSectorIndex] }
                                                [int]$candidatePlaneLightLevel = $context.SectorLightLevels[$candidateSectorIndex]
                                                $referenceRowTrace = [Collections.Generic.List[object]]::new()
                                                [int]$referenceStartX = [Math]::Max(0, [Math]::Min($candidatePlaneSampleOriginX, [int]$reference3D.DiagnosticPlaneSampleOriginX[$referencePosition]) - 2)
                                                for ([int]$referenceTraceX = $referenceStartX; $referenceTraceX -le $x; $referenceTraceX++) {
                                                    [int]$referenceTracePosition = $referenceTraceX * 200 + $y
                                                    if ([int]$reference3D.DiagnosticFinalWriterTypes[$referenceTracePosition] -ne 1) { continue }
                                                    [int]$referenceTraceOwnerSectorIndex = -1
                                                    $referenceTraceOwner = $reference3D.DiagnosticPlaneOwners[$referenceTracePosition]
                                                    for ([int]$referenceTraceSectorIndex = 0; $referenceTraceSectorIndex -lt $game.World.Map.Sectors.Length; $referenceTraceSectorIndex++) {
                                                        if ([object]::ReferenceEquals($referenceTraceOwner, $game.World.Map.Sectors[$referenceTraceSectorIndex])) {
                                                            $referenceTraceOwnerSectorIndex = $referenceTraceSectorIndex
                                                            break
                                                        }
                                                    }
                                                    [int]$referenceTraceCandidatePlaneId = $context.Planes[$y * 320 + $referenceTraceX]
                                                    [int]$referenceTraceCandidateOrigin = $context.PlaneSampleOriginX[$y * 320 + $referenceTraceX]
                                                    $referenceRowTrace.Add([ordered]@{
                                                        X = $referenceTraceX
                                                        ReferenceOwnerSectorIndex = $referenceTraceOwnerSectorIndex
                                                        ReferenceSurfaceType = [int]$reference3D.DiagnosticPlaneSurfaceTypes[$referenceTracePosition]
                                                        ReferencePlaneSampleOriginX = [int]$reference3D.DiagnosticPlaneSampleOriginX[$referenceTracePosition]
                                                        ReferenceReusedPreviousColumn = ([int]$reference3D.DiagnosticPlaneSampleReusedPreviousColumn[$referenceTracePosition] -eq 1)
                                                        ReferenceTexel = [int]$reference3D.DiagnosticPlaneTexelIndices[$referenceTracePosition]
                                                        ReferenceColor = [byte]$referencePixels[$referenceTracePosition]
                                                        CandidatePlaneId = $referenceTraceCandidatePlaneId
                                                        CandidatePlaneSampleOriginX = $referenceTraceCandidateOrigin
                                                        CandidateColor = [byte]$candidate[$y * 320 + $referenceTraceX]
                                                    })
                                                }
                                                $planeSampleCallTrace = [Collections.Generic.List[object]]::new()
                                                [int]$traceStartX = [Math]::Max(0, $candidatePlaneSampleOriginX - 2)
                                                [int[]]$traceCalls = $context.PlaneSampleCalls
                                                for ([int]$traceOffset = 0; $traceOffset -lt $context.PlaneSampleCallCount; $traceOffset += 4) {
                                                    [int]$traceX = $traceCalls[$traceOffset]
                                                    [int]$traceY1 = $traceCalls[$traceOffset + 1]
                                                    [int]$traceY2 = $traceCalls[$traceOffset + 2]
                                                    if ($traceX -lt $traceStartX -or $traceX -gt $x -or $y -lt $traceY1 -or $y -gt $traceY2) { continue }
                                                    [int]$tracePlaneId = $traceCalls[$traceOffset + 3]
                                                    [int]$traceSectorIndex = ($tracePlaneId - 1) -shr 1
                                                    [bool]$traceIsFloor = (($tracePlaneId -band 1) -eq 0)
                                                    [string]$traceSurface = if ($traceIsFloor) { 'Floor' } else { 'Ceiling' }
                                                    [int]$traceHeightData = if ($traceIsFloor) { $context.SectorFloorHeightData[$traceSectorIndex] } else { $context.SectorCeilingHeightData[$traceSectorIndex] }
                                                    [int]$traceFlatIndex = if ($traceIsFloor) { $context.SectorFloorFlatIndex[$traceSectorIndex] } else { $context.SectorCeilingFlatIndex[$traceSectorIndex] }
                                                    [int]$traceLightLevel = $context.SectorLightLevels[$traceSectorIndex]
                                                    [int]$traceFinalPlaneId = $context.Planes[$y * 320 + $traceX]
                                                    $planeSampleCallTrace.Add([ordered]@{
                                                        CallIndex = $traceOffset -shr 2
                                                        X = $traceX
                                                        Y1 = $traceY1
                                                        Y2 = $traceY2
                                                        PlaneId = $tracePlaneId
                                                        SectorIndex = $traceSectorIndex
                                                        Surface = $traceSurface
                                                        HeightData = $traceHeightData
                                                        FlatIndex = $traceFlatIndex
                                                        LightLevel = $traceLightLevel
                                                        FinalPlaneIdAtRow = $traceFinalPlaneId
                                                        IsFinalOwnerAtRow = ($traceFinalPlaneId -eq $tracePlaneId)
                                                        MatchesCandidatePlaneKey = ($traceSurface -eq $candidateSurfaceName -and $traceHeightData -eq $candidatePlaneHeightData -and $traceFlatIndex -eq $candidatePlaneFlatIndex -and $traceLightLevel -eq $candidatePlaneLightLevel)
                                                    })
                                                }
                                                [int]$referenceOwnerFlatIndex = -1
                                                [int]$referenceOwnerLightLevel = -1
                                                [int]$referenceOwnerHeightData = -1
                                                if ($referenceOwnerSectorIndex -ge 0) {
                                                    $referenceOwnerSector = $game.World.Map.Sectors[$referenceOwnerSectorIndex]
                                                    $referenceOwnerLightLevel = [int]$referenceOwnerSector.LightLevel
                                                    if ($referenceSurfaceName -eq 'Floor') {
                                                        $referenceOwnerFlatIndex = [int]$game.World.Specials.FlatTranslation[$referenceOwnerSector.FloorFlat]
                                                        $referenceOwnerHeightData = $context.SectorFloorHeightData[$referenceOwnerSectorIndex]
                                                    } else {
                                                        $referenceOwnerFlatIndex = [int]$game.World.Specials.FlatTranslation[$referenceOwnerSector.CeilingFlat]
                                                        $referenceOwnerHeightData = $context.SectorCeilingHeightData[$referenceOwnerSectorIndex]
                                                    }
                                                }
                                                $candidatePlaneMismatchDifferentOwnerExamples.Add([ordered]@{
                                                    X = $x
                                                    Y = $y
                                                    CandidatePlaneId = $planeId
                                                    CandidatePlaneSectorIndex = $candidateSectorIndex
                                                    CandidatePlaneSurface = $candidateSurfaceName
                                                    CandidatePlaneHeightData = $candidatePlaneHeightData
                                                    CandidatePlaneFlatIndex = $candidatePlaneFlatIndex
                                                    CandidatePlaneLightLevel = $candidatePlaneLightLevel
                                                    ReferenceRowTrace = $referenceRowTrace.ToArray()
                                                    CandidatePlaneSampleCallTrace = $planeSampleCallTrace.ToArray()
                                                    ReferencePlaneOwnerSectorIndex = $referenceOwnerSectorIndex
                                                    ReferencePlaneSurface = $referenceSurfaceName
                                                    ReferencePlaneHeightData = $referenceOwnerHeightData
                                                    ReferencePlaneFlatIndex = $referenceOwnerFlatIndex
                                                    ReferencePlaneLightLevel = $referenceOwnerLightLevel
                                                    CandidateReferencePlaneKeyMatches = ($candidateSurfaceName -eq $referenceSurfaceName -and $candidatePlaneHeightData -eq $referenceOwnerHeightData -and $candidatePlaneFlatIndex -eq $referenceOwnerFlatIndex -and $candidatePlaneLightLevel -eq $referenceOwnerLightLevel)
                                                    ReferenceFinalWriterType = [int]$reference3D.DiagnosticFinalWriterTypes[$referencePosition]
                                                    ReferenceFinalRenderPassType = [int]$reference3D.DiagnosticFinalRenderPassTypes[$referencePosition]
                                                    CandidateDepth = if ($context.Depth[$candidateIndex] -eq [double]::PositiveInfinity) { 'PositiveInfinity' } else { $context.Depth[$candidateIndex] }
                                                    CandidatePlaneOwnerSegmentIndex = if ($ownerSegmentEncoded -gt 0) { $ownerSegmentIndex } else { -1 }
                                                    CandidatePlaneOwnerSegmentSideIndex = $ownerSegmentSideIndex
                                                    CandidatePlaneOwnerSegmentFrontSectorIndex = $ownerSegmentFrontSectorIndex
                                                    CandidatePlaneOwnerSegmentBackSectorIndex = $ownerSegmentBackSectorIndex
                                                    CandidatePlaneOwnerSegmentLineFlags = $ownerSegmentLineFlags
                                                    CandidatePlaneOwnerSegmentFrontMatchesPlane = ($ownerSegmentFrontSectorIndex -eq $candidateSectorIndex)
                                                    CandidatePlaneOwnerSegmentTrace = $ownerSegmentTrace
                                                    CandidatePlaneOwnerSegmentPosition = $ownerSegmentPosition
                                                    CandidatePlaneSampleMapSectorIndex = $candidatePlaneSampleMapSectorIndex
                                                    CandidatePlaneSampleMapSectorMatchesPlane = ($candidatePlaneSampleMapSectorIndex -eq $candidateSectorIndex)
                                                    CandidatePlaneSampleMapSectorMatchesReferenceOwner = ($candidatePlaneSampleMapSectorIndex -eq $referenceOwnerSectorIndex)
                                                    CandidatePlaneSampleMapSectorMatchesNeitherOwner = ($candidatePlaneSampleMapSectorIndex -ne $candidateSectorIndex -and $candidatePlaneSampleMapSectorIndex -ne $referenceOwnerSectorIndex)
                                                    CandidatePlaneSampleMapSectorFloorHeightData = if ($candidatePlaneSampleMapSectorIndex -ge 0) { $context.SectorFloorHeightData[$candidatePlaneSampleMapSectorIndex] } else { -1 }
                                                    CandidatePlaneSampleMapSectorCeilingHeightData = if ($candidatePlaneSampleMapSectorIndex -ge 0) { $context.SectorCeilingHeightData[$candidatePlaneSampleMapSectorIndex] } else { -1 }
                                                    CandidatePlaneSampleMapSectorFloorFlatIndex = if ($candidatePlaneSampleMapSectorIndex -ge 0) { $context.SectorFloorFlatIndex[$candidatePlaneSampleMapSectorIndex] } else { -1 }
                                                    CandidatePlaneSampleMapSectorCeilingFlatIndex = if ($candidatePlaneSampleMapSectorIndex -ge 0) { $context.SectorCeilingFlatIndex[$candidatePlaneSampleMapSectorIndex] } else { -1 }
                                                    ReferencePlaneSampleMapSectorIndex = $referencePlaneSampleMapSectorIndex
                                                    ReferencePlaneSampleMapSectorFloorHeightData = if ($referencePlaneSampleMapSectorIndex -ge 0) { $context.SectorFloorHeightData[$referencePlaneSampleMapSectorIndex] } else { -1 }
                                                    ReferencePlaneSampleMapSectorCeilingHeightData = if ($referencePlaneSampleMapSectorIndex -ge 0) { $context.SectorCeilingHeightData[$referencePlaneSampleMapSectorIndex] } else { -1 }
                                                    CandidatePlaneSampleDistanceData = $candidateMismatchPlaneSample.DistanceData
                                                    ReferencePlaneSampleDistanceData = $referencePlaneSampleDistanceData
                                                    CandidatePlaneSampleXFracData = $candidateMismatchPlaneSample.XFracData
                                                    ReferencePlaneSampleXFracData = $referencePlaneSampleXFracData
                                                    CandidatePlaneSampleYFracData = $candidateMismatchPlaneSample.YFracData
                                                    ReferencePlaneSampleYFracData = $referencePlaneSampleYFracData
                                                    CandidatePlaneSampleOriginX = $candidatePlaneSampleOriginX
                                                    CandidateAtReferenceOriginXFracData = $candidateReferenceOriginXFrac
                                                    CandidateAtReferenceOriginYFracData = $candidateReferenceOriginYFrac
                                                    CandidateAtReferenceOriginFlatTexelIndex = $candidateReferenceOriginFlatTexelIndex
                                                    CandidateAtReferenceOriginColor = $candidateReferenceOriginColor
                                                    CandidateDirectXFracData = $candidateMismatchPlaneSample.DirectXFracData
                                                    CandidateDirectYFracData = $candidateMismatchPlaneSample.DirectYFracData
                                                    CandidateDirectTextureX = $candidateMismatchPlaneSample.DirectTextureX
                                                    CandidateDirectTextureY = $candidateMismatchPlaneSample.DirectTextureY
                                                    CandidateDirectFlatTexelIndex = $candidateMismatchPlaneSample.DirectFlatTexelIndex
                                                    CandidateDirectColor = $candidateMismatchPlaneSample.DirectColor
                                                    CandidateDirectMatchesReferenceXFrac = ($candidateMismatchPlaneSample.DirectXFracData -eq $referencePlaneSampleXFracData)
                                                    CandidateDirectMatchesReferenceYFrac = ($candidateMismatchPlaneSample.DirectYFracData -eq $referencePlaneSampleYFracData)
                                                    CandidateDirectMatchesReferenceTexture = ($candidateMismatchPlaneSample.DirectTextureX -eq (($referencePlaneSampleXFracData -shr 16) -band 63) -and $candidateMismatchPlaneSample.DirectTextureY -eq (((($referencePlaneSampleYFracData -shr 10) -band 4032) -shr 6)))
                                                    CandidateDirectMatchesReferenceTexel = ($candidateMismatchPlaneSample.DirectFlatTexelIndex -eq $referencePlaneSampleTexelIndex)
                                                    CandidateDirectMatchesReferenceColor = ($candidateMismatchPlaneSample.DirectColor -eq $referencePlaneSampleColor)
                                                    CandidatePlaneSampleLightMapIndex = $candidateMismatchPlaneSample.LightMapIndex
                                                    ReferencePlaneSampleLightMapIndex = [int]$reference3D.DiagnosticPlaneLightIndices[$referencePosition]
                                                    CandidatePlaneSampleTextureX = $candidateMismatchPlaneSample.TextureX
                                                    ReferencePlaneSampleTextureX = (($referencePlaneSampleXFracData -shr 16) -band 63)
                                                    CandidatePlaneSampleTextureY = $candidateMismatchPlaneSample.TextureY
                                                    ReferencePlaneSampleTextureY = (((($referencePlaneSampleYFracData -shr 10) -band 4032) -shr 6))
                                                    CandidatePlaneSampleFlatTexelIndex = $candidateMismatchPlaneSample.FlatTexelIndex
                                                    ReferencePlaneSampleFlatTexelIndex = $referencePlaneSampleTexelIndex
                                                    CandidatePlaneSampleColor = $candidateMismatchPlaneSample.Color
                                                    ReferencePlaneSampleColor = $referencePlaneSampleColor
                                                    CandidateFramebufferColor = [byte]$candidate[$candidateIndex]
                                                    CandidateFramebufferMatchesCurrentPlaneSample = ([byte]$candidate[$candidateIndex] -eq $candidateMismatchPlaneSample.Color)
                                                    CandidateFramebufferMatchesReferenceOriginSample = ([byte]$candidate[$candidateIndex] -eq $candidateReferenceOriginColor)
                                                    CandidateSectorFloorHeightData = $context.SectorFloorHeightData[$candidateSectorIndex]
                                                    ReferenceSectorFloorHeightData = $context.SectorFloorHeightData[$referenceOwnerSectorIndex]
                                                    CandidateSectorCeilingHeightData = $context.SectorCeilingHeightData[$candidateSectorIndex]
                                                    ReferenceSectorCeilingHeightData = $context.SectorCeilingHeightData[$referenceOwnerSectorIndex]
                                                    ReferencePlaneSampleOriginX = $reference3D.DiagnosticPlaneSampleOriginX[$referencePosition]
                                                    ReferencePlaneSampleReusedPreviousColumn = ($reference3D.DiagnosticPlaneSampleReusedPreviousColumn[$referencePosition] -eq 1)
                                                    ReferencePlaneDistanceData = $reference3D.DiagnosticPlaneDistanceData[$referencePosition]
                                                    ReferencePlaneXFracData = $reference3D.DiagnosticPlaneXFracData[$referencePosition]
                                                    ReferencePlaneYFracData = $reference3D.DiagnosticPlaneYFracData[$referencePosition]
                                                    ReferencePlaneTexelIndex = $reference3D.DiagnosticPlaneTexelIndices[$referencePosition]
                                                })
                                            }
                                        }
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
            $candidatePlaneMismatchFinalRenderPassTotal = 0
            foreach ($renderPassCount in $candidatePlaneMismatchFinalRenderPassCounts.Values) { $candidatePlaneMismatchFinalRenderPassTotal += [int]$renderPassCount }
            if ($candidatePlaneMismatchFinalRenderPassTotal -ne $candidatePlaneMismatchPixels) {
                throw "Reference final render-pass classes did not reconcile at ceiling height $height."
            }
            $candidateNonPlaneMismatchFinalWriterTotal = 0
            foreach ($writerCount in $candidateNonPlaneMismatchFinalWriterCounts.Values) { $candidateNonPlaneMismatchFinalWriterTotal += [int]$writerCount }
            if ($candidateNonPlaneMismatchFinalWriterTotal -ne $candidateNonPlaneMismatchPixels) {
                throw "Reference final-writer classes did not reconcile for non-plane mismatches at ceiling height $height."
            }
            $candidateNonPlaneMismatchFinalRenderPassTotal = 0
            foreach ($renderPassCount in $candidateNonPlaneMismatchFinalRenderPassCounts.Values) { $candidateNonPlaneMismatchFinalRenderPassTotal += [int]$renderPassCount }
            if ($candidateNonPlaneMismatchFinalRenderPassTotal -ne $candidateNonPlaneMismatchPixels) {
                throw "Reference final render-pass classes did not reconcile for non-plane mismatches at ceiling height $height."
            }
            if ($CaptureWallBoundaryTrace) {
                $candidateNonPlaneMismatchDepthOwnerTotal = 0
                foreach ($depthOwnerCount in $candidateNonPlaneMismatchDepthOwnerCounts.Values) {
                    $candidateNonPlaneMismatchDepthOwnerTotal += [int]$depthOwnerCount.MismatchPixels
                }
                if ($candidateNonPlaneMismatchDepthOwnerTotal -ne $candidateNonPlaneMismatchPixels) {
                    throw "Candidate depth-owner classes did not reconcile for non-plane mismatches at ceiling height $height."
                }
                $candidateNonPlaneMismatchReferenceWallSegmentTotal = 0
                $candidateNonPlaneMismatchReferenceMappedColumnTotal = 0
                foreach ($referenceWallSegmentCount in $candidateNonPlaneMismatchReferenceWallSegmentCounts.Values) {
                    $candidateNonPlaneMismatchReferenceWallSegmentTotal += [int]$referenceWallSegmentCount.MismatchPixels
                    if ([int]$referenceWallSegmentCount.ReferenceFinalWriterType -eq 2) {
                        $candidateNonPlaneMismatchReferenceMappedColumnTotal += [int]$referenceWallSegmentCount.MismatchPixels
                    }
                }
                $candidateNonPlaneMismatchMappedColumnTotal = if ($candidateNonPlaneMismatchFinalWriterCounts.ContainsKey('2')) { [int]$candidateNonPlaneMismatchFinalWriterCounts['2'] } else { 0 }
                if ($candidateNonPlaneMismatchReferenceWallSegmentTotal -ne $candidateNonPlaneMismatchPixels -or
                    $candidateNonPlaneMismatchMappedColumnTotal -ne $candidateNonPlaneMismatchReferenceMappedColumnTotal) {
                    throw "Reference final-writer segment attribution did not reconcile for non-plane mismatches at ceiling height $height."
                }
                if ($candidatePlaneMismatchWallSpanCounts.ReferenceOpaqueWallPixels -ne $candidatePlaneMismatchBspColumnPixels -or
                    $candidatePlaneMismatchWallSpanCounts.ReferenceWallWriteIntervalContainsPixel -ne $candidatePlaneMismatchWallSpanCounts.ReferenceOpaqueWallPixels) {
                    throw "Reference BSP column wall-span attribution did not reconcile at ceiling height $height."
                }
                if ($candidatePlaneMismatchWallSpanCounts.ReferenceWallSegmentMissing +
                    $candidatePlaneMismatchWallSpanCounts.CandidateSegmentColumnTraceMissing +
                    $candidatePlaneMismatchWallSpanCounts.CandidateSegmentColumnTraceFound -ne
                    $candidatePlaneMismatchWallSpanCounts.ReferenceOpaqueWallPixels) {
                    throw "Candidate segment-column traces did not reconcile at ceiling height $height."
                }
                if ($candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentFound +
                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentMissing -ne
                    $candidatePlaneMismatchOwnerSegmentCounts.DifferentOwnerPlanePixels) {
                    throw "Candidate plane-owner segment attribution did not reconcile at ceiling height $height."
                }
                if ($candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentTraceFound +
                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentTraceMissing -ne
                    $candidatePlaneMismatchOwnerSegmentCounts.CandidatePlaneOwnerSegmentFound) {
                    throw "Candidate plane-owner segment trace attribution did not reconcile at ceiling height $height."
                }
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
            CandidateNonPlaneMismatchReferenceFinalWriters = @(
                foreach ($writerKey in @($candidateNonPlaneMismatchFinalWriterCounts.Keys | Sort-Object { [int]$_ })) {
                    [ordered]@{
                        WriterType = [int]$writerKey
                        WriterName = $referenceFinalWriterNames[[string][int]$writerKey]
                        MismatchPixels = $candidateNonPlaneMismatchFinalWriterCounts[$writerKey]
                        CandidateDepthWrittenPixels = if ($candidateNonPlaneMismatchWriterDepthWrittenCounts.ContainsKey([string]$writerKey)) { $candidateNonPlaneMismatchWriterDepthWrittenCounts[[string]$writerKey] } else { 0 }
                        CandidateDepthInfinitePixels = if ($candidateNonPlaneMismatchWriterNoDepthCounts.ContainsKey([string]$writerKey)) { $candidateNonPlaneMismatchWriterNoDepthCounts[[string]$writerKey] } else { 0 }
                    }
                }
            )
            CandidateNonPlaneMismatchCandidateDepthOwners = if ($CaptureWallBoundaryTrace) {
                @(
                    foreach ($ownerKey in @($candidateNonPlaneMismatchDepthOwnerCounts.Keys | Sort-Object { -[int]$candidateNonPlaneMismatchDepthOwnerCounts[$_].MismatchPixels })) {
                        $owner = $candidateNonPlaneMismatchDepthOwnerCounts[$ownerKey]
                        [ordered]@{
                            ReferenceFinalWriterType = $owner.ReferenceFinalWriterType
                            ReferenceFinalWriterName = $referenceFinalWriterNames[[string]$owner.ReferenceFinalWriterType]
                            CandidateDepthOwnerWriterType = $owner.CandidateDepthOwnerWriterType
                            CandidateDepthOwnerWriterName = $candidateDepthOwnerWriterNames[[string]$owner.CandidateDepthOwnerWriterType]
                            CandidateDepthOwnerSegmentIndex = $owner.CandidateDepthOwnerSegmentIndex
                            CandidateDepthOwnerSideIndex = $owner.CandidateDepthOwnerSideIndex
                            CandidateDepthOwnerFrontSectorIndex = $owner.CandidateDepthOwnerFrontSectorIndex
                            CandidateDepthOwnerBackSectorIndex = $owner.CandidateDepthOwnerBackSectorIndex
                            CandidateDepthOwnerLineFlags = $owner.CandidateDepthOwnerLineFlags
                            CandidateDepthOwnerTopTexture = $owner.CandidateDepthOwnerTopTexture
                            CandidateDepthOwnerBottomTexture = $owner.CandidateDepthOwnerBottomTexture
                            CandidateDepthOwnerMiddleTexture = $owner.CandidateDepthOwnerMiddleTexture
                            CandidateDepthOwnerFrontFloorHeightData = $owner.CandidateDepthOwnerFrontFloorHeightData
                            CandidateDepthOwnerFrontCeilingHeightData = $owner.CandidateDepthOwnerFrontCeilingHeightData
                            CandidateDepthOwnerBackFloorHeightData = $owner.CandidateDepthOwnerBackFloorHeightData
                            CandidateDepthOwnerBackCeilingHeightData = $owner.CandidateDepthOwnerBackCeilingHeightData
                            MismatchPixels = $owner.MismatchPixels
                            Examples = $owner.Examples.ToArray()
                        }
                    }
                )
            } else { $null }
            CandidateNonPlaneMismatchReferenceWallSegments = if ($CaptureWallBoundaryTrace) {
                @(
                    foreach ($referenceWallKey in @($candidateNonPlaneMismatchReferenceWallSegmentCounts.Keys | Sort-Object { -[int]$candidateNonPlaneMismatchReferenceWallSegmentCounts[$_].MismatchPixels })) {
                        $referenceWall = $candidateNonPlaneMismatchReferenceWallSegmentCounts[$referenceWallKey]
                        [ordered]@{
                            ReferenceFinalWriterType = $referenceWall.ReferenceFinalWriterType
                            ReferenceFinalWriterName = $referenceFinalWriterNames[[string]$referenceWall.ReferenceFinalWriterType]
                            ReferenceFinalWallSegmentIndex = $referenceWall.ReferenceFinalWallSegmentIndex
                            ReferenceFinalWallSideIndex = $referenceWall.ReferenceFinalWallSideIndex
                            ReferenceFinalWallFrontSectorIndex = $referenceWall.ReferenceFinalWallFrontSectorIndex
                            ReferenceFinalWallBackSectorIndex = $referenceWall.ReferenceFinalWallBackSectorIndex
                            ReferenceFinalWallLineFlags = $referenceWall.ReferenceFinalWallLineFlags
                            ReferenceFinalWallTopTexture = $referenceWall.ReferenceFinalWallTopTexture
                            ReferenceFinalWallBottomTexture = $referenceWall.ReferenceFinalWallBottomTexture
                            ReferenceFinalWallMiddleTexture = $referenceWall.ReferenceFinalWallMiddleTexture
                            ReferenceFinalWallFrontFloorHeightData = $referenceWall.ReferenceFinalWallFrontFloorHeightData
                            ReferenceFinalWallFrontCeilingHeightData = $referenceWall.ReferenceFinalWallFrontCeilingHeightData
                            ReferenceFinalWallBackFloorHeightData = $referenceWall.ReferenceFinalWallBackFloorHeightData
                            ReferenceFinalWallBackCeilingHeightData = $referenceWall.ReferenceFinalWallBackCeilingHeightData
                            MismatchPixels = $referenceWall.MismatchPixels
                            Examples = $referenceWall.Examples.ToArray()
                        }
                    }
                )
            } else { $null }
            CandidateNonPlaneMismatchReferenceFinalRenderPasses = @(
                foreach ($passKey in @($candidateNonPlaneMismatchFinalRenderPassCounts.Keys | Sort-Object { [int]$_ })) {
                    [ordered]@{
                        PassType = [int]$passKey
                        PassName = $referenceRenderPassNames[[string][int]$passKey]
                        MismatchPixels = $candidateNonPlaneMismatchFinalRenderPassCounts[$passKey]
                    }
                }
            )
            CandidatePlaneMismatchReferenceFinalRenderPasses = @(
                foreach ($passKey in @($candidatePlaneMismatchFinalRenderPassCounts.Keys | Sort-Object { [int]$_ })) {
                    [ordered]@{
                        PassType = [int]$passKey
                        PassName = $referenceRenderPassNames[[string][int]$passKey]
                        MismatchPixels = $candidatePlaneMismatchFinalRenderPassCounts[$passKey]
                    }
                }
            )
            CandidatePlaneMismatchReferenceWallSpanCounts = if ($CaptureWallBoundaryTrace) { $candidatePlaneMismatchWallSpanCounts } else { $null }
            CandidatePlaneMismatchReferenceWallSpanExamples = if ($CaptureWallBoundaryTrace) { $candidatePlaneMismatchWallSpanExamples.ToArray() } else { @() }
            CandidatePlaneMismatchDifferentOwnerSegmentCounts = if ($CaptureWallBoundaryTrace) { $candidatePlaneMismatchOwnerSegmentCounts } else { $null }
            CandidatePlaneMismatchDifferentOwnerExamples = if ($CaptureWallBoundaryTrace) { $candidatePlaneMismatchDifferentOwnerExamples.ToArray() } else { @() }
            SameOwnerPlaneSampleComparisons = $planeSampleCounts
            SameOwnerPlaneSampleExamples = $planeSampleExamples.ToArray()
            ReferencePlaneWriteOwnerPairs = @(
                foreach ($pairKey in @($referencePlaneOwnerPairCounts.Keys | Sort-Object)) {
                    [ordered]@{ Pair = $pairKey; MismatchPixels = $referencePlaneOwnerPairCounts[$pairKey] }
                }
            )
            CandidatePlaneCallTrace = $candidatePlaneCallTrace.ToArray()
            ReferencePlaneCallTrace = if ($CaptureReferencePlaneOwners -and [int]$height -eq 68) {
                @(
                    [int]$planeCallOrdinal = 0
                    foreach ($planeCall in $reference3D.DiagnosticPlaneCallTrace) {
                        [int]$callOrdinal = $planeCallOrdinal++
                        [int]$callX = $planeCall[0]
                        [int]$callY1 = $planeCall[1]
                        [int]$callY2 = $planeCall[2]
                        if ($callX -lt 0 -or $callX -ge 320) { throw "Reference plane-call trace contains out-of-frame column $callX." }
                        [ordered]@{
                            Ordinal = $callOrdinal
                            X = $callX
                            Y1 = $callY1
                            Y2 = $callY2
                            SectorIndex = [int]$planeCall[3]
                            SurfaceType = if ([int]$planeCall[4] -eq 1) { 'Floor' } else { 'Ceiling' }
                            SegmentIndex = [int]$planeCall[5]
                        }
                    }
                )
            } else { @() }
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
        ReferenceFinalRenderPassDefinitions = $referenceRenderPassNames
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
        CandidateOwnershipInterpretation = 'Plane-buffer counts classify the candidate plane ID at mismatch coordinates; the separate final-render-pass tags identify which reference render pass supplied the final pixel.'
        ReferencePlaneWritesInterpretation = 'Plane ownership records the last reference floor/ceiling write. Final-writer tags distinguish plane, mapped-column and fuzz writes; final-render-pass tags distinguish BSP traversal, world sprites, masked textures, player sprites, back-screen fill and sky columns.'
        ReferenceFinalRenderPassInterpretation = 'Within BSP traversal, a final plane write is a plane sampler output and a mapped-column write is an opaque wall column; sky columns are tagged separately. Later pass tags distinguish world sprites, masked textures, player sprites and back-screen fill.'
        ReferenceWallSpanInterpretation = 'For candidate plane-buffer mismatches whose final reference pixel is a BSP mapped-column write, the diagnostic records the reference segment and actual write interval, then compares that pixel with the candidate segment-column wall bounds, clip interval, and upper/solid, lower, and deferred masked-middle bands. Candidate band intervals are clipped raster spans; this classifies geometry coverage and does not by itself prove the texture sample or final candidate color.'
        CandidatePortalBoundaryInterpretation = 'CandidatePortalTopEqualsPixel counts mismatch pixels that lie exactly on the candidate portal top boundary. CandidateUpperBandEndsImmediatelyAbovePixel counts when the candidate band-0 span ends at y-1; together with ReferenceWallBottomEqualsPixel, these counts isolate a one-row upper-wall versus portal-boundary difference.'
        PlaneSampleInterpretation = 'Candidate plane fractions, recurrence origins and reuse flags are captured from the production per-call plane sampler. Reference fractions, distance, light bin and flat texel are recorded at writes. Candidate frame bytes may include later overlays.'
        CandidatePlaneCallTraceInterpretation = 'At ceiling height 68, the receipt includes every candidate floor/ceiling plane call across the full 320-column frame in original call order, including vertical spans outside the target mismatch rows. Each record gives x, y1, y2, plane id, sector index, surface, and segment index. Calls outside a target row can still reset per-surface previous-call state.'
        ReferencePlaneCallTraceInterpretation = 'At ceiling height 68, the receipt includes every adapted-reference floor/ceiling call across the full 320-column frame in original call order, including vertical spans outside the target mismatch rows. Each record gives x, y1, y2, sector index, surface, and segment index. Calls expose visibility and recurrence boundaries; they do not establish original-executable parity.'
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
