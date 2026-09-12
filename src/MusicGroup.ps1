# SPDX-License-Identifier: GPL-2.0-or-later
# Experimental channel-partitioned synthesis. Not loaded by the game host.
function New-DoomMusicGroup {
    param($Bank,$Score,[int[]]$Channels,[ValidateRange(1,13230000)][int]$Frames,
        [ValidateSet('Channel','Note')][string]$Partition='Channel',[ValidateRange(1,8)][int]$GroupCount=1,[int]$GroupIndex=0)
    $owned=[bool[]]::new(16)
    if($Channels.Count -eq 0){throw 'A music group needs at least one channel.'}
    foreach($channel in $Channels){if($channel -lt 0 -or $channel -gt 15 -or $owned[$channel]){throw 'Invalid or repeated music group channel.'};$owned[$channel]=$true}
    if($GroupIndex -lt 0 -or $GroupIndex -ge $GroupCount){throw 'Invalid music group index.'}
    return @{Synth=(New-DoomMusicSynth $Bank);Timeline=(New-DoomMusicTimeline $Score -Loop);Owned=$owned;Frames=$Frames;Chunk=0;
        Partition=$Partition;GroupCount=$GroupCount;GroupIndex=$GroupIndex;OwnedNoteOns=0;OwnedPeakVoices=0}
}
function Read-DoomMusicGroup {
    param($Group,[ValidateRange(1,140)][int]$Blocks=20)
    $synth=$Group.Synth;$timeline=$Group.Timeline;[int]$begin=$synth.Frame
    [int]$count=[Math]::Min($Blocks*1260,$Group.Frames-$begin)
    if($count -le 0){throw 'Music group is already finished.'}
    [double[]]$mix=[double[]]::new(2*$count);[int]$cursor=0;$watch=[Diagnostics.Stopwatch]::StartNew()
    while($synth.Frame -lt $begin+$count){
        [int]$frames=[Math]::Min(1260,$begin+$count-$synth.Frame);$block=Read-DoomMusicFrames $timeline $frames
        foreach($event in $block.Events){
            # Preserve every event boundary, including events ignored by this group.
            [int]$span=$event[0]-$synth.Frame
            if($span -gt 0){$part=Read-DoomMusicSynth $synth $span;$part.CopyTo($mix,$cursor);$cursor+=$part.Length}
            if($Group.Partition -eq 'Note'){
                # Every worker processes cuts/controllers/releases. Only the selected
                # worker retains the newly admitted note, including all its layers.
                Invoke-DoomMusicEvent $synth $event
                if($event[1] -eq 1 -and $event[4] -gt 0){
                    if(($synth.NextNote-1)%$Group.GroupCount -eq $Group.GroupIndex){$Group.OwnedNoteOns++}
                    else{for($i=$synth.Voices.Count-1;$i -ge 0;$i--){if($synth.Voices[$i].NoteId -ne $synth.NextNote){break};$synth.Voices.RemoveAt($i)}}
                }
                $Group.OwnedPeakVoices=[Math]::Max($Group.OwnedPeakVoices,$synth.Voices.Count)
            }elseif($event[1] -eq 6 -or $Group.Owned[$event[2]]){Invoke-DoomMusicEvent $synth $event}
        }
        [int]$span=$block.Frame+$frames-$synth.Frame
        if($span -gt 0){$part=Read-DoomMusicSynth $synth $span;$part.CopyTo($mix,$cursor);$cursor+=$part.Length}
    }
    if($cursor -ne $mix.Length){throw 'Incomplete music group chunk.'}
    $chunk=@{Index=$Group.Chunk;Frame=$begin;Frames=$count;Mix=$mix;RenderMilliseconds=$watch.Elapsed.TotalMilliseconds};$Group.Chunk++;return $chunk
}
