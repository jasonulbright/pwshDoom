# SPDX-License-Identifier: GPL-2.0-or-later
# DMX decoding, linear resampling, stereo gains and PCM mixing are PowerShell.
function ConvertFrom-DoomDmxSound {
    param([Parameter(Mandatory)][byte[]]$Data,[string]$Name='sound',[ValidateSet('Dmx','None')][string]$Padding='Dmx')
    if($Data.Length -lt 8 -or [BitConverter]::ToUInt16($Data,0) -ne 3){throw 'Unsupported DMX sound header.'}
    [int]$rate=[BitConverter]::ToUInt16($Data,2);[long]$count=[BitConverter]::ToUInt32($Data,4)
    if($rate -lt 1000 -or $rate -gt 48000 -or $count -gt $Data.Length-8 -or $count -le 0){throw 'Invalid DMX sample rate/count.'}
    [int]$offset=8
    if($Padding -eq 'Dmx'){if($count -le 48){throw 'DMX sound is below the supported minimum length.'};$offset+=16;$count-=32}
    [single[]]$samples=[single[]]::new([int]$count)
    for([int]$i=0;$i -lt $samples.Length;$i++){$samples[$i]=([int]$Data[$offset+$i]-128)*256}
    return @{Name=$Name;Rate=$rate;Samples=$samples;Padding=$Padding;SourceBytes=$Data.Length}
}
function Get-DoomStereoGains {
    param([double]$ListenerX,[double]$ListenerY,[double]$AngleRadians,[double]$SourceX,[double]$SourceY,[ValidateRange(0,1)][double]$Volume=1,[switch]$Local)
    if($Local){return @(($Volume*.5),($Volume*.5))}
    [double]$dx=$SourceX-$ListenerX;[double]$dy=$SourceY-$ListenerY
    [double]$distance=[Math]::Max([Math]::Abs($dx),[Math]::Abs($dy))+.5*[Math]::Min([Math]::Abs($dx),[Math]::Abs($dy))
    [double]$gain=$Volume*[Math]::Clamp((1200-$distance)/1040,0.0,1.0)
    [double]$pan=.75*[Math]::Sin([Math]::Atan2($dy,$dx)-$AngleRadians)
    return @(($gain*(1+$pan)*.5),($gain*(1-$pan)*.5))
}
function New-DoomAudioMixer {
    param([ValidateRange(8000,48000)][int]$Rate=44100,[ValidateRange(1,64)][int]$MaxVoices=16)
    return @{Rate=$Rate;MaxVoices=$MaxVoices;Voices=[Collections.Generic.List[object]]::new();Volume=1.0;Paused=$false;Frames=0L;ClippedSamples=0L;NextId=0L;ReplacedVoices=0}
}
function Add-DoomAudioVoice {
    param($Mixer,$Clip,[ValidateRange(0,1)][double]$Left=.5,[ValidateRange(0,1)][double]$Right=.5,[int]$Source=0,[int]$Group=0,[ValidateRange(.25,4)][double]$Pitch=1)
    if($Clip.Samples.Length -eq 0){throw 'Cannot play an empty sound.'}
    for($i=$Mixer.Voices.Count-1;$i -ge 0;$i--){if($Mixer.Voices[$i].Source -eq $Source -and $Mixer.Voices[$i].Group -eq $Group){$Mixer.Voices.RemoveAt($i);$Mixer.ReplacedVoices++}}
    if($Mixer.Voices.Count -ge $Mixer.MaxVoices){$Mixer.Voices.RemoveAt(0);$Mixer.ReplacedVoices++}
    $Mixer.NextId++
    $voice=@{Id=$Mixer.NextId;Clip=$Clip;Position=0.0;Step=$Clip.Rate*$Pitch/$Mixer.Rate;Left=$Left;Right=$Right;Source=$Source;Group=$Group}
    $Mixer.Voices.Add($voice);return $voice
}
function Remove-DoomAudioSource {
    param($Mixer,[int]$Source)
    for($i=$Mixer.Voices.Count-1;$i -ge 0;$i--){if($Mixer.Voices[$i].Source -eq $Source){$Mixer.Voices.RemoveAt($i)}}
}
function Read-DoomAudioFrames {
    param($Mixer,[ValidateRange(1,48000)][int]$Frames)
    [int16[]]$pcm=[int16[]]::new($Frames*2)
    if($Mixer.Paused){return ,$pcm}
    if($Mixer.Voices.Count -eq 0){$Mixer.Frames+=$Frames;return ,$pcm}
    [double[]]$mix=[double[]]::new($Frames*2)
    foreach($voice in $Mixer.Voices){
        [single[]]$samples=$voice.Clip.Samples;[double]$position=$voice.Position;[double]$step=$voice.Step
        [int]$sampleCount=$samples.Length;[int]$last=$sampleCount-1
        [double]$left=$voice.Left*$Mixer.Volume;[double]$right=$voice.Right*$Mixer.Volume
        for([int]$frame=0;$frame -lt $Frames -and $position -lt $sampleCount;$frame++){
            [int]$index=[Math]::Floor($position);[int]$next=$index+1;if($next -gt $last){$next=$last}
            [double]$sample=$samples[$index]+($samples[$next]-$samples[$index])*($position-$index)
            $mix[2*$frame]+=$sample*$left;$mix[2*$frame+1]+=$sample*$right;$position+=$step
        }
        $voice.Position=$position
    }
    for([int]$i=0;$i -lt $pcm.Length;$i++){
        # PowerShell's numeric cast rounds to even. Test the rounding boundaries
        # before casting: -32768.5 rounds to valid -32768, +32767.5 overflows.
        [double]$sample=$mix[$i]
        if($sample -ge 32767.5){$pcm[$i]=32767;$Mixer.ClippedSamples++}elseif($sample -lt -32768.5){$pcm[$i]=-32768;$Mixer.ClippedSamples++}else{$pcm[$i]=[int16]$sample}
    }
    for($i=$Mixer.Voices.Count-1;$i -ge 0;$i--){if($Mixer.Voices[$i].Position -ge $Mixer.Voices[$i].Clip.Samples.Length){$Mixer.Voices.RemoveAt($i)}}
    $Mixer.Frames+=$Frames;return ,$pcm
}
function Write-DoomPcmWave {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][int16[]]$Samples,[ValidateRange(8000,48000)][int]$Rate=44100)
    if($Samples.Length%2){throw 'Stereo PCM must contain complete frames.'}
    $stream=[IO.File]::Open([IO.Path]::GetFullPath($Path),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
    $writer=[IO.BinaryWriter]::new($stream)
    try{
        $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF'));$writer.Write([uint32](36+2*$Samples.Length));$writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
        $writer.Write([uint32]16);$writer.Write([uint16]1);$writer.Write([uint16]2);$writer.Write([uint32]$Rate);$writer.Write([uint32]($Rate*4));$writer.Write([uint16]4);$writer.Write([uint16]16)
        $writer.Write([Text.Encoding]::ASCII.GetBytes('data'));$writer.Write([uint32]($Samples.Length*2))
        $bytes=[byte[]]::new($Samples.Length*2);[Buffer]::BlockCopy($Samples,0,$bytes,0,$bytes.Length);$writer.Write($bytes)
    }finally{$writer.Dispose()}
}
