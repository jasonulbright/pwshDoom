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
$reuseMarker = '                [bool]$reuseCurrentRow = $reusePrevious -and $y -ge $overlapStart -and $y -le $overlapEnd'
if (([regex]::Matches($source, [regex]::Escape($reuseMarker))).Count -ne 1) {
    throw 'Expected one plane row reuse decision.'
}
$source = $source.Replace($reuseMarker, '                [bool]$reuseCurrentRow = $false')

[IO.File]::WriteAllText($outputPath, $source, [Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    InputRenderer = [IO.Path]::GetRelativePath($repo, $sourcePath).Replace('\', '/')
    InputRendererSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash
    CounterfactualRenderer = [IO.Path]::GetRelativePath($repo, $outputPath).Replace('\', '/')
    CounterfactualRendererSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
    Meaning = 'Disposable renderer only. Initializes every visible plane pixel at its own column instead of reusing the prior fixed-point sample.'
}
