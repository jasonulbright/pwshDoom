#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [string]$InputRenderer = "$PSScriptRoot/../src/FastRenderer.ps1",
    [Parameter(Mandatory)][string]$Output
)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath=[IO.Path]::GetFullPath($InputRenderer)
$outputPath=[IO.Path]::GetFullPath($Output)
$srcRoot=[IO.Path]::GetFullPath((Join-Path $repo 'src'))
$outputRelative=[IO.Path]::GetRelativePath($srcRoot,$outputPath)
if([IO.Path]::IsPathRooted($outputRelative) -or $outputRelative -eq '..' -or $outputRelative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")){
    throw 'Diagnostic renderer output must remain inside src so its relative imports resolve.'
}
if($sourcePath -eq $outputPath){throw 'Diagnostic renderer cannot overwrite its source.'}
if(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)){throw "Renderer source not found: $sourcePath"}
if(Test-Path -LiteralPath $outputPath){throw 'Use a fresh output path.'}

$source=[IO.File]::ReadAllText($sourcePath)
$newline=if($source.Contains("`r`n")){"`r`n"}else{"`n"}
$boundaryMarker='                [int]$wallLightIndex=47'
if(([regex]::Matches($source,[regex]::Escape($boundaryMarker))).Count -ne 1){throw 'Expected one wall-light boundary marker.'}
$boundaryTrace=@'
                if($Context.ContainsKey('DiagnosticWallSpanTrace') -and $Context.ContainsKey('DiagnosticWallSpanTraceSeen')){
                    [int]$diagnosticWallTraceCell=$segIndex*320+$x
                    [int]$diagnosticWallTraceOffset=$diagnosticWallTraceCell*12
                    [int[]]$diagnosticWallTrace=$Context.DiagnosticWallSpanTrace
                    $Context.DiagnosticWallSpanTraceSeen[$diagnosticWallTraceCell]=1
                    $diagnosticWallTrace[$diagnosticWallTraceOffset]=$wallT
                    $diagnosticWallTrace[$diagnosticWallTraceOffset+1]=$wallB
                    $diagnosticWallTrace[$diagnosticWallTraceOffset+2]=$clipT
                    $diagnosticWallTrace[$diagnosticWallTraceOffset+3]=$clipB
                    $diagnosticWallTrace[$diagnosticWallTraceOffset+4]=$portalT
                    $diagnosticWallTrace[$diagnosticWallTraceOffset+5]=$portalB
                    for([int]$diagnosticWallTraceSlot=6;$diagnosticWallTraceSlot -lt 12;$diagnosticWallTraceSlot++){$diagnosticWallTrace[$diagnosticWallTraceOffset+$diagnosticWallTraceSlot]=-1}
                }
'@.TrimEnd()
$source=$source.Replace($boundaryMarker,$boundaryTrace+$newline+$boundaryMarker)

$intervalMarker='                    if($y0 -gt $y1){continue}'
if(([regex]::Matches($source,[regex]::Escape($intervalMarker))).Count -ne 1){throw 'Expected one clipped wall-band interval marker.'}
$intervalTrace=@'
                    if($Context.ContainsKey('DiagnosticWallSpanTrace') -and $Context.ContainsKey('DiagnosticWallSpanTraceSeen')){
                        [int]$diagnosticWallIntervalOffset=$diagnosticWallTraceOffset+6+(2*$band)
                        $diagnosticWallTrace[$diagnosticWallIntervalOffset]=$y0
                        $diagnosticWallTrace[$diagnosticWallIntervalOffset+1]=$y1
                    }
'@.TrimEnd()
$source=$source.Replace($intervalMarker,$intervalMarker+$newline+$intervalTrace)

[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath))
[IO.File]::WriteAllText($outputPath,$source,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    InputRenderer=[IO.Path]::GetRelativePath($repo,$sourcePath).Replace('\','/')
    DiagnosticRenderer=[IO.Path]::GetRelativePath($repo,$outputPath).Replace('\','/')
    InputRendererSha256=(Get-FileHash -LiteralPath $sourcePath).Hash
    DiagnosticRendererSha256=(Get-FileHash -LiteralPath $outputPath).Hash
    BoundaryTraceStride=12
    Meaning='Disposable source copy only. Captures fixed-point top/bottom boundaries, per-column clip, portal boundaries, and clipped upper/lower/middle texture intervals for each candidate segment-column pair.'
}
