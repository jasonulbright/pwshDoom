#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/AudioRunspace.ps1"
$audio=$null;$report=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new();$barriers=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Send([int]$Sequence){Send-DoomAudioPacket $audio @{Sequence=$Sequence;Epoch=0;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=@(@{Kind='Start';Sound=$Sequence+1;Source=1;Group=1;Volume=100});Gains=@{1=[double[]]@(.5,.5)}}}
try{
    $clips=@{};$expected=[int16[]]::new(5*2520)
    for($n=0;$n -lt 5;$n++){
        $samples=[single[]]::new(1260);[Array]::Fill($samples,[single](($n+1)*200));$clips[$n+1]=@{Name="packet $n";Rate=44100;Samples=$samples}
        [Array]::Fill($expected,[int16](($n+1)*100),$n*2520,2520)
    }
    $bytes=[byte[]]::new($expected.Length*2);[Buffer]::BlockCopy($expected,0,$bytes,0,$bytes.Length)
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $audio=Start-DoomAudioRunspace $clips
    $barriers.Add((Suspend-DoomAudioAfterPacket $audio -1))
    Check 'Empty startup boundary acknowledges without invented audio' ($audio.Shared.DrainReady -and $barriers[-1].CompletedFrames -eq 0)
    $audio.Shared.DrainTarget=$null
    Send 0;$barriers.Add((Suspend-DoomAudioAfterPacket $audio 0))
    Check 'A single initial packet plays completely before pause' ($barriers[-1].CompletedFrames -eq 1260 -and $audio.Shared.LastSequence -eq 0)
    foreach($n in 1..4){Send $n};[Threading.Thread]::Sleep(60)
    Check 'Acknowledged boundary holds later queued packets' ($audio.Shared.LastSequence -eq 0 -and $audio.Queue.Count -eq 4)
    $rejected=$false;try{$null=Suspend-DoomAudioAfterPacket $audio 4}catch{$rejected=$_.Exception.Message -match 'overlapping'}
    Check 'Overlapping boundary is rejected' $rejected
    $audio.Shared.DrainTarget=$null;$barriers.Add((Suspend-DoomAudioAfterPacket $audio 4))
    Check 'All remaining packets complete before the next acknowledgement' ($barriers[-1].CompletedFrames -eq 6300 -and $audio.Shared.LastSequence -eq 4 -and $audio.Queue.Count -eq 0)
    $report=Stop-DoomAudioRunspace $audio
    Check 'Distinct literal PCM values and ordering remain exact' ($report.PcmSha256 -ceq $expectedHash -and $report.Packets -eq 5)
    Check 'All submitted frames return with no canceled tail or stale packets' ($report.SubmittedFrames -eq 6300 -and $report.ReturnedCompletedFrames -eq 6300 -and $report.CancelledQueuedFramesUpperBound -eq 0 -and $report.StalePacketsDiscarded -eq 0)
    Check 'Intentional drains are reported separately from starvation' ($report.LoadingDrains.Count -eq 3 -and $report.QueueStarvationObservations.Count -eq 0)
    Check 'Held device and worker close cleanly' (-not $report.Error -and -not $report.CleanupError -and $report.DeviceClosed)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($audio -and -not $audio.Closed){$report=Stop-DoomAudioRunspace $audio}
    @{Error=$failure;Checks=$checks.ToArray();Barriers=$barriers.ToArray();Audio=$report;ExpectedPcmSha256=$expectedHash;Sources=@('src/AudioRunspace.ps1','scripts/Invoke-AudioWorker.ps1','scripts/Test-AudioLoadingBoundary.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});Meaning='Actual device drain/hold boundaries with five independent literal PCM packets, including empty startup, one-packet tail, queued future packets and clean held shutdown. Intentional loading silence is not uninterrupted playback.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) loading audio checks."
