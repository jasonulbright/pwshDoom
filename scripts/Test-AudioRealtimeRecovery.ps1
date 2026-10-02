#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Qualification="$PSScriptRoot/../results/music-loop-e1m1-hour-bound.json",
    [ValidateRange(300,750)][int]$GapMilliseconds=700,
    [ValidateRange(35,140)][int]$RecoveryTics=70,
    [ValidateRange(30,500)][double]$MaximumRecoveredPacketAgeMs=120,
    [switch]$RequireRecovery,[switch]$EffectEvents)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..")
. "$PSScriptRoot/../src/AudioRunspace.ps1"
$Qualification=[IO.Path]::GetFullPath($Qualification)
$track=[string](Get-Content -LiteralPath $Qualification -Raw|ConvertFrom-Json).Details.Track
$audio=$null;$report=$null;$failure=$null;$sequence=0;$waits=[Collections.Generic.List[double]]::new()
$gap=$null;$recoveredAge=$null;$gate=$false;$barrier=$null
$finalPacket=35+[int][Math]::Ceiling($GapMilliseconds*35.0/1000)+$RecoveryTics
function Wait-Worker([scriptblock]$Condition,[string]$Name){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not (& $Condition)){
        if($audio.Shared.Error -or $audio.Async.IsCompleted){throw "Audio failed during $Name. $($audio.Shared.Error)"}
        if($watch.ElapsedMilliseconds -gt 3000){throw "Timed out during $Name."}
        [Threading.Thread]::Sleep(1)
    }
}
function Send-TestPacket([switch]$StartMusic){
    $packet=@{Sequence=$script:sequence;Epoch=0;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=@();Gains=@{}}
    if($StartMusic){$packet.Music=@(@{Kind='Start';Track=$track;Loop=$true})}
    if($EffectEvents){
        switch($script:sequence){
            36 {$packet.Events=@(@{Kind='Start';Sound=1;Source=1;Group=1;Volume=100})}
            37 {$packet.Events=@(@{Kind='Stop';Source=1})}
            38 {$packet.Events=@(@{Kind='Start';Sound=1;Source=2;Group=1;Volume=100})}
        }
        if($script:sequence -eq $finalPacket){$packet.Events=@(@{Kind='Start';Sound=1;Source=3;Group=1;Volume=100})}
    }
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($audio.Queue.Count -ge 32){
        if($audio.Shared.Error -or $audio.Async.IsCompleted -or $watch.ElapsedMilliseconds -gt 3000){throw 'Recovery producer queue wait failed.'}
        [Threading.Thread]::Sleep(1)
    }
    if($watch.ElapsedMilliseconds -gt 0){$waits.Add($watch.Elapsed.TotalMilliseconds)}
    Send-DoomAudioPacket $audio $packet;$script:sequence++
}
function Send-ClockedPackets([int]$Count){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    for($i=0;$i -lt $Count;$i++){
        while($watch.Elapsed.TotalMilliseconds -lt ($i+1)*1000.0/35){[Threading.Thread]::Sleep(1)}
        Send-TestPacket
    }
}
try{
    $clips=if($EffectEvents){@{1=@{Name='muted-recovery-fixture';Rate=44100;Samples=[single[]]::new(176400)}}}else{@{}}
    $audio=Start-DoomAudioRunspace $clips -MusicReports @{$track=$Qualification} -Realtime
    $audio.Shared.Volume=0;$audio.Shared.Paused=$false
    Send-TestPacket -StartMusic
    Wait-Worker {$audio.Shared.LastSequence -eq 0 -and $audio.Shared.SubmittedFrames -ge 5040} 'initial qualified music reserve'
    Send-ClockedPackets 35
    $before=$audio.Shared.SubmittedFrames;$gapWatch=[Diagnostics.Stopwatch]::StartNew()
    [Threading.Thread]::Sleep($GapMilliseconds)
    $gap=@{RequestedMilliseconds=$GapMilliseconds;ElapsedMilliseconds=$gapWatch.Elapsed.TotalMilliseconds;
        BeforeSubmittedFrames=$before;AfterSubmittedFrames=$audio.Shared.SubmittedFrames;LastSequenceBeforeCatchup=$audio.Shared.LastSequence}
    $catchup=[int][Math]::Ceiling($GapMilliseconds*35.0/1000)
    for($i=0;$i -lt $catchup;$i++){Send-TestPacket}
    Send-ClockedPackets $RecoveryTics
    $barrier=Suspend-DoomAudioAfterPacket $audio ($sequence-1)
    $report=Stop-DoomAudioRunspace $audio
    if($report.Error -or $report.CleanupError -or -not $report.DeviceClosed -or $report.Packets -ne $sequence -or $report.UnconsumedPackets -ne 0){throw 'Recovery transport/device accounting failed.'}
    if($report.CompensatedRealtimePackets+$report.PendingTimelineCredits+$report.ClearedTimelineCredits -ne $report.GeneratedRealtimeBlocks -or
        $report.PacketAgeAtProcessingMs.Count -ne $sequence -or
        $report.MixedBlocks -ne $report.Packets+$report.GeneratedRealtimeBlocks-$report.CompensatedRealtimePackets -or
        $report.SubmittedFrames -ne $report.MixedBlocks*1260 -or $report.ReturnedCompletedFrames -ne $report.SubmittedFrames){throw 'Realtime interval or packet accounting failed.'}
    if($EffectEvents){
        $finalVoice=@($report.FinalVoices|Where-Object Source -eq 3)
        if(@($report.FinalVoices|Where-Object Source -eq 1).Count -ne 0 -or $finalVoice.Count -ne 1 -or $finalVoice[0].Position -lt 1260 -or $report.PendingEffectOutput){throw 'Ordered caught-up Start/Stop events or the final event output drain failed.'}
    }
    $tail=@($report.PacketAgeAtProcessingMs|Select-Object -Last 20|Sort-Object)
    if($tail.Count -ne 20){throw 'Insufficient recovered packet ages.'}
    $recoveredAge=@{Count=$tail.Count;MedianMs=($tail[9]+$tail[10])/2;MaximumMs=$tail[-1]}
    $gate=$recoveredAge.MaximumMs -le $MaximumRecoveredPacketAgeMs
    if($RequireRecovery -and -not $gate){throw "Recovered packet age exceeds $MaximumRecoveredPacketAgeMs ms: $($recoveredAge.MaximumMs) ms."}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($audio -and -not $audio.Closed){$report=Stop-DoomAudioRunspace $audio}
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Runtime=$PSVersionTable.PSVersion.ToString();
        Track=$track;QualificationSha256=(Get-FileHash -LiteralPath $Qualification).Hash;Gap=$gap;RecoveryTics=$RecoveryTics;
        IssuedPackets=$sequence;ProducerQueueWaitMs=$waits.ToArray();RecoveredPacketAge=$recoveredAge;
        MaximumRecoveredPacketAgeMs=$MaximumRecoveredPacketAgeMs;RecoveryGatePassed=$gate;RequireRecovery=[bool]$RequireRecovery;EffectEvents=[bool]$EffectEvents;Audio=$report;Drain=$barrier;
        Sources=@(foreach($path in 'scripts/Test-AudioRealtimeRecovery.ps1','scripts/Invoke-AudioWorker.ps1','src/AudioRunspace.ps1','src/AudioPackets.ps1','src/AudioMixer.ps1','src/MusicPlayback.ps1','src/MusicLoopReader.ps1','src/WaveOutDevice.ps1'){@{Path=$path;Sha256=(Get-FileHash -LiteralPath "$root/$path").Hash}});
        Meaning='Controlled actual waveOut/qualified-music producer-gap recovery. Muted PCM, no microphone or screen. One second of 35-Hz packets, a finite no-packet interval, its caught-up packet burst, then resumed 35-Hz input. Final twenty packet ages measure construction through control/event processing, including packets whose intervals were already covered by realtime filler. Device tail and acoustic latency are excluded. The baseline test used submission ages when every packet produced PCM. RequireRecovery enforces the recovery gate; all interval/packet/driver accounting must also reconcile.'}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $Output
}
"Recovery gate: $gate; final maximum packet age $($recoveredAge.MaximumMs) ms."
