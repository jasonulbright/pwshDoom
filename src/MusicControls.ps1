# SPDX-License-Identifier: GPL-2.0-or-later
# Original PowerShell control math. SF2 units and defaults are documented in docs/music.md.
function New-DoomMusicChannel {
    $cc=[int[]]::new(128);$cc[7]=100;$cc[10]=64;$cc[11]=127;$cc[91]=40
    return @{CC=$cc;Program=0;Bend=8192;BendRange=2.0;Pressure=0;PolyPressure=[int[]]::new(128);Revision=0;Mono=$false}
}
function Get-DoomMusicModSource {
    param([int]$Source,$Channel,[int]$Key,[int]$Velocity)
    if($Source -eq 0){return 1.0}
    $index=$Source -band 127;$curve=$Source -shr 10;$negative=($Source -band 256) -ne 0;$bipolar=($Source -band 512) -ne 0
    if($curve -gt 3){throw 'Unsupported linked/reserved SF2 modulator source.'}
    $maximum=127.0;$center=64.0
    if($Source -band 128){$raw=$Channel.CC[$index]}
    else{
        switch($index){2 {$raw=$Velocity};3 {$raw=$Key};10 {$raw=$Channel.PolyPressure[$Key]};13 {$raw=$Channel.Pressure};14 {$raw=$Channel.Bend;$maximum=16383.0;$center=8192.0};16 {$raw=$Channel.BendRange};default {throw "Unsupported SF2 general modulator source $index."}}
    }
    if($bipolar){$x=[Math]::Clamp($raw/$center-1,-1.0,1.0);if($negative){$x=-$x};$sign=[Math]::Sign($x);$x=[Math]::Abs($x)}
    else{$x=[Math]::Clamp($raw/$maximum,0.0,1.0);if($negative){$x=1-$x};$sign=1}
    switch($curve){
        0 {$value=$x}
        1 {$value=if($x -ge 1){1.0}else{[Math]::Clamp(-40.0/96*[Math]::Log10(1-$x),0.0,1.0)}}
        2 {$value=if($x -le 0){0.0}else{1-[Math]::Clamp(-40.0/96*[Math]::Log10($x),0.0,1.0)}}
        3 {if($bipolar -and $sign -eq 0){$sign=1};$value=if($bipolar -or $x -ge .5){1.0}else{0.0}}
    }
    return [double]($sign*$value)
}
function Get-DoomMusicModulators {
    param($Region)
    # Correct CC7 index and conventional centered-pan amount resolve typos in
    # the old specification table. Velocity/filter uses its SF2.04 definition.
    $defaults=@([int[]]@(0x0502,48,960,0,0),[int[]]@(0x0102,8,-2400,0,0),[int[]]@(13,6,50,0,0),[int[]]@(129,6,50,0,0),
        [int[]]@(0x0587,48,960,0,0),[int[]]@(0x028a,17,500,0,0),[int[]]@(0x058b,48,960,0,0),[int[]]@(219,16,200,0,0),[int[]]@(221,15,200,0,0),[int[]]@(0x020e,52,12700,16,0))
    $mods=@{};foreach($m in $defaults){$mods[('{0}:{1}:{2}' -f $m[0],$m[1],$m[3])]=$m}
    foreach($m in $Region.InstrumentModulators){$mods[('{0}:{1}:{2}' -f $m[0],$m[1],$m[3])]=$m}
    $result=[Collections.Generic.List[object]]::new();foreach($key in ($mods.Keys|Sort-Object)){$result.Add($mods[$key])}
    foreach($m in $Region.PresetModulators){$result.Add($m)}
    return ,$result.ToArray()
}
function Get-DoomMusicGenerators {
    param($Region,$Modulators,$Channel,[int]$Key,[int]$Velocity)
    $values=[double[]]::new(61);for($i=0;$i -lt 61;$i++){$values[$i]=$Region.Values[$i]}
    foreach($m in $Modulators){
        if($m[2] -eq 0){continue}
        if($m[1] -notin 5,6,7,8,9,10,11,13,15,16,17,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,48,51,52,56){throw "Unsupported SF2 modulation destination $($m[1])."}
        $value=(Get-DoomMusicModSource $m[0] $Channel $Key $Velocity)*(Get-DoomMusicModSource $m[3] $Channel $Key $Velocity)*$m[2]
        if($m[4] -eq 2){$value=[Math]::Abs($value)}elseif($m[4] -ne 0){throw 'Unsupported SF2 modulator transform.'}
        $values[$m[1]]+=$value
    }
    return ,$values
}
function Convert-DoomMusicTimecents {
    param([double]$Value,[double]$Maximum=8000)
    if($Value -le -32768){return 0.0}
    return [Math]::Pow(2,[Math]::Clamp($Value,-12000.0,$Maximum)/1200)
}
function New-DoomMusicEnvelope {
    param([double[]]$Values,[int]$Key,[switch]$Modulation)
    $base=if($Modulation){25}else{33}
    $hold=$Values[$base+2];if($hold -gt -32768){$hold+=$Values[$base+6]*(60-$Key)}
    $decay=$Values[$base+3];if($decay -gt -32768){$decay+=$Values[$base+7]*(60-$Key)}
    $sustain=if($Modulation){1-[Math]::Clamp($Values[29]/1000,0.0,1.0)}else{[Math]::Pow(10,-[Math]::Clamp($Values[37],0.0,1440.0)/200)}
    return @{Delay=(Convert-DoomMusicTimecents $Values[$base] 5000);Attack=(Convert-DoomMusicTimecents $Values[$base+1]);Hold=(Convert-DoomMusicTimecents $hold 5000);
        Decay=(Convert-DoomMusicTimecents $decay);Sustain=$sustain;Release=(Convert-DoomMusicTimecents $Values[$base+5]);Modulation=[bool]$Modulation;ReleaseTime=-1.0;ReleaseValue=0.0}
}
function Get-DoomMusicEnvelopeValue {
    param($Envelope,[double]$Time)
    if($Envelope.ReleaseTime -ge 0 -and $Time -ge $Envelope.ReleaseTime){
        $t=$Time-$Envelope.ReleaseTime
        if($Envelope.Release -le 0 -or $t -ge $Envelope.Release){return 0.0}
        if($Envelope.Modulation){return [Math]::Max(0.0,$Envelope.ReleaseValue*(1-$t/$Envelope.Release))}
        return [double]($Envelope.ReleaseValue*[Math]::Pow(10,-4.8*$t/$Envelope.Release))
    }
    $t=$Time-$Envelope.Delay;if($t -lt 0){return 0.0}
    if($t -lt $Envelope.Attack){return [double]($t/$Envelope.Attack)}
    $t-=$Envelope.Attack;if($t -lt $Envelope.Hold){return 1.0};$t-=$Envelope.Hold
    if($Envelope.Decay -le 0){return [double]$Envelope.Sustain}
    if($Envelope.Modulation){return [Math]::Max($Envelope.Sustain,1-$t/$Envelope.Decay)}
    return [Math]::Max($Envelope.Sustain,[Math]::Pow(10,-4.8*$t/$Envelope.Decay))
}
function Get-DoomMusicLfo {
    param([double]$Time,[double]$Delay,[double]$Frequency)
    if($Time -lt $Delay){return 0.0}
    $phase=(($Time-$Delay)*$Frequency)%1
    if($phase -lt .25){return [double](4*$phase)}
    if($phase -lt .75){return [double](2-4*$phase)}
    return [double](4*$phase-4)
}
function Get-DoomMusicLowPass {
    param([double]$Frequency,[double]$Q,[int]$Rate)
    # Standard normalized two-pole low-pass (RBJ bilinear-transform form).
    $w=2*[Math]::PI*[Math]::Clamp($Frequency,5.0,.49*$Rate)/$Rate;$cos=[Math]::Cos($w);$alpha=[Math]::Sin($w)/(2*[Math]::Clamp($Q,.70710678,100.0));$a=1+$alpha
    return ,([double[]]@(((1-$cos)/2/$a),((1-$cos)/$a),((1-$cos)/2/$a),(-2*$cos/$a),((1-$alpha)/$a)))
}
