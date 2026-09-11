#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([ValidateSet('Load','Reference')][string]$Mode='Load',[Parameter(Mandatory)][string]$Save,
    [Parameter(Mandatory)][int]$StartCommand,[int]$ContinueTics=140,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/save-process-bundle-$PID.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1";. "$PSScriptRoot/../src/SaveState.ps1"
$content=$null;$failure=$null;$samples=[Collections.Generic.List[object]]::new();$graphHash=$null;$loadMs=$null
$recordedChecks=[Collections.Generic.List[object]]::new();$expected=@{}
function Check-RecordedBoundary([int]$Tic){
    if($expected.ContainsKey($Tic)){
        $actual=Get-DoomReplayCheckpoint $game $Tic;$match=$actual.Sha256 -ceq $expected[$Tic]
        $recordedChecks.Add(@{Tic=$Tic;Expected=$expected[$Tic];Actual=$actual.Sha256;Passed=$match})
        if(-not $match){throw "Original recorded checkpoint diverged at $Tic."}
    }
}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$wadHash=(Get-FileHash $Wad).Hash
    $input=Read-DoomInputReplay "$PSScriptRoot/../results/input-session-replay.json" $wadHash
    foreach($point in $input.Checkpoints){$expected[[int]$point.Tic]=$point.Sha256}
    $commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    if($Mode -eq 'Load'){
        $watch=[Diagnostics.Stopwatch]::StartNew();$saved=Read-DoomSaveState $Save $wadHash;$game=New-DoomGameFromSave $saved $content;$loadMs=$watch.Elapsed.TotalMilliseconds;$first=$StartCommand
        if($game.GameTic -ne $StartCommand+1){throw 'Save does not correspond to the declared ordinary-input boundary.'}
    }else{
        $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
        $game=[DoomGame]::new($content,$options);$game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands);$first=0
    }
    Check-RecordedBoundary $first
    for($i=$first;$i -lt $StartCommand+$ContinueTics;$i++){
        foreach($c in $commands){$c.Clear()}
        if($i -lt $input.InputCommands.Count){$v=$input.InputCommands[$i];$c=$commands[0];$c.ForwardMove=$v[0];$c.SideMove=$v[1];$c.AngleTurn=$v[2];$c.Buttons=$v[3]}
        $null=$game.Update($commands)
        Check-RecordedBoundary ($i+1)
        if($i -ge $StartCommand -and (($i-$StartCommand)%35 -eq 34 -or $i -eq $StartCommand+$ContinueTics-1)){$samples.Add((Get-DoomReplayCheckpoint $game ($i+1)))}
    }
    $json=ConvertTo-DoomSaveGraph $game|ConvertTo-Json -Depth 12 -Compress
    $graphHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json)))
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Mode=$Mode;ProcessId=$PID;PowerShell=$PSVersionTable.PSVersion.ToString();Error=$failure;Save=$Save;SaveSha256=(Get-FileHash $Save).Hash;StartCommand=$StartCommand;ContinueTics=$ContinueTics;LoadMs=$loadMs;Samples=$samples.ToArray();RecordedChecks=$recordedChecks.ToArray();GraphSha256=$graphHash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;SourceSha256=(Get-FileHash "$PSScriptRoot/../src/SaveState.ps1").Hash;Meaning='Run this harness in separate PowerShell processes for Load and Reference, then compare checkpoints and final graph hashes. Reference plays the full prefix from a fresh game; Load reconstructs the recorded boundary and plays only the suffix. Each also verifies original recorded checkpoints encountered along its portion.'}|ConvertTo-Json -Depth 10|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
"Completed $Mode in process $PID."
