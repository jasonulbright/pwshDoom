#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Replay,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [Parameter(Mandatory)][string]$Output
)
$ErrorActionPreference='Stop'
$Replay=[IO.Path]::GetFullPath($Replay)
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report destination.'}
$Wad=(Resolve-Path -LiteralPath $Wad).Path
$wadHash=(Get-FileHash -LiteralPath $Wad).Hash
$replayHash=(Get-FileHash -LiteralPath $Replay).Hash
$replayData=Get-Content -LiteralPath $Replay -Raw|ConvertFrom-Json
if($replayData.Format -cne 'pwshDoom.InputReplay' -or $replayData.WadSha256 -cne $wadHash){
    throw 'Replay format or IWAD hash does not match.'
}
if($replayData.ExitReason -ne 'Error' -or -not $replayData.Error){
    throw 'This focused regression expects the retained interrupted human attempt.'
}

$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"
. "$PSScriptRoot/../src/SnapshotTransport.ps1"
. "$PSScriptRoot/../src/AutomapSession.ps1"

$content=$null
$failure=$null
$failureTic=$null
$actualCheckpoints=[Collections.Generic.List[object]]::new()
$transitions=[Collections.Generic.List[object]]::new()
$consumed=0
$game=$null
try {
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode
    $options.GameVersion=$content.Wad.GameVersion
    $options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options)
    $commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt $commands.Length;$i++){$commands[$i]=[TicCmd]::new()}
    $expectedByTic=@{}
    foreach($checkpoint in $replayData.Checkpoints){$expectedByTic[[int]$checkpoint.Tic]=$checkpoint}
    $game.DeferedInitNew([GameSkill]([int]$replayData.Skill-1),$replayData.Episode,$replayData.Map)
    $null=$game.Update($commands)
    if($expectedByTic.ContainsKey(0)){$actualCheckpoints.Add((Get-DoomReplayCheckpoint $game 0))}
    $previousState=''
    $previousEpisode=0
    $previousMap=0
    foreach($entry in $replayData.InputCommands){
        $tic=$consumed+1
        for($i=0;$i -lt $commands.Length;$i++){$commands[$i].Clear()}
        $commands[0].ForwardMove=[sbyte][int]$entry[0]
        $commands[0].SideMove=[sbyte][int]$entry[1]
        $commands[0].AngleTurn=[int16][int]$entry[2]
        $commands[0].Buttons=[byte][int]$entry[3]
        try{$null=$game.Update($commands)}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$failureTic=$tic;break}
        $consumed++

        $state=$game.State.ToString()
        $episode=[int]$game.Options.Episode
        $map=[int]$game.Options.Map
        if($state -ne $previousState -or $episode -ne $previousEpisode -or $map -ne $previousMap){
            $transitions.Add(@{Tic=$tic;State=$state;Episode=$episode;Map=$map})
            $previousState=$state;$previousEpisode=$episode;$previousMap=$map
        }
        if($expectedByTic.ContainsKey($tic)){
            $actual=Get-DoomReplayCheckpoint $game $tic
            $actualCheckpoints.Add($actual)
        }
    }
} catch {
    if(-not $failure){$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$failureTic=$consumed}
} finally {
    if($content){$content.Dispose()}
}

$expectedStateCheckpoints=@(foreach($checkpoint in $replayData.Checkpoints){
    $copy=@{}
    if($checkpoint -is [Collections.IDictionary]){
        foreach($key in $checkpoint.Keys){if($key -ne 'AutomapSha256'){$copy[$key]=$checkpoint[$key]}}
    }else{
        foreach($property in $checkpoint.PSObject.Properties){if($property.Name -ne 'AutomapSha256'){$copy[$property.Name]=$property.Value}}
    }
    $copy
})
$actualStateCheckpoints=@(foreach($checkpoint in $actualCheckpoints){
    $copy=@{}
    if($checkpoint -is [Collections.IDictionary]){
        foreach($key in $checkpoint.Keys){if($key -ne 'AutomapSha256'){$copy[$key]=$checkpoint[$key]}}
    }else{
        foreach($property in $checkpoint.PSObject.Properties){if($property.Name -ne 'AutomapSha256'){$copy[$property.Name]=$property.Value}}
    }
    $copy
})
$comparison=Compare-DoomReplayCheckpoints $expectedStateCheckpoints $actualStateCheckpoints $consumed
$finalState=$null
if($game){
    $player=$game.World.ConsolePlayer
    $finalState=@{
        State=$game.State.ToString();Episode=$game.Options.Episode;Map=$game.Options.Map
        LevelTime=$game.World.LevelTime;Health=$player.Health;Armor=$player.ArmorPoints
        Weapon=$player.ReadyWeapon.ToString();Position=@($player.Mobj.X.Data,$player.Mobj.Y.Data,$player.Mobj.Z.Data,$player.Mobj.Angle.Data)
    }
}
$commit=(git -C (Split-Path $PSScriptRoot) rev-parse HEAD).Trim()
$currentFingerprint=Get-DoomReplaySourceFingerprint
$result=[ordered]@{
    Format='pwshDoom.RecordedHumanCrashReplay';Version=1;FinishedUtc=[DateTime]::UtcNow.ToString('o')
    SourceCommit=$commit;CurrentSourceFingerprint=$currentFingerprint
    RecordedSourceFingerprint=$replayData.SourceFingerprint
    SourceFingerprintMatches=$currentFingerprint -ceq $replayData.SourceFingerprint
    ReplayPath=[IO.Path]::GetRelativePath((Split-Path $PSScriptRoot),$Replay).Replace('\','/')
    ReplaySha256=$replayHash;WadSha256=$wadHash;RecordedExitReason=$replayData.ExitReason
    RecordedError=$replayData.Error;RecordedCommands=$replayData.InputCommands.Count
    ConsumedCommands=$consumed;FailureTic=$failureTic;Failure=$failure
    Checkpoints=$comparison;AutomapCheckpointsCompared=$false
    RecordedAutomapCommandCount=@($replayData.AutomapCommands).Count
    Transitions=$transitions.ToArray();FinalState=$finalState
    Passed=($null -eq $failure -and $consumed -eq $replayData.InputCommands.Count -and $comparison.Matched)
    Meaning='Replays the complete saved human command stream through the current in-process PowerShell game simulation. It checks the recorded gameplay and render-snapshot checkpoints while excluding the separately recorded automap state/commands, and verifies that the original chainsaw-crash command stream completes without a simulation exception. It does not run renderer workers, terminal I/O, or audio, and it is not a human campaign completion.'
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Output))
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $Output -Encoding utf8NoBOM
if(-not $result.Passed){throw "Recorded human replay failed at tic $failureTic after $consumed commands."}
"PASS: replayed $consumed human commands; matched $($comparison.Checked) saved checkpoints (matched=$($comparison.Matched))."
