#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Output,[ValidateRange(1,100000)][int]$RandomCases=50000,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh sight-bounds report.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/sight-bounds-$PID.ps1"
$source=[IO.File]::ReadAllText($bundle)
$marker='$this.BottomSlope.Data = $bottomSlopeData'
if([regex]::Matches($source,[regex]::Escape($marker)).Count -ne 1){throw 'Could not isolate the production sight-bound initialization.'}
# Stop the owned test bundle immediately after production initialization so
# randomized bound checks do not traverse or mutate a map's BSP line markers.
$source=$source.Replace($marker,$marker+"`r`n        return `$true")
[IO.File]::WriteAllText($bundle,$source,[Text.UTF8Encoding]::new($false))
. $bundle
$content=$null;$failure=$null;$cases=0;$mismatchTotal=0;$mismatches=[Collections.Generic.List[object]]::new()
function New-RawFixedData([Random]$Random){return [Fixed]::ToInt32Unchecked($Random.NextInt64(0L,4294967296L))}
try{
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$game.InitNew([GameSkill]::Medium,1,1)
    $bytes=[byte[]]::new([math]::Ceiling($game.World.Map.Sectors.Count*$game.World.Map.Sectors.Count/8.0))
    $game.World.Map.Reject=[Reject]::new($bytes,$game.World.Map.Sectors.Count)
    $subsector=$game.World.Map.Subsectors[0]
    $looker=[Mobj]::new($game.World);$target=[Mobj]::new($game.World)
    $looker.Subsector=$subsector;$target.Subsector=$subsector
    $check=[VisibilityCheck]::new($game.World);$random=[Random]::new(20260927)
    $edge=[int[]]@([int]::MinValue,([int]::MinValue+1),-65537,-65536,-1,0,1,65535,65536,65537,([int]::MaxValue-1),[int]::MaxValue)
    $vectors=[Collections.Generic.List[int[]]]::new()
    for($i=0;$i -lt 200;$i++){$vectors.Add([int[]]@($edge[$random.Next($edge.Count)],$edge[$random.Next($edge.Count)],$edge[$random.Next($edge.Count)],$edge[$random.Next($edge.Count)]))}
    for($i=0;$i -lt $RandomCases;$i++){
        $vectors.Add([int[]]@((New-RawFixedData $random),(New-RawFixedData $random),(New-RawFixedData $random),(New-RawFixedData $random)))
    }
    foreach($values in $vectors){
        $looker.Z=[Fixed]::new($values[0]);$looker.Height=[Fixed]::new($values[1])
        $target.Z=[Fixed]::new($values[2]);$target.Height=[Fixed]::new($values[3])
        $expectedSight=$looker.Z+$looker.Height-($looker.Height -shr 2)
        $expectedTop=($target.Z+$target.Height)-$expectedSight
        $expectedBottom=$target.Z-$expectedSight
        if(-not $check.CheckSight($looker,$target)){throw 'Same-sector sight initialization unexpectedly rejected the target.'}
        if($check.SightZStart.Data -ne $expectedSight.Data -or $check.TopSlope.Data -ne $expectedTop.Data -or $check.BottomSlope.Data -ne $expectedBottom.Data){
            $mismatchTotal++
            if($mismatches.Count -lt 8){$mismatches.Add(@{Case=$cases;Input=$values;Expected=@($expectedSight.Data,$expectedTop.Data,$expectedBottom.Data);Actual=@($check.SightZStart.Data,$check.TopSlope.Data,$check.BottomSlope.Data)})}
        }
        $cases++
    }
    if($mismatchTotal){throw "Sight bounds differ from the previous Fixed expression in $mismatchTotal sampled cases."}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Passed=($null -eq $failure -and $cases -eq ($RandomCases+200) -and $mismatchTotal -eq 0);
        BoundaryCases=200;RandomCases=$RandomCases;RandomSeed=20260927;Cases=$cases;MismatchCount=$mismatchTotal;MismatchSamples=$mismatches.ToArray();
        WADSha256=(Get-FileHash -LiteralPath $Wad).Hash;
        SourceSha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Doom/World/VisibilityCheck.sb.ps1").Hash;
        BundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        Meaning='Calls the production CheckSight initialization in an owned bundle that returns before BSP traversal, then compares sight Z and both slopes against the prior Fixed operators. Same-sector reject data is zeroed for the fixture; this tests arithmetic, not map visibility or campaign behavior.'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $Output
}
if($failure){throw $failure}
"PASS: $cases production CheckSight bound cases ($($RandomCases) deterministic raw inputs plus 200 boundaries)."
