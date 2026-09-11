#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$ReplayReport="$PSScriptRoot/../results/audio-replay-legacy.json")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/WaveOutDevice.ps1"
$device=$null;$failure=$null;$cleanup=$null;$checks=[Collections.Generic.List[object]]::new()
$watch=[Diagnostics.Stopwatch]::new();$starvation=0;$submitted=0L;$completed=0L;$pauseMs=0.0;$tail=0
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $report=Get-Content $ReplayReport -Raw|ConvertFrom-Json
    Check 'Source PCM matches replay hash' ((Get-FileHash $report.Wave).Hash -eq $report.WaveSha256)
    $wave=[IO.File]::ReadAllBytes($report.Wave)
    Check 'Canonical stereo PCM format' ([Text.Encoding]::ASCII.GetString($wave,0,4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($wave,8,8) -eq 'WAVEfmt ' -and [BitConverter]::ToUInt32($wave,16) -eq 16 -and [BitConverter]::ToUInt16($wave,20) -eq 1 -and [BitConverter]::ToUInt16($wave,22) -eq 2 -and [BitConverter]::ToUInt32($wave,24) -eq 44100 -and [BitConverter]::ToUInt16($wave,34) -eq 16 -and [Text.Encoding]::ASCII.GetString($wave,36,4) -eq 'data')
    # Eight seconds plus a partial queue block, starting after the route's silent lead-in.
    $frames=44100*8+137;$source=44+9*44100*4;$end=$source+$frames*4
    Check 'Selected segment lies within PCM data' ($end -le $wave.Length -and $end -le 44+[BitConverter]::ToUInt32($wave,40))
    $device=Open-DoomWaveOut -BufferFrames 882 -Buffers 4
    Check 'Native PCM format layout' ([Runtime.InteropServices.Marshal]::SizeOf([type][PwshDoomAudio.Format]) -eq 18)
    Check 'Native header layout' ($device.HeaderSize -eq $(if([IntPtr]::Size -eq 8){48}else{32}) -and $device.FlagsOffset -eq $(if([IntPtr]::Size -eq 8){24}else{16}))
    foreach($slot in $device.Buffers){$block=[byte[]]::new(3528);[Array]::Copy($wave,$source,$block,0,$block.Length);Submit-DoomWaveOut $device $slot $block;$source+=$block.Length}
    $rejected=$false;try{Submit-DoomWaveOut $device $device.Buffers[0] $block}catch{$rejected=$true}
    Check 'Reject overwriting queued native buffer' $rejected
    $device.Event.Reset()|Out-Null;$watch.Start();Set-DoomWaveOutPaused $device $false;$paused=$false
    while($device.CompletedFrames -lt $frames){
        if($watch.Elapsed.TotalSeconds -gt 20){throw 'Playback exceeded 20-second wall limit.'}
        $device.Event.Reset()|Out-Null;Update-DoomWaveOutBuffers $device
        $queued=@($device.Buffers|Where-Object Queued).Count
        if($queued -eq 0 -and $source -lt $end){$starvation++}
        foreach($slot in $device.Buffers){
            if(-not $slot.Queued -and $source -lt $end){
                $length=[Math]::Min(3528,$end-$source);$block=[byte[]]::new($length)
                [Array]::Copy($wave,$source,$block,0,$length);Submit-DoomWaveOut $device $slot $block;$source+=$length
                if($length -lt 3528){$tail=$length/4}
            }
        }
        if(-not $paused -and $watch.Elapsed.TotalSeconds -ge 3){
            Set-DoomWaveOutPaused $device $true;$hold=[Diagnostics.Stopwatch]::StartNew()
            Start-Sleep -Milliseconds 200;$pauseMs=$hold.Elapsed.TotalMilliseconds
            Set-DoomWaveOutPaused $device $false;$paused=$true
        }
        if($device.CompletedFrames -lt $frames){$null=$device.Event.WaitOne(10)}
    }
    $watch.Stop();$submitted=$device.SubmittedFrames;$completed=$device.CompletedFrames
    Check 'Every submitted frame returned by driver' ($submitted -eq $frames -and $completed -eq $frames)
    Check 'Partial final buffer completed' ($tail -eq 137)
    Check 'Pause and restart completed' $paused
    Close-DoomWaveOut $device;Close-DoomWaveOut $device
    Check 'Idempotent close releases native allocations' ($device.Closed -and @($device.Buffers|Where-Object {$_.Data -ne [IntPtr]::Zero -or $_.Header -ne [IntPtr]::Zero}).Count -eq 0)
    # Reset with outstanding queued audio must return ownership before freeing it.
    $device=Open-DoomWaveOut -BufferFrames 882 -Buffers 2
    Submit-DoomWaveOut $device $device.Buffers[0] ([byte[]]::new(3528))
    Close-DoomWaveOut $device
    Check 'Early close safely resets outstanding buffer' $device.Closed
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($device){try{Close-DoomWaveOut $device}catch{$cleanup=$_.ToString()}}
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;CleanupError=$cleanup;Checks=$checks.ToArray();ReplayReportSha256=(Get-FileHash $ReplayReport).Hash;
      Sources=@('src/WaveOutDevice.ps1','scripts/Test-WaveOutPlayback.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
      Rate=44100;BufferFrames=882;Buffers=4;SourceStartSeconds=9;SelectedFrames=352937;SubmittedFrames=$submitted;CompletedFrames=$completed;WallSeconds=$watch.Elapsed.TotalSeconds;PauseMilliseconds=$pauseMs;QueueEmptyWithInputRemainingObservations=$starvation;TailFrames=$tail;
      Meaning='Default Windows waveOut device API completion of prerecorded PowerShell PCM. Queue-empty polling is not hardware underrun telemetry. No audibility, latency, live mixing, renderer load, or audio/video synchronization claim.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
if($cleanup){throw $cleanup}
"PASS: $($checks.Count) playback checks, $completed completed stereo frames."
