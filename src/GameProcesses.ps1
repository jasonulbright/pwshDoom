# SPDX-License-Identifier: GPL-2.0-or-later
# Separate PowerShell heaps avoid the runspace contention measured by the study.
. "$PSScriptRoot/RenderAssets.ps1"
. "$PSScriptRoot/SnapshotTransport.ps1"
function New-GameRenderPool {
    param($Context,$Codec,[int]$Workers=16,[ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic',
        [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Ascii')
    $root=Split-Path $PSScriptRoot
    $pool=@{Workers=[Collections.Generic.List[object]]::new();Results=[object[]]::new($Workers);Count=$Workers;Style=$Style;
        Assets=(Join-Path $root ('local/session-'+[guid]::NewGuid().ToString('N')+'.assets'))}
    $pool.OwnAssets=$false;$pool.CopyPixels=-not $Context.ContainsKey('AssetPath')
    try {
        if($Context.ContainsKey('AssetPath')){$pool.Assets=$Context.AssetPath}
        else {
            $pool.OwnAssets=$true
            $palette=[int[][]]::new(256)
            for($i=0;$i -lt 256;$i++){$palette[$i]=@($Context.Content.Palette.Data[3*$i],$Context.Content.Palette.Data[3*$i+1],$Context.Content.Palette.Data[3*$i+2])}
            Write-GameRenderAssets $Context $palette $pool.Assets
        }
        for($i=0;$i -lt $Workers;$i++) {
            $name='Local\pwshDoom-game-'+[guid]::NewGuid().ToString('N')
            $map=[IO.MemoryMappedFiles.MemoryMappedFile]::CreateNew($name,4194304);$view=$map.CreateViewAccessor()
            $ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$name+'-ready')
            $go=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,$name+'-go')
            $done=[Threading.EventWaitHandle]::new($true,[Threading.EventResetMode]::ManualReset,$name+'-done')
            $first=[int][Math]::Floor($i*320.0/$Workers);$end=[int][Math]::Floor(($i+1)*320.0/$Workers)
            if($Style -ne 'Classic'){$first=2*[int][Math]::Floor($i*160.0/$Workers);$end=2*[int][Math]::Floor(($i+1)*160.0/$Workers)}
            $info=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
            $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
            foreach($arg in @('-NoProfile','-File',"$root/scripts/Invoke-GameRenderWorker.ps1",'-Assets',$pool.Assets,'-OwnerPid',"$PID",'-Channel',$name,'-FirstColumn',"$first",'-EndColumn',"$end",'-Style',$Style,'-GlyphSet',$GlyphSet)){$info.ArgumentList.Add($arg)}
            $process=[Diagnostics.Process]::Start($info)
            $pool.Workers.Add(@{Map=$map;View=$view;Ready=$ready;Go=$go;Done=$done;Process=$process;First=$first;End=$end;
                Stdout=$process.StandardOutput.ReadToEndAsync();Stderr=$process.StandardError.ReadToEndAsync()})
        }
        foreach($worker in $pool.Workers){if(-not $worker.Ready.WaitOne(30000)){throw 'Game renderer startup timed out.'};Get-GameWorkerError $worker}
        return $pool
    } catch {Close-GameRenderPool $pool;throw}
}
function Get-GameWorkerError {
    param($Worker)
    if($Worker.View.ReadInt32(12) -ne 0) {
        $bytes=[byte[]]::new($Worker.View.ReadInt32(8));[void]$Worker.View.ReadArray(1114112L,$bytes,0,$bytes.Length)
        throw [Text.Encoding]::UTF8.GetString($bytes)
    }
    if($Worker.Process.HasExited){throw "Game worker exited: $($Worker.Stderr.Result)"}
}
function Test-GameRenderCompleted {
    param($Pool)
    foreach($worker in $Pool.Workers){if(-not $worker.Done.WaitOne(0)){return $false}}
    return $true
}
function Submit-GameRender {
    param($Pool,$Snapshot,[int]$ColumnOffset=0,[int]$RowOffset=0,[int]$FrameNumber=0,[switch]$ScreenPixels,[int]$Tic=0)
    if(-not (Test-GameRenderCompleted $Pool)){throw 'A render is already in progress.'}
    if($Snapshot -is [byte[]]){$bytes=$Snapshot}else{$bytes=ConvertTo-GameSnapshotBytes $Snapshot}
    if($bytes.Length -gt 1048448){throw 'Snapshot exceeds transport capacity.'}
    if($ScreenPixels -and $bytes.Length -ne 64000){throw 'Session screens require 320x200 indexed pixels.'}
    foreach($worker in $Pool.Workers) {
        [void]$worker.Done.Reset();$worker.View.Write(4,$bytes.Length);$worker.View.WriteArray(128L,$bytes,0,$bytes.Length)
        $worker.View.Write(64,$ColumnOffset);$worker.View.Write(68,$RowOffset);$worker.View.Write(72,$FrameNumber)
        $worker.View.Write(76,[int][bool]$ScreenPixels);$worker.View.Write(80,$Tic);[void]$worker.Go.Set()
    }
}
function Update-GameRenderAssets {
    param($Pool)
    if(-not (Test-GameRenderCompleted $Pool)){throw 'Drain rendering before changing map assets.'}
    foreach($worker in $Pool.Workers){[void]$worker.Done.Reset();$worker.View.Write(76,2);[void]$worker.Go.Set()}
    foreach($worker in $Pool.Workers){if(-not $worker.Done.WaitOne(30000)){throw 'Map asset reload timed out.'};Get-GameWorkerError $worker}
    $Pool.Results=[object[]]::new($Pool.Count)
}
function Wait-GameRender {
    param($Pool,[int]$TimeoutMs=30000,[switch]$ReadPixels)
    for($i=0;$i -lt $Pool.Count;$i++) {
        $worker=$Pool.Workers[$i]
        if(-not $worker.Done.WaitOne($TimeoutMs)){throw 'Game renderer timed out.'}
        Get-GameWorkerError $worker
        $view=$worker.View;$bytes=[byte[]]::new($view.ReadInt32(8));$pixels=$null
        [void]$view.ReadArray(1114112L,$bytes,0,$bytes.Length)
        if($ReadPixels -or $Pool.CopyPixels){$pixels=[byte[]]::new(64000);[void]$view.ReadArray(1048576L,$pixels,0,64000)}
        $Pool.Results[$i]=@{Bytes=$bytes;Pixels=$pixels;RenderMs=$view.ReadDouble(16);EncodeMs=$view.ReadDouble(24);DecodeMs=$view.ReadDouble(40);StartedQpc=$view.ReadInt64(48);DoneQpc=$view.ReadInt64(56);Tic=$view.ReadInt32(32)}
    }
}
function Close-GameRenderPool {
    param($Pool)
    foreach($worker in $Pool.Workers){$worker.View.Write(0,1);[void]$worker.Go.Set()}
    foreach($worker in $Pool.Workers) {
        if(-not $worker.Process.WaitForExit(5000)){$worker.Process.Kill();$worker.Process.WaitForExit()}
        $worker.Process.Dispose();$worker.View.Dispose();$worker.Map.Dispose();$worker.Go.Dispose();$worker.Done.Dispose();$worker.Ready.Dispose()
    }
    if($Pool.OwnAssets -and (Test-Path -LiteralPath $Pool.Assets)){Remove-Item -LiteralPath $Pool.Assets}
}
