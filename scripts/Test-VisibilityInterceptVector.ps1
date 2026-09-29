#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh visibility-intercept report.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/visibility-intercept-$PID.ps1"
. $bundle
$visibility=[VisibilityCheck]::new($null)
$cases=[Collections.Generic.List[object]]::new();$failure=$null;$randomCount=0;$mismatchTotal=0;$divisionCases=0;$divisionMismatches=0;$mismatches=[Collections.Generic.List[object]]::new()
function New-TestLine([int]$X,[int]$Y,[int]$Dx,[int]$Dy){
    $line=[DivLine]::new();$line.X=[Fixed]::FromInt($X);$line.Y=[Fixed]::FromInt($Y)
    $line.Dx=[Fixed]::FromInt($Dx);$line.Dy=[Fixed]::FromInt($Dy);return $line
}
function New-RawTestLine([int]$X,[int]$Y,[int]$Dx,[int]$Dy){
    $line=[DivLine]::new();$line.X=[Fixed]::new($X);$line.Y=[Fixed]::new($Y)
    $line.Dx=[Fixed]::new($Dx);$line.Dy=[Fixed]::new($Dy);return $line
}
function Get-LegacyInterceptVector([DivLine]$V2,[DivLine]$V1){
    $den=($V1.Dy -shr 8)*$V2.Dx-($V1.Dx -shr 8)*$V2.Dy
    if($den.Data -eq [Fixed]::Zero.Data){return [Fixed]::Zero}
    $num=(($V1.X-$V2.X) -shr 8)*$V1.Dy+(($V2.Y-$V1.Y) -shr 8)*$V1.Dx
    return $num/$den
}
function Check-Intercept([string]$Name,[DivLine]$Trace,[DivLine]$Occluder,[int]$ExpectedData){
    $actual=$visibility.InterceptVector($Trace,$Occluder)
    $actualRaw=$visibility.InterceptVectorData($Trace,$Occluder)
    $passed=$actual.Data -eq $ExpectedData -and $actualRaw -eq $ExpectedData
    $cases.Add(@{Name=$Name;Passed=$passed;ExpectedData=$ExpectedData;ActualData=$actual.Data;ActualRawData=$actualRaw})
    if(-not $passed){throw "Unexpected intercept fraction for $Name."}
}
function Get-RootErrorType($ErrorRecord){
    $exception=$ErrorRecord.Exception
    while($null -ne $exception.InnerException){$exception=$exception.InnerException}
    return $exception.GetType().FullName
}
function Check-Division([int]$Numerator,[int]$Denominator){
    $script:divisionCases++
    $expected=$null;$actual=$null;$expectedError=$null;$actualError=$null
    try{$expected=([Fixed]::new($Numerator)/[Fixed]::new($Denominator)).Data}catch{$expectedError=Get-RootErrorType $_}
    try{$actual=$visibility.DivideFixedData($Numerator,$Denominator)}catch{$actualError=Get-RootErrorType $_}
    if($expectedError -cne $actualError -or ($null -eq $expectedError -and $expected -ne $actual)){
        $script:divisionMismatches++
        throw "Raw Fixed division differs for numerator $Numerator and denominator $Denominator."
    }
}
try{
    # Parallel disjoint lines have a distinct Fixed(0) denominator. The
    # reference implementation compares its numeric Data, not object identity.
    Check-Intercept 'Parallel separated rays return zero' `
        (New-TestLine 0 0 100 0) (New-TestLine 20 10 100 0) 0
    Check-Intercept 'Perpendicular segments intersect halfway' `
        (New-TestLine 0 0 100 0) (New-TestLine 50 -10 0 20) ([Fixed]::FromDouble(.5).Data)

    $divisionEdges=[int[]]@([int]::MinValue,([int]::MinValue+1),-1073741824,-65536,-1,0,1,65536,1073741824,([int]::MaxValue-1),[int]::MaxValue)
    foreach($numerator in $divisionEdges){foreach($denominator in $divisionEdges){Check-Division $numerator $denominator}}

    $random=[Random]::new(20260927);$randomCount=50000
    function New-RandomFixedData([Random]$Random){return [Fixed]::ToInt32Unchecked($Random.NextInt64(0L,4294967296L))}
    for($i=0;$i -lt $randomCount;$i++){
        $trace=New-RawTestLine (New-RandomFixedData $random) (New-RandomFixedData $random) (New-RandomFixedData $random) (New-RandomFixedData $random)
        $occluder=New-RawTestLine (New-RandomFixedData $random) (New-RandomFixedData $random) (New-RandomFixedData $random) (New-RandomFixedData $random)
        $expected=$null;$actual=$null;$expectedError=$null;$actualError=$null
        try{$expected=(Get-LegacyInterceptVector $trace $occluder).Data}catch{$expectedError=$_.Exception.GetType().FullName}
        try{$actual=$visibility.InterceptVector($trace,$occluder).Data;$actualRaw=$visibility.InterceptVectorData($trace,$occluder)}catch{$actualError=$_.Exception.GetType().FullName}
        if($expectedError -cne $actualError -or ($null -eq $expectedError -and ($expected -ne $actual -or $expected -ne $actualRaw))){
            $mismatchTotal++
            if($mismatches.Count -lt 8){$mismatches.Add(@{Case=$i;ExpectedData=$expected;ActualData=$actual;ActualRawData=$actualRaw;ExpectedError=$expectedError;ActualError=$actualError})}
        }
        Check-Division $trace.Dx.Data $occluder.Dy.Data
    }
    if($mismatchTotal){throw "Numeric intercept differs from Fixed reference in $mismatchTotal sampled cases."}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    @{Error=$failure;Passed=($null -eq $failure -and $cases.Count -eq 2 -and @($cases|Where-Object {-not $_.Passed}).Count -eq 0 -and $randomCount -eq 50000 -and $mismatchTotal -eq 0);
        Cases=$cases.ToArray();PowerShell=$PSVersionTable.PSVersion.ToString();BundleSha256=if(Test-Path $bundle){(Get-FileHash $bundle).Hash}else{$null};
        RandomParity=@{Seed=20260927;Count=$randomCount;MismatchCount=$mismatchTotal;MismatchSamples=$mismatches.ToArray()};
        DivisionParity=@{BoundaryInputs=$divisionEdges.Count*$divisionEdges.Count;RandomInputs=$randomCount;Cases=$divisionCases;Reference='Fixed.op_Division';MismatchCount=$divisionMismatches};
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        VisibilitySourceSha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Doom/World/VisibilityCheck.sb.ps1").Hash;
        Meaning='Actual VisibilityCheck.InterceptVector known cases plus deterministic raw-Int32 parity against the prior Fixed-operator expression. Random cases compare result data and exception type; they do not substitute for route, sight, or campaign tests.'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $Output
}
if($failure){throw $failure}
"PASS: $($cases.Count) direct intercept cases, $randomCount deterministic intercept parity cases, and $($divisionEdges.Count*$divisionEdges.Count+$randomCount) raw division parity cases."
