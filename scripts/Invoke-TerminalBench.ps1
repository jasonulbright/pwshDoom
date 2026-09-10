#requires -Version 7.4
[CmdletBinding()]
param([string]$Plan = (Join-Path $PSScriptRoot '../local/plan.json'),
    [string]$Output = (Join-Path $PSScriptRoot '../results/terminal.json'),
    [int]$HoldSeconds = 0)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/FrameCodec.ps1"
if (-not $env:WT_SESSION -or [Console]::IsOutputRedirected) { throw 'Run this script inside an actual Windows Terminal window.' }
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = Join-Path $root 'local/frames'
$manifest = Get-Content -Raw (Join-Path $cache 'manifest.json') | ConvertFrom-Json
$cases = Get-Content -Raw $Plan | ConvertFrom-Json
$originalEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$stream = [Console]::OpenStandardOutput()
$esc = [char]27
$frequency = [Diagnostics.Stopwatch]::Frequency
$report = [ordered]@{ StartedUtc=[DateTime]::UtcNow.ToString('o'); PowerShell=$PSVersionTable.PSVersion.ToString();
    Executable=(Get-Process -Id $PID).Path; ProcessId=$PID; TerminalSession=$env:WT_SESSION;
    GridWidth=[Console]::WindowWidth;GridHeight=[Console]::WindowHeight;
    OutputCodePage=[Console]::OutputEncoding.CodePage;OriginalOutputCodePage=$originalEncoding.CodePage;
    Meaning='Pre-encoded frames. Completed write rate is NOT displayed frame rate.'; Cases=@() }
function Write-Control([string]$Text) { $b=[Text.Encoding]::UTF8.GetBytes($Text); $stream.Write($b,0,$b.Length) }
try {
    [Console]::Title = 'pwshDoom benchmark'
    Write-Control "$esc[?1049h$esc[?25l$esc[?7l$esc[2J"
    foreach ($case in $cases) {
        $entry = @($manifest | Where-Object Id -eq $case.Id)
        if ($entry.Count -ne 1) { throw "Missing/ambiguous cache: $($case.Id)" }
        $entry = $entry[0]
        if ($entry.Codec -eq 'Ansi' -and ([Console]::WindowWidth -lt $entry.Width -or [Console]::WindowHeight -lt ([Math]::Ceiling($entry.Height/2)+3))) {
            throw "ANSI image $($entry.Id) will not fit the terminal grid: $([Console]::WindowWidth)x$([Console]::WindowHeight)."
        }
        $frames = [Collections.Generic.List[byte[]]]::new()
        for ($n=0;$n -lt $entry.Files.Count;$n++) {
            $prefix = "$esc[0m$esc[1;1H$($case.Id) sync=$($case.Sync) target=$($case.Fps) phase=$n$esc[K$esc[3;1H"
            if ($case.Sync) { $prefix = "$esc[?2026h$prefix" }
            $suffix = "$esc[0m"
            if ($case.Sync) { $suffix += "$esc[?2026l" }
            $a=[Text.Encoding]::UTF8.GetBytes($prefix)
            $b=[IO.File]::ReadAllBytes((Join-Path $cache $entry.Files[$n]))
            $c=[Text.Encoding]::UTF8.GetBytes($suffix)
            $frame=[byte[]]::new($a.Length+$b.Length+$c.Length)
            [Array]::Copy($a,0,$frame,0,$a.Length); [Array]::Copy($b,0,$frame,$a.Length,$b.Length); [Array]::Copy($c,0,$frame,$a.Length+$b.Length,$c.Length)
            $frames.Add($frame)
        }
        Write-Control "$esc[?2026l$esc[0m$esc[2J"
        Start-Sleep -Milliseconds 400
        for ($warm=0;$warm -lt 8;$warm++) { $f=$frames[$warm % $frames.Count]; $stream.Write($f,0,$f.Length) }
        Start-Sleep -Milliseconds 500
        $writeMs=[Collections.Generic.List[double]]::new()
        $startTimes=[Collections.Generic.List[double]]::new()
        $bytesWritten=[long]0
        $utc=[DateTime]::UtcNow.ToString('o')
        $start=[Diagnostics.Stopwatch]::GetTimestamp()
        $deadline=$start+[long]($case.Seconds*$frequency)
        $i=0
        while ([Diagnostics.Stopwatch]::GetTimestamp() -lt $deadline) {
            if ($case.Fps -gt 0 -and $i -gt 0) {
                $target=$start+[long]($i*$frequency/$case.Fps)
                $remaining=($target-[Diagnostics.Stopwatch]::GetTimestamp())*1000.0/$frequency
                if ($remaining -gt 2) { [Threading.Thread]::Sleep([int][Math]::Floor($remaining-1)) }
                while ([Diagnostics.Stopwatch]::GetTimestamp() -lt $target) { [Threading.Thread]::SpinWait(30) }
                if ([Diagnostics.Stopwatch]::GetTimestamp() -ge $deadline) { break }
            }
            $f=$frames[$i % $frames.Count]
            $before=[Diagnostics.Stopwatch]::GetTimestamp()
            $stream.Write($f,0,$f.Length)
            $after=[Diagnostics.Stopwatch]::GetTimestamp()
            $startTimes.Add(($before-$start)*1000.0/$frequency)
            $writeMs.Add(($after-$before)*1000.0/$frequency)
            $bytesWritten+=$f.Length
            $i++
        }
        $elapsed=([Diagnostics.Stopwatch]::GetTimestamp()-$start)/[double]$frequency
        $result=[ordered]@{Id=$case.Id;Sync=[bool]$case.Sync;TargetFps=$case.Fps;RequestedSeconds=$case.Seconds;
            StartedUtc=$utc;StartQpc=$start;QpcFrequency=$frequency;ElapsedSeconds=$elapsed;CompletedWrites=$i;
            CompletedWritesPerSecond=$i/$elapsed;BytesWritten=$bytesWritten;WriteMs=(Get-SampleStats $writeMs.ToArray());
            WriteStartSamplesMs=$startTimes.ToArray();WriteSamplesMs=$writeMs.ToArray()}
        $report.Cases += $result
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
        # Let queued output drain between finite cases; this is not an acknowledgement.
        Start-Sleep -Milliseconds 700
    }
    if ($HoldSeconds -gt 0) { Start-Sleep -Seconds $HoldSeconds }
    $report['FinishedUtc']=[DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
} catch {
    $report.Error=$_.ToString()
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
    throw
} finally {
    Write-Control "$esc[?2026l$esc[0m$esc[?7h$esc[?25h$esc[?1049l"
    $stream.Dispose()
    [Console]::OutputEncoding = $originalEncoding
}
