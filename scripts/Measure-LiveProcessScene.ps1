#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Wad,[ValidateRange(1,20)][int]$Workers=16,
    [ValidateSet('TrueColor','Ansi256')][string]$ColorMode='TrueColor',
    [ValidateRange(2,60)][int]$Seconds=12,
    [switch]$PacedOnly,
    [string]$Output=(Join-Path $PSScriptRoot '../results/process-scene-live.json'))
$ErrorActionPreference='Stop'
if(-not $env:WT_SESSION -or [Console]::IsOutputRedirected){throw 'Run in Windows Terminal.'}
. "$PSScriptRoot/ProcessScene.ps1"
if([Console]::WindowWidth -lt 320 -or [Console]::WindowHeight -lt 103){throw 'Requires at least 320x103 cells.'}
$scene=& "$PSScriptRoot/Measure-DoomScene.ps1" -Wad $Wad -InitializeOnly
$original=[Console]::OutputEncoding
$pool=$null;$stream=$null;$esc=[char]27;$freq=[Diagnostics.Stopwatch]::Frequency
$report=[ordered]@{StartedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
    Executable=(Get-Process -Id $PID).Path;Workers=$Workers;ColorMode=$ColorMode;Width=320;Height=200;
    GridWidth=[Console]::WindowWidth;GridHeight=[Console]::WindowHeight;WadSha256=$scene.WadSha256;
    SourceSha256=$scene.SourceSha256;OutputCodePage=65001;Pacing='Stopwatch + Thread.SpinWait; no coarse Sleep in frame pacing';
    Meaning='Live PowerShell process workers render fresh continuously rotating camera views, encode strips, transfer through shared memory, and write to Terminal. Geometry only, no gameplay. Completed writes are NOT displayed FPS.';Cases=@()}
try {
    $pool=New-ProcessScene $Wad $Workers $ColorMode
    [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
    $stream=[Console]::OpenStandardOutput()
    $control=[Text.Encoding]::UTF8.GetBytes("$esc[?1049h$esc[?25l$esc[?7l$esc[2J")
    $stream.Write($control,0,$control.Length)
    for($warm=0;$warm -lt 64;$warm++){Invoke-ProcessScene $pool ($scene.Level.startA+($warm%8)*[Math]::PI/4)}
    $targets=if($PacedOnly){@(60)}else{@(0,60)}
    foreach($target in $targets){
        $costs=[Collections.Generic.List[object]]::new();$count=0;$bytesWritten=0L
        $suffix=[Text.Encoding]::UTF8.GetBytes("$esc[0m$esc[?2026l")
        $control=[Text.Encoding]::UTF8.GetBytes("$esc[?2026l$esc[0m$esc[2J")
        $stream.Write($control,0,$control.Length)
        Start-Sleep -Milliseconds 700
        $start=[Diagnostics.Stopwatch]::GetTimestamp()
        while(([Diagnostics.Stopwatch]::GetTimestamp()-$start)/[double]$freq -lt $Seconds){
            if($target -gt 0){
                $due=$start+[long]($count*$freq/[double]$target)
                # Sleep can overshoot by a Windows timer quantum. Spending part
                # of one coordinator core is an explicit precision tradeoff.
                while([Diagnostics.Stopwatch]::GetTimestamp() -lt $due){[Threading.Thread]::SpinWait(30)}
                if(([Diagnostics.Stopwatch]::GetTimestamp()-$start)/[double]$freq -ge $Seconds){break}
            }
            $before=[Diagnostics.Stopwatch]::GetTimestamp()
            $angle=$scene.Level.startA+($before-$start)/[double]$freq*0.35
            Invoke-ProcessScene $pool $angle
            $afterBuild=[Diagnostics.Stopwatch]::GetTimestamp()
            $prefix=[Text.Encoding]::UTF8.GetBytes("$esc[?2026h$esc[0m$esc[1;1H320x200 PowerShell $Workers processes $ColorMode target=$target frame=$count$esc[K")
            $stream.Write($prefix,0,$prefix.Length);$bytesWritten+=$prefix.Length
            foreach($worker in $pool.Workers){$b=$worker.Bytes;$stream.Write($b,0,$b.Length);$bytesWritten+=$b.Length}
            $stream.Write($suffix,0,$suffix.Length);$bytesWritten+=$suffix.Length
            $afterWrite=[Diagnostics.Stopwatch]::GetTimestamp()
            $costs.Add(@{ConstructionMs=($afterBuild-$before)*1000.0/$freq;WriteMs=($afterWrite-$afterBuild)*1000.0/$freq;
                TotalWorkMs=($afterWrite-$before)*1000.0/$freq;StartMs=($before-$start)*1000.0/$freq;Angle=$angle})
            $count++
        }
        $elapsed=([Diagnostics.Stopwatch]::GetTimestamp()-$start)/[double]$freq
        $intervals=[Collections.Generic.List[double]]::new()
        $deadlineMisses=0
        for($i=0;$i -lt $costs.Count;$i++){
            if($i -gt 0){$intervals.Add($costs[$i].StartMs-$costs[$i-1].StartMs)}
            if($target -gt 0 -and ($costs[$i].StartMs+$costs[$i].TotalWorkMs) -gt (($i+1)*1000.0/$target)){$deadlineMisses++}
        }
        $report.Cases+=@{RequestedRate=$target;RequestedSeconds=$Seconds;ElapsedSeconds=$elapsed;CompletedWrites=$count;
            CompletedWritesPerSecond=$count/$elapsed;BytesWritten=$bytesWritten;
            ConstructionMs=(Get-SampleStats @($costs | ForEach-Object ConstructionMs));WriteMs=(Get-SampleStats @($costs | ForEach-Object WriteMs));
            WorkMs=(Get-SampleStats @($costs | ForEach-Object TotalWorkMs));
            FramesOver16Point67Ms=@($costs | Where-Object TotalWorkMs -gt (1000.0/60)).Count;
            FrameStartIntervalMs=(Get-SampleStats $intervals.ToArray());CompletionDeadlineMisses=$deadlineMisses;Samples=$costs.ToArray()}
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
    }
    $report['WorkerWorkingSetBytesAtEnd']=($pool.Workers | ForEach-Object {$_.Process.WorkingSet64} | Measure-Object -Sum).Sum
    $report['FinishedUtc']=[DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
} catch {
    $report['Error']=$_.ToString();$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output;throw
} finally {
    if($pool){Close-ProcessScene $pool}
    if($stream){
        $control=[Text.Encoding]::UTF8.GetBytes("$esc[?2026l$esc[0m$esc[?7h$esc[?25h$esc[?1049l")
        $stream.Write($control,0,$control.Length);$stream.Dispose()
    }
    [Console]::OutputEncoding=$original
}
