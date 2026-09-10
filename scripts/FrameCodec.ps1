# PowerShell-only frame generation and terminal encoders. No dynamically compiled code.
Set-StrictMode -Version Latest

function New-TestPalette {
    param([ValidateSet(16,256)][int]$Count = 16)
    $palette = [int[][]]::new($Count)
    for ($i = 0; $i -lt $Count; $i++) {
        if ($Count -eq 16) {
            $palette[$i] = @((($i -band 1) * 170 + (($i -shr 3) * 85)), ((($i -shr 1) -band 1) * 170 + (($i -shr 3) * 85)), ((($i -shr 2) -band 1) * 170 + (($i -shr 3) * 85)))
        } else {
            $palette[$i] = @([int](($i -band 7) * 255 / 7), [int]((($i -shr 3) -band 7) * 255 / 7), [int]((($i -shr 6) -band 3) * 255 / 3))
        }
    }
    return ,$palette
}

function New-IndexedFrame {
    param([int]$Width, [int]$Height, [int]$Phase = 0,
        [ValidateSet('Coherent','Entropy')][string]$Pattern = 'Coherent', [int]$Colors = 16)
    if ($Width -lt 1 -or $Height -lt 1 -or $Colors -notin 16,256) { throw 'Invalid frame dimensions or palette.' }
    $pixels = [byte[]]::new($Width * $Height)
    for ($y = 0; $y -lt $Height; $y++) {
        $row = $y * $Width
        for ($x = 0; $x -lt $Width; $x++) {
            if ($Pattern -eq 'Entropy') {
                # Deterministic high-frequency texture, deliberately difficult for RLE.
                $value = (($x * 73 + $y * 151 + $Phase * 17) -bxor (($x * $y + 13) -shr 2)) % $Colors
            } else {
                # Coherent moving tiled image; synthetic, not a Doom renderer.
                $value = ((($x + $Phase * 3) -shr 4) + ($y -shr 3) * 3) % $Colors
                if (($y % 16) -eq 0 -or (($x + $Phase * 3 + (($y -shr 4) % 2) * 16) % 32) -eq 0) { $value = 0 }
            }
            $pixels[$row + $x] = [byte]$value
        }
    }
    return ,$pixels
}

function New-CodecContext {
    param([int[][]]$Palette)
    $count = $Palette.Length
    $pairs = [string[]]::new($count * $count)
    $esc = [char]27
    for ($top = 0; $top -lt $count; $top++) {
        for ($bottom = 0; $bottom -lt $count; $bottom++) {
            $t = $Palette[$top]; $b = $Palette[$bottom]
            $pairs[$top * $count + $bottom] = "$esc[38;2;$($t[0]);$($t[1]);$($t[2]);48;2;$($b[0]);$($b[1]);$($b[2])m"
        }
    }
    $defs = [Text.StringBuilder]::new()
    for ($i = 0; $i -lt $count; $i++) {
        $p = $Palette[$i]
        [void]$defs.Append("#$i;2;$([int]($p[0]*100/255));$([int]($p[1]*100/255));$([int]($p[2]*100/255))")
    }
    $cells = [string[]]::new($pairs.Length)
    for ($i=0; $i -lt $cells.Length; $i++) { $cells[$i] = $pairs[$i] + [char]0x2580 }
    return @{ Palette = $Palette; Count = $count; Pairs = $pairs; Cells = $cells; Definitions = $defs.ToString() }
}

function ConvertTo-AnsiFastFrame {
    param([byte[]]$Pixels, [int]$Width, [int]$Height, [hashtable]$Context)
    if ($Pixels.Length -ne $Width * $Height) { throw 'Pixel buffer length mismatch.' }
    [int]$count=$Context.Count
    [string[]]$cells=$Context.Cells
    [string]$block=[char]0x2580
    [string[]]$chunks=[string[]]::new(($Width+1)*[int][Math]::Ceiling($Height/2))
    [int]$n=0
    [int]$last=-1
    for ($y=0; $y -lt $Height; $y+=2) {
        if ($y -gt 0) { $chunks[$n++] = "$([char]27)[$([int]($y/2)+3);1H" }
        [int]$top=$y*$Width
        [int]$bottom=[Math]::Min($y+1,$Height-1)*$Width
        for ($x=0; $x -lt $Width; $x++) {
            [int]$pair=[int]$Pixels[$top+$x]*$count+[int]$Pixels[$bottom+$x]
            if ($pair -eq $last) { $chunks[$n++]=$block }
            else { $chunks[$n++]=$cells[$pair]; $last=$pair }
        }
    }
    return [string]::Concat($chunks)
}

function ConvertTo-AnsiFrame {
    param([byte[]]$Pixels, [int]$Width, [int]$Height, [hashtable]$Context)
    if ($Pixels.Length -ne $Width * $Height) { throw 'Pixel buffer length mismatch.' }
    $sb = [Text.StringBuilder]::new($Width * $Height * 10)
    $esc = [char]27
    $block = [char]0x2580
    $last = -1
    for ($y = 0; $y -lt $Height; $y += 2) {
        if ($y -gt 0) { [void]$sb.Append("$esc[$([int]($y/2)+3);1H") }
        $top = $y * $Width
        $bottom = [Math]::Min($y + 1, $Height - 1) * $Width
        for ($x = 0; $x -lt $Width; $x++) {
            $pair = [int]$Pixels[$top + $x] * $Context.Count + [int]$Pixels[$bottom + $x]
            if ($pair -ne $last) { [void]$sb.Append($Context.Pairs[$pair]); $last = $pair }
            [void]$sb.Append($block)
        }
    }
    return $sb.ToString()
}

