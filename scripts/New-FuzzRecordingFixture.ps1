#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[Parameter(Mandatory)][string]$SaveRoot,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh fixture path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
. "$PSScriptRoot/../src/SaveState.ps1";. "$PSScriptRoot/../src/SaveSlots.ps1";. "$PSScriptRoot/../src/AutomapSession.ps1"
$content=$null
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$hash=(Get-FileHash $Wad).Hash
    $o=[GameOptions]::new();$o.GameMode=$content.Wad.GameMode;$o.GameVersion=$content.Wad.GameVersion;$o.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$o);$cmd=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$cmd[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($cmd)
    $player=$game.World.ConsolePlayer;$camera=$player.Mobj;$angle=$camera.Angle.Data*2*[Math]::PI/4294967296.0
    $null=$game.World.ItemPickup.GivePower($player,[PowerType]::Invisibility);$player.Powers[[int][PowerType]::Invisibility]=210
    # Visual fixture only: keep the idle player alive while the Spectre attacks.
    $player.Health=999;$camera.Health=999
    $shadow=$game.World.ThingAllocation.SpawnMobj([Fixed]::FromDouble($camera.X.Data/65536.0+96*[Math]::Cos($angle)),[Fixed]::FromDouble($camera.Y.Data/65536.0+96*[Math]::Sin($angle)),$camera.Z,[MobjType]::Shadows)
    if(-not ($shadow.Flags -band [MobjFlags]::Shadow)){throw 'Spectre fixture lacks Shadow flag.'}
    $directory=Get-DoomSaveDirectory $SaveRoot $hash;$savePath=Join-Path $directory 'fuzz-fixture.pds'
    $save=Write-DoomSaveState $game $savePath $hash 'Fuzz visual fixture, not campaign evidence'
    $archive=Get-DoomReplaySavePath $directory $save.Sha256;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($archive));Copy-Item -LiteralPath $savePath -Destination $archive
    $game=New-DoomGameFromSave (Read-DoomSaveState $archive $hash) $content
    $graphics=New-DoomAutomapGraphics $content;$graphics.Discovery.DiscoverMap($game.World.ConsolePlayer)
    $checkpoints=[Collections.Generic.List[object]]::new();$checkpoints.Add((Get-DoomReplayCheckpoint $game 0))
    $inputs=[Collections.Generic.List[object]]::new();$timers=[Collections.Generic.List[object]]::new()
    for($tic=1;$tic -le 350;$tic++){
        $inputs.Add(@(0,0,0,0));$null=$game.Update($cmd);$graphics.Discovery.DiscoverMap($game.World.ConsolePlayer)
        if($tic -in 35,70,82,90,98,105,120,128,129,140,175,210,245,280,315,350){
            $checkpoints.Add((Get-DoomReplayCheckpoint $game $tic));$timers.Add(@{Tic=$tic;Invisibility=$game.World.ConsolePlayer.Powers[[int][PowerType]::Invisibility];Health=$game.World.ConsolePlayer.Health})
        }
    }
    $transition=@{Tic=0;State='Level';Episode=1;Map=1}
    if($timers[-1].Invisibility -ne 0 -or $timers[-1].Health -le 0){throw 'Fixture failed to reach living power expiry.'}
    $data=@{Format='pwshDoom.InputReplay';Version=3;WadSha256=$hash;Skill=3;Episode=1;Map=1;ContinueCampaign=$true;
        InputCommands=$inputs.ToArray();ControlEvents=@(@{Tic=0;Action='LoadGame';SaveHash=$save.Sha256});Checkpoints=$checkpoints.ToArray();Transitions=@($transition,$transition);
        SourceFingerprint=(Get-DoomReplaySourceFingerprint);FixtureTimers=$timers.ToArray();
        Meaning='Explicit save fixture: grant invisibility, shorten its timer to 210, set player and actor health to999, and spawn a Spectre 96 units ahead in E1M1. Then load through normal replay control and run 350 idle commands. Shows fuzz and power expiry; not a pickup route or campaign completion.'}
    $null=Write-DoomInputReplay $Output $data
    "Created 350-command fuzz fixture with $($checkpoints.Count) checkpoints."
}finally{if($content){$content.Dispose()}}
