#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Reference,[Parameter(Mandatory)][string]$Candidate,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Use a fresh parity report.'}
$a=Get-Content $Reference -Raw|ConvertFrom-Json;$b=Get-Content $Candidate -Raw|ConvertFrom-Json
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Same-Value($Left,$Right){return ($Left|ConvertTo-Json -Depth 8 -Compress) -ceq ($Right|ConvertTo-Json -Depth 8 -Compress)}
try{
    foreach($field in 'WadSha256','BundleSha256','PlanSha256','Episode','Map','Skill','ArrivalDistance','CombatStrafe','CollectDroppedWeapons','MaxIterations','CompletedUpdates','SimulationCommands','FinalHealth','FinalState','Passed'){
        Check "Same $field" (Same-Value $a.$field $b.$field)
    }
    Check 'Candidate pins current driver' ($b.DriverSha256 -ceq (Get-FileHash "$PSScriptRoot/Test-CampaignRoute.ps1").Hash)
    Check 'Barrel strategy is disabled with no events' (-not $b.BarrelStrategy.Enabled -and $b.BarrelStrategy.Events.Count -eq 0)
    Check 'Identical planned points and emitted commands' ((Same-Value $a.Route $b.Route) -and (Same-Value $a.InputCommands $b.InputCommands))
    Check 'Same trace and arrival counts' ($a.Trace.Count -eq $b.Trace.Count -and $a.Reached.Count -eq $b.Reached.Count)
    foreach($kind in 'Trace','Reached','PickupEvents'){
        Check "Same $kind count" ($a.$kind.Count -eq $b.$kind.Count)
        for($i=0;$i -lt $a.$kind.Count;$i++){
            $left=$a.$kind[$i];$right=$b.$kind[$i]
            foreach($property in $left.PSObject.Properties){
                if(-not $right.PSObject.Properties[$property.Name] -or -not(Same-Value $property.Value $right.($property.Name))){throw "$kind differs at item $i / $($property.Name)."}
            }
        }
        Check "Every $kind value matches" $true
    }
    foreach($property in $a.FinalPlayer.PSObject.Properties){Check "Final player $($property.Name) matches" (Same-Value $property.Value $b.FinalPlayer.($property.Name))}
    # Line numbers change when the driver changes; preserve the actual outcome.
    Check 'Same outcome message' (($a.Error -split "`n")[0] -ceq ($b.Error -split "`n")[0])
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    @{Passed=($null -eq $failure);Error=$failure;Checks=$checks.ToArray();Commands=$b.CompletedUpdates;TraceSamples=$b.Trace.Count;ReferenceSha256=(Get-FileHash $Reference).Hash;CandidateSha256=(Get-FileHash $Candidate).Hash;ScriptSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Two complete route-driver executions with identical plan/assets/options compare every emitted input and recorded trace/arrival/pickup value plus final state. Candidate barrel strategy is off. An identical retained failure proves default preservation, not successful map completion; changing script stack line numbers is expected.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $($checks.Count) driver parity checks; $($b.CompletedUpdates) identical commands."
