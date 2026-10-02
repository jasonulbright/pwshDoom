#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay = "$PSScriptRoot/../results/e1m1-route-lineflags.json",
    [Parameter(Mandatory)][string]$Output,
    [string]$Images,
    [string]$Renderer = "$PSScriptRoot/../src/FastRenderer.ps1",
    [ValidateRange(2,100000)][int]$InputTic = 315,
    [ValidateRange(0,32767)][int]$SectorIndex = 26,
    [ValidateRange(-4096,4096)][int[]]$Heights = @(0, 6, 34, 68)
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$Wad = [IO.Path]::GetFullPath($Wad)
$Replay = [IO.Path]::GetFullPath($Replay)
$Output = [IO.Path]::GetFullPath($Output)
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

$bundle = & "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. $Renderer
. "$PSScriptRoot/../src/GameHost.ps1"
$sourcePaths = @(
    [IO.Path]::GetRelativePath($root, [IO.Path]::GetFullPath($Renderer)).Replace('\', '/'),
    'src/GameHost.ps1',
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
    $context = New-FastRenderContext $content $game.World
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
        Invoke-FastRender $context
        [byte[]]$candidate = $context.Pixels.Clone()
        $reference.RenderGame($game, [Fixed]::One)
        [byte[]]$referencePixels = $reference.Screen.Data.Clone()

        $sceneDifferences = 0
        $hudDifferences = 0
        $bounds = [int[]]@(320, 168, -1, -1)
        for ($y = 0; $y -lt 200; $y++) {
            for ($x = 0; $x -lt 320; $x++) {
                if ($candidate[$y * 320 + $x] -eq $referencePixels[$x * 200 + $y]) { continue }
                if ($y -lt 168) {
                    $sceneDifferences++
                    $bounds[0] = [Math]::Min($bounds[0], $x)
                    $bounds[1] = [Math]::Min($bounds[1], $y)
                    $bounds[2] = [Math]::Max($bounds[2], $x)
                    $bounds[3] = [Math]::Max($bounds[3], $y)
                } else { $hudDifferences++ }
            }
        }
        $heightResults.Add([ordered]@{
            CeilingHeight = $height
            SceneDifferentIndices = $sceneDifferences
            HudDifferentIndices = $hudDifferences
            SceneMismatchBounds = if ($sceneDifferences) { $bounds } else { @() }
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
