#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $PSScriptRoot '..'),
    [long]$MaximumBytes = 30000000000
)

$ErrorActionPreference = 'Stop'
if ($MaximumBytes -le 0) { throw 'MaximumBytes must be greater than zero.' }

$rootPath = [IO.Path]::GetFullPath($Root)
if (-not [IO.Directory]::Exists($rootPath)) { throw "Repository directory not found: $rootPath" }
$rootAttributes = [IO.File]::GetAttributes($rootPath)
if (($rootAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Repository root is a reparse point; resolve it before measuring: $rootPath"
}

# Force includes hidden items such as .git; no Git-ignore filtering is applied.
# Stop on enumeration errors or links so an inaccessible or untraversed subtree
# cannot look under-limit. PowerShell does not follow directory symlinks by default.
$entries = @(Get-ChildItem -LiteralPath $rootPath -Force -Recurse -ErrorAction Stop)
$reparsePoints = @($entries | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
if ($reparsePoints.Count -gt 0) {
    $paths = @($reparsePoints | Select-Object -First 20 -ExpandProperty FullName)
    throw "Repository contains reparse points whose target sizes are not included. Resolve them before measuring: $($paths -join '; ')"
}
$files = @($entries | Where-Object { -not $_.PSIsContainer })
[long]$totalBytes = 0
foreach ($file in $files) { $totalBytes += [long]$file.Length }

[long]$headroomBytes = $MaximumBytes - $totalBytes
[bool]$withinLimit = $totalBytes -le $MaximumBytes
$largestFiles = @()
if (-not $withinLimit) {
    $largestFiles = @(
        $files |
            Sort-Object -Property Length -Descending |
            Select-Object -First 20 |
            ForEach-Object {
                [pscustomobject]@{
                    Path = [IO.Path]::GetRelativePath($rootPath, $_.FullName)
                    Bytes = [long]$_.Length
                }
            }
    )
}

[pscustomobject]@{
    Root = $rootPath
    MeasuredUtc = [DateTimeOffset]::UtcNow.ToString('o')
    FileCount = $files.Count
    TotalBytes = $totalBytes
    DecimalGB = [math]::Round($totalBytes / 1000000000, 6)
    GiB = [math]::Round($totalBytes / 1GB, 6)
    MaximumBytes = $MaximumBytes
    HeadroomBytes = $headroomBytes
    WithinLimit = $withinLimit
    LargestFilesWhenOverLimit = $largestFiles
} | ConvertTo-Json -Depth 4

if (-not $withinLimit) { exit 1 }
