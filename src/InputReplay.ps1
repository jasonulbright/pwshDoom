# SPDX-License-Identifier: GPL-2.0-or-later
# Data-only input recordings. Checkpoints detect selected state divergence; they
# are not save states, a complete thinker graph, or vanilla demo compatibility.
function Read-DoomInputReplay {
    param([string]$Path,[string]$WadSha256)
    $file=Get-Item -LiteralPath $Path
    if($file.Length -gt 128MB){throw 'Replay exceeds the 128 MiB input limit.'}
    $data=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json -Depth 16
    if($data -isnot [pscustomobject]){throw 'Replay root must be an object.'}
    foreach($field in 'Format','Version','Skill','Episode','Map','Checkpoints','SourceFingerprint','ControlEvents','AutomapCommands'){
        if($null -eq $data.PSObject.Properties[$field]){$data|Add-Member -NotePropertyName $field -NotePropertyValue $null}
    }
    $hasContinuation=$null -ne $data.PSObject.Properties['ContinueCampaign']
    if(-not $hasContinuation){$data|Add-Member -NotePropertyName ContinueCampaign -NotePropertyValue $false}
    if($data.ContinueCampaign -isnot [bool]){throw 'Replay ContinueCampaign must be a boolean.'}
    if($null -ne $data.SourceFingerprint -and $data.SourceFingerprint -notmatch '^[0-9a-fA-F]{64}$'){throw 'Invalid replay source fingerprint.'}
    if($data.WadSha256 -notmatch '^[0-9a-fA-F]{64}$' -or ($WadSha256 -and $data.WadSha256 -ne $WadSha256)){throw 'Replay IWAD hash does not match.'}
    if($null -ne $data.Format -or $null -ne $data.Version){
        if($data.Format -ne 'pwshDoom.InputReplay' -or $data.Version -isnot [long] -or $data.Version -notin 1,2,3,4){throw 'Unsupported input replay format/version.'}
        foreach($field in 'Skill','Episode','Map'){if($null -eq $data.$field){throw "Replay is missing $field."}}
        if(-not $hasContinuation -or $data.ContinueCampaign -isnot [bool]){throw 'Replay ContinueCampaign must be a boolean.'}
    }
    if($data.Version -in 2,3,4){
        if($data.ControlEvents -isnot [array] -or $data.ControlEvents.Count -gt 10000){throw 'Invalid replay control event list.'}
        $lastControl=-1
        foreach($control in $data.ControlEvents){
            if($control.Tic -isnot [long] -or $control.Tic -lt 0 -or $control.Tic -lt $lastControl -or $control.Tic -gt $data.InputCommands.Count){throw 'Invalid replay control boundary.'}
            if($control.Action -eq 'NewGame'){
                if($control.Skill -isnot [long] -or $control.Skill -lt 1 -or $control.Skill -gt 5 -or $control.Episode -isnot [long] -or $control.Episode -lt 1 -or $control.Episode -gt 4 -or $control.Map -isnot [long] -or $control.Map -ne 1){throw 'Invalid replay new-game event.'}
            }elseif($control.Action -eq 'LoadGame' -and $data.Version -in 3,4){
                if($control.SaveHash -isnot [string] -or $control.SaveHash -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid replay save reference.'}
            }else{throw 'Unsupported replay control action.'}
            $lastControl=$control.Tic
        }
        # Do not forward file paths or slot mutations from replay data.
        $data.ControlEvents=@(foreach($control in $data.ControlEvents){if($control.Action -eq 'LoadGame'){[pscustomobject]@{Tic=$control.Tic;Action='LoadGame';SaveHash=$control.SaveHash}}else{$control}})
    }elseif($null -ne $data.ControlEvents -and $data.ControlEvents.Count -gt 0){throw 'Control events require replay version 2.'}
    foreach($pair in @(@('Skill',5),@('Episode',4),@('Map',32))){
        $value=$data.($pair[0])
        if($null -ne $value -and ($value -isnot [long] -or $value -lt 1 -or $value -gt $pair[1])){throw "Invalid replay $($pair[0])."}
    }
    if($data.InputCommands -isnot [array] -or $data.InputCommands.Count -gt 1260000){throw 'Replay requires an array of at most ten hours of commands.'}
    if($data.Version -eq 4){
        if($data.AutomapCommands -isnot [array] -or $data.AutomapCommands.Count -gt $data.InputCommands.Count){throw 'Invalid replay automap command list.'}
        $lastMapTic=-1
        foreach($mapCommand in $data.AutomapCommands){
            if($mapCommand.Tic -isnot [long] -or $mapCommand.Tic -le $lastMapTic -or $mapCommand.Tic -ge $data.InputCommands.Count -or $mapCommand.Mask -isnot [long] -or $mapCommand.Mask -lt 1 -or $mapCommand.Mask -gt 1023){throw 'Invalid replay automap command.'}
            $lastMapTic=$mapCommand.Tic
        }
    }elseif($null -ne $data.AutomapCommands -and $data.AutomapCommands.Count -gt 0){throw 'Automap commands require replay version 4.'}
    foreach($entry in $data.InputCommands){
        if($entry -isnot [array] -or $entry.Count -ne 4){throw 'Invalid replay command shape.'}
        foreach($value in $entry){if($value -isnot [long]){throw 'Replay commands must contain integers.'}}
        if([Math]::Abs($entry[0]) -gt 50 -or [Math]::Abs($entry[1]) -gt 50 -or $entry[2] -lt -32768 -or $entry[2] -gt 32767 -or $entry[3] -lt 0 -or $entry[3] -gt 255){throw 'Replay command is out of range.'}
    }
    if($null -ne $data.Checkpoints){
        if($data.Checkpoints -isnot [array] -or $data.Checkpoints.Count -gt 126001){throw 'Invalid replay checkpoint list.'}
        $last=-1
        foreach($checkpoint in $data.Checkpoints){
            if($checkpoint.Tic -isnot [long] -or $checkpoint.Tic -le $last -or $checkpoint.Tic -gt $data.InputCommands.Count -or $checkpoint.Sha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'Invalid replay checkpoint.'}
            if($null -ne $checkpoint.PSObject.Properties['AutomapSha256'] -and $checkpoint.AutomapSha256 -notmatch '^[0-9a-fA-F]{64}$'){throw 'Invalid replay automap checkpoint.'}
            $last=$checkpoint.Tic
        }
    }
    return $data
}

function Set-DoomReplaySettings {
    param($ReplayData,[System.Collections.IDictionary]$Explicit,[int]$Skill=3,[int]$Episode=1,[int]$Map=1)
    $settings=@{Skill=$Skill;Episode=$Episode;Map=$Map}
    foreach($field in 'Skill','Episode','Map'){
        # Historical route files omitted settings; their documented start is E1M1/HMP.
        $recorded=if($null -ne $ReplayData.$field){[int]$ReplayData.$field}elseif($field -eq 'Skill'){3}else{1}
        if($Explicit.Keys -contains $field -and $settings[$field] -ne $recorded){throw "Replay $field is $recorded; the explicit launch setting differs."}
        $settings[$field]=$recorded
    }
    return $settings
}

function Get-DoomReplaySourceFingerprint {
    $root=Split-Path $PSScriptRoot
    $paths=@('scripts/Build-EngineBundle.ps1','scripts/Invoke-SimulationWorker.ps1','src/GameHost.ps1','src/SnapshotTransport.ps1','src/SessionScreens.ps1','src/SessionMenu.ps1','src/InputReplay.ps1','src/SaveState.ps1','src/SaveSlots.ps1','src/AutomapSession.ps1')
    $paths+=@(Get-ChildItem -LiteralPath "$PSScriptRoot/ManagedDoom" -Filter *.ps1 -File -Recurse|ForEach-Object {[IO.Path]::GetRelativePath($root,$_.FullName).Replace('\','/')})
    $lines=@($paths|Sort-Object|ForEach-Object {$_+' '+(Get-FileHash -LiteralPath (Join-Path $root $_)).Hash})
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($lines -join "`n")))
}

function Get-DoomReplayCheckpoint {
    param($Game,[int]$Tic)
    $p=$Game.World.ConsolePlayer
    $bytes=ConvertTo-GameSnapshotBytes (New-GameRenderSnapshot $Game 1)
    $state=[ordered]@{Schema=1;Tic=$Tic;State=$Game.State.ToString();Episode=$Game.Options.Episode;Map=$Game.Options.Map;LevelTime=$Game.World.LevelTime;
        RandomIndex=$Game.Options.Random.Index;Paused=$Game.Paused;PlayerState=$p.PlayerState.ToString();Health=$p.Health;Armor=$p.ArmorPoints;
        Position=@($p.Mobj.X.Data,$p.Mobj.Y.Data,$p.Mobj.Z.Data,$p.Mobj.Angle.Data);Ammo=$p.Ammo.Clone();Weapons=$p.WeaponOwned.Clone();Keys=$p.Cards.Clone();DidSecret=$p.DidSecret;
        RenderSnapshotSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));Intermission=$null;Finale=$null}
    if([int]$Game.State -eq 1){$ui=$Game.Intermission;$state.Intermission=@([int]$ui.State,$ui.SpState,$ui.Count,$ui.BgCount,$ui.TimeCount,$ui.ParCount,$ui.Random.Index)}
    if([int]$Game.State -eq 2){$ui=$Game.Finale;$state.Finale=@($ui.Stage,$ui.Count,$ui.Scrolled,$ui.TheEndIndex)}
    $json=$state|ConvertTo-Json -Depth 5 -Compress
    $result=@{Tic=$Tic;Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json)));State=$state}
    if(Get-Command Get-DoomAutomapCheckpoint -ErrorAction SilentlyContinue){$result.AutomapSha256=Get-DoomAutomapCheckpoint $Game}
    return $result
}

