#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [ValidateRange(1,10)][int]$Repeats=3,[string]$Output="$PSScriptRoot/../local/map-render-assets.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..")
$Output=[IO.Path]::GetFullPath($Output);$directory=[IO.Path]::GetDirectoryName($Output)
[void][IO.Directory]::CreateDirectory($directory)
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/FrameCodec.ps1";. "$root/src/FastRenderer.ps1";. "$root/src/GameHost.ps1";. "$root/src/RenderAssets.ps1"
$content=$null;$failure=$null;$rows=[Collections.Generic.List[object]]::new();$initial=$null
$sources=@(foreach($name in 'src/FastRenderer.ps1','src/RenderAssets.ps1'){@{Path=$name;Sha256=(Get-FileHash "$root/$name").Hash}})
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $palette=[int[][]]::new(256)
    for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $watch=[Diagnostics.Stopwatch]::StartNew();$resources=New-FastRenderContext $content $game.World -CacheResources
    $contextMs=$watch.Elapsed.TotalMilliseconds;$watch.Restart()
    Write-GameRenderAssets $resources $palette "$directory/map-assets-$PID-initial.assets"
    $initial=@{ContextMilliseconds=$contextMs;WriteMilliseconds=$watch.Elapsed.TotalMilliseconds;RetainedBodyBytes=$resources.RenderAssetCache.Body.Length}
    $game.DeferedInitNew([GameSkill]::Medium,1,2);$null=$game.Update($commands);$snapshot=New-GameRenderSnapshot $game
    $referenceHash=$null
    for($repeat=0;$repeat -lt $Repeats;$repeat++){
        foreach($variant in 'Fresh','Reuse','Reuse','Fresh'){
            $process=[Diagnostics.Process]::GetCurrentProcess();$cpuBefore=$process.TotalProcessorTime.TotalMilliseconds
            $watch.Restart()
            $ctx=if($variant -eq 'Reuse'){New-FastRenderContext $content $game.World -Resources $resources}else{New-FastRenderContext $content $game.World}
            $contextMs=$watch.Elapsed.TotalMilliseconds;$watch.Restart();$assets="$directory/map-assets-$PID-$($rows.Count).assets"
            Write-GameRenderAssets $ctx $palette $assets
            $writeMs=$watch.Elapsed.TotalMilliseconds;$watch.Restart()
            $read=Read-GameRenderAssets $assets;$readMs=$watch.Elapsed.TotalMilliseconds
            $process.Refresh();$cpuMs=$process.TotalProcessorTime.TotalMilliseconds-$cpuBefore;$process.Dispose()
            Set-GameRenderSnapshot $ctx $snapshot;Invoke-FastRender $ctx
            Set-GameRenderSnapshot $read $snapshot;Invoke-FastRender $read
            $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($ctx.Pixels))
            if($hash -cne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($read.Pixels))){throw 'Asset roundtrip changed pixels.'}
            if($null -eq $referenceHash){$referenceHash=$hash}elseif($hash -cne $referenceHash){throw 'Fresh/reused resources changed pixels.'}
            $rows.Add(@{Repeat=$repeat;Variant=$variant;ContextMilliseconds=$contextMs;WriteMilliseconds=$writeMs;ReadMilliseconds=$readMs;
                PreparationMilliseconds=$contextMs+$writeMs;CpuMilliseconds=$cpuMs;AssetBytes=(Get-Item $assets).Length;
                FrameSha256=$hash;AssetSha256=(Get-FileHash $assets).Hash;AssetPath=$assets})
        }
    }
}catch{$failure=$_.ToString();throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Order='Fresh-Reuse-Reuse-Fresh';Repeats=$Repeats;InitialCacheBuild=$initial;
        Samples=$rows.ToArray();Runtime=$PSVersionTable.PSVersion.ToString();RuntimeExecutable=(Get-Process -Id $PID).Path;
        Sources=$sources;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;WadSha256=(Get-FileHash $Wad).Hash;
        Meaning='Sequential single-process ABBA repetitions on a fixed E1M2 snapshot. Resource cache is built once on E1M1 and its startup cost is retained. Includes exact fresh/reused/read-back frame hashes. This measures map asset stages, not campaign load, concurrent renderer reload or Terminal display pacing.'}|
        ConvertTo-Json -Depth 6|Set-Content -LiteralPath $Output
    if($null -ne $content){$content.Dispose()}
}
$rows|Select-Object Repeat,Variant,ContextMilliseconds,WriteMilliseconds,ReadMilliseconds,PreparationMilliseconds
