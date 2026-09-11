#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay="$PSScriptRoot/../results/input-session-replay.json",[ValidateRange(1,140)][int]$EveryTics=35)
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Choose a fresh output path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/numeric-discovery-$PID.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
. "$PSScriptRoot/FrameCodec.ps1"
$checks=[Collections.Generic.List[object]]::new();$poses=[Collections.Generic.List[object]]::new();$checkpoints=[Collections.Generic.List[object]]::new()
$failure=$null;$content=$null;$angleCases=0;$angleErrors=0;$angleTimes=[Collections.Generic.List[double]]::new();$numericTimes=[Collections.Generic.List[double]]::new();$comparison=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $random=[Random]::new(20260911)
    $points=@(for($i=0;$i -lt 2048;$i++){,@([int]$random.NextInt64(-2147483648L,2147483648L),[int]$random.NextInt64(-2147483648L,2147483648L),[int]$random.NextInt64(-2147483648L,2147483648L),[int]$random.NextInt64(-2147483648L,2147483648L))})
    foreach($x in -2147483648,-65536,-513,-512,-511,-1,0,1,511,512,513,65536,2147483647){foreach($y in -2147483648,-65536,-1,0,1,65536,2147483647){$points+=,@(0,0,$x,$y)}}
    foreach($point in $points){
        $expected=$null;$actual=$null;$oldError=$false;$newError=$false
        $watch=[Diagnostics.Stopwatch]::StartNew()
        try{$expected=[Geometry]::PointToAngle([Fixed]::new($point[0]),[Fixed]::new($point[1]),[Fixed]::new($point[2]),[Fixed]::new($point[3])).Data}catch{$oldError=$true}
        $angleTimes.Add($watch.Elapsed.TotalMilliseconds);$watch.Restart()
        try{$actual=[Geometry]::PointToAngleData($point[0],$point[1],$point[2],$point[3])}catch{$newError=$true}
        $numericTimes.Add($watch.Elapsed.TotalMilliseconds)
        if($oldError -ne $newError -or (-not $oldError -and $expected -ne $actual)){throw "Angle mismatch at $($point -join ','): $expected / $actual; errors $oldError / $newError"}
        $angleCases++;if($oldError){$angleErrors++}
    }
    Check 'Random and octant/overflow/slope-boundary point angles match the retained implementation' ($angleCases -eq 2139)
    $recorded=Read-DoomInputReplay $Replay (Get-FileHash $Wad).Hash
    $content=[GameContent]::new(@('-iwad',$Wad));$o=[GameOptions]::new();$o.GameMode=$content.Wad.GameMode;$o.GameVersion=$content.Wad.GameVersion;$o.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$o);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $screen=[DrawScreen]::new($content.Wad,320,200);$renderer=[ThreeDRenderer]::new($content,$screen,7)
    $checkpointTics=@{};foreach($point in $recorded.Checkpoints){$checkpointTics[[int]$point.Tic]=$true}
    for($tic=0;$tic -le $recorded.InputCommands.Count;$tic++){
        if([int]$game.State -eq 0 -and ($tic%$EveryTics -eq 0 -or $tic -eq $recorded.InputCommands.Count)){
            $world=$game.World;$p=$world.ConsolePlayer;$flags=@($world.Map.Lines|ForEach-Object Flags)
            $valid=$world.ValidCount;$sectorValid=@($world.Map.Sectors|ForEach-Object ValidCount)
            for($i=0;$i -lt $flags.Count;$i++){$world.Map.Lines[$i].Flags=$flags[$i] -band (-bnot 256)}
            $renderer.Render($p,[Fixed]::One)
            $expected=@(for($i=0;$i -lt $flags.Count;$i++){if($world.Map.Lines[$i].Flags -band 256){$i}})
            $world.ValidCount=$valid;for($i=0;$i -lt $sectorValid.Count;$i++){$world.Map.Sectors[$i].ValidCount=$sectorValid[$i]}
            for($i=0;$i -lt $flags.Count;$i++){$world.Map.Lines[$i].Flags=$flags[$i] -band (-bnot 256)}
            $watch.Restart();$renderer.DiscoverMap($p);$ms=$watch.Elapsed.TotalMilliseconds
            $actual=@(for($i=0;$i -lt $flags.Count;$i++){if($world.Map.Lines[$i].Flags -band 256){$i}})
            Check "Tic $tic E$($o.Episode)M$($o.Map) discovery matches full renderer" (($actual -join ',') -ceq ($expected -join ','))
            $poses.Add(@{Tic=$tic;Episode=$o.Episode;Map=$o.Map;Position=@($p.Mobj.X.Data,$p.Mobj.Y.Data,$p.Mobj.Angle.Data);ExpectedLines=$expected;ActualLines=$actual;DiscoveryMs=$ms})
            for($i=0;$i -lt $flags.Count;$i++){$world.Map.Lines[$i].Flags=$flags[$i]}
        }
        if($checkpointTics.ContainsKey($tic)){$checkpoints.Add((Get-DoomReplayCheckpoint $game $tic))}
        if($tic -eq $recorded.InputCommands.Count){break}
        $cmd=$commands[0];$entry=$recorded.InputCommands[$tic];$cmd.Clear();$cmd.ForwardMove=$entry[0];$cmd.SideMove=$entry[1];$cmd.AngleTurn=$entry[2];$cmd.Buttons=$entry[3];$null=$game.Update($commands)
    }
    $comparison=Compare-DoomReplayCheckpoints $recorded.Checkpoints $checkpoints.ToArray() $recorded.InputCommands.Count
    Check 'Reference-renderer sampling leaves all legacy campaign checkpoints intact' ($comparison.Matched -and $comparison.Checked -eq 8)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();AngleCases=$angleCases;MatchingAngleExceptions=$angleErrors;PointSeed=20260911;OldPointMs=(Get-SampleStats $angleTimes.ToArray());NumericPointMs=(Get-SampleStats $numericTimes.ToArray());EveryTics=$EveryTics;Poses=$poses.ToArray();CheckpointComparison=$comparison;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;BundleSha256=(Get-FileHash $bundle).Hash;ReplaySha256=(Get-FileHash $Replay).Hash;Meaning='Exact adopted point-angle comparison and sampled moving-route discovery against the retained full renderer, restoring reference-only validity counters and flags before continuing simulation. This does not qualify every map or reference buffer-overflow limits. Timing includes harness instrumentation and is not a live frame-rate benchmark.'}|ConvertTo-Json -Depth 8|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($checks.Count) numeric discovery checks, $angleCases angle cases."
