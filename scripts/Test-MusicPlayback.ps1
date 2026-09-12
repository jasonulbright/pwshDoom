#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Qualification="$PSScriptRoot/../results/music-loop-e1m1-hour-bound.json")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/MusicLoopReader.ps1";. "$PSScriptRoot/../src/MusicPlayback.ps1"
$state=$null;$checks=[Collections.Generic.List[object]]::new();$failure=$null
$report=[IO.Path]::GetFullPath($Qualification)
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $Name $rejected}
try{
    $state=New-DoomMusicPlayback @{'D_E1M1'=$report}
    Check 'Catalog opens qualified track without selecting it' ($null -eq $state.Selected -and $null -eq (Read-DoomMusicPlayback $state 1260))
    Update-DoomMusicPlayback $state @(@{Kind='Start';Track='D_E1M1';Loop=$true;Frame=4232970})
    $mix=Read-DoomMusicPlayback $state 1260
    $r=Get-Content $report -Raw|ConvertFrom-Json;$expected=[byte[]]::new(20160)
    $f=[IO.File]::OpenRead($r.Details.Periods[0].Path);try{$f.Position=4232970L*16;$f.ReadExactly($expected,0,10080)}finally{$f.Dispose()}
    $f=[IO.File]::OpenRead($r.Details.Periods[1].Path);try{$f.ReadExactly($expected,10080,10080)}finally{$f.Dispose()}
    $actual=[byte[]]::new(20160);[Buffer]::BlockCopy($mix,0,$actual,0,$actual.Length)
    Check 'Start offset crosses intro boundary with exact stored samples' ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($actual)) -ceq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($expected)))
    Update-DoomMusicPlayback $state @(@{Kind='Start';Track='D_E1M1';Loop=$true},@{Kind='Gain';Value=.1})
    Check 'Explicit restart and gain applied' ($state.Readers.D_E1M1.Frame -eq 0 -and $state.Gain -eq .1)
    Reject 'Missing track packet rejected atomically' {Update-DoomMusicPlayback $state @(@{Kind='Gain';Value=.5},@{Kind='Start';Track='D_MISSING';Loop=$true})}
    Check 'Rejected packet preserves prior track and gain' ($state.Selected -ceq 'D_E1M1' -and $state.Gain -eq .1 -and $state.Readers.D_E1M1.Frame -eq 0)
    Reject 'Unqualified one-shot command rejected' {Update-DoomMusicPlayback $state @(@{Kind='Start';Track='D_E1M1';Loop=$false})}
    Reject 'Negative start frame rejected' {Update-DoomMusicPlayback $state @(@{Kind='Start';Track='D_E1M1';Loop=$true;Frame=-1})}
    Reject 'Nonfinite gain rejected' {Update-DoomMusicPlayback $state @(@{Kind='Gain';Value=[double]::NaN})}
    Reset-DoomMusicPlayback $state
    Check 'Epoch reset stops selection while retaining gain' ($null -eq $state.Selected -and $state.Gain -eq .1 -and $state.Frames -eq 1260)
    Update-DoomMusicPlayback $state @(@{Kind='Start';Track='D_E1M1';Loop=$true},@{Kind='Stop'})
    Check 'Stop leaves no music layer' ($null -eq (Read-DoomMusicPlayback $state 1260))
    Close-DoomMusicPlayback $state;Check 'Catalog closes all qualified readers' ($state.Closed -and $state.Readers.D_E1M1.Closed)
    Reject 'Closed playback rejects commands' {Update-DoomMusicPlayback $state @(@{Kind='Stop'})};$state=$null
    Reject 'Catalog rejects mismatched track label' {$s=New-DoomMusicPlayback @{'D_WRONG'=$report};Close-DoomMusicPlayback $s}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($state){Close-DoomMusicPlayback $state}
    @{Error=$failure;Checks=$checks.ToArray();QualificationSha256=(Get-FileHash $report).Hash;Sources=@('MusicLoopReader','MusicPlayback'|ForEach-Object {@{Path="src/$_.ps1";Sha256=(Get-FileHash "$PSScriptRoot/../src/$_.ps1").Hash}});ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Persistent catalog command/lifecycle checks using real qualified E1M1 samples and independent file slices at the intro seam. No playback device or host integration.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) music playback checks."
