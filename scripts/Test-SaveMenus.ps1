#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/SessionMenu.ps1";. "$PSScriptRoot/../src/InputReplay.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Condition){$checks.Add(@{Name=$Name;Passed=$Condition});if(-not $Condition){throw $Name}}
try{
    $m=New-DoomMenuState;foreach($key in 'Escape','Down','Down','Enter'){$null=Invoke-DoomMenuKey $m $key}
    Check 'Main menu opens save slots' ($m.Screen -eq 8 -and $m.Choice -eq 0)
    $a=Invoke-DoomMenuKey $m Enter;Check 'Empty slot saves directly with no overwrite hash' ($a.Action -eq 'SaveGame' -and $a.Slot -eq 1 -and $null -eq $a.ExpectedHash -and $m.Screen -eq 13)
    Check 'Busy screen ignores navigation' ($null -eq (Invoke-DoomMenuKey $m Escape) -and $m.Screen -eq 13)
    $m=New-DoomMenuState;$m.Screen=8;$m.Slots[0]=@{Slot=1;State='Ready';Sha256=('A'*64);Episode=1;Map=2;Skill=3;Time='12:34';SourceMatches=$true}
    $a=Invoke-DoomMenuKey $m Enter;Check 'Occupied slot defaults to no replacement' ($a.Action -eq 'ShowMenu' -and $m.Screen -eq 10 -and $m.Choice -eq 0)
    $a=Invoke-DoomMenuKey $m Enter;Check 'Default no returns without a save action' ($a.Action -eq 'ShowMenu' -and $m.Screen -eq 8)
    $null=Invoke-DoomMenuKey $m Enter;$a=Invoke-DoomMenuKey $m Yes
    Check 'Replacement carries the exact selected save hash' ($a.Action -eq 'SaveGame' -and $a.ExpectedHash -eq ('A'*64))
    $m=New-DoomMenuState;$m.Screen=9;$a=Invoke-DoomMenuKey $m Enter
    Check 'Empty load slot shows a message without load action' ($a.Action -eq 'ShowMenu' -and $m.Screen -eq 12 -and $m.MessageTitle -eq 'EMPTY SLOT')
    $null=Invoke-DoomMenuKey $m Enter;Check 'Empty-slot message returns to load slots' ($m.Screen -eq 9)
    $m.Slots[0]=@{Slot=1;State='Ready';Sha256=('B'*64);Episode=4;Map=9;Skill=5;Time='23:59';SourceMatches=$false}
    $null=Invoke-DoomMenuKey $m Enter;Check 'Loading defaults to no' ($m.Screen -eq 11 -and $m.Choice -eq 0)
    $compact=Get-DoomCompactMenu $m 98 24;Check 'Compact confirmation exposes changed source version' ($compact -match 'Version changed')
    $a=Invoke-DoomMenuKey $m Yes;Check 'Confirmed changed-version load includes selected hash and acceptance' ($a.Action -eq 'LoadGame' -and $a.ExpectedHash -eq ('B'*64) -and $a.AllowSourceMismatch)
    $root=Join-Path "$PSScriptRoot/../local" ('slot-metadata-'+[guid]::NewGuid().ToString('N'));$directory=Get-DoomSaveDirectory $root ('C'*64)
    $slots=Get-DoomSlotSummaries $directory ('C'*64);Check 'Listing absent slots creates no files' ($slots.Count -eq 6 -and @($slots|Where-Object State -NE Empty).Count -eq 0 -and -not (Test-Path $directory))
    [void][IO.Directory]::CreateDirectory($directory);$path=Get-DoomSlotPath $directory 1
    $createdUtc=[DateTime]::SpecifyKind([datetime]'2026-09-11T15:19:00',[DateTimeKind]::Utc)
    [ordered]@{Format='pwshDoom.SaveState';Version=1;WadSha256=('C'*64);Episode=4;Map=9;Skill=5;EngineSourceFingerprint=(Get-DoomReplaySourceFingerprint);CreatedUtc=$createdUtc.ToString('o')}|ConvertTo-Json|Set-Content $path
    $slots=Get-DoomSlotSummaries $directory ('C'*64);Check 'Metadata preview identifies map and source' ($slots[0].State -eq 'Ready' -and $slots[0].Map -eq 9 -and $slots[0].SourceMatches -and $slots[0].Sha256 -eq (Get-FileHash $path).Hash)
    Check 'UTC metadata is displayed in the local time zone' ($slots[0].Time -eq [TimeZoneInfo]::ConvertTimeFromUtc($createdUtc,[TimeZoneInfo]::Local).ToString('HH:mm'))
    [IO.File]::WriteAllText($path,'{');$slots=Get-DoomSlotSummaries $directory ('C'*64)
    Check 'Malformed slot remains visible and preserves a hash for replacement' ($slots[0].State -eq 'Unavailable' -and $slots[0].Sha256 -eq (Get-FileHash $path).Hash)
    $rejected=$false;try{$null=Get-DoomReplaySavePath $directory '../slot-01.pds'}catch{$rejected=$true};Check 'Replay archive keys cannot name paths' $rejected
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Menu state/confirmation and bounded metadata-preview fixtures. Actual save graph validation and worker transactions have separate tests.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) save-menu checks."
