#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# Finite owned capture target; no Doom assets or game algorithms.
param([Parameter(Mandatory)][string]$Prefix,[Parameter(Mandatory)][string]$Title)
$ErrorActionPreference='Stop'
[Console]::Title=$Title
@{Pid=$PID;StartedUtc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content ($Prefix+'-ready.json')
$watch=[Diagnostics.Stopwatch]::StartNew();$frame=0
try{
    [Console]::Write("`e[2J`e[?25l")
    while($watch.Elapsed.TotalSeconds -lt 40 -and -not (Test-Path ($Prefix+'-stop'))){
        $color=32+($frame%192)
        [Console]::Write("`e[H`e[38;2;${color};220;120mOwned recorder lifecycle test`nFrame $frame`n$Title`e[0m")
        $frame++;Start-Sleep -Milliseconds 16
    }
}finally{[Console]::Write("`e[0m`e[?25h");@{Frames=$frame;Seconds=$watch.Elapsed.TotalSeconds}|ConvertTo-Json|Set-Content ($Prefix+'-target.json')}
