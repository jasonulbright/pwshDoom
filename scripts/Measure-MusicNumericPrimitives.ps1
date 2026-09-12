#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[ValidateRange(10000,1000000)][int]$Count=200000)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
function Floor-Standard([double[]]$Values){
    [int[]]$out=[int[]]::new($Values.Length)
    for([int]$i=0;$i -lt $Values.Length;$i++){$out[$i]=[Math]::Floor($Values[$i])}
    return ,$out
}
function Floor-RoundCorrect([double[]]$Values){
    [int[]]$out=[int[]]::new($Values.Length)
    for([int]$i=0;$i -lt $Values.Length;$i++){
        [double]$value=$Values[$i];[int]$rounded=$value;if($rounded -gt $value){$rounded--};$out[$i]=$rounded
    }
    return ,$out
}
function Finite-Standard([double[]]$Values){
    [bool[]]$out=[bool[]]::new($Values.Length)
    for([int]$i=0;$i -lt $Values.Length;$i++){$out[$i]=[double]::IsFinite($Values[$i])}
    return ,$out
}
function Finite-Range([double[]]$Values){
    [bool[]]$out=[bool[]]::new($Values.Length);[double]$limit=[double]::MaxValue;[double]$lower=-$limit
    for([int]$i=0;$i -lt $Values.Length;$i++){
        [double]$value=$Values[$i];$out[$i]=$value -le $limit -and $value -ge $lower
    }
    return ,$out
}
$phases=[double[]]::new($Count);$samples=[double[]]::new($Count)
for($i=0;$i -lt $Count;$i++){$phases[$i]=($i*1.125)%100000;$samples[$i]=($i%65536)-32768.5}
$edge=[double[]]@(-[double]::MaxValue,[double]::MaxValue,[double]::NegativeInfinity,[double]::PositiveInfinity,[double]::NaN,0,-0.0,[double]::Epsilon)
[Array]::Copy($edge,$samples,$edge.Length)
$rows=[Collections.Generic.List[object]]::new();$failure=$null
try{
    $floorA=Floor-Standard $phases;$floorB=Floor-RoundCorrect $phases;$finiteA=Finite-Standard $samples;$finiteB=Finite-Range $samples
    for($i=0;$i -lt $Count;$i++){if($floorA[$i] -ne $floorB[$i] -or $finiteA[$i] -ne $finiteB[$i]){throw "Numeric candidate mismatch at $i"}}
    for($pass=1;$pass -le 3;$pass++){
        $order=if($pass%2){@('Floor-Standard','Floor-RoundCorrect','Finite-Standard','Finite-Range')}else{@('Finite-Range','Finite-Standard','Floor-RoundCorrect','Floor-Standard')}
        foreach($name in $order){
            $values=if($name.StartsWith('Floor')){$phases}else{$samples}
            $w=[Diagnostics.Stopwatch]::StartNew();$out=& $name $values;$ms=$w.Elapsed.TotalMilliseconds
            $rows.Add(@{Pass=$pass;Kernel=$name;Milliseconds=$ms;Count=$out.Length})
        }
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Count=$Count;Trials=$rows.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;PowerShell=$PSVersionTable.PSVersion.ToString();
      Meaning='Bounded numeric-operation probe with one warmup and alternating measured order. Candidate floor is limited to nonnegative sample positions safely below Int32 maximum. Includes output allocation and function dispatch. Does not establish game or synthesizer performance.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}
$rows|ForEach-Object {[pscustomobject]$_}|Format-Table Pass,Kernel,Milliseconds,Count
