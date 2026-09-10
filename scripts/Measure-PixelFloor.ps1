#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
function Invoke-PixelMethod([byte[]]$pixels,[double[]]$depth,[byte[]]$flat,[byte[]]$colors) {
    [double]$du=3.41;[double]$dv=-1.72;[double]$wu=2340.2;[double]$wv=-4433.3;[double]$d=420
    for([int]$y=0;$y -lt 168;$y++) {
        [int]$row=$y*320
        for([int]$x=160;$x -lt 180;$x++) {
            [int]$u=[int][Math]::Floor($wu+($x+0.5-160)*$du) -band 63
            [int]$v=[int][Math]::Floor(-($wv+($x+0.5-160)*$dv)) -band 63
            [int]$p=$row+$x;$pixels[$p]=$colors[$flat[$v*64+$u]];$depth[$p]=$d
        }
    }
}
function Invoke-PixelCast([byte[]]$pixels,[double[]]$depth,[byte[]]$flat,[byte[]]$colors) {
    [double]$du=3.41;[double]$dv=-1.72;[double]$wu=2340.2;[double]$wv=-4433.3;[double]$d=420
    for([int]$y=0;$y -lt 168;$y++) {
        [int]$row=$y*320
        for([int]$x=160;$x -lt 180;$x++) {
            [double]$uf=$wu+($x+0.5-160)*$du;[int]$u=$uf;if($u -gt $uf){$u--};$u=$u -band 63
            [double]$vf=-($wv+($x+0.5-160)*$dv);[int]$v=$vf;if($v -gt $vf){$v--};$v=$v -band 63
            [int]$p=$row+$x;$pixels[$p]=$colors[$flat[$v*64+$u]];$depth[$p]=$d
        }
    }
}
$checks=0
foreach($whole in @(-10000000,-65536,-4096,-1,0,1,4096,65536,10000000)) {
    foreach($fraction in @(-.999999,-.500001,-.5,-.499999,-.000001,0,.000001,.499999,.5,.500001,.999999)) {
        [double]$value=$whole+$fraction;[int]$actual=$value;if($actual -gt $value){$actual--}
        if($actual -ne [Math]::Floor($value)){throw 'Signed floor boundary mismatch.'};$checks++
    }
}
$p=[byte[]]::new(64000);$q=[byte[]]::new(64000);$d=[double[]]::new(64000);$f=[byte[]]::new(4096);$c=[byte[]]::new(256)
for($i=0;$i -lt 4096;$i++){$f[$i]=($i*73+($i -shr 6)*19)%256}
for($i=0;$i -lt 256;$i++){$c[$i]=255-$i}
$method=[Collections.Generic.List[double]]::new();$cast=[Collections.Generic.List[double]]::new()
for($i=0;$i -lt 48;$i++) {
    $watch=[Diagnostics.Stopwatch]::StartNew();Invoke-PixelMethod $p $d $f $c;$ms=$watch.Elapsed.TotalMilliseconds;if($i -ge 16){$method.Add($ms)}
    $watch.Restart();Invoke-PixelCast $q $d $f $c;$ms=$watch.Elapsed.TotalMilliseconds;if($i -ge 16){$cast.Add($ms)}
}
if(-not [Linq.Enumerable]::SequenceEqual[byte]($p,$q)){throw 'Pixel buffers differ.'}
@{FinishedUtc=[DateTime]::UtcNow.ToString('o');SignedBoundaryCases=$checks;PixelsEqual=$true;PixelsPerCall=3360;Warmup=16;Samples=32;
    MathFloorMs=(Get-SampleStats $method.ToArray());CastCorrectMs=(Get-SampleStats $cast.ToArray());MethodSamplesMs=$method.ToArray();CastSamplesMs=$cast.ToArray();
    Meaning='Isolated floor UV sampling microbenchmark. Both algorithms produce identical nonuniform pixels. Cast correction is for finite coordinates safely inside Int32 range, not a general replacement at the Int32 limits. This is not a whole-renderer speedup measurement.'} |
    ConvertTo-Json -Depth 5 | Set-Content "$PSScriptRoot/../results/pixel-floor.json"
'PASS: pixel equality and signed floor boundaries; microbenchmark saved.'
