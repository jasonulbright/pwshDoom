# SPDX-License-Identifier: GPL-2.0-or-later
# Persistent catalog of qualified readers, owned only by the audio runspace.
function New-DoomMusicPlayback {
    param([hashtable]$Reports=@{})
    $state=@{Readers=@{};Reports=@{};Selected=$null;Gain=.2;Frames=0L;Transitions=[Collections.Generic.List[object]]::new();Closed=$false}
    try{
        foreach($track in $Reports.Keys){
            if($track -cnotmatch '^D_[A-Z0-9]+$'){throw 'Invalid music catalog track name.'}
            $r=Get-Content $Reports[$track] -Raw|ConvertFrom-Json
            if($r.Details.Track -cne $track){throw 'Music catalog name does not match its qualification.'}
            $state.Readers[$track]=Open-DoomMusicLoopReader $Reports[$track]
            $state.Reports[$track]=$state.Readers[$track].ReportSha256
        }
        return $state
    }catch{Close-DoomMusicPlayback $state;throw}
}
function Close-DoomMusicPlayback {
    param($State)
    if(-not $State.Closed){foreach($reader in $State.Readers.Values){Close-DoomMusicLoopReader $reader};$State.Closed=$true}
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
                if(-not $State.Readers.ContainsKey($command.Track) -or $command.Loop -isnot [bool] -or -not $command.Loop){throw 'Track is missing or one-shot music is not qualified.'}
                if($command.ContainsKey('Frame') -and ($command.Frame -isnot [int] -and $command.Frame -isnot [long] -or $command.Frame -lt 0 -or $command.Frame -gt [long]::MaxValue-48000)){throw 'Invalid music start frame.'}
            }
            Stop {}
            Gain {if($command.Value -isnot [ValueType] -or -not [double]::IsFinite([double]$command.Value) -or $command.Value -lt 0 -or $command.Value -gt 1){throw 'Invalid music gain.'}}
            default {throw 'Unknown music playback command.'}
        }
    }
    foreach($command in $Commands){
        switch($command.Kind){
            Start {$State.Selected=$command.Track;$State.Readers[$State.Selected].Frame=if($command.ContainsKey('Frame')){[long]$command.Frame}else{0L}}
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
    $block=Read-DoomMusicLoop $State.Readers[$State.Selected] $Frames;$State.Frames+=$Frames
    return ,$block.Mix
}
