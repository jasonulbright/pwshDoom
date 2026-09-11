#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1";. "$PSScriptRoot/../src/SaveState.ps1"
Set-StrictMode -Version Latest
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new();$evidence=[ordered]@{}
$directory=Join-Path "$PSScriptRoot/../local" ('save-specials-'+[guid]::NewGuid().ToString('N'))
function Assert-Special([string]$Name,[bool]$Condition){$checks.Add(@{Name=$Name;Passed=$Condition});if(-not $Condition){throw $Name}}
function Get-GraphText($Game){return (ConvertTo-DoomSaveGraph $Game|ConvertTo-Json -Depth 12 -Compress)}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$wadHash=(Get-FileHash $Wad).Hash
    $o=[GameOptions]::new();$o.GameMode=$content.Wad.GameMode;$o.GameVersion=$content.Wad.GameVersion;$o.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$o);$game.InitNew([GameSkill]::Medium,1,1);$w=$game.World;$player=$w.ConsolePlayer.Mobj
    $sectors=@($w.Map.Sectors|Where-Object {$null -eq $_.SpecialData -and $_.CeilingHeight.Data-$_.FloorHeight.Data -ge 64*65536}|Select-Object -First 3)
    if($sectors.Count -ne 3){throw 'Fixture needs three unoccupied mover sectors.'}
    $line=@($w.Map.Lines|Where-Object {$null -ne $_.FrontSide}|Select-Object -First 1)[0]
    $lineIndex=[array]::IndexOf($w.Map.Lines,$line);$line.Tag=4242;$originalTexture=$line.FrontSide.TopTexture;$line.FrontSide.TopTexture=1
    $w.Specials.StartButton($line,[ButtonPosition]::Top,$originalTexture,35)
    $w.LightingChange.SpawnFireFlicker($sectors[0])
    $ceiling=[CeilingMove]::new($w);$ceiling.Sector=$sectors[1];$ceiling.Type=[CeilingMoveType]::CrushAndRaise
    $ceiling.TopHeight=$ceiling.Sector.CeilingHeight;$ceiling.BottomHeight=$ceiling.Sector.FloorHeight+[Fixed]::FromInt(8)
    $ceiling.Speed=[Fixed]::One;$ceiling.Crush=$true;$ceiling.Direction=-1;$ceiling.Tag=4242
    $ceiling.Sector.SpecialData=$ceiling;$w.Thinkers.Add($ceiling);$w.SectorAction.AddActiveCeiling($ceiling)
    $platform=[Platform]::new($w);$platform.Sector=$sectors[2];$platform.Type=[PlatformType]::PerpetualRaise
    $platform.High=$platform.Sector.FloorHeight;$platform.Low=$platform.High-[Fixed]::FromInt(16);$platform.Speed=[Fixed]::One
    $platform.Wait=7;$platform.Status=[PlatformState]::InStasis;$platform.OldStatus=[PlatformState]::Down;$platform.Tag=4243
    $platform.Sector.SpecialData=$platform;$w.Thinkers.Add($platform);$platform.ThinkerState=[ThinkerState]::InStasis;$w.SectorAction.AddActivePlatform($platform)
    $missile=$w.ThingAllocation.SpawnMobj($player.X,$player.Y,$player.Z+[Fixed]::FromInt(32),[MobjType]::Troopshot)
    $missile.Target=$player;$missile.Tracer=$player;$player.Target=$missile;$w.ConsolePlayer.Attacker=$missile;$sectors[0].SoundTarget=$missile
    $evidence.Setup=@{ButtonLine=$lineIndex;LightSector=$sectors[0].Number;CeilingSector=$sectors[1].Number;PlatformSector=$sectors[2].Number;ButtonTimer=35;PlatformStatus='InStasis';CeilingDirection=-1;MissileType='Troopshot'}
    $savePath=Join-Path $directory 'specials.pds';$evidence.Save=Write-DoomSaveState $game $savePath $wadHash 'Specials fixture'
    $wire=Read-DoomSaveState $savePath $wadHash;$loaded=New-DoomGameFromSave $wire $content;$lw=$loaded.World
    Assert-Special 'Entire fixture graph matches on load' ((Get-GraphText $game) -ceq (Get-GraphText $loaded))
    $lm=$lw.ConsolePlayer.Attacker;$lp=$lw.ConsolePlayer.Mobj
    Assert-Special 'Actor target/tracer cycles retain loaded player identity' ([object]::ReferenceEquals($lm.Target,$lp) -and [object]::ReferenceEquals($lm.Tracer,$lp) -and [object]::ReferenceEquals($lp.Target,$lm))
    Assert-Special 'Sector sound target retains loaded actor identity' ([object]::ReferenceEquals($lw.Map.Sectors[$sectors[0].Number].SoundTarget,$lm))
    $lc=@($lw.SectorAction.activeCeilings|Where-Object {$null -ne $_ -and $_.Tag -eq 4242})[0]
    $lplat=@($lw.SectorAction.activePlatforms|Where-Object {$null -ne $_ -and $_.Tag -eq 4243})[0]
    Assert-Special 'Mover registries and sector links share their loaded thinkers' ([object]::ReferenceEquals($lc.Sector.SpecialData,$lc) -and [object]::ReferenceEquals($lplat.Sector.SpecialData,$lplat))
    Assert-Special 'Stasis platform survives with its resume state' ($lplat.ThinkerState -eq [ThinkerState]::InStasis -and $lplat.Status -eq [PlatformState]::InStasis -and $lplat.OldStatus -eq [PlatformState]::Down)
    $commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    for($tic=1;$tic -le 70;$tic++){
        if($tic -eq 10){$null=$w.SectorAction.CeilingCrushStop($line);$null=$lw.SectorAction.CeilingCrushStop($lw.Map.Lines[$lineIndex])}
        if($tic -eq 20){$w.SectorAction.ActivateInStasisCeiling($line);$lw.SectorAction.ActivateInStasisCeiling($lw.Map.Lines[$lineIndex]);$w.SectorAction.ActivateInStasis(4243);$lw.SectorAction.ActivateInStasis(4243)}
        $null=$game.Update($commands);$null=$loaded.Update($commands)
        if($tic -in 10,20,35,70){Assert-Special "Full graph matches after special continuation tic $tic" ((Get-GraphText $game) -ceq (Get-GraphText $loaded))}
        if($tic -eq 10){Assert-Special 'Ceiling actually entered stasis' ($lc.Direction -eq 0 -and $lc.ThinkerState -eq [ThinkerState]::InStasis)}
        if($tic -eq 20){Assert-Special 'Ceiling and platform actually resumed' ($lc.Direction -eq -1 -and $lplat.Status -eq [PlatformState]::Down -and $lplat.ThinkerState -eq [ThinkerState]::Active)}
        if($tic -eq 35){Assert-Special 'Pending switch expires and restores its texture' ($lw.Specials.ButtonList[0].Timer -eq 0 -and $lw.Map.Lines[$lineIndex].FrontSide.TopTexture -eq $originalTexture)}
    }
    $evidence.FinalCheckpoint=Get-DoomReplayCheckpoint $loaded 70
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Evidence=$evidence;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;SourceSha256=(Get-FileHash "$PSScriptRoot/../src/SaveState.ps1").Hash;Meaning='Explicit E1M1 data/behavior fixtures, not a human campaign route: pending switch, fire flicker, crusher, stasis platform and cyclic actor/sector links. Both games then run identical updates, including stop/resume actions.'}|ConvertTo-Json -Depth 12|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($checks.Count) special-save checks."
