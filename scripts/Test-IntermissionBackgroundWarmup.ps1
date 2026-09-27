#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Baseline="$PSScriptRoot/../results/session-screens-render-final-20260927.json",
    [int]$TimingRepeats=5,
    [string]$Output="$PSScriptRoot/../results/intermission-background-warmup-20260927-r4.json"
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
if(-not (Test-Path -LiteralPath $Wad)){throw "Ultimate Doom IWAD was not found: $Wad"}
if(-not (Test-Path -LiteralPath $Baseline)){throw "Pinned pre-change session-screen receipt was not found: $Baseline"}
if($TimingRepeats -lt 3 -or $TimingRepeats -gt 20){throw 'TimingRepeats must be between 3 and 20.'}
$checks=[Collections.Generic.List[object]]::new();$failure=$null;$content=$null
function Add-Check {
    param([string]$Name,[bool]$Passed,$Evidence)
    $script:checks.Add(@{Name=$Name;Passed=$Passed;Evidence=$Evidence})
    if(-not $Passed){throw "Failed: $Name; $($Evidence|ConvertTo-Json -Compress -Depth 6)"}
}
function Get-PixelHash([byte[]]$Pixels) {
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Pixels))
}
try{
    $baselineObject=Get-Content -LiteralPath $Baseline -Raw|ConvertFrom-Json
    $baselineWad=(Get-FileHash -LiteralPath $Wad).Hash
    if($baselineObject.WadSha256 -ne $baselineWad){throw 'The baseline screen receipt uses a different IWAD.'}
    $baselineByScreen=@{}
    foreach($item in $baselineObject.Checks|Where-Object {$_.Screen -in 'Stats','Next'}){$baselineByScreen["$($item.Episode)/$($item.Screen)"]=$item.Sha256}
    if($baselineByScreen.Count -ne 8){throw 'The pre-change receipt must contain Stats and Next images for all four episodes.'}

    $bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/intermission-warmup-engine-$PID.ps1";. $bundle
    . "$PSScriptRoot/../src/SessionScreens.ps1"
    $content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt $commands.Length;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $allSourceHashes=@{
        SessionScreens=(Get-FileHash "$PSScriptRoot/../src/SessionScreens.ps1").Hash
        IntermissionRenderer=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Video/IntermissionRenderer.sb.ps1").Hash
        SimulationWorker=(Get-FileHash "$PSScriptRoot/Invoke-SimulationWorker.ps1").Hash
        Harness=(Get-FileHash $PSCommandPath).Hash
    }
    $mapNameByEpisode=@{1='WIMAP0';2='WIMAP1';3='WIMAP2';4='INTERPIC'}
    foreach($episode in 1..4){
        $options.Episode=$episode;$options.Map=1;$game.DoCompleted()
        if($game.State -ne [GameState]::Intermission){throw "Episode $episode did not enter intermission state."}
        $sessionWatch=[Diagnostics.Stopwatch]::StartNew();$session=New-DoomSessionScreens $content $episode;$sessionWatch.Stop()
        $selected=$mapNameByEpisode[$episode]
        $screenIsClear=(Get-PixelHash $session.Screen.Data) -eq (Get-PixelHash ([byte[]]::new(64000)))
        Add-Check "Episode $episode session preloads $selected" ($session.Intermission.backgroundFrames.ContainsKey($selected)) @{CachedNames=@($session.Intermission.backgroundFrames.Keys);CreationMilliseconds=$sessionWatch.Elapsed.TotalMilliseconds}
        Add-Check "Episode $episode session leaves framebuffer clear" $screenIsClear @{Sha256=(Get-PixelHash $session.Screen.Data)}

        foreach($phase in 'Stats','Next'){
            if($phase -eq 'Next'){$game.Intermission.InitShowNextLoc()}
            $coldScreen=[DrawScreen]::new($content.Wad,320,200);$cold=[IntermissionRenderer]::new($content.Wad,$coldScreen)
            $warmScreen=[DrawScreen]::new($content.Wad,320,200);$warm=[IntermissionRenderer]::new($content.Wad,$warmScreen)
            # Compile the render path and decode all non-background patches
            # before timing. Clearing only the frame cache leaves the cold
            # renderer to rasterize its background on the measured first frame.
            $cold.Render($game.Intermission);$warm.Render($game.Intermission)
            $cold.backgroundFrames.Clear();$warm.backgroundFrames.Clear()
            $coldSamples=[Collections.Generic.List[double]]::new();$warmSamples=[Collections.Generic.List[double]]::new();$warmupSamples=[Collections.Generic.List[double]]::new()
            $hashPairs=[Collections.Generic.List[object]]::new()
            for($repeat=1;$repeat -le $TimingRepeats;$repeat++){
                $cold.backgroundFrames.Clear();$warm.backgroundFrames.Clear()
                $prewarmWatch=[Diagnostics.Stopwatch]::StartNew();$warm.WarmupBackground($content.Wad.GameMode,$episode);$prewarmWatch.Stop();$warmupSamples.Add($prewarmWatch.Elapsed.TotalMilliseconds)
                if((($repeat+$episode) -band 1) -eq 1){
                    $coldWatch=[Diagnostics.Stopwatch]::StartNew();$cold.Render($game.Intermission);$coldWatch.Stop()
                    $warmWatch=[Diagnostics.Stopwatch]::StartNew();$warm.Render($game.Intermission);$warmWatch.Stop()
                }else{
                    $warmWatch=[Diagnostics.Stopwatch]::StartNew();$warm.Render($game.Intermission);$warmWatch.Stop()
                    $coldWatch=[Diagnostics.Stopwatch]::StartNew();$cold.Render($game.Intermission);$coldWatch.Stop()
                }
                $coldSamples.Add($coldWatch.Elapsed.TotalMilliseconds);$warmSamples.Add($warmWatch.Elapsed.TotalMilliseconds)
                $hashPairs.Add(@{Cold=(Get-PixelHash $coldScreen.Data);Warm=(Get-PixelHash $warmScreen.Data)})
            }
            $coldSorted=@($coldSamples|Sort-Object);$warmSorted=@($warmSamples|Sort-Object);$warmupSorted=@($warmupSamples|Sort-Object)
            $coldHash=$hashPairs[$hashPairs.Count-1].Cold;$warmHash=$hashPairs[$hashPairs.Count-1].Warm
            $coldMedian=$coldSorted[[int][math]::Floor(($coldSorted.Count-1)/2)]
            $warmMedian=$warmSorted[[int][math]::Floor(($warmSorted.Count-1)/2)]
            $warmupMedian=$warmupSorted[[int][math]::Floor(($warmupSorted.Count-1)/2)]
            $key="$episode/$phase"
            $allPairsMatch=@($hashPairs|Where-Object {$_.Cold -ne $_.Warm}).Count -eq 0
            Add-Check "Episode $episode $phase equals cold renderer across $TimingRepeats interleaved trials" $allPairsMatch @{Trials=$hashPairs.ToArray();ColdSha256=$coldHash;WarmSha256=$warmHash}
            Add-Check "Episode $episode $phase preserves prior frame" ($warmHash -eq $baselineByScreen[$key]) @{ExpectedSha256=$baselineByScreen[$key];ActualSha256=$warmHash}
            Add-Check "Episode $episode $phase background caches are identical" ((Get-PixelHash $cold.backgroundFrames[$selected]) -eq (Get-PixelHash $warm.backgroundFrames[$selected])) @{Background=$selected;Sha256=(Get-PixelHash $warm.backgroundFrames[$selected])}

            # Independently prove warm-up restores existing framebuffer data,
            # and measure the moved work without mixing it into screen drawing.
            $probeScreen=[DrawScreen]::new($content.Wad,320,200);[Array]::Fill($probeScreen.Data,[byte]0x5A)
            $beforeHash=Get-PixelHash $probeScreen.Data;$probe=[IntermissionRenderer]::new($content.Wad,$probeScreen)
            $prewarmWatch=[Diagnostics.Stopwatch]::StartNew();$probe.WarmupBackground($content.Wad.GameMode,$episode);$prewarmWatch.Stop()
            $afterHash=Get-PixelHash $probeScreen.Data
            Add-Check "Episode $episode $phase warm-up preserves an existing framebuffer" ($afterHash -eq $beforeHash) @{BeforeSha256=$beforeHash;AfterSha256=$afterHash;WarmupMilliseconds=$prewarmWatch.Elapsed.TotalMilliseconds}

            $checks.Add(@{Name="Episode $episode $phase first-frame timings";Passed=$true;Evidence=@{ColdMedianMilliseconds=$coldMedian;WarmMedianMilliseconds=$warmMedian;WarmupMedianMilliseconds=$warmupMedian;ColdSamplesMilliseconds=$coldSamples.ToArray();WarmSamplesMilliseconds=$warmSamples.ToArray();WarmupSamplesMilliseconds=$warmupSamples.ToArray();SessionCreationMilliseconds=$sessionWatch.Elapsed.TotalMilliseconds;Ordering='Alternated cold-first and warm-first renders after JIT and patch-cache priming.';Pixels=64000;Scope='Five interleaved first-render trials after PowerShell render-path JIT and patch-cache priming; process startup, terminal presentation and full-game pacing are excluded.'}})
        }
    }
}catch{$failure=$_.ToString();throw}finally{
    $result=@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Passed=($null -eq $failure -and @($checks|Where-Object {-not $_.Passed}).Count -eq 0)
        Checks=$checks.ToArray();WadSha256=if(Test-Path -LiteralPath $Wad){(Get-FileHash -LiteralPath $Wad).Hash}else{$null}
        BaselinePath=[IO.Path]::GetRelativePath((Get-Location).Path,[IO.Path]::GetFullPath($Baseline));BaselineSha256=if(Test-Path -LiteralPath $Baseline){(Get-FileHash -LiteralPath $Baseline).Hash}else{$null}
        SourceSha256=$allSourceHashes
        Meaning='For all four Ultimate Doom episodes, prewarmed intermission Stats/Next frames are hash-identical to the prior renderer and a fresh cold renderer. Five alternating-order first-render trials per screen follow render-path JIT and patch-cache priming; the probe confirms warm-up preserves existing screen bytes. Timings exclude process startup, terminal presentation and full-game pacing, and do not prove campaign audio continuity, visual parity against the original executable, or a frame-rate target.'
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Output)))
    $result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
    if($null -ne $content){$content.Dispose()}
}
$passed=@($checks|Where-Object Passed).Count
"PASS: $passed intermission background warm-up checks across four episodes."
