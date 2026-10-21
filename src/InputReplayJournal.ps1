# SPDX-License-Identifier: GPL-2.0-or-later
# Append-only recovery journal for long, opt-in human input recordings.
function ConvertTo-DoomPowerShellArgument {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Get-DoomInputReplayJournalRecoveryAdvice {
    param([Parameter(Mandatory)][string]$RecordPath,[Parameter(Mandatory)][string]$RecoveryScriptPath)
    $record=[IO.Path]::GetFullPath($RecordPath)
    if(Test-Path -LiteralPath $record){throw 'Input recording destination already exists; choose a new filename.'}
    $journal=$record+'.journal'
    if(-not (Test-Path -LiteralPath $journal)){return $null}
    if(-not (Test-Path -LiteralPath $journal -PathType Leaf)){throw "An unfinished input journal path is not a file: $journal"}

    $output=$record+'.recovered.json';$suffix=1
    while(Test-Path -LiteralPath $output){$output=$record+".recovered-$suffix.json";$suffix++}
    $script=[IO.Path]::GetFullPath($RecoveryScriptPath)
    $command='pwsh -NoProfile -File {0} -Journal {1} -Output {2}' -f `
        (ConvertTo-DoomPowerShellArgument $script),
        (ConvertTo-DoomPowerShellArgument $journal),
        (ConvertTo-DoomPowerShellArgument $output)
    $message=@"
An unfinished input recording journal was found and is still available at:
$journal

Recover its complete prefix to a new file with:
$command

Recovery preserves the journal and does not overwrite an existing replay.
After recovery, start a new recording with a fresh -RecordInput path.
"@
    return $message.Trim()
}

function ConvertTo-DoomReplayJournalLine {
    param([Parameter(Mandatory)]$Payload)
    $payloadJson=ConvertTo-Json -InputObject $Payload -Depth 10 -Compress
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($payloadJson)))
    return (ConvertTo-Json -InputObject ([ordered]@{Payload=$payloadJson;Sha256=$hash}) -Compress -Depth 3)
}

function Write-DoomReplayJournalLine {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Payload,[switch]$Create)
    $full=[IO.Path]::GetFullPath($Path)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))
    $line=ConvertTo-DoomReplayJournalLine $Payload
    [byte[]]$bytes=[Text.Encoding]::UTF8.GetBytes($line+"`n")
    $mode=if($Create){[IO.FileMode]::CreateNew}else{[IO.FileMode]::Append}
    $stream=[IO.FileStream]::new($full,$mode,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
}

function Initialize-DoomInputReplayJournal {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$WadSha256,
        [Parameter(Mandatory)][string]$SourceFingerprint,[Parameter(Mandatory)][int]$Skill,
        [Parameter(Mandatory)][int]$Episode,[Parameter(Mandatory)][int]$Map)
    if($WadSha256 -notmatch '^[a-fA-F0-9]{64}$' -or $SourceFingerprint -notmatch '^[a-fA-F0-9]{64}$'){
        throw 'Replay journal requires valid IWAD and source hashes.'
    }
    if($Skill -lt 1 -or $Skill -gt 5 -or $Episode -lt 1 -or $Episode -gt 4 -or $Map -lt 1 -or $Map -gt 32){
        throw 'Replay journal start settings are out of range.'
    }
    Write-DoomReplayJournalLine $Path ([ordered]@{Format='pwshDoom.InputReplayJournal';Version=1;
        CreatedUtc=[DateTime]::UtcNow.ToString('o');WadSha256=$WadSha256.ToUpperInvariant();
        SourceFingerprint=$SourceFingerprint.ToUpperInvariant();Skill=$Skill;Episode=$Episode;Map=$Map;
        PowerShell=$PSVersionTable.PSVersion.ToString()}) -Create
}

function Add-DoomInputReplayJournalBatch {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Batch)
    if($Batch.Kind -ne 'Batch' -or ($Batch.Sequence -isnot [int] -and $Batch.Sequence -isnot [long]) -or
        $Batch.Sequence -lt 1 -or ($Batch.StartTic -isnot [int] -and $Batch.StartTic -isnot [long]) -or
        ($Batch.EndTic -isnot [int] -and $Batch.EndTic -isnot [long]) -or $Batch.StartTic -lt 0 -or
        $Batch.EndTic -lt $Batch.StartTic -or $Batch.EndTic -gt 1260000 -or $Batch.Final -isnot [bool]){
        throw 'Invalid replay journal batch boundary.'
    }
    foreach($field in 'InputCommands','AutomapCommands','ControlEvents','Checkpoints','Transitions'){
        if($Batch.$field -isnot [array]){throw "Replay journal $field must be an array."}
    }
    if($Batch.InputCommands.Count -ne ($Batch.EndTic-$Batch.StartTic)){
        throw 'Replay journal command count does not match its boundary.'
    }
    foreach($command in $Batch.InputCommands){
        if($command -isnot [array] -or $command.Count -ne 4){throw 'Invalid replay journal command shape.'}
        foreach($value in $command){if($value -isnot [int] -and $value -isnot [long]){throw 'Replay journal commands must contain integers.'}}
        if($command[0] -lt -50 -or $command[0] -gt 50 -or $command[1] -lt -50 -or $command[1] -gt 50 -or
            $command[2] -lt -32768 -or $command[2] -gt 32767 -or $command[3] -lt 0 -or $command[3] -gt 255){
            throw 'Replay journal command is out of range.'
        }
    }
    foreach($entry in $Batch.AutomapCommands){
        if($null -eq $entry -or ($entry.Tic -isnot [int] -and $entry.Tic -isnot [long]) -or
            $entry.Tic -lt $Batch.StartTic -or $entry.Tic -ge $Batch.EndTic -or
            ($entry.Mask -isnot [int] -and $entry.Mask -isnot [long]) -or $entry.Mask -lt 1 -or $entry.Mask -gt 1023){
            throw 'Invalid automap command boundary in replay journal batch.'
        }
    }
    foreach($field in 'ControlEvents','Checkpoints'){
        $previousTic=$null
        foreach($entry in $Batch.$field){
            if($null -eq $entry -or ($entry.Tic -isnot [int] -and $entry.Tic -isnot [long]) -or
                $entry.Tic -lt $Batch.StartTic -or $entry.Tic -gt $Batch.EndTic -or
                ($null -ne $previousTic -and $entry.Tic -lt $previousTic)){
                throw "Invalid $field boundary in replay journal batch."
            }
            if($field -eq 'Checkpoints' -and ($entry.Sha256 -isnot [string] -or $entry.Sha256 -notmatch '^[a-fA-F0-9]{64}$')){
                throw 'Invalid checkpoint hash in replay journal batch.'
            }
            $previousTic=$entry.Tic
        }
    }
    $previousTransitionTic=$null
    foreach($entry in $Batch.Transitions){
        if($null -eq $entry -or ($entry.Tic -isnot [int] -and $entry.Tic -isnot [long]) -or
            $entry.Tic -lt $Batch.StartTic -or $entry.Tic -gt $Batch.EndTic -or
            ($null -ne $previousTransitionTic -and $entry.Tic -lt $previousTransitionTic)){
            throw 'Invalid transition boundary in replay journal batch.'
        }
        $previousTransitionTic=$entry.Tic
    }
    Write-DoomReplayJournalLine $Path $Batch
}

