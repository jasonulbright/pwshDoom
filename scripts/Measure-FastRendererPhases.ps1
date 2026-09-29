#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [ValidateRange(1,4)][int]$Episode=1,
    [ValidateRange(1,9)][int]$Map=1,
    [ValidateRange(1,5)][int]$Skill=3,
    [ValidateRange(0,10000)][int]$Tics=0,
    [ValidateRange(1,100)][int]$WarmupFrames=3,
    [ValidateRange(1,100)][int]$Frames=20,
    [ValidateRange(1,32)][int]$WorkerCount=1,
    [switch]$TransportPrepared,
    [switch]$TransportLegacy,
    [switch]$TransportWorkerMasks,
    [switch]$BaselineWorkerActorScan,
    [switch]$LegacyWorkerProjection,
    [string]$Output="$PSScriptRoot/../results/renderer-phases.json"
)
$ErrorActionPreference='Stop'
if($TransportPrepared -and $TransportLegacy){throw 'Choose one transport mode.'}
if($TransportWorkerMasks -and (-not $TransportPrepared -or $TransportLegacy)){throw 'Worker masks require prepared transport.'}
if($LegacyWorkerProjection -and -not $TransportWorkerMasks){throw 'The projection-cache control requires worker masks.'}
if($BaselineWorkerActorScan -and -not $TransportWorkerMasks){throw 'The full-array actor-scan control requires worker masks.'}
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$outputPath=[IO.Path]::GetFullPath($Output)
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath))
. "$PSScriptRoot/FrameCodec.ps1"
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"
. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$content=$null;$failure=$null;$report=$null;$samples=[Collections.Generic.List[object]]::new();$workerProfiles=[Collections.Generic.List[object]]::new();$projectionPacketVersion=-1
function Get-PhaseStats([double[]]$Values){
    [double[]]$sorted=@($Values|Sort-Object)
    if($sorted.Length -eq 0){return @{Count=0;Mean=0.0;Median=0.0;P95=0.0;P99=0.0;Max=0.0}}
    return @{
        Count=$sorted.Length
        Mean=($sorted|Measure-Object -Average).Average
        Median=$sorted[[int][Math]::Floor(($sorted.Length-1)*.50)]
        P95=$sorted[[int][Math]::Floor(($sorted.Length-1)*.95)]
        P99=$sorted[[int][Math]::Floor(($sorted.Length-1)*.99)]
        Max=$sorted[-1]
    }
}
try{
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode
    $options.GameVersion=$content.Wad.GameVersion
    $options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options)
    $commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt $commands.Length;$i++){$commands[$i]=[TicCmd]::new()}
    # Match the user-facing Doom skill selection used by the campaign and
    # worker test scripts: 1=Baby through 5=Nightmare.
    $game.DeferedInitNew([GameSkill]($Skill-1),$Episode,$Map)
    $null=$game.Update($commands)
    for($i=0;$i -lt $Tics;$i++){$null=$game.Update($commands)}
    $camera=$game.World.ConsolePlayer.Mobj
    $context=New-FastRenderContext $content $game.World
    $snapshot=New-GameRenderSnapshot $game 1
    $snapshotPreparationSamples=[Collections.Generic.List[double]]::new()
    $maskPool=$null;$actorWorkerMaskStats=$null
    if($TransportPrepared -or $TransportLegacy){
        $pair=Get-GameRenderSnapshotPair $game
        [double[]]$previousValues=[double[]]::new($pair.Previous.Length/8);[Buffer]::BlockCopy($pair.Previous,0,$previousValues,0,$pair.Previous.Length)
        [double[]]$currentValues=[double[]]::new($pair.Current.Length/8);[Buffer]::BlockCopy($pair.Current,0,$currentValues,0,$pair.Current.Length)
        if($TransportWorkerMasks){
            $renderWorkers=[Collections.Generic.List[object]]::new()
            for([int]$i=0;$i -lt $WorkerCount;$i++){$renderWorkers.Add(@{Index=$i;First=[int][Math]::Floor($i*320.0/$WorkerCount);End=[int][Math]::Floor(($i+1)*320.0/$WorkerCount)})}
            $maskPool=@{Workers=$renderWorkers;SpriteAtlas=$context.SpriteAtlas;PlaneFineSine=$context.PlaneFineSine;TanToAngleTable=$context.TanToAngleTable}
        }
        [byte[]]$preparedBytes=$null
        for([int]$prepareIndex=0;$prepareIndex -lt ($WarmupFrames+$Frames);$prepareIndex++){
            $prepareWatch=[Diagnostics.Stopwatch]::StartNew()
            if($TransportLegacy){$preparedBytes=Get-InterpolatedSnapshotBytes $previousValues $currentValues 1 -DeferFuzzSort}
            else{$preparedBytes=Get-InterpolatedSnapshotBytes $previousValues $currentValues 1}
            if($TransportWorkerMasks){$preparedBytes=if($LegacyWorkerProjection){Add-GameRenderActorWorkerMasks $preparedBytes $maskPool -SkipProjectionCache}else{Add-GameRenderActorWorkerMasks $preparedBytes $maskPool}}
            $prepareWatch.Stop();$snapshotPreparationSamples.Add($prepareWatch.Elapsed.TotalMilliseconds)
        }
        $snapshot=Read-GameSnapshotBytes $preparedBytes $null
        if($TransportWorkerMasks){$projectionPacketVersion=if($snapshot.RenderProjectionPrepared){5}else{4}}
        if($TransportWorkerMasks){
            [int]$maskCount=$snapshot.Actors.Count;[long]$allPairs=[long]$maskCount*$WorkerCount;[long]$visiblePairs=0
            foreach($actor in $snapshot.Actors){for([int]$wi=0;$wi -lt $WorkerCount;$wi++){if(($actor.WorkerMask -band (1L -shl $wi)) -ne 0){$visiblePairs++}}}
            [int]$preparedProjectionActorCount=0
            if($snapshot.RenderProjectionPrepared){for([int]$actorIndex=0;$actorIndex -lt $maskCount;$actorIndex++){if($snapshot.RenderProjectionData[5*$actorIndex] -eq 1){$preparedProjectionActorCount++}}}
            $actorWorkerMaskStats=@{Actors=$maskCount;PossibleActorWorkerPairs=$allPairs;IncludedActorWorkerPairs=$visiblePairs;SkippedActorWorkerPairs=$allPairs-$visiblePairs;PreparedProjectionActors=$preparedProjectionActorCount}
        }
    }
    Set-GameRenderSnapshot $context $snapshot
    [int]$fuzzActorCount=@($snapshot.Actors|Where-Object {($_.Flags -band 0x40000) -ne 0}).Count
    for($workerIndex=0;$workerIndex -lt $WorkerCount;$workerIndex++){
        # Match the production worker's integer column partition exactly.
        [int]$first=[Math]::Floor($workerIndex*320.0/$WorkerCount)
        [int]$end=[Math]::Floor(($workerIndex+1)*320.0/$WorkerCount)
        $workerSnapshot=$snapshot;$workerDecodeSamples=[Collections.Generic.List[double]]::new()
        if($TransportWorkerMasks){
            $decodeState=$null
            for($decodeIndex=0;$decodeIndex -lt ($WarmupFrames+$Frames);$decodeIndex++){
                $decodeWatch=[Diagnostics.Stopwatch]::StartNew()
                $workerBit=if($BaselineWorkerActorScan){0L}else{1L -shl $workerIndex}
                $workerSnapshot=Read-GameSnapshotBytes $preparedBytes $decodeState $workerBit
                $decodeState=$workerSnapshot
                $decodeWatch.Stop()
                if($decodeIndex -ge $WarmupFrames){$workerDecodeSamples.Add($decodeWatch.Elapsed.TotalMilliseconds)}
            }
            $workerSnapshot.RenderWorkerBit=1L -shl $workerIndex
        }
        Set-GameRenderSnapshot $context $workerSnapshot
        for($i=0;$i -lt $WarmupFrames;$i++){Invoke-FastRender $context $first $end}
        $workerSamples=[Collections.Generic.List[object]]::new()
        for($i=0;$i -lt $Frames;$i++){
            $watch=[Diagnostics.Stopwatch]::StartNew()
            Invoke-FastRender $context $first $end
            $watch.Stop()
            $sample=@{
                WorkerIndex=$workerIndex;FirstColumn=$first;EndColumn=$end;Index=$i
                TotalMs=$watch.Elapsed.TotalMilliseconds
                GeometryMs=$context.Profile.GeometryMs
                ActorsMs=$context.Profile.ActorsMs
                WeaponMs=$context.Profile.WeaponMs
                HudMs=$context.Profile.HudMs
            }
            $workerSamples.Add($sample);$samples.Add($sample)
        }
        $workerPhases=[ordered]@{}
        foreach($name in 'TotalMs','GeometryMs','ActorsMs','WeaponMs','HudMs'){
            $workerPhases[$name]=Get-PhaseStats ([double[]]@($workerSamples|ForEach-Object {$_.$name}))
        }
        $workerProfiles.Add(@{
            WorkerIndex=$workerIndex;FirstColumn=$first;EndColumn=$end
            OutputSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]$context.Pixels))
            DecodeStats=Get-PhaseStats ([double[]]$workerDecodeSamples.ToArray())
            PhaseStats=$workerPhases
        })
    }
    if($TransportWorkerMasks){$null=$snapshot.Remove('RenderWorkerBit')}
    Set-GameRenderSnapshot $context $snapshot;Invoke-FastRender $context
    $frameSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([byte[]]$context.Pixels))
    $phases=@{}
    foreach($name in 'TotalMs','GeometryMs','ActorsMs','WeaponMs','HudMs'){
        $phases[$name]=Get-PhaseStats ([double[]]@($samples|ForEach-Object {$_.$name}))
    }
    $report=[ordered]@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o')
        Error=$null
        Episode=$Episode;Map=$Map;Skill=$Skill;SetupTics=$Tics
        WarmupFrames=$WarmupFrames;MeasuredFrames=$Frames
        TransportMode=if($TransportWorkerMasks -and $LegacyWorkerProjection -and $BaselineWorkerActorScan){'NumericV4 worker masks, full actor-array scan, and worker-side projection control'}elseif($TransportWorkerMasks -and $LegacyWorkerProjection){'NumericV4 worker masks with worker-side fixed-point actor projection control'}elseif($TransportWorkerMasks -and $projectionPacketVersion -eq 5 -and $BaselineWorkerActorScan){'adaptive NumericV5 actor projections with the full-array per-worker actor-scan control'}elseif($TransportWorkerMasks -and $projectionPacketVersion -eq 5){'adaptive NumericV5 actor projections with decoded per-worker visible-actor lists'}elseif($TransportWorkerMasks){'adaptive NumericV4 mask-only packet for a sparse scene'}elseif($TransportPrepared){'prepared shared actor order'}elseif($TransportLegacy){'legacy worker-side actor sort'}else{'object snapshot fallback'}
        FullFramePixels=64000;FullFrameSha256=$frameSha256
        SnapshotPreparationStats=Get-PhaseStats ([double[]]$snapshotPreparationSamples.ToArray())
        SnapshotPreparationSamples=$snapshotPreparationSamples.ToArray();FuzzActorCount=$fuzzActorCount;ActorWorkerMaskStats=$actorWorkerMaskStats
        RenderMode="Fixed game state and view; renderer phases measured serially for each of $WorkerCount production-equivalent column stripe(s); no terminal, audio, or simulation timing. Worker mask snapshot preparation includes host-side actor projection and mask generation."
        WorkerCount=$WorkerCount
        Camera=@{X=$camera.X;Y=$camera.Y;Angle=$camera.Angle;ViewZ=$game.World.ConsolePlayer.ViewZ}
        ActorCount=@($context.World.Actors).Count
        PhaseStats=$phases
        WorkerPhaseStats=$workerProfiles.ToArray()
        Samples=$samples.ToArray()
        WadSha256=(Get-FileHash -LiteralPath $Wad).Hash
        BundleSha256=(Get-FileHash -LiteralPath $bundle).Hash
        RendererSha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../src/FastRenderer.ps1").Hash
        SnapshotTransportSha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../src/SnapshotTransport.ps1").Hash
        GameHostSha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../src/GameHost.ps1").Hash
        HarnessSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
        PowerShell=$PSVersionTable.PSVersion.ToString()
        Meaning='Attributes PowerShell software-rendering time to the instrumented geometry, actor, player-weapon, and HUD phases at one fixed real-IWAD state. When WorkerCount is greater than one, each production-equivalent column stripe is rendered sequentially in this process: these are not concurrent-worker timings and do not model process scheduling, IPC, or terminal output. TransportLegacy exercises unsorted interpolation followed by each worker sorting locally; TransportPrepared measures repeated interpolation with shared far-to-near fuzz actor order. The LegacyWorkerProjection control forces the prior NumericV4 mask packet so workers repeat transforms locally; current production selects NumericV5 only for snapshots with at least 200 actors, otherwise it keeps the mask-only packet. Snapshot preparation includes host actor projection/mask generation; decode and render phases are reported separately with equal warmup/sample counts. Use live host receipts for pacing.'
    }
}catch{
    $failure=$_.ToString()+"`n"+$_.ScriptStackTrace
    throw
}finally{
    if($null -ne $content){$content.Dispose()}
    if($null -ne $report){$report.Error=$failure;$report|ConvertTo-Json -Depth 9|Set-Content -LiteralPath $outputPath}
}
foreach($phase in $report.PhaseStats.GetEnumerator()){
    "{0,-12} median {1,8:N2} ms  p95 {2,8:N2} ms" -f $phase.Key,$phase.Value.Median,$phase.Value.P95
}
"Receipt: $outputPath"
