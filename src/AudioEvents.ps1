# SPDX-License-Identifier: GPL-2.0-or-later
# Load after the engine bundle. Captures existing game callbacks without RNG use.
class DoomSoundEvents : ISound {
    [Collections.Generic.List[object]]$Events=[Collections.Generic.List[object]]::new()
    [Collections.Generic.Dictionary[object,int]]$Keys=[Collections.Generic.Dictionary[object,int]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    [Collections.Generic.Dictionary[int,object]]$Sources=[Collections.Generic.Dictionary[int,object]]::new()
    [Mobj]$Listener
    [int]$NextSource
    [int]$Tic
    [int] Register([Mobj]$source){
        if($null -eq $source){return 0}
        if(-not $this.Keys.ContainsKey($source)){$this.NextSource++;$this.Keys.Add($source,$this.NextSource);$this.Sources.Add($this.NextSource,$source)}
        return $this.Keys[$source]
    }
    [void] SetListener([Mobj]$listener){$this.Listener=$listener}
    [void] Update(){}
    [void] StartSound([sfx]$sound){$this.Events.Add(@{Kind='Start';Tic=$this.Tic;Sound=[int]$sound;Source=0;Group=0;Volume=100})}
    [void] StartSound([Mobj]$source,[sfx]$sound,[SfxType]$kind){$this.StartSound($source,$sound,$kind,100)}
    [void] StartSound([Mobj]$source,[sfx]$sound,[SfxType]$kind,[int]$level){
        $this.Events.Add(@{Kind='Start';Tic=$this.Tic;Sound=[int]$sound;Source=$this.Register($source);Group=[int]$kind+1;Volume=[Math]::Clamp($level,0,100)})
    }
    [void] StopSound([Mobj]$source){if($null -ne $source -and $this.Keys.ContainsKey($source)){$this.Events.Add(@{Kind='Stop';Tic=$this.Tic;Source=$this.Keys[$source]})}}
    [void] Reset(){$this.Events.Add(@{Kind='Reset';Tic=$this.Tic});$this.Keys.Clear();$this.Sources.Clear()}
    [void] Pause(){$this.Events.Add(@{Kind='Pause';Tic=$this.Tic})}
    [void] Resume(){$this.Events.Add(@{Kind='Resume';Tic=$this.Tic})}
    [object[]] Drain(){[object[]]$result=$this.Events.ToArray();$this.Events.Clear();return $result}
}
function Update-DoomAudioEvents {
    param($Mixer,$Events,[hashtable]$Clips,$Log)
    foreach($event in $Events.Drain()){
        if($null -ne $Log){$Log.Add($event)}
        switch($event.Kind){
            Start {
                if($event.Sound -eq 0){continue}
                if(-not $Clips.ContainsKey([int]$event.Sound)){throw "Missing sound asset $($event.Sound)"}
                $voice=Add-DoomAudioVoice $Mixer $Clips[[int]$event.Sound] -Source $event.Source -Group $event.Group
                $voice.BaseVolume=$event.Volume/100.0
            }
            Stop {Remove-DoomAudioSource $Mixer $event.Source}
            Reset {$Mixer.Voices.Clear()}
            Pause {$Mixer.Paused=$true}
            Resume {$Mixer.Paused=$false}
        }
    }
    $listener=$Events.Listener
    foreach($voice in $Mixer.Voices){
        $source=if($Events.Sources.ContainsKey([int]$voice.Source)){$Events.Sources[[int]$voice.Source]}else{$null}
        if($null -eq $listener -or $null -eq $source -or [object]::ReferenceEquals($listener,$source)){$gains=Get-DoomStereoGains -Local -Volume $voice.BaseVolume}
        else{$gains=Get-DoomStereoGains ($listener.X.Data/65536.0) ($listener.Y.Data/65536.0) ($listener.Angle.Data*(2*[Math]::PI/4294967296.0)) ($source.X.Data/65536.0) ($source.Y.Data/65536.0) -Volume $voice.BaseVolume}
        $voice.Left=$gains[0];$voice.Right=$gains[1]
    }
}
