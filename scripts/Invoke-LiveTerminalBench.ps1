#requires -Version 7.4
[CmdletBinding()]
param([string]$Output = (Join-Path $PSScriptRoot '../results/terminal-live.json'))
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
if (-not $env:WT_SESSION -or [Console]::IsOutputRedirected) { throw 'Requires Windows Terminal.' }
$esc=[char]27
$originalEncoding=[Console]::OutputEncoding
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$stream=[Console]::OpenStandardOutput()
$frequency=[Diagnostics.Stopwatch]::Frequency
$report=[ordered]@{StartedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
    Executable=(Get-Process -Id $PID).Path;GridWidth=[Console]::WindowWidth;GridHeight=[Console]::WindowHeight;
    OutputCodePage=[Console]::OutputEncoding.CodePage;OriginalOutputCodePage=$originalEncoding.CodePage;
    Meaning='Live synthetic generation + PowerShell encoding + completed writes. NOT displayed FPS.';Cases=@()}
function Send-Control([string]$s) { $b=[Text.Encoding]::UTF8.GetBytes($s);$stream.Write($b,0,$b.Length) }
try {
    Send-Control "$esc[?1049h$esc[?25l$esc[?7l$esc[2J"
    if ([Console]::WindowWidth -lt 320 -or [Console]::WindowHeight -lt 103) { throw 'Requires 320x103 cells.' }
    foreach ($repeat in 1,2) {
        foreach ($pattern in 'Coherent','Entropy') {
            $ctx=New-CodecContext (New-TestPalette 256)
            $codecs=if ($repeat -eq 1) { @('AnsiFast','Sixel','SixelFast') } else { @('SixelFast','Sixel','AnsiFast') }
            foreach ($codec in $codecs) {
                $fn="ConvertTo-${codec}Frame"
                $p=New-IndexedFrame 320 200 0 $pattern 256
                for($j=0;$j -lt 3;$j++) { $null=& $fn $p 320 200 $ctx }
                Send-Control "$esc[?2026l$esc[0m$esc[2J"
                Start-Sleep -Milliseconds 500
                $gen=[Collections.Generic.List[double]]::new()
                $enc=[Collections.Generic.List[double]]::new()
                $write=[Collections.Generic.List[double]]::new()
                $i=0;$totalBytes=[long]0
                $start=[Diagnostics.Stopwatch]::GetTimestamp()
                $deadline=$start+5*$frequency
                while([Diagnostics.Stopwatch]::GetTimestamp() -lt $deadline) {
                    $t0=[Diagnostics.Stopwatch]::GetTimestamp()
                    $p=New-IndexedFrame 320 200 $i $pattern 256
                    $t1=[Diagnostics.Stopwatch]::GetTimestamp()
                    $frame=& $fn $p 320 200 $ctx
                    $prefix="$esc[?2026h$esc[0m$esc[1;1HLIVE $codec $pattern 320x200 256colors frame=$i$esc[K$esc[3;1H"
                    $b=[Text.Encoding]::UTF8.GetBytes($prefix+$frame+"$esc[0m$esc[?2026l")
                    $t2=[Diagnostics.Stopwatch]::GetTimestamp()
                    $stream.Write($b,0,$b.Length)
                    $t3=[Diagnostics.Stopwatch]::GetTimestamp()
                    $gen.Add(($t1-$t0)*1000.0/$frequency)
                    $enc.Add(($t2-$t1)*1000.0/$frequency)
                    $write.Add(($t3-$t2)*1000.0/$frequency)
                    $totalBytes+=$b.Length;$i++
                }
                $elapsed=([Diagnostics.Stopwatch]::GetTimestamp()-$start)/[double]$frequency
                $report.Cases+=@{Codec=$codec;Pattern=$pattern;Width=320;Height=200;Colors=256;Repeat=$repeat;Sync=$true;
                    CompletedWrites=$i;ElapsedSeconds=$elapsed;CompletedWritesPerSecond=$i/$elapsed;BytesWritten=$totalBytes;
                    GenerationMs=(Get-SampleStats $gen.ToArray());EncodingIncludingUtf8Ms=(Get-SampleStats $enc.ToArray());
                    WriteMs=(Get-SampleStats $write.ToArray());GenerationSamplesMs=$gen.ToArray();EncodingSamplesMs=$enc.ToArray();WriteSamplesMs=$write.ToArray()}
                $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
                Start-Sleep -Milliseconds 700
            }
        }
    }
    $report['FinishedUtc']=[DateTime]::UtcNow.ToString('o')
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
} catch {
    $report.Error=$_.ToString()
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
    throw
} finally {
    Send-Control "$esc[?2026l$esc[0m$esc[?7h$esc[?25h$esc[?1049l"
    $stream.Dispose()
    [Console]::OutputEncoding=$originalEncoding
}
