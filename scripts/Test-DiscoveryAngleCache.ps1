#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Replay,[Parameter(Mandatory)][string]$Output,
    [ValidateSet('Dictionary','Indexed')][string]$Candidate='Dictionary',
    [ValidateRange(1,1260000)][int]$MaxCommands=1200,[string]$ReferenceReport,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh cache experiment report.'}
$owned=Join-Path "$PSScriptRoot/../local" ('discovery-cache-'+[guid]::NewGuid().ToString('N'))
$original=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$owned/baseline.ps1"
$builder=if($Candidate -eq 'Indexed'){"$PSScriptRoot/experiments/Add-IndexedDiscoveryCache.ps1"}else{"$PSScriptRoot/experiments/Add-DiscoveryAngleCache.ps1"}
$bundle=& $builder -Bundle $original -Output "$owned/candidate.ps1"
. $bundle
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$reference=Read-DoomInputReplay $Replay (Get-FileHash $Wad).Hash
$prior=if($ReferenceReport){Get-Content $ReferenceReport -Raw|ConvertFrom-Json}else{$null}
if($prior -and ($prior.Error -or $prior.ReplaySha256 -cne (Get-FileHash $Replay).Hash -or $prior.BaselineBundleSha256 -cne (Get-FileHash $original).Hash)){throw 'Reference source/replay mismatch.'}
$content=$null;$failure=$null;$completed=0;$verification=$null;$freshComparisons=0;$priorComparisons=0
$samples=[Collections.Generic.List[object]]::new();$points=[Collections.Generic.List[object]]::new()
function Mapped-Hash($Lines){
    $bits=[byte[]]::new($Lines.Length)
    for($j=0;$j -lt $bits.Length;$j++){$bits[$j]=[byte](($Lines[$j].Flags -band 256) -ne 0)}
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bits))
}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($j=0;$j -lt 4;$j++){$commands[$j]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]([int]$reference.Skill-1),$reference.Episode,$reference.Map);$null=$game.Update($commands)
    $renderers=@([ThreeDRenderer]::new($content,[DrawScreen]::new($content.Wad,320,200),7),[ThreeDRenderer]::new($content,[DrawScreen]::new($content.Wad,320,200),7))
    $renderers[1].CacheDiscoveryAngles=$true
    $renderers[0].DiscoverMap($game.World.ConsolePlayer)
    $expected=@{};foreach($point in $reference.Checkpoints){$expected[[int]$point.Tic]=$true}
    $points.Add((Get-DoomReplayCheckpoint $game 0))
    for($i=0;$i -lt [Math]::Min($MaxCommands,$reference.InputCommands.Count);$i++){
        $entry=$reference.InputCommands[$i];$cmd=$commands[0];$cmd.Clear()
        $cmd.ForwardMove=$entry[0];$cmd.SideMove=$entry[1];$cmd.AngleTurn=$entry[2];$cmd.Buttons=$entry[3]
        $null=$game.Update($commands);$completed++
        $durations=[double[]]::new(2);$hashes=[string[]]::new(2);$cacheEntries=0
        if([int]$game.State -eq 0){
            $lines=$game.World.Map.Lines;$saved=[int[]]::new($lines.Length)
            for($j=0;$j -lt $lines.Length;$j++){$saved[$j]=[int]$lines[$j].Flags}
            $order=if($i%2 -eq 0){@(0,1)}else{@(1,0)}
            foreach($which in $order){
                for($j=0;$j -lt $lines.Length;$j++){$lines[$j].Flags=$saved[$j] -band (-bnot 256)}
                $watch=[Diagnostics.Stopwatch]::StartNew();$renderers[$which].DiscoverMap($game.World.ConsolePlayer)
                $durations[$which]=$watch.Elapsed.TotalMilliseconds
                $hashes[$which]=Mapped-Hash $lines
            }
            if($hashes[0] -cne $hashes[1]){throw "Fresh discovery differs at command $completed"};$freshComparisons++
            $cacheEntries=if($Candidate -eq 'Indexed'){@($renderers[1].DiscoveryAngleReady|Where-Object {$_}).Count}else{$renderers[1].DiscoveryAngles.Count}
            # Both passes agree; union current discoveries with the prior map.
            for($j=0;$j -lt $lines.Length;$j++){$lines[$j].Flags=[int]$lines[$j].Flags -bor $saved[$j]}
        }
        $cumulative=Mapped-Hash $game.World.Map.Lines
        if($prior){if($i -ge $prior.Samples.Count -or $cumulative -cne $prior.Samples[$i].MappedSha256){throw "Prior cumulative mapping differs at $completed"};$priorComparisons++}
        $samples.Add(@{Command=$completed;State=[int]$game.State;Episode=$game.Options.Episode;Map=$game.Options.Map;
            First=if($i%2 -eq 0){'Baseline'}else{'Cache'};BaselineMs=$durations[0];CacheMs=$durations[1];
            BaselineFreshSha256=$hashes[0];CacheFreshSha256=$hashes[1];CumulativeMappedSha256=$cumulative;CachedVertices=$cacheEntries})
        if($expected.ContainsKey($completed)){$points.Add((Get-DoomReplayCheckpoint $game $completed))}
    }
    if($points[-1].Tic -ne $completed){$points.Add((Get-DoomReplayCheckpoint $game $completed))}
    $verification=Compare-DoomReplayCheckpoints $reference.Checkpoints $points.ToArray() $completed
    if(-not $verification.Matched){throw 'Cache experiment differs from original gameplay checkpoints.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    $timed=@($samples|Where-Object State -eq 0)
    @{Error=$failure;Candidate=$Candidate;Commands=$completed;FreshMappingComparisons=$freshComparisons;PriorMappingComparisons=$priorComparisons;
        CacheSetupSamplesMs=if($Candidate -eq 'Indexed' -and $renderers){$renderers[1].DiscoveryCacheSetupSamples.ToArray()}else{@()};
        BaselineBundleSha256=(Get-FileHash $original).Hash;ExecutedBundleSha256=(Get-FileHash $bundle).Hash;BuilderSha256=(Get-FileHash $builder).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        ReplaySha256=(Get-FileHash $Replay).Hash;WadSha256=(Get-FileHash $Wad).Hash;ReferenceReportSha256=if($ReferenceReport){(Get-FileHash $ReferenceReport).Hash}else{$null};
        BaselineMs=(Get-SampleStats ([double[]]$timed.BaselineMs));CacheMs=(Get-SampleStats ([double[]]$timed.CacheMs));
        Samples=$samples.ToArray();ReplayVerification=$verification;Checkpoints=$points.ToArray();OwnedBundle=$bundle;
        Meaning='Experimental owned bundle only. Per-view paired discovery calls alternate order; mapped flags are cleared before each call, freshly discovered bitsets compared, then unioned with prior flags. Optional reference also checks every cumulative hash. Cache validity clears on every call; no cross-tic reuse. Indexed candidate resolves vertex identity once per map, then uses arrays and a dedicated segment call. Timing includes cold calls, cache clear and any lazy per-map index construction; excludes renderer creation/flag reset/hash. Both paths include experimental selection branches. Not loaded-host or display FPS.'}|
        ConvertTo-Json -Depth 10|Set-Content -LiteralPath $Output
}
if($failure){throw $failure}
"PASS: $completed commands, $freshComparisons fresh mapping comparisons, $priorComparisons prior mapping comparisons."
