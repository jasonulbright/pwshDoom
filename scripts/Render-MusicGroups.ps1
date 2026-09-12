#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2",
    [ValidatePattern('^D_[A-Z0-9]+$')][string]$Track='D_E1M1',[ValidateRange(1,300)][int]$Seconds=8,
    [ValidateRange(1,8)][int]$Groups=2,[ValidateSet('Serial','Parallel')][string]$Execution='Parallel',
    [ValidateSet('RoundRobin','GreedyNotes','RoundRobinNotes')][string]$GroupPolicy='RoundRobin',
    [ValidateSet('Inline','Function')][string]$MergeMode='Inline',
    [ValidateRange(1,140)][int]$BlocksPerChunk=20,[ValidateRange(10,3600)][int]$TimeoutSeconds=600,
    [ValidateRange(0,1)][double]$Volume=.2,[string]$ReferenceReport)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$sourcePaths=@('src/MusScore.ps1','src/SoundFontBank.ps1','src/SoundFontRegions.ps1','src/MusicOscillator.ps1','src/MusicControls.ps1','src/MusicSynth.ps1','src/MusicGroup.ps1','src/AudioMixer.ps1','scripts/Invoke-MusicGroupWorker.ps1','scripts/Render-MusicGroups.ps1')
$sourceHashes=@($sourcePaths|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path $root $_)).Hash}})
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$root/local/music-groups-$PID.ps1";. $bundle
foreach($name in 'MusScore','SoundFontBank','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','MusicGroup','AudioMixer'){. "$root/src/$name.ps1"}
$failure=$null;$details=$null;$archive=$null;$pool=$null;$tasks=[Collections.Generic.List[object]]::new();$states=[Collections.Generic.List[object]]::new()
$cancellation=[Threading.CancellationTokenSource]::new();$chunkTimes=[Collections.Generic.List[object]]::new();$workers=[Collections.Generic.List[object]]::new()
function Add-MusicGroupBuffer([double[]]$Destination,[double[]]$Source){
    for([int]$i=0;$i -lt $Destination.Length;$i++){$Destination[$i]+=$Source[$i]}
}
try{
    $prep=[Diagnostics.Stopwatch]::StartNew()
    $bank=ConvertTo-DoomSoundFontRegions (ConvertFrom-DoomSoundFont ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($SoundFont))))
    $archive=[Wad]::new([string[]]@($Wad));$score=ConvertFrom-DoomMus ($archive.ReadLump($archive.GetLumpNumber($Track))) -Name $Track
    $channelNotes=[int[]]::new(16);foreach($event in $score.Events){if($event[1] -eq 1 -and $event[4] -gt 0){$channelNotes[$event[2]]++}}
    $assignment=[int[]]::new(16)
    $partition=if($GroupPolicy -eq 'RoundRobinNotes'){'Note'}else{'Channel'}
    if($GroupPolicy -ne 'GreedyNotes'){for($ch=0;$ch -lt 16;$ch++){$assignment[$ch]=$ch%$Groups}}
    else{
        $loads=[int[]]::new($Groups);$rank=0
        foreach($ch in (0..15|Sort-Object @{Expression={$channelNotes[$_]};Descending=$true},@{Expression={$_};Descending=$false})){
            $target=if($rank -lt $Groups){$rank}else{0}
            if($rank -ge $Groups){for($id=1;$id -lt $Groups;$id++){if($loads[$id] -lt $loads[$target]){$target=$id}}}
            $assignment[$ch]=$target;$loads[$target]+=$channelNotes[$ch];$rank++
        }
    }
    $preparationSeconds=$prep.Elapsed.TotalSeconds;$frames=$Seconds*44100;$samples=[int16[]]::new($frames*2);$pcmState=@{Volume=$Volume;ClippedSamples=0L}
    $watch=[Diagnostics.Stopwatch]::StartNew();$launch=[Diagnostics.Stopwatch]::GetTimestamp();$initialized=0L
    if($Execution -eq 'Parallel'){$pool=[runspacefactory]::CreateRunspacePool($Groups,$Groups);$pool.Open()}
    for($id=0;$id -lt $Groups;$id++){
        [int[]]$channels=if($partition -eq 'Note'){0..15}else{@(0..15|Where-Object {$assignment[$_] -eq $id})}
        if($Execution -eq 'Serial'){$states.Add((New-DoomMusicGroup $bank $score $channels $frames -Partition $partition -GroupIndex $id -GroupCount $Groups))}
        else{
            $queue=[Collections.Concurrent.BlockingCollection[object]]::new(2);$ps=[powershell]::Create();$ps.RunspacePool=$pool
            $null=$ps.AddScript([IO.File]::ReadAllText("$PSScriptRoot/Invoke-MusicGroupWorker.ps1")).AddArgument($root).AddArgument($bank).AddArgument($score).AddArgument($channels).AddArgument($frames).AddArgument($BlocksPerChunk).AddArgument($queue).AddArgument($cancellation).AddArgument($partition).AddArgument($id).AddArgument($Groups)
            $tasks.Add(@{Shell=$ps;Queue=$queue;Handle=$ps.BeginInvoke();Channels=$channels;Observed=$false})
        }
    }
    if($Execution -eq 'Serial'){$initialized=[Diagnostics.Stopwatch]::GetTimestamp()}
    [int]$cursor=0;[int]$chunkIndex=0;[double]$mergeSeconds=0;[double]$firstChunkSeconds=0;[double]$requiredStartupSeconds=0
    while($cursor -lt $frames){
        $chunks=[Collections.Generic.List[object]]::new()
        for($id=0;$id -lt $Groups;$id++){
            if($Execution -eq 'Serial'){$chunk=Read-DoomMusicGroup $states[$id] $BlocksPerChunk}
            else{
                $task=$tasks[$id];$chunk=$null
                while(-not $task.Queue.TryTake([ref]$chunk,100)){
                    if($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw 'Music group experiment timed out.'}
                    if($task.Handle.IsCompleted -and $task.Queue.Count -eq 0){throw "Music worker ended before supplying a chunk: $($task.Shell.Streams.Error -join '; ')"}
                }
                if($chunk.InitializedAt -gt $initialized){$initialized=$chunk.InitializedAt}
            }
            if($chunk.Frame -ne $cursor -or $chunk.Index -ne $chunkIndex -or ($chunks.Count -gt 0 -and $chunk.Frames -ne $chunks[0].Frames)){throw 'Music group chunk sequence mismatch.'}
            $chunks.Add($chunk)
        }
        $merge=[Diagnostics.Stopwatch]::StartNew();[double[]]$mix=$chunks[0].Mix
        for($id=1;$id -lt $Groups;$id++){
            [double[]]$part=$chunks[$id].Mix
            if($MergeMode -eq 'Function'){Add-MusicGroupBuffer $mix $part}
            else{for([int]$i=0;$i -lt $mix.Length;$i++){$mix[$i]+=$part[$i]}}
        }
        $pcm=ConvertTo-DoomMusicPcm $pcmState $mix;$pcm.CopyTo($samples,2*$cursor);$mergeSeconds+=$merge.Elapsed.TotalSeconds
        $completed=$watch.Elapsed.TotalSeconds;if($chunkIndex -eq 0){$firstChunkSeconds=$completed}
        $requiredStartupSeconds=[Math]::Max($requiredStartupSeconds,$completed-$cursor/44100.0)
        $chunkTimes.Add(@{Frame=$cursor;Frames=$chunks[0].Frames;CompletedSeconds=$completed;WorkerRenderMilliseconds=@($chunks|ForEach-Object {$_.RenderMilliseconds})})
        $cursor+=$chunks[0].Frames;$chunkIndex++
        if($chunkIndex%10 -eq 0 -or $cursor -eq $frames){"Produced $([Math]::Round($cursor/44100.0,2))/$Seconds seconds with $Groups $Execution groups."}
        if($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds){throw 'Music group experiment timed out.'}
    }
    if($Execution -eq 'Parallel'){
        foreach($task in $tasks){$result=$task.Shell.EndInvoke($task.Handle);$task.Observed=$true;if($task.Shell.HadErrors -or $result.Count -ne 1){throw "Music worker failed: $($task.Shell.Streams.Error -join '; ')"};$workers.Add($result[0])}
    }else{
        foreach($state in $states){$workers.Add(@{Channels=@(0..15|Where-Object {$state.Owned[$_]});NoteOns=if($partition -eq 'Note'){$state.OwnedNoteOns}else{$state.Synth.NoteOns};ProcessedNoteOns=$state.Synth.NoteOns;ExclusiveCuts=$state.Synth.ExclusiveCuts;
            PeakVoices=if($partition -eq 'Note'){$state.OwnedPeakVoices}else{$state.Synth.PeakVoices};Frames=$state.Synth.Frame})}
    }
    $renderSeconds=$watch.Elapsed.TotalSeconds
    $dir=Join-Path "$root/local" ('music-groups-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $dir|Out-Null
    $wave=Join-Path $dir "$Track-$Execution-$Groups.wav";Write-DoomPcmWave $wave $samples
    $comparison=$null
    if($ReferenceReport){
        $r=Get-Content $ReferenceReport -Raw|ConvertFrom-Json
        if($r.Error -or $r.Details.Frames -ne $frames -or $r.Details.MusSha256 -cne $score.SourceSha256 -or $r.Details.SoundFontSha256 -cne $bank.SourceSha256 -or $r.Details.Volume -ne $Volume){throw 'Music reference inputs differ.'}
        if((Get-FileHash $r.Details.WavPath).Hash -cne $r.Details.WavSha256){throw 'Music reference WAV changed.'}
        $bytes=[IO.File]::ReadAllBytes($r.Details.WavPath);if($bytes.Length -ne 44+$samples.Length*2 -or [Text.Encoding]::ASCII.GetString($bytes,36,4) -cne 'data'){throw 'Expected canonical PCM reference WAV.'}
        $reference=[int16[]]::new($samples.Length);[Buffer]::BlockCopy($bytes,44,$reference,0,$samples.Length*2)
        [int]$changed=0;[int]$maximum=0;[double]$squared=0
        for([int]$i=0;$i -lt $samples.Length;$i++){[int]$difference=[int]$samples[$i]-[int]$reference[$i];if($difference -ne 0){$changed++;$squared+=[double]$difference*$difference;if($difference -lt 0){$difference=-$difference};if($difference -gt $maximum){$maximum=$difference}}}
        $comparison=@{ReportSha256=(Get-FileHash $ReferenceReport).Hash;ReferenceWavSha256=$r.Details.WavSha256;ChangedSamples=$changed;MaximumPcmDifference=$maximum;DifferenceRms=[Math]::Sqrt($squared/$samples.Length)}
    }
    $details=@{WavPath=$wave;WavSha256=(Get-FileHash $wave).Hash;Frames=$frames;Seconds=$Seconds;Track=$Track;MusSha256=$score.SourceSha256;SoundFontSha256=$bank.SourceSha256;Volume=$Volume;
        Execution=$Execution;Groups=$Groups;GroupPolicy=$GroupPolicy;MergeMode=$MergeMode;ChannelNotesPerScore=$channelNotes;ChannelAssignment=if($partition -eq 'Channel'){$assignment}else{$null};BlocksPerChunk=$BlocksPerChunk;QueueCapacityPerWorker=2;Workers=$workers.ToArray();ClippedSamples=$pcmState.ClippedSamples;
        PreparationSeconds=$preparationSeconds;RenderSeconds=$renderSeconds;AudioSecondsPerRenderSecond=$Seconds/$renderSeconds;InitializationSeconds=($initialized-$launch)/[double][Diagnostics.Stopwatch]::Frequency;
        FirstChunkSeconds=$firstChunkSeconds;MergeAndPcmSeconds=$mergeSeconds;RequiredStartupSecondsForObservedChunkSchedule=$requiredStartupSeconds;Chunks=$chunkTimes.ToArray();Comparison=$comparison;
        PeakProcessWorkingSetBytes=[Diagnostics.Process]::GetCurrentProcess().PeakWorkingSet64;QueuePayloadBoundBytes=$Groups*2*$BlocksPerChunk*1260*2*8;OutputPcmBytes=$samples.Length*2}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    $cancellation.Cancel()
    foreach($task in $tasks){if(-not $task.Handle.IsCompleted){$task.Shell.Stop()};$task.Shell.Dispose();$task.Queue.Dispose()}
    if($pool){$pool.Close();$pool.Dispose()};$cancellation.Dispose();if($archive){$archive.Dispose()}
    @{Error=$failure;Details=$details;WadSha256=(Get-FileHash $Wad).Hash;Sources=$sourceHashes;SourcesChangedDuringRun=@($sourceHashes|Where-Object {$_.Sha256 -cne (Get-FileHash (Join-Path $root $_.Path)).Hash});PowerShell=$PSVersionTable.PSVersion.ToString();
      Meaning='Offline dry PowerShell channel-group experiment. Parallel queues are bounded; bank/score objects are shared read-only. Render timing includes group/pool initialization, producer waits and final mixing, excludes bank/score preparation and output/diagnostics. Peak memory is the entire harness process. Required startup is retrospective from an unpaced chunk schedule, not actual playback/underrun evidence. No game-host integration.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: grouped music rendered to $wave"
