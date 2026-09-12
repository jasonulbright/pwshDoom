#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][int]$TargetProcessId,[Parameter(Mandatory)][string]$OutputPrefix,
    [ValidateRange(1,300)][int]$Seconds=10,[string]$StopFile,[string]$ReadyFile)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. "$PSScriptRoot/../src/ProcessAudioCapture.ps1"
. "$PSScriptRoot/../src/CaptureClock.ps1"
$prefix=[IO.Path]::GetFullPath($OutputPrefix);$wav=$prefix+'.wav';$report=$prefix+'.json'
foreach($path in @($wav,$report,$ReadyFile)|Where-Object {$_}){if(Test-Path -LiteralPath $path){throw 'Choose fresh capture destinations.'}}
$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($prefix))
$state=$null;$stream=$null;$writer=$null;$failure=$null;$packets=[Collections.Generic.List[object]]::new();$started=$null;$ended=$null;$stopReason='Duration'
$anchors=[Collections.Generic.List[object]]::new()
try{
    $anchors.Add((Get-DoomCaptureClockAnchor))
    $state=Open-DoomProcessCapture $TargetProcessId;$started=[datetime]::UtcNow.ToString('o')
    $stream=[IO.File]::Open($wav,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $writer=[IO.BinaryWriter]::new($stream)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([uint32]0);$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '));$writer.Write([uint32]16)
    $writer.Write([uint16]1);$writer.Write([uint16]2);$writer.Write([uint32]44100);$writer.Write([uint32]176400);$writer.Write([uint16]4);$writer.Write([uint16]16)
    $writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([uint32]0)
    if($ReadyFile){@{TargetProcessId=$TargetProcessId;CaptureProcessId=$PID;StartQpc=$state.StartQpc}|ConvertTo-Json|Set-Content -LiteralPath $ReadyFile}
    $watch=[Diagnostics.Stopwatch]::StartNew();$nextAnchor=1.0
    while($watch.Elapsed.TotalSeconds -lt $Seconds){
        if($StopFile -and (Test-Path -LiteralPath $StopFile)){$stopReason='StopFile';break}
        $null=$state.Event.WaitOne(20)
        while($null -ne ($packet=Read-DoomProcessCapture $state)){
            $writer.Write([byte[]]$packet.Bytes);$packet.Remove('Bytes');$packets.Add($packet)
            if($watch.Elapsed.TotalSeconds -ge $Seconds){break}
        }
        if($watch.Elapsed.TotalSeconds -ge $nextAnchor){$anchors.Add((Get-DoomCaptureClockAnchor));$nextAnchor=$watch.Elapsed.TotalSeconds+1}
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    $ended=[datetime]::UtcNow.ToString('o')
    if($state){try{Close-DoomProcessCapture $state}catch{$failure="${failure}`nCapture cleanup: $_"}}
    $anchors.Add((Get-DoomCaptureClockAnchor))
    if($writer){$length=$stream.Length;$stream.Position=4;$writer.Write([uint32]($length-8));$stream.Position=40;$writer.Write([uint32]($length-44));$writer.Flush();$stream.Flush($true);$writer.Dispose()}
    @{Error=$failure;StartedUtc=$started;EndedUtc=$ended;StopReason=$stopReason;TargetProcessId=$TargetProcessId;TargetStartUtc=if($state){$state.TargetStartUtc}else{$null};
      StartQpc=if($state){$state.StartQpc}else{$null};QpcFrequency=[Diagnostics.Stopwatch]::Frequency;Rate=44100;Channels=2;Bits=16;
      Frames=if($state){$state.Frames}else{0};Closed=if($state){$state.Closed}else{$true};Packets=$packets.ToArray();WavPath=$wav;WavSha256=if(Test-Path $wav){(Get-FileHash $wav).Hash}else{$null};
      ClockAnchors=$anchors.ToArray();Sources=@('src/ProcessAudioCapture.ps1','src/CaptureClock.ps1','scripts/Record-ProcessAudio.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});
      Meaning='WASAPI process-tree loopback, fixed 44.1 kHz stereo PCM16. Captured packets are concatenated without silently filling gaps; flags, positions and 100-nanosecond QPC timestamps are retained. Includes the selected process and children only, no microphone. Windows digital output capture is not an acoustic microphone measurement. External recording instrumentation has compiled COM forwarding/callback plumbing; packet handling and WAV writing are PowerShell.'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $report
}
if($failure){throw $failure}
$wav
