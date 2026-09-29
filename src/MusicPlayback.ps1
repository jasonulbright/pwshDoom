# SPDX-License-Identifier: GPL-2.0-or-later
# Persistent catalog of qualified readers, owned only by the audio runspace.
function New-DoomMusicPlayback {
    param([hashtable]$Reports=@{})
    $state=@{Readers=@{};ReaderModes=@{};Reports=@{};Selected=$null;Gain=.2;Frames=0L;Transitions=[Collections.Generic.List[object]]::new();Closed=$false}
    $catalog=[Collections.Generic.List[object]]::new();$pool=$null;$jobs=[Collections.Generic.List[object]]::new();$failure=$null
    try{
        foreach($track in @($Reports.Keys|Sort-Object)){
            if($track -cnotmatch '^D_[A-Z0-9]+$'){throw 'Invalid music catalog track name.'}
            $path=[IO.Path]::GetFullPath([string]$Reports[$track])
            $r=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json -AsHashtable
            if($r.Details.Track -cne $track){throw 'Music catalog name does not match its qualification.'}
            $mode=if($r.Details.ContainsKey('Mode') -and $r.Details.Mode -ceq 'OneShot'){'OneShot'}else{'Loop'}
            $catalog.Add(@{Track=$track;Path=$path;Mode=$mode;ReportSha256=(Get-FileHash -LiteralPath $path).Hash})
            $state.Readers[$track]=$null;$state.ReaderModes[$track]=$mode
        }
        if($catalog.Count -gt 0){
            # Each reader verifies and locks its full playback payload. Open independent
            # tracks concurrently so startup does not hash several GiB on one thread.
            $readerModule=Join-Path $PSScriptRoot 'MusicLoopReader.ps1'
            $oneShotModule=Join-Path $PSScriptRoot 'MusicOneShotReader.ps1'
            $pool=[RunspaceFactory]::CreateRunspacePool(1,[Math]::Min(4,$catalog.Count));$pool.Open()
            foreach($entry in $catalog){
                $ps=[PowerShell]::Create();$ps.RunspacePool=$pool
                if($entry.Mode -ceq 'OneShot'){
                    $null=$ps.AddScript({param($Module,$Report);. $Module;Open-DoomMusicOneShotReader $Report}).AddArgument($oneShotModule).AddArgument($entry.Path)
                }else{
                    $null=$ps.AddScript({param($Module,$Report);. $Module;Open-DoomMusicLoopReader $Report}).AddArgument($readerModule).AddArgument($entry.Path)
                }
                try{$async=$ps.BeginInvoke();$jobs.Add(@{Track=$entry.Track;ExpectedReportSha256=$entry.ReportSha256;PowerShell=$ps;Async=$async})}
                catch{$ps.Dispose();if(-not $failure){$failure=$_.Exception}}
            }
            foreach($job in $jobs){
                try{
                    $opened=$job.PowerShell.EndInvoke($job.Async)
                    if($job.PowerShell.Streams.Error.Count -gt 0){throw $job.PowerShell.Streams.Error[0].ToString()}
                    if($opened.Count -ne 1){throw 'Music reader initialization returned an invalid result.'}
                    $reader=$opened[0]
                    if($reader -isnot [Collections.IDictionary]){throw 'Music reader initialization returned an invalid reader.'}
                    if($reader.ReportSha256 -cne $job.ExpectedReportSha256){
                        if($state.ReaderModes[$job.Track] -ceq 'OneShot'){Close-DoomMusicOneShotReader $reader}else{Close-DoomMusicLoopReader $reader}
                        throw 'Music qualification report changed during catalog loading.'
                    }
                    $state.Readers[$job.Track]=$reader;$state.Reports[$job.Track]=$reader.ReportSha256
                }catch{if(-not $failure){$failure=$_.Exception}}
                finally{$job.PowerShell.Dispose()}
            }
        }
        if($failure){throw $failure}
        foreach($entry in $catalog){
            if($null -eq $state.Readers[$entry.Track]){throw "Music reader failed to initialize: $($entry.Track)."}
        }
        return $state
    }catch{Close-DoomMusicPlayback $state;throw}
    finally{if($pool){$pool.Close();$pool.Dispose()}}
}
function Close-DoomMusicPlayback {
    param($State)
    if(-not $State.Closed){
        foreach($track in $State.Readers.Keys){
            $reader=$State.Readers[$track]
            if($null -ne $reader){
                if($State.ReaderModes[$track] -ceq 'OneShot'){Close-DoomMusicOneShotReader $reader}
                else{Close-DoomMusicLoopReader $reader}
            }
        }
        $State.Closed=$true
    }
}
function Reset-DoomMusicPlayback {
    param($State)
    if($State.Closed){throw 'Music playback is closed.'}
    $State.Selected=$null;$State.Transitions.Add(@{Kind='EpochReset';AfterFrames=$State.Frames})
}
function Update-DoomMusicPlayback {
    param($State,[object[]]$Commands)
    if($State.Closed){throw 'Music playback is closed.'}
    # Validate the complete packet before changing selection, gain or any cursor.
    foreach($command in $Commands){
        switch($command.Kind){
            Start {
                if(-not $State.Readers.ContainsKey($command.Track) -or $command.Loop -isnot [bool]){throw 'Track is missing or its loop mode is invalid.'}
                $mode=$State.ReaderModes[$command.Track]
                if(($mode -ceq 'Loop' -and -not $command.Loop) -or ($mode -ceq 'OneShot' -and $command.Loop)){throw 'Music command loop mode does not match its qualification.'}
                if($command.ContainsKey('Frame') -and ($command.Frame -isnot [int] -and $command.Frame -isnot [long] -or $command.Frame -lt 0 -or $command.Frame -gt [long]::MaxValue-48000)){throw 'Invalid music start frame.'}
                if($command.ContainsKey('Frame') -and $mode -ceq 'OneShot' -and $command.Frame -gt $State.Readers[$command.Track].FrameCount){throw 'One-shot start frame is past the end of its payload.'}
            }
            Stop {}
            Gain {if($command.Value -isnot [ValueType] -or -not [double]::IsFinite([double]$command.Value) -or $command.Value -lt 0 -or $command.Value -gt 1){throw 'Invalid music gain.'}}
            default {throw 'Unknown music playback command.'}
        }
    }
    foreach($command in $Commands){
        switch($command.Kind){
            Start {$State.Selected=$command.Track;$State.Readers[$State.Selected].Frame=if($command.ContainsKey('Frame')){[long]$command.Frame}else{0L};if($State.ReaderModes[$State.Selected] -ceq 'OneShot'){$State.Readers[$State.Selected].Finished=$false}}
            Stop {$State.Selected=$null}
            Gain {$State.Gain=[double]$command.Value}
        }
        $entry=$command.Clone();$entry.AfterFrames=$State.Frames;$State.Transitions.Add($entry)
    }
}
function Read-DoomMusicPlayback {
    param($State,[int]$Frames)
    if($State.Closed){throw 'Music playback is closed.'}
    if($null -eq $State.Selected){return $null}
    $track=$State.Selected
    if($State.ReaderModes[$track] -ceq 'OneShot'){
        $block=Read-DoomMusicOneShot $State.Readers[$track] $Frames
        if($block.Finished){$State.Selected=$null}
    }else{$block=Read-DoomMusicLoop $State.Readers[$track] $Frames}
    $State.Frames+=$Frames
    return ,$block.Mix
}
