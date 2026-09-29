# SPDX-License-Identifier: GPL-2.0-or-later
# Reader for a locally trusted qualification report; reports are evidence, not signatures.
function Get-DoomMusicSourceHashes {
    param([Parameter(Mandatory)][string]$Path)
    $hashes=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [void]$hashes.Add((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash)
    # Git may check out identical PowerShell text with LF or CRLF endings. Accept those
    # canonical text forms while preserving every non-newline character in the comparison.
    $text=[IO.File]::ReadAllText($Path)
    $lf=[regex]::Replace($text,"`r`n|`r|`n","`n")
    $utf8=[Text.UTF8Encoding]::new($false)
    foreach($candidate in @($lf,$lf.Replace("`n","`r`n"))){
        [void]$hashes.Add([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($utf8.GetBytes($candidate))))
    }
    return ,$hashes
}
function Open-DoomMusicLoopReader {
    param([string]$Report,[switch]$MetadataOnly)
    if(-not [BitConverter]::IsLittleEndian){throw 'Music loop payloads require little endian float64.'}
    if(([IO.FileInfo]::new($Report)).Length -gt 16MB){throw 'Loop report exceeds size bound.'}
    $r=[IO.File]::ReadAllText($Report)|ConvertFrom-Json -AsHashtable
    if($r -isnot [Collections.IDictionary] -or -not $r.ContainsKey('Details') -or $r.Details -isnot [Collections.IDictionary]){
        throw "Music loop report '$Report' is missing its qualification details. Re-run scripts/Prepare-DoomMusic.ps1 and update the catalog entry."
    }
    $d=$r.Details
    $recordedPowerShell=if($d.ContainsKey('PowerShell')){[string]$d['PowerShell']}else{''}
    $qualifiedRuntime=$null
    $runtimeCompatible=[version]::TryParse($recordedPowerShell,[ref]$qualifiedRuntime)
    if($runtimeCompatible){$runtimeCompatible=$qualifiedRuntime.Major -eq $PSVersionTable.PSVersion.Major -and $qualifiedRuntime.Minor -eq $PSVersionTable.PSVersion.Minor}
    $rejectionReasons=[Collections.Generic.List[string]]::new()
    if($r.ContainsKey('Error') -and $r.Error){$rejectionReasons.Add("qualifier recorded an error: $($r.Error)")}
    if(-not $d.ContainsKey('Qualified')){$rejectionReasons.Add('report is missing its Qualified status')}
    elseif(-not $d.Qualified){$rejectionReasons.Add('report is marked unqualified')}
    if(-not $d.ContainsKey('NormalizedStateRepeats')){$rejectionReasons.Add('report is missing its loop-state recurrence result')}
    elseif(-not $d.NormalizedStateRepeats){$rejectionReasons.Add('normalized loop state did not repeat')}
    if(-not $d.ContainsKey('Reference') -or $d.Reference -isnot [Collections.IDictionary] -or -not $d.Reference.ContainsKey('Exact') -or -not $d.Reference.Exact){$rejectionReasons.Add('the independent reference comparison is not exact')}
    if(-not $d.ContainsKey('SourcesChangedDuringRun')){$rejectionReasons.Add('report is missing its source-stability result')}
    elseif(@($d.SourcesChangedDuringRun).Count -ne 0){$rejectionReasons.Add("$(@($d.SourcesChangedDuringRun).Count) synthesis source file(s) changed during qualification")}
    if(-not $d.ContainsKey('PowerShell')){$rejectionReasons.Add('report is missing its PowerShell runtime')}
    elseif(-not $runtimeCompatible){$rejectionReasons.Add("qualification uses PowerShell $recordedPowerShell; this runtime is $($PSVersionTable.PSVersion), and matching major/minor versions are required")}
    if($rejectionReasons.Count -gt 0){
        $trackName=if($d.ContainsKey('Track') -and $d.Track){[string]$d.Track}else{[IO.Path]::GetFileName($Report)}
        throw "Music loop qualification '$trackName' ($Report) is not usable: $($rejectionReasons -join '; '). Re-run scripts/Prepare-DoomMusic.ps1 for this track and update the catalog entry."
    }
    $mode=if($d.ContainsKey('EvidenceMode')){$d['EvidenceMode']}else{'IndependentStateAndOutput'} # Existing three-period receipt.
    if($d.PeriodFrames -le 0 -or $d.PeriodFrames -gt 52920000 -or $d.PeriodFrames%1260 -ne 0 -or $d.LoopStartFrame -ne $d.PeriodFrames -or $d.LoopFrames -ne $d.PeriodFrames){throw 'Unsupported music loop layout.'}
    if($mode -ceq 'CompleteStateRecurrence'){
        if($d.Periods.Count -ne 2 -or $d.Snapshots.Count -ne 3 -or $d.NextPeriodFloatOutputRepeats -ne $null -or $d.Snapshots[1].StateSha256 -cne $d.Snapshots[2].StateSha256){throw 'State-recurrence evidence is inconsistent.'}
    }elseif($mode -ceq 'IndependentStateAndOutput'){
        if($d.Periods.Count -ne 3 -or $d.Snapshots.Count -ne 4 -or -not $d.NextPeriodFloatOutputRepeats -or $d.Snapshots[1].StateSha256 -cne $d.Snapshots[2].StateSha256 -or $d.Snapshots[2].StateSha256 -cne $d.Snapshots[3].StateSha256 -or $d.Periods[1].Sha256 -cne $d.Periods[2].Sha256){throw 'Independent-output evidence is inconsistent.'}
    }else{throw 'Unsupported music loop evidence mode.'}
    $names='MusScore','SoundFontBank','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','MusicGroup','MusicLoopState'
    if($r.Sources.Count -ne $names.Count){throw 'Music loop source set differs.'}
    foreach($name in $names){
        $entry=@($r.Sources|Where-Object {$_.Path -ceq "src/$name.ps1"})
        if($entry.Count -ne 1 -or -not (Get-DoomMusicSourceHashes "$PSScriptRoot/$name.ps1").Contains([string]$entry[0].Sha256)){
            $trackName=if($d.ContainsKey('Track') -and $d.Track){[string]$d.Track}else{[IO.Path]::GetFileName($Report)}
            throw "Music loop qualification '$trackName' ($Report) is stale: synthesis source $name changed. Re-run scripts/Prepare-DoomMusic.ps1 for this track and update the catalog entry."
        }
    }
    $handles=[Collections.Generic.List[object]]::new()
    try{
        for($i=0;$i -lt $d.Periods.Count;$i++){
            $period=$d.Periods[$i]
            if($period.Index -ne $i -or $period.Frames -ne $d.PeriodFrames -or $period.Bytes -ne $d.PeriodFrames*16 -or $period.Sha256 -cnotmatch '^[0-9A-F]{64}$'){throw 'Invalid music loop payload metadata.'}
        }
        $playbackPeriods=if($mode -ceq 'IndependentStateAndOutput'){2}else{$d.Periods.Count}
        if($MetadataOnly){
            return @{MetadataOnly=$true;Files=[Collections.Generic.List[object]]::new();QualificationPeriods=$d.Periods.Count;PlaybackPeriods=$playbackPeriods;
                Frame=0L;Paused=$false;Closed=$true;PeriodFrames=[long]$d.PeriodFrames;Loaded=$null;LoadedSegment=-1;LoadedFrame=-1L;
                DiskBytesRead=0L;ReportSha256=(Get-FileHash $Report).Hash;Track=[string]$d.Track;MusSha256=$d.MusSha256;BankSha256=$d.BankSha256}
        }
        # IndependentStateAndOutput stores a third period as proof that the loop
        # repeats. Its hash must match the second period above, but playback uses
        # only the initial period and that verified repeating period. Avoid hashing
        # the redundant proof payload whenever a catalog opens.
        for($i=0;$i -lt $playbackPeriods;$i++){
            $period=$d.Periods[$i]
            # Keep playback files read-locked after hashing, so bytes cannot change underneath playback.
            $file=[IO.File]::Open($period.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);$handles.Add($file)
            if($file.Length -ne $period.Bytes -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($file)) -cne $period.Sha256){throw 'Music loop payload checksum or length mismatch.'}
            $file.Position=0
        }
        return @{Files=$handles;QualificationPeriods=$d.Periods.Count;PlaybackPeriods=$playbackPeriods;Frame=0L;Paused=$false;Closed=$false;PeriodFrames=[long]$d.PeriodFrames;Loaded=$null;LoadedSegment=-1;LoadedFrame=-1L;DiskBytesRead=0L;ReportSha256=(Get-FileHash $Report).Hash;MusSha256=$d.MusSha256;BankSha256=$d.BankSha256}
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
