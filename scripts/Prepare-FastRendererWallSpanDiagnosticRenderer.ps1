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
$planeCallCountMarker='Draw-FastPlaneColumnCalls $Context $planeSampleCallCount'
if(([regex]::Matches($source,[regex]::Escape($planeCallCountMarker))).Count -ne 1){throw 'Expected one plane-sample call dispatch.'}
$source=$source.Replace($planeCallCountMarker,'$Context.PlaneSampleCallCount = $planeSampleCallCount'+$newline+'    '+$planeCallCountMarker)
$planeCallSegmentMarker='$planeSampleCalls[$planeSampleCallCount]=$x;'
if(([regex]::Matches($source,[regex]::Escape($planeCallSegmentMarker))).Count -ne 2){throw 'Expected two plane-call append sites.'}
$planeCallSegmentTrace='$planeSampleCalls[$planeSampleCallCount]=$x;if($Context.ContainsKey(''DiagnosticPlaneCallSegIndices'')){[int]$diagnosticPlaneCallIndex=$planeSampleCallCount -shr 2;[int[]]$diagnosticPlaneCallSegIndices=$Context.DiagnosticPlaneCallSegIndices;if($diagnosticPlaneCallIndex -ge $diagnosticPlaneCallSegIndices.Length){[int[]]$grownDiagnosticPlaneCallSegIndices=[int[]]::new([Math]::Max(64,$diagnosticPlaneCallIndex+1));[Array]::Copy($diagnosticPlaneCallSegIndices,$grownDiagnosticPlaneCallSegIndices,$diagnosticPlaneCallSegIndices.Length);$Context.DiagnosticPlaneCallSegIndices=$grownDiagnosticPlaneCallSegIndices;$diagnosticPlaneCallSegIndices=$grownDiagnosticPlaneCallSegIndices};$diagnosticPlaneCallSegIndices[$diagnosticPlaneCallIndex]=$segIndex}'
$source=$source.Replace($planeCallSegmentMarker,$planeCallSegmentTrace)
$opaqueDepthMarker='$p=$y*320+$x;$pixels[$p]=$wallColors[$color];$depthBuffer[$p]=$distance'
if(([regex]::Matches($source,[regex]::Escape($opaqueDepthMarker))).Count -ne 1){throw 'Expected one opaque wall depth write.'}
$opaqueDepthTrace='$p=$y*320+$x;$pixels[$p]=$wallColors[$color];$depthBuffer[$p]=$distance;if($Context.ContainsKey(''DiagnosticDepthOwnerSegIndices'')){$Context.DiagnosticDepthOwnerSegIndices[$p]=$segIndex+1;$Context.DiagnosticDepthOwnerWriterTypes[$p]=1}'
$source=$source.Replace($opaqueDepthMarker,$opaqueDepthTrace)
$untexturedDepthMarker='[int]$p=$y*320+$x;if($distance -lt $depthBuffer[$p]){$depthBuffer[$p]=$distance;'
if(([regex]::Matches($source,[regex]::Escape($untexturedDepthMarker))).Count -ne 3){throw 'Expected three untextured wall depth writes.'}
$untexturedDepthTrace='[int]$p=$y*320+$x;if($distance -lt $depthBuffer[$p]){$depthBuffer[$p]=$distance;if($Context.ContainsKey(''DiagnosticDepthOwnerSegIndices'')){$Context.DiagnosticDepthOwnerSegIndices[$p]=$segIndex+1;$Context.DiagnosticDepthOwnerWriterTypes[$p]=2}'
$source=$source.Replace($untexturedDepthMarker,$untexturedDepthTrace)
$maskedColumnReuseMarker='$maskedColumn.X=$x;$maskedColumn.Y0=$y0;$maskedColumn.Y1=$y1;$maskedColumn.Distance=$distance'
if(([regex]::Matches($source,[regex]::Escape($maskedColumnReuseMarker))).Count -ne 1){throw 'Expected one reused masked-column initializer.'}
$source=$source.Replace($maskedColumnReuseMarker,'$maskedColumn.X=$x;$maskedColumn.Y0=$y0;$maskedColumn.Y1=$y1;$maskedColumn.SegIndex=$segIndex;$maskedColumn.Distance=$distance')
$maskedColumnCreateMarker='@{X=$x;Y0=$y0;Y1=$y1;Distance=$distance'
if(([regex]::Matches($source,[regex]::Escape($maskedColumnCreateMarker))).Count -ne 1){throw 'Expected one new masked-column initializer.'}
$source=$source.Replace($maskedColumnCreateMarker,'@{X=$x;Y0=$y0;Y1=$y1;SegIndex=$segIndex;Distance=$distance')
$maskedDepthMarker='if($color -ge 0){$pixels[$p]=$colors[$color];$depthBuffer[$p]=$distance;$Context.ActorDepthBypassMask[$p]=0;$Context.ActorDepthBypassLowerHeightData[$p]=0}'
if(([regex]::Matches($source,[regex]::Escape($maskedDepthMarker))).Count -ne 1){throw 'Expected one masked-column depth write.'}
$maskedDepthTrace='if($color -ge 0){$pixels[$p]=$colors[$color];$depthBuffer[$p]=$distance;$Context.ActorDepthBypassMask[$p]=0;$Context.ActorDepthBypassLowerHeightData[$p]=0;if($Context.ContainsKey(''DiagnosticDepthOwnerSegIndices'')){$Context.DiagnosticDepthOwnerSegIndices[$p]=$column.SegIndex+1;$Context.DiagnosticDepthOwnerWriterTypes[$p]=3}}'
$source=$source.Replace($maskedDepthMarker,$maskedDepthTrace)
$upperPlaneMarker='for([int]$y=$clipT;$y -le $upperPlaneEnd;$y++){$planes[$y*320+$x]=$upperPlaneId}'
if(([regex]::Matches($source,[regex]::Escape($upperPlaneMarker))).Count -ne 1){throw 'Expected one upper-plane ownership loop.'}
$source=$source.Replace($upperPlaneMarker,'for([int]$y=$clipT;$y -le $upperPlaneEnd;$y++){$planes[$y*320+$x]=$upperPlaneId;if($Context.ContainsKey(''DiagnosticPlaneOwnerSegIndices'')){$Context.DiagnosticPlaneOwnerSegIndices[$y*320+$x]=$segIndex+1}}')
$lowerPlaneMarker='for([int]$y=$lowerPlaneStart;$y -le $clipB;$y++){$planes[$y*320+$x]=$lowerPlaneId}'
if(([regex]::Matches($source,[regex]::Escape($lowerPlaneMarker))).Count -ne 1){throw 'Expected one lower-plane ownership loop.'}
$source=$source.Replace($lowerPlaneMarker,'for([int]$y=$lowerPlaneStart;$y -le $clipB;$y++){$planes[$y*320+$x]=$lowerPlaneId;if($Context.ContainsKey(''DiagnosticPlaneOwnerSegIndices'')){$Context.DiagnosticPlaneOwnerSegIndices[$y*320+$x]=$segIndex+1}}')
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

