#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [Parameter(Mandatory)][string]$Output,
    [string]$Qualification="$PSScriptRoot/../results/music-loop-e1m1-hour-bound.json"
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..")
. "$PSScriptRoot/../src/AudioRunspace.ps1"
$Qualification=[IO.Path]::GetFullPath($Qualification);$trackData=Get-Content -LiteralPath $Qualification -Raw|ConvertFrom-Json
$track=[string]$trackData.Details.Track;if(-not $track){throw 'Music qualification has no track name.'}
$audio=$null;$report=$null;$barrier=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Wait-Audio([scriptblock]$Condition,[string]$Name,[int]$TimeoutMilliseconds=3000){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not (& $Condition)){
        if($audio.Shared.Error -or $audio.Async.IsCompleted -or $watch.ElapsedMilliseconds -gt $TimeoutMilliseconds){throw "Audio failed while waiting for $Name. $($audio.Shared.Error)"}
        [Threading.Thread]::Sleep(1)
    }
}
try{
    $audio=Start-DoomAudioRunspace @{} -MusicReports @{$track=$Qualification} -Realtime
    $audio.Shared.Paused=$false
    $packet=@{Sequence=0;Epoch=0;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=@();Gains=@{};Music=@(@{Kind='Start';Track=$track;Loop=$true})}
    Send-DoomAudioPacket $audio $packet
    Wait-Audio { $audio.Shared.LastSequence -eq 0 -and $audio.Shared.SubmittedFrames -ge 5040 } 'initial four queued music blocks'
    Check 'One simulation packet starts actual qualified music output' ($audio.Shared.LastSequence -eq 0 -and $audio.Shared.SubmittedFrames -ge 5040)
    $beforeGap=$audio.Shared.SubmittedFrames
    Wait-Audio { $audio.Shared.SubmittedFrames -ge $beforeGap+5040 } 'music blocks during a packet-producer gap'
    Check 'Active music advances while no additional simulation packet exists' ($audio.Shared.LastSequence -eq 0 -and $audio.Shared.SubmittedFrames -ge $beforeGap+5040)

    $audio.Shared.Paused=$true
    Wait-Audio { $audio.Shared.DevicePaused } 'device pause acknowledgement'
    $pausedFrames=$audio.Shared.SubmittedFrames;[Threading.Thread]::Sleep(80)
    Check 'Shared pause stops realtime block production' ($audio.Shared.SubmittedFrames -eq $pausedFrames)
    $audio.Shared.Paused=$false
    Wait-Audio { -not $audio.Shared.DevicePaused -and $audio.Shared.SubmittedFrames -ge $pausedFrames+2520 } 'music output after resume'
    Check 'Music resumes from the retained cursor without a new game packet' ($audio.Shared.LastSequence -eq 0 -and $audio.Shared.SubmittedFrames -ge $pausedFrames+2520)

    $barrier=Suspend-DoomAudioAfterPacket $audio 0;$submittedBeforeDrain=$audio.Shared.SubmittedFrames
    [Threading.Thread]::Sleep(80)
    Check 'Explicit drain stops realtime fill at the requested packet' ($audio.Shared.DrainReady -and $audio.Shared.LastSequence -eq 0 -and $audio.Shared.SubmittedFrames -eq $submittedBeforeDrain)
    $report=Stop-DoomAudioRunspace $audio
    Check 'Music advanced beyond the sole simulation block' ($report.Realtime -and $report.Packets -eq 1 -and $report.GeneratedRealtimeBlocks -ge 9 -and $report.Music.Frames -eq $report.SubmittedFrames)
    Check 'No active rebuffer occurred and drained device tail returned' (@($report.QueueStarvationObservations).Count -eq 0 -and $report.RebufferCount -eq 0 -and $report.ReturnedCompletedFrames -eq $report.SubmittedFrames -and $report.CancelledQueuedFramesUpperBound -eq 0)
    Check 'Worker and actual output device closed cleanly' (-not $report.Error -and -not $report.CleanupError -and $report.DeviceClosed)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($audio -and -not $audio.Closed){$report=Stop-DoomAudioRunspace $audio}
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();Error=$failure;Track=$track;QualificationSha256=(Get-FileHash $Qualification).Hash;Checks=$checks.ToArray();Audio=$report;Drain=$barrier;
      Sources=@('src/AudioMixer.ps1','src/AudioRunspace.ps1','src/MusicLoopReader.ps1','src/MusicPlayback.ps1','scripts/Invoke-AudioWorker.ps1','scripts/Test-AudioRealtimeContinuity.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path $root $_)).Hash}});
      Meaning='Actual waveOut device with one PowerShell simulation packet, a deliberate no-packet interval, shared pause/resume and a packet-bounded drain. Verifies that active qualified music continues on the interactive output clock. Submitted PCM and driver counters do not prove acoustic quality or latency.'}|ConvertTo-Json -Depth 9|Set-Content -LiteralPath $Output
}
"PASS: $($checks.Count) realtime audio continuity checks."
