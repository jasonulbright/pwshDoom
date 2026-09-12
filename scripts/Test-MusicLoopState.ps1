#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$names='MusScore','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','MusicGroup','MusicLoopState'
foreach($name in $names){. "$PSScriptRoot/../src/$name.ps1"}
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $Name $rejected}
try{
    Check 'Map order is immaterial' ((Get-DoomMusicStateHash @{a=1;b=2}) -ceq (Get-DoomMusicStateHash @{b=2;a=1}))
    Check 'Double precision bits are retained' ((Get-DoomMusicStateHash 1.0) -cne (Get-DoomMusicStateHash ([Math]::BitIncrement(1.0))))
    Check 'Array ordering is material' ((Get-DoomMusicStateHash ([double[]]@(1,2))) -cne (Get-DoomMusicStateHash ([double[]]@(2,1))))
    Check 'Scalar types remain distinct' ((Get-DoomMusicStateHash 1) -cne (Get-DoomMusicStateHash 1L))
    $values=[int[]]::new(61);$values[8]=13500;$values[46]=-1;$values[47]=-1;$values[56]=100;$values[58]=-1
    foreach($op in 21,23,25,26,27,28,30,33,34,35,36){$values[$op]=-12000};$values[38]=-6000
    $region=@{Values=$values;RootKey=60;Sample=@{Rate=8000;Correction=0};Start=0;End=8;LoopStart=0;LoopEnd=8;LoopMode=1;KeyLow=0;KeyHigh=127;VelocityLow=0;VelocityHigh=127;InstrumentModulators=@();PresetModulators=@()}
    $bank=@{Samples=[int16[]]@(0,1000,2000,1000,0,-1000,-2000,-1000);Presets=@{'0:0'=@{Name='Fixture';Regions=@($region)}};SourceSha256='synthetic-bank'}
    $score=@{DurationTicks=8;SourceSha256='synthetic-score';Events=@([long[]]@(0,1,0,60,100),[long[]]@(6,2,0,8192,0),[long[]]@(7,0,0,60,0),[long[]]@(8,6,0,0,0))}
    $g=New-DoomMusicGroup $bank $score ([int[]](0..15)) (2520*4)
    $zero=Get-DoomMusicLoopSnapshot $g;$null=Read-DoomMusicGroup $g 2;$one=Get-DoomMusicLoopSnapshot $g
    $second=Read-DoomMusicGroup $g 2;$two=Get-DoomMusicLoopSnapshot $g
    $third=Read-DoomMusicGroup $g 2;$three=Get-DoomMusicLoopSnapshot $g
    Check 'Opening and sustained loop states differ' ($zero.StateSha256 -cne $one.StateSha256)
    Check 'Live release tail participates in loop state' ($one.VoiceCount -gt 0)
    Check 'Normalized adjacent loop states match' ($one.StateSha256 -ceq $two.StateSha256 -and $two.StateSha256 -ceq $three.StateSha256)
    Check 'Repeated future cycle preserves every float bit' ((Get-DoomMusicStateHash $second.Mix) -ceq (Get-DoomMusicStateHash $third.Mix))
    $voice=$g.Synth.Voices[0]
    foreach($field in 'Position','Step'){$old=$voice.Oscillator[$field];$voice.Oscillator[$field]=[Math]::BitIncrement([double]$old);Check "Oscillator $field changes fingerprint" ((Get-DoomMusicLoopSnapshot $g).StateSha256 -cne $three.StateSha256);$voice.Oscillator[$field]=$old}
    foreach($field in 'X1','Y1','ControlLeft','DeltaRight','LastCutoff'){$old=$voice[$field];$voice[$field]=[Math]::BitIncrement([double]$old);Check "Voice $field changes fingerprint" ((Get-DoomMusicLoopSnapshot $g).StateSha256 -cne $three.StateSha256);$voice[$field]=$old}
    $old=$voice.VolumeEnvelope.ReleaseValue;$voice.VolumeEnvelope.ReleaseValue+=.01;Check 'Envelope history changes fingerprint' ((Get-DoomMusicLoopSnapshot $g).StateSha256 -cne $three.StateSha256);$voice.VolumeEnvelope.ReleaseValue=$old
    $g.Synth.Channels[0].CC[7]--;Check 'Controller state changes fingerprint' ((Get-DoomMusicLoopSnapshot $g).StateSha256 -cne $three.StateSha256);$g.Synth.Channels[0].CC[7]++
    $g.Synth.Channels[0].Revision++;Check 'Pending controller revision remains material' ((Get-DoomMusicLoopSnapshot $g).StateSha256 -cne $three.StateSha256);$g.Synth.Channels[0].Revision--
    $g.Synth.PeakVoices+=100;$g.Synth.NoteOns+=100;Check 'Diagnostic counters do not change future state' ((Get-DoomMusicLoopSnapshot $g).StateSha256 -ceq $three.StateSha256)
    $g.Synth.UnknownFutureField=1;Reject 'Unknown synthesizer state requires review' {$null=Get-DoomMusicLoopSnapshot $g};$g.Synth.Remove('UnknownFutureField')
    $g.Synth.Paused=$true;Reject 'Paused snapshot rejected' {$null=Get-DoomMusicLoopSnapshot $g};$g.Synth.Paused=$false
    $g.Partition='Note';Reject 'Note-partitioned snapshot rejected' {$null=Get-DoomMusicLoopSnapshot $g};$g.Partition='Channel'
    Check 'Fingerprinting never changes the actual synthesis state' ((Get-DoomMusicLoopSnapshot $g).StateSha256 -ceq $three.StateSha256)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=@($names|ForEach-Object {@{Path="src/$_.ps1";Sha256=(Get-FileHash "$PSScriptRoot/../src/$_.ps1").Hash}});ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Synthetic recurring state with live release tails, exact future float output, bit-sensitive fields and conservative snapshot rejection. Does not by itself qualify any real score/bank or reference-engine fidelity.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) loop-state checks."
