#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Wad,[ValidateRange(1,32)][int]$Workers=16,
    [ValidateRange(0,3600)][int]$Seconds=0,[switch]$Headless,[switch]$Scripted,[string]$Replay,
    [ValidateRange(0,10000)][int]$CaptureEveryTics=0,
    [ValidateRange(1,5)][int]$Skill=3,[ValidateRange(1,4)][int]$Episode=1,[ValidateRange(1,32)][int]$Map=1,
    [string]$Report="$PSScriptRoot/../local/game-session.json")
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"
. "$PSScriptRoot/../src/GameProcesses.ps1"
. "$PSScriptRoot/../src/ConsoleInput.ps1"
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
$content=$null;$pool=$null;$consoleState=$null;$terminalActive=$false
$oldEncoding=[Console]::OutputEncoding;$esc=[char]27
$tickTimes=[Collections.Generic.List[double]]::new();$frameTimes=[Collections.Generic.List[double]]::new()
$snapshotTimes=[Collections.Generic.List[double]]::new();$tickLateness=[Collections.Generic.List[double]]::new()
$inputLog=[Collections.Generic.List[object]]::new();$frameStats=[Collections.Generic.List[object]]::new()
$clock=[Diagnostics.Stopwatch]::new();$completed=0;$tics=0;$exitReason='Error';$failure=$null;$game=$null
$terminalWidth=0;$terminalHeight=0;$workerMemory=0;$warmupTics=140
$timerRequested=$false;$replayData=$null;$nextCapture=$CaptureEveryTics;$captures=[Collections.Generic.List[string]]::new()
try {
    if($Replay) {
        $replayData=Get-Content -LiteralPath $Replay -Raw | ConvertFrom-Json
        if($replayData.WadSha256 -ne (Get-FileHash -LiteralPath $Wad).Hash){throw 'Replay IWAD hash does not match the supplied IWAD.'}
        foreach($inputCommand in $replayData.InputCommands) {
            if($inputCommand.Count -ne 4 -or [Math]::Abs($inputCommand[0]) -gt 50 -or [Math]::Abs($inputCommand[1]) -gt 50 -or $inputCommand[2] -lt -32768 -or $inputCommand[2] -gt 32767 -or $inputCommand[3] -lt 0 -or $inputCommand[3] -gt 255){throw 'Invalid replay command.'}
        }
    }
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',[IO.Path]::GetFullPath($Wad)))
    $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]($Skill-1),$Episode,$Map);$null=$game.Update($commands)
    # Warm common simulation paths in a disposable level, then start a fresh game.
    # The reset restores position, inventory, counters and the deterministic RNG.
    for($i=0;$i -lt $warmupTics;$i++) {
        $commands[0].ForwardMove=25;$commands[0].Buttons=1
        if($i -gt 70){$commands[0].AngleTurn=640}
        $null=$game.Update($commands)
    }
    foreach($cmd in $commands){$cmd.Clear()}
    $game.DeferedInitNew([GameSkill]($Skill-1),$Episode,$Map);$null=$game.Update($commands)
    $context=New-FastRenderContext $content $game.World
    $palette=[int[][]]::new(256)
    for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $codec=New-CodecContext $palette
    $pool=New-GameRenderPool $context $codec $Workers
    $snapshot=New-GameRenderSnapshot $game
    for($i=0;$i -lt 4;$i++){Submit-GameRender $pool $snapshot;Wait-GameRender $pool}
    if(-not $Headless) {
        $terminalWidth=[Console]::WindowWidth;$terminalHeight=[Console]::WindowHeight
        if([Console]::WindowWidth -lt 320 -or [Console]::WindowHeight -lt 102){throw 'The terminal needs at least 320 columns and 102 rows. Use Start-Doom.ps1 to open the small-font profile.'}
        [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
        if(-not $Scripted -and -not $Replay){$consoleState=Open-DoomConsoleInput}
        [Console]::Write("$esc[?1049h$esc[?25l$esc[2J");$terminalActive=$true
    }
    $stdout=[Console]::OpenStandardOutput();$frameStart=[Text.Encoding]::UTF8.GetBytes("$esc[?2026h")
    $frameEnd=[Text.Encoding]::UTF8.GetBytes("$esc[0m$esc[?2026l")
    $inFlight=$false;$frameWatch=[Diagnostics.Stopwatch]::new();$lastFrameTic=-1;$nextFrame=0.0
    Initialize-DoomConsoleApi;$timerRequested=[PwshDoomPlatform.ConsoleApi]::timeBeginPeriod(1) -eq 0
    $clock.Start();$exitReason='Quit'
    while($true) {
        $now=$clock.Elapsed.TotalMilliseconds
        if($Seconds -gt 0 -and $now -ge $Seconds*1000){$exitReason='Duration';break}
        if($null -ne $consoleState){Read-DoomConsoleInput $consoleState;if($consoleState.Keys[27] -or $consoleState.Pressed[27]){break}}
        # Never discard simulation tics. At most one is processed per host iteration,
        # allowing completed frames and fresh input to be handled during catch-up.
        if($now -ge ($tics+1)*1000.0/35) {
            $tickLateness.Add($now-($tics+1)*1000.0/35)
            $cmd=$commands[0];$cmd.Clear()
            if($null -ne $replayData) {
                if($tics -ge $replayData.InputCommands.Count){$exitReason='ReplayEnd';break}
                $record=$replayData.InputCommands[$tics];$cmd.ForwardMove=$record[0];$cmd.SideMove=$record[1];$cmd.AngleTurn=$record[2];$cmd.Buttons=$record[3]
            }
            elseif($null -ne $consoleState){Set-DoomInputCommand $consoleState $cmd}
            elseif($Scripted) {
                $phase=$tics%700
                if($phase -lt 120){$cmd.ForwardMove=25}
                elseif($phase -lt 260){$cmd.AngleTurn=640}
                elseif($phase -lt 430){$cmd.ForwardMove=25}
                if(($tics%14) -lt 7){$cmd.Buttons=1}
                if(($tics%70) -eq 69){$cmd.Buttons=$cmd.Buttons -bor 2}
            }
            $inputLog.Add(@($cmd.ForwardMove,$cmd.SideMove,$cmd.AngleTurn,$cmd.Buttons))
            $watch=[Diagnostics.Stopwatch]::StartNew();$null=$game.Update($commands);$tickTimes.Add($watch.Elapsed.TotalMilliseconds);$tics++
            if($game.State -ne [GameState]::Level){$exitReason='LevelComplete';break}
            if(-not [object]::ReferenceEquals($context.World,$game.World)) {
                # Death/rebirth can replace the world. Rebuild assets after all old readers stop.
                if($inFlight){Wait-GameRender $pool;$inFlight=$false}
                Close-GameRenderPool $pool;$pool=$null
                $context=New-FastRenderContext $content $game.World;$pool=New-GameRenderPool $context $codec $Workers
            }
        }
        if($inFlight -and (Test-GameRenderCompleted $pool)) {
            $harvestWatch=[Diagnostics.Stopwatch]::StartNew();Wait-GameRender $pool 0;$harvestMs=$harvestWatch.Elapsed.TotalMilliseconds
            if($CaptureEveryTics -gt 0 -and $lastFrameTic -ge $nextCapture) {
                $capture=[byte[]]::new(64000)
                for($i=0;$i -lt $pool.Count;$i++) {
                    $worker=$pool.Workers[$i]
                    for($y=0;$y -lt 200;$y++){[Array]::Copy($pool.Results[$i].Pixels,$y*320+$worker.First,$capture,$y*320+$worker.First,$worker.End-$worker.First)}
                }
                $capturePath="$PSScriptRoot/../local/capture-$lastFrameTic.bin";[IO.File]::WriteAllBytes($capturePath,$capture);$captures.Add([IO.Path]::GetFullPath($capturePath));$nextCapture+=$CaptureEveryTics
            }
            if(-not $Headless) {
                $stdout.Write($frameStart)
                foreach($result in $pool.Results){$stdout.Write($result.Bytes)}
                $status="$esc[H$esc[0mpwshDoom | WASD move | arrows turn | Ctrl fire | E/Space use | Shift run | 1-7 weapons | Esc quit$esc[K`r`n"
                $status+="tic $tics | $([Math]::Round($completed/[Math]::Max(0.01,$clock.Elapsed.TotalSeconds),1)) completed updates/s | $($game.World.Map.Title)$esc[K"
                $stdout.Write([Text.Encoding]::UTF8.GetBytes($status));$stdout.Write($frameEnd);$stdout.Flush()
            }
            $frameTimes.Add($frameWatch.Elapsed.TotalMilliseconds);$completed++
            $frameStats.Add(@{SubmitMs=$submitMs;HarvestMs=$harvestMs;StartQpc=$frameQpc;EndQpc=[Diagnostics.Stopwatch]::GetTimestamp();Tic=$lastFrameTic;ElapsedMs=$clock.Elapsed.TotalMilliseconds;Workers=@($pool.Results | ForEach-Object {,@($_.RenderMs,$_.EncodeMs,$_.DecodeMs,$_.StartedQpc,$_.DoneQpc)})})
            $inFlight=$false
        }
        if(-not $inFlight -and $clock.Elapsed.TotalMilliseconds -ge $nextFrame) {
            $watch=[Diagnostics.Stopwatch]::StartNew();$snapshot=New-GameRenderSnapshot $game ([Math]::Clamp($clock.Elapsed.TotalMilliseconds*35/1000-$tics,[double]0,[double]1));$snapshotTimes.Add($watch.Elapsed.TotalMilliseconds)
            $lastFrameTic=$tics;$frameWatch.Restart();$frameQpc=[Diagnostics.Stopwatch]::GetTimestamp();$submitWatch=[Diagnostics.Stopwatch]::StartNew();Submit-GameRender $pool $snapshot;$submitMs=$submitWatch.Elapsed.TotalMilliseconds;$inFlight=$true
            $nextFrame+=1000.0/60
        }
        if($inFlight -and $frameWatch.Elapsed.TotalSeconds -gt 30){throw 'Render timed out.'}
        [Threading.Thread]::Sleep(1)
    }
} catch {$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;$exitReason='Error';[Console]::Error.WriteLine($_.ScriptStackTrace);throw}
finally {
    $clock.Stop()
    if($timerRequested){$null=[PwshDoomPlatform.ConsoleApi]::timeEndPeriod(1)}
    if($null -ne $pool) {
        foreach($worker in $pool.Workers){if(-not $worker.Process.HasExited){$worker.Process.Refresh();$workerMemory+=$worker.Process.WorkingSet64}}
        try {Wait-GameRender $pool 30000} catch {}
        # Retain only a user-local diagnostic frame assembled from completed disjoint strips.
        $image=[byte[]]::new(64000)
        for($i=0;$i -lt $pool.Count;$i++) {
            $result=$pool.Results[$i];if($null -eq $result){continue}
            $worker=$pool.Workers[$i]
            for($y=0;$y -lt 200;$y++){[Array]::Copy($result.Pixels,$y*320+$worker.First,$image,$y*320+$worker.First,$worker.End-$worker.First)}
        }
        [IO.File]::WriteAllBytes("$PSScriptRoot/../local/game-frame.bin",$image)
        Close-GameRenderPool $pool
    }
    if($terminalActive){[Console]::Write("$esc[?2026l$esc[0m$esc[?25h$esc[?1049l")}
    if($null -ne $consoleState){Close-DoomConsoleInput $consoleState}
    [Console]::OutputEncoding=$oldEncoding
    if($null -ne $content){[IO.File]::WriteAllBytes("$PSScriptRoot/../local/palette.bin",$content.Palette.Data);$content.Dispose()}
    if($true) {
        $reportData=@{FinishedUtc=[DateTime]::UtcNow.ToString('o');WadSha256=(Get-FileHash $Wad).Hash;Workers=$Workers;Skill=$Skill;Episode=$Episode;Map=$Map;
            PowerShell=$PSVersionTable.PSVersion.ToString();Headless=[bool]$Headless;Scripted=[bool]$Scripted;ExitReason=$exitReason;Error=$failure;
            WarmupSimulationTics=$warmupTics;WarmupFrames=4;TerminalColumns=$terminalWidth;TerminalRows=$terminalHeight;WorkerWorkingSetBytes=$workerMemory;
            Transport='NumericV1';Requested1msTimer=$timerRequested;Replay=$Replay;CaptureEveryTics=$CaptureEveryTics;Captures=$captures.ToArray();
            Health=if($null -ne $game){$game.World.ConsolePlayer.Health}else{$null};Kills=if($null -ne $game){$game.World.ConsolePlayer.KillCount}else{$null};
            DurationSeconds=$clock.Elapsed.TotalSeconds;SimulationTics=$tics;TicsPerSecond=$tics/[Math]::Max(.001,$clock.Elapsed.TotalSeconds);
            CompletedFrames=$completed;CompletedUpdatesPerSecond=$completed/[Math]::Max(.001,$clock.Elapsed.TotalSeconds);
            SimulationMs=(Get-SampleStats $tickTimes.ToArray());SnapshotMs=(Get-SampleStats $snapshotTimes.ToArray());
            FrameMs=(Get-SampleStats $frameTimes.ToArray());TickLatenessMs=(Get-SampleStats $tickLateness.ToArray());
            SimulationSamplesMs=$tickTimes.ToArray();FrameSamplesMs=$frameTimes.ToArray();SnapshotSamplesMs=$snapshotTimes.ToArray();
            InputCommands=$inputLog.ToArray();FrameStats=$frameStats.ToArray();Meaning='35 Hz target simulation with independent snapshot rendering. Updates are completed renders/encodes (and console writes when not headless), not measured monitor presentations. Camera, actor positions and moving sectors use interpolation between simulation states.'}
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Report)))
        $reportData | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Report
        [pscustomobject]@{Report=$Report;Tics=$tics;Frames=$completed;Seconds=$clock.Elapsed.TotalSeconds;Exit=$exitReason} | Format-List
    }
}
