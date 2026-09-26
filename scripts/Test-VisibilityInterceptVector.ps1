#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh visibility-intercept report.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/visibility-intercept-$PID.ps1"
. $bundle
$visibility=[VisibilityCheck]::new($null)
$cases=[Collections.Generic.List[object]]::new();$failure=$null
function New-TestLine([int]$X,[int]$Y,[int]$Dx,[int]$Dy){
    $line=[DivLine]::new();$line.X=[Fixed]::FromInt($X);$line.Y=[Fixed]::FromInt($Y)
    $line.Dx=[Fixed]::FromInt($Dx);$line.Dy=[Fixed]::FromInt($Dy);return $line
}
function Check-Intercept([string]$Name,[DivLine]$Trace,[DivLine]$Occluder,[int]$ExpectedData){
    $actual=$visibility.InterceptVector($Trace,$Occluder)
    $passed=$actual.Data -eq $ExpectedData
    $cases.Add(@{Name=$Name;Passed=$passed;ExpectedData=$ExpectedData;ActualData=$actual.Data})
    if(-not $passed){throw "Unexpected intercept fraction for $Name."}
}
try{
    # Parallel disjoint lines have a distinct Fixed(0) denominator. The
    # reference implementation compares its numeric Data, not object identity.
    Check-Intercept 'Parallel separated rays return zero' `
        (New-TestLine 0 0 100 0) (New-TestLine 20 10 100 0) 0
    Check-Intercept 'Perpendicular segments intersect halfway' `
        (New-TestLine 0 0 100 0) (New-TestLine 50 -10 0 20) ([Fixed]::FromDouble(.5).Data)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    @{Error=$failure;Passed=($null -eq $failure -and $cases.Count -eq 2 -and @($cases|Where-Object {-not $_.Passed}).Count -eq 0);
        Cases=$cases.ToArray();PowerShell=$PSVersionTable.PSVersion.ToString();BundleSha256=if(Test-Path $bundle){(Get-FileHash $bundle).Hash}else{$null};
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        VisibilitySourceSha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Doom/World/VisibilityCheck.sb.ps1").Hash;
        Meaning='Actual VisibilityCheck.InterceptVector denominator-zero early-out and known nonparallel fraction. The zero case is the PowerShell Fixed object-equality boundary.'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $Output
}
if($failure){throw $failure}
"PASS: $($cases.Count) sight-intercept cases."
