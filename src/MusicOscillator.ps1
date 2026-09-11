# SPDX-License-Identifier: GPL-2.0-or-later
# Original PowerShell linear sample oscillator; envelope/filter/modulators follow.
function New-DoomMusicOscillator {
    param($SoundBank,$Region,[ValidateRange(0,127)][int]$Key=60,[ValidateRange(8000,192000)][int]$Rate=44100,[ValidateRange(-12000,12000)][double]$BendCents=0)
    $effectiveKey=$Key;if($Region.Values[46] -ge 0 -and $Region.Values[46] -le 127){$effectiveKey=$Region.Values[46]}
    [double]$cents=($effectiveKey-$Region.RootKey)*$Region.Values[56]+100*$Region.Values[51]+$Region.Values[52]+$Region.Sample.Correction+$BendCents
    [double]$step=$Region.Sample.Rate/[double]$Rate*[Math]::Pow(2,$cents/1200)
    if(-not [double]::IsFinite($step) -or $step -le 0 -or $step -gt 1048576){throw 'Unsupported oscillator pitch/rate ratio.'}
    return @{Samples=$SoundBank.Samples;Region=$Region;Position=[double]$Region.Start;Step=$step;Released=$false;Paused=$false;Finished=$false;Frames=0L}
}
function Read-DoomMusicOscillator {
    param($Oscillator,[ValidateRange(1,192000)][int]$Frames)
    $output=[double[]]::new($Frames)
    if($Oscillator.Paused){return ,$output}
    if($Oscillator.Finished){$Oscillator.Frames+=$Frames;return ,$output}
    [int16[]]$samples=$Oscillator.Samples;$region=$Oscillator.Region
    [double]$position=$Oscillator.Position;[double]$step=$Oscillator.Step
    [int]$end=$region.End;[int]$loopEnd=$region.LoopEnd;[int]$loopStart=$region.LoopStart;[int]$loopLength=$loopEnd-$loopStart
    [bool]$loop=$region.LoopMode -eq 1 -or ($region.LoopMode -eq 3 -and -not $Oscillator.Released)
    for([int]$i=0;$i -lt $Frames;$i++){
        if($loop -and $position -ge $loopEnd){$position=$loopStart+($position-$loopStart)%$loopLength}
        if($position -ge $end){break}
        [int]$index=[Math]::Floor($position);[int]$next=$index+1
        if($loop -and $next -ge $loopEnd){$next=$loopStart}elseif($next -ge $end){$next=$end-1}
        $output[$i]=$samples[$index]+([int]$samples[$next]-[int]$samples[$index])*($position-$index)
        $position+=$step
    }
    $Oscillator.Position=$position;$Oscillator.Frames+=$Frames
    if(-not $loop -and $position -ge $end){$Oscillator.Finished=$true}
    return ,$output
}
