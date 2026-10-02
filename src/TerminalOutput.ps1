# SPDX-License-Identifier: GPL-2.0-or-later
# Preserve the encoded terminal byte stream while selecting write granularity.
function New-DoomTerminalOutputContext {
    return @{Buffer=[byte[]]::new(0);Frames=0L;Bytes=0L;Writes=0L;Pending=$null}
}
function Get-DoomOutputThreadPoolState {
    [int]$available=0;[int]$availableIO=0;[int]$maximum=0;[int]$maximumIO=0;[int]$minimum=0;[int]$minimumIO=0
    [Threading.ThreadPool]::GetAvailableThreads([ref]$available,[ref]$availableIO)
    [Threading.ThreadPool]::GetMaxThreads([ref]$maximum,[ref]$maximumIO)
    [Threading.ThreadPool]::GetMinThreads([ref]$minimum,[ref]$minimumIO)
    return @{MinWorkerThreads=$minimum;WorkerThreads=[Threading.ThreadPool]::ThreadCount;BusyWorkerThreads=$maximum-$available;PendingWorkItems=[Threading.ThreadPool]::PendingWorkItemCount}
}
function Copy-DoomTerminalFrame {
    param($Context,$Results,[byte[]]$Start,[byte[]]$End,[byte[]]$Clear,[byte[]]$Status)
    if($null -ne $Context.Pending){throw 'A terminal write already owns the frame buffer.'}
    [int]$length=$Start.Length+$End.Length+$Clear.Length+$Status.Length
    foreach($result in $Results){$length+=$result.Bytes.Length}
    if($Context.Buffer.Length -lt $length){$Context.Buffer=[byte[]]::new([int]([Math]::Ceiling($length/65536.0)*65536))}
    [byte[]]$buffer=$Context.Buffer;[int]$offset=0
    [Buffer]::BlockCopy($Start,0,$buffer,$offset,$Start.Length);$offset+=$Start.Length
    [Buffer]::BlockCopy($Clear,0,$buffer,$offset,$Clear.Length);$offset+=$Clear.Length
    foreach($result in $Results){[Buffer]::BlockCopy($result.Bytes,0,$buffer,$offset,$result.Bytes.Length);$offset+=$result.Bytes.Length}
    [Buffer]::BlockCopy($Status,0,$buffer,$offset,$Status.Length);$offset+=$Status.Length
    [Buffer]::BlockCopy($End,0,$buffer,$offset,$End.Length)
    return $length
}
function Start-DoomTerminalFrame {
    param($Context,[IO.Stream]$Stream,$Results,[byte[]]$Start,[byte[]]$End,
        [byte[]]$Clear=[byte[]]::new(0),[byte[]]$Status=[byte[]]::new(0))
    $startQpc=[Diagnostics.Stopwatch]::GetTimestamp()
    $length=Copy-DoomTerminalFrame $Context $Results $Start $End $Clear $Status
    $writeStartQpc=[Diagnostics.Stopwatch]::GetTimestamp()
    $task=$Stream.WriteAsync($Context.Buffer,0,$length)
    $job=@{Task=$task;Bytes=$length;StartQpc=$startQpc;WriteStartQpc=$writeStartQpc;DispatchQpc=[Diagnostics.Stopwatch]::GetTimestamp();
        LastIncompleteQpc=0L;FirstCompletedObservationQpc=0L;CompletionProbes=0;PendingProbes=0}
    $null=Test-DoomTerminalTaskCompletion $job
    $Context.Pending=$job
    return $job
}
function Test-DoomTerminalTaskCompletion {
    param($Job)
    # A false read proves incompletion at the timestamp BEFORE that read.
    # A true read proves completion by the timestamp AFTER it. Preserve the
    # first true observation; later host/flush delay must not widen the bound.
    $before=[Diagnostics.Stopwatch]::GetTimestamp();$done=$Job.Task.IsCompleted;$after=[Diagnostics.Stopwatch]::GetTimestamp()
    $Job.CompletionProbes++
    if(-not $done){$Job.PendingProbes++;$Job.LastIncompleteQpc=$before}
    elseif($Job.FirstCompletedObservationQpc -eq 0){$Job.FirstCompletedObservationQpc=$after}
    return $done
}
function Complete-DoomTerminalFrame {
    param($Context,[IO.Stream]$Stream,[switch]$Wait)
    $job=$Context.Pending
    if($null -eq $job){return $null}
    if(-not (Test-DoomTerminalTaskCompletion $job)){
        if(-not $Wait){return $null}
        if(-not $job.Task.Wait(30000)){throw 'Terminal output drain timed out.'}
        $null=Test-DoomTerminalTaskCompletion $job
    }
    [void]$job.Task.GetAwaiter().GetResult();$Stream.Flush()
    $job.EndQpc=[Diagnostics.Stopwatch]::GetTimestamp()
    $Context.Frames++;$Context.Bytes+=$job.Bytes;$Context.Writes++;$Context.Pending=$null
    return $job
}
function Write-DoomTerminalFrame {
    param($Context,[IO.Stream]$Stream,$Results,[byte[]]$Start,[byte[]]$End,
        [byte[]]$Clear=[byte[]]::new(0),[byte[]]$Status=[byte[]]::new(0),[ValidateSet('Strips','Batch')][string]$Mode='Strips')
    if($null -ne $Context.Pending){throw 'A terminal write already owns the frame buffer.'}
    [int]$length=$Start.Length+$End.Length+$Clear.Length+$Status.Length
    foreach($result in $Results){$length+=$result.Bytes.Length}
    if($Mode -eq 'Strips'){
        $Stream.Write($Start,0,$Start.Length)
        if($Clear.Length){$Stream.Write($Clear,0,$Clear.Length)}
        foreach($result in $Results){$Stream.Write($result.Bytes,0,$result.Bytes.Length)}
        if($Status.Length){$Stream.Write($Status,0,$Status.Length)}
        $Stream.Write($End,0,$End.Length)
        $Context.Writes+=2+$Results.Count+[int]($Clear.Length -gt 0)+[int]($Status.Length -gt 0)
    }else{
        $length=Copy-DoomTerminalFrame $Context $Results $Start $End $Clear $Status
        $Stream.Write($Context.Buffer,0,$length);$Context.Writes++
    }
    $Stream.Flush();$Context.Frames++;$Context.Bytes+=$length
}
