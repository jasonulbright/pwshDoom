#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Save,[Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/save-validation-bundle-$PID.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1";. "$PSScriptRoot/../src/SaveState.ps1"
Set-StrictMode -Version Latest
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new()
$directory=Join-Path "$PSScriptRoot/../local" ('save-validation-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
function Check-Rejection([string]$Name,[scriptblock]$Action,[string]$Expected){
    $message=$null;try{& $Action}catch{$message=$_.ToString()}
    $pass=$null -ne $message -and $message -like ('*'+$Expected+'*')
    $checks.Add(@{Name=$Name;Passed=$pass;Error=$message});if(-not $pass){throw "Unexpected validation result for $Name : $message"}
}
function Set-GraphProperty($Graph,[string]$Type,[string]$Property,$Value){
    $node=@($Graph.Nodes|Where-Object Type -EQ $Type)[0];$names=@($catalog[$Type].Properties.Name);$index=-1
    for($i=0;$i -lt $names.Count;$i++){if($names[$i] -ieq $Property){$index=$i;break}}
    if($index -lt 0){throw "Fixture property unavailable: $Type.$Property"};$node.Values[$index]=$Value
}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$wadHash=(Get-FileHash $Wad).Hash;$catalog=New-DoomSaveCatalog
    $wire=Read-DoomSaveState $Save $wadHash;$live=New-DoomGameFromSave $wire $content;$before=Get-DoomReplayCheckpoint $live $live.GameTic
    $truncated=Join-Path $directory 'truncated.pds';[IO.File]::WriteAllText($truncated,'{')
    Check-Rejection 'Truncated JSON' {$null=Read-DoomSaveState $truncated $wadHash} 'Conversion from JSON failed'
    $huge=Join-Path $directory 'oversized.pds';$stream=[IO.File]::Create($huge);try{$stream.SetLength(64MB+1)}finally{$stream.Dispose()}
    Check-Rejection 'File size limit before JSON parsing' {$null=Read-DoomSaveState $huge $wadHash} 'exceeds 64 MiB'
    $wire.Metadata.WadSha256='A'*64
    Check-Rejection 'Actual candidate IWAD checked even after metadata-only read' {$null=New-DoomGameFromSave $wire $content} 'does not match the saved single IWAD'
    foreach($case in @(
        @('Duplicate binding',{param($g)$g.Nodes+=@($g.Nodes[0])},'repeated save binding'),
        @('Null thinker ring',{param($g)Set-GraphProperty $g 'Thinkers' 'Cap' @(0)},'Invalid saved thinker'),
        @('Invalid collision-grid dimensions',{param($g)$block=@($g.Nodes|Where-Object Type -EQ 'BlockMap')[0];$g.Nodes[$block.Values[0][1]].Values=@()},'Invalid saved collision-grid size'),
        @('Invalid RNG index',{param($g)Set-GraphProperty $g 'DoomRandom' 'Index' @(1,'Int32',999)},'Invalid saved clock or RNG state'),
        @('Out-of-range Fixed value',{param($g)Set-GraphProperty $g 'Mobj' 'X' @(1,'Fixed',2147483648)},'Fixed value outside range')
    )){
        $wire=Read-DoomSaveState $Save $wadHash;& $case[1] $wire.Graph
        $wire.Graph=$wire.Graph|ConvertTo-Json -Depth 12 -Compress|ConvertFrom-Json -Depth 12
        Check-Rejection $case[0] {$null=New-DoomGameFromSave $wire $content} $case[2]
    }
    $wire=Read-DoomSaveState $Save $wadHash;$wire.Metadata.Skill=if($wire.Metadata.Skill -eq 3){4}else{3}
    Check-Rejection 'Header and graph starting settings disagree' {$null=New-DoomGameFromSave $wire $content} 'disagrees with its IWAD/settings header'
    $after=Get-DoomReplayCheckpoint $live $live.GameTic;$same=$before.Sha256 -ceq $after.Sha256
    $checks.Add(@{Name='Rejected candidates leave live checkpoint unchanged';Passed=$same});if(-not $same){throw 'Live state changed.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();SaveSha256=(Get-FileHash $Save).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;SourceSha256=(Get-FileHash "$PSScriptRoot/../src/SaveState.ps1").Hash;Meaning='Additional bounded corruption cases against independent candidate games; named expected rejection messages prevent arbitrary harness failures from counting as success.'}|ConvertTo-Json -Depth 8|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($checks.Count) additional save validation checks."
