#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',[string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2",
    [ValidatePattern('^D_[A-Z0-9]+$')][string]$Track='D_E1M1',[ValidateRange(1,300)][int]$Seconds=8,[ValidateRange(0,1)][double]$Volume=.2)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/music-render-$PID.ps1";. $bundle
foreach($name in 'MusScore','SoundFontBank','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','AudioMixer'){. "$PSScriptRoot/../src/$name.ps1"}
$failure=$null;$archive=$null;$details=$null;$times=[Collections.Generic.List[double]]::new()
try{
    $bank=ConvertTo-DoomSoundFontRegions (ConvertFrom-DoomSoundFont ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($SoundFont))))
    $archive=[Wad]::new([string[]]@($Wad));$score=ConvertFrom-DoomMus ($archive.ReadLump($archive.GetLumpNumber($Track))) -Name $Track
    $timeline=New-DoomMusicTimeline $score -Loop;$synth=New-DoomMusicSynth $bank;$synth.Volume=$Volume
    $samples=[int16[]]::new($Seconds*44100*2);$cursor=0;$watch=[Diagnostics.Stopwatch]::StartNew();$blockNumber=0
    while($synth.Frame -lt $Seconds*44100){
        $blockWatch=[Diagnostics.Stopwatch]::StartNew();$count=[Math]::Min(1260,$Seconds*44100-$synth.Frame);$block=Read-DoomMusicFrames $timeline $count
        foreach($event in $block.Events){
            $span=[int]($event[0]-$synth.Frame)
            if($span -gt 0){$pcm=ConvertTo-DoomMusicPcm $synth (Read-DoomMusicSynth $synth $span);$pcm.CopyTo($samples,$cursor);$cursor+=$pcm.Length}
            Invoke-DoomMusicEvent $synth $event
        }
        $span=[int]($block.Frame+$count-$synth.Frame)
        if($span -gt 0){$pcm=ConvertTo-DoomMusicPcm $synth (Read-DoomMusicSynth $synth $span);$pcm.CopyTo($samples,$cursor);$cursor+=$pcm.Length}
        $times.Add($blockWatch.Elapsed.TotalMilliseconds);$blockNumber++
        if($blockNumber%35 -eq 0){"Rendered $([Math]::Round($synth.Frame/44100.0,2))/$Seconds seconds; peak voices $($synth.PeakVoices)."}
    }
    $renderSeconds=$watch.Elapsed.TotalSeconds
    $dir=Join-Path "$PSScriptRoot/../local" ('music-render-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $dir|Out-Null
    $wave=[IO.Path]::GetFullPath((Join-Path $dir ($Track+'-dry.wav')));Write-DoomPcmWave $wave $samples
    $peak=0;$sum=0.0;$nonzero=0;foreach($sample in $samples){$peak=[Math]::Max($peak,[Math]::Abs([int]$sample));$sum+=[double]$sample*$sample;if($sample -ne 0){$nonzero++}}
    $details=@{WavPath=$wave;WavSha256=(Get-FileHash $wave).Hash;SoundFontSha256=$bank.SourceSha256;MusSha256=$score.SourceSha256;Track=$Track;Seconds=$Seconds;Frames=$synth.Frame;
        Volume=$Volume;RenderSeconds=$renderSeconds;AudioSecondsPerRenderSecond=$Seconds/$renderSeconds;PeakVoices=$synth.PeakVoices;NoteOns=$synth.NoteOns;ExclusiveCuts=$synth.ExclusiveCuts;
        ClippedSamples=$synth.ClippedSamples;PeakPcm=$peak;RmsPcm=[Math]::Sqrt($sum/$samples.Length);NonzeroSamples=$nonzero;ReverbVoices=$synth.NonzeroReverbVoices;ChorusVoices=$synth.NonzeroChorusVoices;
        MillisecondsPerBlock=$times.ToArray();Effects='Dry: chorus and reverb sends evaluated but not mixed';ControlFrames=32}
    if($cursor -ne $samples.Length -or $nonzero -eq 0){throw 'Incomplete or silent score render.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($archive){$archive.Dispose()}
    @{Error=$failure;Details=$details;WadSha256=(Get-FileHash $Wad).Hash;Sources=@('src/MusScore.ps1','src/SoundFontBank.ps1','src/SoundFontRegions.ps1','src/MusicOscillator.ps1','src/MusicControls.ps1','src/MusicSynth.ps1','src/AudioMixer.ps1','scripts/Render-MusicScore.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
      Meaning='Offline PowerShell dry-score render with all selected layers. Source decoding, bank preparation, output hashing and file writes excluded from render timing. No actual playback, live deadline, effects or reference-fidelity qualification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $Track dry music rendered to $wave"
