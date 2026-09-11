# SPDX-License-Identifier: GPL-2.0-or-later
# Numeric messages only. No engine objects or PowerShell class methods cross threads.
function New-DoomAudioPacketState {return @{Expires=@{};Sequence=0;Clock=0;Paused=$false;MaxSources=0;Events=0}}
function Read-DoomSoundClips {
    param($Content)
    $clips=@{}
    for($i=1;$i -lt [DoomInfo]::SfxNames.Names.Count;$i++){
        $name='DS'+[DoomInfo]::SfxNames.Names[$i].ToString().ToUpperInvariant();$lump=$Content.Wad.GetLumpNumber($name)
        if($lump -ge 0){$clips[$i]=ConvertFrom-DoomDmxSound ($Content.Wad.ReadLump($lump)) -Name $name}
    }
    if(-not $clips.ContainsKey([int][Sfx]::CHGUN)){$clips[[int][Sfx]::CHGUN]=$clips[[int][Sfx]::PISTOL]}
    return $clips
}
function Get-DoomAudioPacket {
    param($State,$Events,[hashtable]$Clips,[int]$Epoch=0)
    $batch=$Events.Drain();$State.Events+=$batch.Count
    foreach($event in $batch){
        if($event.Kind -eq 'Reset'){$State.Expires.Clear();$State.Paused=$false}
        if($event.Kind -eq 'Pause'){$State.Paused=$true}
        if($event.Kind -eq 'Resume'){$State.Paused=$false}
        if($event.Kind -eq 'Start' -and $event.Sound -ne 0){
            if(-not $Clips.ContainsKey([int]$event.Sound)){throw "Missing sound asset $($event.Sound)"}
            $clip=$Clips[[int]$event.Sound]
            $until=$State.Clock+[int][Math]::Ceiling($clip.Samples.Length*35.0/$clip.Rate)+2
            $key=[int]$event.Source
            if(-not $State.Expires.ContainsKey($key) -or $State.Expires[$key] -lt $until){$State.Expires[$key]=$until}
        }
    }
    # Conservative expiry keeps sources through the longest pending sound plus two
    # tics; retired identities are regenerated if the same object emits again.
    foreach($key in @($State.Expires.Keys)){
        if($State.Expires[$key] -lt $State.Clock){
            $State.Expires.Remove($key)
            if($Events.Sources.ContainsKey($key)){$source=$Events.Sources[$key];$Events.Keys.Remove($source)|Out-Null;$Events.Sources.Remove($key)|Out-Null}
        }
    }
    $gains=@{};$listener=$Events.Listener
    foreach($key in $State.Expires.Keys){
        $source=if($Events.Sources.ContainsKey([int]$key)){$Events.Sources[[int]$key]}else{$null}
        if($null -eq $listener -or $null -eq $source -or [object]::ReferenceEquals($listener,$source)){$gain=@(.5,.5)}
        else{$gain=Get-DoomStereoGains ($listener.X.Data/65536.0) ($listener.Y.Data/65536.0) ($listener.Angle.Data*(2*[Math]::PI/4294967296.0)) ($source.X.Data/65536.0) ($source.Y.Data/65536.0)}
        $gains[[int]$key]=[double[]]$gain
    }
    $State.MaxSources=[Math]::Max($State.MaxSources,$Events.Sources.Count)
    $packet=@{Sequence=$State.Sequence;Epoch=$Epoch;Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Events=$batch;Gains=$gains}
    $State.Sequence++;if(-not $State.Paused){$State.Clock++};return $packet
}
function Update-DoomAudioPacket {
    param($Mixer,$Packet,[hashtable]$Clips)
    foreach($event in $Packet.Events){
        switch($event.Kind){
            Start {
                if($event.Sound -eq 0){continue}
                if(-not $Clips.ContainsKey([int]$event.Sound)){throw "Missing sound asset $($event.Sound)"}
                $voice=Add-DoomAudioVoice $Mixer $Clips[[int]$event.Sound] -Source $event.Source -Group $event.Group
                $voice.BaseVolume=$event.Volume/100.0
            }
            Stop {Remove-DoomAudioSource $Mixer $event.Source}
            Reset {$Mixer.Voices.Clear();$Mixer.Paused=$false}
            Pause {$Mixer.Paused=$true}
            Resume {$Mixer.Paused=$false}
        }
    }
    foreach($voice in $Mixer.Voices){
        $gain=if($Packet.Gains.ContainsKey([int]$voice.Source)){$Packet.Gains[[int]$voice.Source]}else{@(.5,.5)}
        $voice.Left=$gain[0]*$voice.BaseVolume;$voice.Right=$gain[1]*$voice.BaseVolume
    }
}
