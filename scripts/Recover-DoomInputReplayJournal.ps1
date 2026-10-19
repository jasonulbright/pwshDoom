#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Journal,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/../src/InputReplayJournal.ps1"

$journalPath=[IO.Path]::GetFullPath($Journal);$outputPath=[IO.Path]::GetFullPath($Output)
if($journalPath -eq $outputPath){throw 'Recovered replay must use a new path; the journal is retained.'}
$data=ConvertFrom-DoomInputReplayJournal $journalPath
$written=Write-DoomInputReplay $outputPath $data
$receipt=[ordered]@{RecoveredUtc=[DateTime]::UtcNow.ToString('o');Journal=$journalPath;
    JournalSha256=(Get-FileHash -LiteralPath $journalPath).Hash;Replay=$written;
    ReplaySha256=(Get-FileHash -LiteralPath $written).Hash;RecoveredTics=$data.RecoveredTics;
    TornJournalTailDiscarded=$data.TornJournalTailDiscarded;ExitReason=$data.ExitReason;
    Meaning='Recovered a validated, hash-checked prefix of consumed gameplay input. This receipt does not establish map completion.'}
[pscustomobject]$receipt|ConvertTo-Json -Depth 5|Write-Output
