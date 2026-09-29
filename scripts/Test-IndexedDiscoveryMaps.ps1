#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh map comparison report.'}
$owned=Join-Path "$PSScriptRoot/../local" ('discovery-maps-'+[guid]::NewGuid().ToString('N'))
$original=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$owned/baseline.ps1"
$builder="$PSScriptRoot/experiments/Add-IndexedDiscoveryCache.ps1"
$bundle=& $builder -Bundle $original -Output "$owned/candidate.ps1"
. $bundle
$content=$null;$failure=$null;$maps=0;$cases=[Collections.Generic.List[object]]::new()
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    $screens=@([DrawScreen]::new($content.Wad,320,200),[DrawScreen]::new($content.Wad,320,200))
    $renderers=@([ThreeDRenderer]::new($content,$screens[0],7),[ThreeDRenderer]::new($content,$screens[1],7))
    $renderers[0].CacheDiscoveryAngles=$false
    $renderers[0].CacheStationaryDiscovery=$false
    $renderers[1].CacheDiscoveryAngles=$true
    $sentinel=[byte[]]::new(64000);[Array]::Fill($sentinel,[byte]77)
    $commands=[TicCmd[]]::new(4);for($j=0;$j -lt 4;$j++){$commands[$j]=[TicCmd]::new()}
    foreach($episode in 1..4){foreach($map in 1..9){
        $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
        $game=[DoomGame]::new($content,$options);$game.DeferedInitNew([GameSkill]::Medium,$episode,$map);$null=$game.Update($commands)
        $world=$game.World;$player=$world.ConsolePlayer;$angle=$player.Mobj.Angle;$lines=$world.Map.Lines
        $originalFlags=[int[]]::new($lines.Length);for($j=0;$j -lt $lines.Length;$j++){$originalFlags[$j]=[int]$lines[$j].Flags}
        foreach($degrees in 0,90,180,270){
            $player.Mobj.Angle=$angle+[Angle]::FromDegree($degrees)
            $hashes=[string[]]::new(2);$counts=[int[]]::new(2)
            foreach($which in 0,1){
                for($j=0;$j -lt $lines.Length;$j++){$lines[$j].Flags=$originalFlags[$j] -band (-bnot 256)}
                [Array]::Copy($sentinel,$screens[$which].Data,64000)
                $valid=$world.ValidCount;$sectors=@($world.Map.Sectors|ForEach-Object ValidCount)
                $renderers[$which].DiscoverMap($player)
                if($valid -ne $world.ValidCount -or ($sectors -join ',') -cne (@($world.Map.Sectors|ForEach-Object ValidCount) -join ',')){throw "E${episode}M$map heading $degrees changes renderer validity counters"}
                if(-not [Linq.Enumerable]::SequenceEqual[byte]($sentinel,$screens[$which].Data)){throw 'Discovery changes framebuffer pixels'}
                $bits=[byte[]]::new($lines.Length)
                for($j=0;$j -lt $lines.Length;$j++){
                    if(([int]$lines[$j].Flags -band (-bnot 256)) -ne ($originalFlags[$j] -band (-bnot 256))){throw 'Non-discovery line flags changed'}
                    $bits[$j]=[byte](($lines[$j].Flags -band 256) -ne 0);$counts[$which]+=$bits[$j]
                }
                $hashes[$which]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bits))
            }
            if($hashes[0] -cne $hashes[1]){throw "E${episode}M$map heading $degrees differs"}
            if(-not [object]::ReferenceEquals($renderers[1].DiscoveryIndexedMap,$world.Map)){throw 'Cached indices belong to a different map'}
            $candidate=$renderers[1]
            $passBeforeRepeat=$candidate.DiscoveryCachePasses
            $hitsBeforeRepeat=$candidate.DiscoveryCacheHits
            $candidate.DiscoverMap($player)
            $warmupPasses=0
            if($candidate.DiscoveryCacheHits -eq $hitsBeforeRepeat){
                if($candidate.DiscoveryCachePasses -ne ($passBeforeRepeat+1)){throw "E${episode}M$map heading $degrees did neither a cache hit nor a discovery pass"}
                $warmupPasses=1
                $candidate.DiscoverMap($player)
            }
            if($candidate.DiscoveryCacheHits -ne ($hitsBeforeRepeat+1) -or $candidate.DiscoveryCachePasses -ne ($passBeforeRepeat+$warmupPasses)){throw "E${episode}M$map heading $degrees did not reuse the stable discovery result"}
            $repeatBits=[byte[]]::new($lines.Length)
            for($j=0;$j -lt $lines.Length;$j++){$repeatBits[$j]=[byte](($lines[$j].Flags -band 256) -ne 0)}
            $repeatHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($repeatBits))
            if($repeatHash -cne $hashes[1]){throw "E${episode}M$map heading $degrees changed mapped lines on cache reuse"}
            $cases.Add(@{Episode=$episode;Map=$map;Heading=$degrees;BaselineSha256=$hashes[0];CacheSha256=$hashes[1];MappedLines=$counts[1];FramebufferUnchanged=$true;CountersUnchanged=$true;OtherFlagsUnchanged=$true;StableViewReuse=$true;WarmupPasses=$warmupPasses})
        }
        $maps++;"Compared E${episode}M$map"
    }}
    if($maps -ne 36 -or $cases.Count -ne 144 -or $renderers[1].DiscoveryCacheSetupSamples.Count -ne 36 -or $renderers[1].DiscoveryCacheHits -ne 144){throw 'Incomplete map/rebuild or stable-view cache coverage'}

    function Assert-DiscoveryStateInvalidation([string]$Name,[object]$Target,[object]$Original,[scriptblock]$Mutate,[scriptblock]$Restore,[ThreeDRenderer]$Renderer,[Player]$Player){
        $hits=$Renderer.DiscoveryCacheHits;$passes=$Renderer.DiscoveryCachePasses
        $null=& $Mutate $Target $Original
        $Renderer.DiscoverMap($Player)
        if($Renderer.DiscoveryCacheHits -ne $hits -or $Renderer.DiscoveryCachePasses -ne ($passes+1)){throw "Discovery incorrectly reused state after changing $Name"}
        $passes++
        $null=& $Restore $Target $Original
        $Renderer.DiscoverMap($Player)
        if($Renderer.DiscoveryCacheHits -ne $hits -or $Renderer.DiscoveryCachePasses -ne ($passes+1)){throw "Discovery incorrectly reused state after restoring $Name"}
        $passes++
        $Renderer.DiscoverMap($Player)
        if($Renderer.DiscoveryCacheHits -ne ($hits+1) -or $Renderer.DiscoveryCachePasses -ne $passes){throw "Discovery did not reuse restored $Name state"}
        return @{Name=$Name;InvalidatedOnChange=$true;InvalidatedOnRestore=$true;ReusedAfterStabilizing=$true}
    }
    function Assert-DiscoveryViewInvalidation([string]$Name,[object]$Target,[object]$Original,[scriptblock]$Change,[scriptblock]$Restore,[ThreeDRenderer]$Renderer,[Player]$Player){
        $hits=$Renderer.DiscoveryCacheHits;$passes=$Renderer.DiscoveryCachePasses
        $null=& $Change $Target $Original
        $Renderer.DiscoverMap($Player)
        if($Renderer.DiscoveryCacheHits -ne $hits -or $Renderer.DiscoveryCachePasses -ne ($passes+1)){throw "Discovery incorrectly reused a changed $Name"}
        $passes++
        $null=& $Restore $Target $Original
        $Renderer.DiscoverMap($Player)
        if($Renderer.DiscoveryCacheHits -ne $hits -or $Renderer.DiscoveryCachePasses -ne ($passes+1)){throw "Discovery incorrectly reused a restored $Name"}
        $passes++
        $Renderer.DiscoverMap($Player)
        if($Renderer.DiscoveryCacheHits -ne $hits -or $Renderer.DiscoveryCachePasses -ne ($passes+1)){throw "Discovery failed to refresh the restored $Name signature"}
        $passes++
        $Renderer.DiscoverMap($Player)
        if($Renderer.DiscoveryCacheHits -ne ($hits+1) -or $Renderer.DiscoveryCachePasses -ne $passes){throw "Discovery did not reuse the stable $Name"}
        return @{Name=$Name;InvalidatedOnChange=$true;InvalidatedOnRestore=$true;ReusedAfterStabilizing=$true}
    }
    function Measure-DiscoveryBatch([ThreeDRenderer]$Renderer,[Player]$Player,[int]$Repeats){
        $watch=[Diagnostics.Stopwatch]::StartNew()
        for($i=0;$i -lt $Repeats;$i++){$Renderer.DiscoverMap($Player)}
        $watch.Stop()
        return $watch.Elapsed.TotalMilliseconds/$Repeats
    }

    $cache=$renderers[1]
    if($cache.DiscoveryRelevantSectorIndices.Count -eq 0 -or $cache.DiscoveryRelevantSideIndices.Count -eq 0){throw 'Final view did not retain its relevant discovery sectors/sides'}
    $testSector=$world.Map.Sectors[$cache.DiscoveryRelevantSectorIndices[0]]
    $testSide=$world.Map.Sides[$cache.DiscoveryRelevantSideIndices[0]]
    $invalidationCases=[Collections.Generic.List[object]]::new()
    $originalFloor=$testSector.FloorHeight
    $invalidationCases.Add((Assert-DiscoveryStateInvalidation -Name 'sector floor height' -Target $testSector -Original $originalFloor -Mutate {param($s,$old)$s.FloorHeight=$s.FloorHeight+[Fixed]::FromInt(1)} -Restore {param($s,$old)$s.FloorHeight=$old} -Renderer $cache -Player $player))
    $originalCeiling=$testSector.CeilingHeight
    $invalidationCases.Add((Assert-DiscoveryStateInvalidation -Name 'sector ceiling height' -Target $testSector -Original $originalCeiling -Mutate {param($s,$old)$s.CeilingHeight=$s.CeilingHeight+[Fixed]::FromInt(1)} -Restore {param($s,$old)$s.CeilingHeight=$old} -Renderer $cache -Player $player))
    $originalFloorFlat=$testSector.FloorFlat
    $invalidationCases.Add((Assert-DiscoveryStateInvalidation -Name 'sector floor flat' -Target $testSector -Original $originalFloorFlat -Mutate {param($s,$old)$s.FloorFlat=$old+1} -Restore {param($s,$old)$s.FloorFlat=$old} -Renderer $cache -Player $player))
    $originalCeilingFlat=$testSector.CeilingFlat
    $invalidationCases.Add((Assert-DiscoveryStateInvalidation -Name 'sector ceiling flat' -Target $testSector -Original $originalCeilingFlat -Mutate {param($s,$old)$s.CeilingFlat=$old+1} -Restore {param($s,$old)$s.CeilingFlat=$old} -Renderer $cache -Player $player))
    $originalLightLevel=$testSector.LightLevel
    $invalidationCases.Add((Assert-DiscoveryStateInvalidation -Name 'sector light level' -Target $testSector -Original $originalLightLevel -Mutate {param($s,$old)$s.LightLevel=$old+1} -Restore {param($s,$old)$s.LightLevel=$old} -Renderer $cache -Player $player))
    $originalMiddleTexture=$testSide.MiddleTexture
    $invalidationCases.Add((Assert-DiscoveryStateInvalidation -Name 'side middle texture' -Target $testSide -Original $originalMiddleTexture -Mutate {param($s,$old)$s.MiddleTexture=$old+1} -Restore {param($s,$old)$s.MiddleTexture=$old} -Renderer $cache -Player $player))
    $unseenSector=$null
    for($i=0;$i -lt $world.Map.Sectors.Length;$i++){
        if($i -notin $cache.DiscoveryRelevantSectorIndices){$unseenSector=$world.Map.Sectors[$i];break}
    }
    if($null -ne $unseenSector){
        $unseenLight=$unseenSector.LightLevel;$hits=$cache.DiscoveryCacheHits;$passes=$cache.DiscoveryCachePasses
        $unseenSector.LightLevel=$unseenLight+1;$cache.DiscoverMap($player)
        if($cache.DiscoveryCacheHits -ne ($hits+1) -or $cache.DiscoveryCachePasses -ne $passes){throw 'Off-view sector lighting unnecessarily invalidated discovery'}
        $unseenSector.LightLevel=$unseenLight;$hits=$cache.DiscoveryCacheHits;$cache.DiscoverMap($player)
        if($cache.DiscoveryCacheHits -ne ($hits+1) -or $cache.DiscoveryCachePasses -ne $passes){throw 'Restoring off-view lighting unnecessarily invalidated discovery'}
        $invalidationCases.Add(@{Name='off-view sector light';IgnoredUnrelatedChange=$true;ReusedAfterRestore=$true})
    }
    $mappedLine=$null
    foreach($line in $world.Map.Lines){if(($line.Flags -band [LineFlags]::Mapped) -ne 0){$mappedLine=$line;break}}
    if($null -eq $mappedLine){throw 'No mapped line available for reset invalidation check'}
    $originalLineFlags=[int]$mappedLine.Flags
    $hitsBeforeLineReset=$cache.DiscoveryCacheHits;$passesBeforeLineReset=$cache.DiscoveryCachePasses
    $mappedLine.Flags=[LineFlags]($originalLineFlags -band (-bnot 256))
    $cache.DiscoverMap($player)
    if($cache.DiscoveryCacheHits -ne $hitsBeforeLineReset -or $cache.DiscoveryCachePasses -ne ($passesBeforeLineReset+1) -or (($mappedLine.Flags -band [LineFlags]::Mapped) -eq 0)){throw 'Discovery reused a reset mapped-line flag or failed to restore the visible line'}
    $passesBeforeLineReset++
    $cache.DiscoverMap($player)
    if($cache.DiscoveryCacheHits -ne ($hitsBeforeLineReset+1) -or $cache.DiscoveryCachePasses -ne $passesBeforeLineReset){throw 'Discovery did not reuse after restoring the mapped-line flag'}
    $invalidationCases.Add(@{Name='mapped-line reset';InvalidatedOnChange=$true;InvalidatedOnRestore=$false;ReusedAfterStabilizing=$true})

    $playerMobj=$player.Mobj;$originalX=$playerMobj.X;$originalAngle=$playerMobj.Angle
    $invalidationCases.Add((Assert-DiscoveryViewInvalidation -Name 'player position' -Target $playerMobj -Original $originalX -Change {param($m,$old)$m.X=$old+[Fixed]::FromInt(1)} -Restore {param($m,$old)$m.X=$old} -Renderer $cache -Player $player))
    $invalidationCases.Add((Assert-DiscoveryViewInvalidation -Name 'player angle' -Target $playerMobj -Original $originalAngle -Change {param($m,$old)$m.Angle=$old+[Angle]::FromDegree(1)} -Restore {param($m,$old)$m.Angle=$old} -Renderer $cache -Player $player))
    $originalFirstColumn=$screens[1].FirstColumn
    $invalidationCases.Add((Assert-DiscoveryViewInvalidation -Name 'viewport clipping' -Target $screens[1] -Original $originalFirstColumn -Change {param($screen,$old)$screen.FirstColumn=$old+1} -Restore {param($screen,$old)$screen.FirstColumn=$old} -Renderer $cache -Player $player))

    $baseline=$renderers[0]
    $baseline.CacheDiscoveryAngles=$true
    $baseline.CacheStationaryDiscovery=$false
    $baseline.DiscoverMap($player);$baseline.DiscoverMap($player)
    $cache.DiscoverMap($player)
    $benchmarkHitsStart=$cache.DiscoveryCacheHits
    $benchmarkPassesStart=$cache.DiscoveryCachePasses
    $baselineTimes=[Collections.Generic.List[double]]::new()
    $cachedTimes=[Collections.Generic.List[double]]::new()
    $benchmarkRepeats=20
    for($round=0;$round -lt 6;$round++){
        if(($round -band 1) -eq 0){
            $baselineTimes.Add((Measure-DiscoveryBatch $baseline $player $benchmarkRepeats))
            $cachedTimes.Add((Measure-DiscoveryBatch $cache $player $benchmarkRepeats))
        }else{
            $cachedTimes.Add((Measure-DiscoveryBatch $cache $player $benchmarkRepeats))
            $baselineTimes.Add((Measure-DiscoveryBatch $baseline $player $benchmarkRepeats))
        }
    }
    if($cache.DiscoveryCacheHits -ne ($benchmarkHitsStart+($benchmarkRepeats*6)) -or $cache.DiscoveryCachePasses -ne $benchmarkPassesStart){throw 'Stationary benchmark did not reuse every cached discovery call'}
    $baselineSorted=[double[]]$baselineTimes.ToArray();[Array]::Sort($baselineSorted)
    $cachedSorted=[double[]]$cachedTimes.ToArray();[Array]::Sort($cachedSorted)
    $medianIndex=[int][Math]::Floor(($baselineSorted.Length-1)/2)
    $p95Index=[int][Math]::Ceiling($baselineSorted.Length*0.95)-1
    $stationaryBenchmark=@{
        Map='E4M9';RepeatsPerBatch=$benchmarkRepeats;Batches=$baselineSorted.Length;CallsPerPath=$benchmarkRepeats*$baselineSorted.Length;
        BaselineIndexedAnglesMedianMsPerCall=$baselineSorted[$medianIndex];BaselineIndexedAnglesP95MsPerCall=$baselineSorted[$p95Index];BaselineSamplesMsPerCall=$baselineTimes.ToArray();
        CachedMedianMsPerCall=$cachedSorted[$medianIndex];CachedP95MsPerCall=$cachedSorted[[int][Math]::Ceiling($cachedSorted.Length*0.95)-1];CachedSamplesMsPerCall=$cachedTimes.ToArray();
        MedianSpeedup=$baselineSorted[$medianIndex]/[Math]::Max(0.000001,$cachedSorted[$medianIndex]);
        CacheHits=$cache.DiscoveryCacheHits-$benchmarkHitsStart;TraversalPassesDuringCachedBatches=$cache.DiscoveryCachePasses-$benchmarkPassesStart;
        Meaning='Alternating 20-call batches on one unchanged E4M9 view with no world updates. Both paths use indexed vertex angles; baseline disables only stationary reuse. Measures DiscoverMap method time, not simulation tics, rendering, terminal output, displayed frames or gameplay FPS.'
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Maps=$maps;Cases=$cases.ToArray();InvalidationCases=if($invalidationCases){$invalidationCases.ToArray()}else{@()};CacheReuseHits=if($renderers){$renderers[1].DiscoveryCacheHits}else{0};CacheTraversalPasses=if($renderers){$renderers[1].DiscoveryCachePasses}else{0};CacheSetupSamplesMs=if($renderers){$renderers[1].DiscoveryCacheSetupSamples.ToArray()}else{@()};StationaryBenchmark=$stationaryBenchmark;
        BaselineBundleSha256=(Get-FileHash $original).Hash;ExecutedBundleSha256=(Get-FileHash $bundle).Hash;BuilderSha256=(Get-FileHash $builder).Hash;
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;WadSha256=(Get-FileHash $Wad).Hash;OwnedBundle=$bundle;
        Meaning='All 36 Ultimate Doom map spawns at four synthetic headings. Clear discovery flags independently, compare full line bitsets, preserve framebuffer, world/sector validity counters and other flags. Repeat each stable view to verify a skip, and mutate every semantic cache input to verify invalidation. Reuse one candidate renderer across all maps to require rebuilds. No campaign completion, full-renderer buffer-limit parity, or FPS claim.'}|
        ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
}
if($failure){throw $failure}
"PASS: $maps maps, $($cases.Count) discovery cases."
