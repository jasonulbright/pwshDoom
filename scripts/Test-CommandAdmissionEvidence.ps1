#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Report,[Parameter(Mandatory)][string]$Replay,
    [Parameter(Mandatory)][string]$Recording,[Parameter(Mandatory)][string]$Output,[switch]$ExpectSourceChange)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh admission audit.'}
. "$PSScriptRoot/../src/InputReplay.ps1"
$failure=$null;$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $reportData=Get-Content -LiteralPath $Report -Raw|ConvertFrom-Json
    $expected=Read-DoomInputReplay $Replay '';$actual=Read-DoomInputReplay $Recording $expected.WadSha256
    $count=$expected.InputCommands.Count
    Check 'Host and simulation finish the complete supplied replay' ($null -eq $reportData.Error -and $null -eq $reportData.Simulation.Error -and $reportData.ExitReason -eq 'ReplayEnd' -and $reportData.IssuedCommands -eq $count -and $reportData.SimulationTics -eq $count)
    Check 'Recorded input is complete and successful' ($null -eq $actual.Error -and $actual.ExitReason -eq 'ReplayEnd' -and $actual.InputCommands.Count -eq $count)
    foreach($field in 'Skill','Episode','Map','ContinueCampaign'){Check "Recorded $field matches input" ($expected.$field -eq $actual.$field)}
    if($ExpectSourceChange){Check 'Declared source change is explicitly reported' ($expected.SourceFingerprint -ne $actual.SourceFingerprint -and -not $reportData.ReplaySourceMatches)}
    else{Check 'Recorded source fingerprint matches input' ($expected.SourceFingerprint -eq $actual.SourceFingerprint -and $reportData.ReplaySourceMatches)}
    for($i=0;$i -lt $count;$i++){for($field=0;$field -lt 4;$field++){if($expected.InputCommands[$i][$field] -ne $actual.InputCommands[$i][$field]){throw "Command $i field $field differs."}}}
    Check 'Every command and field survives in order' $true
    $verification=Compare-DoomReplayCheckpoints $expected.Checkpoints $actual.Checkpoints $count
    Check 'Every supplied checkpoint matches the independently recorded replay' ($verification.Matched -and $verification.Checked -eq $expected.Checkpoints.Count)
    Check 'Host independently reports all checkpoints matching' ($reportData.ReplayVerification.Matched -and $reportData.ReplayVerification.Checked -eq $expected.Checkpoints.Count)
    Check 'Two-command admission pressure occurs and finishes' ($reportData.MaximumPendingCommands -eq 2 -and $reportData.CommandBackpressure.Count -gt 0 -and $reportData.IncompleteCommandBackpressureStartQpc -eq 0)
    $previousEnd=0L
    foreach($interval in $reportData.CommandBackpressure){if($interval.StartQpc -lt $previousEnd -or $interval.EndQpc -lt $interval.StartQpc -or $interval.Milliseconds -lt 0 -or $interval.BeforeCommand -gt $count){throw 'Malformed admission interval.'};$previousEnd=$interval.EndQpc}
    Check 'Pressure intervals are ordered and bounded' $true
    $audio=$reportData.Simulation.Audio
    Check 'All replay audio packets and frames return without cancellation' ($null -eq $audio.Error -and $audio.Packets -eq $count -and $audio.SubmittedFrames -eq $count*1260 -and $audio.ReturnedCompletedFrames -eq $count*1260 -and $audio.CancelledQueuedFramesUpperBound -eq 0 -and $audio.UnconsumedPackets -eq 0)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    @{Error=$failure;Checks=$checks.ToArray();ReportSha256=(Get-FileHash $Report).Hash;ReplaySha256=(Get-FileHash $Replay).Hash;RecordingSha256=(Get-FileHash $Recording).Hash;
        ExpectSourceChange=[bool]$ExpectSourceChange;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;FinishedUtc=[DateTime]::UtcNow.ToString('o');
        Meaning='Audit of completed real-host evidence and every recorded command, supplied checkpoint, pressure interval and digital audio frame accounting. Two is the configured admission limit, not a separately sampled maximum. No acoustic or displayed-rate claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $($checks.Count) admission evidence checks."
