#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Wad,
    [ValidateRange(8,700)][int]$Tics=70,
    [ValidateRange(1,16)][int]$Frames=4,
    [switch]$ProfileRenderer,
    [ValidateRange(0,319)][int]$FirstColumn=0,
    [ValidateRange(1,320)][int]$EndColumn=320,
    [string]$Output=(Join-Path $PSScriptRoot '../local/engine-baseline.json')
)
$ErrorActionPreference='Stop'
if($ProfileRenderer){$env:DOOM_POWERSHELL_RENDER_PERF='1'}
. "$PSScriptRoot/FrameCodec.ps1"
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
$loadWatch=[Diagnostics.Stopwatch]::StartNew()
. $bundle
$content=$null
try {
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',[IO.Path]::GetFullPath($Wad)))
    $options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode
    $options.GameVersion=$content.Wad.GameVersion
    $options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options)
    $commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1)
    $null=$game.Update($commands)
    $config=[Config]::new()
    $config.video_highresolution=$false
    $config.video_gamescreensize=7
    $renderer=[Renderer]::new($config,$content)
    $renderer.Screen.FirstColumn=$FirstColumn;$renderer.Screen.EndColumn=$EndColumn
    $loadWatch.Stop()
    $tickMs=[double[]]::new($Tics)
    $frameMs=[double[]]::new($Frames)
    for($tic=0;$tic -lt $Tics;$tic++) {
        $commands[0].ForwardMove=25
        $commands[0].Buttons=if(($tic%14) -lt 7){[TicCmdButtons]::Attack}else{0}
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $null=$game.Update($commands)
        $watch.Stop();$tickMs[$tic]=$watch.Elapsed.TotalMilliseconds
    }
    for($frame=0;$frame -lt $Frames;$frame++) {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $renderer.RenderGame($game,[Fixed]::One)
        $watch.Stop();$frameMs[$frame]=$watch.Elapsed.TotalMilliseconds
    }
    $player=$game.World.ConsolePlayer
    $report=[ordered]@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
        WadSha256=(Get-FileHash -LiteralPath $Wad).Hash;Upstream='e8440ae2f33f190318ebde4ef20ffec3bc804244';
        LoadMs=$loadWatch.Elapsed.TotalMilliseconds;Tics=$Tics;Frames=$Frames;WarmupTics=0;
        FirstColumn=$FirstColumn;EndColumn=$EndColumn;
        SimulationMs=(Get-SampleStats $tickMs);RenderMs=(Get-SampleStats $frameMs);
        TickSamplesMs=$tickMs;RenderSamplesMs=$frameMs;Health=$player.Health;
        X=$player.Mobj.X.ToDouble();Y=$player.Mobj.Y.ToDouble();LevelTime=$game.World.LevelTime;
        Kills=$player.KillCount;TotalMonsters=$game.World.TotalKills;
        RendererProfile=if($ProfileRenderer){@{
            Frames=$renderer.ThreeD.PerfThreeDFrames;
            SetupMs=$renderer.ThreeD.PerfThreeDTicksSetup*1000.0/[Diagnostics.Stopwatch]::Frequency;
            BspMs=$renderer.ThreeD.PerfThreeDTicksBsp*1000.0/[Diagnostics.Stopwatch]::Frequency;
            SpritesMs=$renderer.ThreeD.PerfThreeDTicksSprites*1000.0/[Diagnostics.Stopwatch]::Frequency;
            MaskedMs=$renderer.ThreeD.PerfThreeDTicksMasked*1000.0/[Diagnostics.Stopwatch]::Frequency;
            WeaponMs=$renderer.ThreeD.PerfThreeDTicksPlayerSprites*1000.0/[Diagnostics.Stopwatch]::Frequency;
            SegMs=$renderer.ThreeD.PerfThreeDTicksDrawSeg*1000.0/[Diagnostics.Stopwatch]::Frequency;
            SolidMs=$renderer.ThreeD.PerfThreeDTicksSolidRange*1000.0/[Diagnostics.Stopwatch]::Frequency;
            PassMs=$renderer.ThreeD.PerfThreeDTicksPassRange*1000.0/[Diagnostics.Stopwatch]::Frequency
        }}else{$null};
        Meaning='Licensed PowerShell engine baseline: E1M1 HMP, forward movement and intermittent attack. Includes cold simulation/render samples; no output, no frame pacing, no full-map completion claim.'
    }
    $destination=[IO.Path]::GetFullPath($Output)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $destination -Encoding utf8
    [IO.File]::WriteAllBytes((Join-Path $PSScriptRoot '../local/engine-frame-column-major.bin'),$renderer.Screen.Data)
    [pscustomobject]@{Output=$destination;Simulation=$report.SimulationMs;Rendering=$report.RenderMs;Profile=$report.RendererProfile} | ConvertTo-Json -Depth 5
} catch {
    [Console]::Error.WriteLine($_.ScriptStackTrace)
    $engineException=$_.Exception
    while($null -ne $engineException){[Console]::Error.WriteLine($engineException.ToString());$engineException=$engineException.InnerException}
    throw
}
finally {if($null -ne $content){$content.Dispose()}}
