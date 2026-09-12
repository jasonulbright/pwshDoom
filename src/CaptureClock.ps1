# SPDX-License-Identifier: GPL-2.0-or-later
# Recorder-only Windows clock ABI. All clock sampling/conversion is PowerShell.
function Initialize-DoomCaptureClockApi {
    if('PwshDoomCapture.ClockApi' -as [type]){return}
    Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace PwshDoomCapture {
 public static class ClockApi {
  [DllImport("kernel32.dll")] public static extern void GetSystemTimePreciseAsFileTime(out long time);
  [DllImport("kernel32.dll")] public static extern void GetSystemTimeAsFileTime(out long time);
 }
}
'@
}
function Get-DoomCaptureClockAnchor {
    Initialize-DoomCaptureClockApi
    $best=$null
    for($i=0;$i -lt 8;$i++){
        [long]$precise=0;[long]$regular=0
        $before=[Diagnostics.Stopwatch]::GetTimestamp()
        [PwshDoomCapture.ClockApi]::GetSystemTimePreciseAsFileTime([ref]$precise)
        [PwshDoomCapture.ClockApi]::GetSystemTimeAsFileTime([ref]$regular)
        $after=[Diagnostics.Stopwatch]::GetTimestamp()
        if($null -eq $best -or $after-$before -lt $best.BracketTicks){
            $best=@{QpcBefore=$before;QpcAfter=$after;BracketTicks=$after-$before;Frequency=[Diagnostics.Stopwatch]::Frequency;
                PreciseUnix100ns=$precise-116444736000000000L;RegularUnix100ns=$regular-116444736000000000L}
        }
    }
    return $best
}
function ConvertTo-DoomCaptureQpcOrigin {
    param([Parameter(Mandatory)][object[]]$Anchors,[Parameter(Mandatory)][decimal]$UnixMicroseconds)
    if($Anchors.Count -lt 2){throw 'At least two capture clock anchors are required.'}
    $offsets=[Collections.Generic.List[decimal]]::new();$maxBracket=0.0;$maxRegularDelta=0.0;$last=-1L
    foreach($a in $Anchors){
        if($a.Frequency -le 0 -or $a.QpcBefore -lt 0 -or $a.QpcAfter -lt $a.QpcBefore -or $a.QpcBefore -le $last){throw 'Malformed capture clock anchor.'}
        $mid=([decimal]$a.QpcBefore+[decimal]$a.QpcAfter)*5000000/[decimal]$a.Frequency
        $offsets.Add([decimal]$a.PreciseUnix100ns-$mid);$last=$a.QpcBefore
        $maxBracket=[Math]::Max($maxBracket,($a.QpcAfter-$a.QpcBefore)*1000.0/$a.Frequency)
        $maxRegularDelta=[Math]::Max($maxRegularDelta,[Math]::Abs($a.RegularUnix100ns-$a.PreciseUnix100ns)/10000.0)
    }
    $sorted=@($offsets|Sort-Object);$offset=$sorted[[int][Math]::Floor($sorted.Count/2)]
    $drift=[double]($sorted[-1]-$sorted[0])/10000
    if($maxBracket -gt 1 -or $drift -gt 2 -or $maxRegularDelta -gt 2){throw 'Capture clock uncertainty exceeds the current 1 ms bracket / 2 ms drift and wall-clock bounds.'}
    return @{OriginQpc100ns=$UnixMicroseconds*10-$offset;OffsetUnix100ns=$offset;OffsetSpreadMilliseconds=$drift;MaximumBracketMilliseconds=$maxBracket;MaximumRegularClockDeltaMilliseconds=$maxRegularDelta;
        Meaning='Median of bracketed precise UTC/QPC offsets, accepted only within explicit observed clock bounds. Does not include GDI copy latency or prove physical A/V synchronization.'}
}