function Read-DoomInputReplayJournal {
    param([Parameter(Mandatory)][string]$Path)
    $full=[IO.Path]::GetFullPath($Path);$info=Get-Item -LiteralPath $full
    if($info.Length -gt 128MB){throw 'Replay journal exceeds the 128 MiB input limit.'}
    [byte[]]$bytes=[IO.File]::ReadAllBytes($full)
    $lastNewline=[Array]::LastIndexOf($bytes,[byte]10)
    if($lastNewline -lt 0){throw 'Replay journal has no complete header record.'}
    $tornTail=$lastNewline -lt ($bytes.Length-1)
    $text=[Text.Encoding]::UTF8.GetString($bytes,0,$lastNewline+1)
    $lines=@($text.Split([char]10,[StringSplitOptions]::RemoveEmptyEntries))
    if($lines.Count -lt 1 -or $lines.Count -gt 20001){throw 'Replay journal record count is invalid.'}
    $payloads=[Collections.Generic.List[object]]::new()
    for($i=0;$i -lt $lines.Count;$i++){
        $line=$lines[$i].TrimEnd([char]13)
        try{$envelope=ConvertFrom-Json -InputObject $line -AsHashtable -Depth 16}catch{throw "Invalid replay journal envelope at line $($i+1)."}
        if($envelope.Payload -isnot [string] -or $envelope.Sha256 -notmatch '^[a-fA-F0-9]{64}$'){
            throw "Invalid replay journal envelope at line $($i+1)."
        }
        $actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($envelope.Payload)))
        if($actual -cne $envelope.Sha256.ToUpperInvariant()){throw "Replay journal checksum mismatch at line $($i+1)."}
        try{$payload=ConvertFrom-Json -InputObject $envelope.Payload -AsHashtable -Depth 16}catch{throw "Invalid replay journal payload at line $($i+1)."}
        $payloads.Add($payload)
    }
    $header=$payloads[0]
    if($header.Format -ne 'pwshDoom.InputReplayJournal' -or $header.Version -ne 1 -or
        $header.WadSha256 -notmatch '^[a-fA-F0-9]{64}$' -or $header.SourceFingerprint -notmatch '^[a-fA-F0-9]{64}$' -or
        $header.Skill -lt 1 -or $header.Skill -gt 5 -or $header.Episode -lt 1 -or $header.Episode -gt 4 -or $header.Map -lt 1 -or $header.Map -gt 32){
        throw 'Unsupported or invalid replay journal header.'
    }
    $commands=[Collections.Generic.List[object]]::new();$automap=[Collections.Generic.List[object]]::new()
    $controls=[Collections.Generic.List[object]]::new();$checkpoints=[Collections.Generic.List[object]]::new()
    $transitions=[Collections.Generic.List[object]]::new();$covered=0;$expectedSequence=1;$final=$false
    for($i=1;$i -lt $payloads.Count;$i++){
        $batch=$payloads[$i]
        if($batch.Kind -ne 'Batch' -or $batch.Sequence -ne $expectedSequence -or $batch.StartTic -ne $covered -or
            $batch.EndTic -lt $batch.StartTic -or $batch.EndTic -gt 1260000 -or
            $batch.InputCommands -isnot [array] -or $batch.InputCommands.Count -ne ($batch.EndTic-$batch.StartTic) -or
            $batch.AutomapCommands -isnot [array] -or $batch.ControlEvents -isnot [array] -or
            $batch.Checkpoints -isnot [array] -or $batch.Transitions -isnot [array]){
            throw "Invalid replay journal sequence or boundary at record $($i+1)."
        }
        foreach($command in $batch.InputCommands){$commands.Add($command)}
        foreach($entry in @($batch.AutomapCommands)){
            if($entry.Tic -lt $batch.StartTic -or $entry.Tic -ge $batch.EndTic -or $entry.Mask -lt 1 -or $entry.Mask -gt 1023){throw 'Invalid automap command in replay journal.'}
            if($automap.Count -gt 0 -and $entry.Tic -le $automap[$automap.Count-1].Tic){throw 'Replay journal automap commands are not strictly ordered.'}
            $automap.Add($entry)
        }
        foreach($entry in @($batch.ControlEvents)){
            if($null -eq $entry -or $entry.Tic -isnot [long] -or $entry.Tic -lt $batch.StartTic -or
                $entry.Tic -gt $batch.EndTic -or ($controls.Count -gt 0 -and $entry.Tic -lt $controls[$controls.Count-1].Tic)){
                throw 'Invalid control event boundary in replay journal.'
            }
            $controls.Add($entry)
        }
        foreach($entry in @($batch.Checkpoints)){
            if($null -eq $entry -or $entry.Tic -isnot [long] -or $entry.Tic -lt $batch.StartTic -or
                $entry.Tic -gt $batch.EndTic -or ($checkpoints.Count -gt 0 -and $entry.Tic -lt $checkpoints[$checkpoints.Count-1].Tic)){
                throw 'Invalid checkpoint boundary in replay journal.'
            }
            if($checkpoints.Count -gt 0 -and $entry.Tic -eq $checkpoints[$checkpoints.Count-1].Tic){$checkpoints[$checkpoints.Count-1]=$entry}
            else{$checkpoints.Add($entry)}
        }
        foreach($entry in @($batch.Transitions)){
            if($null -eq $entry -or $entry.Tic -isnot [long] -or $entry.Tic -lt $batch.StartTic -or
                $entry.Tic -gt $batch.EndTic -or ($transitions.Count -gt 0 -and $entry.Tic -lt $transitions[$transitions.Count-1].Tic)){
                throw 'Invalid transition boundary in replay journal.'
            }
            $transitions.Add($entry)
        }
        $covered=$batch.EndTic;$expectedSequence++
        if($batch.Final -isnot [bool]){throw 'Replay journal final marker must be a boolean.'}
        if($batch.Final){if($i -ne $payloads.Count-1){throw 'Replay journal contains records after its final batch.'};$final=$true}
    }
    if($controls.Count -gt 10000 -or $checkpoints.Count -gt 126001 -or $automap.Count -gt $commands.Count){throw 'Replay journal exceeds a replay collection limit.'}
    return @{Header=$header;InputCommands=$commands.ToArray();AutomapCommands=$automap.ToArray();
        ControlEvents=$controls.ToArray();Checkpoints=$checkpoints.ToArray();Transitions=$transitions.ToArray();
        Tics=$covered;Final=$final;TornTailDiscarded=$tornTail;CompleteRecords=$payloads.Count}
}

