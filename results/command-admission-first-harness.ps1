#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh admission report.'}
. "$PSScriptRoot/../src/SimulationProcess.ps1"
$map=$null;$view=$null;$go=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Verify-Command([int]$Index){
    [long]$offset=4096+($Index%1024)*16
    $expected=@(($Index%51),(-($Index%51)),(($Index*13)%32768),($Index%4))
    for($field=0;$field -lt 4;$field++){if($view.ReadInt32($offset+4*$field) -ne $expected[$field]){throw "Command $Index field $field changed across ring wrap."}}
    if($view.ReadInt32(98304+($Index%1024)*4) -ne $Index%1024){throw 'Automap mask changed.'}
}
try{
    $map=[IO.MemoryMappedFiles.MemoryMappedFile]::CreateNew($null,3145728);$view=$map.CreateViewAccessor()
    $go=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset)
    $simulation=@{View=$view;Go=$go}
    Check 'Empty default window admits the first command' (Test-DoomSimulationCommandWindow $simulation 0)
    $read=0
    for($write=0;$write -lt 1200;$write++){
        if($write-$read -eq 2){
            if(Test-DoomSimulationCommandWindow $simulation $write){throw 'Full two-command window admitted another input.'}
            $published=$view.ReadInt32(0);Verify-Command $read
            if($view.ReadInt32(0) -ne $published){throw 'Admission query changed producer position.'}
            $read++;$view.Write(20,[int]$read)
        }
        if(-not (Test-DoomSimulationCommandWindow $simulation $write)){throw 'Freed slot was not admitted.'}
        Send-DoomSimulationCommand $simulation $write @(($write%51),(-($write%51)),(($write*13)%32768),($write%4)) -AutomapMask ($write%1024)
        if($view.ReadInt32(0) -ne $write+1 -or -not $go.WaitOne(0)){throw 'Publication index or wake event missing.'}
    }
    while($read -lt 1200){Verify-Command $read;$read++;$view.Write(20,[int]$read)}
    Check 'All 1200 commands and masks survive admission and physical ring wrap' ($read -eq 1200 -and $view.ReadInt32(0) -eq 1200)
    Check 'Drained window admits its exact next index' (Test-DoomSimulationCommandWindow $simulation 1200)
    $view.Write(20,0);$view.Write(0,0)
    Check 'Configured full transport window rejects index 1024' (-not (Test-DoomSimulationCommandWindow $simulation 1024 -Limit 1024))
    $rejected=$false;try{Send-DoomSimulationCommand $simulation 1024 @(0,0,0,0)}catch{$rejected=$_.Exception.Message -eq 'Simulation command ring overflow.'}
    Check 'Transport hard overflow guard remains and does not publish' ($rejected -and $view.ReadInt32(0) -eq 0)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($go){$go.Dispose()};if($view){$view.Dispose()};if($map){$map.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();TransportSha256=(Get-FileHash "$PSScriptRoot/../src/SimulationProcess.ps1").Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Actual mapped memory and wake event with deterministic consumer-header fixture; 1200 distinct commands/masks cross the 1024-slot boundary. This isolates transport/admission semantics; actual-process pressure and gameplay are separate host checks.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $($checks.Count) command-admission checks, 1200 commands verified."
