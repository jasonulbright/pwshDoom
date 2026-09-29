# SPDX-License-Identifier: GPL-2.0-or-later
# Optional xterm 256-color approximation for the Classic indexed framebuffer.
# Gameplay pixels and all mapping/encoding logic remain in PowerShell.
$script:Xterm256Palette = $null

function Get-Xterm256Palette {
    if ($null -ne $script:Xterm256Palette) { return ,$script:Xterm256Palette }
    [int[][]]$colors = [int[][]]::new(256)
    # xterm's extended 6x6x6 cube and 24-step grayscale ramp.
    [int[]]$levels = @(0,95,135,175,215,255)
    for ([int]$r=0; $r -lt 6; $r++) {
        for ([int]$g=0; $g -lt 6; $g++) {
            for ([int]$b=0; $b -lt 6; $b++) {
                $colors[16+36*$r+6*$g+$b] = @($levels[$r],$levels[$g],$levels[$b])
            }
        }
    }
    for ([int]$i=0; $i -lt 24; $i++) {
        [int]$value = 8+10*$i
        $colors[232+$i] = @($value,$value,$value)
    }
    $script:Xterm256Palette = $colors
    return ,$script:Xterm256Palette
}

function New-Ansi256Context {
    param([int[][]]$Palette)
    if ($Palette.Length -ne 256) { throw 'ANSI 256 mode requires the 256-entry Doom PLAYPAL.' }
    [int[][]]$terminalPalette = Get-Xterm256Palette
    [int[]]$mapping = [int[]]::new(256)
    for ([int]$i=0; $i -lt 256; $i++) {
        [int]$bestDistance = [int]::MaxValue
        for ([int]$j=16; $j -lt 256; $j++) {
            [int]$dr = $Palette[$i][0]-$terminalPalette[$j][0]
            [int]$dg = $Palette[$i][1]-$terminalPalette[$j][1]
            [int]$db = $Palette[$i][2]-$terminalPalette[$j][2]
            [int]$distance = $dr*$dr+$dg*$dg+$db*$db
            if ($distance -lt $bestDistance) { $bestDistance=$distance; $mapping[$i]=$j }
        }
    }
    [string[]]$topPrefixes = [string[]]::new(256)
    [string[]]$bottomSuffixes = [string[]]::new(256)
    [string]$escape = [char]27
    for ([int]$i=0; $i -lt 256; $i++) {
        [int]$index = $mapping[$i]
        $topPrefixes[$i] = "$escape[38;5;$index"
        $bottomSuffixes[$i] = ";48;5;$index`m$([char]0x2580)"
    }
    return @{
        Mode='Ansi256Approximate'; Palette=$Palette; TerminalPalette=$terminalPalette
        Mapping=$mapping; Count=256; Cells=[string[]]::new(65536)
        TopPrefixes=$topPrefixes; BottomSuffixes=$bottomSuffixes
    }
}
