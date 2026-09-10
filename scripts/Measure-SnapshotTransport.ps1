#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$content=$null
try {
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $snapshot=New-GameRenderSnapshot $game;$previous=$null
    $times=@{JsonEncode=[Collections.Generic.List[double]]::new();JsonDecode=[Collections.Generic.List[double]]::new();BinaryEncode=[Collections.Generic.List[double]]::new();BinaryDecode=[Collections.Generic.List[double]]::new()}
    for($i=0;$i -lt 48;$i++) {
        $watch=[Diagnostics.Stopwatch]::StartNew();$json=[Text.Encoding]::UTF8.GetBytes(($snapshot | ConvertTo-Json -Depth 8 -Compress));$elapsed=$watch.Elapsed.TotalMilliseconds
        if($i -ge 16){$times.JsonEncode.Add($elapsed)}
        $watch.Restart();$decoded=[Text.Encoding]::UTF8.GetString($json) | ConvertFrom-Json -AsHashtable;$elapsed=$watch.Elapsed.TotalMilliseconds
        if($i -ge 16){$times.JsonDecode.Add($elapsed)}
        $watch.Restart();$binary=ConvertTo-GameSnapshotBytes $snapshot;$elapsed=$watch.Elapsed.TotalMilliseconds
        if($i -ge 16){$times.BinaryEncode.Add($elapsed)}
        $watch.Restart();$previous=Read-GameSnapshotBytes $binary $previous;$elapsed=$watch.Elapsed.TotalMilliseconds
        if($i -ge 16){$times.BinaryDecode.Add($elapsed)}
    }
    # Pack the decoded fields again. Exact bytes must survive all coordinates, IDs,
    # booleans, arrays, and frame metadata (not just the player position).
    $roundTrip=ConvertTo-GameSnapshotBytes $previous
    if(-not [Linq.Enumerable]::SequenceEqual[byte]($binary,$roundTrip)){throw 'Snapshot binary round-trip mismatch.'}
    $report=@{FinishedUtc=[DateTime]::UtcNow.ToString('o');Warmup=16;Samples=32;JsonBytes=$json.Length;BinaryBytes=$binary.Length;RoundTripBytesEqual=$true;Stats=@{};SamplesMs=@{}}
    foreach($key in $times.Keys){$report.Stats[$key]=Get-SampleStats $times[$key].ToArray();$report.SamplesMs[$key]=$times[$key].ToArray()}
    $report | ConvertTo-Json -Depth 6 | Set-Content "$PSScriptRoot/../results/snapshot-transport.json"
    $report.Stats | ConvertTo-Json -Depth 4
} catch {[Console]::Error.WriteLine($_.ScriptStackTrace);throw}
finally {if($null -ne $content){$content.Dispose()}}
