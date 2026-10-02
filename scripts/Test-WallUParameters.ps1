#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Renderer="$PSScriptRoot/../src/FastRenderer.ps1")
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh report.'}
$taskBundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $taskBundle;. $Renderer
function Get-ReferenceWallUParameters {
    param([int]$ViewX,[int]$ViewY,[int]$VertexX,[int]$VertexY,[uint32]$SegmentAngle,[uint32]$ViewAngle,[int]$SegmentOffset,[int]$SideOffset)
    $normal=[Angle]::new($SegmentAngle)+[Angle]::Ang90
    $angle1=[Geometry]::PointToAngle([Fixed]::new($ViewX),[Fixed]::new($ViewY),[Fixed]::new($VertexX),[Fixed]::new($VertexY))
    $offsetAngle=[Angle]::Abs($normal-$angle1);if($offsetAngle.Data -gt [Angle]::Ang90.Data){$offsetAngle=[Angle]::Ang90}
    $hyp=[Geometry]::PointToDist([Fixed]::new($ViewX),[Fixed]::new($ViewY),[Fixed]::new($VertexX),[Fixed]::new($VertexY))
    $perp=$hyp*[Trig]::Sin([Angle]::Ang90-$offsetAngle)
    $textureAngle=$normal-$angle1;if($textureAngle.Data -gt [Angle]::Ang180.Data){$textureAngle=-$textureAngle}
    if($textureAngle.Data -gt [Angle]::Ang90.Data){$textureAngle=[Angle]::Ang90}
    $offset=$hyp*[Trig]::Sin($textureAngle);if(($normal-$angle1).Data -lt [Angle]::Ang180.Data){$offset=-$offset}
    $offset=[Fixed]::new([Fixed]::ToInt32Unchecked([long]$offset.Data+$SegmentOffset+[long]$SideOffset))
    $center=[Angle]::Ang90+[Angle]::new($ViewAngle)-$normal
    return ,([long[]]@($perp.Data,$offset.Data,$center.Data))
}
$taskCompared=0;$taskWrong=0;$taskErrorsMatched=0;$taskExamples=[Collections.Generic.List[object]]::new();$taskFailure=$null
$taskRandom=[Random]::new(20261002)
$taskCases=[Collections.Generic.List[object]]::new()
foreach($taskX in [int]::MinValue,[int]::MaxValue,-65536,-1,0,1,65536){foreach($taskY in [int]::MinValue,[int]::MaxValue,-65536,-1,0,1,65536){
    $taskCases.Add(@(0,0,$taskX,$taskY,[uint32]4294901760,[uint32]2147483648,[int]::MaxValue,[int]::MinValue))
}}
for($taskI=0;$taskI -lt 20000;$taskI++){
    $taskBound=if($taskI -lt 10000){536870912L}else{2147483648L}
    $taskCases.Add(@([int]$taskRandom.NextInt64(-$taskBound,$taskBound),[int]$taskRandom.NextInt64(-$taskBound,$taskBound),[int]$taskRandom.NextInt64(-$taskBound,$taskBound),[int]$taskRandom.NextInt64(-$taskBound,$taskBound),[uint32]$taskRandom.NextInt64(0,4294967296L),[uint32]$taskRandom.NextInt64(0,4294967296L),[int]$taskRandom.NextInt64(-2147483648L,2147483648L),[int]$taskRandom.NextInt64(-2147483648L,2147483648L)))
}
try{
    foreach($taskCase in $taskCases){
        $taskReferenceError=$null;$taskCandidateError=$null;$taskExpected=$null;$taskActual=$null
        try{$taskExpected=Get-ReferenceWallUParameters @taskCase}catch{$taskCause=$_.Exception;while($taskCause.InnerException){$taskCause=$taskCause.InnerException};$taskReferenceError=$taskCause.GetType().FullName}
        try{$taskActual=Get-FastWallUParameters @taskCase -TanToAngle ([Trig]::tanToAngleTable) -FineSine ([Trig]::fineSine)}catch{$taskCause=$_.Exception;while($taskCause.InnerException){$taskCause=$taskCause.InnerException};$taskCandidateError=$taskCause.GetType().FullName}
        $taskCompared++
        $taskMatch=if($taskReferenceError -or $taskCandidateError){$taskReferenceError -eq $taskCandidateError}else{[Linq.Enumerable]::SequenceEqual[long]($taskExpected,$taskActual)}
        if($taskReferenceError -and $taskMatch){$taskErrorsMatched++}
        if(-not $taskMatch){$taskWrong++;if($taskExamples.Count -lt 8){$taskExamples.Add(@{Input=$taskCase;Expected=$taskExpected;Actual=$taskActual;ReferenceError=$taskReferenceError;CandidateError=$taskCandidateError})}}
    }
}catch{$taskFailure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    @{Error=$taskFailure;Compared=$taskCompared;Mismatches=$taskWrong;MatchedErrors=$taskErrorsMatched;Examples=$taskExamples.ToArray();Seed=20261002;RendererSha256=(Get-FileHash $Renderer).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;ReferenceGeometrySha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Doom/Math/Geometry.sb.ps1").Hash;Meaning='Actual numeric PowerShell wall segment parameters versus class-based pinned reference formula using legacy PointToAngle, Fixed and Trig. 49 coordinate edge fixtures plus20k seeded normal/full-range int32 coordinates, arbitrary uint32 angles and int32 offsets. Compare all three parameters and innermost exception type, unwrapping class invocation layers; matching errors are retained, not counted as rendered scenes. No original executable, coverage or pacing claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
if($taskFailure -or $taskWrong){throw "Wall U parameter comparison failed: $taskWrong mismatches."}
"PASS: $taskCompared wall parameter cases; $taskErrorsMatched matched errors."
