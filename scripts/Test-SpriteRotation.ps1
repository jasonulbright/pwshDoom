#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Output="$PSScriptRoot/../local/sprite-rotation-parity.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh sprite-rotation report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"

$table=[uint32[]][Trig]::tanToAngleTable
$tableBytes=[byte[]]::new($table.Length*4);[Buffer]::BlockCopy($table,0,$tableBytes,0,$tableBytes.Length)
$sourcePaths=@('scripts/Test-SpriteRotation.ps1','src/FastRenderer.ps1','src/SpriteProjection.ps1','src/RenderAssets.ps1',
    'src/ManagedDoom/Doom/Math/Geometry.sb.ps1','src/ManagedDoom/Doom/Math/Trig.ps1',
    'scripts/Build-EngineBundle.ps1')
$sources=@($sourcePaths|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}})
$pointCases=0;$pointMismatches=0;$boundaryCases=0;$rotationMismatches=0;$legacyMismatches=0
$turn=4294967296.0;$angleScale=2*[Math]::PI/$turn;$bucket=0x20000000L;$angleOffset=9*[Math]::PI/8
$referenceOffset=[uint64]([uint32](([Angle]::Ang45.Data/2)*9));$denominator=524288
for($octant=0;$octant -lt 8;$octant++){
    for($slope=0;$slope -le 2048;$slope++){
        $numerator=$slope*256
        if($octant -in 0,3,4,7){$x=$denominator;$y=$numerator}else{$x=$numerator;$y=$denominator}
        if($octant -in 2,3,4,5){$x=-$x}
        if($octant -in 4,5,6,7){$y=-$y}
        [long]$referenceAngle=[Geometry]::PointToAngleData(0,0,$x,$y)
        [long]$candidateAngle=Get-FastPointAngleData 0 0 $x $y $table
        $pointCases++;if($candidateAngle -ne $referenceAngle){$pointMismatches++}
        $atan=[Math]::Atan2([double]$y,[double]$x)
        for($sector=0;$sector -lt 8;$sector++){
            $boundary=([long]$referenceAngle+[long]$referenceOffset-([long]$sector*$bucket))%0x100000000L
            if($boundary -lt 0){$boundary+=0x100000000L}
            foreach($offset in -1,0,1){
                $actorAngleData=($boundary+$offset+0x100000000L)%0x100000000L
                $actorAngleRadians=$actorAngleData*$angleScale
                $expectedRotation=([uint64]$referenceAngle+[uint64]$referenceOffset+0x100000000L-$actorAngleData)%0x100000000L
                $expectedRotation=[int]($expectedRotation -shr 29)
                $candidateRotation=Get-FastSpriteRotation 0 0 $x $y $actorAngleRadians $table
                $boundaryCases++;if($candidateRotation -ne $expectedRotation){$rotationMismatches++}
                $legacyAngle=$atan-$actorAngleRadians+$angleOffset
                $legacyAngle=($legacyAngle%(2*[Math]::PI)+2*[Math]::PI)%(2*[Math]::PI)
                $legacyRotation=[int][Math]::Floor($legacyAngle/([Math]::PI/4))
                if($legacyRotation -ne $expectedRotation){$legacyMismatches++}
            }
        }
    }
}

$edgeCases=@(
    @(0,0,-2147483648,0),@(0,0,0,-2147483648),
    @(0,0,-2147483648,1),@(0,0,1,-2147483648),
    @(2147483647,0,-1,0),@(0,2147483647,0,-1)
)
$edgeMismatches=0
foreach($p in $edgeCases){
    $reference=[Geometry]::PointToAngleData([int]$p[0],[int]$p[1],[int]$p[2],[int]$p[3])
    $candidate=Get-FastPointAngleData ([int]$p[0]) ([int]$p[1]) ([int]$p[2]) ([int]$p[3]) $table
    if($candidate -ne $reference){$edgeMismatches++}
}

$random=[Random]::new(911);$angleRoundTrips=0
for($i=0;$i -lt 100000;$i++){
    [uint32]$raw=[uint32]$random.NextInt64(0,4294967296)
    $radians=$raw*$angleScale
    [uint32]$roundTrip=[uint32][Math]::Round($radians*($turn/(2*[Math]::PI)))
    if($roundTrip -ne $raw){$angleRoundTrips++}
}

$report=[ordered]@{
    Format='pwshDoom.SpriteRotationParity'
    FinishedUtc=[DateTime]::UtcNow.ToString('o')
    PowerShell=$PSVersionTable.PSVersion.ToString()
    TanToAngleEntries=$table.Length
    TanToAngleTableSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($tableBytes))
    DirectionCases=$pointCases
    PointAngleMismatches=$pointMismatches
    BoundaryRotationCases=$boundaryCases
    FixedRotationMismatches=$rotationMismatches
    LegacyAtan2BoundaryMismatches=$legacyMismatches
    IntMinEdgeCases=$edgeCases.Count
    IntMinEdgeMismatches=$edgeMismatches
    AngleDataRoundTrips=100000
    AngleDataRoundTripMismatches=$angleRoundTrips
    Sources=$sources
    Meaning='Exhaustive slope-table directions across eight octants, every angle-sector boundary at -1/0/+1 binary-angle units, and signed-int-minimum point differences. Fixed rotation is compared with the adopted Geometry.PointToAngleData and ThreeDRenderer unsigned sprite-frame selection. LegacyAtan2BoundaryMismatches replays the prior floating expression on the same boundary fixtures. Synthetic math conformance only; not actor image, animation, occlusion, gameplay, or original-executable evidence.'
}
if($pointMismatches -or $rotationMismatches -or $edgeMismatches -or $angleRoundTrips){throw 'Fixed sprite-rotation parity failed.'}
$resolved=[IO.Path]::GetFullPath($Output);[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolved))
$report|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $resolved
"PASS: $pointCases directions, $boundaryCases rotation boundaries, $($edgeCases.Count) int-min edges, and 100000 angle round trips; legacy Atan2 boundary mismatches: $legacyMismatches."
