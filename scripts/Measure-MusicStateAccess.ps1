#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[ValidateRange(10000,1000000)][int]$Count=200000)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
class MusicStateAccessFixture {
    [long]$Frame
    [double]$Volume=.2
    [double[]]$Generators=[double[]]::new(61)
}
function Read-PropertyState($State,[int]$Count){
    [double]$sum=0
    for([int]$i=0;$i -lt $Count;$i++){$State.Frame+=32;$sum+=$State.Frame*$State.Volume+$State.Generators[8]}
    return $sum
}
function Read-IndexedState([hashtable]$State,[int]$Count){
    [double]$sum=0
    for([int]$i=0;$i -lt $Count;$i++){$State['Frame']+=32;$sum+=$State['Frame']*$State['Volume']+$State['Generators'][8]}
    return $sum
}
$rows=[Collections.Generic.List[object]]::new();$failure=$null
try{
    for($pass=0;$pass -le 3;$pass++){
        $order=if($pass%2){@('HashtableProperty','HashtableIndex','PowerShellClass')}else{@('PowerShellClass','HashtableIndex','HashtableProperty')}
        $expected=$null
        foreach($kind in $order){
            $state=if($kind -eq 'PowerShellClass'){[MusicStateAccessFixture]::new()}else{@{Frame=0L;Volume=.2;Generators=[double[]]::new(61)}}
            $state.Generators[8]=1000
            $watch=[Diagnostics.Stopwatch]::StartNew()
            $sum=if($kind -eq 'HashtableIndex'){Read-IndexedState $state $Count}else{Read-PropertyState $state $Count}
            $elapsed=$watch.Elapsed.TotalMilliseconds
            if($null -eq $expected){$expected=$sum}elseif($sum -ne $expected){throw 'State access candidate changed the checksum.'}
            if($state.Frame -ne $Count*32){throw 'State access candidate changed the frame counter.'}
            if($pass -gt 0){$rows.Add(@{Pass=$pass;Kind=$kind;Milliseconds=$elapsed;Checksum=$sum;Frame=$state.Frame})}
        }
    }
}catch{$failure=$_.ToString();throw}finally{
    @{Error=$failure;Count=$Count;Trials=$rows.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;PowerShell=$PSVersionTable.PSVersion.ToString();
      Meaning='Isolated mutable-state access probe, one warmup and alternating measured order. Class is declared in PowerShell and contains only fields. Not evidence of actual music-render performance.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}
$rows|ForEach-Object {[pscustomobject]$_}|Format-Table Pass,Kind,Milliseconds,Checksum
