#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [ValidateRange(1,4)][int]$Episode=3,
    [ValidateRange(1,9)][int]$Map=6,
    [ValidateRange(1,5)][int]$Skill=3,
    [ValidateRange(1,32)][int]$Workers=16,
    [ValidateRange(1,100)][int]$WarmupFrames=4,
    [ValidateRange(1,200)][int]$Frames=24,
    [switch]$DisableMasks,
    [string]$Output="$PSScriptRoot/../results/renderer-worker-mask-impact.json"
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$outputPath=[IO.Path]::GetFullPath($Output)
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath))
. "$PSScriptRoot/FrameCodec.ps1"
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"
. "$PSScriptRoot/../src/SnapshotTransport.ps1"
. "$PSScriptRoot/../src/GameProcesses.ps1"

function Get-MeasureStats([double[]]$Values){
    [double[]]$sorted=@($Values|Sort-Object)
    if($sorted.Length -eq 0){return @{Count=0;Mean=0.0;Median=0.0;P95=0.0;Max=0.0}}
    return @{
        Count=$sorted.Length
        Mean=($sorted|Measure-Object -Average).Average
        Median=$sorted[[int][Math]::Floor(($sorted.Length-1)*.5)]
        P95=$sorted[[int][Math]::Floor(($sorted.Length-1)*.95)]
        Max=$sorted[-1]
    }
}

