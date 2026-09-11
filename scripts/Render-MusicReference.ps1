#requires -Version 7.6
# SPDX-License-Identifier: GPL-2.0-or-later
# COMPILED COMPARISON ONLY. Not loaded by the PowerShell game or music renderer.
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',[string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2",
    [string]$Library="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/External/MeltySynth.dll",[ValidatePattern('^D_[A-Z0-9]+$')][string]$Track='D_E1M1',[ValidateRange(1,300)][int]$Seconds=8,[ValidateRange(0,1)][double]$Volume=.2)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/music-reference-$PID.ps1";. $bundle
. "$PSScriptRoot/../src/MusScore.ps1";. "$PSScriptRoot/../src/AudioMixer.ps1"
$failure=$null;$archive=$null;$details=$null
try{
    $assembly=[Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($Library))
    $settings=[MeltySynth.SynthesizerSettings]::new(44100);$settings.BlockSize=32;$settings.MaximumPolyphony=256;$settings.EnableReverbAndChorus=$false
    $synth=[MeltySynth.Synthesizer]::new([IO.Path]::GetFullPath($SoundFont),$settings);$synth.MasterVolume=$Volume
    $archive=[Wad]::new([string[]]@($Wad));$score=ConvertFrom-DoomMus ($archive.ReadLump($archive.GetLumpNumber($Track))) -Name $Track;$timeline=New-DoomMusicTimeline $score -Loop
    $pcm=[int16[]]::new($Seconds*44100*2);$frame=0;$clipped=0;$peakVoices=0;$watch=[Diagnostics.Stopwatch]::StartNew()
    while($frame -lt $Seconds*44100){
        $count=[Math]::Min(1260,$Seconds*44100-$frame);$block=Read-DoomMusicFrames $timeline $count;$events=[Collections.Generic.List[object]]::new();foreach($e in $block.Events){$events.Add($e)}
        $events.Add([long[]]@(($block.Frame+$count),-1,0,0,0,0))
        foreach($e in $events){
            $span=[int]($e[0]-$frame)
            if($span -gt 0){
                $left=[single[]]::new($span);$right=[single[]]::new($span);$synth.Render($left,$right)
                for($i=0;$i -lt $span;$i++){foreach($side in 0,1){$sample=if($side -eq 0){$left[$i]*32768.0}else{$right[$i]*32768.0};if($sample -ge 32767.5){$sample=32767;$clipped++}elseif($sample -lt -32768.5){$sample=-32768;$clipped++};$pcm[2*($frame+$i)+$side]=[int16]$sample}}
                $frame+=$span;$peakVoices=[Math]::Max($peakVoices,$synth.ActiveVoiceCount)
            }
            $ch=[int]$e[2];if($ch -eq 15){$ch=9}elseif($ch -eq 9){$ch=15};$a=[int]$e[3];$b=[int]$e[4]
            switch([int]$e[1]){
                -1 {}
                0 {$synth.NoteOff($ch,$a)}
                1 {$synth.NoteOn($ch,$a,$b)}
                2 {$synth.ProcessMidiMessage($ch,0xe0,($a -band 127),($a -shr 7))}
                3 {$cc=([int[]]@(120,123,126,127,121))[$a-10];$synth.ProcessMidiMessage($ch,0xb0,$cc,0)}
                4 {if($a -eq 0){$synth.ProcessMidiMessage($ch,0xc0,$b,0)}else{$cc=([int[]]@(0,32,1,7,10,11,91,93,64,67))[$a];$synth.ProcessMidiMessage($ch,0xb0,$cc,$b)}}
                6 {$synth.NoteOffAll($false)}
            }
        }
    }
    $renderSeconds=$watch.Elapsed.TotalSeconds;$dir=Join-Path "$PSScriptRoot/../local" ('music-reference-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $dir|Out-Null
    $wave=[IO.Path]::GetFullPath((Join-Path $dir ($Track+'-meltysynth-dry.wav')));Write-DoomPcmWave $wave $pcm
    $peak=0;$sum=0.0;foreach($sample in $pcm){$peak=[Math]::Max($peak,[Math]::Abs([int]$sample));$sum+=[double]$sample*$sample}
    $details=@{WavPath=$wave;WavSha256=(Get-FileHash $wave).Hash;LibrarySha256=(Get-FileHash $Library).Hash;LibraryIdentity=$assembly.GetName().FullName;SoundFontSha256=(Get-FileHash $SoundFont).Hash;MusSha256=$score.SourceSha256;
        Track=$Track;Seconds=$Seconds;Frames=$frame;Volume=$Volume;RenderSeconds=$renderSeconds;PeakVoices=$peakVoices;ClippedSamples=$clipped;PeakPcm=$peak;RmsPcm=[Math]::Sqrt($sum/$pcm.Length);BlockFrames=32;Effects='Disabled';ReferenceOnly=$true}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($archive){$archive.Dispose()}
    @{Error=$failure;Details=$details;WadSha256=(Get-FileHash $Wad).Hash;Sources=@('src/MusScore.ps1','src/AudioMixer.ps1','scripts/Render-MusicReference.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
      Meaning='Separately labeled compiled MeltySynth reference using the same decoded score, bank, rate, volume and dry setting. Float precision, block event latency, envelopes, modulators and gain conventions can differ. Not the PowerShell implementation or its performance.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: compiled comparison written to $wave"
