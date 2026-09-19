# SPDX-License-Identifier: GPL-2.0-or-later
# Alternative diagnostic bundle: index shared vertices once per map.
param([Parameter(Mandatory)][string]$Bundle,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh candidate bundle.'}
$text=[IO.File]::ReadAllText($Bundle)
function Replace-Once([string]$Marker,[string]$Replacement){
    if([regex]::Matches($script:text,[regex]::Escape($Marker)).Count -ne 1){throw "Missing or ambiguous candidate marker: $Marker"}
    $script:text=$script:text.Replace($Marker,$Replacement)
}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
$type=$ast.Find({param($n) $n -is [Management.Automation.Language.TypeDefinitionAst] -and $n.Name -eq 'ThreeDRenderer'},$false)
$method=@($type.Members|Where-Object {$_.Name -eq 'DiscoverSeg' -and $_ -is [Management.Automation.Language.FunctionMemberAst]})
if($method.Count -ne 1){throw 'Expected one original discovery segment method.'}
$copy=$method[0].Extent.Text.Replace('DiscoverSeg([Seg] $seg)','DiscoverIndexedSeg([int] $index)')
$start=$copy.IndexOf('{')+1
$copy=$copy.Insert($start,"`n"+'        $seg=$this.world.Map.Segs[$index]'+"`n")
$marker=@'
        [long] $a1 = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex1.X.Data, $seg.Vertex1.Y.Data)
        [long] $a2 = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex2.X.Data, $seg.Vertex2.Y.Data)
'@
if(-not $copy.Contains($marker)){$marker=$marker.Replace("`r`n","`n")}
if(-not $copy.Contains($marker)){throw 'Missing angle pair.'}
$copy=$copy.Replace($marker,@'
        [int] $v1 = $this.DiscoveryVertex1[$index]
        [int] $v2 = $this.DiscoveryVertex2[$index]
        if (-not $this.DiscoveryAngleReady[$v1]) {
            $this.DiscoveryAngleValues[$v1] = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex1.X.Data, $seg.Vertex1.Y.Data)
            $this.DiscoveryAngleReady[$v1] = $true
        }
        if (-not $this.DiscoveryAngleReady[$v2]) {
            $this.DiscoveryAngleValues[$v2] = [Geometry]::PointToAngleData($this.viewXData, $this.viewYData, $seg.Vertex2.X.Data, $seg.Vertex2.Y.Data)
            $this.DiscoveryAngleReady[$v2] = $true
        }
        [long] $a1 = $this.DiscoveryAngleValues[$v1]
        [long] $a2 = $this.DiscoveryAngleValues[$v2]
'@)
$properties=@'
class ThreeDRenderer {
    [bool] $CacheDiscoveryAngles
    [Map] $DiscoveryIndexedMap
    [int[]] $DiscoveryVertex1
    [int[]] $DiscoveryVertex2
    [long[]] $DiscoveryAngleValues
    [bool[]] $DiscoveryAngleReady
    [Collections.Generic.List[double]] $DiscoveryCacheSetupSamples = [Collections.Generic.List[double]]::new()
'@
Replace-Once 'class ThreeDRenderer {' ($properties+"`n    "+$copy+"`n")
Replace-Once '    [void] DiscoverMap([Player] $player) {' @'
    [void] DiscoverMap([Player] $player) {
        if ($this.CacheDiscoveryAngles) {
            if (-not [object]::ReferenceEquals($this.DiscoveryIndexedMap, $player.Mobj.World.Map)) {
                $setupWatch = [Diagnostics.Stopwatch]::StartNew()
                $map = $player.Mobj.World.Map
                $lookup = [Collections.Generic.Dictionary[Vertex,int]]::new()
                for ($v = 0; $v -lt $map.Vertices.Length; $v++) { $lookup.Add($map.Vertices[$v], $v) }
                $this.DiscoveryVertex1 = [int[]]::new($map.Segs.Length)
                $this.DiscoveryVertex2 = [int[]]::new($map.Segs.Length)
                for ($s = 0; $s -lt $map.Segs.Length; $s++) {
                    $this.DiscoveryVertex1[$s] = $lookup[$map.Segs[$s].Vertex1]
                    $this.DiscoveryVertex2[$s] = $lookup[$map.Segs[$s].Vertex2]
                }
                $this.DiscoveryAngleValues = [long[]]::new($map.Vertices.Length)
                $this.DiscoveryAngleReady = [bool[]]::new($map.Vertices.Length)
                $this.DiscoveryIndexedMap = $map
                $this.DiscoveryCacheSetupSamples.Add($setupWatch.Elapsed.TotalMilliseconds)
            }
            [Array]::Clear($this.DiscoveryAngleReady)
        }
'@
$branch=@'
        if ($this.DiscoveryOnly) {
            for ($i = 0; $i -lt $target.SegCount; $i++) {
                $this.DrawSeg($this.world.Map.Segs[$target.FirstSeg + $i])
            }
            return
        }
'@
if(-not $text.Contains($branch)){$branch=$branch.Replace("`r`n","`n")}
Replace-Once $branch @'
        if ($this.DiscoveryOnly) {
            for ($i = 0; $i -lt $target.SegCount; $i++) {
                if ($this.CacheDiscoveryAngles) { $this.DiscoverIndexedSeg($target.FirstSeg + $i) }
                else { $this.DrawSeg($this.world.Map.Segs[$target.FirstSeg + $i]) }
            }
            return
        }
'@
[IO.File]::WriteAllText($Output,$text,[Text.UTF8Encoding]::new($false))
return [IO.Path]::GetFullPath($Output)
