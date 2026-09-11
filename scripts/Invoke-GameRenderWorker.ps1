#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Assets,[string]$Channel,[int]$FirstColumn,[int]$EndColumn,[int]$OwnerPid,
    [ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/RenderAssets.ps1"
. "$PSScriptRoot/../src/SnapshotTransport.ps1"
. "$PSScriptRoot/../src/TerminalCodec.ps1"
. "$PSScriptRoot/FrameCodec.ps1"
. "$PSScriptRoot/../src/CharacterCodec.ps1"
$map=[IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting($Channel);$view=$map.CreateViewAccessor()
$ready=[Threading.EventWaitHandle]::OpenExisting($Channel+'-ready');$go=[Threading.EventWaitHandle]::OpenExisting($Channel+'-go');$done=[Threading.EventWaitHandle]::OpenExisting($Channel+'-done')
try {
    $owner=if($OwnerPid -gt 0){[Diagnostics.Process]::GetProcessById($OwnerPid)}else{$null}
    $previousSnapshot=$null;$ctx=Read-GameRenderAssets $Assets
    $codec=if($Style -eq 'Classic'){New-CodecContext $ctx.Palette}else{New-CharacterCodecContext $ctx.Palette $Style}
    [void]$ready.Set()
    while($true) {
        if(-not $go.WaitOne(1000)){if($null -ne $owner -and $owner.HasExited){break};continue}
        if($view.ReadInt32(0) -ne 0){break}
        $view.Write(48,[long][Diagnostics.Stopwatch]::GetTimestamp())
        $length=$view.ReadInt32(4);if($length -le 0 -or $length -gt 1048448){throw 'Invalid snapshot length.'}
        $bytes=[byte[]]::new($length);[void]$view.ReadArray(128L,$bytes,0,$length)
        $decodeWatch=[Diagnostics.Stopwatch]::StartNew();$snapshot=Read-GameSnapshotBytes $bytes $previousSnapshot;$previousSnapshot=$snapshot;$view.Write(40,$decodeWatch.Elapsed.TotalMilliseconds)
        $ctx.World=$snapshot;$ctx.Sectors=$snapshot.Sectors;$ctx.Sides=$snapshot.Sides
        $watch=[Diagnostics.Stopwatch]::StartNew();Invoke-FastRender $ctx $FirstColumn $EndColumn
        $view.Write(16,$watch.Elapsed.TotalMilliseconds);$watch.Restart()
        $encoded=if($Style -eq 'Classic'){
            ConvertTo-AnsiStrip $ctx.Pixels 320 200 $FirstColumn $EndColumn $codec -ColumnOffset ($view.ReadInt32(64)) -RowOffset ($view.ReadInt32(68))
        }else{
            ConvertTo-CharacterStrip $ctx.Pixels 320 200 $FirstColumn $EndColumn $codec -ColumnOffset ($view.ReadInt32(64)) -RowOffset ($view.ReadInt32(68)) -FrameNumber ($view.ReadInt32(72))
        }
        if($encoded.Length -gt 3000000){throw 'Encoded frame exceeds transport capacity.'}
        $view.Write(24,$watch.Elapsed.TotalMilliseconds);$view.Write(8,$encoded.Length);$view.Write(32,[int]$snapshot.Tic)
        $view.WriteArray(1048576L,$ctx.Pixels,0,64000);$view.WriteArray(1114112L,$encoded,0,$encoded.Length)
        $view.Write(56,[long][Diagnostics.Stopwatch]::GetTimestamp());[void]$done.Set()
    }
} catch {
    $errorBytes=[Text.Encoding]::UTF8.GetBytes($_.ToString()+"`n"+$_.ScriptStackTrace)
    $view.Write(12,1);$view.Write(8,$errorBytes.Length);$view.WriteArray(1114112L,$errorBytes,0,$errorBytes.Length)
    [void]$ready.Set();[void]$done.Set()
} finally {$ready.Dispose();$go.Dispose();$done.Dispose();$view.Dispose();$map.Dispose()}
