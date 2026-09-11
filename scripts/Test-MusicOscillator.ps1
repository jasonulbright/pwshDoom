#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/MusicOscillator.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Fixture([int]$Mode=0){
    $v=[int[]]::new(61);$v[46]=-1;$v[56]=100
    $r=@{Values=$v;RootKey=60;Sample=@{Rate=22050;Correction=0};Start=0;End=8;LoopStart=2;LoopEnd=5;LoopMode=$Mode}
    $b=@{Samples=[int16[]]@(0,1000,2000,3000,4000,5000,6000,7000)}
    return New-DoomMusicOscillator $b $r
}
try{
    $v=Fixture;$samples=Read-DoomMusicOscillator $v 18
    Check 'Independent half-rate interpolation and finite tail' (($samples -join ',') -ceq '0,500,1000,1500,2000,2500,3000,3500,4000,4500,5000,5500,6000,6500,7000,7000,0,0' -and $v.Finished)
    $v=Fixture 1;$samples=Read-DoomMusicOscillator $v 16
    Check 'Independent fractional loop interpolation wraps next tap' (($samples -join ',') -ceq '0,500,1000,1500,2000,2500,3000,3500,4000,3000,2000,2500,3000,3500,4000,3000')
    $v=Fixture 3;$null=Read-DoomMusicOscillator $v 12;$v.Released=$true;$tail=Read-DoomMusicOscillator $v 12
    Check 'Sustain loop exits into sample tail after release' (($tail -join ',') -ceq '3000,3500,4000,4500,5000,5500,6000,6500,7000,7000,0,0' -and $v.Finished)
    $v=Fixture 1;$v.Released=$true;$samples=Read-DoomMusicOscillator $v 100
    Check 'Continuous loop remains looping through release' (-not $v.Finished -and $samples[99] -eq 3000)
    $whole=Fixture 1;$expected=Read-DoomMusicOscillator $whole 101;$parts=Fixture 1;$joined=[Collections.Generic.List[double]]::new()
    foreach($size in 1,7,13,16,64){$joined.AddRange((Read-DoomMusicOscillator $parts $size))}
    Check 'Oscillator block partition invariance' (($expected -join ',') -ceq ($joined -join ',') -and $whole.Position -eq $parts.Position)
    $v=Fixture 1;$null=Read-DoomMusicOscillator $v 7;$position=$v.Position;$v.Paused=$true;$silent=Read-DoomMusicOscillator $v 10
    Check 'Pause freezes position and clock' ($v.Position -eq $position -and $v.Frames -eq 7 -and @($silent|Where-Object {$_ -ne 0}).Count -eq 0)
    $v=Fixture;$v.Region.Values[51]=12;$octave=New-DoomMusicOscillator @{Samples=$v.Samples} $v.Region
    Check 'Coarse octave doubles source step' ($octave.Step -eq 1)
    $v.Region.Values[51]=0;$v.Region.Values[46]=72;$forced=New-DoomMusicOscillator @{Samples=$v.Samples} $v.Region -Key 24
    Check 'Forced key replaces played key for pitch' ($forced.Step -eq 1)
    $v.Region.Values[46]=-1;$v.Region.Values[56]=0;$fixed=New-DoomMusicOscillator @{Samples=$v.Samples} $v.Region -Key 72 -BendCents 1200
    Check 'Zero scale tuning retains bend' ($fixed.Step -eq 1)
    $v=Fixture 1;$v.Step=12;$samples=Read-DoomMusicOscillator $v 4
    Check 'Large step crosses multiple loops without losing phase' (($samples -join ',') -ceq '0,3000,3000,3000')
    $v=Fixture 1;$v.Step=.7;$samples=Read-DoomMusicOscillator $v 200;$maxError=0.0
    for($i=0;$i -lt 200;$i++){
        $phase=$i*.7;if($phase -ge 5){$phase=2+($phase-2)%3}
        $expected=if($phase -le 4){1000*$phase}else{12000-2000*$phase}
        $maxError=[Math]::Max($maxError,[Math]::Abs($samples[$i]-$expected))
    }
    Check 'Fractional-step loops match an independent piecewise waveform' ($maxError -lt 1e-8)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=@('src/MusicOscillator.ps1','scripts/Test-MusicOscillator.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Independent sample oscillator values, loop/release behavior and pitch ratios. No envelopes, filters, controller modulation or complete synthesizer fidelity.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) oscillator checks."
