# SPDX-License-Identifier: GPL-2.0-or-later
# Diagnostic bundle edit only. Production sources remain unchanged.
param([Parameter(Mandatory)][string]$Bundle,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh candidate bundle.'}
$text=[IO.File]::ReadAllText($Bundle)
function Replace-Once([string]$Marker,[string]$Replacement){
    if([regex]::Matches($script:text,[regex]::Escape($Marker)).Count -ne 1){throw "Missing or ambiguous candidate marker: $Marker"}
    $script:text=$script:text.Replace($Marker,$Replacement)
}
Replace-Once 'class ThreeDRenderer {' @'
class ThreeDRenderer {
    [bool] $CacheDiscoveryAngles
    [Collections.Generic.Dictionary[Vertex,long]] $DiscoveryAngles = [Collections.Generic.Dictionary[Vertex,long]]::new()
'@
$marker=@'
        [long] $a1 = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex1.X.Data, $seg.Vertex1.Y.Data)
        [long] $a2 = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex2.X.Data, $seg.Vertex2.Y.Data)
'@
if(-not $text.Contains($marker)){$marker=$marker.Replace("`r`n","`n")}
Replace-Once $marker @'
        [long] $a1 = 0
        [long] $a2 = 0
        if ($this.CacheDiscoveryAngles) {
            if (-not $this.DiscoveryAngles.TryGetValue($seg.Vertex1, [ref]$a1)) {
                $a1 = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex1.X.Data, $seg.Vertex1.Y.Data)
                $this.DiscoveryAngles.Add($seg.Vertex1, $a1)
            }
            if (-not $this.DiscoveryAngles.TryGetValue($seg.Vertex2, [ref]$a2)) {
                $a2 = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex2.X.Data, $seg.Vertex2.Y.Data)
                $this.DiscoveryAngles.Add($seg.Vertex2, $a2)
            }
        } else {
            $a1 = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex1.X.Data, $seg.Vertex1.Y.Data)
            $a2 = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex2.X.Data, $seg.Vertex2.Y.Data)
        }
'@
Replace-Once '    [void] DiscoverMap([Player] $player) {' @'
    [void] DiscoverMap([Player] $player) {
        if ($this.CacheDiscoveryAngles) { $this.DiscoveryAngles.Clear() }
'@
[IO.File]::WriteAllText($Output,$text,[Text.UTF8Encoding]::new($false))
return [IO.Path]::GetFullPath($Output)
