# SPDX-License-Identifier: GPL-2.0-or-later
# Original PowerShell reader for the 16-bit, in-file-sample subset of SF2.
# Structural decoding only: generators/modulators are retained, not synthesized.
function Read-DoomRiffChunks {
    param([byte[]]$Data,[int]$Start,[int]$End)
    if($Start -lt 0 -or $End -lt $Start -or $End -gt $Data.Length){throw 'Invalid RIFF container bounds.'}
    $chunks=[Collections.Generic.List[object]]::new();[long]$offset=$Start
    while($offset -lt $End){
        if($End-$offset -lt 8){throw 'Truncated RIFF chunk header.'}
        $id=[Text.Encoding]::ASCII.GetString($Data,[int]$offset,4)
        [long]$size=[BitConverter]::ToUInt32($Data,[int]$offset+4)
        [long]$next=$offset+8+$size+($size%2)
        if($next -gt $End){throw "RIFF chunk $id exceeds its container."}
        $chunks.Add(@{Id=$id;Offset=[int]($offset+8);Size=[int]$size});$offset=$next
    }
    return ,$chunks.ToArray()
}
function ConvertFrom-DoomSoundFont {
    param([Parameter(Mandatory)][byte[]]$Data)
    if(-not [BitConverter]::IsLittleEndian){throw 'SF2 bulk sample decoding requires little-endian .NET.'}
    if($Data.Length -lt 12 -or $Data.Length -gt 128MB -or [Text.Encoding]::ASCII.GetString($Data,0,4) -cne 'RIFF' -or [Text.Encoding]::ASCII.GetString($Data,8,4) -cne 'sfbk'){
        throw 'Invalid SF2 signature or unsupported size (maximum 128 MiB).'
    }
    if([long][BitConverter]::ToUInt32($Data,4)+8 -ne $Data.Length){throw 'SF2 RIFF length must match the file.'}
    $lists=@{}
    foreach($chunk in (Read-DoomRiffChunks $Data 12 $Data.Length)){
        if($chunk.Id -cne 'LIST' -or $chunk.Size -lt 4){throw 'SF2 requires top-level LIST chunks.'}
        $name=[Text.Encoding]::ASCII.GetString($Data,$chunk.Offset,4)
        if($lists.ContainsKey($name)){throw "Duplicate SF2 list $name."}
        $children=@{}
        foreach($child in (Read-DoomRiffChunks $Data ($chunk.Offset+4) ($chunk.Offset+$chunk.Size))){
            if($children.ContainsKey($child.Id)){throw "Duplicate SF2 chunk $name/$($child.Id)."};$children[$child.Id]=$child
        }
        $lists[$name]=$children
    }
    foreach($name in 'INFO','sdta','pdta'){if(-not $lists.ContainsKey($name)){throw "Missing SF2 list $name."}}
    $info=@{};$infoChunks=$lists.INFO
    if(-not $infoChunks.ContainsKey('ifil') -or $infoChunks.ifil.Size -ne 4){throw 'Missing or invalid SF2 version.'}
    $version=@([int][BitConverter]::ToUInt16($Data,$infoChunks.ifil.Offset),[int][BitConverter]::ToUInt16($Data,$infoChunks.ifil.Offset+2))
    if($version[0] -ne 2 -or $version[1] -gt 4){throw 'Only SF2 versions 2.00 through 2.04 are supported.'}
    foreach($name in 'isng','INAM','irom','ICRD','IENG','IPRD','ICOP','ICMT','ISFT'){
        if($infoChunks.ContainsKey($name)){$c=$infoChunks[$name];$info[$name]=[Text.Encoding]::ASCII.GetString($Data,$c.Offset,$c.Size).TrimEnd([char]0)}
    }
    if(-not $lists.sdta.ContainsKey('smpl') -or $lists.sdta.smpl.Size%2){throw 'Missing or odd-length SF2 sample data.'}
    if($lists.sdta.ContainsKey('sm24')){throw '24-bit SF2 sample extensions are not yet supported.'}
    $sampleChunk=$lists.sdta.smpl;[int]$sampleCount=$sampleChunk.Size/2
    $sizes=@{phdr=38;pbag=4;pmod=10;pgen=4;inst=22;ibag=4;imod=10;igen=4;shdr=46};$tables=@{}
    foreach($name in 'phdr','pbag','pmod','pgen','inst','ibag','imod','igen','shdr'){
        if(-not $lists.pdta.ContainsKey($name)){throw "Missing SF2 table $name."}
        $c=$lists.pdta[$name];$stride=$sizes[$name]
        if($c.Size -lt $stride -or $c.Size%$stride){throw "Invalid SF2 table size $name."}
        $rows=[Collections.Generic.List[object]]::new()
        for($o=$c.Offset;$o -lt $c.Offset+$c.Size;$o+=$stride){
            switch($name){
                phdr {$rows.Add(@{Name=[Text.Encoding]::ASCII.GetString($Data,$o,20).TrimEnd([char]0);Program=[int][BitConverter]::ToUInt16($Data,$o+20);Bank=[int][BitConverter]::ToUInt16($Data,$o+22);Bag=[int][BitConverter]::ToUInt16($Data,$o+24)})}
                inst {$rows.Add(@{Name=[Text.Encoding]::ASCII.GetString($Data,$o,20).TrimEnd([char]0);Bag=[int][BitConverter]::ToUInt16($Data,$o+20)})}
                shdr {
                    $correction=[int]$Data[$o+41];if($correction -ge 128){$correction-=256}
                    $rows.Add(@{Name=[Text.Encoding]::ASCII.GetString($Data,$o,20).TrimEnd([char]0);Start=[long][BitConverter]::ToUInt32($Data,$o+20);End=[long][BitConverter]::ToUInt32($Data,$o+24);
                        LoopStart=[long][BitConverter]::ToUInt32($Data,$o+28);LoopEnd=[long][BitConverter]::ToUInt32($Data,$o+32);Rate=[long][BitConverter]::ToUInt32($Data,$o+36);
                        RootKey=[int]$Data[$o+40];Correction=$correction;Link=[int][BitConverter]::ToUInt16($Data,$o+42);Type=[int][BitConverter]::ToUInt16($Data,$o+44)})
                }
                {$_ -in 'pmod','imod'} {$rows.Add([int[]]@([BitConverter]::ToUInt16($Data,$o),[BitConverter]::ToUInt16($Data,$o+2),[BitConverter]::ToInt16($Data,$o+4),[BitConverter]::ToUInt16($Data,$o+6),[BitConverter]::ToUInt16($Data,$o+8)))}
                default {$rows.Add([int[]]@([BitConverter]::ToUInt16($Data,$o),[BitConverter]::ToUInt16($Data,$o+2)))}
            }
        }
        $tables[$name]=$rows.ToArray()
    }
    if($tables.phdr.Count -lt 2 -or $tables.inst.Count -lt 2 -or $tables.shdr.Count -lt 2){throw 'SF2 must include a preset, instrument and sample plus terminal records.'}
    foreach($level in 'p','i'){
        $headers=if($level -eq 'p'){$tables.phdr}else{$tables.inst}
        $bags=$tables[$level+'bag'];$gens=$tables[$level+'gen'];$mods=$tables[$level+'mod'];$previous=0
        foreach($header in $headers){if($header.Bag -lt $previous -or $header.Bag -ge $bags.Count){throw "Invalid SF2 $level header bag index."};$previous=$header.Bag}
        if($headers[0].Bag -ne 0 -or $headers[-1].Bag -ne $bags.Count-1){throw "Invalid SF2 $level header terminal index."}
        $previousGen=0;$previousMod=0
        foreach($bag in $bags){
            if($bag[0] -lt $previousGen -or $bag[0] -ge $gens.Count -or $bag[1] -lt $previousMod -or $bag[1] -ge $mods.Count){throw "Invalid SF2 $level bag generator/modulator index."}
            $previousGen=$bag[0];$previousMod=$bag[1]
        }
        if($bags[0][0] -ne 0 -or $bags[0][1] -ne 0 -or $bags[-1][0] -ne $gens.Count-1 -or $bags[-1][1] -ne $mods.Count-1){throw "Invalid SF2 $level bag terminal index."}
        $referenceOp=if($level -eq 'p'){41}else{53};$referenceCount=if($level -eq 'p'){$tables.inst.Count-1}else{$tables.shdr.Count-1}
        for($i=0;$i -lt $gens.Count-1;$i++){if($gens[$i][0] -eq $referenceOp -and $gens[$i][1] -ge $referenceCount){throw "Out-of-bounds SF2 $level generator reference."}}
    }
    for($i=0;$i -lt $tables.shdr.Count-1;$i++){
        $sample=$tables.shdr[$i]
        if($sample.Type -notin 1,2,4,8){throw 'ROM or unknown SF2 sample types are not supported.'}
        if($sample.Start -ge $sample.End -or $sample.End -gt $sampleCount -or $sample.LoopStart -lt $sample.Start -or $sample.LoopEnd -gt $sample.End -or $sample.LoopEnd -lt $sample.LoopStart -or $sample.Rate -le 0){throw "Invalid SF2 sample bounds/rate at $i."}
        if($sample.Type -ne 1 -and $sample.Link -ge $tables.shdr.Count-1){throw 'Invalid SF2 linked sample index.'}
    }
    $samples=[int16[]]::new($sampleCount);[Buffer]::BlockCopy($Data,$sampleChunk.Offset,$samples,0,$sampleChunk.Size)
    return @{Version=$version;Info=$info;Tables=$tables;Samples=$samples;SourceSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Data));
        Meaning='Structural SF2 decode only. Generator/modulator semantics, effective sample offsets and synthesis require subsequent validation.'}
}
