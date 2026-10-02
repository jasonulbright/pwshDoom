#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath("$PSScriptRoot/..");$taskRuntimeVersion=$PSVersionTable.PSVersion.ToString()
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report.'}
$taskOwned=Join-Path "$taskRoot/local" ("discovery-slope-test-"+[guid]::NewGuid().ToString("N"))
if(Test-Path -LiteralPath $taskOwned){throw 'Use a fresh owned directory.'}
[void][IO.Directory]::CreateDirectory($taskOwned)
$taskBundle=& "$taskRoot/scripts/Build-EngineBundle.ps1" -Output "$taskOwned/current.ps1"
. $taskBundle;. "$taskRoot/scripts/fixtures/DiscoveryAngleReference.ps1";. "$taskRoot/scripts/FrameCodec.ps1"
$taskFailure=$null;$taskAngleCases=0;$taskExceptions=0;$taskQuotientCases=0;$taskProfiles=[Collections.Generic.List[object]]::new()
try{
    $taskRandom=[Random]::new(20261002)
    $taskPoints=[Collections.Generic.List[int[]]]::new()
    for($taskI=0;$taskI -lt 20000;$taskI++){$taskPoints.Add(@([int]$taskRandom.NextInt64(-2147483648L,2147483648L),[int]$taskRandom.NextInt64(-2147483648L,2147483648L),[int]$taskRandom.NextInt64(-2147483648L,2147483648L),[int]$taskRandom.NextInt64(-2147483648L,2147483648L)))}
    foreach($taskX in -2147483648,-1073741825,-1073741824,-1073741823,-536870913,-536870912,-536870911,-65536,-513,-512,-511,-1,0,1,511,512,513,65536,536870911,536870912,536870913,1073741823,1073741824,1073741825,2147483647){
        foreach($taskY in -2147483648,-536870913,-536870912,-65536,-513,-512,-511,-1,0,1,511,512,513,65536,536870911,536870912,536870913,2147483647){$taskPoints.Add(@(0,0,$taskX,$taskY));$taskPoints.Add(@(2147483647,-2147483648,$taskX,$taskY))}
    }
    foreach($taskPoint in $taskPoints){
        $taskExpectedError=$false;$taskActualError=$false;$taskExpected=0L;$taskActual=0L
        try{$taskExpected=[DiscoveryAngleReference]::PointToAngleData($taskPoint[0],$taskPoint[1],$taskPoint[2],$taskPoint[3])}catch{$taskExpectedError=$true}
        try{$taskActual=[Geometry]::PointToAngleData($taskPoint[0],$taskPoint[1],$taskPoint[2],$taskPoint[3])}catch{$taskActualError=$true}
        if($taskExpectedError -ne $taskActualError -or (-not $taskActualError -and $taskExpected -ne $taskActual)){throw "Angle/error mismatch at$($taskPoint -join ',')"}
        $taskAngleCases++;if($taskActualError){$taskExceptions++}
    }
    # The candidate's wrapped numerator is uint32 and divisor is2..8388607.
    # Double division cannot round a noninteger to an integer in this domain:
    # half-ulp/(minimum1/divisor fraction) is less than2^-20.
    $taskDivisors=@(2,3,4,7,8,255,256,257,511,512,513,65535,65536,65537,4194303,4194304,4194305,8388606,8388607)
    foreach($taskDivisor in $taskDivisors){
        $taskNumerators=@(0,1,2,7,8,511,512,513,2147483647L,2147483648L,4294967288L,4294967295L)
        foreach($taskQ in 1,2,2047,2048,2049,65535){
            foreach($taskOffset in -1,0,1){$taskN=[long]$taskDivisor*$taskQ+$taskOffset;if($taskN -ge 0 -and $taskN -le 4294967295L){$taskNumerators+=,$taskN}}
        }
        foreach($taskNumerator in $taskNumerators){
            $taskRemainder=0L;$taskExpectedQ=[Math]::DivRem([long]$taskNumerator,[long]$taskDivisor,[ref]$taskRemainder)
            $taskActualQ=[long][Math]::Truncate([double]$taskNumerator/$taskDivisor)
            if($taskActualQ -ne $taskExpectedQ){throw 'Boundary quotient differs.'};$taskQuotientCases++
        }
    }
    for($taskI=0;$taskI -lt 20000;$taskI++){
        $taskN=$taskRandom.NextInt64(0,4294967296L);$taskD=$taskRandom.NextInt64(2,8388608L);$taskRemainder=0L
        if([long][Math]::Truncate([double]$taskN/$taskD) -ne [Math]::DivRem($taskN,$taskD,[ref]$taskRemainder)){throw 'Random quotient differs.'};$taskQuotientCases++
    }
    # Fixed ordinary-sized coordinates, identical points in all warm batches.
    $taskTimingPoints=[Collections.Generic.List[int[]]]::new()
    for($taskI=0;$taskI -lt 256;$taskI++){$taskTimingPoints.Add(@(($taskRandom.Next(-10000,10001)*65536),($taskRandom.Next(-10000,10001)*65536),($taskRandom.Next(-10000,10001)*65536),($taskRandom.Next(-10000,10001)*65536)))}
    $taskWatch=[Diagnostics.Stopwatch]::new()
    for($taskCycle=1;$taskCycle -le 3;$taskCycle++){
        for($taskPosition=1;$taskPosition -le 4;$taskPosition++){
            $taskCandidate=$taskPosition -in 2,3;$taskSamples=[Collections.Generic.List[double]]::new();$taskWarmups=[Collections.Generic.List[double]]::new();$taskAnswers=[long[]]::new(256)
            for($taskBatch=0;$taskBatch -lt 23;$taskBatch++){
                $taskWatch.Restart()
                for($taskI=0;$taskI -lt $taskTimingPoints.Count;$taskI++){
                    $taskP=$taskTimingPoints[$taskI]
                    $taskAnswers[$taskI]=if($taskCandidate){[Geometry]::PointToAngleData($taskP[0],$taskP[1],$taskP[2],$taskP[3])}else{[DiscoveryAngleReference]::PointToAngleData($taskP[0],$taskP[1],$taskP[2],$taskP[3])}
                }
                if($taskBatch -lt 3){$taskWarmups.Add($taskWatch.Elapsed.TotalMilliseconds)}else{$taskSamples.Add($taskWatch.Elapsed.TotalMilliseconds)}
            }
            $taskBytes=[byte[]]::new($taskAnswers.Length*8);[Buffer]::BlockCopy($taskAnswers,0,$taskBytes,0,$taskBytes.Length)
            $taskProfiles.Add(@{Cycle=$taskCycle;Position=$taskPosition;Kind=if($taskCandidate){'Candidate'}else{'Baseline'};CallsPerBatch=256;WarmupSamplesMs=$taskWarmups.ToArray();SamplesMs=$taskSamples.ToArray();Stats=(Get-SampleStats $taskSamples.ToArray());AnswerSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($taskBytes))})
        }
    }
    if(@($taskProfiles.AnswerSha256|Select-Object -Unique).Count -ne 1){throw 'Timed answer hashes differ.'}
}catch{$taskFailure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    @{Error=$taskFailure;FinishedUtc=[DateTime]::UtcNow.ToString('o');Runtime=$taskRuntimeVersion;AngleCases=$taskAngleCases;MatchingAngleExceptions=$taskExceptions;QuotientCases=$taskQuotientCases;PointSeed=20261002;Profiles=$taskProfiles.ToArray();Files=@(foreach($taskFile in $PSCommandPath,"$taskRoot/scripts/fixtures/DiscoveryAngleReference.ps1","$taskRoot/src/ManagedDoom/Doom/Math/Geometry.sb.ps1",$taskBundle){@{Path=$taskFile;Sha256=(Get-FileHash $taskFile).Hash}});Meaning='Production pure-PowerShell numeric discovery slope checks against the retained previous method; general SlopeDiv and legacy PointToAngle stay unchanged. Signed-coordinate wrap, uint32 numerator wrap, octants, table and int32-minimum/error fallback preserved. Full previous-numeric answer/error equality plus floor-vs-DivRem domain checks, then3 warm256-call ABBA cycles. First3 batches retained separately,20 timed batches/slot. Validation precedes timing; answers hashed outside timing. This is a method microbenchmark, not native/full-host pacing, mapped-line qualification or a full release qualification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
if($taskFailure){throw $taskFailure}
"PASS:$taskAngleCases previous-numeric angle/error comparisons;$taskQuotientCases integer quotient checks;3 ABBA cycles."
