#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$OutputRoot)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceRoot=Join-Path $repo 'src'
$outputRoot=[IO.Path]::GetFullPath($OutputRoot)
$relative=[IO.Path]::GetRelativePath($repo,$outputRoot)
if([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")){
    throw 'Diagnostic renderer must remain inside the project.'
}
if(Test-Path -LiteralPath $outputRoot){throw 'Use a fresh diagnostic renderer directory.'}
[void][IO.Directory]::CreateDirectory($outputRoot)
foreach($name in @('FastRenderer.ps1','RenderLighting.ps1','RenderFuzz.ps1','SpriteProjection.ps1')){
    Copy-Item -LiteralPath (Join-Path $sourceRoot $name) -Destination (Join-Path $outputRoot $name)
}

$renderer=Join-Path $outputRoot 'FastRenderer.ps1'
$source=[IO.File]::ReadAllText($renderer)
$startMarker='[int]$u=($xFrac -shr 16) -band 63;[int]$v=($yFrac -shr 10) -band 4032'
if($source.IndexOf($startMarker,[StringComparison]::Ordinal) -lt 0 -or
    $source.LastIndexOf($startMarker,[StringComparison]::Ordinal) -ne $source.IndexOf($startMarker,[StringComparison]::Ordinal)){
    throw 'Expected exactly one horizontal plane sample loop.'
}
$start=$source.IndexOf($startMarker,[StringComparison]::Ordinal)
$end=$source.IndexOf('$x++',$start,[StringComparison]::Ordinal)
if($end -lt 0){throw 'Horizontal plane sample loop end not found.'}
$lineEnd=$source.IndexOf("`n",$end,[StringComparison]::Ordinal)
if($lineEnd -lt 0){throw 'Horizontal plane sample line end not found.'}
$nl=[Environment]::NewLine
$replacement=@'
[int]$directLengthData=([long]$distanceData*[long]$Context.PlaneDistanceScales[$x]) -shr 16
                [long]$directXFracWide=[long]$viewXData+(([long]$rayCos[$x]*[long]$directLengthData) -shr 16)
                [long]$directYFracWide=-[long]$viewYData-(([long]$raySin[$x]*[long]$directLengthData) -shr 16)
                [int]$u=($directXFracWide -shr 16) -band 63;[int]$v=($directYFracWide -shr 10) -band 4032
                [int]$p=$row+$x
                $pixels[$p]=$colors[$flatData[$v+$u]]
                $x++
'@
$replacement=$replacement.Trim([char]13,[char]10).Replace("`n",$nl)+$nl
$source=$source.Substring(0,$start)+$replacement+$source.Substring($lineEnd+1)
[IO.File]::WriteAllText($renderer,$source,[Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    OutputRoot=$outputRoot
    Renderer=[IO.Path]::GetRelativePath($repo,$renderer).Replace('\','/')
    RendererSha256=(Get-FileHash -LiteralPath $renderer).Hash
    Variant='Experimental direct fixed-point plane sample for every pixel; production source is untouched.'
}
