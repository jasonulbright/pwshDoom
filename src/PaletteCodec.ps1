# SPDX-License-Identifier: GPL-2.0-or-later
# PLAYPAL colors are presentation state, separate from indexed-pixel colormaps.
function Get-DoomPaletteRgb {
    param([byte[]]$Data,[int]$Number)
    if($Data.Length -lt 768 -or $Data.Length%768 -or $Number -lt 0 -or $Number -ge $Data.Length/768){throw 'Invalid PLAYPAL palette.'}
    $palette=[int[][]]::new(256);$offset=$Number*768
    for($i=0;$i -lt 256;$i++){$palette[$i]=@([int]$Data[$offset+3*$i],[int]$Data[$offset+3*$i+1],[int]$Data[$offset+3*$i+2])}
    return ,$palette
}
function New-DoomPaletteCodecs {
    param([byte[]]$Data,[ValidateSet('Classic','Matrix','AnsiArt')][string]$Style,
        [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Ascii',
        [ValidateSet('Pairs','ColorState')][string]$AnsiEncoding='Pairs')
    if($Data.Length -lt 14*768 -or $Data.Length%768){throw 'PLAYPAL must contain the fourteen Doom palettes.'}
    # Only vanilla selection indices 0..13 are used. All small style tables are
    # prepared before ready; pair strings are populated on demand in each worker.
    $codecs=[object[]]::new(14)
    for($number=0;$number -lt 14;$number++){
        $rgb=Get-DoomPaletteRgb $Data $number
        $codecs[$number]=if($Style -eq 'Classic'){
            if($AnsiEncoding -eq 'ColorState'){New-AnsiColorStateContext $rgb -LazyCells}
            else{New-CodecContext $rgb -LazyCells}
        }else{New-CharacterCodecContext $rgb $Style -GlyphSet $GlyphSet -LazyCells}
    }
    return ,$codecs
}
