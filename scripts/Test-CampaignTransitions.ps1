#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Output="$PSScriptRoot/../local/campaign-transitions.json",[switch]$AllowFailures)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$checks=[Collections.Generic.List[object]]::new();$content=$null
function Check-Transition([string]$Name,$Actual,$Expected){
    $a=$Actual|ConvertTo-Json -Compress -Depth 5;$e=$Expected|ConvertTo-Json -Compress -Depth 5
    $checks.Add(@{Name=$Name;Actual=$Actual;Expected=$Expected;Passed=$a -ceq $e})
}
try {
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    # Isolated routing fixtures reuse a loaded world and vary only routing inputs.
    # This is deliberately not a claim that any of these maps was played through.
    $returns=@(4,6,7,3)
    foreach($episode in 1..4){
        foreach($map in 1..9){
            $options.Episode=$episode;$options.Map=$map;$game.World.SecretExit=$false
            if($map -ne 8){Check-Transition "E${episode}M$map normal destination" $game.GetNextIntermissionMap() $(if($map -eq 9){$returns[$episode-1]}else{$map+1})}
        }
        $options.Map=@(3,5,6,2)[$episode-1];$game.World.SecretExit=$true
        Check-Transition "Episode $episode secret destination" $game.GetNextIntermissionMap() 9
        $options.Map=8;$game.World.SecretExit=$false;$game.DoCompleted()
        Check-Transition "Episode $episode completion state" $game.State.ToString() 'Finale'
        if($game.State -eq [GameState]::Finale){$finale=$game.Finale}else{$finale=[Finale]::new($options)}
        Check-Transition "Episode $episode finale flat" $finale.Flat @('FLOOR4_8','SFLR6_1','MFLR8_4','MFLR8_3')[$episode-1]
        $expectedLines=[DoomInfo]::Strings."E${episode}TEXT".ToString().Replace("`r",'').Split("`n")
        for($line=0;$line -lt $expectedLines.Length;$line++){$expectedLines[$line]=$expectedLines[$line].Trim()}
        Check-Transition "Episode $episode finale text" $finale.Text ($expectedLines -join "`n")
    }
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $p=$game.World.ConsolePlayer;$p.Health=73;$p.ArmorPoints=42;$p.ArmorType=1;$p.Ammo[0]=37;$p.WeaponOwned[2]=$true;$p.Ammo[1]=11;$p.Cards[0]=$true
    $game.DoCompleted();Check-Transition 'E1M1 par is 30 seconds in tics' $options.IntermissionInfo.ParTime 1050
    Check-Transition 'Exit clears keys' $p.Cards[0] $false
    $oldWorld=$game.World
    for($tic=0;$tic -lt 350 -and $game.State -eq [GameState]::Intermission;$tic++){
        $commands[0].Clear();if($tic -in 1,4,8){$commands[0].Buttons=1};$null=$game.Update($commands)
    }
    Check-Transition 'Intermission advances to E1M2' @($game.State.ToString(),$options.Episode,$options.Map) @('Level',1,2)
    Check-Transition 'Map transition creates a fresh world' ([object]::ReferenceEquals($oldWorld,$game.World)) $false
    Check-Transition 'Health armor weapons ammo carry over' @($p.Health,$p.ArmorPoints,$p.Ammo[0],$p.WeaponOwned[2],$p.Ammo[1]) @(73,42,37,$true,11)
    $p.DidSecret=$true;$game.World.SecretExit=$false;$game.DoCompleted()
    Check-Transition 'Intermission retains prior secret visit' $options.IntermissionInfo.DidSecret $true
    $commands[0].Clear();$game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $p=$game.World.ConsolePlayer;$p.WeaponOwned[2]=$true;$p.Ammo[0]=99;$oldWorld=$game.World
    # A lethal-damage fixture exercises the engine's death -> use -> rebirth path.
    $game.World.ThingInteraction.DamageMobj($p.Mobj,$null,$null,10000)
    Check-Transition 'Lethal damage sets dead state' $p.PlayerState.ToString() 'Dead'
    $commands[0].Buttons=2;$null=$game.Update($commands);$commands[0].Clear();$null=$game.Update($commands)
    Check-Transition 'Use after death recreates the current level' @($game.State.ToString(),$options.Map,[object]::ReferenceEquals($oldWorld,$game.World)) @('Level',1,$false)
    Check-Transition 'Respawn restores health and pistol ammunition' @($p.Health,$p.Ammo[0],$p.WeaponOwned[2]) @(100,50,$false)
} finally {
    $failures=@($checks|Where-Object {-not $_.Passed})
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');WadSha256=(Get-FileHash -LiteralPath $Wad).Hash;Checks=$checks.ToArray();Failures=$failures.Count;
        Sources=@('src/ManagedDoom/Doom/Game/DoomGame.sb.ps1','src/ManagedDoom/Doom/Intermission/Finale.sb.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../$_").Hash}});
        Meaning='Isolated controller/routing/finale fixtures plus real intermission input advancement and E1M2 world creation. Direct exit and inventory setup are test fixtures, not map playthrough evidence.'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
    if($null -ne $content){$content.Dispose()}
}
$failures|ForEach-Object {Write-Host "FAIL: $($_.Name)"}
"$($checks.Count) checks, $($failures.Count) failures; $Output"
if($failures.Count -and -not $AllowFailures){throw 'Campaign transition regression failed.'}
