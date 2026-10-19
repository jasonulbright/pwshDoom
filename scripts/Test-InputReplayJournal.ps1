#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/../src/InputReplayJournal.ps1"

$root=Split-Path $PSScriptRoot;$temp=Join-Path $root ('local/input-replay-journal-'+[guid]::NewGuid().ToString('N'))
$journal=Join-Path $temp 'session.jsonl';$recovered=Join-Path $temp 'recovered.json'
$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Condition){$checks.Add(@{Name=$Name;Passed=$Condition});if(-not $Condition){throw "FAIL: $Name"}}
function New-TestCommands([int]$Count,[int]$Seed){
    $items=[object[]]::new($Count)
    for($i=0;$i -lt $Count;$i++){$firstMove=([long]$Seed)+([long]$i);$items[$i]=[long[]]@($firstMove,[long]0,[long]0,[long]0)}
    return ,$items
}
function New-TestCheckpoint([long]$Tic,[string]$Hash){return [ordered]@{Tic=$Tic;Sha256=$Hash}}
function New-TestTransition([long]$Tic,[int]$Map){return [ordered]@{Tic=$Tic;State='Level';Episode=1;Map=$Map;Generation=$Map;Health=100}}

try{
    [void][IO.Directory]::CreateDirectory($temp)
    $wadHash='A'*64;$sourceHash='B'*64
    Initialize-DoomInputReplayJournal $journal $wadHash $sourceHash 3 1 1
    Check 'Journal header is durably created without a game or IWAD' (Test-Path -LiteralPath $journal)
    $first=[ordered]@{Kind='Batch';Sequence=1;StartTic=0;EndTic=3;InputCommands=(New-TestCommands 3 0);
        AutomapCommands=@([ordered]@{Tic=[long]1;Mask=[long]3});
        ControlEvents=@([ordered]@{Tic=[long]0;Action='NewGame';Skill=[long]3;Episode=[long]1;Map=[long]1});
        Checkpoints=@((New-TestCheckpoint 0 ('C'*64)),(New-TestCheckpoint 3 ('D'*64)));
        Transitions=@((New-TestTransition 0 1),(New-TestTransition 3 2));Final=$false}
    Add-DoomInputReplayJournalBatch $journal $first
    Check 'First append-only command batch is accepted' ((Read-DoomInputReplayJournal $journal).Tics -eq 3)
    $second=[ordered]@{Kind='Batch';Sequence=2;StartTic=3;EndTic=5;InputCommands=(New-TestCommands 2 10);
        AutomapCommands=@([ordered]@{Tic=[long]3;Mask=[long]8});
        ControlEvents=@([ordered]@{Tic=[long]4;Action='LoadGame';SaveHash=('E'*64)});
        Checkpoints=@((New-TestCheckpoint 3 ('F'*64)),(New-TestCheckpoint 5 ('1'*64)));
        Transitions=@((New-TestTransition 4 1));Final=$false}
    Add-DoomInputReplayJournalBatch $journal $second
    [IO.File]::AppendAllText($journal,'{"Payload":"torn-final-record"',[Text.UTF8Encoding]::new($false))
    $readJournal=Read-DoomInputReplayJournal $journal
    Check 'Torn final line is discarded while complete batches survive' ($readJournal.TornTailDiscarded -and $readJournal.Tics -eq 5)
    Check 'Recovery preserves every consumed command in order' (($readJournal.InputCommands.Count -eq 5) -and $readJournal.InputCommands[4][0] -eq 11)
    Check 'Recovery preserves sparse automap input and ordered menu controls' (($readJournal.AutomapCommands.Count -eq 2) -and ($readJournal.ControlEvents.Count -eq 2) -and $readJournal.ControlEvents[1].Action -eq 'LoadGame')
    Check 'Checkpoint replacement at the same tic keeps the newest state' (($readJournal.Checkpoints.Count -eq 3) -and $readJournal.Checkpoints[1].Sha256 -eq ('F'*64))
    $data=ConvertFrom-DoomInputReplayJournal $journal
    $recoveryScript=Join-Path $PSScriptRoot 'Recover-DoomInputReplayJournal.ps1'
    $recoveryReceipt=(& $recoveryScript -Journal $journal -Output $recovered | ConvertFrom-Json)
    $replay=Read-DoomInputReplay $recovered $wadHash
    Check 'Recovered output validates as the existing version-4 replay format' ($replay.Format -eq 'pwshDoom.InputReplay' -and $replay.Version -eq 4 -and $replay.InputCommands.Count -eq 5)
    Check 'Recovered replay retains controls, checkpoints and campaign continuation' (($replay.ControlEvents.Count -eq 2) -and ($replay.Checkpoints.Count -eq 3) -and $replay.ContinueCampaign)
    Check 'Recovery marks the artifact as a partial journal prefix' ($replay.RecoveredFromJournal -and $replay.ExitReason -eq 'RecoveredInterrupted' -and $replay.TornJournalTailDiscarded)
    Check 'Recovery CLI emits journal and replay hashes with the recovered tic count' ($recoveryReceipt.RecoveredTics -eq 5 -and $recoveryReceipt.ReplaySha256 -eq (Get-FileHash -LiteralPath $recovered).Hash)
    foreach($case in @(@('ControlEvents',2),@('Checkpoints',2),@('Transitions',2),@('Transitions',6))){
        $invalidPath=Join-Path $temp ($case[0]+'-'+$case[1]+'.jsonl')
        Initialize-DoomInputReplayJournal $invalidPath $wadHash $sourceHash 3 1 1
        Add-DoomInputReplayJournalBatch $invalidPath $first
        $badSecond=ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $second -Depth 10 -Compress) -AsHashtable -Depth 10
        $badSecond[$case[0]][0].Tic=[long]$case[1]
        Add-DoomInputReplayJournalBatch $invalidPath $badSecond
        $boundaryRejected=$false
        try{$null=Read-DoomInputReplayJournal $invalidPath}catch{$boundaryRejected=$_.Exception.Message -match 'boundary in replay journal'}
        Check "Recovery rejects out-of-batch $($case[0]) tic $($case[1])" $boundaryRejected
    }
    $before=(Get-FileHash -LiteralPath $recovered).Hash;$overwriteRejected=$false
    try{$null=Write-DoomInputReplay $recovered $data}catch{$overwriteRejected=$_.Exception.Message -match 'never replace|new filename'}
    Check 'Recovery never overwrites an existing replay' ($overwriteRejected -and (Get-FileHash -LiteralPath $recovered).Hash -eq $before)
    $lines=[IO.File]::ReadAllLines($journal)
    $envelope=ConvertFrom-Json -InputObject $lines[1] -AsHashtable
    $envelope.Payload=$envelope.Payload.Replace('StartTic', 'StartTicX')
    $lines[1]=ConvertTo-Json -InputObject $envelope -Compress -Depth 3
    $tampered=Join-Path $temp 'tampered.jsonl';[IO.File]::WriteAllLines($tampered,$lines,[Text.UTF8Encoding]::new($false))
    $tamperRejected=$false;try{$null=Read-DoomInputReplayJournal $tampered}catch{$tamperRejected=$_.Exception.Message -match 'checksum mismatch'}
    Check 'Complete journal record tampering is rejected by its checksum' $tamperRejected
    $workerPath=Join-Path $root 'scripts/Invoke-SimulationWorker.ps1';$workerText=Get-Content -LiteralPath $workerPath -Raw
    $hostPath=Join-Path $root 'scripts/Invoke-Doom.ps1';$hostText=Get-Content -LiteralPath $hostPath -Raw
    Check 'Worker accepts the journal path and source identity' ($workerText.Contains('$ReplayJournalPath') -and $workerText.Contains('$ReplaySourceFingerprint'))
    Check 'Worker writes the initial state before accepting commands' ($workerText -match '(?s)Initialize-DoomInputReplayJournal.*?Record-SimulationTransition\s+Record-ReplayCheckpoint\s+Flush-DoomInputReplayJournal')
    Check 'Worker flushes periodic and transition checkpoints' ($workerText.Contains('if($tick%350 -eq 0 -or $game.State -ne $priorState -or $extraCheckpoints.ContainsKey($tick)){Flush-DoomInputReplayJournal}') -and $workerText -match '(?s)Record-SimulationTransition;Record-ReplayCheckpoint -Replace\s+Flush-DoomInputReplayJournal')
    Check 'Worker flushes remaining commands during shutdown' ($workerText -match '(?s)finally \{.*?Flush-DoomInputReplayJournal -Final:')
    Check 'Host passes a fresh companion journal path to the worker' ($hostText.Contains("`$recordJournalPath=`$RecordInput+'.journal'") -and $hostText.Contains('-ReplayJournalPath $recordJournalPath'))
    Check 'Host removes the journal only after a replay is written' ($hostText -match '(?s)Write-DoomInputReplay \$RecordInput.*?if\(Test-Path -LiteralPath \$recordJournalPath\)')
    $out=[IO.Path]::GetFullPath($Output);[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($out))
    [ordered]@{CreatedUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks.ToArray();Passed=$checks.Count;Failed=0;
        JournalSha256=(Get-FileHash -LiteralPath $journal).Hash;HelperSha256=(Get-FileHash -LiteralPath "$root/src/InputReplayJournal.ps1").Hash;
        HarnessSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;WorkerSha256=(Get-FileHash -LiteralPath $workerPath).Hash;
        HostSha256=(Get-FileHash -LiteralPath $hostPath).Hash;ProcessSha256=(Get-FileHash -LiteralPath (Join-Path $root 'src/SimulationProcess.ps1')).Hash;
        RecoverySha256=(Get-FileHash -LiteralPath $recoveryScript).Hash;
        Meaning='Offline contract and static wiring checks for append-only input-replay journaling and recovery. Uses synthetic command data and temporary files only; launches no game, user process, display, or audio device.'} |
        ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $out
    Write-Output "PASS: $($checks.Count) input replay journal checks."
}finally{
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
}
