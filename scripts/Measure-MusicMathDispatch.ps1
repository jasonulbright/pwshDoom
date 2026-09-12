#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[int]$Count=100000)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
function Pow-Standard([double[]]$Values){
    $out=[double[]]::new($Values.Length)
    for([int]$i=0;$i -lt $Values.Length;$i++){$out[$i]=[Math]::Pow(10.0,$Values[$i])}
    return ,$out
}
function Pow-Delegate([double[]]$Values,[Func[double,double,double]]$Power){
    $out=[double[]]::new($Values.Length)
    for([int]$i=0;$i -lt $Values.Length;$i++){$out[$i]=$Power.Invoke(10.0,$Values[$i])}
    return ,$out
}
function Pow-Typed([double[]]$Values){
    $out=[double[]]::new($Values.Length)
    for([int]$i=0;$i -lt $Values.Length;$i++){[double]$value=$Values[$i];$out[$i]=[Math]::Pow(10.0,$value)}
    return ,$out
}
$power=[Math].GetMethod('Pow',[type[]]@([double],[double])).CreateDelegate([Func[double,double,double]])
$values=[double[]]::new($Count);for($i=0;$i -lt $Count;$i++){$values[$i]=(($i%3200)-1600)/1000.0}
$rows=[Collections.Generic.List[object]]::new();$failure=$null
try{
    $a=Pow-Standard $values;$b=Pow-Delegate $values $power;$c=Pow-Typed $values
    for($i=0;$i -lt $Count;$i++){if($a[$i] -ne $b[$i] -or $a[$i] -ne $c[$i]){throw "Mismatch at $i"}}
    for($pass=1;$pass -le 3;$pass++){
        $order=if($pass%2){@('Pow-Standard','Pow-Delegate','Pow-Typed')}else{@('Pow-Typed','Pow-Delegate','Pow-Standard')}
        foreach($name in $order){$w=[Diagnostics.Stopwatch]::StartNew();$out=& $name $values $power;$rows.Add(@{Pass=$pass;Kernel=$name;Milliseconds=$w.Elapsed.TotalMilliseconds;Count=$out.Length})}
    }
}catch{$failure=$_.ToString();throw}finally{
    @{Error=$failure;Count=$Count;Trials=$rows.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;PowerShell=$PSVersionTable.PSVersion.ToString();
      Meaning='Bounded exact-result comparison of standard .NET Math.Pow dispatch from PowerShell. Delegate binds the existing standard method; no compiled custom math. One warmup per kernel, alternating trial order. Not a synthesizer benchmark.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}
$rows|ForEach-Object {[pscustomobject]$_}|Format-Table Pass,Kernel,Milliseconds,Count
