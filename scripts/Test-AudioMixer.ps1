#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/AudioMixer.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $data=[byte[]]::new(104);[BitConverter]::GetBytes([uint16]3).CopyTo($data,0);[BitConverter]::GetBytes([uint16]11025).CopyTo($data,2);[BitConverter]::GetBytes([uint32]96).CopyTo($data,4)
    for($i=0;$i -lt 96;$i++){$data[8+$i]=[byte]$i}
    $clip=ConvertFrom-DoomDmxSound $data
    Check 'DMX header/padding/unsigned conversion' ($clip.Rate -eq 11025 -and $clip.Samples.Length -eq 64 -and $clip.Samples[0] -eq -28672 -and $clip.Samples[-1] -eq -12544)
    $raw=ConvertFrom-DoomDmxSound $data -Padding None;Check 'Explicit unpadded decoding' ($raw.Samples.Length -eq 96 -and $raw.Samples[0] -eq -32768)
    foreach($kind in 'short','format','rate','count','minimum'){
        $bad=$data.Clone();switch($kind){short{$bad=[byte[]]::new(7)};format{$bad[0]=0};rate{$bad[2]=0;$bad[3]=0};count{[BitConverter]::GetBytes([uint32]1000).CopyTo($bad,4)};minimum{[BitConverter]::GetBytes([uint32]48).CopyTo($bad,4)}}
        $rejected=$false;try{$null=ConvertFrom-DoomDmxSound $bad}catch{$rejected=$true};Check "Reject malformed DMX $kind" $rejected
    }
    $clip=@{Name='ramp';Rate=8000;Samples=[single[]]@(0,256,-256,512)};$m=New-DoomAudioMixer 16000
    $null=Add-DoomAudioVoice $m $clip -Left 1 -Right 0
    $pcm=Read-DoomAudioFrames $m 10;$expected=@(0,128,256,0,-256,128,512,512,0,0)
    Check 'Independent half-rate interpolation/tail/silence values' (@(for($i=0;$i -lt 10;$i++){if($pcm[2*$i] -ne $expected[$i] -or $pcm[2*$i+1] -ne 0){$i}}).Count -eq 0)
    Check 'Completed voice removed' ($m.Voices.Count -eq 0)
    $a=New-DoomAudioMixer 16000;$b=New-DoomAudioMixer 16000;$null=Add-DoomAudioVoice $a $clip;$null=Add-DoomAudioVoice $b $clip
    $whole=Read-DoomAudioFrames $a 12;$part1=Read-DoomAudioFrames $b 3;$part2=Read-DoomAudioFrames $b 9
    Check 'PCM is invariant to block boundaries' (($whole -join ',') -ceq ((@($part1)+@($part2)) -join ','))
    $clip=@{Name='constant';Rate=8000;Samples=[single[]]@(30000,30000,-30000,-30000)};$m=New-DoomAudioMixer 8000
    $null=Add-DoomAudioVoice $m $clip -Source 1 -Left 1 -Right 0;$null=Add-DoomAudioVoice $m $clip -Source 2 -Left 1 -Right 0
    $pcm=Read-DoomAudioFrames $m 4
    Check 'Overlapping channels saturate without signed wrap' (($pcm -join ',') -ceq '32767,0,32767,0,-32768,0,-32768,0' -and $m.ClippedSamples -eq 4)
    $edges=[single[]]@(32767.25,32767.5,-32768.5,-32768.75,.5,1.5,2.5,-.5,-1.5)
    $edgeMixer=New-DoomAudioMixer 8000
    $null=Add-DoomAudioVoice $edgeMixer @{Name='rounding';Rate=8000;Samples=$edges} -Left 1 -Right 0
    $edgePcm=Read-DoomAudioFrames $edgeMixer $edges.Length
    Check 'To-even cast and asymmetric saturation boundaries' (($edgePcm -join ',') -ceq '32767,0,32767,0,-32768,0,-32768,0,0,0,2,0,2,0,0,0,-2,0' -and $edgeMixer.ClippedSamples -eq 2)
    $m=New-DoomAudioMixer 8000;$voice=Add-DoomAudioVoice $m $clip;$m.Paused=$true;$pcm=Read-DoomAudioFrames $m 2
    Check 'Pause emits silence without advancing voice' (($pcm -join ',') -ceq '0,0,0,0' -and $voice.Position -eq 0)
    $m.Paused=$false;$m.Volume=0;$pcm=Read-DoomAudioFrames $m 2
    Check 'Mute emits silence while advancing voice' (($pcm -join ',') -ceq '0,0,0,0' -and $voice.Position -eq 2)
    $m=New-DoomAudioMixer 8000 -MaxVoices 2;$null=Add-DoomAudioVoice $m $clip -Source 1 -Group 1;$null=Add-DoomAudioVoice $m $clip -Source 1 -Group 1
    Check 'Same emitter/group replaces prior voice' ($m.Voices.Count -eq 1 -and $m.ReplacedVoices -eq 1)
    $null=Add-DoomAudioVoice $m $clip -Source 1 -Group 2;$null=Add-DoomAudioVoice $m $clip -Source 2 -Group 1
    Check 'Voice limit replaces oldest rather than growing' ($m.Voices.Count -eq 2 -and $m.Voices[0].Group -eq 2 -and $m.ReplacedVoices -eq 2)
    Remove-DoomAudioSource $m 1;Check 'Stop emitter preserves other emitters' ($m.Voices.Count -eq 1 -and $m.Voices[0].Source -eq 2)
    $front=Get-DoomStereoGains 0 0 0 100 0;$left=Get-DoomStereoGains 0 0 0 0 100;$right=Get-DoomStereoGains 0 0 0 0 -100;$far=Get-DoomStereoGains 0 0 0 1200 0
    Check 'Front is centered and near field is full gain' ($front[0] -eq .5 -and $front[1] -eq .5)
    Check 'Left/right cardinal pans have correct handedness' ($left[0] -eq .875 -and $left[1] -eq .125 -and $right[0] -eq .125 -and $right[1] -eq .875)
    Check 'Cutoff emits no energy' ($far[0] -eq 0 -and $far[1] -eq 0)
    $half=Get-DoomStereoGains 0 0 0 680 0;Check 'Mid attenuation point is half volume' ($half[0] -eq .25 -and $half[1] -eq .25)
    $turned=Get-DoomStereoGains 0 0 ([Math]::PI/2) 100 0;Check 'Listener rotation changes pan' ([Math]::Abs($turned[0]-.125) -lt 1e-10)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();SourceSha256=(Get-FileHash "$PSScriptRoot/../src/AudioMixer.ps1").Hash;Meaning='Deterministic synthetic DMX/PCM tests with explicit reference sample values, stereo geometry, voice lifecycle and block partitioning. No device playback or vanilla audio equivalence claim.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}
"PASS: $($checks.Count) audio mixer checks."