$content=$null;$pool=$null;$failure=$null;$report=$null
$samples=[Collections.Generic.List[object]]::new()
try{
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode
    $options.GameVersion=$content.Wad.GameVersion
    $options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options)
    [TicCmd[]]$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt $commands.Length;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]($Skill-1),$Episode,$Map)
    $null=$game.Update($commands)
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}

    $context=New-FastRenderContext $content $game.World
    [int[][]]$palette=[int[][]]::new(256)
    for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $pool=New-GameRenderPool $context (New-CodecContext $palette) $Workers
    # Live gameplay reads encoded strips but does not copy worker framebuffers
    # back to the host unless a capture is requested.
    $pool.CopyPixels=$false
    if($DisableMasks){$pool.SpriteAtlas=$null}

    $pair=Get-GameRenderSnapshotPair $game
    [double[]]$previous=[double[]]::new($pair.Previous.Length/8)
    [Buffer]::BlockCopy($pair.Previous,0,$previous,0,$pair.Previous.Length)
    [double[]]$current=[double[]]::new($pair.Current.Length/8)
    [Buffer]::BlockCopy($pair.Current,0,$current,0,$pair.Current.Length)
    $lastPacket=$null;$lastOutputHash=$null

    for([int]$frame=0;$frame -lt ($WarmupFrames+$Frames);$frame++){
        $frameWatch=[Diagnostics.Stopwatch]::StartNew()
        $interpolationWatch=[Diagnostics.Stopwatch]::StartNew()
        [byte[]]$packet=Get-InterpolatedSnapshotBytes $previous $current 1
        $interpolationWatch.Stop()
        $submitWatch=[Diagnostics.Stopwatch]::StartNew()
        Submit-GameRender $pool $packet
        $submitWatch.Stop()
        $waitWatch=[Diagnostics.Stopwatch]::StartNew()
        Wait-GameRender $pool
        $waitWatch.Stop()
        $frameWatch.Stop()

        [double[]]$workerRender=[double[]]@($pool.Results|ForEach-Object {$_.RenderMs})
        [double[]]$workerEncode=[double[]]@($pool.Results|ForEach-Object {$_.EncodeMs})
        [double[]]$workerDecode=[double[]]@($pool.Results|ForEach-Object {$_.DecodeMs})
        $hash=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
        foreach($result in $pool.Results){$hash.AppendData([byte[]]$result.Bytes)}
        $outputHash=[Convert]::ToHexString($hash.GetHashAndReset());$hash.Dispose()
        if($null -ne $lastOutputHash -and $outputHash -cne $lastOutputHash){throw 'Encoded worker output changed for a fixed game state.'}
        $lastOutputHash=$outputHash;$lastPacket=$packet
        if($frame -ge $WarmupFrames){
            $samples.Add(@{
                Index=$frame-$WarmupFrames
                InterpolationMs=$interpolationWatch.Elapsed.TotalMilliseconds
                SubmitMs=$submitWatch.Elapsed.TotalMilliseconds
                WaitMs=$waitWatch.Elapsed.TotalMilliseconds
                DispatchWallMs=$frameWatch.Elapsed.TotalMilliseconds
                PeakWorkerRenderMs=($workerRender|Measure-Object -Maximum).Maximum
                PeakWorkerEncodeMs=($workerEncode|Measure-Object -Maximum).Maximum
                PeakWorkerDecodeMs=($workerDecode|Measure-Object -Maximum).Maximum
                SumWorkerRenderMs=($workerRender|Measure-Object -Sum).Sum
                SumWorkerEncodeMs=($workerEncode|Measure-Object -Sum).Sum
                EncodedOutputSha256=$outputHash
            })
        }
    }

    $maskStats=$null;$packetVersion=3
    if(-not $DisableMasks){
        [byte[]]$diagnosticPacket=Add-GameRenderActorWorkerMasks $lastPacket $pool
        [double[]]$diagnosticValues=[double[]]::new($diagnosticPacket.Length/8)
        [Buffer]::BlockCopy($diagnosticPacket,0,$diagnosticValues,0,$diagnosticPacket.Length)
        $packetVersion=[int]$diagnosticValues[0]
        $diagnostic=Read-GameSnapshotBytes $diagnosticPacket $null
        [long]$possible=[long]$diagnostic.Actors.Count*$Workers;[long]$included=0
        foreach($actor in $diagnostic.Actors){for([int]$workerIndex=0;$workerIndex -lt $Workers;$workerIndex++){if(($actor.WorkerMask -band (1L -shl $workerIndex)) -ne 0){$included++}}}
        $maskStats=@{Actors=$diagnostic.Actors.Count;PossibleActorWorkerPairs=$possible;IncludedActorWorkerPairs=$included;SkippedActorWorkerPairs=$possible-$included;PacketBytes=$diagnosticPacket.Length}
    }
    $report=[ordered]@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o')
        Error=$null
        Episode=$Episode;Map=$Map;Skill=$Skill;Workers=$Workers
        WarmupFrames=$WarmupFrames;MeasuredFrames=$Frames
        TransportMode=if($DisableMasks){'NumericV3 without worker masks'}else{'NumericV4 with projected actor worker masks'}
        SnapshotPacketVersion=$packetVersion;ActorWorkerMaskStats=$maskStats
        DispatchWallStats=Get-MeasureStats ([double[]]@($samples|ForEach-Object DispatchWallMs))
        SubmitStats=Get-MeasureStats ([double[]]@($samples|ForEach-Object SubmitMs))
        WaitStats=Get-MeasureStats ([double[]]@($samples|ForEach-Object WaitMs))
        PeakWorkerRenderStats=Get-MeasureStats ([double[]]@($samples|ForEach-Object PeakWorkerRenderMs))
        SumWorkerRenderStats=Get-MeasureStats ([double[]]@($samples|ForEach-Object SumWorkerRenderMs))
        EncodedOutputSha256=$lastOutputHash
        Samples=$samples.ToArray()
        Measurement='Fixed E3M6 simulation state through the real 16-process renderer pool. Each frame interpolates the same snapshot, submits it to every renderer process, waits for all processes, and retrieves encoded strips without framebuffer copies. Worker startup is outside the timed interval. This measures dispatch, software rendering and strip encoding, not simulation, audio, terminal output, or displayed FPS.'
        WadSha256=(Get-FileHash -LiteralPath $Wad).Hash
        BundleSha256=(Get-FileHash -LiteralPath $bundle).Hash
        RendererSha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../src/FastRenderer.ps1").Hash
        SpriteProjectionSha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../src/SpriteProjection.ps1").Hash
        SnapshotTransportSha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../src/SnapshotTransport.ps1").Hash
        GameProcessesSha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../src/GameProcesses.ps1").Hash
        HarnessSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
        PowerShell=$PSVersionTable.PSVersion.ToString()
    }
}catch{
    $failure=$_.ToString()+"`n"+$_.ScriptStackTrace
    throw
}finally{
    if($null -ne $content){$content.Dispose()}
    if($null -ne $pool){Close-GameRenderPool $pool}
    if($null -ne $report){$report.Error=$failure;$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $outputPath}
}
"Dispatch wall  median $($report.DispatchWallStats.Median.ToString('N2')) ms  p95 $($report.DispatchWallStats.P95.ToString('N2')) ms"
"Submit        median $($report.SubmitStats.Median.ToString('N2')) ms  p95 $($report.SubmitStats.P95.ToString('N2')) ms"
"Peak worker   median $($report.PeakWorkerRenderStats.Median.ToString('N2')) ms  p95 $($report.PeakWorkerRenderStats.P95.ToString('N2')) ms"
"Receipt: $outputPath"
