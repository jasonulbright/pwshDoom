#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param($Queue,$Shared,[hashtable]$Clips)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. "$PSScriptRoot/../src/AudioMixer.ps1";. "$PSScriptRoot/../src/AudioPackets.ps1";. "$PSScriptRoot/../src/WaveOutDevice.ps1"
$device=$null;$mixer=New-DoomAudioMixer 44100;$epoch=0;$started=$false;$devicePaused=$true
$mixTimes=[Collections.Generic.List[double]]::new();$ages=[Collections.Generic.List[double]]::new()
$starves=[Collections.Generic.List[object]]::new();$starved=$false;$cancelled=0L;$stale=0;$packets=0;$resets=0;$pauses=0;$lastSequence=-1;$maxVoices=0
$watch=[Diagnostics.Stopwatch]::StartNew();$failure=$null;$cleanup=$null
$pending=$null;$digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
try{
    $device=Open-DoomWaveOut -BufferFrames 1260 -Buffers 4;$Shared.Ready=$true
    while(-not $Shared.Stop){
        if($Shared.Epoch -ne $epoch){
            $cancelled+=Reset-DoomWaveOut $device;Set-DoomWaveOutPaused $device $true
            $epoch=$Shared.Epoch;$mixer.Voices.Clear();$mixer.Paused=$false;$devicePaused=$true;$started=$false;$starved=$false;$resets++
        }
        if($Shared.Paused){
            if(-not $devicePaused){Set-DoomWaveOutPaused $device $true;$devicePaused=$true;$pauses++}
            [Threading.Thread]::Sleep(2);continue
        }
        $device.Event.Reset()|Out-Null;Update-DoomWaveOutBuffers $device
        foreach($slot in $device.Buffers){
            if($slot.Queued){continue};$packet=$null
            if($null -ne $pending){$packet=$pending;$pending=$null}
            elseif(-not $Queue.TryTake([ref]$packet)){break}
            if($packet.Epoch -gt $epoch){$pending=$packet;break}
            if($packet.Epoch -lt $epoch){$stale++;continue}
            Update-DoomAudioPacket $mixer $packet $Clips
            $maxVoices=[Math]::Max($maxVoices,$mixer.Voices.Count)
            $mixWatch=[Diagnostics.Stopwatch]::StartNew();$pcm=Read-DoomAudioFrames $mixer 1260;$mixTimes.Add($mixWatch.Elapsed.TotalMilliseconds)
            $bytes=[byte[]]::new(5040);[Buffer]::BlockCopy($pcm,0,$bytes,0,5040)
            # Epoch/pause can change during a block; next loop resets/pauses before
            # continuing. The driver owns only copied PCM, never game objects.
            Submit-DoomWaveOut $device $slot $bytes
            $digest.AppendData($bytes)
            $ages.Add(([Diagnostics.Stopwatch]::GetTimestamp()-$packet.Qpc)*1000.0/[Diagnostics.Stopwatch]::Frequency)
            $lastSequence=$packet.Sequence;$packets++
        }
        $queued=@($device.Buffers|Where-Object Queued).Count
        if($devicePaused -and ($started -or $queued -ge 2)){
            Set-DoomWaveOutPaused $device $false;$devicePaused=$false;$started=$true
        }
        if($started -and $queued -eq 0){
            if(-not $starved){$starves.Add(@{WallMs=$watch.Elapsed.TotalMilliseconds;AfterPacket=$lastSequence});$starved=$true}
        }else{$starved=$false}
        $null=$device.Event.WaitOne(2)
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$Shared.Error=$failure}finally{
    if($device){try{$cancelled+=Reset-DoomWaveOut $device;Close-DoomWaveOut $device}catch{$cleanup=$_.ToString();$Shared.Error=$cleanup}}
    $Shared.Report=@{Error=$failure;CleanupError=$cleanup;Packets=$packets;LastSequence=$lastSequence;StalePacketsDiscarded=$stale;EpochResets=$resets;PauseTransitions=$pauses;MixSamplesMs=$mixTimes.ToArray();PacketAgeAtSubmissionMs=$ages.ToArray();QueueStarvationObservations=$starves.ToArray();MaxVoices=$maxVoices;ClippedSamples=$mixer.ClippedSamples;SubmittedFrames=if($device){$device.SubmittedFrames}else{0};ReturnedCompletedFrames=if($device){$device.CompletedFrames}else{0};CancelledQueuedFramesUpperBound=$cancelled;UnconsumedPackets=$Queue.Count;DeviceClosed=if($device){$device.Closed}else{$false};WallSeconds=$watch.Elapsed.TotalSeconds;Meaning='PowerShell runspace mixing and waveOut playback; packet age ends at submission, not audible output. Starvation is queue polling, not hardware telemetry. Reset/exit can cancel queued tail audio; cancelled frame count is an upper bound.'}
    $Shared.Report.PcmSha256=[Convert]::ToHexString($digest.GetHashAndReset());$digest.Dispose()
    $Shared.Report.PendingPacket=if($pending){$pending.Sequence}else{$null}
    $Shared.Finished=$true
}