function ConvertFrom-DoomInputReplayJournal {
    param([Parameter(Mandatory)][string]$Path)
    $journal=Read-DoomInputReplayJournal $Path;$header=$journal.Header
    if($journal.Tics -eq 0){throw 'Replay journal does not contain any consumed game commands.'}
    return [ordered]@{Format='pwshDoom.InputReplay';Version=4;CreatedUtc=$header.CreatedUtc;WadSha256=$header.WadSha256;
        Skill=[long]$header.Skill;Episode=[long]$header.Episode;Map=[long]$header.Map;ContinueCampaign=$true;
        SourceFingerprint=$header.SourceFingerprint;PowerShell=$header.PowerShell;Origin='RecoveredJournal';
        ExitReason=if($journal.Final){'RecoveredWorkerStop'}else{'RecoveredInterrupted'};RecoveredFromJournal=$true;
        RecoveredUtc=[DateTime]::UtcNow.ToString('o');RecoveredTics=$journal.Tics;TornJournalTailDiscarded=$journal.TornTailDiscarded;
        InputCommands=$journal.InputCommands;AutomapCommands=$journal.AutomapCommands;ControlEvents=$journal.ControlEvents;
        Checkpoints=$journal.Checkpoints;Transitions=$journal.Transitions;
        Meaning='Recovered prefix from the append-only session journal. The last complete journal batch is preserved; any torn final line is discarded. This is replay evidence, not proof of map completion.'}
}
