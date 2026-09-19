# SPDX-License-Identifier: GPL-2.0-or-later
# Shared numeric lighting setup for the host, simulation and render workers.
function New-FastLightingTables {
    # Doom's 320-wide view: 16 sector-light bands, 48 projected-scale bins,
    # and 128 distance bins. Store palette-map indices, not copied palettes.
    $scale=[int[][]]::new(16);$distance=[int[][]]::new(16)
    for($level=0;$level -lt 16;$level++){
        $scale[$level]=[int[]]::new(48);$distance[$level]=[int[]]::new(128)
        $start=4*(15-$level)
        for($i=0;$i -lt 48;$i++){$scale[$level][$i]=[Math]::Clamp($start-[int][Math]::Floor($i/2),0,31)}
        for($i=0;$i -lt 128;$i++){$distance[$level][$i]=[Math]::Clamp($start-[int][Math]::Floor(80.0/($i+1)),0,31)}
    }
    return @{Scale=$scale;Distance=$distance}
}

