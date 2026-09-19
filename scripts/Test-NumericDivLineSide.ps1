#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[ValidateRange(1,100000)][int]$RandomCases=20000)
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Use a fresh side-comparison report.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/fixtures/DivLineSideReference.ps1";. "$PSScriptRoot/FrameCodec.ps1"
$failure=$null;$comparisons=0;$knownChecks=0;$firstMismatch=$null
$cases=[Collections.Generic.List[object]]::new();$counts=[int[]]::new(3);$times=[Collections.Generic.List[object]]::new()
$seed=20260919;$random=[Random]::new($seed);$zero=[Fixed]::Zero
function Add-Case([int[]]$Numbers,[int]$Expected=-1){
    $line=[DivLine]::new();$line.X=[Fixed]::new($Numbers[2]);$line.Y=[Fixed]::new($Numbers[3]);$line.Dx=[Fixed]::new($Numbers[4]);$line.Dy=[Fixed]::new($Numbers[5])
    $node=[Node]::new($line.X,$line.Y,$line.Dx,$line.Dy,$zero,$zero,$zero,$zero,$zero,$zero,$zero,$zero,0,0)
    $cases.Add(@{X=[Fixed]::new($Numbers[0]);Y=[Fixed]::new($Numbers[1]);Line=$line;Node=$node;Expected=$Expected;Numbers=$Numbers})
}
try{
    foreach($point in -65536,0,65536){
        Add-Case @($point,0,0,0,0,65536) $(if($point -lt 0){1}elseif($point -gt 0){0}else{2})
        Add-Case @(0,$point,0,0,65536,0) $(if($point -lt 0){0}elseif($point -gt 0){1}else{2})
        Add-Case @($point,0,0,0,0,-65536) $(if($point -lt 0){0}elseif($point -gt 0){1}else{2})
        Add-Case @(0,$point,0,0,-65536,0) $(if($point -lt 0){1}elseif($point -gt 0){0}else{2})
    }
    Add-Case @(65536,0,0,0,65536,65536) 0
    Add-Case @(0,65536,0,0,65536,65536) 1
    Add-Case @(65536,65536,0,0,65536,65536) 2
    # Wrap, negative-shift, sub-unit truncation and zero-length boundaries.
    $edges=@([int]::MinValue,([int]::MinValue+1),-65537,-65536,-65535,-1,0,1,65535,65536,65537,([int]::MaxValue-1),[int]::MaxValue)
    foreach($x in $edges){foreach($y in $edges){foreach($dx in $edges){
        Add-Case @($x,$y,[int]::MaxValue,[int]::MinValue,$dx,($edges[($cases.Count+5)%$edges.Count]))
    }}}
    for($i=0;$i -lt $RandomCases;$i++){
        $values=[int[]]::new(6);for($j=0;$j -lt 6;$j++){$values[$j]=$random.NextInt64(-2147483648L,2147483648L)}
        switch($i%8){0{$values[4]=0}1{$values[5]=0}2{$values[0]=$values[2];$values[1]=$values[3]}3{$values[4]=0;$values[5]=0}}
        Add-Case $values
    }
    foreach($case in $cases){
        foreach($field in 'Line','Node'){
            $expected=[RetainedDivLineSide]::DivLineSide($case.X,$case.Y,$case[$field])
            $actual=[Geometry]::DivLineSide($case.X,$case.Y,$case[$field]);$comparisons++
            if($actual -ne $expected -or ($case.Expected -ge 0 -and $actual -ne $case.Expected)){
                $firstMismatch=@{Numbers=$case.Numbers;Kind=$field;Expected=$expected;Analytic=$case.Expected;Actual=$actual};throw 'Numeric side differs from reference or analytic result.'
            }
            $counts[$actual]++;if($case.Expected -ge 0){$knownChecks++}
        }
    }
    # Same stored arguments; object construction excluded. Alternate order and
    # retain every batch. Cover axes, exact endpoints and general diagonal cases.
    $bench=@($cases|Select-Object -Last 1024);$answers=[int[]]::new(2*$bench.Count)
    for($round=0;$round -lt 32;$round++){
        foreach($kind in $(if($round%2 -eq 0){@('Reference','Numeric')}else{@('Numeric','Reference')})){
            $index=0;$watch=[Diagnostics.Stopwatch]::StartNew()
            if($kind -eq 'Reference'){
                foreach($case in $bench){$answers[$index++]=[RetainedDivLineSide]::DivLineSide($case.X,$case.Y,$case.Line);$answers[$index++]=[RetainedDivLineSide]::DivLineSide($case.X,$case.Y,$case.Node)}
            }else{
                foreach($case in $bench){$answers[$index++]=[Geometry]::DivLineSide($case.X,$case.Y,$case.Line);$answers[$index++]=[Geometry]::DivLineSide($case.X,$case.Y,$case.Node)}
            }
            $milliseconds=$watch.Elapsed.TotalMilliseconds
            $bytes=[byte[]]::new($answers.Length*4);[Buffer]::BlockCopy($answers,0,$bytes,0,$bytes.Length)
            $times.Add(@{Round=$round;Kind=$kind;Calls=$answers.Length;Milliseconds=$milliseconds;AnswerSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))})
        }
    }
    if(@($times.AnswerSha256|Select-Object -Unique).Count -ne 1){throw 'Benchmark answer hashes differ.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    @{Error=$failure;Comparisons=$comparisons;AnalyticChecks=$knownChecks;SideCounts=$counts;Seed=$seed;RandomCases=$RandomCases;
        FirstMismatch=$firstMismatch;Samples=$times.ToArray();ReferenceBatchMs=if($times.Count){Get-SampleStats ([double[]]@($times|Where-Object Kind -eq Reference|ForEach-Object Milliseconds))};
        NumericBatchMs=if($times.Count){Get-SampleStats ([double[]]@($times|Where-Object Kind -eq Numeric|ForEach-Object Milliseconds))};
        GeometrySha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Doom/Math/Geometry.sb.ps1").Hash;
        ReferenceSha256=(Get-FileHash "$PSScriptRoot/fixtures/DivLineSideReference.ps1").Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;BundleSha256=(Get-FileHash $bundle).Hash;
        Meaning='Two actual Geometry.DivLineSide overloads versus retained pre-change methods, analytic axis/diagonal cases, signed wrap/shift boundaries and deterministic full-int32 random values. Paired warm microbenchmarks retain all 32 batches per path; allocations of input objects and answer hashing excluded. No full-host/FPS claim.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $comparisons reference comparisons and $knownChecks analytic checks."
