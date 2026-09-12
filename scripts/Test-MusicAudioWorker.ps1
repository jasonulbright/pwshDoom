#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Qualification="$PSScriptRoot/../results/music-loop-e1m1-hour-bound.json")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");foreach($name in 'AudioMixer','AudioPackets','AudioRunspace','MusicLoopReader'){. "$root/src/$name.ps1"}
$qualification=[IO.Path]::GetFullPath($Qualification);$audio=$null;$reader=$null;$report=$null;$failure=$null;$expectedHash=$null;$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Wait-AudioValue([string]$Key,$Value){
    $wait=[Diagnostics.Stopwatch]::StartNew()
    while($audio.Shared[$Key] -ne $Value){if($audio.Shared.Error -or $audio.Async.IsCompleted -or $wait.Elapsed.TotalSeconds -gt 5){throw "Audio failed waiting for $Key=$Value : $($audio.Shared.Error)"};[Threading.Thread]::Sleep(1)}
}
try{
    $samples=[single[]]::new(12600);for($i=0;$i -lt $samples.Length;$i++){$samples[$i]=300*[Math]::Sin($i*2*[Math]::PI*440/44100)}
    $clips=@{1=@{Name='quiet worker fixture';Rate=44100;Samples=$samples}};$packets=[Collections.Generic.List[object]]::new()
    for($n=0;$n -lt 140;$n++){
        $events=@();if($n -in 0,70,105){$events+=@{Kind='Start';Sound=1;Source=1;Group=1;Volume=100}}
        if($n -eq 14){$events+=@{Kind='Pause'}};if($n -eq 16){$events+=@{Kind='Resume'}}
        $music=@();if($n -eq 0){$music+=@{Kind='Start';Track='D_E1M1';Loop=$true;Frame=(95*44100)}}
        if($n -eq 35){$music+=@{Kind='Gain';Value=.1}}
        if($n -in 70,130){$music+=@{Kind='Start';Track='D_E1M1';Loop=$true}}
        if($n -eq 120){$music+=@{Kind='Stop'}}
        $packets.Add(@{Sequence=$n;Epoch=if($n -lt 70){0}else{1};Qpc=0L;Events=$events;Gains=@{1=[double[]]@(.5,.25)};Music=$music})
    }
    # Independent offline music control schedule; do not use the worker's command helper.
    $reader=Open-DoomMusicLoopReader $qualification;$reader.Frame=95*44100;$m=New-DoomAudioMixer;$gain=.2;$active=$true
    $expected=[int16[]]::new(140*2520)
    for($n=0;$n -lt 140;$n++){
        if($n -eq 35){$gain=.1};if($n -eq 70){$m.Voices.Clear();$m.Paused=$false;$reader.Frame=0}
        if($n -eq 120){$active=$false};if($n -eq 130){$active=$true;$reader.Frame=0}
        $m.Volume=if($n -lt 70){1.0}elseif($n -lt 105){0.0}else{.5}
        Update-DoomAudioPacket $m $packets[$n] $clips
        $layer=if($active -and -not $m.Paused){(Read-DoomMusicLoop $reader 1260).Mix}else{$null}
        $pcm=Read-DoomAudioFrames $m 1260 -Music $layer -MusicGain ($gain*$m.Volume);$pcm.CopyTo($expected,$n*2520)
    }
    Close-DoomMusicLoopReader $reader;$reader=$null;$bytes=[byte[]]::new($expected.Length*2);[Buffer]::BlockCopy($expected,0,$bytes,0,$bytes.Length)
    $expectedHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $audio=Start-DoomAudioRunspace $clips -MusicReports @{'D_E1M1'=$qualification};Check 'Qualified catalog and actual device initialize' $audio.Shared.Ready
    $audio.Shared.Paused=$false;$watch=[Diagnostics.Stopwatch]::StartNew();$offset=0.0
    for($n=0;$n -lt 140;$n++){
        while($watch.Elapsed.TotalSeconds -lt $n/35.0+$offset){[Threading.Thread]::Sleep(1)}
        if($n -eq 70){
            Wait-AudioValue LastSequence 69;$audio.Shared.Paused=$true;$audio.Shared.Volume=0.0;Wait-AudioValue AppliedVolume 0.0
            $packets[$n].Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Send-DoomAudioPacket $audio $packets[$n];[Threading.Thread]::Sleep(80)
            Check 'Shared pause prevents consumption of queued music packet' ($audio.Shared.LastSequence -eq 69)
            $audio.Shared.Paused=$false;[Threading.Thread]::Sleep(30)
            Check 'Future epoch music packet waits for control epoch' ($audio.Shared.LastSequence -eq 69)
            $audio.Shared.Epoch=1;Wait-AudioValue LastSequence 70;$offset=$watch.Elapsed.TotalSeconds-$n/35.0;continue
        }
        if($n -eq 105){Wait-AudioValue LastSequence 104;$audio.Shared.Paused=$true;$audio.Shared.Volume=.5;Wait-AudioValue AppliedVolume .5;$audio.Shared.Paused=$false;$offset=$watch.Elapsed.TotalSeconds-$n/35.0}
        $packets[$n].Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Send-DoomAudioPacket $audio $packets[$n]
    }
    Wait-AudioValue LastSequence 139;[Threading.Thread]::Sleep(180);$report=Stop-DoomAudioRunspace $audio
    Check 'Worker, device and music handles close cleanly' (-not $report.Error -and -not $report.CleanupError -and $report.DeviceClosed -and $report.Music.Closed)
    Check 'Every submitted sample matches independent offline schedule' ($report.PcmSha256 -ceq $expectedHash -and $report.SubmittedFrames -eq 176400 -and $report.Packets -eq 140)
    Check 'Music pause, mute advancement, stop and restart preserve frame accounting' ($report.Music.Frames -eq 161280 -and $report.Music.Selected -ceq 'D_E1M1' -and $report.Music.Gain -eq .1)
    Check 'Master mute and volume applied to complete mix' ($report.MutedPackets -eq 35 -and $report.FinalVolume -eq .5 -and $report.VolumeChanges.Count -eq 2)
    Check 'Epoch transition retains future packet with no loss' ($report.EpochResets -eq 1 -and $report.StalePacketsDiscarded -eq 0 -and $null -eq $report.PendingPacket -and $report.UnconsumedPackets -eq 0)
    Check 'All intended music commands and epoch reset are recorded' ($report.Music.Transitions.Count -eq 6 -and $report.Music.Reports.D_E1M1 -ceq (Get-FileHash $qualification).Hash)
    Check 'Device returns completed buffers with bounded packet queue' ($report.ReturnedCompletedFrames -gt 0 -and $report.MaxPacketQueue -le 32)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($reader){Close-DoomMusicLoopReader $reader};if($audio -and -not $audio.Closed){$report=Stop-DoomAudioRunspace $audio}
    @{Error=$failure;Checks=$checks.ToArray();ExpectedPcmSha256=$expectedHash;Audio=$report;QualificationSha256=(Get-FileHash $qualification).Hash;
      Sources=@('src/AudioMixer.ps1','src/AudioPackets.ps1','src/AudioRunspace.ps1','src/WaveOutDevice.ps1','src/MusicLoopReader.ps1','src/MusicPlayback.ps1','scripts/Invoke-AudioWorker.ps1','scripts/Test-MusicAudioWorker.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path $root $_)).Hash}});
      Meaning='Actual default waveOut device with qualified E1M1 across its intro/loop seam, synthetic effect, packet/shared pauses, independent gains, master mute, epoch and restart. Complete submitted PCM compared with independent offline command schedule. Reset may cancel queued device tail; submitted bytes do not prove acoustic output/latency or gameplay-load qualification. Audio-only test, no terminal effect run or screen capture.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) music audio-worker checks."
