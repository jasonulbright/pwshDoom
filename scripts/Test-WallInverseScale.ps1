#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$ReferenceSource="$PSScriptRoot/../src/ManagedDoom/Video/ThreeDRenderer.sb.ps1")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report.'}
$taskBundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $taskBundle
$taskTokens=$null;$taskParseErrors=$null
$taskAst=[Management.Automation.Language.Parser]::ParseFile([IO.Path]::GetFullPath($ReferenceSource),[ref]$taskTokens,[ref]$taskParseErrors)
if($taskParseErrors.Count){throw 'Reference source does not parse.'}
$taskAssignments=@($taskAst.FindAll({param($n)
    $n -is [Management.Automation.Language.AssignmentStatementAst] -and
    $n.Right.Extent.Text -match '0xFFFFFFFFu\s*/\s*\[uint\]'
},$true))
if($taskAssignments.Count -ne 3){throw 'Expected the solid, portal and masked inverse-scale assignments.'}
$taskCases=[Collections.Generic.List[int]]::new()
foreach($taskScale in 256,257,511,512,513,1023,1024,1025,32767,32768,32769,65535,65536,65537,131071,131072,131073,262143,262144,262145,4194303,4194304){$taskCases.Add($taskScale)}
$taskRandom=[Random]::new(20261002)
for($taskI=0;$taskI -lt 20000;$taskI++){$taskCases.Add($taskRandom.Next(256,4194305))}
$taskResults=[Collections.Generic.List[object]]::new();$taskFailure=$null;$taskCompared=0;$taskMismatches=0
try{
    foreach($taskAssignment in $taskAssignments){
        # Evaluate the actual source expression rather than a duplicated formula.
        $taskExpression=[scriptblock]::Create('param([int]$rwScaleData,[Fixed]$scale) '+$taskAssignment.Right.Extent.Text)
        $taskCount=0;$taskWrong=0;$taskExamples=[Collections.Generic.List[object]]::new()
        foreach($taskScaleData in $taskCases){
            $taskRemainder=0L
            $taskExpected=[Math]::DivRem(4294967295L,[long]$taskScaleData,[ref]$taskRemainder)
            $taskActual=$taskExpression.InvokeReturnAsIs($taskScaleData,[Fixed]::new($taskScaleData))
            $taskActualData=if($taskActual -is [Fixed]){$taskActual.Data}else{[int]$taskActual}
            if($taskActualData -ne $taskExpected){
                $taskWrong++
                if($taskExamples.Count -lt 5){$taskExamples.Add(@{ScaleData=$taskScaleData;Expected=$taskExpected;Actual=$taskActualData})}
            }
            $taskCount++
        }
        $taskCompared+=$taskCount;$taskMismatches+=$taskWrong
        $taskResults.Add(@{SourceLine=$taskAssignment.Extent.StartLineNumber;Expression=$taskAssignment.Right.Extent.Text;Compared=$taskCount;Mismatches=$taskWrong;Examples=$taskExamples.ToArray()})
    }
}catch{$taskFailure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    @{Error=$taskFailure;FinishedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();ScaleSeed=20261002;ScaleCases=$taskCases.Count;Compared=$taskCompared;Mismatches=$taskMismatches;Assignments=$taskResults.ToArray();SourceSha256=(Get-FileHash $ReferenceSource).Hash;SourcePath=[IO.Path]::GetFullPath($ReferenceSource);HarnessSha256=(Get-FileHash $PSCommandPath).Hash;BundleSha256=(Get-FileHash $taskBundle).Hash;Meaning='Three actual adopted-renderer inverse-scale assignment expressions evaluated across the ScaleFromGlobalAngle256..4194304 domain, boundary cases plus20k seeded scales, against independent exact uint32 numerator integer division via DivRem. Failed mismatch report retained. This qualifies the scalar expressions, not whole-scene/reference-original fidelity, frame pacing or gameplay.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
if($taskFailure){throw $taskFailure}
if($taskMismatches){throw "Inverse-scale mismatch; retained report has$taskMismatches of$taskCompared."}
"PASS: $taskCompared exact inverse-scale comparisons across three source assignments."
