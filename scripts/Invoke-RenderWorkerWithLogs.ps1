#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# PowerShell stream redirection avoids dedicating host thread-pool threads to
# synchronous anonymous-pipe readers that normally produce no renderer output.
param([string]$Assets,[string]$Channel,[int]$FirstColumn,[int]$EndColumn,[int]$OwnerPid,
    [ValidateRange(0,31)][int]$WorkerIndex=0,
    [ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic',
    [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Ascii',
    [ValidateSet('Pairs','ColorState','Ansi256')][string]$AnsiEncoding='Pairs',
    [Parameter(Mandatory)][string]$LogPrefix)
$ErrorActionPreference='Stop'
$arguments=@{};foreach($key in $PSBoundParameters.Keys){if($key -ne 'LogPrefix'){$arguments[$key]=$PSBoundParameters[$key]}}
$stdout=$LogPrefix+'-stdout.txt';$stderr=$LogPrefix+'-stderr.txt'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($LogPrefix)))
try{
    & "$PSScriptRoot/Invoke-GameRenderWorker.ps1" @arguments 1> $stdout 2> $stderr 3>&1 4>&1 5>&1 6>&1
}catch{
    [IO.File]::AppendAllText($stderr,$_.ToString()+"`n"+$_.ScriptStackTrace+"`n")
    exit 1
}
