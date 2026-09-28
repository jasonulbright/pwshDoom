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
    [string]$Output="$PSScriptRoot/../results/renderer-phases.json"
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
$content=$null;$failure=$null;$report=$null;$samples=[Collections.Generic.List[object]]::new();$workerProfiles=[Collections.Generic.List[object]]::new()
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
    $game.DeferedInitNew([GameSkill]$Skill,$Episode,$Map)
    $null=$game.Update($commands)
    for($i=0;$i -lt $Tics;$i++){$null=$game.Update($commands)}
    $camera=$game.World.ConsolePlayer.Mobj
    $context=New-FastRenderContext $content $game.World
    Set-GameRenderSnapshot $context (New-GameRenderSnapshot $game 1)
    for($workerIndex=0;$workerIndex -lt $WorkerCount;$workerIndex++){
        # Match the production worker's integer column partition exactly.
        [int]$first=[Math]::Floor($workerIndex*320.0/$WorkerCount)
        [int]$end=[Math]::Floor(($workerIndex+1)*320.0/$WorkerCount)
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
            PhaseStats=$workerPhases
        })
    }
    $phases=@{}
    foreach($name in 'TotalMs','GeometryMs','ActorsMs','WeaponMs','HudMs'){
        $phases[$name]=Get-PhaseStats ([double[]]@($samples|ForEach-Object {$_.$name}))
    }
    $report=[ordered]@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o')
        Error=$null
        Episode=$Episode;Map=$Map;Skill=$Skill;SetupTics=$Tics
        WarmupFrames=$WarmupFrames;MeasuredFrames=$Frames
        RenderMode="Fixed game state and view; renderer phases measured serially for each of $WorkerCount production-equivalent column stripe(s); no terminal, audio, or simulation timing"
        WorkerCount=$WorkerCount
        Camera=@{X=$camera.X;Y=$camera.Y;Angle=$camera.Angle;ViewZ=$game.World.ConsolePlayer.ViewZ}
        ActorCount=@($context.World.Actors).Count
        PhaseStats=$phases
        WorkerPhaseStats=$workerProfiles.ToArray()
        Samples=$samples.ToArray()
        WadSha256=(Get-FileHash -LiteralPath $Wad).Hash
        BundleSha256=(Get-FileHash -LiteralPath $bundle).Hash
        RendererSha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../src/FastRenderer.ps1").Hash
        GameHostSha256=(Get-FileHash -LiteralPath "$PSScriptRoot/../src/GameHost.ps1").Hash
        HarnessSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
        PowerShell=$PSVersionTable.PSVersion.ToString()
        Meaning='Attributes PowerShell software-rendering time to the instrumented geometry, actor, player-weapon, and HUD phases at one fixed real-IWAD state. When WorkerCount is greater than one, each production-equivalent column stripe is rendered sequentially in this process: these are not concurrent-worker timings and do not model process scheduling, IPC, or terminal output. Use live host receipts for pacing.'
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
