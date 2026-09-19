#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Replay,[Parameter(Mandatory)][string]$Output,[switch]$AllMaps,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh snapshot report.'}
$sources=@(foreach($path in @($PSCommandPath,"$PSScriptRoot/../src/GameHost.ps1","$PSScriptRoot/../src/SnapshotTransport.ps1","$PSScriptRoot/../src/InputReplay.ps1")){
    @{Path=[IO.Path]::GetRelativePath((Split-Path $PSScriptRoot),$path).Replace('\','/');Sha256=(Get-FileHash $path).Hash}
})
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/FrameCodec.ps1"
$wadHash=(Get-FileHash $Wad).Hash;$reference=Read-DoomInputReplay $Replay $wadHash
$content=$null;$failure=$null;$sampleIndex=0;$completed=0
$samples=[Collections.Generic.List[object]]::new();$points=[Collections.Generic.List[object]]::new();$transitions=[Collections.Generic.List[object]]::new()
$verification=$null
function Compare-Snapshot([string]$Label,[double]$Fraction){
    $watch=[Diagnostics.Stopwatch]::new()
    # Alternate order; retain every cold and warm observation without exclusions.
    foreach($kind in $(if($script:sampleIndex%2 -eq 0){@('Object','Direct')}else{@('Direct','Object')})){
        $watch.Restart()
        if($kind -eq 'Object'){$expected=ConvertTo-GameSnapshotBytes (New-GameRenderSnapshot $game $Fraction);$objectMs=$watch.Elapsed.TotalMilliseconds}
        else{$actual=Get-GameRenderSnapshotBytes $game $Fraction;$directMs=$watch.Elapsed.TotalMilliseconds}
    }
    if($actual -isnot [byte[]] -or -not [Linq.Enumerable]::SequenceEqual[byte]($expected,$actual)){throw "Snapshot bytes differ: $Label, fraction $Fraction."}
    $samples.Add(@{Label=$Label;Fraction=$Fraction;Bytes=$actual.Length;ObjectMilliseconds=$objectMs;DirectMilliseconds=$directMs;
        Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($actual))})
    $script:sampleIndex++
}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    if($AllMaps){
        for($episode=1;$episode -le 4;$episode++){for($map=1;$map -le 9;$map++){
            $game=[DoomGame]::new($content,$options);$commands[0].Clear()
            $game.DeferedInitNew([GameSkill]::Medium,$episode,$map);$null=$game.Update($commands)
            foreach($fraction in @(-.5,0,.25,.5,.75,1,1.5)){Compare-Snapshot "E${episode}M${map} initial" $fraction}
            for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
            foreach($fraction in @(0,1)){Compare-Snapshot "E${episode}M${map} 35 idle tics" $fraction}
        }}
    }
    $game=[DoomGame]::new($content,$options);$commands[0].Clear()
    $game.DeferedInitNew([GameSkill]([int]$reference.Skill-1),$reference.Episode,$reference.Map);$null=$game.Update($commands)
    $expectedPoints=@{};foreach($point in $reference.Checkpoints){$expectedPoints[[int]$point.Tic]=$true}
    if($expectedPoints.ContainsKey(0)){$points.Add((Get-DoomReplayCheckpoint $game 0))}
    $last=''
    for($i=0;$i -le $reference.InputCommands.Count;$i++){
        if($i -gt 0){
            $entry=$reference.InputCommands[$i-1];$cmd=$commands[0];$cmd.Clear()
            $cmd.ForwardMove=$entry[0];$cmd.SideMove=$entry[1];$cmd.AngleTurn=$entry[2];$cmd.Buttons=$entry[3]
            $null=$game.Update($commands);$completed++
            if($expectedPoints.ContainsKey($i)){$points.Add((Get-DoomReplayCheckpoint $game $i))}
        }
        $key="$($game.State):$($game.Options.Episode):$($game.Options.Map)";$changed=$key -cne $last
        if($changed){$transitions.Add(@{Command=$i;State=$key});$last=$key}
        if($i%35 -eq 0 -or $changed -or $i -eq $reference.InputCommands.Count){
            foreach($fraction in @(0,.25,.5,1)){Compare-Snapshot "Replay command $i $key" $fraction}
        }
    }
    $verification=Compare-DoomReplayCheckpoints $reference.Checkpoints $points.ToArray() $completed
    if(-not $verification.Matched -or $verification.Checked -ne $reference.Checkpoints.Count){throw 'Original gameplay checkpoints differ.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    $report=@{Error=$failure;FinishedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();WadSha256=$wadHash;
        Sources=$sources;BundleSha256=(Get-FileHash $bundle).Hash;ReplaySha256=(Get-FileHash $Replay).Hash;AllMaps=[bool]$AllMaps;
        Commands=$completed;ByteComparisons=$samples.Count;ReplayVerification=$verification;Transitions=$transitions.ToArray();Samples=$samples.ToArray();
        Meaning='Exact complete NumericV1 byte equality against unchanged object snapshot + serializer, all requested fractions. Alternating in-process order includes all samples and cold calls; these microbenchmarks are not full-host or displayed FPS. Fixed replay checks original selected-state checkpoints.'}
    if($samples.Count){$report.ObjectMs=Get-SampleStats ([double[]]$samples.ObjectMilliseconds);$report.DirectMs=Get-SampleStats ([double[]]$samples.DirectMilliseconds)}
    $report|ConvertTo-Json -Depth 8|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $($samples.Count) complete byte comparisons; $completed commands; $($verification.Checked) replay checkpoints."
