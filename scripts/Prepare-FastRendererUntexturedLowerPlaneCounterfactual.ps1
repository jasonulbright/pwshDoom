#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InputRenderer,
    [Parameter(Mandatory)][string]$Output
)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourcePath=[IO.Path]::GetFullPath($InputRenderer)
$outputPath=[IO.Path]::GetFullPath($Output)
$srcRoot=[IO.Path]::GetFullPath((Join-Path $repo 'src'))
$outputRelative=[IO.Path]::GetRelativePath($srcRoot,$outputPath)
if([IO.Path]::IsPathRooted($outputRelative) -or $outputRelative -eq '..' -or $outputRelative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")){
    throw 'Counterfactual renderer output must remain inside src so its relative imports resolve.'
}
if($sourcePath -eq $outputPath){throw 'Counterfactual renderer cannot overwrite its source.'}
if(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)){throw "Renderer source not found: $sourcePath"}
if(Test-Path -LiteralPath $outputPath){throw 'Use a fresh output path.'}

$source=[IO.File]::ReadAllText($sourcePath)
$lowerBandMarker='[int]$lowerTop=[Math]::Max($clipT,$portalB+1);[int]$lowerBottom=[Math]::Min($clipB,$wallB)'
if(([regex]::Matches($source,[regex]::Escape($lowerBandMarker))).Count -ne 1){throw 'Expected one untextured lower-band interval.'}
$lowerPlaneCounterfactual=@'
[int]$lowerTop=[Math]::Max($clipT,$portalB+1);[int]$lowerBottom=[Math]::Min($clipB,$wallB)
                    if(-not $solid -and $segBack -ge 0 -and $bf -eq $fh -and $lowerTop -eq $lowerBottom){
                        [int]$counterfactualBackFloorPlaneId=2+($segBack*2)
                        for([int]$counterfactualY=$lowerTop;$counterfactualY -le $lowerBottom;$counterfactualY++){$planes[$counterfactualY*320+$x]=$counterfactualBackFloorPlaneId}
                        if($planeSampleCallCount+4 -gt $planeSampleCalls.Length){
                            [int[]]$counterfactualGrownPlaneCalls=[int[]]::new([Math]::Max(16384,$planeSampleCalls.Length*2))
                            [Array]::Copy($planeSampleCalls,$counterfactualGrownPlaneCalls,$planeSampleCallCount);$Context.PlaneSampleCalls=$counterfactualGrownPlaneCalls;$planeSampleCalls=$counterfactualGrownPlaneCalls
                        }
                        $planeSampleCalls[$planeSampleCallCount]=$x;$planeSampleCalls[$planeSampleCallCount+1]=$lowerTop;$planeSampleCalls[$planeSampleCallCount+2]=$lowerBottom;$planeSampleCalls[$planeSampleCallCount+3]=$counterfactualBackFloorPlaneId;$planeSampleCallCount+=4
                    }
'@.TrimEnd()
$source=$source.Replace($lowerBandMarker,$lowerPlaneCounterfactual)

[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath))
[IO.File]::WriteAllText($outputPath,$source,[Text.UTF8Encoding]::new($false))
[pscustomobject]@{
    InputRenderer=[IO.Path]::GetRelativePath($repo,$sourcePath).Replace('\','/')
    CounterfactualRenderer=[IO.Path]::GetRelativePath($repo,$outputPath).Replace('\','/')
    InputRendererSha256=(Get-FileHash -LiteralPath $sourcePath).Hash
    CounterfactualRendererSha256=(Get-FileHash -LiteralPath $outputPath).Hash
    Meaning='Disposable source copy only. For equal front/back floor heights and a one-row untextured lower band, assigns the back-sector floor plane to that row and records it as a candidate plane call; production source is not edited.'
}
