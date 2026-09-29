#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/AudioRunspace.ps1"
$audio=$null;$failure=$null;$report=$null;$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Wait-Audio([scriptblock]$Condition,[string]$Name,[int]$TimeoutMilliseconds=3000){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not (& $Condition)){
        if($audio.Shared.Error -or $audio.Async.IsCompleted -or $watch.ElapsedMilliseconds -gt $TimeoutMilliseconds){throw "Audio failed while waiting for $Name. $($audio.Shared.Error)"}
        [Threading.Thread]::Sleep(1)
    }
}
try{
    $samples=[single[]]::new(2205);for($i=0;$i -lt $samples.Length;$i++){$samples[$i]=1000*[Math]::Sin($i*2*[Math]::PI*440/11025)}
    $audio=Start-DoomAudioRunspace @{1=@{Name='quiet test tone';Rate=11025;Samples=$samples}}
    Check 'Worker initialized default device' $audio.Shared.Ready
    $audio.Shared.Volume=0
    Wait-Audio { $audio.Shared.AppliedVolume -eq 0 } 'silent test output'
    $audio.Shared.Paused=$false;$watch=[Diagnostics.Stopwatch]::StartNew()
    for($tic=0;$tic -lt 105;$tic++){
        while($watch.Elapsed.TotalMilliseconds -lt $tic*1000/35){[Threading.Thread]::Sleep(1)}
        if($tic -eq 35){$audio.Shared.Paused=$true;Start-Sleep -Milliseconds 150;$audio.Shared.Paused=$false}
        if($tic -eq 70){$audio.Shared.Epoch++}
        $events=if($tic%14 -eq 0){@(@{Kind='Start';Sound=1;Source=1;Group=1;Volume=100})}else{@()}
        Send-DoomAudioPacket $audio @{Sequence=$tic;Epoch=$audio.Shared.Epoch;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=$events;Gains=@{1=[double[]]@(.5,.5)}}
    }
    Start-Sleep -Milliseconds 250
    # Exercise the epoch-publication race deterministically: hold a future packet
    # until the shared control epoch catches up instead of discarding it.
    Send-DoomAudioPacket $audio @{Sequence=105;Epoch=2;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=@();Gains=@{}}
    Start-Sleep -Milliseconds 30;$audio.Shared.Epoch=2;Start-Sleep -Milliseconds 150
    $beforeShutdown=$audio.Shared.SubmittedFrames
    Send-DoomAudioPacket $audio @{Sequence=106;Epoch=2;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=@(@{Kind='Start';Sound=1;Source=1;Group=1;Volume=100});Gains=@{1=[double[]]@(.5,.5)}}
    Send-DoomAudioPacket $audio @{Sequence=107;Epoch=2;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=@();Gains=@{}}
    Wait-Audio { $audio.Shared.LastSequence -eq 107 -and $audio.Shared.SubmittedFrames -gt $beforeShutdown -and $audio.Shared.SubmittedFrames -gt $audio.Shared.CompletedFrames } 'queued silent shutdown tail'
    $report=Stop-DoomAudioRunspace $audio
    Check 'Worker and cleanup report no error' ($null -eq $report.Error -and $null -eq $report.CleanupError -and $report.DeviceClosed)
    Check 'Real packets mixed in independent runspace' ($report.Packets -ge 97 -and $report.LastSequence -eq 107 -and $report.MaxVoices -eq 1)
    Check 'Pause observed' ($report.PauseTransitions -ge 1)
    Check 'Epoch reset and future packet retained' ($report.EpochResets -eq 2 -and $report.PendingPacket -eq $null)
    Check 'Bounded queue and returned buffers' ($report.MaxPacketQueue -le 32 -and $report.ReturnedCompletedFrames -gt 0)
    Check 'Shutdown began with queued audio' ($report.ShutdownDrain.Attempted -and $report.ShutdownDrain.PendingFramesAtStop -gt 0)
    Check 'Normal unpaused shutdown drains its queued tail' ($report.ShutdownDrain.Completed -and -not $report.ShutdownDrain.TimedOut -and $report.ShutdownDrain.RemainingFrames -eq 0 -and $report.ShutdownDrain.CancelledFramesUpperBound -eq 0)
    Check 'Queued tail completes before clean device close' ($report.ShutdownDrain.CompletedFramesDuringWait -eq $report.ShutdownDrain.PendingFramesAtStop -and $report.DeviceClosed -and $null -eq $report.Error -and $null -eq $report.CleanupError)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($audio -and -not $audio.Closed){$report=Stop-DoomAudioRunspace $audio}
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Audio=$report;Sources=@('src/AudioRunspace.ps1','src/AudioPackets.ps1','src/WaveOutDevice.ps1','scripts/Invoke-AudioWorker.ps1','scripts/Test-AudioRunspace.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Actual-device independent-runspace lifecycle with muted synthetic PCM, one pause, an epoch reset, and two queued packets at normal shutdown. Verifies that unpaused exit completes the submitted device tail within the bounded drain. No gameplay/render load or audibility claim.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) audio runspace checks."
