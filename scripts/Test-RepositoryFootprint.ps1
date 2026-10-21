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

# Force includes hidden items such as .git; no Git-ignore filtering is applied.
# Stop on enumeration errors so an inaccessible subtree cannot look under-limit.
$files = @(Get-ChildItem -LiteralPath $rootPath -Force -Recurse -File -ErrorAction Stop)
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
