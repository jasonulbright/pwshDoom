#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Output="$PSScriptRoot/../results/snapshot-correctness.json")
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/SnapshotTransport.ps1"
if(-not (Get-Command Get-FastSpriteRotation -ErrorAction SilentlyContinue)){throw 'Snapshot transport did not load the shared PowerShell sprite projection helper.'}
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
$checks=1
foreach($fraction in 0,0.5,1) {
    $bytes=Get-InterpolatedSnapshotBytes $old $current $fraction
    if($bytes -isnot [byte[]]){throw 'Wire bytes were enumerated by the pipeline.'}
    $actual=ConvertTo-TestValues $bytes
    for($i=0;$i -lt $actual.Length;$i++) {
        $expected=$current[$i]
        if($i -eq 2){$expected=$fraction}
        elseif($i -eq 7){$expected=1}
        elseif($i -in 8,9,10,11,48,49,58,59,60){$expected=$old[$i]+0.125*$fraction}
        if([Math]::Abs($actual[$i]-$expected) -gt 1e-12){throw "Interpolation mismatch at $i, fraction $fraction."}
    }
    $state=Read-GameSnapshotBytes $bytes $null
    if(-not $state.ActorsDepthSortedForFuzz){throw 'Interpolated fuzz packet did not preserve its prepared actor order.'};$checks++
    if(-not [Linq.Enumerable]::SequenceEqual[byte]($bytes,(ConvertTo-GameSnapshotBytes $state))){throw 'All-field wire round trip failed.'}
    $reused=Read-GameSnapshotBytes $bytes $state
    if(-not [object]::ReferenceEquals($state,$reused)){throw 'Decoder did not reuse its private state.'}
    $checks++
}
# Changing actor count must replace the private actor array without stale actors.
$state.Actors=@();$empty=ConvertTo-GameSnapshotBytes $state;$state=Read-GameSnapshotBytes $empty $state
if($state.Actors.Count -ne 0){throw 'Removed actor remained in decoded state.'};$checks++
# Worker packets extend the fixed NumericV3 simulation fields with one mask per actor.
$v3=ConvertTo-TestValues $bytes;$actorCount=[int]$v3[5]
$v4=[double[]]::new($v3.Length+$actorCount);[Array]::Copy($v3,$v4,$v3.Length);$v4[0]=4
for($i=0;$i -lt $actorCount;$i++){$v4[$v3.Length+$i]=1}
$v4Bytes=[byte[]]::new($v4.Length*8);[Buffer]::BlockCopy($v4,0,$v4Bytes,0,$v4Bytes.Length)
$v4State=Read-GameSnapshotBytes $v4Bytes $null
if($v4State.Actors.Count -ne $actorCount -or $v4State.Actors[0].WorkerMask -ne 1 -or $v4State.RenderActors.Count -ne $actorCount -or $v4State.RenderActorsFiltered){throw 'NumericV4 worker mask did not round-trip.'};$checks++
$filtered=Read-GameSnapshotBytes $v4Bytes $v4State 1L
if(-not $filtered.RenderActorsFiltered -or $filtered.RenderActors.Count -ne $actorCount){throw 'Worker-visible actor selection omitted an included actor.'};$checks++
$renderActorsBuffer=$filtered.RenderActors
$filtered=Read-GameSnapshotBytes $v4Bytes $filtered 2L
if(-not [object]::ReferenceEquals($renderActorsBuffer,$filtered.RenderActors) -or $filtered.RenderActors.Count -ne 0){throw 'Worker actor selection did not reuse and refresh its visible-actor list.'};$checks++
$badV4=[double[]]$v4.Clone();$badV4[$v3.Length]=1.5
$badV4Bytes=[byte[]]::new($badV4.Length*8);[Buffer]::BlockCopy($badV4,0,$badV4Bytes,0,$badV4Bytes.Length);Assert-Rejected $badV4Bytes;$checks++
# NumericV5 carries the same visibility mask plus fixed-point projection data.
$baseLength=$v3.Length;$v5Bytes=[byte[]]::new($bytes.Length+24*$actorCount);[Buffer]::BlockCopy($bytes,0,$v5Bytes,0,$bytes.Length)
[Buffer]::BlockCopy([BitConverter]::GetBytes([double]5),0,$v5Bytes,0,8)
[uint32[]]$v5Masks=[uint32[]]::new($actorCount);$v5Masks[0]=5
[int[]]$v5Projection=[int[]]::new(5*$actorCount);$v5Projection[0]=1;$v5Projection[1]=123456;$v5Projection[2]=-23456;$v5Projection[3]=54321;$v5Projection[4]=3
[Buffer]::BlockCopy($v5Masks,0,$v5Bytes,$bytes.Length,4*$actorCount)
[Buffer]::BlockCopy($v5Projection,0,$v5Bytes,$bytes.Length+4*$actorCount,20*$actorCount)
$v5State=Read-GameSnapshotBytes $v5Bytes $null
if(-not $v5State.RenderProjectionPrepared -or $v5State.RenderProjectionData[0] -ne 1 -or
   $v5State.Actors[0].ProjectionIndex -ne 0 -or $v5State.Actors[0].WorkerMask -ne 5 -or
   $v5State.RenderProjectionData[1] -ne 123456 -or $v5State.RenderProjectionData[2] -ne -23456 -or
   $v5State.RenderProjectionData[3] -ne 54321 -or $v5State.RenderProjectionData[4] -ne 3){throw 'NumericV5 actor projection did not round-trip.'};$checks++
$filteredV5=Read-GameSnapshotBytes $v5Bytes $null 4L
if($filteredV5.RenderActors.Count -ne 1 -or $filteredV5.RenderActors[0].ProjectionIndex -ne 0 -or $filteredV5.RenderProjectionData[4] -ne 3){throw 'NumericV5 worker filter lost its prepared projection.'};$checks++
$badV5=[byte[]]$v5Bytes.Clone();[Buffer]::BlockCopy([BitConverter]::GetBytes([int]2),0,$badV5,$bytes.Length+4*$actorCount,4)
Assert-Rejected $badV5;$checks++
Assert-Rejected ([byte[]]::new(383));Assert-Rejected ([byte[]]::new(385));$checks+=2
$bad=Get-InterpolatedSnapshotBytes $old $current 1;$bad[0]=1;Assert-Rejected $bad;$checks++
$badValues=ConvertTo-TestValues (Get-InterpolatedSnapshotBytes $old $current 1);$badValues[7]=2
$bad=[byte[]]::new($badValues.Length*8);[Buffer]::BlockCopy($badValues,0,$bad,0,$bad.Length);Assert-Rejected $bad;$checks++
$preparedEndpoint=[double[]]$old.Clone();$preparedEndpoint[7]=1
$rejectedPreparedEndpoint=$false;try{$null=Get-InterpolatedSnapshotBytes $preparedEndpoint $current 0.5}catch{$rejectedPreparedEndpoint=$true}
if(-not $rejectedPreparedEndpoint){throw 'Already sorted endpoint was accepted for interpolation.'};$checks++
$bad=[byte[]]::new(384);[Buffer]::BlockCopy($current,0,$bad,0,384);Assert-Rejected $bad;$checks++
@{FinishedUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks;Result='Pass';Meaning='Shared PowerShell sprite-projection helper bootstrap plus synthetic all-field wire round trips, interpolation endpoints/midpoint, private state reuse, actor removal, and malformed packet rejection. No game assets required.'} |
    ConvertTo-Json | Set-Content $Output
"PASS: $checks snapshot checks."
