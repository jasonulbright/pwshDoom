# SPDX-License-Identifier: GPL-2.0-or-later
# Original PowerShell SF2 zone resolution. Modulators are retained for synthesis.
function Get-DoomSfZones {
    param($Tables,[ValidateSet('p','i')][string]$Level,[int]$Header,$Stats)
    $headers=if($Level -eq 'p'){$Tables.phdr}else{$Tables.inst}
    $bags=$Tables[$Level+'bag'];$generators=$Tables[$Level+'gen'];$modulators=$Tables[$Level+'mod']
    $reference=if($Level -eq 'p'){41}else{53};$globalGenerators=@{};$globalModulators=@{};$zones=[Collections.Generic.List[object]]::new()
    $begin=$headers[$Header].Bag;$end=$headers[$Header+1].Bag
    for($bag=$begin;$bag -lt $end;$bag++){
        $g=@{};$m=@{};$target=-1;$first=$bags[$bag][0]
        for($n=$first;$n -lt $bags[$bag+1][0];$n++){
            [int]$op=$generators[$n][0];[int]$raw=$generators[$n][1]
            if($op -eq $reference){$target=$raw;break}
            if($op -in 14,18,19,20,42,49,55,59,60 -or $op -gt 60 -or ($Level -eq 'p' -and $op -in 0,1,2,3,4,12,45,46,47,50,53,54,57,58) -or ($Level -eq 'i' -and $op -eq 41)){$Stats.IgnoredGenerators++;continue}
            if(($op -eq 43 -and $n -ne $first) -or ($op -eq 44 -and ($n -gt $first+1 -or ($n -eq $first+1 -and $generators[$first][0] -ne 43)))){$Stats.IgnoredGenerators++;continue}
            $value=$raw;if($op -notin 43,44,54,57 -and $raw -ge 32768){$value-=65536};$g[$op]=$value
        }
        for($n=$bags[$bag][1];$n -lt $bags[$bag+1][1];$n++){
            $mod=$modulators[$n];$identity='{0}:{1}:{2}' -f $mod[0],$mod[1],$mod[3];$m[$identity]=$mod.Clone()
        }
        if($target -lt 0){
            if($bag -eq $begin){$globalGenerators=$g;$globalModulators=$m}else{$Stats.IgnoredZones++};continue
        }
        $merged=$globalGenerators.Clone();foreach($op in $g.Keys){$merged[$op]=$g[$op]}
        $mergedMods=$globalModulators.Clone();foreach($identity in $m.Keys){$mergedMods[$identity]=$m[$identity]}
        $zones.Add(@{Target=$target;Generators=$merged;Modulators=@($mergedMods.Keys|Sort-Object|ForEach-Object {,$mergedMods[$_]})})
    }
    return ,$zones.ToArray()
}
function ConvertTo-DoomSoundFontRegions {
    param($Bank,[ValidateRange(1,100000)][int]$MaxRegions=100000)
    $stats=@{IgnoredGenerators=0;IgnoredZones=0;EmptyIntersections=0;Regions=0;DuplicatePresets=0};$t=$Bank.Tables
    $instruments=[object[]]::new($t.inst.Count-1)
    for($i=0;$i -lt $instruments.Length;$i++){$instruments[$i]=Get-DoomSfZones $t i $i $stats}
    $defaults=[int[]]::new(61);$defaults[8]=13500;$defaults[43]=32512;$defaults[44]=32512;$defaults[46]=-1;$defaults[47]=-1;$defaults[58]=-1;$defaults[56]=100
    foreach($op in 21,23,25,26,27,28,30,33,34,35,36,38){$defaults[$op]=-12000}
    $presets=@{}
    for($p=0;$p -lt $t.phdr.Count-1;$p++){
        $header=$t.phdr[$p];$key='{0}:{1}' -f $header.Bank,$header.Program
        if($presets.ContainsKey($key)){$stats.DuplicatePresets++;continue}
        $regions=[Collections.Generic.List[object]]::new();$presetZones=Get-DoomSfZones $t p $p $stats
        foreach($pz in $presetZones){foreach($iz in $instruments[$pz.Target]){
            $values=$defaults.Clone();foreach($op in $iz.Generators.Keys){$values[$op]=$iz.Generators[$op]}
            $keyLow=$values[43] -band 255;$keyHigh=$values[43] -shr 8;$velLow=$values[44] -band 255;$velHigh=$values[44] -shr 8
            foreach($op in $pz.Generators.Keys){
                $value=$pz.Generators[$op]
                if($op -eq 43){$keyLow=[Math]::Max($keyLow,$value -band 255);$keyHigh=[Math]::Min($keyHigh,$value -shr 8)}
                elseif($op -eq 44){$velLow=[Math]::Max($velLow,$value -band 255);$velHigh=[Math]::Min($velHigh,$value -shr 8)}
                else{$values[$op]+=$value}
            }
            if($keyLow -gt $keyHigh -or $velLow -gt $velHigh -or $keyLow -gt 127 -or $velLow -gt 127){$stats.EmptyIntersections++;continue}
            $keyHigh=[Math]::Min(127,$keyHigh);$velHigh=[Math]::Min(127,$velHigh)
            $sample=$t.shdr[$iz.Target]
            [long]$start=$sample.Start+[long]$values[0]+32768L*$values[4];[long]$end=$sample.End+[long]$values[1]+32768L*$values[12]
            [long]$loopStart=$sample.LoopStart+[long]$values[2]+32768L*$values[45];[long]$loopEnd=$sample.LoopEnd+[long]$values[3]+32768L*$values[50]
            [int]$mode=$values[54] -band 3
            if($start -lt 0 -or $end -gt $Bank.Samples.Length -or $start -ge $end){throw "Effective sample bounds invalid in preset $key sample $($iz.Target)."}
            if($mode -in 1,3 -and ($loopStart -lt $start -or $loopEnd -gt $end -or $loopStart -ge $loopEnd)){throw "Effective loop bounds invalid in preset $key sample $($iz.Target)."}
            if($mode -eq 2){$mode=0}
            $root=$values[58];if($root -lt 0 -or $root -gt 127){$root=$sample.RootKey};if($root -gt 127){$root=60}
            $regions.Add(@{SampleId=$iz.Target;Sample=$sample;Start=$start;End=$end;LoopStart=$loopStart;LoopEnd=$loopEnd;LoopMode=$mode;
                KeyLow=$keyLow;KeyHigh=$keyHigh;VelocityLow=$velLow;VelocityHigh=$velHigh;RootKey=$root;Values=$values;
                InstrumentModulators=$iz.Modulators;PresetModulators=$pz.Modulators})
            $stats.Regions++;if($stats.Regions -gt $MaxRegions){throw 'SF2 expanded region limit exceeded.'}
        }}
        $presets[$key]=@{Name=$header.Name;Regions=$regions.ToArray()}
    }
    return @{Samples=$Bank.Samples;Presets=$presets;Stats=$stats;SourceSha256=$Bank.SourceSha256}
}
function Find-DoomSoundFontRegions {
    param($SoundBank,[ValidateRange(0,16383)][int]$BankNumber=0,[ValidateRange(0,127)][int]$Program=0,[ValidateRange(0,127)][int]$Key=60,[ValidateRange(0,127)][int]$Velocity=100)
    $presetKey='{0}:{1}' -f $BankNumber,$Program
    if(-not $SoundBank.Presets.ContainsKey($presetKey)){throw "Missing SF2 preset $presetKey."}
    $matches=[Collections.Generic.List[object]]::new()
    foreach($region in $SoundBank.Presets[$presetKey].Regions){if($Key -ge $region.KeyLow -and $Key -le $region.KeyHigh -and $Velocity -ge $region.VelocityLow -and $Velocity -le $region.VelocityHigh){$matches.Add($region)}}
    return ,$matches.ToArray()
}
