#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [Parameter(Mandatory)][string]$Output,
    [string]$Qualification="$PSScriptRoot/../results/music-loop-e1m1-hour-bound.json",
    [string]$OneShotQualification="$PSScriptRoot/../results/music-one-shot-dintro-20260926.json"
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/MusicLoopReader.ps1";. "$PSScriptRoot/../src/MusicOneShotReader.ps1";. "$PSScriptRoot/../src/MusicPlayback.ps1"
$state=$null;$checks=[Collections.Generic.List[object]]::new();$failure=$null;$loopStartFrame=$null
$report=[IO.Path]::GetFullPath($Qualification);$oneShotReport=[IO.Path]::GetFullPath($OneShotQualification)
$loopData=Get-Content $report -Raw|ConvertFrom-Json -AsHashtable
$loopTrack=[string]$loopData.Details.Track
if(-not $loopTrack){throw 'Loop qualification has no track name.'}
$oneShotData=Get-Content $oneShotReport -Raw|ConvertFrom-Json -AsHashtable
$oneShotTrack=[string]$oneShotData.Details.Track
if(-not $oneShotTrack){throw 'One-shot qualification has no track name.'}
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $Name $rejected}
try{
    $catalog=@{};$catalog[$loopTrack]=$report;$catalog[$oneShotTrack]=$oneShotReport
    $state=New-DoomMusicPlayback $catalog
    Check 'Catalog opens qualified loop and finite score without selecting either' ($null -eq $state.Selected -and $null -eq (Read-DoomMusicPlayback $state 1260) -and $state.ReaderModes[$loopTrack] -ceq 'Loop' -and $state.ReaderModes[$oneShotTrack] -ceq 'OneShot')
    [long]$loopStartFrame=[long]$loopData.Details.PeriodFrames-630
    if($loopStartFrame -lt 0 -or $loopData.Details.Periods.Count -lt 2){throw 'Loop qualification lacks two complete periods for the boundary fixture.'}
    Update-DoomMusicPlayback $state @(@{Kind='Start';Track=$loopTrack;Loop=$true;Frame=$loopStartFrame})
    $mix=Read-DoomMusicPlayback $state 1260
    $expected=[byte[]]::new(20160)
    $f=[IO.File]::OpenRead($loopData.Details.Periods[0].Path);try{$f.Position=$loopStartFrame*16;$f.ReadExactly($expected,0,10080)}finally{$f.Dispose()}
    $f=[IO.File]::OpenRead($loopData.Details.Periods[1].Path);try{$f.ReadExactly($expected,10080,10080)}finally{$f.Dispose()}
    $actual=[byte[]]::new(20160);[Buffer]::BlockCopy($mix,0,$actual,0,$actual.Length)
    Check 'Start offset crosses the qualified loop boundary with exact stored samples' ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($actual)) -ceq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expected)))
    Update-DoomMusicPlayback $state @(@{Kind='Start';Track=$loopTrack;Loop=$true},@{Kind='Gain';Value=.1})
    Check 'Explicit restart and gain applied' ($state.Readers[$loopTrack].Frame -eq 0 -and $state.Gain -eq .1)
    Reject 'Missing track packet rejected atomically' {Update-DoomMusicPlayback $state @(@{Kind='Gain';Value=.5},@{Kind='Start';Track='D_MISSING';Loop=$true})}
    Check 'Rejected packet preserves prior track and gain' ($state.Selected -ceq $loopTrack -and $state.Gain -eq .1 -and $state.Readers[$loopTrack].Frame -eq 0)
    Reject 'Loop qualification rejects one-shot command mode' {Update-DoomMusicPlayback $state @(@{Kind='Start';Track=$loopTrack;Loop=$false})}
    Reject 'One-shot qualification rejects loop command mode' {Update-DoomMusicPlayback $state @(@{Kind='Start';Track=$oneShotTrack;Loop=$true})}
    $oneShot=$oneShotData
    Reject 'One-shot offset past payload end rejected' {Update-DoomMusicPlayback $state @(@{Kind='Start';Track=$oneShotTrack;Loop=$false;Frame=[long]$oneShot.Details.Frames+1})}
    Update-DoomMusicPlayback $state @(@{Kind='Start';Track=$oneShotTrack;Loop=$false;Frame=[long]$oneShot.Details.Frames-6})
    $finiteMix=Read-DoomMusicPlayback $state 10
    $expectedBytes=[byte[]]::new(160);$file=[IO.File]::OpenRead($oneShot.Details.Payload.Path)
    try{$file.Position=([long]$oneShot.Details.Frames-6)*16;$file.ReadExactly($expectedBytes,0,96)}finally{$file.Dispose()}
    $finiteBytes=[byte[]]::new(160);[Buffer]::BlockCopy($finiteMix,0,$finiteBytes,0,$finiteBytes.Length)
    Check 'One-shot plays the final payload frames then zero pads' ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($finiteBytes)) -ceq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expectedBytes)))
    Check 'One-shot auto-stops exactly at end and next read is silent' ($state.Readers[$oneShotTrack].Frame -eq $oneShot.Details.Frames -and $state.Readers[$oneShotTrack].Finished -and $null -eq $state.Selected -and $null -eq (Read-DoomMusicPlayback $state 10))
    Reject 'Negative start frame rejected' {Update-DoomMusicPlayback $state @(@{Kind='Start';Track=$loopTrack;Loop=$true;Frame=-1})}
    Reject 'Nonfinite gain rejected' {Update-DoomMusicPlayback $state @(@{Kind='Gain';Value=[double]::NaN})}
    Reset-DoomMusicPlayback $state
    Check 'Epoch reset stops selection while retaining gain' ($null -eq $state.Selected -and $state.Gain -eq .1 -and $state.Frames -eq 1270)
    Update-DoomMusicPlayback $state @(@{Kind='Start';Track=$loopTrack;Loop=$true},@{Kind='Stop'})
    Check 'Stop leaves no music layer' ($null -eq (Read-DoomMusicPlayback $state 1260))
    Close-DoomMusicPlayback $state;Check 'Catalog closes loop and one-shot readers' ($state.Closed -and $state.Readers[$loopTrack].Closed -and $state.Readers[$oneShotTrack].Closed)
    Reject 'Closed playback rejects commands' {Update-DoomMusicPlayback $state @(@{Kind='Stop'})};$state=$null
    Reject 'Catalog rejects mismatched track label' {$s=New-DoomMusicPlayback @{'D_WRONG'=$report};Close-DoomMusicPlayback $s}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($state){Close-DoomMusicPlayback $state}
    $sourcePaths=@('src/MusicLoopReader.ps1','src/MusicOneShotReader.ps1','src/MusicPlayback.ps1','scripts/Qualify-MusicOneShot.ps1')
    @{Error=$failure;LoopTrack=$loopTrack;OneShotTrack=$oneShotTrack;LoopStartFrame=$loopStartFrame;Checks=$checks.ToArray();QualificationSha256=(Get-FileHash $report).Hash;OneShotQualificationSha256=(Get-FileHash $oneShotReport).Hash;Sources=@($sourcePaths|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Persistent catalog command/lifecycle checks using real qualified loop samples across a period boundary and the named finite score, including automatic end and zero padding. No playback device or host integration.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) music playback checks."
