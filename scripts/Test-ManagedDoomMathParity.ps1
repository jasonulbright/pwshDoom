#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop'
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$bundle=& (Join-Path $PSScriptRoot 'Build-EngineBundle.ps1') -Output (Join-Path $root 'local/math-parity-bundle.ps1')
. $bundle

function Get-ExpectedSlopeDiv([int]$Numerator,[int]$Denominator) {
    [long]$numUnsigned=[long]$Numerator -band 0xFFFFFFFFL
    [long]$denUnsigned=[long]$Denominator -band 0xFFFFFFFFL
    if($denUnsigned -lt 512){return 2048}
    [long]$wrappedNumerator=($numUnsigned -shl 3) -band 0xFFFFFFFFL
    [long]$remainder=0
    [long]$quotient=[Math]::DivRem($wrappedNumerator,($denUnsigned -shr 8),[ref]$remainder)
    return [Math]::Min(2048,$quotient)
}

$edgeCases=@(@(1,1280),@(1000,1280),@(-1,1280),@(2147483647,2147483647),@(-2147483648,512),@(123456789,-2147483648))
$random=[Random]::new(9272026)
$caseCount=0
foreach($pair in $edgeCases){
    $expected=Get-ExpectedSlopeDiv $pair[0] $pair[1]
    $actual=[Geometry]::SlopeDiv($pair[0],$pair[1])
    if($actual -ne $expected){throw "SlopeDiv edge case ($($pair[0]),$($pair[1])): expected $expected, got $actual."}
    $caseCount++
}
for($i=0;$i -lt 50000;$i++){
    $numerator=[int]$random.NextInt64(-2147483648L,2147483648L)
    $denominator=[int]$random.NextInt64(-2147483648L,2147483648L)
    $expected=Get-ExpectedSlopeDiv $numerator $denominator
    $actual=[Geometry]::SlopeDiv($numerator,$denominator)
    if($actual -ne $expected){throw "SlopeDiv case $i ($numerator,$denominator): expected $expected, got $actual."}
    $caseCount++
}

$bobStep=[int][Math]::Truncate([Trig]::FineAngleCount / 20)
[long]$remainder=0
$expectedDeathTurn=[Math]::DivRem([long][Angle]::Ang90.Data,18,[ref]$remainder)
$deathTurn=[Angle]::new([uint32]$expectedDeathTurn)
$negativeDeathTurn=-$deathTurn
$expectedNegative=[uint32](([long]0-$expectedDeathTurn)-band 0xFFFFFFFFL)
if($bobStep -ne 409){throw "Player bob angle step mismatch: $bobStep."}
if($deathTurn.Data -ne $expectedDeathTurn -or $negativeDeathTurn.Data -ne $expectedNegative){throw 'Player death turn does not match five degrees in binary-angle units.'}

$geometryPath=Join-Path $root 'src/ManagedDoom/Doom/Math/Geometry.sb.ps1'
$playerPath=Join-Path $root 'src/ManagedDoom/Doom/World/PlayerBehavior.sb.ps1'
$report=@{
    Format='pwshDoom.ManagedDoomMathParity';Version=1;FinishedUtc=[datetime]::UtcNow.ToString('o')
    SlopeDivCases=$caseCount;RandomSeed=9272026;BobAngleStep=$bobStep
    DeathTurnData=[long]$deathTurn.Data;NegativeDeathTurnData=[long]$negativeDeathTurn.Data
    GeometrySha256=(Get-FileHash $geometryPath).Hash;PlayerBehaviorSha256=(Get-FileHash $playerPath).Hash
    BundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash
    Meaning='Checks unsigned 32-bit C# SlopeDiv wrapping and integer division against a separate integer oracle over explicit boundary inputs and 50,000 deterministic random pairs; also checks the original player bob step and five-degree death turn constants.'
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Output))
$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $Output -Encoding utf8
"PASS: $caseCount SlopeDiv cases; bob step $bobStep; death turn $($deathTurn.Data)."
