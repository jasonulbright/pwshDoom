#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/AudioRunspace.ps1"
$audio=$null;$report=$null;$failure=$null;$expectedHash=$null;$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Wait-AudioValue([string]$Key,$Value){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($audio.Shared[$Key] -ne $Value){if($audio.Shared.Error -or $audio.Async.IsCompleted -or $watch.Elapsed.TotalSeconds -gt 3){throw "Audio did not acknowledge $Key=$Value"};[Threading.Thread]::Sleep(1)}
}
try{
    $samples=[single[]]::new(10080);$expected=[int16[]]::new(20160)
    for($i=0;$i -lt 10080;$i++){
        $samples[$i]=($i%1000)-500
        $gain=if($i -lt 3780){1.0}elseif($i -lt 7560){0.0}else{.25}
        $expected[2*$i]=[int16]($samples[$i]*$gain)
    }
    $bytes=[byte[]]::new($expected.Length*2);[Buffer]::BlockCopy($expected,0,$bytes,0,$bytes.Length)
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $audio=Start-DoomAudioRunspace @{1=@{Name='quiet numeric ramp';Rate=44100;Samples=$samples}}
    foreach($segment in @(@{First=0;End=2;Gain=1.0},@{First=3;End=5;Gain=0.0},@{First=6;End=7;Gain=.25})){
        $audio.Shared.Paused=$true;$audio.Shared.Volume=$segment.Gain;Wait-AudioValue AppliedVolume $segment.Gain
        $audio.Shared.Paused=$false
        for($n=$segment.First;$n -le $segment.End;$n++){
            $events=if($n -eq 0){@(@{Kind='Start';Sound=1;Source=1;Group=1;Volume=100})}else{@()}
            Send-DoomAudioPacket $audio @{Sequence=$n;Epoch=0;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=$events;Gains=@{1=[double[]]@(1,0)}}
        }
        Wait-AudioValue LastSequence $segment.End
    }
    $report=Stop-DoomAudioRunspace $audio
    Check 'Device and worker close cleanly' ($null -eq $report.Error -and $null -eq $report.CleanupError -and $report.DeviceClosed)
    Check 'Submitted PCM matches independent gain and timeline vector' ($report.PcmSha256 -eq $expectedHash -and $report.SubmittedFrames -eq 10080)
    Check 'Mute produces three packets without resetting the active voice' ($report.MutedPackets -eq 3 -and $report.Packets -eq 8 -and $report.EpochResets -eq 0)
    Check 'Gain acknowledgements retain selected quarter volume' ($report.VolumeChanges.Count -eq 2 -and $report.VolumeChanges[0].Volume -eq 0 -and $report.VolumeChanges[1].Volume -eq .25 -and $report.FinalVolume -eq .25)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($audio -and -not $audio.Closed){$report=Stop-DoomAudioRunspace $audio}
    @{Error=$failure;Checks=$checks.ToArray();ExpectedPcmSha256=$expectedHash;Audio=$report;Sources=@('src/AudioMixer.ps1','src/AudioRunspace.ps1','scripts/Invoke-AudioWorker.ps1','scripts/Test-AudioVolume.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Independent submitted-PCM vector across full volume, mute and quarter volume in the actual playback runspace. Gain changes can cancel queued tail PCM. No acoustic latency or listening claim.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) audio volume checks."
