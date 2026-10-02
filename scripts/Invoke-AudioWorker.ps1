#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param($Queue,$Shared,[hashtable]$Clips,[hashtable]$MusicReports=@{})
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. "$PSScriptRoot/../src/AudioMixer.ps1";. "$PSScriptRoot/../src/AudioPackets.ps1";. "$PSScriptRoot/../src/WaveOutDevice.ps1"
. "$PSScriptRoot/../src/MusicLoopReader.ps1";. "$PSScriptRoot/../src/MusicOneShotReader.ps1";. "$PSScriptRoot/../src/MusicPlayback.ps1"
$music=$null
$device=$null;$mixer=New-DoomAudioMixer 44100;$epoch=0;$started=$false;$devicePaused=$true
$mixTimes=[Collections.Generic.List[double]]::new();$ages=[Collections.Generic.List[double]]::new()
$starves=[Collections.Generic.List[object]]::new();$starved=$false;$cancelled=0L;$stale=0;$packets=0;$syntheticBlocks=0;$resets=0;$pauses=0;$lastSequence=-1;$maxVoices=0
$watch=[Diagnostics.Stopwatch]::StartNew();$failure=$null;$cleanup=$null
$pending=$null;$digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
$timelineCredits=0L;$maximumTimelineCredits=0L;$compensatedPackets=0L;$clearedTimelineCredits=0L
$processedAges=[Collections.Generic.List[double]]::new();$compensatedAges=[Collections.Generic.List[double]]::new()
$pendingEffectOutput=$false;$compensatedEvents=0L;$drainEffectBlocks=0L
$volumeChanges=[Collections.Generic.List[object]]::new();$mutedPackets=0
$rebufferStart=-1.0;$rebufferFirstPacket=-1.0;$rebufferResumes=[Collections.Generic.List[object]]::new()
$Shared.Rebuffering=$false;$Shared.RebufferCount=0;$Shared.RebufferResumeCount=0
$Shared.DrainTarget=$null;$Shared.DrainReady=$false;$drains=[Collections.Generic.List[object]]::new()
$shutdownDrain=@{Attempted=$false;Completed=$false;TimedOut=$false;SkippedReason=$null;WaitMilliseconds=0.0;PendingFramesAtStop=0L;CompletedFramesDuringWait=0L;RemainingFrames=0L;CancelledFramesUpperBound=0L}
try{
    $music=New-DoomMusicPlayback $MusicReports
    $device=Open-DoomWaveOut -BufferFrames 1260 -Buffers 4;$Shared.DevicePaused=$true;$Shared.SubmittedFrames=0L;$Shared.Ready=$true
    while(-not $Shared.Stop){
        $volume=[double]$Shared.Volume
        if(-not [double]::IsFinite($volume) -or $volume -lt 0 -or $volume -gt 1){throw 'Invalid shared sound volume.'}
        $musicVolume=[double]$Shared.MusicVolume
        if(-not [double]::IsFinite($musicVolume) -or $musicVolume -lt 0 -or $musicVolume -gt 1){throw 'Invalid shared music volume.'}
        if($volume -ne $mixer.Volume){
            # Do not replay previously queued loud PCM after unpausing a muted
            # menu. Clear its device tail, while retaining advanced voice positions.
            $cleared=Reset-DoomWaveOut $device;$cancelled+=$cleared;Set-DoomWaveOutPaused $device $true
            $mixer.Volume=$volume;$devicePaused=$true;$Shared.DevicePaused=$true;$started=$false;$starved=$false
            $clearedTimelineCredits+=$timelineCredits;$timelineCredits=0L
            $rebufferStart=-1.0;$rebufferFirstPacket=-1.0;$Shared.Rebuffering=$false
            $volumeChanges.Add(@{Volume=$volume;AfterPacket=$lastSequence;WallMs=$watch.Elapsed.TotalMilliseconds;CancelledFramesUpperBound=$cleared})
            $Shared.AppliedVolume=$volume
        }
        if($Shared.Epoch -ne $epoch){
            $cancelled+=Reset-DoomWaveOut $device;Set-DoomWaveOutPaused $device $true
            $epoch=$Shared.Epoch;$mixer.Voices.Clear();$mixer.Paused=$false;$devicePaused=$true;$Shared.DevicePaused=$true;$started=$false;$starved=$false;$resets++
            Reset-DoomMusicPlayback $music
            $clearedTimelineCredits+=$timelineCredits;$timelineCredits=0L
            $pendingEffectOutput=$false
            $rebufferStart=-1.0;$rebufferFirstPacket=-1.0;$Shared.Rebuffering=$false
        }
        if($Shared.Paused -or ($null -ne $Shared.DrainTarget -and $Shared.DrainReady)){
            if(-not $devicePaused){Set-DoomWaveOutPaused $device $true;$devicePaused=$true;$pauses++}
            $Shared.DevicePaused=$true
            [Threading.Thread]::Sleep(2);continue
        }
        $device.Event.Reset()|Out-Null;Update-DoomWaveOutBuffers $device;$Shared.CompletedFrames=$device.CompletedFrames
        foreach($slot in $device.Buffers){
            if($slot.Queued){continue};$packet=$null
            $outputReady=$false
            # Realtime filler already represented these elapsed intervals. Apply
            # every caught-up packet's controls/events in order, without adding
            # its duration again. Newly received sounds start on the current
            # output clock; past audible output cannot be reconstructed.
            for($catchup=0;$catchup -le 32;$catchup++){
            if($Shared.Epoch -ne $epoch -or $Shared.Paused){break}
            if($null -ne $Shared.DrainTarget -and $lastSequence -ge $Shared.DrainTarget){
                # A credited final event still needs one current-clock block
                # before its explicit drain can acknowledge audible work.
                if($pendingEffectOutput){$synthetic=$true;$outputReady=$true;$drainEffectBlocks++}
                break
            }
            $synthetic=$false
            if($null -ne $pending){$packet=$pending;$pending=$null}
            elseif(-not $Queue.TryTake([ref]$packet)){
                $active= -not $mixer.Paused -and ($mixer.Voices.Count -gt 0 -or $null -ne $music.Selected)
                if($Shared.Realtime -and $null -eq $Shared.DrainTarget -and $active){$synthetic=$true}else{break}
            }
            if($null -ne $packet){
                if($packet.Epoch -gt $epoch){$pending=$packet;break}
                if($packet.Epoch -lt $epoch){$stale++;continue}
                Update-DoomAudioPacket $mixer $packet $Clips
                if($packet.ContainsKey('Music')){
                    Update-DoomMusicPlayback $music $packet.Music
                    if(@($packet.Music|Where-Object {$_.Kind -in 'Start','Stop'}).Count){$clearedTimelineCredits+=$timelineCredits;$timelineCredits=0L}
                }
                $maxVoices=[Math]::Max($maxVoices,$mixer.Voices.Count)
                $age=([Diagnostics.Stopwatch]::GetTimestamp()-$packet.Qpc)*1000.0/[Diagnostics.Stopwatch]::Frequency
                $processedAges.Add($age)
                if($timelineCredits -gt 0){
                    $timelineCredits--;$compensatedPackets++;$compensatedAges.Add($age)
                    if($packet.Events.Count){$pendingEffectOutput=$true;$compensatedEvents+=$packet.Events.Count}
                    $lastSequence=$packet.Sequence;$packets++;$Shared.LastSequence=$lastSequence
                    continue
                }
            }
            $outputReady=$true;break
            }
            if(-not $outputReady){break}
            $mixWatch=[Diagnostics.Stopwatch]::StartNew()
            $musicFrames=if(-not $mixer.Paused){Read-DoomMusicPlayback $music 1260}else{$null}
            $pcm=Read-DoomAudioFrames $mixer 1260 -Music $musicFrames -MusicGain ($music.Gain*$musicVolume);$mixTimes.Add($mixWatch.Elapsed.TotalMilliseconds)
            if($mixer.Volume -eq 0){$mutedPackets++}
            $bytes=[byte[]]::new(5040);[Buffer]::BlockCopy($pcm,0,$bytes,0,5040)
            # Epoch/pause can change during a block; next loop resets/pauses before
            # continuing. The driver owns only copied PCM, never game objects.
            Submit-DoomWaveOut $device $slot $bytes
            $pendingEffectOutput=$false
            $digest.AppendData($bytes)
            $Shared.SubmittedFrames=$device.SubmittedFrames
            if($synthetic){$syntheticBlocks++;$timelineCredits++;$maximumTimelineCredits=[Math]::Max($maximumTimelineCredits,$timelineCredits)}
            else{$ages.Add(([Diagnostics.Stopwatch]::GetTimestamp()-$packet.Qpc)*1000.0/[Diagnostics.Stopwatch]::Frequency);$lastSequence=$packet.Sequence;$packets++;$Shared.LastSequence=$lastSequence}
        }
        $queued=@($device.Buffers|Where-Object Queued).Count
        $drainFinished=$null -ne $Shared.DrainTarget -and $lastSequence -ge $Shared.DrainTarget
        if($drainFinished -and $queued -eq 0){
            Set-DoomWaveOutPaused $device $true;$devicePaused=$true;$Shared.DevicePaused=$true;$started=$false
            $Shared.DrainAcknowledgedQpc=[Diagnostics.Stopwatch]::GetTimestamp();$Shared.DrainCompletedFrames=$device.CompletedFrames
            $drains.Add(@{ThroughSequence=$lastSequence;Qpc=$Shared.DrainAcknowledgedQpc;CompletedFrames=$device.CompletedFrames})
            $rebufferStart=-1.0;$rebufferFirstPacket=-1.0;$Shared.Rebuffering=$false
            $Shared.DrainReady=$true
            continue
        }
        if($rebufferStart -ge 0 -and $queued -gt 0 -and $rebufferFirstPacket -lt 0){$rebufferFirstPacket=$watch.Elapsed.TotalMilliseconds}
        $rebufferExpired=$rebufferFirstPacket -ge 0 -and $watch.Elapsed.TotalMilliseconds-$rebufferFirstPacket -ge 100
        if($devicePaused -and $queued -gt 0 -and ($started -or $queued -ge 2 -or $rebufferExpired -or $drainFinished)){
            Set-DoomWaveOutPaused $device $false;$devicePaused=$false;$Shared.DevicePaused=$false;$started=$true
            if($rebufferStart -ge 0){
                $rebufferResumes.Add(@{AfterPacket=$lastSequence;QueuedBuffers=$queued;WaitMilliseconds=$watch.Elapsed.TotalMilliseconds-$rebufferStart;ReserveWaitMilliseconds=$watch.Elapsed.TotalMilliseconds-$rebufferFirstPacket;Reason=if($queued -ge 2){'TwoPackets'}else{'SinglePacketDeadline'}})
                $Shared.RebufferResumeCount++;$Shared.Rebuffering=$false;$rebufferStart=-1.0;$rebufferFirstPacket=-1.0
            }
        }
        $activeOutput= -not $mixer.Paused -and ($mixer.Voices.Count -gt 0 -or $null -ne $music.Selected)
        if($started -and $queued -eq 0 -and (-not $Shared.Realtime -or $activeOutput)){
            if(-not $starved){$starves.Add(@{WallMs=$watch.Elapsed.TotalMilliseconds;AfterPacket=$lastSequence});$starved=$true}
            # Rebuild the normal start reserve after an underrun. A bounded
            # single-packet fallback prevents an end-of-stream tail from waiting
            # forever. No reset, invented samples or discarded packets here.
            Set-DoomWaveOutPaused $device $true;$devicePaused=$true;$Shared.DevicePaused=$true;$started=$false
            $rebufferStart=$watch.Elapsed.TotalMilliseconds;$rebufferFirstPacket=-1.0;$Shared.Rebuffering=$true;$Shared.RebufferCount++
        }elseif($started -and $queued -eq 0){
            Set-DoomWaveOutPaused $device $true;$devicePaused=$true;$Shared.DevicePaused=$true;$started=$false;$starved=$false
            $rebufferStart=-1.0;$rebufferFirstPacket=-1.0;$Shared.Rebuffering=$false
        }else{$starved=$false}
        $null=$device.Event.WaitOne(2)
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$Shared.Error=$failure}finally{
    if($device){
        try{
            Update-DoomWaveOutBuffers $device
            foreach($slot in $device.Buffers){if($slot.Queued){$shutdownDrain.PendingFramesAtStop+=$slot.Frames}}
            if($shutdownDrain.PendingFramesAtStop -eq 0){$shutdownDrain.Completed=$true;$shutdownDrain.SkippedReason='NoQueuedAudio'}
            elseif($null -ne $failure){$shutdownDrain.SkippedReason='WorkerFailed';$shutdownDrain.RemainingFrames=$shutdownDrain.PendingFramesAtStop}
            elseif($Shared.Paused -or $mixer.Paused){$shutdownDrain.SkippedReason='PlaybackPaused';$shutdownDrain.RemainingFrames=$shutdownDrain.PendingFramesAtStop}
            else{
                $shutdownDrain.Attempted=$true
                if($devicePaused){Set-DoomWaveOutPaused $device $false;$devicePaused=$false;$Shared.DevicePaused=$false}
                $tail=Wait-DoomWaveOutBuffers $device 250
                $shutdownDrain.Completed=$tail.Completed;$shutdownDrain.TimedOut=$tail.TimedOut
                $shutdownDrain.WaitMilliseconds=$tail.WaitMilliseconds
                $shutdownDrain.CompletedFramesDuringWait=$tail.CompletedFramesDuringWait
                $shutdownDrain.RemainingFrames=$tail.RemainingFrames
            }
        }catch{$cleanup=$_.ToString();$Shared.Error=$cleanup;$shutdownDrain.SkippedReason='DrainError';$shutdownDrain.RemainingFrames=$shutdownDrain.PendingFramesAtStop}
        try{$shutdownDrain.CancelledFramesUpperBound=Reset-DoomWaveOut $device;$cancelled+=$shutdownDrain.CancelledFramesUpperBound}catch{$cleanup=$_.ToString();$Shared.Error=$cleanup}
        try{Close-DoomWaveOut $device}catch{$cleanup=$_.ToString();$Shared.Error=$cleanup}
    }
    if($music){try{Close-DoomMusicPlayback $music}catch{$cleanup=$_.ToString();$Shared.Error=$cleanup}}
    $Shared.DevicePaused=$true
    $Shared.Report=@{Error=$failure;CleanupError=$cleanup;Packets=$packets;LastSequence=$lastSequence;Realtime=[bool]$Shared.Realtime;GeneratedRealtimeBlocks=$syntheticBlocks;MixedBlocks=$packets+$syntheticBlocks-$compensatedPackets;StalePacketsDiscarded=$stale;EpochResets=$resets;PauseTransitions=$pauses;MixSamplesMs=$mixTimes.ToArray();PacketAgeAtSubmissionMs=$ages.ToArray();QueueStarvationObservations=$starves.ToArray();MaxVoices=$maxVoices;ClippedSamples=$mixer.ClippedSamples;SubmittedFrames=if($device){$device.SubmittedFrames}else{0};ReturnedCompletedFrames=if($device){$device.CompletedFrames}else{0};CancelledQueuedFramesUpperBound=$cancelled;ShutdownDrain=$shutdownDrain;UnconsumedPackets=$Queue.Count;DeviceClosed=if($device){$device.Closed}else{$false};WallSeconds=$watch.Elapsed.TotalSeconds;Meaning='PowerShell mixes simulation packets. Interactive playback continues active music/effects through producer gaps. Caught-up packets apply every control/event in order without repeating intervals already covered by filler; new sounds start on the current output clock, and past audible output is not reconstructed. Headless/test playback remains packet-exact. Submission ages exclude compensated packets; processing ages include every consumed packet. Neither measures audible output. Queue starvation is polling, not hardware telemetry. Normal unpaused exit drains submitted device buffers for up to 250 ms; paused/error exits cancel the remaining tail and report its upper bound.'}
    $Shared.Report.CompensatedRealtimePackets=$compensatedPackets;$Shared.Report.CompensatedPacketAgeMs=$compensatedAges.ToArray()
    $Shared.Report.PacketAgeAtProcessingMs=$processedAges.ToArray();$Shared.Report.PendingTimelineCredits=$timelineCredits
    $Shared.Report.ClearedTimelineCredits=$clearedTimelineCredits;$Shared.Report.MaximumTimelineCredits=$maximumTimelineCredits
    $Shared.Report.CompensatedControlEvents=$compensatedEvents;$Shared.Report.DrainEffectBlocks=$drainEffectBlocks
    $Shared.Report.PendingEffectOutput=$pendingEffectOutput
    $Shared.Report.ProcessId=$PID;$Shared.Report.ExecutionModel='RunspaceInCallerProcess'
    $Shared.Report.FinalVoices=@(foreach($voice in $mixer.Voices){@{Source=$voice.Source;Position=$voice.Position;Step=$voice.Step}})
    $Shared.Report.PcmSha256=[Convert]::ToHexString($digest.GetHashAndReset());$digest.Dispose()
    $Shared.Report.VolumeChanges=$volumeChanges.ToArray();$Shared.Report.MutedPackets=$mutedPackets;$Shared.Report.FinalVolume=$mixer.Volume
    $Shared.Report.PendingPacket=if($pending){$pending.Sequence}else{$null}
    $Shared.Report.RebufferResumes=$rebufferResumes.ToArray();$Shared.Report.RebufferCount=$Shared.RebufferCount
    $Shared.Report.RebufferSinglePacketDeadlineMs=100
    $Shared.Report.LoadingDrains=$drains.ToArray()
    $Shared.Report.Music=if($music){@{Selected=$music.Selected;Gain=$music.Gain;Frames=$music.Frames;Transitions=$music.Transitions.ToArray();Reports=$music.Reports;Closed=$music.Closed}}else{$null}
    $Shared.Finished=$true
}
