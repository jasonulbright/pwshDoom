#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[ValidateRange(0,500)][int]$ProducerGapMilliseconds=0)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh test report path.'}
. "$PSScriptRoot/../src/AudioRunspace.ps1"
$audio=$null;$failure=$null;$report=$null;$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function WaitValue([string]$Name,$Value){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($audio.Shared[$Name] -ne $Value){if($audio.Shared.Error -or $audio.Async.IsCompleted -or $watch.ElapsedMilliseconds -gt 3000){throw "Audio failed waiting for $Name=$Value"};[Threading.Thread]::Sleep(1)}
}
function Send([int]$Sequence){Send-DoomAudioPacket $audio @{Sequence=$Sequence;Epoch=0;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=@(@{Kind='Start';Sound=$Sequence+1;Source=1;Group=1;Volume=100});Gains=@{1=[double[]]@(.5,.5)}}}
try{
    $clips=@{};$expected=[int16[]]::new(7*2520)
    for($n=0;$n -lt 7;$n++){
        $samples=[single[]]::new(1260);[Array]::Fill($samples,[single](($n+1)*200));$clips[$n+1]=@{Name="packet $n";Rate=44100;Samples=$samples}
        [Array]::Fill($expected,[int16](($n+1)*100),$n*2520,2520)
    }
    $bytes=[byte[]]::new($expected.Length*2);[Buffer]::BlockCopy($expected,0,$bytes,0,$bytes.Length)
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $audio=Start-DoomAudioRunspace $clips;$audio.Shared.Paused=$false
    foreach($n in 0..3){Send $n}
    WaitValue RebufferCount 1
    Check 'Drained device enters recovery after the initial four packets' ($audio.Shared.Rebuffering -and $audio.Shared.LastSequence -eq 3)
    if($ProducerGapMilliseconds){[Threading.Thread]::Sleep($ProducerGapMilliseconds)}
    Send 4;WaitValue LastSequence 4;[Threading.Thread]::Sleep(15)
    Check 'One recovery packet is held briefly for a reserve' ($audio.Shared.Rebuffering -and $audio.Shared.RebufferResumeCount -eq 0)
    Send 5;WaitValue RebufferResumeCount 1
    WaitValue RebufferCount 2
    Send 6;WaitValue LastSequence 6
    WaitValue RebufferResumeCount 2
    WaitValue RebufferCount 3
    $report=Stop-DoomAudioRunspace $audio
    Check 'Exactly two packets restart the first recovery' ($report.RebufferResumes[0].QueuedBuffers -eq 2 -and $report.RebufferResumes[0].Reason -ceq 'TwoPackets')
    Check 'Final single packet restarts after the bounded deadline' ($report.RebufferResumes[1].QueuedBuffers -eq 1 -and $report.RebufferResumes[1].Reason -ceq 'SinglePacketDeadline' -and $report.RebufferResumes[1].ReserveWaitMilliseconds -ge 100 -and $report.RebufferResumes[1].ReserveWaitMilliseconds -lt 3000)
    Check 'All literal PCM samples retain their original sequence and values' ($report.PcmSha256 -ceq $expectedHash -and $report.Packets -eq 7 -and $report.SubmittedFrames -eq 8820)
    Check 'Every frame completes with no discarded packets or cancelled tail' ($report.ReturnedCompletedFrames -eq 8820 -and $report.CancelledQueuedFramesUpperBound -eq 0 -and $report.StalePacketsDiscarded -eq 0 -and $report.UnconsumedPackets -eq 0)
    Check 'Device and worker close without error' (-not $report.Error -and -not $report.CleanupError -and $report.DeviceClosed)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($audio -and -not $audio.Closed){$report=Stop-DoomAudioRunspace $audio}
    @{Error=$failure;ProducerGapMilliseconds=$ProducerGapMilliseconds;Checks=$checks.ToArray();Audio=$report;ExpectedPcmSha256=$expectedHash;Sources=@('scripts/Invoke-AudioWorker.ps1','src/AudioRunspace.ps1','src/WaveOutDevice.ps1','scripts/Test-AudioRebuffer.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});
      Meaning='Finite actual device test with seven distinct literal PCM packets. Deliberate producer gaps verify two-packet reserve recovery, bounded final-single-packet playback, unchanged PCM order and complete device return. Does not eliminate producer stalls or measure acoustics.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) rebuffer checks."
