#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Renderer,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh report.'}
if(-not [BitConverter]::IsLittleEndian){throw 'Byte oracle requires this recorded little-endian host.'}
$taskTokens=$null;$taskErrors=$null
$taskAst=[Management.Automation.Language.Parser]::ParseFile([IO.Path]::GetFullPath($Renderer),[ref]$taskTokens,[ref]$taskErrors)
if($taskErrors.Count){throw 'Renderer parse failed.'}
$taskAssignments=@($taskAst.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$wallTextureColumn' -and $n.Right.Extent.Text -match '65535'},$true))
$taskBranches=@($taskAst.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text.Trim() -eq '$wallTextureColumn -ge 32768'},$true))
if($taskAssignments.Count -ne 1 -or $taskBranches.Count -ne 1){throw 'Expected one signed texture-column wrap expression and branch.'}
$taskExpression=[scriptblock]::Create('param([long]$wallUData) [int]$wallTextureColumn=0;'+$taskAssignments[0].Extent.Text+';'+$taskBranches[0].Extent.Text+';return $wallTextureColumn')
$taskCases=[Collections.Generic.List[long]]::new()
foreach($taskCase in [long]::MinValue,[long]::MaxValue,-4294967297L,-4294967296L,-4294967295L,-2147483649L,-2147483648L,-2147483647L,-65537L,-65536L,-65535L,-1L,0L,1L,65535L,65536L,65537L,2147483647L,2147483648L,2147483649L,4294967295L,4294967296L,4294967297L){$taskCases.Add($taskCase)}
$taskRandom=[Random]::new(20261002);for($taskI=0;$taskI -lt 20000;$taskI++){$taskCases.Add($taskRandom.NextInt64([long]::MinValue,[long]::MaxValue))}
$taskWrong=0;$taskExamples=[Collections.Generic.List[object]]::new();$taskFailure=$null
try{
    foreach($taskValue in $taskCases){
        # Read the signed high word of the low32 bytes, independent of masks/shifts.
        $taskExpected=[BitConverter]::ToInt16([BitConverter]::GetBytes($taskValue),2)
        $taskActual=$taskExpression.InvokeReturnAsIs($taskValue)
        if($taskActual -ne $taskExpected){$taskWrong++;if($taskExamples.Count -lt 8){$taskExamples.Add(@{Value=$taskValue;Actual=$taskActual;Expected=$taskExpected})}}
    }
}catch{$taskFailure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    @{Error=$taskFailure;Compared=$taskCases.Count;Mismatches=$taskWrong;Examples=$taskExamples.ToArray();Seed=20261002;Expression=$taskExpression.ToString();RendererSha256=(Get-FileHash $Renderer).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Actual candidate signed texture-column wrap expression/branch, boundary and20k random signed long inputs, against independent little-endian signed high-word byte decoding. Broad values exceed map projection bounds. This isolates uint32 fixed-result wrap/high16 extraction, not point-distance/trig/coverage, image fidelity or performance.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}
if($taskFailure){throw $taskFailure}
if($taskWrong){throw "Texture-column wrap mismatches: $taskWrong; retained report."}
"PASS: $($taskCases.Count) signed texture-column wrap inputs."
