#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[Parameter(Mandatory)][string]$SaveRoot,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';if((Test-Path $Output) -or (Test-Path $SaveRoot)){throw 'Use fresh fixture and save paths.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
foreach($file in 'InputReplay','GameHost','SnapshotTransport','SaveState','SaveSlots','AutomapSession'){. "$PSScriptRoot/../src/$file.ps1"}
$content=$null
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$hash=(Get-FileHash $Wad).Hash
    $directory=Get-DoomSaveDirectory $SaveRoot $hash
    $inputs=[Collections.Generic.List[object]]::new();$controls=[Collections.Generic.List[object]]::new()
    $points=[Collections.Generic.List[object]]::new();$states=[Collections.Generic.List[object]]::new();$mapCommands=[Collections.Generic.List[object]]::new()
    $segments=@(@{Name='Damage';Damage=100;Bonus=0;Strength=0;Suit=0;Length=140},
        @{Name='Bonus';Damage=0;Bonus=100;Strength=0;Suit=0;Length=140},
        @{Name='Berserk';Damage=0;Bonus=0;Strength=640;Suit=0;Length=175},
        @{Name='Radiation';Damage=0;Bonus=0;Strength=0;Suit=210;Length=245})
    $tic=0
    foreach($segment in $segments){
        $o=[GameOptions]::new();$o.GameMode=$content.Wad.GameMode;$o.GameVersion=$content.Wad.GameVersion;$o.MissionPack=$content.Wad.MissionPack
        $game=[DoomGame]::new($content,$o);$cmd=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$cmd[$i]=[TicCmd]::new()}
        $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($cmd)
        $p=$game.World.ConsolePlayer;$p.DamageCount=$segment.Damage;$p.BonusCount=$segment.Bonus
        $p.Powers[[int][PowerType]::Strength]=$segment.Strength;$p.Powers[[int][PowerType]::IronFeet]=$segment.Suit
        $save=Write-DoomSaveState $game (Join-Path $directory ($segment.Name+'.pds')) $hash ('Palette visual fixture: '+$segment.Name)
        $archive=Get-DoomReplaySavePath $directory $save.Sha256;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($archive));Copy-Item -LiteralPath $save.Path -Destination $archive
        $game=New-DoomGameFromSave (Read-DoomSaveState $archive $hash) $content
        $graphics=New-DoomAutomapGraphics $content;$graphics.Discovery.DiscoverMap($game.World.ConsolePlayer)
        $controls.Add(@{Tic=$tic;Action='LoadGame';SaveHash=$save.Sha256});$segment.StartTic=$tic;$segment.InitialPalette=[Renderer]::GetPaletteNumber($game.World.ConsolePlayer)
        # A load replaces any checkpoint at this boundary, just as the host does.
        if($points.Count -gt 0 -and $points[-1].Tic -eq $tic){$points.RemoveAt($points.Count-1)}
        $points.Add((Get-DoomReplayCheckpoint $game $tic))
        for($step=1;$step -le $segment.Length;$step++){
            # Show each active effect in the automap as well as the world.
            $mask=if($step -in 15,45){1}else{0}
            if($mask){$mapCommands.Add(@{Tic=$tic;Mask=$mask})}
            Set-DoomAutomapCommand $game $mask
            $inputs.Add(@(0,0,0,0));$null=$game.Update($cmd);$tic++;$graphics.Discovery.DiscoverMap($game.World.ConsolePlayer)
            $p=$game.World.ConsolePlayer
            $states.Add(@{Tic=$tic;Segment=$segment.Name;PaletteNumber=[Renderer]::GetPaletteNumber($p);Automap=$game.World.AutoMap.Visible;Health=$p.Health})
            if($step%14 -eq 0 -or $step -eq $segment.Length){$points.Add((Get-DoomReplayCheckpoint $game $tic))}
        }
        if([Renderer]::GetPaletteNumber($p) -ne 0 -or $p.Health -le 0){throw 'Fixture did not reach living base-palette restoration.'}
        $segment.EndTic=$tic
    }
    $data=@{Format='pwshDoom.InputReplay';Version=4;WadSha256=$hash;Skill=3;Episode=1;Map=1;ContinueCampaign=$true;
        InputCommands=$inputs.ToArray();ControlEvents=$controls.ToArray();AutomapCommands=$mapCommands.ToArray();Checkpoints=$points.ToArray();
        Transitions=@(@{Tic=0;State='Level';Episode=1;Map=1})+@($controls|ForEach-Object {@{Tic=$_.Tic;State='Level';Episode=1;Map=1}});
        SourceFingerprint=(Get-DoomReplaySourceFingerprint);FixtureStates=$states.ToArray();FixtureSegments=$segments;
        Meaning='Explicit palette save fixtures, not ordinary damage/pickup or campaign completion evidence. Load separate damage, bonus, late berserk and radiation timer states; advance normal idle commands through base-palette restoration, opening/closing automap in each segment.'}
    $null=Write-DoomInputReplay $Output $data
    "Created $tic-command palette fixture with $($points.Count) checkpoints."
}finally{if($content){$content.Dispose()}}
