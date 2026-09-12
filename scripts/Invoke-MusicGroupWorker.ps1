#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Root,$Bank,$Score,[int[]]$Channels,[int]$Frames,[int]$Blocks,$Queue,$Cancellation,[string]$Partition='Channel',[int]$GroupIndex=0,[int]$GroupCount=1)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
try{
    foreach($name in 'MusScore','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','MusicGroup'){. "$Root/src/$name.ps1"}
    $group=New-DoomMusicGroup $Bank $Score $Channels $Frames -Partition $Partition -GroupIndex $GroupIndex -GroupCount $GroupCount;$initialized=[Diagnostics.Stopwatch]::GetTimestamp()
    while($group.Synth.Frame -lt $Frames){
        $Cancellation.Token.ThrowIfCancellationRequested()
        $chunk=Read-DoomMusicGroup $group $Blocks;$chunk.InitializedAt=$initialized
        $Queue.Add($chunk,$Cancellation.Token)
    }
    return @{Channels=$Channels;NoteOns=if($Partition -eq 'Note'){$group.OwnedNoteOns}else{$group.Synth.NoteOns};ProcessedNoteOns=$group.Synth.NoteOns;ExclusiveCuts=$group.Synth.ExclusiveCuts;
        PeakVoices=if($Partition -eq 'Note'){$group.OwnedPeakVoices}else{$group.Synth.PeakVoices};Frames=$group.Synth.Frame}
}finally{$Queue.CompleteAdding()}