function Compare-DoomReplayCheckpoints {
    param($Expected,$Actual,[int]$ConsumedTics)
    $byTic=@{};foreach($entry in $Actual){$byTic[[int]$entry.Tic]=$entry}
    $checked=0;$mismatches=@()
    foreach($entry in $Expected){
        if($entry.Tic -gt $ConsumedTics){continue}
        $observed=$byTic[[int]$entry.Tic];$checked++
        if($null -eq $observed -or $entry.Sha256 -ne $observed.Sha256){$mismatches+=@{Tic=$entry.Tic;Expected=$entry.Sha256;Actual=if($null -ne $observed){$observed.Sha256}else{$null}}}
        $expectedMap=if($entry -is [Collections.IDictionary]){$entry['AutomapSha256']}elseif($null -ne $entry.PSObject.Properties['AutomapSha256']){$entry.AutomapSha256}else{$null}
        if($expectedMap){
            $actualMap=if($observed -is [Collections.IDictionary]){$observed['AutomapSha256']}elseif($null -ne $observed -and $null -ne $observed.PSObject.Properties['AutomapSha256']){$observed.AutomapSha256}else{$null}
            if($expectedMap -ne $actualMap){$mismatches+=@{Tic=$entry.Tic;Kind='Automap';Expected=$expectedMap;Actual=$actualMap}}
        }
    }
    return @{Checked=$checked;Matched=$mismatches.Count -eq 0;Mismatches=$mismatches;Meaning='Compared available recorded checkpoints through the consumed prefix. This samples selected state and render data, not every hidden game field.'}
}

function Write-DoomInputReplay {
    param([string]$Path,$Data)
    $destination=[IO.Path]::GetFullPath($Path)
    if(Test-Path -LiteralPath $destination){throw 'Input recording destination already exists; choose a new filename.'}
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    $temporary=$destination+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temporary,($Data|ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
        $null=Read-DoomInputReplay $temporary $Data.WadSha256
        [IO.File]::Move($temporary,$destination,$false)
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
    return $destination
}
