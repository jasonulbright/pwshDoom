#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/AudioMixer.ps1";. "$PSScriptRoot/../src/AudioPackets.ps1"
class PacketTestEvents {
    [Collections.Generic.List[object]]$Events=[Collections.Generic.List[object]]::new()
    [Collections.Generic.Dictionary[object,int]]$Keys=[Collections.Generic.Dictionary[object,int]]::new()
    [Collections.Generic.Dictionary[int,object]]$Sources=[Collections.Generic.Dictionary[int,object]]::new()
    [object]$Listener
    [object[]]Drain(){$items=$this.Events.ToArray();$this.Events.Clear();return $items}
}
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $events=[PacketTestEvents]::new();$source=[object]::new();$events.Keys.Add($source,1);$events.Sources.Add(1,$source)
    $clips=@{1=@{Name='short';Rate=11025;Samples=[single[]]@(256,512,768,1024)}};$state=New-DoomAudioPacketState
    $events.Events.Add(@{Kind='Start';Sound=1;Source=1;Group=1;Volume=50})
    $packet=Get-DoomAudioPacket $state $events $clips
    Check 'Event batch drains and numeric center gains captured' ($packet.Events.Count -eq 1 -and $events.Events.Count -eq 0 -and $packet.Gains[1][0] -eq .5)
    $mixer=New-DoomAudioMixer 44100;Update-DoomAudioPacket $mixer $packet $clips
    $pcm=Read-DoomAudioFrames $mixer 4
    Check 'Start volume, interpolation and stereo sample values' (($pcm -join ',') -eq '64,64,80,80,96,96,112,112')
    $replaceEvents=[PacketTestEvents]::new();$replaceSource=[object]::new();$replaceEvents.Keys.Add($replaceSource,1);$replaceEvents.Sources.Add(1,$replaceSource)
    $replaceState=New-DoomAudioPacketState;$replaceMixer=New-DoomAudioMixer 44100
    $replaceEvents.Events.Add(@{Kind='Start';Sound=1;Source=1;Group=1;Volume=100})
    $replacePacket=Get-DoomAudioPacket $replaceState $replaceEvents $clips;Update-DoomAudioPacket $replaceMixer $replacePacket $clips
    $replaceEvents.Events.Add(@{Kind='Start';Sound=1;Source=1;Group=2;Volume=100})
    $replacePacket=Get-DoomAudioPacket $replaceState $replaceEvents $clips;Update-DoomAudioPacket $replaceMixer $replacePacket $clips
    Check 'Production packet path replaces the prior sound across emitter categories' ($replaceMixer.Voices.Count -eq 1 -and $replaceMixer.Voices[0].Source -eq 1 -and $replaceMixer.Voices[0].Group -eq 2 -and $replaceMixer.ReplacedVoices -eq 1)
    $events.Events.Add(@{Kind='Pause'});$null=Get-DoomAudioPacket $state $events $clips
    for($i=0;$i -lt 50;$i++){$null=Get-DoomAudioPacket $state $events $clips}
    Check 'Paused packets retain emitter lifetime' ($events.Sources.Count -eq 1 -and $state.Clock -eq 1 -and $state.Sequence -eq 52)
    $events.Events.Add(@{Kind='Resume'})
    for($i=0;$i -lt 4;$i++){$null=Get-DoomAudioPacket $state $events $clips}
    Check 'Expired emitter removed from both registries' ($events.Sources.Count -eq 0 -and $events.Keys.Count -eq 0)
    $events.Events.Add(@{Kind='Start';Sound=999;Source=1;Group=1;Volume=100});$rejected=$false
    try{$null=Get-DoomAudioPacket $state $events $clips}catch{$rejected=$true};Check 'Missing referenced clip rejected' $rejected
    $mixer.Paused=$true;Update-DoomAudioPacket $mixer @{Events=@(@{Kind='Reset'});Gains=@{}} $clips
    Check 'World reset clears voices and old pause' ($mixer.Voices.Count -eq 0 -and -not $mixer.Paused)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=@('src/AudioPackets.ps1','scripts/Test-AudioPackets.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Independent numeric packet lifetime, pause/reset, conversion and malformed asset tests.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) packet checks."
