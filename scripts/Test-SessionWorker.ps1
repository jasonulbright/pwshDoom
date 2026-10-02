#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [ValidateSet('Classic','Matrix','AnsiArt')][string]$Style='Classic',[ValidateRange(1,32)][int]$Workers=16,[switch]$ResourceReuse,[switch]$NonblockingReload,[switch]$ReloadFailure,[string]$Output="$PSScriptRoot/../local/session-worker.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
$sourceRoot=[IO.Path]::GetFullPath("$PSScriptRoot/..")
$sources=@(foreach($name in 'src/FastRenderer.ps1','src/RenderAssets.ps1','src/GameProcesses.ps1','src/GameHost.ps1','src/SnapshotTransport.ps1','scripts/Invoke-GameRenderWorker.ps1','scripts/Test-SessionWorker.ps1'){
    @{Path=$name;Sha256=(Get-FileHash -LiteralPath "$sourceRoot/$name").Hash}
})
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/CharacterCodec.ps1";. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/TerminalCodec.ps1"
. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/GameProcesses.ps1"
$content=$null;$pool=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new()
function Assert-WorkerImage([byte[]]$Expected,[int]$ExpectedTic,[switch]$Screen,[switch]$Menu,[switch]$Automap){
    $compared=0
    for($i=0;$i -lt $pool.Count;$i++){
        $worker=$pool.Workers[$i];$r=$pool.Results[$i]
        if($r.Tic -ne $ExpectedTic){throw 'Worker returned stale tic metadata.'}
        for($x=$worker.First;$x -lt $worker.End;$x++){for($y=0;$y -lt 200;$y++){
            if($r.Pixels[$y*320+$x] -ne $Expected[$y*320+$x]){throw "Worker pixel mismatch at $x,$y"};$compared++
        }}
        $bytes=if($Style -eq 'Classic'){ConvertTo-AnsiStrip $Expected 320 200 $worker.First $worker.End $codec -ColumnOffset 11 -RowOffset 3}
            elseif($Screen -or $Menu -or $Automap){ConvertTo-MenuStrip $Expected 320 200 $worker.First $worker.End $codec -ColumnOffset 11 -RowOffset 3 -HudStart $(if($Automap){168}else{-1})}
            else{ConvertTo-CharacterStrip $Expected 320 200 $worker.First $worker.End $codec -ColumnOffset 11 -RowOffset 3 -FrameNumber 321 -HudStart $(if($Screen){200}else{168})}
        if([Convert]::ToBase64String($bytes) -cne [Convert]::ToBase64String($r.Bytes)){throw 'Encoded worker output mismatch.'}
    }
    $checks.Add(@{Tic=$ExpectedTic;Screen=[bool]$Screen;Menu=[bool]$Menu;Automap=[bool]$Automap;PixelsCompared=$compared;StripBytesCompared=$pool.Count})
}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$o=[GameOptions]::new();$o.GameMode=$content.Wad.GameMode
    $game=[DoomGame]::new($content,$o);$cmds=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$cmds[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($cmds)
    $context=New-FastRenderContext $content $game.World -CacheResources:$ResourceReuse;$palette=[int[][]]::new(256)
    for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $pool=New-GameRenderPool $context $null $Workers -Style $Style -GlyphSet Katakana;$pids=@($pool.Workers.Process.Id)
    $codec=if($Style -eq 'Classic'){New-CodecContext $palette}else{New-CharacterCodecContext $palette $Style -GlyphSet Katakana}
    $columns=[byte[]]::new(64000);$rows=[byte[]]::new(64000)
    for($x=0;$x -lt 320;$x++){for($y=0;$y -lt 200;$y++){$value=($x*17+$y*31)%256;$columns[$x*200+$y]=$value;$rows[$y*320+$x]=$value}}
    Submit-GameRender $pool $columns -ScreenPixels -Tic 987 -ColumnOffset 11 -RowOffset 3 -FrameNumber 321;Wait-GameRender $pool -ReadPixels
    Assert-WorkerImage $rows 987 -Screen
    Submit-GameRender $pool $columns -MenuPixels -Tic 988 -ColumnOffset 11 -RowOffset 3 -FrameNumber 321;Wait-GameRender $pool -ReadPixels
    Assert-WorkerImage $rows 988 -Menu
    Submit-GameRender $pool $columns -AutomapPixels -Tic 989 -ColumnOffset 11 -RowOffset 3 -FrameNumber 321;Wait-GameRender $pool -ReadPixels
    Assert-WorkerImage $rows 989 -Automap
    $maps=if($ResourceReuse){@(@(1,2),@(2,1),@(3,1),@(1,2))}else{@(,@(1,2))}
    foreach($target in $maps){
    $oldHash=(Get-FileHash -LiteralPath $pool.Assets).Hash;$previous=$context
    $game.DeferedInitNew([GameSkill]::Medium,$target[0],$target[1]);$null=$game.Update($cmds)
    $context=if($ResourceReuse){New-FastRenderContext $content $game.World -Resources $previous}else{New-FastRenderContext $content $game.World}
    if($ResourceReuse){
        foreach($field in 'Pixels','Depth','Planes','TopClip','BottomClip','SegmentGeometry','SectorFloorHeightData'){
            if([object]::ReferenceEquals($context[$field],$previous[$field])){throw "Reused mutable $field"}
        }
        foreach($field in 'Textures','Patches','Hud','SpriteAtlas','RenderAssetCache'){
            if(-not [object]::ReferenceEquals($context[$field],$previous[$field])){throw "Did not reuse immutable $field"}
        }
        $rejected=$false
        try{$null=New-FastRenderContext ([object]::new()) $game.World -Resources $context}catch{
            if($_.Exception.Message -ne 'Render resources must belong to the same GameContent instance.'){throw};$rejected=$true
        }
        if(-not $rejected){throw 'Accepted resources from a different content instance.'}
    }
    $context.PlaneSpanBoundaries=[int[]]@($pool.Workers|ForEach-Object {$_.End})
    Write-GameRenderAssets $context $palette $pool.Assets
    if((Get-FileHash -LiteralPath $pool.Assets).Hash -eq $oldHash){throw 'Map asset test did not change geometry.'}
    if($NonblockingReload){
        Start-GameRenderAssetReload $pool
        $rejected=0
        try{Start-GameRenderAssetReload $pool}catch{if($_.Exception.Message -ne 'A map asset reload is already in progress.'){throw};$rejected++}
        try{Submit-GameRender $pool $columns -ScreenPixels}catch{if($_.Exception.Message -ne 'Finish map asset reload before rendering.'){throw};$rejected++}
        try{Wait-GameRender $pool}catch{if($_.Exception.Message -ne 'Finish map asset reload before harvesting rendering.'){throw};$rejected++}
        $polls=0;$unfinished=0
        do{$ready=Complete-GameRenderAssetReload $pool;$polls++;if(-not $ready){$unfinished++;[Threading.Thread]::Sleep(1)}}while(-not $ready)
        $missingRejected=$false
        try{$null=Complete-GameRenderAssetReload $pool}catch{if($_.Exception.Message -ne 'No map asset reload is in progress.'){throw};$missingRejected=$true}
        if($rejected -ne 3 -or -not $missingRejected -or $pool.AssetReloadPending){throw 'Nonblocking asset ownership guards failed.'}
        $checks.Add(@{Episode=$target[0];Map=$target[1];ReloadPolls=$polls;UnfinishedPolls=$unfinished;OverlappingOperationsRejected=$rejected;DuplicateCompletionRejected=$missingRejected})
    }else{Update-GameRenderAssets $pool}
    if($ResourceReuse){
        $expectedReuse=[object]::ReferenceEquals($previous.SkyTextureReference,$context.SkyTextureReference)
        foreach($reload in $pool.AssetReloadResults){if($reload.ResourceBodyReused -ne $expectedReuse){throw 'Worker body hash reuse/invalidation disagrees with the sky change.'}}
        $checks.Add(@{Episode=$target[0];Map=$target[1];WorkerBodyReuseExpected=$expectedReuse;ReloadResults=$pool.AssetReloadResults})
    }
    $snapshot=New-GameRenderSnapshot $game;Set-GameRenderSnapshot $context $snapshot;Invoke-FastRender $context
    if($ResourceReuse){
        $oracle=New-FastRenderContext $content $game.World
        $oracle.PlaneSpanBoundaries=$context.PlaneSpanBoundaries
        Set-GameRenderSnapshot $oracle $snapshot;Invoke-FastRender $oracle
        if(-not [Linq.Enumerable]::SequenceEqual([byte[]]$oracle.Pixels,[byte[]]$context.Pixels)){throw 'Reused resources differ from independently converted WAD resources.'}
        $checks.Add(@{Episode=$target[0];Map=$target[1];FreshResourcePixelsCompared=64000;PrivateScratch=$true;ForeignContentRejected=$true})
    }
    Submit-GameRender $pool $snapshot -ColumnOffset 11 -RowOffset 3 -FrameNumber 321;Wait-GameRender $pool -ReadPixels
    Assert-WorkerImage $context.Pixels $snapshot.Tic
    if(($pids -join ',') -ne (@($pool.Workers.Process.Id) -join ',')){throw 'Worker processes restarted during reload.'}
    }
    if($ReloadFailure){
        if(-not $NonblockingReload -or -not $pool.OwnAssets){throw 'Failure injection requires nonblocking reload and test-owned assets.'}
        $writer=[IO.BinaryWriter]::new([IO.File]::Create($pool.Assets))
        try{$writer.Write('invalid-test-only-format')}finally{$writer.Dispose()}
        $watch=[Diagnostics.Stopwatch]::StartNew();$rejected=$false
        Start-GameRenderAssetReload $pool
        try{while(-not (Complete-GameRenderAssetReload $pool)){[Threading.Thread]::Sleep(1)}}catch{
            if($_.Exception.Message -notlike '*Unknown render asset format.*'){throw};$rejected=$true
        }
        if(-not $rejected -or $watch.Elapsed.TotalSeconds -gt 5){throw 'Failed worker reload was not promptly propagated.'}
        $checks.Add(@{CorruptOwnedAssetReloadRejected=$true;DetectionMilliseconds=$watch.Elapsed.TotalMilliseconds;PoolRemainsOwnedUntilCleanup=$pool.AssetReloadPending})
    }
    foreach($source in $sources){if((Get-FileHash -LiteralPath "$sourceRoot/$($source.Path)").Hash -cne $source.Sha256){throw 'Source changed during worker qualification.'}}
}catch{$failure=$_.ToString();throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Style=$Style;GlyphSet='Katakana';Workers=$Workers;ResourceReuse=[bool]$ResourceReuse;NonblockingReload=[bool]$NonblockingReload;ReloadFailure=[bool]$ReloadFailure;Checks=$checks.ToArray();WorkerProcessesPreserved=$null -eq $failure;
        Sources=$sources;WadSha256=(Get-FileHash -LiteralPath $Wad).Hash;Runtime=$PSVersionTable.PSVersion.ToString();
        Meaning='Actual worker processes: independent column/row-major screen and encoded strip equivalence, then changed-map rasterization against the serial reference without restarting workers. ResourceReuse adds E1M2/E2M1/E3M1/E1M2 sky reloads, fresh-resource pixel oracles, private mutable scratch and foreign-content rejection. This is a transport/lifecycle check, not campaign completion or a performance benchmark.'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $Output
    if($null -ne $pool){Close-GameRenderPool $pool};if($null -ne $content){$content.Dispose()}
}
"PASS: $Style screen/menu/automap transport and $($maps.Count) map reloads, $((3+$maps.Count)*64000) worker pixels and $($Workers*(3+$maps.Count)) encoded strips."