function ConvertTo-SixelFrame {
    param([byte[]]$Pixels, [int]$Width, [int]$Height, [hashtable]$Context)
    if ($Pixels.Length -ne $Width * $Height) { throw 'Pixel buffer length mismatch.' }
    $esc = [char]27
    $sb = [Text.StringBuilder]::new($Width * $Height)
    [void]$sb.Append("${esc}P0;1;0q`"1;1;$Width;$Height")
    [void]$sb.Append($Context.Definitions)
    for ($band = 0; $band -lt $Height; $band += 6) {
        if ($band -gt 0) { [void]$sb.Append('-') }
        $masks = [byte[]]::new($Width * $Context.Count)
        $ends = [int[]]::new($Context.Count)
        [Array]::Fill($ends, -1)
        $bandHeight = [Math]::Min(6, $Height - $band)
        for ($dy = 0; $dy -lt $bandHeight; $dy++) {
            $row = ($band + $dy) * $Width
            $bit = 1 -shl $dy
            for ($x = 0; $x -lt $Width; $x++) {
                $color = [int]$Pixels[$row + $x]
                $idx = $color * $Width + $x
                $masks[$idx] = $masks[$idx] -bor $bit
                if ($x -gt $ends[$color]) { $ends[$color] = $x }
            }
        }
        $first = $true
        for ($color = 0; $color -lt $Context.Count; $color++) {
            if ($ends[$color] -lt 0) { continue }
            if (-not $first) { [void]$sb.Append('$') }
            $first = $false
            [void]$sb.Append('#').Append($color)
            $offset = $color * $Width
            $x = 0
            while ($x -le $ends[$color]) {
                $value = $masks[$offset + $x]
                $run = 1
                while (($x + $run) -le $ends[$color] -and $masks[$offset + $x + $run] -eq $value) { $run++ }
                $glyph = [char](63 + $value)
                if ($run -gt 3) { [void]$sb.Append('!').Append($run).Append($glyph) }
                else { [void]$sb.Append($glyph, $run) }
                $x += $run
            }
        }
    }
    [void]$sb.Append("$esc\")
    return $sb.ToString()
}

function Get-SampleStats {
    param([double[]]$Values)
    if ($Values.Length -eq 0) { return $null }
    $sorted = [double[]]$Values.Clone()
    [Array]::Sort($sorted)
    $sum = 0.0
    foreach ($v in $Values) { $sum += $v }
    return [ordered]@{ Count = $Values.Length; Mean = $sum / $Values.Length;
        Median = ($sorted[[int][Math]::Floor(($sorted.Length-1)/2)] + $sorted[[int][Math]::Ceiling(($sorted.Length-1)/2)]) / 2;
        P95 = $sorted[[Math]::Max(0, [int][Math]::Ceiling($sorted.Length * .95)-1)]; Max = $sorted[-1] }
}

function ConvertTo-SixelFastFrame {
    param([byte[]]$Pixels, [int]$Width, [int]$Height, [hashtable]$Context)
    if ($Pixels.Length -ne $Width * $Height) { throw 'Pixel buffer length mismatch.' }
    [int]$count=$Context.Count
    [int]$bands=[Math]::Ceiling($Height/6)
    [string[]]$chunks=[string[]]::new($bands*($count+1)+2)
    [int]$n=0
    $esc=[char]27
    $chunks[$n++]="${esc}P0;1;0q`"1;1;$Width;$Height"+$Context.Definitions
    for ($band=0;$band -lt $Height;$band+=6) {
        if($band -gt 0) { $chunks[$n++]='-' }
        [byte[]]$masks=[byte[]]::new($Width*$count)
        [Array]::Fill($masks,[byte]63)
        [int[]]$ends=[int[]]::new($count)
        [Array]::Fill($ends,-1)
        [int]$bandHeight=[Math]::Min(6,$Height-$band)
        for($dy=0;$dy -lt $bandHeight;$dy++) {
            [int]$row=($band+$dy)*$Width
            [int]$bit=1 -shl $dy
            for($x=0;$x -lt $Width;$x++) {
                [int]$color=$Pixels[$row+$x]
                [int]$idx=$color*$Width+$x
                # Each pixel contributes its bit exactly once, so addition is safe.
                $masks[$idx]+=$bit
                if($x -gt $ends[$color]) { $ends[$color]=$x }
            }
        }
        $first=$true
        for($color=0;$color -lt $count;$color++) {
            if($ends[$color] -lt 0) { continue }
            $prefix=if($first) { "#$color" } else { '$'+"#$color" }
            $first=$false
            # Bulk ASCII conversion; intentionally trades RLE compression for CPU time.
            $chunks[$n++]=$prefix+[Text.Encoding]::ASCII.GetString($masks,$color*$Width,$ends[$color]+1)
        }
    }
    $chunks[$n++]="$esc\"
    return [string]::Concat($chunks)
}
