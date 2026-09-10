#requires -Version 7.4
# Small independent decoder for the subset emitted by this study. Not a terminal emulator.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
function Read-SixelPixels([string]$Text,[int]$Width,[int]$Height) {
    $q=$Text.IndexOf('q')
    $body=$Text.Substring($q+1,$Text.Length-$q-3)
    $output=[int[]]::new($Width*$Height)
    [Array]::Fill($output,-1)
    $tokens=[regex]::Matches($body, '"[0-9;]+|#[0-9;]+|![0-9]+[?-~]|[?-~]|[$-]')
    $x=0;$y=0;$color=0
    foreach($match in $tokens) {
        $token=$match.Value
        if($token[0] -eq '"') { continue }
        if($token[0] -eq '#') { $color=[int]($token.Substring(1).Split(';')[0]);continue }
        if($token -eq '$') { $x=0;continue }
        if($token -eq '-') { $x=0;$y+=6;continue }
        $repeat=1
        if($token[0] -eq '!') { $repeat=[int]$token.Substring(1,$token.Length-2) }
        $mask=[int][char]$token[-1]-63
        for($r=0;$r -lt $repeat;$r++) {
            for($bit=0;$bit -lt 6;$bit++) {
                if(($mask -band (1 -shl $bit)) -ne 0) {
                    if($x -ge $Width -or $y+$bit -ge $Height) { throw 'Decoder found a painted out-of-bounds pixel.' }
                    $output[($y+$bit)*$Width+$x]=$color
                }
            }
            $x++
        }
    }
    return ,$output
}
$cases=0
foreach($colors in 16,256) {
    $ctx=New-CodecContext (New-TestPalette $colors)
    foreach($pattern in 'Coherent','Entropy') {
        foreach($size in @(@(17,13),@(160,100),@(320,200))) {
            $w,$h=$size
            $p=New-IndexedFrame $w $h 3 $pattern $colors
            foreach($encoder in 'Sixel','SixelFast') {
                $s=& "ConvertTo-${encoder}Frame" $p $w $h $ctx
                $decoded=Read-SixelPixels $s $w $h
                for($i=0;$i -lt $p.Length;$i++) { if($decoded[$i] -ne $p[$i]) { throw "Round-trip mismatch $encoder $pattern $colors ${w}x${h} pixel $i" } }
                $cases++
            }
        }
    }
}
Write-Host "PASS: $cases Sixel round-trips, every pixel checked; includes 16/256 colors, odd sizes and both textures."
