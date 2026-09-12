#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/AudioMixer.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $Name $rejected}
try{
    $m=New-DoomAudioMixer;$pcm=Read-DoomAudioFrames $m 2 -Music ([double[]]@(100,-100,5,15)) -MusicGain .1
    Check 'Music alone uses explicit gain and ties-to-even PCM' ($pcm[0] -eq 10 -and $pcm[1] -eq -10 -and $pcm[2] -eq 0 -and $pcm[3] -eq 2 -and $m.Frames -eq 2)
    $clip=@{Rate=44100;Samples=[single[]]@(40000,40000)};$m=New-DoomAudioMixer;$voice=Add-DoomAudioVoice $m $clip -Left 1 -Right 1
    $pcm=Read-DoomAudioFrames $m 1 -Music ([double[]]@(-20000,-20000)) -MusicGain 1
    Check 'Opposing music cancels loud effects before clipping' ($pcm[0] -eq 20000 -and $pcm[1] -eq 20000 -and $m.ClippedSamples -eq 0)
    $pcm=Read-DoomAudioFrames $m 1 -Music ([double[]]@(10000,10000)) -MusicGain 1
    Check 'Combined clipping is counted once per sample' ($pcm[0] -eq 32767 -and $pcm[1] -eq 32767 -and $m.ClippedSamples -eq 2)
    $m=New-DoomAudioMixer;$voice=Add-DoomAudioVoice $m $clip;$m.Paused=$true
    $pcm=Read-DoomAudioFrames $m 1 -Music ([double[]]@(10000,-10000))
    Check 'Paused combined mixer is silent without advancing effects' ($pcm[0] -eq 0 -and $pcm[1] -eq 0 -and $m.Frames -eq 0 -and $voice.Position -eq 0)
    $m.Paused=$false;Reject 'Wrong music span is rejected before state advances' {$null=Read-DoomAudioFrames $m 1 -Music ([double[]]@(1))}
    Reject 'NaN music rejected before state advances' {$null=Read-DoomAudioFrames $m 1 -Music ([double[]]@(0,[double]::NaN))}
    Check 'Rejected layers leave effects and frame unchanged' ($m.Frames -eq 0 -and $voice.Position -eq 0)
    $m.Volume=0;$pcm=Read-DoomAudioFrames $m 1 -Music ([double[]]@(10,-10)) -MusicGain 1
    Check 'Effects volume and explicit music gain are independent' ($pcm[0] -eq 10 -and $pcm[1] -eq -10)
    $m=New-DoomAudioMixer;$pcm=Read-DoomAudioFrames $m 1 -Music ([double[]]@(32767.5,-32768.5)) -MusicGain 1
    Check 'Combined conversion retains asymmetric rounding boundaries' ($pcm[0] -eq 32767 -and $pcm[1] -eq -32768 -and $m.ClippedSamples -eq 1)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();SourceSha256=(Get-FileHash "$PSScriptRoot/../src/AudioMixer.ps1").Hash;ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Synthetic unquantized effects/music combination with one final PCM conversion; distinct gains, pause, validation and clipping. Does not qualify device or host integration.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) music/effects mix checks."
