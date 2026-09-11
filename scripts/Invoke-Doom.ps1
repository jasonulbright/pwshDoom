#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Wad,[ValidateRange(1,32)][int]$Workers=16,
    [ValidateRange(0,3600)][int]$Seconds=0,[switch]$Headless,[switch]$Scripted,[string]$Replay,
    [ValidateRange(0,10000)][int]$CaptureEveryTics=0,[ValidateRange(1,5)][int]$Skill=3,
    [ValidateRange(1,4)][int]$Episode=1,[ValidateRange(1,32)][int]$Map=1,
    [ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic',
    [string]$Report="$PSScriptRoot/../local/game-session.json",[string]$ReadyFile,
    [switch]$Diagnostics,[string]$ViewportSchedule)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/GameProcesses.ps1"
. "$PSScriptRoot/../src/SimulationProcess.ps1";. "$PSScriptRoot/../src/ConsoleInput.ps1"
. "$PSScriptRoot/../src/Viewport.ps1"
# Input values only; the actual TicCmd and Doom engine live in the simulation process.
class HostInputCommand {
    [sbyte]$ForwardMove;[sbyte]$SideMove;[int16]$AngleTurn;[byte]$Buttons
    [void]Clear(){$this.ForwardMove=0;$this.SideMove=0;$this.AngleTurn=0;$this.Buttons=0}
}
function Start-DoomRenderJob {
    param($Pool,$Snapshot,$Clock,$InterpolationTimes,$Viewport)
    $fraction=if($Snapshot.Tic -eq 0){1}else{[Math]::Clamp([double]($Clock.Elapsed.TotalMilliseconds*35/1000-$Snapshot.Tic),[double]0,[double]1)}
    $watch=[Diagnostics.Stopwatch]::StartNew();$bytes=Get-InterpolatedSnapshotBytes $Snapshot.Previous $Snapshot.Current $fraction
    $InterpolationTimes.Add($watch.Elapsed.TotalMilliseconds)
    $qpc=[Diagnostics.Stopwatch]::GetTimestamp();$watch.Restart()
    Submit-GameRender $Pool $bytes -ColumnOffset $Viewport.Left -RowOffset $Viewport.Top -FrameNumber ([int][Math]::Floor($Clock.Elapsed.TotalSeconds*60))
    return @{Tic=$Snapshot.Tic;StartQpc=$qpc;SubmitMs=$watch.Elapsed.TotalMilliseconds;ViewportKey=$Viewport.Key}
}
$simulation=$null;$pool=$null;$consoleState=$null;$terminalActive=$false;$timerRequested=$false;$failure=$null
$oldEncoding=[Console]::OutputEncoding;$esc=[char]27;$clock=[Diagnostics.Stopwatch]::new()
$wallClock=[Diagnostics.Stopwatch]::new();$viewport=$null;$viewportScheduleData=@();$needsClear=$true
$outputColumns=if($Style -eq 'Classic'){320}else{160};$outputRows=if($Style -eq 'Classic'){100}else{50}
$viewportChanges=[Collections.Generic.List[object]]::new();$pauseStart=$null;$pausedMs=0.0;$pauseCount=0;$resizeDiscarded=0
$completed=0;$tics=0;$exitReason='Error';$terminalWidth=0;$terminalHeight=0;$workerMemory=0;$simMemory=0
$frameTimes=[Collections.Generic.List[double]]::new();$frameStats=[Collections.Generic.List[object]]::new()
$captures=[Collections.Generic.List[string]]::new();$nextCapture=$CaptureEveryTics;$snapshot=$null;$replayData=$null
$interpolationTimes=[Collections.Generic.List[double]]::new();$simulationReport=$null
try {
    if($ViewportSchedule) {
        if(-not $Headless){throw 'Synthetic viewport schedules are only allowed with -Headless.'}
        $viewportScheduleData=@(Get-Content -LiteralPath $ViewportSchedule -Raw | ConvertFrom-Json | Sort-Object AtSeconds)
        foreach($entry in $viewportScheduleData){if($entry.AtSeconds -lt 0 -or $entry.Columns -lt 1 -or $entry.Rows -lt 1){throw 'Invalid synthetic viewport schedule.'}}
    }
    $Wad=(Resolve-Path -LiteralPath $Wad).Path;$wadHash=(Get-FileHash -LiteralPath $Wad).Hash
    if($Replay) {
        $replayData=Get-Content -LiteralPath $Replay -Raw | ConvertFrom-Json
        if($replayData.WadSha256 -ne $wadHash){throw 'Replay IWAD hash does not match.'}
        foreach($entry in $replayData.InputCommands) {
            if($entry.Count -ne 4 -or [Math]::Abs($entry[0]) -gt 50 -or [Math]::Abs($entry[1]) -gt 50 -or $entry[2] -lt -32768 -or $entry[2] -gt 32767 -or $entry[3] -lt 0 -or $entry[3] -gt 255){throw 'Invalid replay command.'}
        }
    }
    Write-Host 'Loading the PowerShell simulation and rendering workers...'
    $simulation=New-DoomSimulation $Wad $Skill $Episode $Map
    $snapshot=Read-DoomSimulationSnapshot $simulation $null
    if($null -eq $snapshot){throw 'Initial simulation snapshot was not published.'}
    $context=Read-GameRenderAssets $simulation.Assets;$context.AssetPath=$simulation.Assets
    $paletteBytes=[byte[]]::new(768)
    for($i=0;$i -lt 256;$i++){for($j=0;$j -lt 3;$j++){$paletteBytes[3*$i+$j]=$context.Palette[$i][$j]}}
    [IO.File]::WriteAllBytes("$PSScriptRoot/../local/palette.bin",$paletteBytes)
    $pool=New-GameRenderPool $context $null $Workers -Style $Style
    $initialBytes=Get-InterpolatedSnapshotBytes $snapshot.Previous $snapshot.Current 1
    for($i=0;$i -lt 4;$i++){Submit-GameRender $pool $initialBytes;Wait-GameRender $pool}
    if(-not $Headless) {
        $terminalWidth=[Console]::WindowWidth;$terminalHeight=[Console]::WindowHeight
        [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
        if(-not $Scripted -and -not $Replay){$consoleState=Open-DoomConsoleInput}
        [Console]::Write("$esc[?1049h$esc[?25l$esc[2J");$terminalActive=$true
    }
    Initialize-DoomConsoleApi;$timerRequested=[PwshDoomPlatform.ConsoleApi]::timeBeginPeriod(1) -eq 0
    $stdout=[Console]::OpenStandardOutput();$frameStart=[Text.Encoding]::UTF8.GetBytes("$esc[?2026h");$frameEnd=[Text.Encoding]::UTF8.GetBytes("$esc[0m$esc[?2026l")
    $cmd=[HostInputCommand]::new();$inFlight=$false;$nextPresentation=0.0;$activeFrame=$null;$pendingFrame=$null
    $startQpc=[Diagnostics.Stopwatch]::GetTimestamp();$simulation.View.Write(40,[long]$startQpc);$clock.Start();$wallClock.Start();$lastViewportCheck=-100.0;$exitReason='Quit'
    if($ReadyFile){@{HostPid=$PID;SimulationPid=$simulation.Process.Id;WorkerPids=@($pool.Workers.Process.Id);Assets=$simulation.Assets} | ConvertTo-Json | Set-Content -LiteralPath $ReadyFile}
    while($true) {
        $wallNow=$wallClock.Elapsed.TotalMilliseconds;$status=$simulation.View.ReadInt32(12)
        if($status -eq 3){throw 'Simulation failed; see the simulation error in the session report.'}
        if($status -eq 2){$exitReason='LevelComplete';break}
        if($simulation.Process.HasExited){throw 'Simulation exited unexpectedly.'}
        if($Seconds -gt 0 -and $wallNow -ge $Seconds*1000){$exitReason='Duration';break}
        if($null -ne $consoleState){Read-DoomConsoleInput $consoleState;if($consoleState.Keys[27] -or $consoleState.Pressed[27]){break}}
        if($wallNow-$lastViewportCheck -ge 100) {
            $lastViewportCheck=$wallNow
            if($Headless) {
                $columns=$outputColumns;$rows=$outputRows;if($Diagnostics){$rows+=2}
                foreach($entry in $viewportScheduleData){if($entry.AtSeconds*1000 -le $wallNow){$columns=$entry.Columns;$rows=$entry.Rows}else{break}}
            } else {$columns=[Console]::WindowWidth;$rows=[Console]::WindowHeight;$terminalWidth=$columns;$terminalHeight=$rows}
            $nextViewport=Get-DoomViewport $columns $rows -Diagnostics:$Diagnostics -Style $Style
            if($null -eq $viewport -or $nextViewport.Key -ne $viewport.Key) {
                $viewport=$nextViewport;$needsClear=$true
                if(-not $viewport.Fits -and $clock.IsRunning){$clock.Stop();$pauseStart=$wallNow;$pauseCount++}
                elseif($viewport.Fits -and -not $clock.IsRunning) {
                    $pausedMs+=$wallNow-$pauseStart;$pauseStart=$null
                    # Keep the simulation's lateness reference on the active game
                    # clock, so restoring the window does not queue paused tics.
                    $simulation.View.Write(40,[long]([Diagnostics.Stopwatch]::GetTimestamp()-$clock.ElapsedTicks));$clock.Start()
                }
                $viewportChanges.Add(@{WallMs=$wallNow;ActiveMs=$clock.Elapsed.TotalMilliseconds;Columns=$columns;Rows=$rows;Fits=$viewport.Fits;Left=$viewport.Left;Top=$viewport.Top;IssuedCommands=$tics;PublishedSimulationTics=$simulation.View.ReadInt32(20)})
                if(-not $Headless -and -not $viewport.Fits) {
                    [Console]::Write("$esc[?2026h$esc[0m$esc[2J$esc[H"+(Get-DoomViewportMessage $viewport)+"$esc[?2026l")
                }
            }
        }
        $now=$clock.Elapsed.TotalMilliseconds
        if($viewport.Fits -and $now -ge ($tics+1)*1000.0/35) {
            $cmd.Clear();$send=$true
            if($null -ne $replayData) {
                if($tics -ge $replayData.InputCommands.Count){$send=$false;if($simulation.View.ReadInt32(20) -ge $tics){$exitReason='ReplayEnd';break}}
                else{$entry=$replayData.InputCommands[$tics];$cmd.ForwardMove=$entry[0];$cmd.SideMove=$entry[1];$cmd.AngleTurn=$entry[2];$cmd.Buttons=$entry[3]}
            } elseif($null -ne $consoleState){Set-DoomInputCommand $consoleState $cmd}
            elseif($Scripted) {
                $phase=$tics%700
                if($phase -lt 120){$cmd.ForwardMove=25}elseif($phase -lt 260){$cmd.AngleTurn=640}elseif($phase -lt 430){$cmd.ForwardMove=25}
                if(($tics%14) -lt 7){$cmd.Buttons=1};if(($tics%70) -eq 69){$cmd.Buttons=$cmd.Buttons -bor 2}
            }
            if($send){Send-DoomSimulationCommand $simulation $tics @($cmd.ForwardMove,$cmd.SideMove,$cmd.AngleTurn,$cmd.Buttons);$tics++}
        }
        $snapshot=Read-DoomSimulationSnapshot $simulation $snapshot
        if($inFlight -and (Test-GameRenderCompleted $pool)) {
            $captureDue=$CaptureEveryTics -gt 0 -and $activeFrame.Tic -ge $nextCapture
            $harvestWatch=[Diagnostics.Stopwatch]::StartNew();Wait-GameRender $pool 0 -ReadPixels:$captureDue;$harvestMs=$harvestWatch.Elapsed.TotalMilliseconds
            $pendingFrame=$activeFrame;$pendingFrame.HarvestMs=$harvestMs;$pendingFrame.Results=$pool.Results
            $inFlight=$false
        }
        if($null -ne $pendingFrame -and ($pendingFrame.ViewportKey -ne $viewport.Key -or -not $viewport.Fits)){$pendingFrame=$null;$resizeDiscarded++}
        if($viewport.Fits -and $null -ne $pendingFrame -and $clock.Elapsed.TotalMilliseconds -ge $nextPresentation) {
            $present=$pendingFrame;$pendingFrame=$null;$lastFrameTic=$present.Tic
            if($CaptureEveryTics -gt 0 -and $lastFrameTic -ge $nextCapture) {
                $capture=[byte[]]::new(64000)
                for($i=0;$i -lt $pool.Count;$i++){$worker=$pool.Workers[$i];for($y=0;$y -lt 200;$y++){[Array]::Copy($pool.Results[$i].Pixels,$y*320+$worker.First,$capture,$y*320+$worker.First,$worker.End-$worker.First)}}
                $capturePath="$PSScriptRoot/../local/capture-$lastFrameTic.bin";[IO.File]::WriteAllBytes($capturePath,$capture);$captures.Add([IO.Path]::GetFullPath($capturePath));$nextCapture+=$CaptureEveryTics
            }
            # The next render overlaps the current console write. Results are copied
            # out of shared memory before this dispatch, so workers may reuse it.
            $activeFrame=Start-DoomRenderJob $pool $snapshot $clock $interpolationTimes $viewport;$inFlight=$true
            $outputWatch=[Diagnostics.Stopwatch]::StartNew()
            if(-not $Headless) {
                $stdout.Write($frameStart)
                if($needsClear){$stdout.Write([Text.Encoding]::UTF8.GetBytes("$esc[0m$esc[2J"));$needsClear=$false}
                foreach($result in $present.Results){$stdout.Write($result.Bytes)}
                if($Diagnostics) {
                    $statusLine="$esc[$($viewport.StatusTop+1);$($viewport.Left+1)H$esc[0mpwshDoom | WASD move | arrows turn | Ctrl fire | E/Space use | Shift run | 1-7 weapons | Esc quit"
                    $statusLine+="$esc[$($viewport.StatusTop+2);$($viewport.Left+1)Htic $($snapshot.Tic) | $([Math]::Round($completed/[Math]::Max(.01,$clock.Elapsed.TotalSeconds),1)) completed updates/s | health $($snapshot.Current[16]) | kills $($snapshot.Current[18])       "
                    $stdout.Write([Text.Encoding]::UTF8.GetBytes($statusLine))
                }
                $stdout.Write($frameEnd);$stdout.Flush()
            }
            $endQpc=[Diagnostics.Stopwatch]::GetTimestamp();$frameTimes.Add(($endQpc-$present.StartQpc)*1000.0/[Diagnostics.Stopwatch]::Frequency);$completed++
            $frameStats.Add(@{Tic=$lastFrameTic;SubmitMs=$present.SubmitMs;HarvestMs=$present.HarvestMs;OutputMs=$outputWatch.Elapsed.TotalMilliseconds;StartQpc=$present.StartQpc;EndQpc=$endQpc;ElapsedMs=$clock.Elapsed.TotalMilliseconds;
                Workers=@($present.Results | ForEach-Object {,@($_.RenderMs,$_.EncodeMs,$_.DecodeMs,$_.StartedQpc,$_.DoneQpc)})})
            $nextPresentation+=1000.0/60
        }
        if($viewport.Fits -and -not $inFlight -and $null -eq $pendingFrame) {
            $activeFrame=Start-DoomRenderJob $pool $snapshot $clock $interpolationTimes $viewport;$inFlight=$true
        }
        if($inFlight -and ([Diagnostics.Stopwatch]::GetTimestamp()-$activeFrame.StartQpc)/[Diagnostics.Stopwatch]::Frequency -gt 30){throw 'Renderer timed out.'}
        if($viewport.Fits){[Threading.Thread]::Sleep(1)}else{[Threading.Thread]::Sleep(10)}
    }
} catch {$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$exitReason='Error';[Console]::Error.WriteLine($failure);throw}
finally {
    $clock.Stop();$wallClock.Stop();if($null -ne $pauseStart){$pausedMs+=$wallClock.Elapsed.TotalMilliseconds-$pauseStart}
    $measuredTics=if($null -ne $simulation){$simulation.View.ReadInt32(20)}else{0}
    if($timerRequested){$null=[PwshDoomPlatform.ConsoleApi]::timeEndPeriod(1)}
    if($null -ne $simulation -and -not $simulation.Process.HasExited){$simulation.Process.Refresh();$simMemory=$simulation.Process.WorkingSet64}
    if($null -ne $pool) {
        foreach($worker in $pool.Workers){if(-not $worker.Process.HasExited){$worker.Process.Refresh();$workerMemory+=$worker.Process.WorkingSet64}}
        try{Wait-GameRender $pool 30000 -ReadPixels}catch{}
        $image=[byte[]]::new(64000)
        for($i=0;$i -lt $pool.Count;$i++){$result=$pool.Results[$i];if($null -eq $result -or $null -eq $result.Pixels){continue};$worker=$pool.Workers[$i];for($y=0;$y -lt 200;$y++){[Array]::Copy($result.Pixels,$y*320+$worker.First,$image,$y*320+$worker.First,$worker.End-$worker.First)}}
        [IO.File]::WriteAllBytes("$PSScriptRoot/../local/game-frame.bin",$image);Close-GameRenderPool $pool
    }
    if($null -ne $simulation){Close-DoomSimulation $simulation;if(Test-Path -LiteralPath $simulation.Report){$simulationReport=Get-Content -LiteralPath $simulation.Report -Raw | ConvertFrom-Json}}
    if($terminalActive){[Console]::Write("$esc[?2026l$esc[0m$esc[?25h$esc[?1049l")}
    if($null -ne $consoleState){Close-DoomConsoleInput $consoleState};[Console]::OutputEncoding=$oldEncoding
    # Exclude any queued command drained while workers are being closed.
    $simTics=$measuredTics
    $data=@{FinishedUtc=[DateTime]::UtcNow.ToString('o');WadSha256=(Get-FileHash -LiteralPath $Wad).Hash;Workers=$Workers;Skill=$Skill;Episode=$Episode;Map=$Map;
        OutputStyle=$Style;SourceWidth=320;SourceHeight=200;OutputColumns=$outputColumns;OutputRows=$outputRows;
        OutputRepresentation=if($Style -eq 'Classic'){'Two source pixels per truecolor half-block cell'}else{'Lossy 2x4 source-pixel character cells; HUD downsampled to half blocks'};
        Architecture='SeparateSimulation';Transport='NumericV1';QpcFrequency=[Diagnostics.Stopwatch]::Frequency;Headless=[bool]$Headless;Scripted=[bool]$Scripted;Replay=$Replay;ExitReason=$exitReason;Error=$failure;
        DurationSeconds=$clock.Elapsed.TotalSeconds;IssuedCommands=$tics;SimulationTics=$simTics;TicsPerSecond=$simTics/[Math]::Max(.001,$clock.Elapsed.TotalSeconds);
        WallDurationSeconds=$wallClock.Elapsed.TotalSeconds;ViewportPausedSeconds=$pausedMs/1000;ViewportPauseCount=$pauseCount;
        CompletedUpdatesPerWallSecond=$completed/[Math]::Max(.001,$wallClock.Elapsed.TotalSeconds);DiscardedResizeFrames=$resizeDiscarded;
        Diagnostics=[bool]$Diagnostics;SyntheticViewport=[bool]$ViewportSchedule;ViewportChanges=$viewportChanges.ToArray();
        CompletedFrames=$completed;CompletedUpdatesPerSecond=$completed/[Math]::Max(.001,$clock.Elapsed.TotalSeconds);FrameMs=(Get-SampleStats $frameTimes.ToArray());
        InterpolationMs=(Get-SampleStats $interpolationTimes.ToArray());FrameSamplesMs=$frameTimes.ToArray();FrameStats=$frameStats.ToArray();Simulation=$simulationReport;
        Requested1msTimer=$timerRequested;TerminalColumns=$terminalWidth;TerminalRows=$terminalHeight;WorkerWorkingSetBytes=$workerMemory;SimulationWorkingSetBytes=$simMemory;
        CaptureEveryTics=$CaptureEveryTics;Captures=$captures.ToArray();PowerShell=$PSVersionTable.PSVersion.ToString();
        Meaning='35 Hz simulation and 60 Hz interpolated PowerShell rendering. DurationSeconds and throughput exclude time paused for an undersized viewport; wall duration/rate and pause history are also recorded. FrameMs is overlapping render-to-write latency, not output interval. Updates are completed renders/encodes and, when visible, console writes; this report alone does not measure monitor presentation.'}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Report)))
    $data | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Report
    [pscustomobject]@{Report=$Report;Tics=$simTics;Frames=$completed;Seconds=$clock.Elapsed.TotalSeconds;Exit=$exitReason} | Format-List
}
