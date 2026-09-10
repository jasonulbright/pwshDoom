#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',[string]$CompareRenderer)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/GameProcesses.ps1"
$content=$null;$pool=$null;$checks=[Collections.Generic.List[object]]::new()
try {
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    $context=New-FastRenderContext $content $game.World
    $palette=[int[][]]::new(256)
    for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $pool=New-GameRenderPool $context (New-CodecContext $palette) 7
    foreach($angle in 0,37,89,173,269) {
        $snapshot=New-GameRenderSnapshot $game;$snapshot.ConsolePlayer.Mobj.Angle=$angle*[Math]::PI/180
        if($angle -eq 37){$snapshot.ConsolePlayer.ExtraLight=2;foreach($sector in $snapshot.Sectors){$sector.LightLevel=255}}
        if($CompareRenderer){. $CompareRenderer}
        $serial=$context.Clone();Set-GameRenderSnapshot $serial $snapshot;Invoke-FastRender $serial
        $expected=[byte[]]$serial.Pixels.Clone()
        . "$PSScriptRoot/../src/FastRenderer.ps1"
        Submit-GameRender $pool $snapshot -ColumnOffset 17 -RowOffset 5;Wait-GameRender $pool
        $actual=[byte[]]::new(64000)
        for($i=0;$i -lt $pool.Count;$i++) {
            $worker=$pool.Workers[$i];$result=$pool.Results[$i]
            $prefix="$([char]27)[6;$($worker.First+18)H"
            if(-not [Text.Encoding]::UTF8.GetString($result.Bytes).StartsWith($prefix)){throw 'Worker did not apply the requested viewport origin.'}
            if($result.Tic -ne $snapshot.Tic){throw 'Worker returned a different simulation tic.'}
            for($y=0;$y -lt 200;$y++){[Array]::Copy($result.Pixels,$y*320+$worker.First,$actual,$y*320+$worker.First,$worker.End-$worker.First)}
        }
        $differences=0
        for($i=0;$i -lt 64000;$i++){if($actual[$i] -ne $expected[$i]){$differences++}}
        if($differences -ne 0){throw "$differences pixels differ at $angle degrees between serial rendering and seven process strips."}
        $checks.Add(@{AngleDegrees=$angle;ComparedPixels=64000;Differences=$differences})
    }
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks.ToArray();BaselineRendererSha256=if($CompareRenderer){(Get-FileHash -LiteralPath $CompareRenderer).Hash}else{(Get-FileHash "$PSScriptRoot/../src/FastRenderer.ps1").Hash};Meaning='Exact serial/partition equivalence of the new renderer, including its binary asset cache and NumericV1 snapshot transport. This is not a vanilla renderer equivalence claim.'} |
        ConvertTo-Json -Depth 5 | Set-Content "$PSScriptRoot/../results/render-partitions.json"
    'PASS: 320,000 pixels match across five views and seven uneven process strips.'
} catch {[Console]::Error.WriteLine($_.ScriptStackTrace);throw}
finally {if($null -ne $pool){Close-GameRenderPool $pool};if($null -ne $content){$content.Dispose()}}
