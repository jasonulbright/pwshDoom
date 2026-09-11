#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [ValidateSet('Classic','Matrix','AnsiArt')][string]$Style='Classic',[string]$Output="$PSScriptRoot/../local/session-worker.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
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
            elseif($Menu -or $Automap){ConvertTo-MenuStrip $Expected 320 200 $worker.First $worker.End $codec -ColumnOffset 11 -RowOffset 3 -HudStart $(if($Automap){168}else{-1})}
            else{ConvertTo-CharacterStrip $Expected 320 200 $worker.First $worker.End $codec -ColumnOffset 11 -RowOffset 3 -FrameNumber 321 -HudStart $(if($Screen){200}else{168})}
        if([Convert]::ToBase64String($bytes) -cne [Convert]::ToBase64String($r.Bytes)){throw 'Encoded worker output mismatch.'}
    }
    $checks.Add(@{Tic=$ExpectedTic;Screen=[bool]$Screen;Menu=[bool]$Menu;Automap=[bool]$Automap;PixelsCompared=$compared;StripBytesCompared=$pool.Count})
}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$o=[GameOptions]::new();$o.GameMode=$content.Wad.GameMode
    $game=[DoomGame]::new($content,$o);$cmds=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$cmds[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($cmds)
    $context=New-FastRenderContext $content $game.World;$palette=[int[][]]::new(256)
    for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $pool=New-GameRenderPool $context $null 7 -Style $Style -GlyphSet Katakana;$pids=@($pool.Workers.Process.Id)
    $codec=if($Style -eq 'Classic'){New-CodecContext $palette}else{New-CharacterCodecContext $palette $Style -GlyphSet Katakana}
    $columns=[byte[]]::new(64000);$rows=[byte[]]::new(64000)
    for($x=0;$x -lt 320;$x++){for($y=0;$y -lt 200;$y++){$value=($x*17+$y*31)%256;$columns[$x*200+$y]=$value;$rows[$y*320+$x]=$value}}
    Submit-GameRender $pool $columns -ScreenPixels -Tic 987 -ColumnOffset 11 -RowOffset 3 -FrameNumber 321;Wait-GameRender $pool -ReadPixels
    Assert-WorkerImage $rows 987 -Screen
    Submit-GameRender $pool $columns -MenuPixels -Tic 988 -ColumnOffset 11 -RowOffset 3 -FrameNumber 321;Wait-GameRender $pool -ReadPixels
    Assert-WorkerImage $rows 988 -Menu
    Submit-GameRender $pool $columns -AutomapPixels -Tic 989 -ColumnOffset 11 -RowOffset 3 -FrameNumber 321;Wait-GameRender $pool -ReadPixels
    Assert-WorkerImage $rows 989 -Automap
    $oldHash=(Get-FileHash -LiteralPath $pool.Assets).Hash
    $game.DeferedInitNew([GameSkill]::Medium,1,2);$null=$game.Update($cmds)
    $context=New-FastRenderContext $content $game.World;Write-GameRenderAssets $context $palette $pool.Assets
    if((Get-FileHash -LiteralPath $pool.Assets).Hash -eq $oldHash){throw 'Map asset test did not change geometry.'}
    Update-GameRenderAssets $pool
    $snapshot=New-GameRenderSnapshot $game;Set-GameRenderSnapshot $context $snapshot;Invoke-FastRender $context
    Submit-GameRender $pool $snapshot -ColumnOffset 11 -RowOffset 3 -FrameNumber 321;Wait-GameRender $pool -ReadPixels
    Assert-WorkerImage $context.Pixels $snapshot.Tic
    if(($pids -join ',') -ne (@($pool.Workers.Process.Id) -join ',')){throw 'Worker processes restarted during reload.'}
}catch{$failure=$_.ToString();throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Style=$Style;GlyphSet='Katakana';Checks=$checks.ToArray();WorkerProcessesPreserved=$null -eq $failure;
        Meaning='Seven actual workers: independently constructed column/row-major screen equivalence and encoded strip equivalence, then changed E1M2 assets and real rasterization against the serial reference without restarting workers. This is a transport/lifecycle check, not campaign completion or a performance benchmark.'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $Output
    if($null -ne $pool){Close-GameRenderPool $pool};if($null -ne $content){$content.Dispose()}
}
"PASS: $Style screen/menu/automap transport and map reload, 256,000 pixels and 28 encoded strips."
