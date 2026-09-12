# SPDX-License-Identifier: GPL-2.0-or-later
# Reader for a locally trusted qualification report; reports are evidence, not signatures.
function Open-DoomMusicLoopReader {
    param([string]$Report)
    if(-not [BitConverter]::IsLittleEndian){throw 'Music loop payloads require little endian float64.'}
    if(([IO.FileInfo]::new($Report)).Length -gt 16MB){throw 'Loop report exceeds size bound.'}
    $r=[IO.File]::ReadAllText($Report)|ConvertFrom-Json -AsHashtable;$d=$r.Details
    if($r.Error -or -not $d.Qualified -or -not $d.NormalizedStateRepeats -or -not $d.NextPeriodFloatOutputRepeats -or -not $d.Reference.Exact -or $d.SourcesChangedDuringRun.Count -ne 0 -or $d.PowerShell -cne $PSVersionTable.PSVersion.ToString()){throw 'Music loop has no current successful qualification.'}
    if($d.PeriodFrames -le 0 -or $d.PeriodFrames -gt 52920000 -or $d.PeriodFrames%1260 -ne 0 -or $d.LoopStartFrame -ne $d.PeriodFrames -or $d.LoopFrames -ne $d.PeriodFrames -or $d.Periods.Count -ne 3 -or $d.Snapshots.Count -ne 4){throw 'Unsupported music loop layout.'}
    if($d.Snapshots[1].StateSha256 -cne $d.Snapshots[2].StateSha256 -or $d.Snapshots[2].StateSha256 -cne $d.Snapshots[3].StateSha256 -or $d.Periods[1].Sha256 -cne $d.Periods[2].Sha256){throw 'Music loop evidence is inconsistent.'}
    $names='MusScore','SoundFontBank','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','MusicGroup','MusicLoopState'
    if($r.Sources.Count -ne $names.Count){throw 'Music loop source set differs.'}
    foreach($name in $names){
        $entry=@($r.Sources|Where-Object {$_.Path -ceq "src/$name.ps1"})
        if($entry.Count -ne 1 -or $entry[0].Sha256 -cne (Get-FileHash "$PSScriptRoot/$name.ps1").Hash){throw "Music loop source changed: $name"}
    }
    $handles=[Collections.Generic.List[object]]::new()
    try{
        for($i=0;$i -lt 3;$i++){
            $period=$d.Periods[$i]
            if($period.Index -ne $i -or $period.Frames -ne $d.PeriodFrames -or $period.Bytes -ne $d.PeriodFrames*16 -or $period.Sha256 -cnotmatch '^[0-9A-F]{64}$'){throw 'Invalid music loop payload metadata.'}
            # Keep playback files read-locked after hashing, so bytes cannot change underneath playback.
            $file=[IO.File]::Open($period.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$handles.Add($file)
            if($file.Length -ne $period.Bytes -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($file)) -cne $period.Sha256){throw 'Music loop payload checksum or length mismatch.'}
            $file.Position=0
        }
        $handles[2].Dispose();$handles.RemoveAt(2)
        return @{Files=$handles;Frame=0L;Paused=$false;Closed=$false;PeriodFrames=[long]$d.PeriodFrames;Loaded=$null;LoadedSegment=-1;LoadedFrame=-1L;DiskBytesRead=0L;ReportSha256=(Get-FileHash $Report).Hash;MusSha256=$d.MusSha256;BankSha256=$d.BankSha256}
    }catch{foreach($file in $handles){$file.Dispose()};throw}
}
function Close-DoomMusicLoopReader {
    param($Reader)
    if(-not $Reader.Closed){foreach($file in $Reader.Files){$file.Dispose()};$Reader.Loaded=$null;$Reader.Closed=$true}
}
function Read-DoomMusicLoop {
    param($Reader,[ValidateRange(1,44100)][int]$Frames)
    if($Reader.Closed){throw 'Music loop reader is closed.'}
    if($Reader.Frame -lt 0 -or $Reader.Frame -gt [long]::MaxValue-$Frames){throw 'Invalid music loop frame position.'}
    $mix=[double[]]::new($Frames*2);[long]$begin=$Reader.Frame
    if($Reader.Paused){return @{Frame=$begin;Frames=$Frames;Mix=$mix;Paused=$true}}
    [int]$copied=0
    while($copied -lt $Frames){
        [long]$absolute=$begin+$copied
        $segment=if($absolute -lt $Reader.PeriodFrames){0}else{1}
        [long]$position=if($segment -eq 0){$absolute}else{($absolute-$Reader.PeriodFrames)%$Reader.PeriodFrames}
        [long]$offset=0;[long]$page=[Math]::DivRem($position,25200L,[ref]$offset);[long]$pageFrame=$page*25200
        if($Reader.LoadedSegment -ne $segment -or $Reader.LoadedFrame -ne $pageFrame){
            [int]$count=[Math]::Min(25200,$Reader.PeriodFrames-$pageFrame);$bytes=[byte[]]::new($count*16)
            $file=$Reader.Files[$segment];$file.Position=$pageFrame*16;$file.ReadExactly($bytes)
            $samples=[double[]]::new($count*2);[Buffer]::BlockCopy($bytes,0,$samples,0,$bytes.Length)
            $Reader.Loaded=$samples;$Reader.LoadedSegment=$segment;$Reader.LoadedFrame=$pageFrame;$Reader.DiskBytesRead+=$bytes.Length
        }
        [int]$take=[Math]::Min($Frames-$copied,$Reader.Loaded.Length/2-$offset)
        [Array]::Copy($Reader.Loaded,$offset*2,$mix,$copied*2,$take*2);$copied+=$take
    }
    $Reader.Frame+=$Frames;return @{Frame=$begin;Frames=$Frames;Mix=$mix;Paused=$false}
}
