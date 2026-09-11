#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1";. "$PSScriptRoot/../src/SaveState.ps1"
Set-StrictMode -Version Latest
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new();$runs=[Collections.Generic.List[object]]::new()
$directory=Join-Path "$PSScriptRoot/../local" ('save-session-'+[guid]::NewGuid().ToString('N'))
function Assert-Edge([string]$Name,[bool]$Condition){$checks.Add(@{Name=$Name;Passed=$Condition});if(-not $Condition){throw $Name}}
function Graph-Text($Game){return (ConvertTo-DoomSaveGraph $Game|ConvertTo-Json -Depth 12 -Compress)}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$wadHash=(Get-FileHash $Wad).Hash
    $commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    foreach($case in 'Death','E1Finale','E2Finale','E3Finale','E4Finale'){
        foreach($c in $commands){$c.Clear()}
        $episode=if($case -eq 'Death'){1}else{[int]::Parse($case.Substring(1,1))};$map=if($case -eq 'Death'){1}else{8}
        $o=[GameOptions]::new();$o.GameMode=$content.Wad.GameMode;$o.GameVersion=$content.Wad.GameVersion;$o.MissionPack=$content.Wad.MissionPack
        $game=[DoomGame]::new($content,$o);$game.InitNew([GameSkill]::Medium,$episode,$map)
        if($case -eq 'Death'){$game.World.ThingInteraction.DamageMobj($game.World.ConsolePlayer.Mobj,$null,$null,10000)}
        else{$game.DoCompleted()}
        $null=$game.Update($commands)
        if($case -eq 'Death'){Assert-Edge 'Death fixture reached dead state' ($game.World.ConsolePlayer.PlayerState -eq [PlayerState]::Dead)}
        else{Assert-Edge "$case fixture reached finale" ($game.State -eq [GameState]::Finale);$game.Finale.Count=$game.Finale.Text.Length*$game.Finale.TextSpeed+$game.Finale.TextWait-8}
        $path=Join-Path $directory ($case+'.pds');$save=Write-DoomSaveState $game $path $wadHash $case
        $loaded=New-DoomGameFromSave (Read-DoomSaveState $path $wadHash) $content
        Assert-Edge "$case graph matches on load" ((Graph-Text $game) -ceq (Graph-Text $loaded))
        for($tic=0;$tic -lt 16;$tic++){
            foreach($c in $commands){$c.Clear()};if($case -eq 'Death' -and $tic -eq 0){$commands[0].Buttons=2}
            $null=$game.Update($commands);$null=$loaded.Update($commands)
        }
        Assert-Edge "$case continuation graph matches" ((Graph-Text $game) -ceq (Graph-Text $loaded))
        if($case -eq 'Death'){Assert-Edge 'Death save continues through use and rebirth' ($loaded.World.ConsolePlayer.PlayerState -eq [PlayerState]::Live -and $loaded.World.ConsolePlayer.Health -eq 100)}
        else{Assert-Edge "$case text advanced to end-art stage" ($loaded.Finale.Stage -eq 1)}
        $runs.Add(@{Case=$case;Save=$save;Checkpoint=Get-DoomReplayCheckpoint $loaded 16})
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Runs=$runs.ToArray();HarnessSha256=(Get-FileHash $PSCommandPath).Hash;SourceSha256=(Get-FileHash "$PSScriptRoot/../src/SaveState.ps1").Hash;Meaning='Lethal-damage and direct episode-completion fixtures on actual E1M1 and E1/E2/E3/E4M8 worlds. Finale clocks are moved near the text/end-art boundary. Save/load continuation checks, not campaign playthrough or finale pixel-fidelity evidence.'}|ConvertTo-Json -Depth 12|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($checks.Count) session-edge save checks."
