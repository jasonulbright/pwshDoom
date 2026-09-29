# SPDX-License-Identifier: GPL-2.0-or-later
# Bounded paged reader for a locally trusted finite one-shot qualification.
function Open-DoomMusicOneShotReader {
    param([string]$Report,[switch]$MetadataOnly)
    if(-not [BitConverter]::IsLittleEndian){throw 'One-shot payloads require little endian float64.'}
    if(([IO.FileInfo]::new($Report)).Length -gt 16MB){throw 'One-shot report exceeds size bound.'}
    $r=[IO.File]::ReadAllText($Report)|ConvertFrom-Json -AsHashtable
    $d=$r.Details
    $qualifiedRuntime=$null
    $runtimeCompatible=[version]::TryParse([string]$d.PowerShell,[ref]$qualifiedRuntime)
    if($runtimeCompatible){$runtimeCompatible=$qualifiedRuntime.Major -eq $PSVersionTable.PSVersion.Major -and $qualifiedRuntime.Minor -eq $PSVersionTable.PSVersion.Minor}
    if($r.Error -or -not $d.Qualified -or $d.Mode -cne 'OneShot' -or
       $d.SourcesChangedDuringRun.Count -ne 0 -or -not $runtimeCompatible){
        throw "One-shot report has no current successful qualification for PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor).x."
    }
    [long]$maxFrames=44100L*600
    if($d.Frames -le 0 -or $d.Frames -gt $maxFrames -or $d.ScoreFrames -le 0 -or
       $d.ScoreFrames -gt $d.Frames -or $d.TailFrames -ne $d.Frames-$d.ScoreFrames -or
       $d.Payload.Frames -ne $d.Frames -or $d.Payload.Bytes -ne $d.Frames*16 -or
       $d.Payload.Sha256 -cnotmatch '^[0-9A-F]{64}$' -or
       $d.RepeatPayload.Sha256 -cne $d.Payload.Sha256 -or
       $d.RepeatPayload.Bytes -ne $d.Payload.Bytes -or
       $d.DeterministicFrames -ne $true -or $d.DeterministicPayload -ne $true){
        throw 'Unsupported one-shot payload layout.'
    }
    $names='MusScore','SoundFontBank','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth'
    if($r.Sources.Count -ne $names.Count+1){throw 'One-shot source set differs.'}
    foreach($name in $names){
        $entry=@($r.Sources|Where-Object {$_.Path -ceq "src/$name.ps1"})
        if($entry.Count -ne 1 -or $entry[0].Sha256 -cne (Get-FileHash "$PSScriptRoot/$name.ps1").Hash){throw "One-shot source changed: $name"}
    }
    $qualifier=@($r.Sources|Where-Object {$_.Path -ceq 'scripts/Qualify-MusicOneShot.ps1'})
    if($qualifier.Count -ne 1 -or $qualifier[0].Sha256 -cne (Get-FileHash "$PSScriptRoot/../scripts/Qualify-MusicOneShot.ps1").Hash){throw 'One-shot qualifier source changed.'}

    if($MetadataOnly){
        return @{OneShot=$true;MetadataOnly=$true;File=$null;Frame=0L;FrameCount=[long]$d.Frames;Loaded=$null;LoadedFrame=-1L;
            DiskBytesRead=0L;Finished=$false;Closed=$true;ReportSha256=(Get-FileHash $Report).Hash;Track=[string]$d.Track;
            MusSha256=$d.MusSha256;BankSha256=$d.SoundFontSha256}
    }
    $file=[IO.File]::Open($d.Payload.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        if($file.Length -ne $d.Payload.Bytes -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($file)) -cne $d.Payload.Sha256){throw 'One-shot payload checksum or length mismatch.'}
        $file.Position=0
        return @{
            OneShot=$true
            File=$file
            Frame=0L
            FrameCount=[long]$d.Frames
            Loaded=$null
            LoadedFrame=-1L
            DiskBytesRead=0L
            Finished=$false
            Closed=$false
            ReportSha256=(Get-FileHash $Report).Hash
            MusSha256=$d.MusSha256
            BankSha256=$d.SoundFontSha256
        }
    }catch{$file.Dispose();throw}
}

function Read-DoomMusicOneShot {
    param($Reader,[ValidateRange(1,44100)][int]$Frames)
    if($Reader.Closed){throw 'One-shot reader is closed.'}
    if($Reader.Frame -lt 0 -or $Reader.Frame -gt $Reader.FrameCount){throw 'Invalid one-shot frame position.'}
    [long]$begin=$Reader.Frame
    [double[]]$mix=[double[]]::new($Frames*2)
    [int]$remaining=[int][Math]::Min($Frames,$Reader.FrameCount-$Reader.Frame)
    [int]$copied=0
    while($copied -lt $remaining){
        [long]$absolute=$begin+$copied
        [long]$offset=0
        [long]$page=[Math]::DivRem($absolute,25200L,[ref]$offset)
        [long]$pageFrame=$page*25200
        if($Reader.LoadedFrame -ne $pageFrame){
            [int]$count=[int][Math]::Min(25200,$Reader.FrameCount-$pageFrame)
            [byte[]]$bytes=[byte[]]::new($count*16)
            $Reader.File.Position=$pageFrame*16
            $Reader.File.ReadExactly($bytes)
            $Reader.Loaded=[double[]]::new($count*2)
            [Buffer]::BlockCopy($bytes,0,$Reader.Loaded,0,$bytes.Length)
            $Reader.LoadedFrame=$pageFrame
            $Reader.DiskBytesRead+=$bytes.Length
        }
        [int]$take=[int][Math]::Min($remaining-$copied,$Reader.Loaded.Length/2-$offset)
        [Array]::Copy($Reader.Loaded,$offset*2,$mix,$copied*2,$take*2)
        $copied+=$take
    }
    $Reader.Frame+=$copied
    $Reader.Finished=$Reader.Frame -ge $Reader.FrameCount
    return @{Frame=$begin;Frames=$Frames;AvailableFrames=$copied;Mix=$mix;Finished=$Reader.Finished}
}

function Close-DoomMusicOneShotReader {
    param($Reader)
    if(-not $Reader.Closed){$Reader.File.Dispose();$Reader.Loaded=$null;$Reader.Closed=$true}
}
