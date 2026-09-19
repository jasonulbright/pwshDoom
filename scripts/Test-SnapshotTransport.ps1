#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Output="$PSScriptRoot/../results/snapshot-correctness.json")
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/SnapshotTransport.ps1"
function ConvertTo-TestValues([byte[]]$bytes) {
    $values=[double[]]::new($bytes.Length/8);[Buffer]::BlockCopy($bytes,0,$values,0,$bytes.Length);return ,$values
}
function Assert-Rejected([byte[]]$bytes) {
    $rejected=$false;try{$null=Read-GameSnapshotBytes $bytes $null}catch{$rejected=$true}
    if(-not $rejected){throw 'A malformed snapshot was accepted.'}
}
# Pair from the same world update: discrete fields match, only positions differ.
$old=[double[]]::new(70);$old[0]=3;$old[1]=42;$old[3]=1;$old[4]=1;$old[5]=1;$old[6]=1
$old[8]=-120.25;$old[9]=490;$old[10]=6.27;$old[11]=41.5
$old[12]=2;$old[15]=0;$old[16]=75;$old[18]=5;$old[20]=19;$old[24]=200;$old[28]=1;$old[34]=1
$old[43]=97
$old[44]=129;$old[45]=13;$old[69]=0x40000
$old[48]=-24;$old[49]=128;$old[50]=3;$old[51]=4;$old[52]=255
$old[53]=10;$old[54]=-8;$old[55]=9;$old[56]=11;$old[57]=12
$old[58]=100;$old[59]=-400;$old[60]=8;$old[61]=1.7;$old[62]=4;$old[63]=32769;$old[64]=144
$old[65]=2;$old[66]=1;$old[67]=160;$old[68]=100
$current=[double[]]$old.Clone();$current[2]=1
$current[43]=145
$current[44]=128;$current[45]=8;$current[69]=0x40002
foreach($i in 8,9,10,11,48,49,58,59,60){$current[$i]+=0.125}
$checks=0
foreach($fraction in 0,0.5,1) {
    $bytes=Get-InterpolatedSnapshotBytes $old $current $fraction
    if($bytes -isnot [byte[]]){throw 'Wire bytes were enumerated by the pipeline.'}
    $actual=ConvertTo-TestValues $bytes
    for($i=0;$i -lt $actual.Length;$i++) {
        $expected=$current[$i]
        if($i -eq 2){$expected=$fraction}
        elseif($i -in 8,9,10,11,48,49,58,59,60){$expected=$old[$i]+0.125*$fraction}
        if([Math]::Abs($actual[$i]-$expected) -gt 1e-12){throw "Interpolation mismatch at $i, fraction $fraction."}
    }
    $state=Read-GameSnapshotBytes $bytes $null
    if(-not [Linq.Enumerable]::SequenceEqual[byte]($bytes,(ConvertTo-GameSnapshotBytes $state))){throw 'All-field wire round trip failed.'}
    $reused=Read-GameSnapshotBytes $bytes $state
    if(-not [object]::ReferenceEquals($state,$reused)){throw 'Decoder did not reuse its private state.'}
    $checks++
}
# Changing actor count must replace the private actor array without stale actors.
$state.Actors=@();$empty=ConvertTo-GameSnapshotBytes $state;$state=Read-GameSnapshotBytes $empty $state
if($state.Actors.Count -ne 0){throw 'Removed actor remained in decoded state.'};$checks++
Assert-Rejected ([byte[]]::new(383));Assert-Rejected ([byte[]]::new(385));$checks+=2
$bad=Get-InterpolatedSnapshotBytes $old $current 1;$bad[0]=1;Assert-Rejected $bad;$checks++
$bad=[byte[]]::new(384);[Buffer]::BlockCopy($current,0,$bad,0,384);Assert-Rejected $bad;$checks++
@{FinishedUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks;Result='Pass';Meaning='Synthetic all-field wire round trips, interpolation endpoints/midpoint, private state reuse, actor removal, and malformed packet rejection. No game assets required.'} |
    ConvertTo-Json | Set-Content $Output
"PASS: $checks snapshot checks."
