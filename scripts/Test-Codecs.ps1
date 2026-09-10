#requires -Version 7.4
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$ctx=New-CodecContext (New-TestPalette 16)
$esc=[char]27
$pixels=[byte[]]@(0,1,1,0)
$ansi=ConvertTo-AnsiFrame $pixels 2 2 $ctx
$expected=$ctx.Pairs[1]+[char]0x2580+$ctx.Pairs[16]+[char]0x2580
if ($ansi -cne $expected) { throw 'ANSI 2x2 diagonal mapping failed.' }
$sixel=ConvertTo-SixelFrame $pixels 2 2 $ctx
if (-not $sixel.EndsWith('#0@A$#1A@'+$esc+'\')) { throw 'Sixel 2x2 diagonal mapping failed.' }
$solid=ConvertTo-SixelFrame ([byte[]]::new(8*7)) 8 7 $ctx
if (-not $solid.EndsWith('#0!8~-#0!8@'+$esc+'\')) { throw 'Sixel six-row band / partial-band RLE failed.' }
$odd=ConvertTo-AnsiFrame ([byte[]]@(0,1,2)) 1 3 $ctx
if (-not $odd.Contains($esc+'[4;1H'+$ctx.Pairs[34])) { throw 'ANSI odd-height replication failed.' }
$threw=$false
try { $null=ConvertTo-SixelFrame ([byte[]]@(0)) 2 2 $ctx } catch { $threw=$true }
if (-not $threw) { throw 'Buffer length validation failed.' }
Write-Host 'PASS: ANSI pixel pairing, odd height, Sixel palette masks, RLE, partial bands, buffer validation.'
