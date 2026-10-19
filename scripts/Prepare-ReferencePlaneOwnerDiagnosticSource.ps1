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
    [int[]] $DiagnosticPlaneDistanceData
    [int[]] $DiagnosticPlaneXFracData
    [int[]] $DiagnosticPlaneYFracData
    [int[]] $DiagnosticPlaneLightIndices
    [int[]] $DiagnosticPlaneTexelIndices
    [byte[][]] $DiagnosticPlaneLightMaps
'@
$source=$source.Replace($marker,$fields.TrimEnd([char]13,[char]10))
$nl=[Environment]::NewLine

function Add-PlaneOwnerWrites([string]$text,[string]$methodStart,[string]$methodEnd,[byte]$surfaceType){
    $start=$text.IndexOf($methodStart,[StringComparison]::Ordinal)
    if($start -lt 0){throw "Missing method: $methodStart"}
    $end=$text.IndexOf($methodEnd,$start,[StringComparison]::Ordinal)
    if($end -lt 0){throw "Missing next method: $methodEnd"}
    $segment=$text.Substring($start,$end-$start)
    $pattern='(?m)^(?<indent>[ \t]*)\$pos\+\+\r?$'
    $matches=[regex]::Matches($segment,$pattern)
    if($matches.Count -ne 4){throw "$methodStart expected four plane pixel loops, found $($matches.Count)."}
    $lightMapExpression=if($surfaceType -eq 1){'$localFloorLights[$y]'}else{'$localCeilingLights[$y]'}
    $evaluator=[Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $indent=$match.Groups['indent'].Value
        return $indent+'$this.DiagnosticPlaneOwners[$pos] = $sector'+$nl+
            $indent+'$this.DiagnosticPlaneSurfaceTypes[$pos] = '+$surfaceType+$nl+
            $indent+'$this.DiagnosticFinalWriterTypes[$pos] = 1'+$nl+
            $indent+'$this.DiagnosticPlaneDistanceData[$pos] = [Fixed]::ToInt32Unchecked((([long]$heightData * [long]$localPlaneYSlope[$y]) -shr $fracBits))'+$nl+
            $indent+'$this.DiagnosticPlaneXFracData[$pos] = $xFracData'+$nl+
            $indent+'$this.DiagnosticPlaneYFracData[$pos] = $yFracData'+$nl+
            $indent+'$this.DiagnosticPlaneLightIndices[$pos] = [Math]::Clamp(($this.DiagnosticPlaneDistanceData[$pos] -shr $localZLightShift), 0, $localMaxZLight - 1)'+$nl+
            $indent+'$this.DiagnosticPlaneTexelIndices[$pos] = $flatData[$spot]'+$nl+
            $indent+'$this.DiagnosticPlaneLightMaps[$pos] = '+$lightMapExpression+$nl+
            $match.Value
    }
    $segment=[regex]::Replace($segment,$pattern,$evaluator)
    return $text.Substring(0,$start)+$segment+$text.Substring($end)
}

$source=Add-PlaneOwnerWrites $source '    [void] DrawCeilingColumn(' '    [void] DrawFloorColumn(' 2
$source=Add-PlaneOwnerWrites $source '    [void] DrawFloorColumn(' '    hidden [void] DrawColumnData(' 1

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
        return $match.Value+$nl+$indent+'$this.DiagnosticFinalWriterTypes[$pos] = '+$writerType
    }
    $segment=[regex]::Replace($segment,$pattern,$evaluator)
    return $text.Substring(0,$start)+$segment+$text.Substring($end)
}

$source=Add-FinalWriterMarks $source '    hidden [void] DrawColumnData(' '    [void] DrawColumn(' 2
$source=Add-FinalWriterMarks $source '    hidden [void] DrawColumnTranslationData(' '    [void] DrawColumnTranslation(' 2
$source=Add-FinalWriterMarks $source '    [void] DrawFuzzColumn(' '    [void] DrawSkyColumn(' 3
[IO.File]::WriteAllText($target,$source,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    OutputRoot=$outputRoot
    InstrumentedSource=[IO.Path]::GetRelativePath($repo,$target).Replace('\','/')
    SourceSha256=(Get-FileHash -LiteralPath $target).Hash
    CeilingWriteLoops=4
    FloorWriteLoops=4
    Meaning='Isolated copy only. Records the reference row distance, per-pixel fractions, selected light map, flat texel, owner and later mapped-column or fuzz writes; it does not identify every primitive compositor path.'
}
