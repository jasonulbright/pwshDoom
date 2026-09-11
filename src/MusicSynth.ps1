# SPDX-License-Identifier: GPL-2.0-or-later
# Original PowerShell dry SF2 synthesizer. Playback/chorus/reverb are separate stages.
function New-DoomMusicSynth {
    param($SoundBank,[ValidateRange(8000,192000)][int]$Rate=44100,[ValidateRange(1,512)][int]$MaxVoices=256)
    return @{Bank=$SoundBank;Rate=$Rate;Channels=@(1..16|ForEach-Object {New-DoomMusicChannel});Voices=[Collections.Generic.List[object]]::new();Frame=0L;NextNote=0L;
        MaxVoices=$MaxVoices;PeakVoices=0;NoteOns=0;ExclusiveCuts=0;Paused=$false;Volume=.2;ClippedSamples=0L;EffectMode='Dry';NonzeroReverbVoices=0;NonzeroChorusVoices=0}
}
function Stop-DoomMusicVoice {
    param($Voice,[int]$Rate)
    if($Voice.Released){return}
    $time=$Voice.Frame/[double]$Rate
    foreach($env in @($Voice.VolumeEnvelope,$Voice.ModEnvelope)){$env.ReleaseValue=Get-DoomMusicEnvelopeValue $env $time;$env.ReleaseTime=$time}
    $Voice.Released=$true;$Voice.Oscillator.Released=$true;$Voice.ControlUntil=$Voice.Frame
}
function Invoke-DoomMusicEvent {
    param($Synth,[long[]]$Event)
    $kind=[int]$Event[1];$ch=[int]$Event[2];$a=[int]$Event[3];$b=[int]$Event[4];$channel=$Synth.Channels[$ch]
    if($kind -eq 6){foreach($v in $Synth.Voices){$v.KeyDown=$false;Stop-DoomMusicVoice $v $Synth.Rate};return}
    if($kind -eq 0 -or ($kind -eq 1 -and $b -eq 0)){
        foreach($v in $Synth.Voices){if($v.Channel -eq $ch -and $v.Key -eq $a -and $v.KeyDown){$v.KeyDown=$false;if($channel.CC[64] -lt 64){Stop-DoomMusicVoice $v $Synth.Rate}}};return
    }
    if($kind -eq 1){
        if($channel.CC[32] -ne 0){throw 'Nonzero MUS bank selection is not yet supported.'}
        $number=if($ch -eq 15){128}else{0};$regions=Find-DoomSoundFontRegions $Synth.Bank -BankNumber $number -Program $channel.Program -Key $a -Velocity $b
        if($regions.Count -eq 0){throw 'Note-on has no matching sample region.'}
        $classes=[Collections.Generic.HashSet[int]]::new();foreach($region in $regions){if($region.Values[57] -gt 0){$null=$classes.Add($region.Values[57])}}
        $cuts=[Collections.Generic.List[int]]::new()
        for($i=$Synth.Voices.Count-1;$i -ge 0;$i--){$old=$Synth.Voices[$i];if($old.Channel -eq $ch -and ($channel.Mono -or $classes.Contains($old.Exclusive))){$cuts.Add($i)}}
        if($Synth.Voices.Count-$cuts.Count+$regions.Count -gt $Synth.MaxVoices){throw 'Music voice limit reached; the complete note was rejected without changing voices.'}
        $noteId=$Synth.NextNote+1;$pending=[Collections.Generic.List[object]]::new();$reverbVoices=0;$chorusVoices=0
        foreach($region in $regions){
            $exclusive=$region.Values[57]
            $key=$a;if($region.Values[46] -ge 0 -and $region.Values[46] -le 127){$key=$region.Values[46]}
            $velocity=$b;if($region.Values[47] -ge 0 -and $region.Values[47] -le 127){$velocity=$region.Values[47]}
            $mods=Get-DoomMusicModulators $region;$g=Get-DoomMusicGenerators $region $mods $channel $key $velocity
            $voice=@{Channel=$ch;Key=$a;EffectiveKey=$key;Velocity=$velocity;NoteId=$noteId;Exclusive=$exclusive;KeyDown=$true;Released=$false;
                Region=$region;Modulators=$mods;Generators=$g;ChannelRevision=$channel.Revision;StaticControl=$null;LastCutoff=[double]::NaN;Frame=0L;ControlUntil=0L;ControlLeft=0.0;ControlRight=0.0;DeltaLeft=0.0;DeltaRight=0.0;
                VolumeEnvelope=(New-DoomMusicEnvelope $g $key);ModEnvelope=(New-DoomMusicEnvelope $g $key -Modulation);
                Oscillator=(New-DoomMusicOscillator $Synth.Bank $region -Key $a -Rate $Synth.Rate);Filter=[double[]]::new(5);X1=0.0;X2=0.0;Y1=0.0;Y2=0.0;Finished=$false}
            if($g[16] -gt 0){$reverbVoices++};if($g[15] -gt 0){$chorusVoices++};$pending.Add($voice)
        }
        # Publish only after every layer validates; rejected notes retain prior sound.
        foreach($index in $cuts){$Synth.Voices.RemoveAt($index)}
        foreach($voice in $pending){$Synth.Voices.Add($voice)}
        $Synth.NextNote=$noteId;$Synth.NoteOns++;$Synth.ExclusiveCuts+=$cuts.Count;$Synth.NonzeroReverbVoices+=$reverbVoices;$Synth.NonzeroChorusVoices+=$chorusVoices
        $Synth.PeakVoices=[Math]::Max($Synth.PeakVoices,$Synth.Voices.Count)
        return
    }
    if($kind -eq 2){$channel.Bend=$a;$channel.Revision++;return}
    if($kind -eq 3){
        switch($a){
            10 {for($i=$Synth.Voices.Count-1;$i -ge 0;$i--){if($Synth.Voices[$i].Channel -eq $ch){$Synth.Voices.RemoveAt($i)}}}
            11 {foreach($v in $Synth.Voices){if($v.Channel -eq $ch){$v.KeyDown=$false;if($channel.CC[64] -lt 64){Stop-DoomMusicVoice $v $Synth.Rate}}}}
            12 {$channel.Mono=$true}
            13 {$channel.Mono=$false}
            14 {$channel.Bend=8192;$channel.CC[1]=0;$channel.CC[11]=127;$channel.CC[64]=0;$channel.CC[67]=0;$channel.Pressure=0;[Array]::Clear($channel.PolyPressure);foreach($v in $Synth.Voices){if($v.Channel -eq $ch -and -not $v.KeyDown){Stop-DoomMusicVoice $v $Synth.Rate}}}
            default {throw 'Invalid MUS system event.'}
        }
        $channel.Revision++;return
    }
    if($kind -eq 4){
        if($a -eq 0){$channel.Program=$b;return}
        $mapping=[int[]]@(0,32,1,7,10,11,91,93,64,67);$cc=$mapping[$a];$channel.CC[$cc]=$b;$channel.Revision++
        if($cc -eq 64 -and $b -lt 64){foreach($v in $Synth.Voices){if($v.Channel -eq $ch -and -not $v.KeyDown){Stop-DoomMusicVoice $v $Synth.Rate}}};return
    }
    throw "Unsupported music event kind $kind."
}
function Update-DoomMusicVoiceControl {
    param($Voice,$Synth)
    $channel=$Synth.Channels[$Voice.Channel]
    if($Voice.ChannelRevision -ne $channel.Revision){$Voice.Generators=Get-DoomMusicGenerators $Voice.Region $Voice.Modulators $channel $Voice.EffectiveKey $Voice.Velocity;$Voice.ChannelRevision=$channel.Revision;$Voice.StaticControl=$null}
    $g=$Voice.Generators
    if($null -eq $Voice.StaticControl){
        $s=[double[]]::new(18)
        $s[0]=Convert-DoomMusicTimecents $g[21] 5000;$s[1]=8.176*[Math]::Pow(2,[Math]::Clamp($g[22],-16000.0,4500.0)/1200)
        $s[2]=Convert-DoomMusicTimecents $g[23] 5000;$s[3]=8.176*[Math]::Pow(2,[Math]::Clamp($g[24],-16000.0,4500.0)/1200)
        $s[4]=($Voice.EffectiveKey-$Voice.Region.RootKey)*[Math]::Clamp($g[56],0.0,1200.0)+100*[Math]::Clamp($g[51],-120.0,120.0)+$g[52]+$Voice.Region.Sample.Correction
        $s[5]=[int]($g[5] -ne 0 -or $g[6] -ne 0 -or $g[7] -ne 0)
        $s[6]=$Voice.Region.Sample.Rate/[double]$Synth.Rate*[Math]::Pow(2,[Math]::Clamp($s[4],-24000.0,24000.0)/1200)
        $s[7]=[int]($g[10] -ne 0 -or $g[11] -ne 0);$s[8]=[Math]::Pow(10,[Math]::Clamp($g[9],0.0,960.0)/200)/[Math]::Sqrt(2)
        $s[9]=8.176*[Math]::Pow(2,[Math]::Clamp($g[8],1500.0,13500.0)/1200)
        $angle=([Math]::Clamp($g[17],-500.0,500.0)+500)/1000*[Math]::PI/2;$s[10]=[Math]::Cos($angle);$s[11]=[Math]::Sin($angle)
        $s[12]=$g[48]+$g[9]/2;$s[13]=[int]($g[13] -ne 0);$s[14]=[Math]::Pow(10,-[Math]::Clamp($s[12],-960.0,2880.0)/200)
        $s[15]=[int]($g[5] -ne 0 -or $g[10] -ne 0 -or $g[13] -ne 0);$s[16]=[int]($g[6] -ne 0);$s[17]=[int]($g[7] -ne 0 -or $g[11] -ne 0)
        $Voice.StaticControl=$s;$Voice.LastCutoff=[double]::NaN
    }
    [double[]]$s=$Voice.StaticControl;[int]$span=32-[int]($Voice.Frame%32);$time=$Voice.Frame/[double]$Synth.Rate;$nextTime=($Voice.Frame+$span)/[double]$Synth.Rate
    $mod=0.0;$vib=0.0;$env=0.0
    if($s[15]){$mod=Get-DoomMusicLfo $time $s[0] $s[1]};if($s[16]){$vib=Get-DoomMusicLfo $time $s[2] $s[3]};if($s[17]){$env=Get-DoomMusicEnvelopeValue $Voice.ModEnvelope $time}
    if($s[5]){$pitch=$s[4]+$mod*$g[5]+$vib*$g[6]+$env*$g[7];$Voice.Oscillator.Step=$Voice.Region.Sample.Rate/[double]$Synth.Rate*[Math]::Pow(2,[Math]::Clamp($pitch,-24000.0,24000.0)/1200)}else{$Voice.Oscillator.Step=$s[6]}
    $cutoff=$s[9];if($s[7]){$cutoff=8.176*[Math]::Pow(2,[Math]::Clamp(($g[8]+$mod*$g[10]+$env*$g[11]),1500.0,13500.0)/1200)}
    if($cutoff -ne $Voice.LastCutoff){$Voice.Filter=Get-DoomMusicLowPass $cutoff $s[8] $Synth.Rate;$Voice.LastCutoff=$cutoff}
    $left=$s[10];$right=$s[11];$gain=$s[14];$gainNext=$gain
    if($s[13]){$gain=[Math]::Pow(10,-[Math]::Clamp(($s[12]+$mod*$g[13]),-960.0,2880.0)/200);$gainNext=[Math]::Pow(10,-[Math]::Clamp(($s[12]+(Get-DoomMusicLfo $nextTime $s[0] $s[1])*$g[13]),-960.0,2880.0)/200)}
    $gain*=Get-DoomMusicEnvelopeValue $Voice.VolumeEnvelope $time;$gainNext*=Get-DoomMusicEnvelopeValue $Voice.VolumeEnvelope $nextTime
    if($channel.CC[7] -eq 0 -or $channel.CC[11] -eq 0){$gain=0;$gainNext=0}
    $Voice.ControlLeft=$left*$gain;$Voice.ControlRight=$right*$gain;$Voice.DeltaLeft=$left*($gainNext-$gain)/$span;$Voice.DeltaRight=$right*($gainNext-$gain)/$span;$Voice.ControlUntil=$Voice.Frame+$span
}
function Add-DoomMusicVoiceFrames {
    param($Voice,$Synth,[double[]]$Mix,[int]$Frames)
    [int]$written=0
    while($written -lt $Frames -and -not $Voice.Finished){
        if($Voice.Frame -ge $Voice.ControlUntil -or $Voice.ChannelRevision -ne $Synth.Channels[$Voice.Channel].Revision){Update-DoomMusicVoiceControl $Voice $Synth}
        [int]$count=[Math]::Min($Frames-$written,$Voice.ControlUntil-$Voice.Frame)
        # Fuse sample interpolation with filtering; avoid a function and mono array per control interval.
        $osc=$Voice.Oscillator;[int16[]]$samples=$osc.Samples;$region=$osc.Region
        [double]$position=$osc.Position;[double]$step=$osc.Step
        [int]$end=$region.End;[int]$loopEnd=$region.LoopEnd;[int]$loopStart=$region.LoopStart;[int]$loopLength=$loopEnd-$loopStart
        [bool]$loop=$region.LoopMode -eq 1 -or ($region.LoopMode -eq 3 -and -not $osc.Released)
        [bool]$advancing=-not $osc.Paused -and -not $osc.Finished;$f=$Voice.Filter
        [double]$b0=$f[0];[double]$b1=$f[1];[double]$b2=$f[2];[double]$a1=$f[3];[double]$a2=$f[4]
        [double]$x1=$Voice.X1;[double]$x2=$Voice.X2;[double]$y1=$Voice.Y1;[double]$y2=$Voice.Y2
        [double]$left=$Voice.ControlLeft;[double]$right=$Voice.ControlRight;[double]$dl=$Voice.DeltaLeft;[double]$dr=$Voice.DeltaRight
        for($i=0;$i -lt $count;$i++){
            [double]$x=0
            if($advancing){
                if($loop -and $position -ge $loopEnd){$position=$loopStart+($position-$loopStart)%$loopLength}
                if($position -lt $end){
                    [int]$index=[Math]::Floor($position);[int]$next=$index+1
                    if($loop -and $next -ge $loopEnd){$next=$loopStart}elseif($next -ge $end){$next=$end-1}
                    $x=$samples[$index]+([int]$samples[$next]-[int]$samples[$index])*($position-$index);$position+=$step
                }else{$advancing=$false}
            }
            [double]$y=$b0*$x+$b1*$x1+$b2*$x2-$a1*$y1-$a2*$y2;$x2=$x1;$x1=$x;$y2=$y1;$y1=$y
            $Mix[2*($written+$i)]+=$left*$y;$Mix[2*($written+$i)+1]+=$right*$y;$left+=$dl;$right+=$dr
        }
        if(-not $osc.Paused){$osc.Position=$position;$osc.Frames+=$count;if(-not $loop -and $position -ge $end){$osc.Finished=$true}}
        $Voice.X1=$x1;$Voice.X2=$x2;$Voice.Y1=$y1;$Voice.Y2=$y2;$Voice.ControlLeft=$left;$Voice.ControlRight=$right;$Voice.Frame+=$count;$written+=$count
        $e=$Voice.VolumeEnvelope
        if($Voice.Oscillator.Finished -or ($Voice.Released -and $Voice.Frame/[double]$Synth.Rate -ge $e.ReleaseTime+$e.Release)){$Voice.Finished=$true}
    }
}
function Read-DoomMusicSynth {
    param($Synth,[ValidateRange(1,192000)][int]$Frames)
    $mix=[double[]]::new(2*$Frames);if($Synth.Paused){return ,$mix}
    foreach($voice in $Synth.Voices){Add-DoomMusicVoiceFrames $voice $Synth $mix $Frames}
    for($i=$Synth.Voices.Count-1;$i -ge 0;$i--){if($Synth.Voices[$i].Finished){$Synth.Voices.RemoveAt($i)}}
    $Synth.Frame+=$Frames;return ,$mix
}
function ConvertTo-DoomMusicPcm {
    param($Synth,[double[]]$Mix)
    $pcm=[int16[]]::new($Mix.Length);[double]$volume=$Synth.Volume
    for([int]$i=0;$i -lt $Mix.Length;$i++){
        [double]$value=$Mix[$i]*$volume;if(-not [double]::IsFinite($value)){throw 'Music synthesis produced nonfinite PCM.'}
        if($value -ge 32767.5){$pcm[$i]=32767;$Synth.ClippedSamples++}elseif($value -lt -32768.5){$pcm[$i]=-32768;$Synth.ClippedSamples++}else{$pcm[$i]=[int16]$value}
    }
    return ,$pcm
}
