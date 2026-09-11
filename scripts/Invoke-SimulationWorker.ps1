#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad,[int]$Skill,[int]$Episode,[int]$Map,[string]$Channel,[string]$Assets,[string]$Report,[int]$OwnerPid,[switch]$StopAtLevelEnd,[switch]$ReplayCheckpoints,[string]$CheckpointReplay,[string]$SaveRoot)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/RenderAssets.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
. "$PSScriptRoot/../src/SessionScreens.ps1"
. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/../src/SessionMenu.ps1"
. "$PSScriptRoot/../src/SaveState.ps1"
$channelMap=[IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting($Channel);$view=$channelMap.CreateViewAccessor()
$ready=[Threading.EventWaitHandle]::OpenExisting($Channel+'-ready');$go=[Threading.EventWaitHandle]::OpenExisting($Channel+'-go')
$content=$null;$game=$null;$tick=0;$version=0;$slot=0;$failure=$null;$outcome='Stopped'
$tickTimes=[Collections.Generic.List[double]]::new();$snapshotTimes=[Collections.Generic.List[double]]::new();$lateness=[Collections.Generic.List[double]]::new()
$commandLog=[Collections.Generic.List[object]]::new()
$transitions=[Collections.Generic.List[object]]::new();$uiTimes=[Collections.Generic.List[double]]::new();$generation=1;$screens=$null
$checkpoints=[Collections.Generic.List[object]]::new();$checkpointTimes=[Collections.Generic.List[double]]::new();$extraCheckpoints=@{}
$menuGraphics=$null;$menuPixels=$null;$menuScreen=0;$menuRevision=0;$episodeCount=4;$controlLog=[Collections.Generic.List[object]]::new()
$saveOperations=[Collections.Generic.List[object]]::new()
function Record-ReplayCheckpoint {
    param([switch]$Replace)
    if(-not $ReplayCheckpoints){return}
    if($checkpoints.Count -gt 0 -and $checkpoints[-1].Tic -eq $script:tick){if(-not $Replace){return};$checkpoints.RemoveAt($checkpoints.Count-1)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$checkpoints.Add((Get-DoomReplayCheckpoint $game $script:tick));$checkpointTimes.Add($watch.Elapsed.TotalMilliseconds)
}
function Record-SimulationTransition {
    $player=$game.World.ConsolePlayer
    $transitions.Add(@{Tic=$script:tick;State=$game.State.ToString();Episode=$game.Options.Episode;Map=$game.Options.Map;Generation=$script:generation;
        Health=$player.Health;Armor=$player.ArmorPoints;Ammo=$player.Ammo.Clone();Weapons=$player.WeaponOwned.Clone();Keys=$player.Cards.Clone();Kills=$player.KillCount;DidSecret=$player.DidSecret})
}
function Publish-SimulationSnapshot {
    $state=if($StopAtLevelEnd){0}else{[int]$game.State}
    $screenKind=if($null -ne $script:menuPixels){2}elseif($state -ne 0){1}else{0}
    if($screenKind -eq 2){$current=$script:menuPixels;$old=$current}
    elseif($state -eq 0){
        $old=ConvertTo-GameSnapshotBytes (New-GameRenderSnapshot $game 0)
        $current=ConvertTo-GameSnapshotBytes (New-GameRenderSnapshot $game 1)
    }else{
        $uiWatch=[Diagnostics.Stopwatch]::StartNew();$current=Get-DoomSessionScreen $screens $game;$old=$current
        $uiTimes.Add($uiWatch.Elapsed.TotalMilliseconds)
    }
    if($old.Length -ne $current.Length -or $old.Length*2+64 -gt 1048576){throw 'Simulation snapshot exceeds slot capacity.'}
    $script:slot=1-$script:slot;$script:version+=2
    [long]$base=131072+$script:slot*1048576
    $view.Write($base,$script:version-1);[Threading.Thread]::MemoryBarrier()
    $view.Write($base+4,$old.Length);$view.Write($base+8,$script:tick)
    $view.Write($base+12,$script:generation);$view.Write($base+16,[int]$state);$view.Write($base+20,[int]$game.Options.Episode);$view.Write($base+24,[int]$game.Options.Map)
    $view.Write($base+28,[int]$game.World.ConsolePlayer.Health);$view.Write($base+32,[int]$game.World.ConsolePlayer.KillCount)
    $view.Write($base+36,[int]$screenKind);$view.Write($base+40,[int]$script:menuRevision);$view.Write($base+44,[int]$script:menuScreen)
    $view.WriteArray($base+64,$old,0,$old.Length);$view.WriteArray($base+64+$old.Length,$current,0,$current.Length)
    [Threading.Thread]::MemoryBarrier();$view.Write($base,$script:version);$view.Write(16,$script:slot);$view.Write(20,$script:tick)
}
function Publish-SimulationMapChange {
    $view.Write(12,5);$script:generation++
    $context=New-FastRenderContext $content $game.World;Write-GameRenderAssets $context $palette $Assets
    Record-SimulationTransition;Record-ReplayCheckpoint -Replace
    $publishWatch=[Diagnostics.Stopwatch]::StartNew();Publish-SimulationSnapshot;$snapshotTimes.Add($publishWatch.Elapsed.TotalMilliseconds)
    $view.Write(24,$script:generation);[Threading.Thread]::MemoryBarrier();$view.Write(12,4)
    while($view.ReadInt32(28) -ne $script:generation -and $view.ReadInt32(4) -eq 0){[void]$go.WaitOne(1000);if($owner.HasExited){$script:outcome='OwnerExited';break}}
    if($script:outcome -ne 'OwnerExited'){$view.Write(12,1)}
}
try {
    $owner=[Diagnostics.Process]::GetProcessById($OwnerPid)
    $wadHash=(Get-FileHash -LiteralPath $Wad).Hash;$saveDirectory=Get-DoomSaveDirectory $SaveRoot $wadHash
    if($CheckpointReplay){$recorded=Read-DoomInputReplay $CheckpointReplay (Get-FileHash -LiteralPath $Wad).Hash;foreach($point in $recorded.Checkpoints){$extraCheckpoints[[int]$point.Tic]=$true}}
    $bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $episodeCount=if($options.GameMode -in [GameMode]::Shareware,[GameMode]::Commercial){1}elseif($options.GameMode -eq [GameMode]::Retail){4}else{3};$view.Write(80,[int]$episodeCount)
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]($Skill-1),$Episode,$Map);$null=$game.Update($commands)
    for($i=0;$i -lt 140;$i++){$commands[0].ForwardMove=25;$commands[0].Buttons=1;if($i -gt 70){$commands[0].AngleTurn=640};$null=$game.Update($commands)}
    foreach($cmd in $commands){$cmd.Clear()};$game.DeferedInitNew([GameSkill]($Skill-1),$Episode,$Map);$null=$game.Update($commands)
    $context=New-FastRenderContext $content $game.World;$palette=[int[][]]::new(256)
    for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    Write-GameRenderAssets $context $palette $Assets
    if(-not $StopAtLevelEnd){$screens=New-DoomSessionScreens $content}
    Record-SimulationTransition
    Record-ReplayCheckpoint
    Publish-SimulationSnapshot;$view.Write(12,1);[void]$ready.Set()
    while($view.ReadInt32(4) -eq 0) {
        $request=$view.ReadInt32(48)
        if($request -ne $view.ReadInt32(52) -and $tick -ge $view.ReadInt32(76)){
            if($tick -ne $view.ReadInt32(76)){throw 'Session action crossed its command boundary.'}
            $kind=$view.ReadInt32(56);$menuRevision++;$action=Read-DoomSessionPayload $view 32768
            $response=@{Action=$action.Action;Success=$true;Screen=0;Choice=0;Episode=$options.Episode;Skill=[int]$options.Skill+1;MessageTitle='';MessageDetail='';ReturnScreen=1}
            if($kind -eq 1){
                $menuScreen=$view.ReadInt32(60);$choice=$view.ReadInt32(64);$selectedEpisode=$view.ReadInt32(68);$selectedSkill=$view.ReadInt32(72)
                if($menuScreen -lt 0 -or $menuScreen -gt 13 -or $choice -lt 0 -or $choice -gt 5){throw 'Invalid menu request.'}
                if($menuScreen -eq 0){$menuPixels=$null;$options.Sound.Resume()}
                else{
                    $options.Sound.Pause()
                    if($null -eq $menuGraphics){$menuGraphics=New-DoomMenuGraphics $content}
                    $menuPixels=Get-DoomMenuPixels $menuGraphics $menuScreen $choice $selectedEpisode $selectedSkill $episodeCount -Details $action
                }
                Publish-SimulationSnapshot
                $response.Screen=$menuScreen;$response.Choice=$choice
            }elseif($kind -eq 2){
                $newSkill=$view.ReadInt32(60);$newEpisode=$view.ReadInt32(64);$newMap=$view.ReadInt32(68)
                if($newSkill -lt 1 -or $newSkill -gt 5 -or $newEpisode -lt 1 -or $newEpisode -gt $episodeCount -or $newMap -ne 1){throw 'Invalid new-game selection.'}
                $menuScreen=0;$menuPixels=$null;$game.Paused=$false;foreach($cmd in $commands){$cmd.Clear()}
                $game.DeferedInitNew([GameSkill]($newSkill-1),$newEpisode,$newMap);$null=$game.Update($commands)
                $controlLog.Add(@{Tic=$tick;Action='NewGame';Skill=$newSkill;Episode=$newEpisode;Map=$newMap})
                Publish-SimulationMapChange
            }elseif($kind -in 3,4){
                $operationWatch=[Diagnostics.Stopwatch]::StartNew();$result=$null;$errorText=$null
                $menuScreen=13;$options.Sound.Pause()
                if($null -eq $menuGraphics){$menuGraphics=New-DoomMenuGraphics $content}
                $busy=@{MessageTitle=if($kind -eq 3){'SAVING GAME'}else{'LOADING GAME'}}
                $menuPixels=Get-DoomMenuPixels $menuGraphics 13 0 $options.Episode ([int]$options.Skill+1) $episodeCount -Details $busy
                Publish-SimulationSnapshot
                try{
                    if($kind -eq 3){
                        if($action.Action -ne 'SaveGame' -or $action.Slot -isnot [long] -or $action.Slot -lt 1 -or $action.Slot -gt 6){throw 'Invalid save slot request.'}
                        $path=Get-DoomSlotPath $saveDirectory $action.Slot
                        $result=Write-DoomSaveState $game $path $wadHash "E$($options.Episode)M$($options.Map)" -ReplaceExpectedHash $action.ExpectedHash
                    }else{
                        if($action.Action -ne 'LoadGame'){throw 'Invalid load request.'}
                        $replayLoad=$null -ne $action.PSObject.Properties['SaveHash']
                        if($replayLoad){$expectedHash=$action.SaveHash;$path=Get-DoomReplaySavePath $saveDirectory $expectedHash}
                        else{
                            if($action.Slot -isnot [long] -or $action.Slot -lt 1 -or $action.Slot -gt 6){throw 'Invalid load slot request.'}
                            $expectedHash=$action.ExpectedHash;$path=Get-DoomSlotPath $saveDirectory $action.Slot
                        }
                        if($expectedHash -notmatch '^[a-fA-F0-9]{64}$'){throw 'Loading requires the selected save hash.'}
                        $saved=Read-DoomSaveState $path $wadHash
                        if($saved.Sha256 -ne $expectedHash){throw 'Save changed after selection.'}
                        if(-not $saved.SourceMatches -and -not ($replayLoad -or $action.AllowSourceMismatch)){throw 'Save version changed; select and confirm again.'}
                        $candidate=New-DoomGameFromSave $saved $content
                        # Archive the exact parsed bytes before publishing the candidate.
                        # Replay loads cannot mutate a slot or name an arbitrary path.
                        $archive=Get-DoomReplaySavePath $saveDirectory $saved.Sha256
                        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($archive))
                        if(Test-Path -LiteralPath $archive){if((Get-FileHash -LiteralPath $archive).Hash -ne $saved.Sha256){throw 'Replay save archive checksum differs.'}}
                        else{
                            $temporary=$archive+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
                            try{[IO.File]::WriteAllBytes($temporary,$saved.Bytes);[IO.File]::Move($temporary,$archive,$false)}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
                        }
                    }
                }catch{
                    $errorText=$_.ToString()+"`n"+$_.ScriptStackTrace;$response.Success=$false;$response.Error=$errorText
                    $response.Screen=12;$response.ReturnScreen=if($kind -eq 3){8}else{9}
                    $response.MessageTitle=if($kind -eq 3){'SAVE FAILED'}else{'LOAD FAILED'}
                    $response.MessageDetail=if($errorText -match 'changed after|version changed'){'SELECT SLOT AGAIN'}else{'FILE UNAVAILABLE'}
                    $menuRevision++;$menuScreen=12;$menuPixels=Get-DoomMenuPixels $menuGraphics 12 0 $options.Episode ([int]$options.Skill+1) $episodeCount -Details $response
                    Publish-SimulationSnapshot
                }
                if($response.Success){
                    # Reconstruction/archive failures above leave the live game
                    # intact. Failures after this commit are host/worker failures.
                    $menuRevision++;$menuScreen=0;$menuPixels=$null
                    if($kind -eq 4){
                        foreach($device in 'Video','Sound','Music','UserInput'){$candidate.Options.$device=$options.$device}
                        $game=$candidate;$options=$game.Options;$game.Paused=$false;foreach($cmd in $commands){$cmd.Clear()}
                        $screens=if($StopAtLevelEnd){$null}else{New-DoomSessionScreens $content}
                        $options.Sound.SetListener($game.World.ConsolePlayer.Mobj);$options.Sound.Resume()
                        $controlLog.Add(@{Tic=$tick;Action='LoadGame';SaveHash=$saved.Sha256})
                        $result=@{Sha256=$saved.Sha256;SourceMatches=$saved.SourceMatches;GameTic=$game.GameTic;Episode=$options.Episode;Map=$options.Map}
                        Publish-SimulationMapChange
                    }else{$options.Sound.Resume();Publish-SimulationSnapshot}
                }
                $saveOperations.Add(@{Tic=$tick;Action=$action.Action;Request=$action;Success=$response.Success;Error=$errorText;Milliseconds=$operationWatch.Elapsed.TotalMilliseconds;Result=$result})
            }else{throw 'Unknown session action.'}
            $response.Screen=$menuScreen;$response.Episode=$options.Episode;$response.Skill=[int]$options.Skill+1
            Write-DoomSessionPayload $view 65536 $response
            [Threading.Thread]::MemoryBarrier();$view.Write(52,$request)
            if($outcome -eq 'OwnerExited'){break};continue
        }
        if($tick -ge $view.ReadInt32(0)){[void]$go.WaitOne(1000);if($owner.HasExited){$outcome='OwnerExited';break};continue}
        [long]$offset=4096+($tick%1024)*16
        $cmd=$commands[0];$cmd.Clear();$cmd.ForwardMove=$view.ReadInt32($offset);$cmd.SideMove=$view.ReadInt32($offset+4);$cmd.AngleTurn=$view.ReadInt32($offset+8);$cmd.Buttons=$view.ReadInt32($offset+12)
        $commandLog.Add(@($cmd.ForwardMove,$cmd.SideMove,$cmd.AngleTurn,$cmd.Buttons))
        $start=$view.ReadInt64(40)
        if($start -gt 0){$lateness.Add(([Diagnostics.Stopwatch]::GetTimestamp()-$start)*1000.0/[Diagnostics.Stopwatch]::Frequency-($tick+1)*1000.0/35)}
        $priorWorld=$game.World;$priorState=$game.State
        $watch=[Diagnostics.Stopwatch]::StartNew();$null=$game.Update($commands);$tickTimes.Add($watch.Elapsed.TotalMilliseconds);$tick++
        $mapChanged=-not [object]::ReferenceEquals($priorWorld,$game.World)
        if($mapChanged){
            Publish-SimulationMapChange;if($outcome -eq 'OwnerExited'){break}
        }else{
            if($game.State -ne $priorState){Record-SimulationTransition}
            if($tick%350 -eq 0 -or $game.State -ne $priorState -or $extraCheckpoints.ContainsKey($tick)){Record-ReplayCheckpoint}
            $watch.Restart();Publish-SimulationSnapshot;$snapshotTimes.Add($watch.Elapsed.TotalMilliseconds)
        }
        if($StopAtLevelEnd -and $game.State -ne [GameState]::Level){$outcome='LevelComplete';$view.Write(12,2);break}
    }
} catch {$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$outcome='Error';[Console]::Error.WriteLine($failure);$view.Write(12,3);[void]$ready.Set()}
finally {
    if($null -ne $game -and $null -ne $game.World -and -not $failure){try{Record-ReplayCheckpoint}catch{$failure=$_.ToString();$outcome='Error'}}
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Outcome=$outcome;Error=$failure;Tics=$tick;WarmupTics=140;Skill=$Skill;Episode=$Episode;Map=$Map;
        ReplayCheckpoints=$checkpoints.ToArray();ReplayCheckpointMs=(Get-SampleStats $checkpointTimes.ToArray());ReplayCheckpointSamplesMs=$checkpointTimes.ToArray();
        ControlEvents=$controlLog.ToArray();MenuScreen=$menuScreen;MenuRevision=$menuRevision;SaveOperations=$saveOperations.ToArray();SaveDirectory=$saveDirectory;
        StopAtLevelEnd=[bool]$StopAtLevelEnd;Transitions=$transitions.ToArray();FinalGeneration=$generation;SessionScreenMs=(Get-SampleStats $uiTimes.ToArray());SessionScreenSamplesMs=$uiTimes.ToArray();
        SimulationMs=(Get-SampleStats $tickTimes.ToArray());SnapshotPublishMs=(Get-SampleStats $snapshotTimes.ToArray());TickLatenessMs=(Get-SampleStats $lateness.ToArray());
        SimulationSamplesMs=$tickTimes.ToArray();SnapshotSamplesMs=$snapshotTimes.ToArray();TickLatenessSamplesMs=$lateness.ToArray();InputCommands=$commandLog.ToArray();
        Health=if($null -ne $game){$game.World.ConsolePlayer.Health}else{$null};Kills=if($null -ne $game){$game.World.ConsolePlayer.KillCount}else{$null}} |
        ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $Report
    if($null -ne $content){$content.Dispose()};$view.Dispose();$channelMap.Dispose();$ready.Dispose();$go.Dispose()
    if($outcome -eq 'OwnerExited' -and (Test-Path -LiteralPath $Assets)){Remove-Item -LiteralPath $Assets}
}
