#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/CaptureTimeline.ps1";. "$PSScriptRoot/../src/CaptureClock.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null;$details=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $Name $rejected}
function Fixture {
    return @{Error=$null;Rate=44100;Channels=2;Bits=16;Closed=$true;Frames=8;Packets=@(
        @{Index=0;OutputFrame=0;Frames=4;Qpc100ns=1000000;Flags=0},
        @{Index=1;OutputFrame=4;Frames=4;Qpc100ns=1000907;Flags=0})}
}
try{
    $r=Fixture;$p=New-DoomCaptureTimelinePlan $r 1000000 8
    Check 'Contiguous packets retain every sample with no padding' ($p.CopiedFrames -eq 8 -and $p.ZeroFilledFrames -eq 0 -and $p.TimestampAdjustments.Count -eq 0)
    $r.Packets[1].Qpc100ns=1001361;$p=New-DoomCaptureTimelinePlan $r 1000000 10
    Check 'Clock gap explicitly reserves two frames instead of collapsing time' ($p.CopiedFrames -eq 8 -and $p.ZeroFilledIntervals.Count -eq 1 -and $p.ZeroFilledIntervals[0].Frame -eq 4 -and $p.ZeroFilledIntervals[0].Frames -eq 2 -and $p.Placements[1].OutputFrame -eq 6)
    $dir=Join-Path "$PSScriptRoot/../local" ('timeline-test-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($dir)
    $source=Join-Path $dir 'source.wav';$w=[IO.BinaryWriter]::new([IO.File]::Create($source))
    try{$w.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$w.Write([uint32]68);$w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '));$w.Write([uint32]16);$w.Write([uint16]1);$w.Write([uint16]2);$w.Write([uint32]44100);$w.Write([uint32]176400);$w.Write([uint16]4);$w.Write([uint16]16);$w.Write([Text.Encoding]::ASCII.GetBytes('data'));$w.Write([uint32]32);for($i=1;$i -le 8;$i++){$w.Write([int16]$i);$w.Write([int16](-$i))}}finally{$w.Dispose()}
    $r.WavPath=$source;$r.WavSha256=(Get-FileHash $source).Hash;$outWav=Join-Path $dir 'placed.wav';Write-DoomCaptureTimeline $r $p $outWav
    $bytes=[IO.File]::ReadAllBytes($outWav);$actual=[int16[]]::new(20);[Buffer]::BlockCopy($bytes,44,$actual,0,40)
    Check 'Actual WAV preserves both channels around explicit zero gap' (($actual -join ',') -ceq '1,-1,2,-2,3,-3,4,-4,0,0,0,0,5,-5,6,-6,7,-7,8,-8' -and $bytes.Length -eq 84 -and [BitConverter]::ToUInt32($bytes,40) -eq 40)
    Reject 'Existing output is not overwritten' {Write-DoomCaptureTimeline $r $p $outWav}
    $r=Fixture;$p=New-DoomCaptureTimelinePlan $r 1000454 5
    Check 'Beginning and end trim address exact source frames' ($p.CopiedFrames -eq 5 -and $p.TrimmedSourceFrames -eq 3 -and $p.Placements[0].SourceFrame -eq 2 -and $p.Placements[1].Frames -eq 3)
    $p=New-DoomCaptureTimelinePlan $r 999546 12
    Check 'Outside capture coverage has explicit leading and trailing padding' ($p.ZeroFilledIntervals.Count -eq 2 -and $p.ZeroFilledIntervals[0].Frames -eq 2 -and $p.ZeroFilledIntervals[1].Frames -eq 2)
    $r.Packets[1].Qpc100ns=1000680;$p=New-DoomCaptureTimelinePlan $r 1000000 8
    Check 'One-sample clock jitter is reported without dropping samples' ($p.CopiedFrames -eq 8 -and $p.TimestampAdjustments.Count -eq 1 -and $p.Placements[1].OutputFrame -eq 4)
    $r.Packets[1].Qpc100ns=1000454;Reject 'Larger overlapping timestamp fails instead of dropping samples' {$null=New-DoomCaptureTimelinePlan $r 1000000 8}
    $r=Fixture;$r.Packets[1].Flags=4;Reject 'Timestamp-error flag rejects placement' {$null=New-DoomCaptureTimelinePlan $r 1000000 8}
    $r=Fixture;$r.Packets[1].OutputFrame=5;Reject 'Malformed packet/source mapping is rejected' {$null=New-DoomCaptureTimelinePlan $r 1000000 8}
    $r=Fixture;$r.Frames=9;Reject 'Unaccounted source frames are rejected' {$null=New-DoomCaptureTimelinePlan $r 1000000 8}
    $anchors=@(@{QpcBefore=10000000L;QpcAfter=10000020L;Frequency=10000000L;PreciseUnix100ns=17000000000000010L;RegularUnix100ns=17000000000000010L},@{QpcBefore=20000000L;QpcAfter=20000020L;Frequency=10000000L;PreciseUnix100ns=17000000010000010L;RegularUnix100ns=17000000010000010L})
    $clock=ConvertTo-DoomCaptureQpcOrigin $anchors 1700000000000000d
    Check 'Clock conversion retains exact epoch arithmetic and brackets' ($clock.OriginQpc100ns -eq 10000000 -and $clock.OffsetSpreadMilliseconds -eq 0 -and $clock.MaximumBracketMilliseconds -eq .002)
    $anchors[1].PreciseUnix100ns+=30000;Reject 'Clock step beyond stated bound is rejected' {$null=ConvertTo-DoomCaptureQpcOrigin $anchors 1700000000000000d}
    $details=@{Directory=$dir;TimelineWavSha256=(Get-FileHash $outWav).Hash;ClockFixture=$clock}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Details=$details;Sources=@('src/CaptureTimeline.ps1','src/CaptureClock.ps1','scripts/Test-CaptureTimeline.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});Meaning='Synthetic sample/timestamp placement, actual WAV bytes, rejection policies and exact UTC/QPC arithmetic. Not a live capture, measured A/V sync or performance test.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) capture timeline checks."
