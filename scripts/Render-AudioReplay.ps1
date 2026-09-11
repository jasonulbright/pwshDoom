#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay="$PSScriptRoot/../results/input-session-replay.json",[switch]$PacketMix,[string]$VolumeSchedule)
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/audio-replay-$PID.ps1";. $bundle
. "$PSScriptRoot/../src/AudioMixer.ps1";. "$PSScriptRoot/../src/AudioEvents.ps1";. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1";. "$PSScriptRoot/FrameCodec.ps1"
. "$PSScriptRoot/../src/AudioPackets.ps1";$packetState=New-DoomAudioPacketState
$directory=Join-Path "$PSScriptRoot/../local" ('audio-replay-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
$content=$null;$failure=$null;$clips=@{};$assets=[Collections.Generic.List[object]]::new();$eventsLog=[Collections.Generic.List[object]]::new()
$mixTimes=[Collections.Generic.List[double]]::new();$eventTimes=[Collections.Generic.List[double]]::new();$checkpoints=[Collections.Generic.List[object]]::new()
$comparison=$null;$wav=$null;$maxVoices=0;$pcm=$null;$mixer=$null;$peak=0;$nonzero=0L
$volumePoints=@();$volumeIndex=0
try{
    if($VolumeSchedule){
        if((Get-Item $VolumeSchedule).Length -gt 1MB){throw 'Volume schedule is too large.'}
        $volumePoints=@(Get-Content $VolumeSchedule -Raw|ConvertFrom-Json -Depth 4);$previous=-1
        foreach($point in $volumePoints){
            if($point.AfterPacket -isnot [long] -or $point.AfterPacket -lt -1 -or $point.AfterPacket -gt 21000 -or $point.AfterPacket -lt $previous -or
                ($point.Volume -isnot [double] -and $point.Volume -isnot [long]) -or -not [double]::IsFinite([double]$point.Volume) -or $point.Volume -lt 0 -or $point.Volume -gt 1){throw 'Invalid ordered volume schedule.'}
            $previous=$point.AfterPacket
        }
    }
    $recorded=Read-DoomInputReplay $Replay (Get-FileHash $Wad).Hash
    if($null -ne $recorded.ControlEvents -and $recorded.ControlEvents.Count){throw 'This first offline harness requires a route without save/new-game control events.'}
    if($recorded.InputCommands.Count -gt 21000){throw 'Choose a bounded audio fixture of at most ten minutes.'}
    $content=[GameContent]::new(@('-iwad',$Wad))
    for($i=1;$i -lt [DoomInfo]::SfxNames.Names.Count;$i++){
        $name='DS'+[DoomInfo]::SfxNames.Names[$i].ToString().ToUpperInvariant();$lump=$content.Wad.GetLumpNumber($name)
        if($lump -lt 0){continue}
        $bytes=$content.Wad.ReadLump($lump);$clip=ConvertFrom-DoomDmxSound $bytes -Name $name;$clips[$i]=$clip
        $assets.Add(@{Id=$i;Name=$name;SampleRate=$clip.Rate;Samples=$clip.Samples.Length;Padding=$clip.Padding;LumpSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))})
    }
    # Doom's chaingun uses the pistol source when no replacement lump exists.
    if(-not $clips.ContainsKey([int][Sfx]::CHGUN)){$clips[[int][Sfx]::CHGUN]=$clips[[int][Sfx]::PISTOL]}
    $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $events=[DoomSoundEvents]::new();$options.Sound=$events;$mixer=New-DoomAudioMixer 44100
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]([int]$recorded.Skill-1),[int]$recorded.Episode,[int]$recorded.Map);$null=$game.Update($commands)
    if($PacketMix){$packet=Get-DoomAudioPacket $packetState $events $clips;foreach($event in $packet.Events){$eventsLog.Add($event)};Update-DoomAudioPacket $mixer $packet $clips}
    else{Update-DoomAudioEvents $mixer $events $clips $eventsLog}
    $checkpointTics=@{};foreach($point in $recorded.Checkpoints){$checkpointTics[[int]$point.Tic]=$true}
    $pcm=[int16[]]::new($recorded.InputCommands.Count*1260*2);$watch=[Diagnostics.Stopwatch]::new()
    for($tic=0;$tic -le $recorded.InputCommands.Count;$tic++){
        if($checkpointTics.ContainsKey($tic)){$checkpoints.Add((Get-DoomReplayCheckpoint $game $tic))}
        if($tic -eq $recorded.InputCommands.Count){break}
        while($volumeIndex -lt $volumePoints.Count -and $volumePoints[$volumeIndex].AfterPacket -lt $tic){$mixer.Volume=[double]$volumePoints[$volumeIndex].Volume;$volumeIndex++}
        $events.Tic=$tic;$entry=$recorded.InputCommands[$tic];$cmd=$commands[0];$cmd.Clear();$cmd.ForwardMove=$entry[0];$cmd.SideMove=$entry[1];$cmd.AngleTurn=$entry[2];$cmd.Buttons=$entry[3]
        $null=$game.Update($commands);$watch.Restart()
        if($PacketMix){$packet=Get-DoomAudioPacket $packetState $events $clips;foreach($event in $packet.Events){$eventsLog.Add($event)};Update-DoomAudioPacket $mixer $packet $clips}
        else{Update-DoomAudioEvents $mixer $events $clips $eventsLog}
        $eventTimes.Add($watch.Elapsed.TotalMilliseconds)
        $maxVoices=[Math]::Max($maxVoices,$mixer.Voices.Count);$watch.Restart();$block=Read-DoomAudioFrames $mixer 1260;$mixTimes.Add($watch.Elapsed.TotalMilliseconds)
        [Array]::Copy($block,0,$pcm,$tic*2520,$block.Length)
    }
    $comparison=Compare-DoomReplayCheckpoints $recorded.Checkpoints $checkpoints.ToArray() $recorded.InputCommands.Count
    if(-not $comparison.Matched -or $comparison.Checked -ne 8){throw 'Audio event capture changed the qualified route.'}
    for($i=0;$i -lt $pcm.Length;$i++){if($pcm[$i]){$nonzero++};$peak=[Math]::Max($peak,[Math]::Abs([int]$pcm[$i]))}
    if($nonzero -eq 0){throw 'Audio output is entirely silent.'}
    $wav=Join-Path $directory replay.wav;Write-DoomPcmWave $wav $pcm
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;WadSha256=(Get-FileHash $Wad).Hash;ReplaySha256=(Get-FileHash $Replay).Hash;BundleSha256=(Get-FileHash $bundle).Hash;
        PacketMix=[bool]$PacketMix;PacketMaxSources=$packetState.MaxSources;VolumeScheduleSha256=if($VolumeSchedule){(Get-FileHash $VolumeSchedule).Hash}else{$null};VolumeChangesApplied=$volumeIndex;
        Sources=@('src/AudioMixer.ps1','src/AudioEvents.ps1','src/AudioPackets.ps1','scripts/Render-AudioReplay.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
        Assets=$assets.ToArray();Events=$eventsLog.ToArray();CheckpointComparison=$comparison;MixMs=(Get-SampleStats $mixTimes.ToArray());EventMs=(Get-SampleStats $eventTimes.ToArray());MixSamplesMs=$mixTimes.ToArray();EventSamplesMs=$eventTimes.ToArray();MaxVoices=$maxVoices;Peak=$peak;NonzeroSamples=$nonzero;ClippedSamples=if($mixer){$mixer.ClippedSamples}else{0};ReplacedVoices=if($mixer){$mixer.ReplacedVoices}else{0};Wave=$wav;WaveSha256=if($wav -and (Test-Path $wav)){(Get-FileHash $wav).Hash}else{$null};SampleRate=44100;OutputFrames=if($pcm){$pcm.Length/2}else{0};
        Meaning='Offline PowerShell event collection, current-position spatialization and PCM mixing for the ordinary-input E1M1/intermission/E1M2 route. No live device, audio/video synchronization, music, randomized pitch or vanilla mixer equivalence is claimed. Per-block timing excludes gameplay and file writing.'}|ConvertTo-Json -Depth 9|Set-Content $Output
    if($content){$content.Dispose()}
}
"PASS: $($eventsLog.Count) sound events, $($comparison.Checked) checkpoints. Wave: $wav"
