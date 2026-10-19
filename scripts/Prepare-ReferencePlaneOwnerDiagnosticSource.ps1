#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceRoot=Join-Path $repo 'src/ManagedDoom'
$outputRoot=[IO.Path]::GetFullPath($OutputRoot)
$relative=[IO.Path]::GetRelativePath($repo,$outputRoot)
if([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")){
    throw 'Diagnostic source must remain inside the project.'
}
if(Test-Path -LiteralPath $outputRoot){throw 'Use a fresh diagnostic source directory.'}
[void][IO.Directory]::CreateDirectory($outputRoot)
Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $outputRoot -Recurse -Force

$target=Join-Path $outputRoot 'Video/ThreeDRenderer.sb.ps1'
$source=[IO.File]::ReadAllText($target)
$marker='class ThreeDRenderer {'
if(([regex]::Matches($source,[regex]::Escape($marker))).Count -ne 1){throw 'Unexpected ThreeDRenderer class marker.'}
$fields=@'
class ThreeDRenderer {
    # Diagnostic-only reference plane writes; present only in this copied source.
    [Sector[]] $DiagnosticPlaneOwners
    [byte[]] $DiagnosticPlaneSurfaceTypes
    [byte[]] $DiagnosticFinalWriterTypes
    [byte[]] $DiagnosticFinalRenderPassTypes
    [int[]] $DiagnosticFinalWallSegIndices
    [int[]] $DiagnosticFinalWallTopRows
    [int[]] $DiagnosticFinalWallBottomRows
    [byte] $DiagnosticCurrentRenderPassType
    [int] $DiagnosticCurrentWallSegIndex = -1
    [int[]] $DiagnosticPlaneDistanceData
    [int[]] $DiagnosticPlaneXFracData
    [int[]] $DiagnosticPlaneYFracData
    [int[]] $DiagnosticPlaneLightIndices
    [int[]] $DiagnosticPlaneTexelIndices
    [byte[][]] $DiagnosticPlaneLightMaps
    [int[]] $DiagnosticPlaneSampleOriginX
    [byte[]] $DiagnosticPlaneSampleReusedPreviousColumn
    [int[]] $DiagnosticCeilingSampleOriginX
    [int[]] $DiagnosticFloorSampleOriginX
'@
$source=$source.Replace($marker,$fields.TrimEnd([char]13,[char]10))
$nl=[Environment]::NewLine

function Add-PlaneOwnerWrites([string]$text,[string]$methodStart,[string]$methodEnd,[byte]$surfaceType,[string]$planeKind){
    $start=$text.IndexOf($methodStart,[StringComparison]::Ordinal)
    if($start -lt 0){throw "Missing method: $methodStart"}
    $end=$text.IndexOf($methodEnd,$start,[StringComparison]::Ordinal)
    if($end -lt 0){throw "Missing next method: $methodEnd"}
    $segment=$text.Substring($start,$end-$start)
    $reuseBranchPattern='(?m)^(?<indent>[ \t]*)if \(\$sector -eq \$this\.'+[regex]::Escape($planeKind)+'PrevSector'
    $reuseBranchMatches=[regex]::Matches($segment,$reuseBranchPattern)
    if($reuseBranchMatches.Count -ne 1){throw "$methodStart expected one previous-column branch, found $($reuseBranchMatches.Count)."}
    $reuseBranchEvaluator=[Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $indent=$match.Groups['indent'].Value
        return $indent+'[int]$p1 = 0'+$nl+$indent+'[int]$p2 = -1'+$nl+$match.Value
    }
    $segment=[regex]::Replace($segment,$reuseBranchPattern,$reuseBranchEvaluator)
    $pattern='(?m)^(?<indent>[ \t]*)\$pos\+\+\r?$'
    $matches=[regex]::Matches($segment,$pattern)
    if($matches.Count -ne 4){throw "$methodStart expected four plane pixel loops, found $($matches.Count)."}
    $lightMapExpression=if($surfaceType -eq 1){'$localFloorLights[$y]'}else{'$localCeilingLights[$y]'}
    $previousSectorField='$this.'+$planeKind+'PrevSector'
    $previousXField='$this.'+$planeKind+'PrevX'
    $originArrayField='$this.Diagnostic'+$planeKind.Substring(0,1).ToUpperInvariant()+$planeKind.Substring(1)+'SampleOriginX[$y]'
    $reuseExpression='($sector -eq '+$previousSectorField+' -and '+$previousXField+' -eq ($x - 1) -and $y -ge $p1 -and $y -le $p2)'
    $evaluator=[Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $indent=$match.Groups['indent'].Value
        return $indent+'$this.DiagnosticPlaneOwners[$pos] = $sector'+$nl+
            $indent+'$this.DiagnosticPlaneSurfaceTypes[$pos] = '+$surfaceType+$nl+
            $indent+'$this.DiagnosticFinalWriterTypes[$pos] = 1'+$nl+
            $indent+'$this.DiagnosticFinalRenderPassTypes[$pos] = $this.DiagnosticCurrentRenderPassType'+$nl+
            $indent+'$this.DiagnosticPlaneDistanceData[$pos] = [Fixed]::ToInt32Unchecked((([long]$heightData * [long]$localPlaneYSlope[$y]) -shr $fracBits))'+$nl+
            $indent+'$this.DiagnosticPlaneXFracData[$pos] = $xFracData'+$nl+
            $indent+'$this.DiagnosticPlaneYFracData[$pos] = $yFracData'+$nl+
            $indent+'$this.DiagnosticPlaneLightIndices[$pos] = [Math]::Clamp(($this.DiagnosticPlaneDistanceData[$pos] -shr $localZLightShift), 0, $localMaxZLight - 1)'+$nl+
            $indent+'$this.DiagnosticPlaneTexelIndices[$pos] = $flatData[$spot]'+$nl+
            $indent+'$this.DiagnosticPlaneLightMaps[$pos] = '+$lightMapExpression+$nl+
            $indent+'if '+$reuseExpression+' {'+$nl+
            $indent+'    $this.DiagnosticPlaneSampleReusedPreviousColumn[$pos] = 1'+$nl+
            $indent+'    $this.DiagnosticPlaneSampleOriginX[$pos] = '+$originArrayField+$nl+
            $indent+'} else {'+$nl+
            $indent+'    $this.DiagnosticPlaneSampleReusedPreviousColumn[$pos] = 0'+$nl+
            $indent+'    $this.DiagnosticPlaneSampleOriginX[$pos] = $x'+$nl+
            $indent+'    '+$originArrayField+' = $x'+$nl+
            $indent+'}'+$nl+
            $match.Value
    }
    $segment=[regex]::Replace($segment,$pattern,$evaluator)
    return $text.Substring(0,$start)+$segment+$text.Substring($end)
}

$source=Add-PlaneOwnerWrites $source '    [void] DrawCeilingColumn(' '    [void] DrawFloorColumn(' 2 'ceiling'
$source=Add-PlaneOwnerWrites $source '    [void] DrawFloorColumn(' '    hidden [void] DrawColumnData(' 1 'floor'

function Add-FinalWriterMarks([string]$text,[string]$methodStart,[string]$methodEnd,[byte]$writerType){
    $start=$text.IndexOf($methodStart,[StringComparison]::Ordinal)
    if($start -lt 0){throw "Missing writer method: $methodStart"}
    $end=$text.IndexOf($methodEnd,$start,[StringComparison]::Ordinal)
    if($end -lt 0){throw "Missing next writer method: $methodEnd"}
    $segment=$text.Substring($start,$end-$start)
    $pattern='(?m)^(?<indent>[ \t]*)\$localScreenData\[\$pos\] = .+\r?$'
    $matches=[regex]::Matches($segment,$pattern)
    if($matches.Count -ne 1){throw "$methodStart expected one mapped column write, found $($matches.Count)."}
    $evaluator=[Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $indent=$match.Groups['indent'].Value
        $wallTraceMarks=''
        if($writerType -eq 2){
            $wallTraceMarks=$nl+$indent+'if($this.DiagnosticCurrentRenderPassType -eq 1 -and $this.DiagnosticCurrentWallSegIndex -ge 0){'+$nl+
                $indent+'    $this.DiagnosticFinalWallSegIndices[$pos] = $this.DiagnosticCurrentWallSegIndex + 1'+$nl+
                $indent+'    $this.DiagnosticFinalWallTopRows[$pos] = $y1'+$nl+
                $indent+'    $this.DiagnosticFinalWallBottomRows[$pos] = $y2'+$nl+
                $indent+'}'
        }
        return $match.Value+$nl+$indent+'$this.DiagnosticFinalWriterTypes[$pos] = '+$writerType+$nl+$indent+'$this.DiagnosticFinalRenderPassTypes[$pos] = $this.DiagnosticCurrentRenderPassType'+$wallTraceMarks
    }
    $segment=[regex]::Replace($segment,$pattern,$evaluator)
    return $text.Substring(0,$start)+$segment+$text.Substring($end)
}

$source=Add-FinalWriterMarks $source '    hidden [void] DrawColumnData(' '    [void] DrawColumn(' 2
$source=Add-FinalWriterMarks $source '    hidden [void] DrawColumnTranslationData(' '    [void] DrawColumnTranslation(' 2
$source=Add-FinalWriterMarks $source '    [void] DrawFuzzColumn(' '    [void] DrawSkyColumn(' 3

$segIndexMarker='        $angle1 = [Geometry]::PointToAngle($this.viewX, $this.viewY, $seg.Vertex1.X, $seg.Vertex1.Y)'
if(([regex]::Matches($source,[regex]::Escape($segIndexMarker))).Count -ne 1){throw 'Expected one DrawSeg angle marker.'}
$source=$source.Replace($segIndexMarker,'        $this.DiagnosticCurrentWallSegIndex = [Array]::IndexOf($this.world.Map.Segs, $seg)'+$nl+$segIndexMarker)

function Add-RenderPassMarker([string]$text,[string]$call,[byte]$passType){
    $pattern='(?m)^(?<indent>[ \t]*)'+[regex]::Escape($call)+'\r?$'
    $matches=[regex]::Matches($text,$pattern)
    if($matches.Count -ne 1){throw "Expected one render-pass call for $call, found $($matches.Count)."}
    $evaluator=[Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $indent=$match.Groups['indent'].Value
        return $indent+'$this.DiagnosticCurrentRenderPassType = '+$passType+$nl+$match.Value
    }
    return [regex]::Replace($text,$pattern,$evaluator)
}

$source=Add-RenderPassMarker $source '$this.RenderBspNode($this.world.Map.Nodes.Length - 1)' 1
$source=Add-RenderPassMarker $source '$this.RenderSprites()' 2
$source=Add-RenderPassMarker $source '$this.RenderMaskedTextures()' 3
$source=Add-RenderPassMarker $source '$this.DrawPlayerSprites($player)' 4
$source=Add-RenderPassMarker $source '$this.FillBackScreen()' 5

$skyStart=$source.IndexOf('    [void] DrawSkyColumn(',[StringComparison]::Ordinal)
$skyEnd=$source.IndexOf('    [void] DrawMaskedColumn(', $skyStart,[StringComparison]::Ordinal)
if($skyStart -lt 0 -or $skyEnd -lt 0){throw 'Could not isolate DrawSkyColumn.'}
$skySegment=$source.Substring($skyStart,$skyEnd-$skyStart)
$skyCall='$this.DrawColumnData($source[0], $this.defaultColorMap, $x, $y1, $y2, $this.skyInvScale.Data, $this.skyTextureAlt.Data)'
$skyPattern='(?m)^(?<indent>[ \t]*)'+[regex]::Escape($skyCall)+'\r?$'
$skyMatches=[regex]::Matches($skySegment,$skyPattern)
if($skyMatches.Count -ne 1){throw "Expected one sky draw call, found $($skyMatches.Count)."}
$skyEvaluator=[Text.RegularExpressions.MatchEvaluator]{
    param($match)
    $indent=$match.Groups['indent'].Value
    return $indent+'[byte]$diagnosticPriorPass = $this.DiagnosticCurrentRenderPassType'+$nl+$indent+'$this.DiagnosticCurrentRenderPassType = 6'+$nl+$match.Value+$nl+$indent+'$this.DiagnosticCurrentRenderPassType = $diagnosticPriorPass'
}
$skySegment=[regex]::Replace($skySegment,$skyPattern,$skyEvaluator)
$source=$source.Substring(0,$skyStart)+$skySegment+$source.Substring($skyEnd)
[IO.File]::WriteAllText($target,$source,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    OutputRoot=$outputRoot
    InstrumentedSource=[IO.Path]::GetRelativePath($repo,$target).Replace('\','/')
    SourceSha256=(Get-FileHash -LiteralPath $target).Hash
    CeilingWriteLoops=4
    FloorWriteLoops=4
    Meaning='Isolated copy only. Records reference plane samples and owner, mapped-column or fuzz writes, and the final render pass: BSP, world sprites, masked textures, player sprites, back-screen fill, or sky.'
}