$wallSampleMarker='$v=($v%$th+$th)%$th;[int]$color=$td[$tu*$th+$v]'
if(([regex]::Matches($source,[regex]::Escape($wallSampleMarker))).Count -ne 1){throw 'Expected one opaque wall texture-sample marker.'}
$wallSampleTrace='if($color -ge 0 -and $Context.ContainsKey(''DiagnosticWallSampleTextureIds'')){[int]$diagnosticWallSamplePosition=$y*320+$x;$Context.DiagnosticWallSampleTextureIds[$diagnosticWallSamplePosition]=$tex;$Context.DiagnosticWallSampleBands[$diagnosticWallSamplePosition]=$band;$Context.DiagnosticWallSampleColumns[$diagnosticWallSamplePosition]=$tu;$Context.DiagnosticWallSampleRows[$diagnosticWallSamplePosition]=$v;$Context.DiagnosticWallSampleFractions[$diagnosticWallSamplePosition]=$vf;$Context.DiagnosticWallSampleOrigins[$diagnosticWallSamplePosition]=$vOrigin;$Context.DiagnosticWallSampleTexelSteps[$diagnosticWallSamplePosition]=$wallTexelStep;$Context.DiagnosticWallSampleTextureHeights[$diagnosticWallSamplePosition]=$th;$Context.DiagnosticWallSampleSourceColors[$diagnosticWallSamplePosition]=$color;$Context.DiagnosticWallSampleMappedColors[$diagnosticWallSamplePosition]=$wallColors[$color];$Context.DiagnosticWallSampleLightIndexes[$diagnosticWallSamplePosition]=$wallLight}'
$source=$source.Replace($wallSampleMarker,$wallSampleMarker+$newline+'                        '+$wallSampleTrace)

[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath))
[IO.File]::WriteAllText($outputPath,$source,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    InputRenderer=[IO.Path]::GetRelativePath($repo,$sourcePath).Replace('\','/')
    DiagnosticRenderer=[IO.Path]::GetRelativePath($repo,$outputPath).Replace('\','/')
    InputRendererSha256=(Get-FileHash -LiteralPath $sourcePath).Hash
    DiagnosticRendererSha256=(Get-FileHash -LiteralPath $outputPath).Hash
    BoundaryTraceStride=12
    DepthOwnerWriterTypes=[ordered]@{1='Opaque wall band';2='Untextured wall occlusion';3='Masked middle texture'}
    Meaning='Disposable source copy only. Captures candidate depth-writing segment and writer type alongside plane-owner segment indices, fixed-point wall boundaries, per-column clip, portal boundaries, clipped upper/lower/middle texture intervals, and the plane-sample call count for row-level recurrence traces.'
}
