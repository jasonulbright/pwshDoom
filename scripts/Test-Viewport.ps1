#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/Viewport.ps1"
$checks=[Collections.Generic.List[object]]::new()
foreach($case in @(@(320,100,$false,$true,0,0),@(319,100,$false,$false,0,0),@(320,99,$false,$false,0,0),
    @(589,98,$false,$false,0,0),@(688,123,$false,$true,184,11),@(480,108,$false,$true,80,4),
    @(800,150,$false,$true,240,25),@(320,102,$true,$true,0,2),@(320,100,$true,$false,0,2))) {
    $v=Get-DoomViewport $case[0] $case[1] -Diagnostics:$case[2]
    if($v.Fits -ne $case[3] -or $v.Left -ne $case[4] -or $v.Top -ne $case[5]){throw 'Viewport fit/centering mismatch.'}
    if($v.Fits -and ($v.Left+320 -gt $v.Columns -or $v.Top+100 -gt $v.Rows)){throw 'Image extends outside terminal.'}
    $checks.Add(@{Columns=$case[0];Rows=$case[1];Diagnostics=$case[2];Fits=$v.Fits;Left=$v.Left;Top=$v.Top})
}
foreach($size in @(@(8,1),@(40,2),@(320,98))) {
    $v=Get-DoomViewport $size[0] $size[1];$lines=(Get-DoomViewportMessage $v).Split("`r`n")
    if($lines.Count -gt $size[1] -or @($lines | Where-Object {$_.Length -ge $size[0]}).Count){throw 'Pause message wraps outside a small viewport.'}
}
$id=[guid]::NewGuid().ToString('N');$schedule="$PSScriptRoot/../local/viewport-$id.json";$report="$PSScriptRoot/../local/viewport-$id-session.json"
@(@{AtSeconds=0;Columns=589;Rows=98},@{AtSeconds=.8;Columns=320;Rows=100},
    @{AtSeconds=1.8;Columns=800;Rows=150},@{AtSeconds=2.4;Columns=320;Rows=97},
    @{AtSeconds=3.4;Columns=320;Rows=100}) | ConvertTo-Json | Set-Content -LiteralPath $schedule
$runtime=(Get-Process -Id $PID).Path
& $runtime -NoProfile -File "$PSScriptRoot/Invoke-Doom.ps1" -Wad $Wad -Workers 4 -Headless -Scripted -Seconds 5 -ViewportSchedule $schedule -Report $report
if($LASTEXITCODE -ne 0){throw 'Synthetic viewport integration run failed.'}
$session=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
if($session.Error -or $session.ExitReason -ne 'Duration' -or $session.ViewportPauseCount -ne 2 -or $session.ViewportChanges.Count -ne 5){throw 'Pause/resume history mismatch.'}
$history=$session.ViewportChanges
foreach($pair in @(@(0,1),@(3,4))) {
    if($history[$pair[0]].IssuedCommands -ne $history[$pair[1]].IssuedCommands){throw 'New simulation commands were issued while the viewport was too small.'}
    if([Math]::Abs($history[$pair[1]].ActiveMs-$history[$pair[0]].ActiveMs) -gt 5){throw 'Active clock advanced during the resize pause.'}
}
if($session.ViewportPausedSeconds -lt 1.65 -or $session.ViewportPausedSeconds -gt 2.1){throw 'Pause accounting mismatch.'}
if($session.CompletedFrames -lt 1 -or $session.SimulationTics -lt 80){throw 'Game did not resume rendering/simulation.'}
Copy-Item -LiteralPath $report -Destination "$PSScriptRoot/../results/viewport-resize-session.json"
@{FinishedUtc=[DateTime]::UtcNow.ToString('o');LayoutChecks=$checks.ToArray();PauseMessageSizes=3;
    Integration=@{Result='Pass';Pauses=$session.ViewportPauseCount;ViewportPausedSeconds=$session.ViewportPausedSeconds;
        ActiveSeconds=$session.DurationSeconds;WallSeconds=$session.WallDurationSeconds;History=$history};
    Meaning='Synthetic terminal-grid tests with real headless simulation/render workers. The 98-row startup pauses, exact 320x100 resumes, enlargement recenters, shrinking pauses, restoration resumes without catch-up. No physical desktop resize or 1080p-monitor observation is claimed.'} |
    ConvertTo-Json -Depth 7 | Set-Content "$PSScriptRoot/../results/viewport-tests.json"
'PASS: viewport bounds, centered placement, pause messages, and real-game pause/resume with synthetic dimensions.'
