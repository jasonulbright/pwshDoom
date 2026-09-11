#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
foreach($name in 'SoundFontRegions','MusicOscillator','MusicControls','MusicSynth'){. "$PSScriptRoot/../src/$name.ps1"}
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Fixture {
    $v=[int[]]::new(61);$v[8]=13500;$v[46]=-1;$v[47]=-1;$v[56]=100;$v[58]=-1
    foreach($op in 21,23,25,26,27,28,30,33,34,35,36,38){$v[$op]=-12000};$v[38]=0
    $samples=[int16[]]@(0,1000,2000,1000,0,-1000,-2000,-1000)
    $r=@{Values=$v;RootKey=60;Sample=@{Rate=8000;Correction=0};Start=0;End=8;LoopStart=0;LoopEnd=8;LoopMode=1;KeyLow=0;KeyHigh=127;VelocityLow=0;VelocityHigh=127;InstrumentModulators=@();PresetModulators=@()}
    return @{Samples=$samples;Presets=@{'0:0'=@{Name='Fixture';Regions=@($r)};'128:0'=@{Name='Drums';Regions=@($r)}}}
}
try{
    $channel=New-DoomMusicChannel
    Check 'No-controller modulator is unity' ((Get-DoomMusicModSource 0 $channel 60 100) -eq 1)
    Check 'Default pan center is exactly bipolar zero' ((Get-DoomMusicModSource 0x028a $channel 60 100) -eq 0)
    Check 'Pitch wheel center and lower endpoint' ((Get-DoomMusicModSource 0x020e $channel 60 100) -eq 0);$channel.Bend=0
    Check 'Pitch wheel lower endpoint is minus one' ((Get-DoomMusicModSource 0x020e $channel 60 100) -eq -1);$channel.Bend=8192
    $atten=960*(Get-DoomMusicModSource 0x0502 $channel 60 64)
    Check 'Concave velocity attenuation yields squared velocity gain' ([Math]::Abs([Math]::Pow(10,-$atten/200)-[Math]::Pow(64.0/127,2)) -lt 1e-12)
    Check 'Negative switch changes at half scale' ((Get-DoomMusicModSource 0x0d02 $channel 60 32) -eq 1 -and (Get-DoomMusicModSource 0x0d02 $channel 60 96) -eq 0)
    Check 'Bipolar switch chooses positive side at center' ((Get-DoomMusicModSource 0x0e8a $channel 60 100) -eq 1)
    $bank=Fixture;$region=$bank.Presets['0:0'].Regions[0];$mods=Get-DoomMusicModulators $region;$channel.Bend=0;$g=Get-DoomMusicGenerators $region $mods $channel 60 127
    Check 'Two-semitone bend default produces minus 200 cents' ([Math]::Abs($g[52]+200) -lt 1e-12)
    $region.InstrumentModulators=@(,[int[]]@(0x0502,48,0,0,0));$mods=Get-DoomMusicModulators $region;$channel.CC[7]=127;$channel.Bend=8192;$g=Get-DoomMusicGenerators $region $mods $channel 60 1
    Check 'Instrument zero modulator disables a default' ([Math]::Abs($g[48]) -lt 1e-12)
    $values=[double[]]::new(61);$values[33]=-32768;$values[35]=-32768;$values[37]=200
    $env=New-DoomMusicEnvelope $values 60
    Check 'Instant delay and hold sentinel' ($env.Delay -eq 0 -and $env.Hold -eq 0)
    Check 'Volume attack midpoint is linear amplitude' ((Get-DoomMusicEnvelopeValue $env .5) -eq .5)
    Check 'Volume decay follows 96 dB per declared decay duration' ([Math]::Abs((Get-DoomMusicEnvelopeValue $env 1.125)-[Math]::Pow(10,-.6)) -lt 1e-12)
    Check 'Volume sustain clamps decay' ((Get-DoomMusicEnvelopeValue $env 1.5) -eq .1)
    $env.ReleaseTime=2;$env.ReleaseValue=.1
    Check 'Volume release starts at current envelope value' ((Get-DoomMusicEnvelopeValue $env 2) -eq .1 -and (Get-DoomMusicEnvelopeValue $env 3) -eq 0)
    $values[25]=-32768;$values[27]=-32768;$values[29]=250;$env=New-DoomMusicEnvelope $values 60 -Modulation
    Check 'Modulation envelope uses linear decay and percent sustain' ((Get-DoomMusicEnvelopeValue $env 1.125) -eq .875 -and (Get-DoomMusicEnvelopeValue $env 1.5) -eq .75)
    $values[35]=0;$values[39]=100;$keyEnv=New-DoomMusicEnvelope $values 72
    Check 'Envelope hold scales with played key' ($keyEnv.Hold -eq .5)
    Check 'Delayed triangular LFO independent quarter-cycle points' ((Get-DoomMusicLfo 0 .125 2) -eq 0 -and (Get-DoomMusicLfo .25 .125 2) -eq 1 -and (Get-DoomMusicLfo .5 .125 2) -eq -1 -and (Get-DoomMusicLfo .625 .125 2) -eq 0)
    $f=Get-DoomMusicLowPass 2000 1 8000
    Check 'Independent quarter-rate low-pass coefficients' ([Math]::Abs($f[0]-1.0/3) -lt 1e-12 -and [Math]::Abs($f[1]-2.0/3) -lt 1e-12 -and [Math]::Abs($f[3]) -lt 1e-12 -and [Math]::Abs($f[4]-1.0/3) -lt 1e-12)
    $impulseBank=Fixture;$impulseBank.Samples=[int16[]]@(1,0,0,0,0,0,0,0);$impulse=New-DoomMusicSynth $impulseBank -Rate 8000
    Invoke-DoomMusicEvent $impulse ([long[]]@(0,1,0,60,127));$v=$impulse.Voices[0];$v.ControlUntil=8;$v.Filter=$f;$v.ControlLeft=1;$v.ControlRight=1
    $out=Read-DoomMusicSynth $impulse 4;$expected=[double[]]@((1.0/3),(2.0/3),(2.0/9),(-2.0/9));$impulseError=0.0
    for($i=0;$i -lt 4;$i++){$impulseError=[Math]::Max($impulseError,[Math]::Abs($out[2*$i]-$expected[$i]))}
    Check 'Independent impulse response through the actual voice filter loop' ($impulseError -lt 1e-12)
    $whole=New-DoomMusicSynth (Fixture) -Rate 8000;$parts=New-DoomMusicSynth (Fixture) -Rate 8000
    foreach($s in @($whole,$parts)){Invoke-DoomMusicEvent $s ([long[]]@(0,1,0,60,100))}
    $a=Read-DoomMusicSynth $whole 128;$joined=[Collections.Generic.List[double]]::new();foreach($size in 1,63,64){$joined.AddRange((Read-DoomMusicSynth $parts $size))}
    Check 'Full note render is exactly independent of caller block partition' (($a -join ',') -ceq ($joined -join ','))
    Check 'Dry synth emits finite nonzero stereo' (@($a|Where-Object {-not [double]::IsFinite($_)}).Count -eq 0 -and @($a|Where-Object {$_ -ne 0}).Count -gt 0)
    foreach($s in @($whole,$parts)){Invoke-DoomMusicEvent $s ([long[]]@(0,0,0,60,0))}
    $a=Read-DoomMusicSynth $whole 79;$joined.Clear();foreach($size in 7,72){$joined.AddRange((Read-DoomMusicSynth $parts $size))}
    Check 'Release render preserves caller partition invariance' (($a -join ',') -ceq ($joined -join ','))
    $whole.Paused=$true;$frame=$whole.Frame;$voiceFrame=$whole.Voices[0].Frame;$silent=Read-DoomMusicSynth $whole 64
    Check 'Synth pause freezes all clocks' ($whole.Frame -eq $frame -and $whole.Voices[0].Frame -eq $voiceFrame -and @($silent|Where-Object {$_ -ne 0}).Count -eq 0)
    $s=New-DoomMusicSynth (Fixture) -Rate 8000;Invoke-DoomMusicEvent $s ([long[]]@(0,1,0,60,100));Invoke-DoomMusicEvent $s ([long[]]@(0,4,0,8,127));Invoke-DoomMusicEvent $s ([long[]]@(0,0,0,60,0))
    Check 'Sustain pedal defers key release' (-not $s.Voices[0].Released -and -not $s.Voices[0].KeyDown)
    Invoke-DoomMusicEvent $s ([long[]]@(0,4,0,8,0));Check 'Pedal lift starts release' $s.Voices[0].Released
    Invoke-DoomMusicEvent $s ([long[]]@(0,3,0,10,0));Check 'All sounds off removes channel voices' ($s.Voices.Count -eq 0)
    Invoke-DoomMusicEvent $s ([long[]]@(0,1,15,35,100));Check 'MUS channel 15 uses drum preset' ($s.Voices.Count -eq 1 -and $s.Voices[0].Channel -eq 15)
    Invoke-DoomMusicEvent $s ([long[]]@(0,6,0,0,0));Check 'Score end releases all channels' $s.Voices[0].Released
    $null=Read-DoomMusicSynth $s 8000;Check 'Released looping voice is removed at envelope end' ($s.Voices.Count -eq 0)
    $s=New-DoomMusicSynth (Fixture) -Rate 8000;Invoke-DoomMusicEvent $s ([long[]]@(0,1,0,60,100));$null=Read-DoomMusicSynth $s 7
    Invoke-DoomMusicEvent $s ([long[]]@(0,4,0,3,0));$muted=Read-DoomMusicSynth $s 9
    Check 'Channel volume zero invalidates pending gain immediately' (@($muted|Where-Object {$_ -ne 0}).Count -eq 0 -and $s.Voices[0].Frame -eq 16)
    Invoke-DoomMusicEvent $s ([long[]]@(0,4,0,8,127));Invoke-DoomMusicEvent $s ([long[]]@(0,3,0,11,0));Check 'All notes off honors sustain pedal' (-not $s.Voices[0].KeyDown -and -not $s.Voices[0].Released)
    Invoke-DoomMusicEvent $s ([long[]]@(0,3,0,14,0));Check 'Reset controllers releases sustained notes and preserves volume' ($s.Voices[0].Released -and $s.Channels[0].CC[64] -eq 0 -and $s.Channels[0].CC[7] -eq 0 -and $s.Channels[0].CC[11] -eq 127)
    $layerBank=Fixture;$region=$layerBank.Presets['0:0'].Regions[0];$region.Values[57]=1;$layerBank.Presets['0:0'].Regions=@($region,$region)
    $layered=New-DoomMusicSynth $layerBank -Rate 8000;Invoke-DoomMusicEvent $layered ([long[]]@(0,1,0,60,100));Invoke-DoomMusicEvent $layered ([long[]]@(0,1,0,62,100))
    Check 'Exclusive class cuts older notes while retaining all new layers' ($layered.Voices.Count -eq 2 -and $layered.ExclusiveCuts -eq 2 -and $layered.Voices[0].NoteId -eq $layered.Voices[1].NoteId)
    $s.Volume=1;$pcm=ConvertTo-DoomMusicPcm $s ([double[]]@(-32768.5,32767.5,.5,1.5))
    Check 'PCM ties-to-even and asymmetric clipping boundary' (($pcm -join ',') -ceq '-32768,32767,0,2' -and $s.ClippedSamples -eq 1)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=@('src/MusicControls.ps1','src/MusicSynth.ps1','src/MusicOscillator.ps1','src/SoundFontRegions.ps1','scripts/Test-MusicSynth.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Independent control/envelope/filter vectors and dry synthesizer state/partition tests. Does not prove matching another synthesizer or complete effects/live performance.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) dry music synthesis checks."
