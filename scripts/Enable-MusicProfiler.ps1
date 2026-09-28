#requires -Version 7.4
# Instrument an owned source snapshot for experiments; never used by the host.
param([string]$Source="$PSScriptRoot/../src/MusicSynth.ps1")
$text=[IO.File]::ReadAllText([IO.Path]::GetFullPath($Source))
$changes=@(
    @('{Update-DoomMusicVoiceControl $Voice $Synth}','{$pfControl=[Diagnostics.Stopwatch]::GetTimestamp();Update-DoomMusicVoiceControl $Voice $Synth;$Synth.Profile.ControlTicks+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfControl;$Synth.Profile.ControlCalls++}'),
    @('$env=Get-DoomMusicEnvelopeValue $Voice.ModEnvelope $time','$pfEnvelope=[Diagnostics.Stopwatch]::GetTimestamp();$env=Get-DoomMusicEnvelopeValue $Voice.ModEnvelope $time;$Synth.Profile.EnvelopeTicks+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfEnvelope;$Synth.Profile.EnvelopeCalls++'),
    @('$gain*=Get-DoomMusicEnvelopeValue $Voice.VolumeEnvelope $time;$gainNext*=Get-DoomMusicEnvelopeValue $Voice.VolumeEnvelope $nextTime','$pfEnvelope=[Diagnostics.Stopwatch]::GetTimestamp();$gain*=Get-DoomMusicEnvelopeValue $Voice.VolumeEnvelope $time;$Synth.Profile.EnvelopeTicks+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfEnvelope;$Synth.Profile.EnvelopeCalls++;$pfEnvelope=[Diagnostics.Stopwatch]::GetTimestamp();$gainNext*=Get-DoomMusicEnvelopeValue $Voice.VolumeEnvelope $nextTime;$Synth.Profile.EnvelopeTicks+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfEnvelope;$Synth.Profile.EnvelopeCalls++'),
    @('$Voice.Filter=Get-DoomMusicLowPass $cutoff $s[8] $Synth.Rate;','$pfFilter=[Diagnostics.Stopwatch]::GetTimestamp();$Voice.Filter=Get-DoomMusicLowPass $cutoff $s[8] $Synth.Rate;$Synth.Profile.FilterTicks+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfFilter;$Synth.Profile.FilterCalls++;'),
    @('# Fuse sample interpolation with filtering;','$pfMix=[Diagnostics.Stopwatch]::GetTimestamp();# Fuse sample interpolation with filtering;'),
    @('$Voice.X1=$x1;','$Synth.Profile.FusedVoiceTicks+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfMix;$Synth.Profile.FusedVoiceCalls++;$Voice.X1=$x1;')
)
foreach($change in $changes){
    if([regex]::Matches($text,[regex]::Escape($change[0])).Count -ne 1){throw 'Music profiler source marker is missing or ambiguous.'}
    $text=$text.Replace($change[0],$change[1])
}
$script:MusicInstrumentedSourceSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text)))
. ([scriptblock]::Create($text))
