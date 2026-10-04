#requires -Version 7.4
$ErrorActionPreference='Stop'
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"

$tables=Get-FastPlaneTables
$clip=[uint32]$tables.ColumnAngles[0]
$tanto=[uint32[]]$tables.TanToAngle
$angleToX=[int[]]$tables.AngleToX
$unit=65536
$range=[int[]]::new(2)
function Assert-Range([string]$Name,[int[]]$Expected,[int]$X1,[int]$Y1,[int]$X2,[int]$Y2,[uint32]$ViewAngleData=0){
    $visible=Get-FastWallScreenRange 0 0 ($X1*$unit) ($Y1*$unit) ($X2*$unit) ($Y2*$unit) $ViewAngleData $clip $tanto $angleToX $range
    if(-not $visible -or $range[0] -ne $Expected[0] -or $range[1] -ne $Expected[1]){
        throw "$($Name): expected [$($Expected -join ',')], got [$($range -join ',')]."
    }
}
function Assert-Offscreen([string]$Name,[int]$X1,[int]$Y1,[int]$X2,[int]$Y2,[uint32]$ViewAngleData=0){
    $visible=Get-FastWallScreenRange 0 0 ($X1*$unit) ($Y1*$unit) ($X2*$unit) ($Y2*$unit) $ViewAngleData $clip $tanto $angleToX $range
    if($visible){throw "$($Name): expected no visible columns, got [$($range -join ',')]."}
}

if($angleToX.Length -ne 4096 -or $angleToX[3073] -ne 0 -or $angleToX[1024] -ne 320){
    throw 'The Doom viewangletox fenceposts do not map the 90-degree viewport to [0,320].'
}
Assert-Range 'Segment at nominal field-of-view edges' @(1,320) 100 100 100 -100
Assert-Range 'Both endpoints clipped to the viewport' @(0,320) 100 173 100 -173
Assert-Range 'Segment clipped at the left edge' @(0,160) 100 173 100 0
Assert-Range 'Segment clipped at the right edge' @(160,320) 100 0 100 -173
Assert-Offscreen 'Segment fully outside the left edge' 100 173 100 143
Assert-Offscreen 'Back-facing segment' 100 -100 100 100
Assert-Range '90-degree view at nominal field-of-view edges' @(1,320) -100 100 100 100 ([uint32]0x40000000)
Assert-Range '90-degree view clips both viewport edges' @(0,320) -173 100 173 100 ([uint32]0x40000000)
Assert-Range '90-degree view clips at the ANG90-minus-one fencepost' @(0,161) -173 100 0 100 ([uint32]0x40000000)
Assert-Range '90-degree view clips the right edge from column 161' @(161,320) 0 100 173 100 ([uint32]0x40000000)
Assert-Offscreen '90-degree view rejects the reversed wall' 100 100 -100 100 ([uint32]0x40000000)
Assert-Range '180-degree view at nominal field-of-view edges' @(1,320) -100 -100 -100 100 ([uint32]0x80000000L)
Assert-Range '180-degree view clips both viewport edges' @(0,320) -100 -173 -100 173 ([uint32]0x80000000L)
Assert-Offscreen '180-degree view rejects the reversed wall' -100 100 -100 -100 ([uint32]0x80000000L)
Assert-Range '270-degree view at nominal field-of-view edges' @(1,320) 100 -100 -100 -100 ([uint32]0xC0000000L)
Assert-Range '270-degree view clips both viewport edges' @(0,320) 173 -100 -173 -100 ([uint32]0xC0000000L)
Assert-Offscreen '270-degree view rejects the reversed wall' -100 -100 100 -100 ([uint32]0xC0000000L)

'Wall screen-projection cases passed.'
