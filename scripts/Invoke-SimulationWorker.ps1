#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad,[int]$Skill,[int]$Episode,[int]$Map,[string]$Channel,[string]$Assets,[string]$Report,[int]$OwnerPid,[switch]$StopAtLevelEnd,[switch]$ReplayCheckpoints,[string]$CheckpointReplay)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/RenderAssets.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
. "$PSScriptRoot/../src/SessionScreens.ps1"
. "$PSScriptRoot/../src/InputReplay.ps1"
$channelMap=[IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting($Channel);$view=$channelMap.CreateViewAccessor()
$ready=[Threading.EventWaitHandle]::OpenExisting($Channel+'-ready');$go=[Threading.EventWaitHandle]::OpenExisting($Channel+'-go')
$content=$null;$game=$null;$tick=0;$version=0;$slot=0;$failure=$null;$outcome='Stopped'
$tickTimes=[Collections.Generic.List[double]]::new();$snapshotTimes=[Collections.Generic.List[double]]::new();$lateness=[Collections.Generic.List[double]]::new()
$commandLog=[Collections.Generic.List[object]]::new()
$transitions=[Collections.Generic.List[object]]::new();$uiTimes=[Collections.Generic.List[double]]::new();$generation=1;$screens=$null
$checkpoints=[Collections.Generic.List[object]]::new();$checkpointTimes=[Collections.Generic.List[double]]::new();$extraCheckpoints=@{}
function Record-ReplayCheckpoint {
    if(-not $ReplayCheckpoints -or ($checkpoints.Count -gt 0 -and $checkpoints[-1].Tic -eq $script:tick)){return}
    $watch=[Diagnostics.Stopwatch]::StartNew();$checkpoints.Add((Get-DoomReplayCheckpoint $game $script:tick));$checkpointTimes.Add($watch.Elapsed.TotalMilliseconds)
}
function Record-SimulationTransition {
    $player=$game.World.ConsolePlayer
    $transitions.Add(@{Tic=$script:tick;State=$game.State.ToString();Episode=$game.Options.Episode;Map=$game.Options.Map;Generation=$script:generation;
        Health=$player.Health;Armor=$player.ArmorPoints;Ammo=$player.Ammo.Clone();Weapons=$player.WeaponOwned.Clone();Keys=$player.Cards.Clone();Kills=$player.KillCount;DidSecret=$player.DidSecret})
}
function Publish-SimulationSnapshot {
    $state=if($StopAtLevelEnd){0}else{[int]$game.State}
    if($state -eq 0){
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
    $view.WriteArray($base+64,$old,0,$old.Length);$view.WriteArray($base+64+$old.Length,$current,0,$current.Length)
    [Threading.Thread]::MemoryBarrier();$view.Write($base,$script:version);$view.Write(16,$script:slot);$view.Write(20,$script:tick)
}
try {
    $owner=[Diagnostics.Process]::GetProcessById($OwnerPid)
    if($CheckpointReplay){$recorded=Read-DoomInputReplay $CheckpointReplay (Get-FileHash -LiteralPath $Wad).Hash;foreach($point in $recorded.Checkpoints){$extraCheckpoints[[int]$point.Tic]=$true}}
    $bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
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
            # Block further simulation commands until the host has drained old jobs
            # and every persistent renderer has loaded this generation's assets.
            $view.Write(12,5);$generation++
            $context=New-FastRenderContext $content $game.World;Write-GameRenderAssets $context $palette $Assets
        }
        if($mapChanged -or $game.State -ne $priorState){Record-SimulationTransition}
        if($tick%350 -eq 0 -or $mapChanged -or $game.State -ne $priorState -or $extraCheckpoints.ContainsKey($tick)){Record-ReplayCheckpoint}
        $watch.Restart();Publish-SimulationSnapshot;$snapshotTimes.Add($watch.Elapsed.TotalMilliseconds)
        if($mapChanged){
            $view.Write(24,$generation);[Threading.Thread]::MemoryBarrier();$view.Write(12,4)
            while($view.ReadInt32(28) -ne $generation -and $view.ReadInt32(4) -eq 0){[void]$go.WaitOne(1000);if($owner.HasExited){$outcome='OwnerExited';break}}
            if($outcome -eq 'OwnerExited'){break};$view.Write(12,1)
        }
        if($StopAtLevelEnd -and $game.State -ne [GameState]::Level){$outcome='LevelComplete';$view.Write(12,2);break}
    }
} catch {$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$outcome='Error';[Console]::Error.WriteLine($failure);$view.Write(12,3);[void]$ready.Set()}
finally {
    if($null -ne $game -and $null -ne $game.World -and -not $failure){try{Record-ReplayCheckpoint}catch{$failure=$_.ToString();$outcome='Error'}}
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Outcome=$outcome;Error=$failure;Tics=$tick;WarmupTics=140;Skill=$Skill;Episode=$Episode;Map=$Map;
        ReplayCheckpoints=$checkpoints.ToArray();ReplayCheckpointMs=(Get-SampleStats $checkpointTimes.ToArray());ReplayCheckpointSamplesMs=$checkpointTimes.ToArray();
        StopAtLevelEnd=[bool]$StopAtLevelEnd;Transitions=$transitions.ToArray();FinalGeneration=$generation;SessionScreenMs=(Get-SampleStats $uiTimes.ToArray());SessionScreenSamplesMs=$uiTimes.ToArray();
        SimulationMs=(Get-SampleStats $tickTimes.ToArray());SnapshotPublishMs=(Get-SampleStats $snapshotTimes.ToArray());TickLatenessMs=(Get-SampleStats $lateness.ToArray());
        SimulationSamplesMs=$tickTimes.ToArray();SnapshotSamplesMs=$snapshotTimes.ToArray();TickLatenessSamplesMs=$lateness.ToArray();InputCommands=$commandLog.ToArray();
        Health=if($null -ne $game){$game.World.ConsolePlayer.Health}else{$null};Kills=if($null -ne $game){$game.World.ConsolePlayer.KillCount}else{$null}} |
        ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $Report
    if($null -ne $content){$content.Dispose()};$view.Dispose();$channelMap.Dispose();$ready.Dispose();$go.Dispose()
    if($outcome -eq 'OwnerExited' -and (Test-Path -LiteralPath $Assets)){Remove-Item -LiteralPath $Assets}
}
