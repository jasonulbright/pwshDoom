# SPDX-License-Identifier: GPL-2.0-or-later
# External recording: place unchanged captured PCM on the retained QPC timeline.
function New-DoomCaptureTimelinePlan {
    param([Parameter(Mandatory)]$Report,[Parameter(Mandatory)][decimal]$OriginQpc100ns,
        [ValidateRange(1,13230000)][int]$Frames)
    if($Report.Error -or $Report.Rate -ne 44100 -or $Report.Channels -ne 2 -or $Report.Bits -ne 16 -or -not $Report.Closed -or $Report.Packets.Count -eq 0){throw 'Expected a successful closed 44.1 kHz stereo PCM16 capture.'}
    $placements=[Collections.Generic.List[object]]::new();$gaps=[Collections.Generic.List[object]]::new();$adjustments=[Collections.Generic.List[object]]::new()
    [long]$sourceFrames=0;[long]$cursor=0;[decimal]$previousQpc=-1;$flagged=0;$copied=0L;$trimmed=0L
    for($i=0;$i -lt $Report.Packets.Count;$i++){
        $p=$Report.Packets[$i]
        if($p.Index -ne $i -or $p.OutputFrame -ne $sourceFrames -or $p.Frames -le 0 -or $p.Frames -gt 44100 -or [decimal]$p.Qpc100ns -le $previousQpc -or ($p.Flags -band 4)){throw 'Invalid packet sequence, size or capture timestamp.'}
        if($p.Flags -band 1){$flagged++}
        $sourceFrames+=$p.Frames;$previousQpc=[decimal]$p.Qpc100ns
        [long]$at=[Math]::Round(([decimal]$p.Qpc100ns-$OriginQpc100ns)*44100/10000000,0,[MidpointRounding]::AwayFromZero)
        [long]$skip=[Math]::Max(0,-$at);[long]$count=$p.Frames-$skip;$at=[Math]::Max(0,$at)
        if($count -le 0 -or $at -ge $Frames){$trimmed+=$p.Frames;continue}
        $count=[Math]::Min($count,$Frames-$at);$trimmed+=$p.Frames-$count
        if($at -lt $cursor){
            if($cursor-$at -gt 1){throw 'Capture packets overlap by more than one sample; no sample-dropping repair is authorized by this clock model.'}
            $adjustments.Add(@{Packet=$i;FromFrame=$at;ToFrame=$cursor;Reason='One-sample timestamp rounding tolerance'});$at=$cursor;$count=[Math]::Min($count,$Frames-$at)
        }
        if($at -gt $cursor){$gaps.Add(@{Frame=$cursor;Frames=$at-$cursor;NextPacket=$i})}
        if($count -gt 0){$placements.Add(@{Packet=$i;SourceFrame=$p.OutputFrame+$skip;OutputFrame=$at;Frames=$count});$copied+=$count;$cursor=$at+$count}
    }
    if($sourceFrames -ne $Report.Frames){throw 'Capture frame total differs from packets.'}
    if($cursor -lt $Frames){$gaps.Add(@{Frame=$cursor;Frames=$Frames-$cursor;NextPacket=$null})}
    return @{Frames=$Frames;OriginQpc100ns=$OriginQpc100ns;Placements=$placements.ToArray();ZeroFilledIntervals=$gaps.ToArray();TimestampAdjustments=$adjustments.ToArray();
        SourceFrames=$sourceFrames;CopiedFrames=$copied;ZeroFilledFrames=$Frames-$copied;TrimmedSourceFrames=$sourceFrames-$copied;ApiDiscontinuityPackets=$flagged;
        Meaning='PCM packets positioned by capture QPC with nearest-sample rounding, explicit zero-filled gaps and boundary trimming. Original capture stays unchanged. Zero-filled intervals are missing/outside capture coverage, not measured silence. More-than-one-sample overlap or timestamp-error flags fail.'}
}
function Write-DoomCaptureTimeline {
    param([Parameter(Mandatory)]$Report,[Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$OutputWav)
    if(Test-Path -LiteralPath $OutputWav){throw 'Use a fresh timeline WAV path.'}
    $inputFile=$null;$outputFile=$null;$writer=$null
    try{
        $inputFile=[IO.File]::Open($Report.WavPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($inputFile));$inputFile.Position=0
        if($hash -cne $Report.WavSha256 -or $inputFile.Length -ne 44+$Report.Frames*4){throw 'Capture WAV does not match its receipt.'}
        $header=[byte[]]::new(44);$inputFile.ReadExactly($header)
        if([Text.Encoding]::ASCII.GetString($header,0,4) -cne 'RIFF' -or [Text.Encoding]::ASCII.GetString($header,8,8) -cne 'WAVEfmt ' -or [BitConverter]::ToUInt32($header,16) -ne 16 -or [BitConverter]::ToUInt16($header,20) -ne 1 -or [BitConverter]::ToUInt16($header,22) -ne 2 -or [BitConverter]::ToUInt32($header,24) -ne 44100 -or [BitConverter]::ToUInt16($header,34) -ne 16 -or [Text.Encoding]::ASCII.GetString($header,36,4) -cne 'data'){throw 'Expected canonical capture WAV header.'}
        [Buffer]::BlockCopy([BitConverter]::GetBytes([uint32](36+$Plan.Frames*4)),0,$header,4,4);[Buffer]::BlockCopy([BitConverter]::GetBytes([uint32]($Plan.Frames*4)),0,$header,40,4)
        $outputFile=[IO.File]::Open($OutputWav,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$outputFile.Write($header)
        $zeros=[byte[]]::new(65536);$bytesLeft=[long]$Plan.Frames*4
        while($bytesLeft -gt 0){$count=[int][Math]::Min($bytesLeft,$zeros.Length);$outputFile.Write($zeros,0,$count);$bytesLeft-=$count}
        $buffer=[byte[]]::new(176400)
        foreach($p in $Plan.Placements){
            if($p.Frames -le 0 -or $p.Frames -gt 44100 -or $p.SourceFrame -lt 0 -or $p.SourceFrame+$p.Frames -gt $Report.Frames -or $p.OutputFrame -lt 0 -or $p.OutputFrame+$p.Frames -gt $Plan.Frames){throw 'Invalid timeline copy bounds.'}
            $inputFile.Position=44+$p.SourceFrame*4;$count=[int]$p.Frames*4;$inputFile.ReadExactly($buffer,0,$count)
            $outputFile.Position=44+$p.OutputFrame*4;$outputFile.Write($buffer,0,$count)
        }
        $outputFile.Flush($true)
    }finally{if($inputFile){$inputFile.Dispose()};if($outputFile){$outputFile.Dispose()}}
}
