#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [int]$MaxTics=4200,[string]$Output="$PSScriptRoot/../results/e1m1-route.json")
$ErrorActionPreference='Stop'
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
Set-StrictMode -Version Latest
$content=$null;$commandsLog=[Collections.Generic.List[object]]::new();$trace=[Collections.Generic.List[object]]::new();$passed=$false
# Waypoints are a test driver, not changes to player state. All movement, turns,
# attacks, doors and the exit pass through the same TicCmd interface as keyboard input.
$route=@(@(1056,-3000),@(1280,-3000),@(1312,-2610),@(1420,-2496),@(1700,-2496),@(1950,-2520),@(2350,-2630),@(2560,-2688),@(2820,-2816),@(3008,-3072),@(3220,-3240),@(3008,-3510),@(3008,-3840),@(3008,-4200),@(3008,-4510),@(3008,-4768),@(2944,-4768))
$waypoint=0;$reachedAt=0;$tic=0;$game=$null
try {
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    for($tic=0;$tic -lt $MaxTics;$tic++) {
        $world=$game.World;$player=$world.ConsolePlayer;$mo=$player.Mobj
        $x=$mo.X.Data/65536.0;$y=$mo.Y.Data/65536.0;$angle=$mo.Angle.Data*(2*[Math]::PI/4294967296.0)
        $target=$route[$waypoint];$dx=$target[0]-$x;$dy=$target[1]-$y;$distance=[Math]::Sqrt($dx*$dx+$dy*$dy)
        if($distance -lt 18 -and $waypoint -lt $route.Count-1){$waypoint++;$reachedAt=$tic;Write-Host "Waypoint $waypoint at tic $tic";continue}
        $aim=[Math]::Atan2($dy,$dx);$attack=$false
        $cap=$world.Thinkers.Cap;$enemy=$cap.Next;$nearest=240.0
        while(-not [object]::ReferenceEquals($enemy,$cap)) {
            if($enemy -is [Mobj] -and ($enemy.Flags -band [MobjFlags]::CountKill) -and $enemy.Health -gt 0) {
                $ex=$enemy.X.Data/65536.0-$x;$ey=$enemy.Y.Data/65536.0-$y;$ed=[Math]::Sqrt($ex*$ex+$ey*$ey)
                if($ed -lt $nearest -and $player.Ammo[0] -gt 0 -and $world.VisibilityCheck.CheckSight($mo,$enemy)){$nearest=$ed;$aim=[Math]::Atan2($ey,$ex);$attack=$true}
            }
            $enemy=$enemy.Next
        }
        $delta=($aim-$angle+3*[Math]::PI)%(2*[Math]::PI)-[Math]::PI
        $cmd=$commands[0];$cmd.Clear();$cmd.AngleTurn=[int16][Math]::Clamp([Math]::Round($delta*65536/(2*[Math]::PI)),-2048,2048)
        if([Math]::Abs($delta) -lt 0.18 -and -not $attack){$cmd.ForwardMove=if($distance -gt 70){25}else{8}}
        if($attack -and [Math]::Abs($delta) -lt .08){$cmd.Buttons=1}
        if(($tic%105) -eq 0){$cmd.Buttons=$cmd.Buttons -bor 2}
        $commandsLog.Add(@($cmd.ForwardMove,$cmd.SideMove,$cmd.AngleTurn,$cmd.Buttons))
        $null=$game.Update($commands)
        if(($tic%35) -eq 0){$trace.Add(@{Tic=$tic;Waypoint=$waypoint;X=$x;Y=$y;Health=$player.Health;Kills=$player.KillCount;Ammo=$player.Ammo[0]})}
        if($game.State -eq [GameState]::Intermission){$passed=$true;break}
        if($player.Health -le 0){throw "Player died at waypoint $waypoint."}
        if($tic-$reachedAt -gt 500){throw "Route stalled at waypoint $waypoint ($x,$y), target $($target -join ',')."}
    }
    if(-not $passed){throw 'Route did not reach the exit within its tic budget.'}
    "PASS: E1M1 spawn to exit, $tic driver iterations, $($commandsLog.Count) simulation commands, $($game.World.ConsolePlayer.KillCount) kills."
} catch {[Console]::Error.WriteLine($_.ScriptStackTrace);throw}
finally {
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Passed=$passed;DriverIterations=$tic;SimulationCommands=$commandsLog.Count;Route=$route;
        Trace=$trace.ToArray();InputCommands=$commandsLog.ToArray();WadSha256=(Get-FileHash $Wad).Hash;
        Meaning='Unpaced E1M1 HMP navigation/combat test using TicCmd only. No teleporting, direct damage, noclip, god mode, direct special activation, or state edits.'} |
        ConvertTo-Json -Depth 7 | Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
