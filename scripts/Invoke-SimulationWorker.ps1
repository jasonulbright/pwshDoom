#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad,[int]$Skill,[int]$Episode,[int]$Map,[string]$Channel,[string]$Assets,[string]$Report,[int]$OwnerPid)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/RenderAssets.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$channelMap=[IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting($Channel);$view=$channelMap.CreateViewAccessor()
$ready=[Threading.EventWaitHandle]::OpenExisting($Channel+'-ready');$go=[Threading.EventWaitHandle]::OpenExisting($Channel+'-go')
$content=$null;$game=$null;$tick=0;$version=0;$slot=0;$failure=$null;$outcome='Stopped'
$tickTimes=[Collections.Generic.List[double]]::new();$snapshotTimes=[Collections.Generic.List[double]]::new();$lateness=[Collections.Generic.List[double]]::new()
$commandLog=[Collections.Generic.List[object]]::new()
function Publish-SimulationSnapshot {
    $old=ConvertTo-GameSnapshotBytes (New-GameRenderSnapshot $game 0)
    $current=ConvertTo-GameSnapshotBytes (New-GameRenderSnapshot $game 1)
    if($old.Length -ne $current.Length -or $old.Length*2+64 -gt 1048576){throw 'Simulation snapshot exceeds slot capacity.'}
    $script:slot=1-$script:slot;$script:version+=2
    [long]$base=131072+$script:slot*1048576
    $view.Write($base,$script:version-1);[Threading.Thread]::MemoryBarrier()
    $view.Write($base+4,$old.Length);$view.Write($base+8,$script:tick)
    $view.WriteArray($base+64,$old,0,$old.Length);$view.WriteArray($base+64+$old.Length,$current,0,$current.Length)
    [Threading.Thread]::MemoryBarrier();$view.Write($base,$script:version);$view.Write(16,$script:slot);$view.Write(20,$script:tick)
}
try {
    $owner=[Diagnostics.Process]::GetProcessById($OwnerPid)
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
    Publish-SimulationSnapshot;$view.Write(12,1);[void]$ready.Set()
    while($view.ReadInt32(4) -eq 0) {
        if($tick -ge $view.ReadInt32(0)){[void]$go.WaitOne(1000);if($owner.HasExited){$outcome='OwnerExited';break};continue}
        [long]$offset=4096+($tick%1024)*16
        $cmd=$commands[0];$cmd.Clear();$cmd.ForwardMove=$view.ReadInt32($offset);$cmd.SideMove=$view.ReadInt32($offset+4);$cmd.AngleTurn=$view.ReadInt32($offset+8);$cmd.Buttons=$view.ReadInt32($offset+12)
        $commandLog.Add(@($cmd.ForwardMove,$cmd.SideMove,$cmd.AngleTurn,$cmd.Buttons))
        $start=$view.ReadInt64(40)
        if($start -gt 0){$lateness.Add(([Diagnostics.Stopwatch]::GetTimestamp()-$start)*1000.0/[Diagnostics.Stopwatch]::Frequency-($tick+1)*1000.0/35)}
        $watch=[Diagnostics.Stopwatch]::StartNew();$null=$game.Update($commands);$tickTimes.Add($watch.Elapsed.TotalMilliseconds);$tick++
        $watch.Restart();Publish-SimulationSnapshot;$snapshotTimes.Add($watch.Elapsed.TotalMilliseconds)
        if($game.State -ne [GameState]::Level){$outcome='LevelComplete';$view.Write(12,2);break}
    }
} catch {$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$outcome='Error';[Console]::Error.WriteLine($failure);$view.Write(12,3);[void]$ready.Set()}
finally {
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Outcome=$outcome;Error=$failure;Tics=$tick;WarmupTics=140;Skill=$Skill;Episode=$Episode;Map=$Map;
        SimulationMs=(Get-SampleStats $tickTimes.ToArray());SnapshotPublishMs=(Get-SampleStats $snapshotTimes.ToArray());TickLatenessMs=(Get-SampleStats $lateness.ToArray());
        SimulationSamplesMs=$tickTimes.ToArray();SnapshotSamplesMs=$snapshotTimes.ToArray();TickLatenessSamplesMs=$lateness.ToArray();InputCommands=$commandLog.ToArray();
        Health=if($null -ne $game){$game.World.ConsolePlayer.Health}else{$null};Kills=if($null -ne $game){$game.World.ConsolePlayer.KillCount}else{$null}} |
        ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $Report
    if($null -ne $content){$content.Dispose()};$view.Dispose();$channelMap.Dispose();$ready.Dispose();$go.Dispose()
    if($outcome -eq 'OwnerExited' -and (Test-Path -LiteralPath $Assets)){Remove-Item -LiteralPath $Assets}
}
