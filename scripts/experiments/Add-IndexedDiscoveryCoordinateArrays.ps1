# SPDX-License-Identifier: GPL-2.0-or-later
# Disposable engine-bundle variant. Production remains unchanged unless the
# primitive-coordinate path is separately adopted.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Bundle,
    [Parameter(Mandatory)][string]$Output
)

$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$localRoot = [IO.Path]::GetFullPath((Join-Path $repo 'local'))
$bundlePath = [IO.Path]::GetFullPath($Bundle)
$outputPath = [IO.Path]::GetFullPath($Output)
$relative = [IO.Path]::GetRelativePath($localRoot, $outputPath)
if ([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or
    $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")) {
    throw 'The disposable bundle must remain inside local/.'
}
if ($bundlePath -eq $outputPath) { throw 'The disposable bundle cannot overwrite its input.' }
if (-not [IO.File]::Exists($bundlePath)) { throw "Input bundle not found: $bundlePath" }
if ([IO.File]::Exists($outputPath)) { throw 'Use a fresh output path.' }

$text = [IO.File]::ReadAllText($bundlePath)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$text = $text.Replace("`r`n", "`n")

function Replace-Once([string]$Source, [string]$Marker, [string]$Replacement) {
    if (([regex]::Matches($Source, [regex]::Escape($Marker))).Count -ne 1) {
        throw "Expected one candidate marker: $Marker"
    }
    return $Source.Replace($Marker, $Replacement)
}

$text = Replace-Once $text '    [bool] $CacheDiscoveryAngles = $true' @'
    [bool] $CacheDiscoveryAngles = $true
    [bool] $CacheDiscoveryCoordinates
    [int[]] $DiscoveryVertexX
    [int[]] $DiscoveryVertexY
'@.TrimEnd()
$text = Replace-Once $text '                for ($v = 0; $v -lt $map.Vertices.Length; $v++) { $lookup.Add($map.Vertices[$v], $v) }' @'
                if ($this.CacheDiscoveryCoordinates) {
                    $this.DiscoveryVertexX = [int[]]::new($map.Vertices.Length)
                    $this.DiscoveryVertexY = [int[]]::new($map.Vertices.Length)
                }
                for ($v = 0; $v -lt $map.Vertices.Length; $v++) {
                    $vertex = $map.Vertices[$v]
                    $lookup.Add($vertex, $v)
                    if ($this.CacheDiscoveryCoordinates) {
                        $this.DiscoveryVertexX[$v] = $vertex.X.Data
                        $this.DiscoveryVertexY[$v] = $vertex.Y.Data
                    }
                }
'@.TrimEnd()

$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw "Input bundle parse failed: $($parseErrors[0].Message)" }
$renderer = $ast.Find({ param($node) $node -is [Management.Automation.Language.TypeDefinitionAst] -and $node.Name -eq 'ThreeDRenderer' }, $false)
if ($null -eq $renderer) { throw 'ThreeDRenderer class was not found.' }
$methods = @($renderer.Members | Where-Object { $_.Name -eq 'DiscoverIndexedSeg' -and $_ -is [Management.Automation.Language.FunctionMemberAst] })
if ($methods.Count -ne 1) { throw 'Expected one indexed discovery segment method.' }
$method = $methods[0]
$methodText = $method.Extent.Text
$segmentInitialization = @'
        $seg = $null
        if (-not $this.CacheDiscoveryCoordinates) { $seg = $this.world.Map.Segs[$index] }
'@.TrimEnd()
$methodText = Replace-Once $methodText '        $seg=$this.world.Map.Segs[$index]' $segmentInitialization
$methodText = Replace-Once $methodText '        [int] $v2 = $this.DiscoveryVertex2[$index]' @'
        [int] $v2 = $this.DiscoveryVertex2[$index]
'@.TrimEnd()
$methodText = Replace-Once $methodText '$seg.Vertex1.X.Data, $seg.Vertex1.Y.Data' @'
$(if ($this.CacheDiscoveryCoordinates) { $this.DiscoveryVertexX[$v1] } else { $seg.Vertex1.X.Data }), $(if ($this.CacheDiscoveryCoordinates) { $this.DiscoveryVertexY[$v1] } else { $seg.Vertex1.Y.Data })
'@.TrimEnd()
$methodText = Replace-Once $methodText '$seg.Vertex2.X.Data, $seg.Vertex2.Y.Data' @'
$(if ($this.CacheDiscoveryCoordinates) { $this.DiscoveryVertexX[$v2] } else { $seg.Vertex2.X.Data }), $(if ($this.CacheDiscoveryCoordinates) { $this.DiscoveryVertexY[$v2] } else { $seg.Vertex2.Y.Data })
'@.TrimEnd()
$methodText = Replace-Once $methodText '        $front = $seg.FrontSector' @'
        if ($this.CacheDiscoveryCoordinates) { $seg = $this.world.Map.Segs[$index] }
        $front = $seg.FrontSector
'@.TrimEnd()
$text = $text.Substring(0, $method.Extent.StartOffset) + $methodText + $text.Substring($method.Extent.EndOffset)

$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw "Generated candidate parse failed: $($parseErrors[0].Message)" }
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath))
[IO.File]::WriteAllText($outputPath, $text.Replace("`n", $newline), [Text.UTF8Encoding]::new($false))
return $outputPath
