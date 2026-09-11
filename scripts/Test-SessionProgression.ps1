#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Route="$PSScriptRoot/../results/e1m1-route.json",[string]$Output="$PSScriptRoot/../local/session-route.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$original=Get-Content -LiteralPath $Route -Raw|ConvertFrom-Json
if($original.WadSha256 -ne (Get-FileHash -LiteralPath $Wad).Hash){throw 'Route IWAD mismatch.'}
$log=[Collections.Generic.List[object]]::new();$transitions=[Collections.Generic.List[object]]::new();$content=$null;$failure=$null;$passed=$false
try {
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$o=[GameOptions]::new()
    $o.GameMode=$content.Wad.GameMode;$o.GameVersion=$content.Wad.GameVersion;$o.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$o);$cmds=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$cmds[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($cmds)
    $prior='';$exitInventory=$null
    for($tic=0;$tic -lt $original.InputCommands.Count+700;$tic++){
        $cmd=$cmds[0];$cmd.Clear()
        if($tic -lt $original.InputCommands.Count){$input=$original.InputCommands[$tic];$cmd.ForwardMove=$input[0];$cmd.SideMove=$input[1];$cmd.AngleTurn=$input[2];$cmd.Buttons=$input[3]}
        elseif(($tic-$original.InputCommands.Count) -in 35,70,105){$cmd.Buttons=2}
        $log.Add(@($cmd.ForwardMove,$cmd.SideMove,$cmd.AngleTurn,$cmd.Buttons));$null=$game.Update($cmds)
        $key="$($game.State):$($o.Episode):$($o.Map)";$p=$game.World.ConsolePlayer
        if($key -ne $prior){
            $transitions.Add(@{Tic=$log.Count;State=$game.State.ToString();Episode=$o.Episode;Map=$o.Map;Health=$p.Health;Ammo=$p.Ammo.Clone();Armor=$p.ArmorPoints;Kills=$p.KillCount})
            if($game.State -eq [GameState]::Intermission){$exitInventory=@($p.Health,$p.ArmorPoints)+$p.Ammo.Clone()}
            if($o.Map -eq 2){
                if((@($p.Health,$p.ArmorPoints)+$p.Ammo -join ',') -ne ($exitInventory -join ',')){throw 'Inventory changed between E1M1 exit and E1M2 spawn.'}
            }
            $prior=$key
        }
        if($game.State -eq [GameState]::Level -and $o.Map -eq 2 -and $game.World.LevelTime -ge 71){$passed=$true;break}
    }
    if(-not $passed){throw 'Ordinary-input session did not enter and advance E1M2.'}
}catch{$failure=$_.ToString();throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Passed=$passed;Error=$failure;ContinueCampaign=$true;Episode=1;Map=1;Skill=3;
        WadSha256=$original.WadSha256;BaseRouteSha256=(Get-FileHash -LiteralPath $Route).Hash;InputCommands=$log.ToArray();Transitions=$transitions.ToArray();
        Meaning='Unpaced ordinary-input E1M1 completion, use-button intermission advancement, and 71 level tics in E1M2. Existing route inputs followed by three spaced use presses and idle tics. No world/player edits or direct exits. E1M2 completion is not claimed.'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($log.Count) session commands; E1M1 -> intermission -> E1M2 with inventory preserved."
