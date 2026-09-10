# Experimental backend retained for the failed runspace measurement.
function New-GameRenderPool {
    param($Context,$Codec,[int]$Workers=16)
    $pool=@{Workers=[Collections.Generic.List[object]]::new();Done=[Threading.CountdownEvent]::new(0);
        Results=[object[]]::new($Workers);Errors=[Collections.Concurrent.ConcurrentQueue[string]]::new();Count=$Workers}
    $workerScript={
        param($root,$ctx,$codec,$queue,$done,$results,$errors,$index,$first,$end)
        $ErrorActionPreference='Stop'
        . "$root/src/FastRenderer.ps1"
        . "$root/src/TerminalCodec.ps1"
        foreach($snapshot in $queue.GetConsumingEnumerable()) {
            try {
                $ctx.World=$snapshot;$ctx.Sectors=$snapshot.Sectors;$ctx.Sides=$snapshot.Sides
                $watch=[Diagnostics.Stopwatch]::StartNew()
                Invoke-FastRender $ctx $first $end
                $renderMs=$watch.Elapsed.TotalMilliseconds;$watch.Restart()
                $bytes=ConvertTo-AnsiStrip $ctx.Pixels 320 200 $first $end $codec
                $results[$index]=@{Bytes=$bytes;Pixels=$ctx.Pixels;RenderMs=$renderMs;EncodeMs=$watch.Elapsed.TotalMilliseconds;Tic=$snapshot.Tic;Profile=$ctx.Profile}
            } catch {$errors.Enqueue($_.ToString()+"`n"+$_.ScriptStackTrace)}
            finally {[void]$done.Signal()}
        }
    }
    try {
        for($i=0;$i -lt $Workers;$i++) {
            $ctx=$Context.Clone()
            $ctx.Pixels=[byte[]]::new(64000);$ctx.Depth=[double[]]::new(64000);$ctx.Planes=[int[]]::new(53760)
            $ctx.TopClip=[int[]]::new(320);$ctx.BottomClip=[int[]]::new(320);$ctx.Stack=[int[]]::new($Context.Stack.Length)
            # Shared textures, patches and BSP arrays are immutable after this point.
            $queue=[Collections.Concurrent.BlockingCollection[object]]::new(1)
            $ps=[PowerShell]::Create();$runspace=[runspacefactory]::CreateRunspace();$runspace.Open();$ps.Runspace=$runspace
            $first=[int][Math]::Floor($i*320.0/$Workers);$end=[int][Math]::Floor(($i+1)*320.0/$Workers)
            [void]$ps.AddScript($workerScript.ToString()).AddArgument((Split-Path $PSScriptRoot)).AddArgument($ctx).AddArgument($Codec).AddArgument($queue).AddArgument($pool.Done).AddArgument($pool.Results).AddArgument($pool.Errors).AddArgument($i).AddArgument($first).AddArgument($end)
            $handle=$ps.BeginInvoke()
            $pool.Workers.Add(@{PowerShell=$ps;Runspace=$runspace;Queue=$queue;Handle=$handle;First=$first;End=$end})
        }
        return $pool
    } catch {Close-GameRenderPool $pool;throw}
}

function Submit-GameRender {
    param($Pool,$Snapshot)
    if(-not $Pool.Done.IsSet){throw 'A render is already in progress.'}
    $Pool.Done.Reset($Pool.Count)
    foreach($worker in $Pool.Workers){$worker.Queue.Add($Snapshot)}
}

function Wait-GameRender {
    param($Pool,[int]$TimeoutMs=30000)
    if(-not $Pool.Done.Wait($TimeoutMs)){throw 'Render workers timed out.'}
    $failure=''
    if($Pool.Errors.TryDequeue([ref]$failure)){throw $failure}
}

function Close-GameRenderPool {
    param($Pool)
    foreach($worker in $Pool.Workers){$worker.Queue.CompleteAdding()}
    foreach($worker in $Pool.Workers) {
        if(-not $worker.Handle.AsyncWaitHandle.WaitOne(5000)){$worker.PowerShell.Stop()}
        try{$null=$worker.PowerShell.EndInvoke($worker.Handle)}catch{}
        $worker.PowerShell.Dispose();$worker.Runspace.Dispose();$worker.Queue.Dispose()
    }
    $Pool.Done.Dispose()
}
