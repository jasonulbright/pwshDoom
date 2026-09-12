#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param($Queue,$Shared,[hashtable]$Clips,[hashtable]$MusicReports=@{})
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. "$PSScriptRoot/../src/AudioMixer.ps1";. "$PSScriptRoot/../src/AudioPackets.ps1";. "$PSScriptRoot/../src/WaveOutDevice.ps1"
. "$PSScriptRoot/../src/MusicLoopReader.ps1";. "$PSScriptRoot/../src/MusicPlayback.ps1"
$music=$null
$device=$null;$mixer=New-DoomAudioMixer 44100;$epoch=0;$started=$false;$devicePaused=$true
$mixTimes=[Collections.Generic.List[double]]::new();$ages=[Collections.Generic.List[double]]::new()
$starves=[Collections.Generic.List[object]]::new();$starved=$false;$cancelled=0L;$stale=0;$packets=0;$resets=0;$pauses=0;$lastSequence=-1;$maxVoices=0
$watch=[Diagnostics.Stopwatch]::StartNew();$failure=$null;$cleanup=$null
$pending=$null;$digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
$volumeChanges=[Collections.Generic.List[object]]::new();$mutedPackets=0
$rebufferStart=-1.0;$rebufferFirstPacket=-1.0;$rebufferResumes=[Collections.Generic.List[object]]::new()
$Shared.Rebuffering=$false;$Shared.RebufferCount=0;$Shared.RebufferResumeCount=0
$Shared.DrainTarget=$null;$Shared.DrainReady=$false;$drains=[Collections.Generic.List[object]]::new()
try{
    $music=New-DoomMusicPlayback $MusicReports
    $device=Open-DoomWaveOut -BufferFrames 1260 -Buffers 4;$Shared.Ready=$true
    while(-not $Shared.Stop){
        $volume=[double]$Shared.Volume
        if(-not [double]::IsFinite($volume) -or $volume -lt 0 -or $volume -gt 1){throw 'Invalid shared sound volume.'}
        if($volume -ne $mixer.Volume){
            # Do not replay previously queued loud PCM after unpausing a muted
            # menu. Clear its device tail, while retaining advanced voice positions.
            $cleared=Reset-DoomWaveOut $device;$cancelled+=$cleared;Set-DoomWaveOutPaused $device $true
            $mixer.Volume=$volume;$devicePaused=$true;$started=$false;$starved=$false
            $rebufferStart=-1.0;$rebufferFirstPacket=-1.0;$Shared.Rebuffering=$false
            $volumeChanges.Add(@{Volume=$volume;AfterPacket=$lastSequence;WallMs=$watch.Elapsed.TotalMilliseconds;CancelledFramesUpperBound=$cleared})
            $Shared.AppliedVolume=$volume
        }
        if($Shared.Epoch -ne $epoch){
            $cancelled+=Reset-DoomWaveOut $device;Set-DoomWaveOutPaused $device $true
            $epoch=$Shared.Epoch;$mixer.Voices.Clear();$mixer.Paused=$false;$devicePaused=$true;$started=$false;$starved=$false;$resets++
            Reset-DoomMusicPlayback $music
            $rebufferStart=-1.0;$rebufferFirstPacket=-1.0;$Shared.Rebuffering=$false
        }
        if($Shared.Paused -or ($null -ne $Shared.DrainTarget -and $Shared.DrainReady)){
            if(-not $devicePaused){Set-DoomWaveOutPaused $device $true;$devicePaused=$true;$pauses++}
            [Threading.Thread]::Sleep(2);continue
        }
        $device.Event.Reset()|Out-Null;Update-DoomWaveOutBuffers $device
        foreach($slot in $device.Buffers){
            if($slot.Queued){continue};$packet=$null
            if($null -ne $Shared.DrainTarget -and $lastSequence -ge $Shared.DrainTarget){break}
            if($null -ne $pending){$packet=$pending;$pending=$null}
            elseif(-not $Queue.TryTake([ref]$packet)){break}
            if($packet.Epoch -gt $epoch){$pending=$packet;break}
            if($packet.Epoch -lt $epoch){$stale++;continue}
            Update-DoomAudioPacket $mixer $packet $Clips
            if($packet.ContainsKey('Music')){Update-DoomMusicPlayback $music $packet.Music}
            $maxVoices=[Math]::Max($maxVoices,$mixer.Voices.Count)
            $mixWatch=[Diagnostics.Stopwatch]::StartNew()
            $musicFrames=if(-not $mixer.Paused){Read-DoomMusicPlayback $music 1260}else{$null}
            $pcm=Read-DoomAudioFrames $mixer 1260 -Music $musicFrames -MusicGain ($music.Gain*$mixer.Volume);$mixTimes.Add($mixWatch.Elapsed.TotalMilliseconds)
            if($mixer.Volume -eq 0){$mutedPackets++}
            $bytes=[byte[]]::new(5040);[Buffer]::BlockCopy($pcm,0,$bytes,0,5040)
            # Epoch/pause can change during a block; next loop resets/pauses before
            # continuing. The driver owns only copied PCM, never game objects.
            Submit-DoomWaveOut $device $slot $bytes
            $digest.AppendData($bytes)
            $ages.Add(([Diagnostics.Stopwatch]::GetTimestamp()-$packet.Qpc)*1000.0/[Diagnostics.Stopwatch]::Frequency)
            $lastSequence=$packet.Sequence;$packets++;$Shared.LastSequence=$lastSequence
        }
        $queued=@($device.Buffers|Where-Object Queued).Count
        $drainFinished=$null -ne $Shared.DrainTarget -and $lastSequence -ge $Shared.DrainTarget
        if($drainFinished -and $queued -eq 0){
            Set-DoomWaveOutPaused $device $true;$devicePaused=$true;$started=$false
            $Shared.DrainAcknowledgedQpc=[Diagnostics.Stopwatch]::GetTimestamp();$Shared.DrainCompletedFrames=$device.CompletedFrames
            $drains.Add(@{ThroughSequence=$lastSequence;Qpc=$Shared.DrainAcknowledgedQpc;CompletedFrames=$device.CompletedFrames})
            $rebufferStart=-1.0;$rebufferFirstPacket=-1.0;$Shared.Rebuffering=$false
            $Shared.DrainReady=$true
            continue
        }
        if($rebufferStart -ge 0 -and $queued -gt 0 -and $rebufferFirstPacket -lt 0){$rebufferFirstPacket=$watch.Elapsed.TotalMilliseconds}
        $rebufferExpired=$rebufferFirstPacket -ge 0 -and $watch.Elapsed.TotalMilliseconds-$rebufferFirstPacket -ge 100
        if($devicePaused -and $queued -gt 0 -and ($started -or $queued -ge 2 -or $rebufferExpired -or $drainFinished)){
            Set-DoomWaveOutPaused $device $false;$devicePaused=$false;$started=$true
            if($rebufferStart -ge 0){
                $rebufferResumes.Add(@{AfterPacket=$lastSequence;QueuedBuffers=$queued;WaitMilliseconds=$watch.Elapsed.TotalMilliseconds-$rebufferStart;ReserveWaitMilliseconds=$watch.Elapsed.TotalMilliseconds-$rebufferFirstPacket;Reason=if($queued -ge 2){'TwoPackets'}else{'SinglePacketDeadline'}})
                $Shared.RebufferResumeCount++;$Shared.Rebuffering=$false;$rebufferStart=-1.0;$rebufferFirstPacket=-1.0
            }
        }
        if($started -and $queued -eq 0){
            if(-not $starved){$starves.Add(@{WallMs=$watch.Elapsed.TotalMilliseconds;AfterPacket=$lastSequence});$starved=$true}
            # Rebuild the normal start reserve after an underrun. A bounded
            # single-packet fallback prevents an end-of-stream tail from waiting
            # forever. No reset, invented samples or discarded packets here.
            Set-DoomWaveOutPaused $device $true;$devicePaused=$true;$started=$false
            $rebufferStart=$watch.Elapsed.TotalMilliseconds;$rebufferFirstPacket=-1.0;$Shared.Rebuffering=$true;$Shared.RebufferCount++
        }else{$starved=$false}
        $null=$device.Event.WaitOne(2)
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$Shared.Error=$failure}finally{
    if($device){try{$cancelled+=Reset-DoomWaveOut $device;Close-DoomWaveOut $device}catch{$cleanup=$_.ToString();$Shared.Error=$cleanup}}
    if($music){try{Close-DoomMusicPlayback $music}catch{$cleanup=$_.ToString();$Shared.Error=$cleanup}}
    $Shared.Report=@{Error=$failure;CleanupError=$cleanup;Packets=$packets;LastSequence=$lastSequence;StalePacketsDiscarded=$stale;EpochResets=$resets;PauseTransitions=$pauses;MixSamplesMs=$mixTimes.ToArray();PacketAgeAtSubmissionMs=$ages.ToArray();QueueStarvationObservations=$starves.ToArray();MaxVoices=$maxVoices;ClippedSamples=$mixer.ClippedSamples;SubmittedFrames=if($device){$device.SubmittedFrames}else{0};ReturnedCompletedFrames=if($device){$device.CompletedFrames}else{0};CancelledQueuedFramesUpperBound=$cancelled;UnconsumedPackets=$Queue.Count;DeviceClosed=if($device){$device.Closed}else{$false};WallSeconds=$watch.Elapsed.TotalSeconds;Meaning='PowerShell runspace mixing and waveOut playback; packet age ends at submission, not audible output. Starvation is queue polling, not hardware telemetry. Reset/exit can cancel queued tail audio; cancelled frame count is an upper bound.'}
    $Shared.Report.PcmSha256=[Convert]::ToHexString($digest.GetHashAndReset());$digest.Dispose()
    $Shared.Report.VolumeChanges=$volumeChanges.ToArray();$Shared.Report.MutedPackets=$mutedPackets;$Shared.Report.FinalVolume=$mixer.Volume
    $Shared.Report.PendingPacket=if($pending){$pending.Sequence}else{$null}
    $Shared.Report.RebufferResumes=$rebufferResumes.ToArray();$Shared.Report.RebufferCount=$Shared.RebufferCount
    $Shared.Report.RebufferSinglePacketDeadlineMs=100
    $Shared.Report.LoadingDrains=$drains.ToArray()
    $Shared.Report.Music=if($music){@{Selected=$music.Selected;Gain=$music.Gain;Frames=$music.Frames;Transitions=$music.Transitions.ToArray();Reports=$music.Reports;Closed=$music.Closed}}else{$null}
    $Shared.Finished=$true
}
