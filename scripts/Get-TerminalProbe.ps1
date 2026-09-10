#requires -Version 7.4
param([string]$Output=(Join-Path $PSScriptRoot '../results/terminal-probe.json'),[switch]$VerifyGlyphWidth)
$ErrorActionPreference='Stop'
if (-not $env:WT_SESSION -or [Console]::IsOutputRedirected) { throw 'Run inside Windows Terminal.' }
$report=[ordered]@{RecordedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
    Executable=(Get-Process -Id $PID).Path;OutputEncoding=[Console]::OutputEncoding.WebName;
    OutputCodePage=[Console]::OutputEncoding.CodePage;InputEncoding=[Console]::InputEncoding.WebName;
    GridWidth=[Console]::WindowWidth;GridHeight=[Console]::WindowHeight;
    Meaning='Post-benchmark probe in a new window using the same profile/runtime. Not retroactive telemetry of a previous process.'}
if ($VerifyGlyphWidth) {
    $original=[Console]::OutputEncoding
    $stream=[Console]::OpenStandardOutput()
    $bytes=[Text.Encoding]::UTF8.GetBytes([string][char]0x2580)
    $results=@()
    try {
        foreach ($encoding in @($original,[Text.UTF8Encoding]::new($false))) {
            [Console]::OutputEncoding=$encoding
            [Console]::SetCursorPosition(0,3)
            $before=[Console]::CursorLeft
            $stream.Write($bytes,0,$bytes.Length)
            $after=[Console]::CursorLeft
            $results+=@{OutputCodePage=$encoding.CodePage;Bytes=$bytes.Length;CursorColumnsAdvanced=$after-$before}
        }
    } finally {
        [Console]::OutputEncoding=$original
        $stream.Dispose()
    }
    $report['HalfBlockUtf8Probe']=$results
    $report['ProbeMeaning']='Console cursor advancement for three raw UTF-8 bytes encoding U+2580. This tests decoding/cell width, not monitor-visible pixels.'
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Output
