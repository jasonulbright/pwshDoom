#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Output="$PSScriptRoot/../results/input-replay-format.json")
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../src/InputReplay.ps1"
Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Choose a fresh output path.'}
$directory=Join-Path "$PSScriptRoot/../local" ('replay-format-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($directory)
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function New-Fixture {
    return [pscustomobject]@{Format='pwshDoom.InputReplay';Version=1;WadSha256=('A'*64);Skill=2;Episode=1;Map=2;ContinueCampaign=$true;
        InputCommands=@(@(25,0,640,1),@(0,-40,-32768,255));Checkpoints=@(@{Tic=0;Sha256=('B'*64)},@{Tic=2;Sha256=('C'*64)})}
}
function Assert-Rejected {
    param([string]$Name,[scriptblock]$Change)
    $data=New-Fixture;& $Change $data
    $path=Join-Path $directory ($checks.Count.ToString()+'.json')
    $data|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $path
    $rejected=$false;try{$null=Read-DoomInputReplay $path}catch{$rejected=$true}
    if(-not $rejected){throw "Accepted invalid replay: $Name"}
    $checks.Add(@{Name=$Name;Passed=$true})
}
try{
    $path=Join-Path $directory 'valid.json'
    $null=Write-DoomInputReplay $path (New-Fixture)
    $data=Read-DoomInputReplay $path ('A'*64)
    if($data.InputCommands.Count -ne 2 -or $data.InputCommands[1][2] -ne -32768){throw 'Valid replay changed during round trip.'}
    $checks.Add(@{Name='Versioned data-only round trip';Passed=$true})
    $hash=(Get-FileHash $path).Hash;$rejected=$false
    try{$null=Write-DoomInputReplay $path (New-Fixture)}catch{$rejected=$true}
    if(-not $rejected -or (Get-FileHash $path).Hash -ne $hash){throw 'Existing recording was overwritten.'}
    $checks.Add(@{Name='Existing file preserved';Passed=$true})
    $rejected=$false;try{$null=Read-DoomInputReplay $path ('D'*64)}catch{$rejected=$true}
    if(-not $rejected){throw 'Wrong IWAD accepted.'};$checks.Add(@{Name='Wrong IWAD rejected';Passed=$true})
    $settings=Set-DoomReplaySettings $data @{}
    if($settings.Skill -ne 2 -or $settings.Map -ne 2){throw 'Recorded settings were not selected.'}
    $checks.Add(@{Name='Recorded nondefault settings';Passed=$true})
    $rejected=$false;try{$null=Set-DoomReplaySettings $data @{Skill=3}}catch{$rejected=$true}
    if(-not $rejected){throw 'Conflicting setting accepted.'};$checks.Add(@{Name='Conflicting explicit setting rejected';Passed=$true})
    function Test-ExplicitBinding {param([int]$Skill=2) Set-DoomReplaySettings $data $PSBoundParameters $Skill}
    $null=Test-ExplicitBinding -Skill 2;$checks.Add(@{Name='Actual PSBoundParameters accepted';Passed=$true})
    foreach($case in @(
        @('Unknown version',{param($d)$d.Version=2}),@('String version',{param($d)$d.Version='1'}),@('Wrong format',{param($d)$d.Format='other'}),
        @('Missing starting skill',{param($d)$d.PSObject.Properties.Remove('Skill')}),@('Boolean skill',{param($d)$d.Skill=$true}),@('Map outside bounds',{param($d)$d.Map=33}),
        @('Nonboolean continuation',{param($d)$d.ContinueCampaign='false'}),@('Missing continuation',{param($d)$d.PSObject.Properties.Remove('ContinueCampaign')}),
        @('Invalid WAD hash',{param($d)$d.WadSha256='no'}),@('Invalid source fingerprint',{param($d)$d|Add-Member SourceFingerprint 'bad'}),@('Null commands',{param($d)$d.InputCommands=$null}),@('Scalar command',{param($d)$d.InputCommands=@(1)}),
        @('Short command',{param($d)$d.InputCommands=@(@(1,2,3),@(0,0,0,0))}),@('Float command',{param($d)$d.InputCommands[0][0]=1.5}),@('String command',{param($d)$d.InputCommands[0][0]='25'}),
        @('Null command field',{param($d)$d.InputCommands[0][0]=$null}),@('Forward movement bound',{param($d)$d.InputCommands[0][0]=51}),@('Side movement bound',{param($d)$d.InputCommands[0][1]=-51}),
        @('Turn bound',{param($d)$d.InputCommands[0][2]=32768}),@('Button bound',{param($d)$d.InputCommands[0][3]=256}),
        @('Unordered checkpoints',{param($d)$d.Checkpoints=@(@{Tic=2;Sha256=('B'*64)},@{Tic=0;Sha256=('C'*64)})}),
        @('Out-of-range checkpoint',{param($d)$d.Checkpoints[1].Tic=3}),@('Invalid checkpoint hash',{param($d)$d.Checkpoints[0].Sha256='bad'})
    )){Assert-Rejected $case[0] $case[1]}
    $legacy=Join-Path $directory 'legacy.json'
    @{WadSha256=('A'*64);InputCommands=@(@(0,0,0,0),@(0,0,0,2))}|ConvertTo-Json -Depth 4|Set-Content $legacy
    $old=Read-DoomInputReplay $legacy;$settings=Set-DoomReplaySettings $old @{}
    if($old.ContinueCampaign -or $settings.Skill -ne 3 -or $settings.Map -ne 1){throw 'Historical replay defaults changed.'}
    $checks.Add(@{Name='Historical replay defaults under strict mode';Passed=$true})
    $empty=New-Fixture;$empty.InputCommands=@();$empty.Checkpoints=@(@{Tic=0;Sha256=('B'*64)})
    $null=Write-DoomInputReplay (Join-Path $directory 'empty.json') $empty
    $checks.Add(@{Name='Zero-command graceful recording';Passed=$true})
    $large=Join-Path $directory 'large.json';$stream=[IO.File]::Create($large);try{$stream.SetLength(128MB+1)}finally{$stream.Dispose()}
    $rejected=$false;try{$null=Read-DoomInputReplay $large}catch{$rejected=$true}
    if(-not $rejected){throw 'Oversized file accepted.'};$checks.Add(@{Name='128 MiB size guard before JSON parsing';Passed=$true})
    $comparison=Compare-DoomReplayCheckpoints @(@{Tic=0;Sha256=('B'*64)},@{Tic=2;Sha256=('C'*64)}) @(@{Tic=0;Sha256=('B'*64)}) 1
    if(-not $comparison.Matched -or $comparison.Checked -ne 1){throw 'Prefix comparison failed.'}
    $checks.Add(@{Name='Unconsumed future checkpoint excluded';Passed=$true})
    $comparison=Compare-DoomReplayCheckpoints @(@{Tic=2;Sha256=('C'*64)}) @() 2
    if($comparison.Matched -or $comparison.Mismatches.Count -ne 1){throw 'Missing checkpoint accepted.'}
    $checks.Add(@{Name='Missing consumed checkpoint fails';Passed=$true})
    $comparison=Compare-DoomReplayCheckpoints @(@{Tic=2;Sha256=('C'*64)}) @(@{Tic=2;Sha256=('D'*64)}) 2
    if($comparison.Matched){throw 'Divergence accepted.'};$checks.Add(@{Name='Diverged checkpoint fails';Passed=$true})
}catch{$failure=$_.ToString();throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();SourceSha256=(Get-FileHash "$PSScriptRoot/../src/InputReplay.ps1").Hash;
        Meaning='Data format, bounds, non-overwrite, legacy defaults, launch binding and checkpoint-comparison checks. No WAD or running engine required; separate real-host replay checks establish runtime behavior.'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $Output
}
"PASS: $($checks.Count) input replay format checks."
