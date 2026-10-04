# SPDX-License-Identifier: GPL-2.0-or-later
# PLAYPAL colors are presentation state, separate from indexed-pixel colormaps.
function Get-DoomGammaExponent {
    param([ValidateRange(0,10)][int]$GammaLevel=0)
    $parameters=[double[]]@(1.00,0.95,0.90,0.85,0.80,0.75,0.70,0.65,0.60,0.55,0.50)
    return $parameters[$GammaLevel]
}
function Get-DoomPaletteRgb {
    param([byte[]]$Data,[int]$Number,[ValidateRange(0,10)][int]$GammaLevel=0)
    if($Data.Length -lt 768 -or $Data.Length%768 -or $Number -lt 0 -or $Number -ge $Data.Length/768){throw 'Invalid PLAYPAL palette.'}
    $palette=[int[][]]::new(256);$offset=$Number*768
    $exponent=Get-DoomGammaExponent $GammaLevel
    for($i=0;$i -lt 256;$i++){
        $palette[$i]=@([int]$Data[$offset+3*$i],[int]$Data[$offset+3*$i+1],[int]$Data[$offset+3*$i+2])
        if($GammaLevel -gt 0){for($channel=0;$channel -lt 3;$channel++){$palette[$i][$channel]=[int][Math]::Round(255*[Math]::Pow($palette[$i][$channel]/255.0,$exponent))}}
    }
    return ,$palette
}
function Get-DoomPaletteBytes {
    param([byte[]]$Data,[int]$Number,[ValidateRange(0,10)][int]$GammaLevel=0)
    $rgb=Get-DoomPaletteRgb $Data $Number -GammaLevel $GammaLevel
    $bytes=[byte[]]::new(768)
    for($i=0;$i -lt 256;$i++){for($channel=0;$channel -lt 3;$channel++){$bytes[3*$i+$channel]=[byte]$rgb[$i][$channel]}}
    return ,$bytes
}
function New-DoomPaletteCodecs {
    param([byte[]]$Data,[ValidateSet('Classic','Matrix','AnsiArt')][string]$Style,
        [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Ascii',
        [ValidateSet('Pairs','ColorState','Ansi256')][string]$AnsiEncoding='Pairs',
        [ValidateRange(0,10)][int]$GammaLevel=0)
    if($Data.Length -lt 14*768 -or $Data.Length%768){throw 'PLAYPAL must contain the fourteen Doom palettes.'}
    # Only vanilla selection indices 0..13 are used. All small style tables are
    # prepared before ready; pair strings are populated on demand in each worker.
    $codecs=[object[]]::new(14)
    for($number=0;$number -lt 14;$number++){
        $rgb=Get-DoomPaletteRgb $Data $number -GammaLevel $GammaLevel
        $codecs[$number]=if($Style -eq 'Classic'){
            if($AnsiEncoding -eq 'ColorState'){New-AnsiColorStateContext $rgb -LazyCells}
            elseif($AnsiEncoding -eq 'Ansi256'){New-Ansi256Context $rgb}
            else{New-CodecContext $rgb -LazyCells}
        }else{New-CharacterCodecContext $rgb $Style -GlyphSet $GlyphSet -LazyCells}
    }
    return ,$codecs
}
