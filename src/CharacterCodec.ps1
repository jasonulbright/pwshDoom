# SPDX-License-Identifier: GPL-2.0-or-later
# PowerShell image-to-character encoding. Source pixels are never modified.
function ConvertTo-MenuStrip {
    param([byte[]]$Pixels,[int]$Width,[int]$Height,[int]$FirstColumn,[int]$EndColumn,[hashtable]$Context,
        [ValidateRange(0,32767)][int]$ColumnOffset=0,[ValidateRange(0,32767)][int]$RowOffset=0)
    if($Width -lt 2 -or $Height -lt 4 -or $Pixels.Length -ne $Width*$Height -or $Width%2 -or $Height%4 -or $FirstColumn%2 -or $EndColumn%2 -or $FirstColumn -lt 0 -or $EndColumn -gt $Width -or $FirstColumn -ge $EndColumn){throw 'Menu strip dimensions are invalid.'}
    # Brightest of each 2x2 source region preserves thin menu text on black.
    # Each output cell still carries two independent palette colors.
    $chunks=[Collections.Generic.List[string]]::new();$esc=[char]27;[int[]]$luma=$Context.Luma;[string[]]$cells=$Context.Hud.Cells
    for($y=0;$y -lt $Height;$y+=4){
        $chunks.Add("$esc[$($y/4+1+$RowOffset);$($FirstColumn/2+1+$ColumnOffset)H")
        for($x=$FirstColumn;$x -lt $EndColumn;$x+=2){
            $offset=$y*$Width+$x;$top=[int]$Pixels[$offset];$bottom=[int]$Pixels[$offset+2*$Width]
            foreach($index in @(($offset+1),($offset+$Width),($offset+$Width+1))){if($luma[$Pixels[$index]] -gt $luma[$top]){$top=$Pixels[$index]}}
            foreach($index in @(($offset+2*$Width+1),($offset+3*$Width),($offset+3*$Width+1))){if($luma[$Pixels[$index]] -gt $luma[$bottom]){$bottom=$Pixels[$index]}}
            $chunks.Add($cells[$top*256+$bottom])
        }
    }
    return ,([Text.Encoding]::UTF8.GetBytes([string]::Concat($chunks)))
}
function Get-CharacterAlphabet {
    param([ValidateSet('Ascii','Katakana')][string]$GlyphSet='Ascii')
    if($GlyphSet -eq 'Katakana'){
        # Half-width forms; do not normalize to full-width or add voiced marks.
        return @{Ramp=' ･､ｨｱｲｳｴｵｶｷｻﾈﾎ';Vertical='ｲ';Horizontal='ｰ';
            Code='ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789'}
    }
    return @{Ramp=' .,:;i1tfLCG08@';Code='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ:;+=<>[]{}';Vertical='|';Horizontal='-'}
}

function Test-CharacterConsoleWidth {
    param([ValidateSet('Ascii','Katakana')][string]$GlyphSet='Katakana',[switch]$Batch)
    $alphabet=Get-CharacterAlphabet $GlyphSet
    $symbols=($alphabet.Ramp+$alphabet.Code+$alphabet.Vertical+$alphabet.Horizontal+[char]0x2580).ToCharArray() | Sort-Object -Unique
    $results=[Collections.Generic.List[object]]::new();$stream=[Console]::OpenStandardOutput()
    $probes=if($Batch -and [Console]::WindowWidth -gt $symbols.Count){,@{Text=($symbols -join '');Label='Complete alphabet';Expected=$symbols.Count}}
        else{@($symbols | ForEach-Object {@{Text=[string]$_;Label=('U+{0:X4}' -f [int]$_);Expected=1}})}
    foreach($probe in $probes){
        [Console]::SetCursorPosition(0,0);$before=[Console]::CursorLeft
        $bytes=[Text.Encoding]::UTF8.GetBytes($probe.Text);$stream.Write($bytes);$stream.Flush()
        $advance=[Console]::CursorLeft-$before
        $results.Add(@{Symbols=$probe.Label;Columns=$advance;Expected=$probe.Expected})
        if($advance -ne $probe.Expected){throw "Character width mismatch for $($probe.Label); try -GlyphSet Ascii."}
    }
    [Console]::Write("$([char]27)[2J$([char]27)[H")
    return @{GlyphSet=$GlyphSet;SymbolCount=$symbols.Count;Checks=$results.ToArray();Meaning='Live console cursor advancement under the active Terminal profile; batch mode checks total alphabet width. Visual font rendering is verified separately by recording.'}
}

function New-CharacterCodecContext {
    param([int[][]]$Palette,[ValidateSet('AnsiArt','Matrix')][string]$Style='Matrix',
        [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Ascii')
    if($Palette.Count -ne 256){throw 'A 256-color source palette is required.'}
    $luma=[int[]]::new(256);$tones=[int[]]::new(256);$colors=[string[]]::new(256)
    $matrixColors=[string[]]::new(1280);$greenPalette=[int[][]]::new(256);$esc=[char]27
    for($i=0;$i -lt 256;$i++) {
        $rgb=$Palette[$i];$luma[$i]=[int](($rgb[0]*54+$rgb[1]*183+$rgb[2]*19)/256)
        $tones[$i]=[int](255*[Math]::Pow($i/255.0,.6))
        $r=[Math]::Min(255,[int]($rgb[0]*1.35));$g=[Math]::Min(255,[int]($rgb[1]*1.35));$b=[Math]::Min(255,[int]($rgb[2]*1.35))
        $colors[$i]="$esc[38;2;$r;$g;$($b);48;2;$([int]($rgb[0]*.08));$([int]($rgb[1]*.08));$([int]($rgb[2]*.08))m"
        $v=[int](255*[Math]::Pow($luma[$i]/255.0,.75));$greenPalette[$i]=@([int]($v*.08),$v,[int]($v*.25))
    }
    for($i=0;$i -lt 256;$i++) {
        for($accent=0;$accent -lt 5;$accent++) {
            # Expand Doom's dim scene values while leaving the deepest shadows dark.
            $baseTone=[int](255*[Math]::Pow([Math]::Clamp(($i-6)/130.0,0.0,1.0),.85))
            $v=[Math]::Min(255,$baseTone+@(0,18,42,75,120)[$accent])
            if($i -lt 4){$v=[Math]::Min($v,75)}
            $r=[int]($v*.08);$b=[int]($v*.25)
            if($accent -eq 4){$r=[int]($v*.85);$b=[int]($v*.9)}
            $matrixColors[$accent*256+$i]="$esc[38;2;$r;$v;$($b);48;2;0;$([int]($baseTone*.12));0m"
        }
    }
    $hudPalette=if($Style -eq 'Matrix'){$greenPalette}else{$Palette}
    $alphabet=Get-CharacterAlphabet $GlyphSet
    return @{Style=$Style;GlyphSet=$GlyphSet;Luma=$luma;Tones=$tones;Colors=$colors;MatrixColors=$matrixColors;
        Ramp=$alphabet.Ramp;Code=$alphabet.Code;Vertical=$alphabet.Vertical;Horizontal=$alphabet.Horizontal;Hud=(New-CodecContext $hudPalette)}
}

function ConvertTo-CharacterStrip {
    param([byte[]]$Pixels,[int]$Width,[int]$Height,[int]$FirstColumn,[int]$EndColumn,[hashtable]$Context,
        [ValidateRange(0,32767)][int]$ColumnOffset=0,[ValidateRange(0,32767)][int]$RowOffset=0,
        [ValidateRange(0,2147483647)][int]$FrameNumber=0,[int]$HudStart=168)
    if($Pixels.Length -ne $Width*$Height -or $Width%2 -or $Height%4 -or $FirstColumn%2 -or $EndColumn%2 -or
        $FirstColumn -lt 0 -or $EndColumn -gt $Width -or $FirstColumn -ge $EndColumn -or $HudStart%4 -or $HudStart -lt 0 -or $HudStart -gt $Height){throw 'Character strips require an even width, four-pixel rows, and boundaries aligned to two source columns.'}
    [int]$columns=$Width/2;[int]$rows=$Height/4;[int]$sceneRows=$HudStart/4
    [int[]]$lum=$Context.Luma;[string[]]$colors=$Context.Colors;[string[]]$matrixColors=$Context.MatrixColors
    [int[]]$tones=$Context.Tones;[string]$ramp=$Context.Ramp;[string]$code=$Context.Code;[string[]]$hud=$Context.Hud.Cells
    [string]$verticalGlyph=$Context.Vertical;[string]$horizontalGlyph=$Context.Horizontal
    [bool]$matrix=$Context.Style -eq 'Matrix';$esc=[char]27
    [string[]]$chunks=[string[]]::new((($EndColumn-$FirstColumn)/2+1)*$rows);[int]$n=0
    [int[]]$heads=[int[]]::new($columns);[Array]::Fill($heads,-100)
    if($matrix){for($x=$FirstColumn/2;$x -lt $EndColumn/2;$x++){if(($x*37)%7 -lt 2){$heads[$x]=([int][Math]::Floor($FrameNumber*(3+$x%4)/60.0)+$x*11)%($sceneRows+12)-6}}}
    [int]$phase=[Math]::Floor($FrameNumber/8.0)
    for([int]$row=0;$row -lt $rows;$row++) {
        $chunks[$n++]="$esc[$($row+1+$RowOffset);$($FirstColumn/2+1+$ColumnOffset)H"
        [int]$y=$row*4;[int]$base=$y*$Width
        for([int]$x=$FirstColumn;$x -lt $EndColumn;$x+=2) {
            [int]$a=$Pixels[$base+$x];[int]$b=$Pixels[$base+$x+1];[int]$c=$Pixels[$base+$Width+$x];[int]$d=$Pixels[$base+$Width+$x+1]
            [int]$e=$Pixels[$base+2*$Width+$x];[int]$f=$Pixels[$base+2*$Width+$x+1];[int]$g=$Pixels[$base+3*$Width+$x];[int]$h=$Pixels[$base+3*$Width+$x+1]
            if($row -ge $sceneRows){$chunks[$n++]=$hud[$d*256+$h];continue}
            [int]$la=$lum[$a];[int]$lb=$lum[$b];[int]$lc=$lum[$c];[int]$ld=$lum[$d]
            [int]$le=$lum[$e];[int]$lf=$lum[$f];[int]$lg=$lum[$g];[int]$lh=$lum[$h]
            [int]$mean=($la+$lb+$lc+$ld+$le+$lf+$lg+$lh)/8
            [int]$column=$x/2;[string]$glyph=' '
            if($matrix) {
                [int]$distance=$heads[$column]-$row;[int]$accent=0
                if($distance -eq 0){$accent=4}elseif($distance -eq 1){$accent=3}elseif($distance -le 4 -and $distance -gt 1){$accent=2}elseif($distance -le 8 -and $distance -gt 4){$accent=1}
                if($mean -ge 3 -or $accent -gt 0){
                    [long]$hash=(($column+1)*73856093L) -bxor (($row+1)*19349663L)
                    $hash=$hash -bxor ($hash -shr 13)
                    if($accent -gt 0){$hash+=$phase}
                    $glyph=[string]$code[$hash%$code.Length]
                }
                $chunks[$n++]=$matrixColors[$accent*256+$mean]+$glyph
            } else {
                [int]$representative=$a;[int]$brightest=$la
                if($lb -gt $brightest){$representative=$b;$brightest=$lb};if($lc -gt $brightest){$representative=$c;$brightest=$lc}
                if($ld -gt $brightest){$representative=$d;$brightest=$ld};if($le -gt $brightest){$representative=$e;$brightest=$le}
                if($lf -gt $brightest){$representative=$f;$brightest=$lf};if($lg -gt $brightest){$representative=$g;$brightest=$lg}
                if($lh -gt $brightest){$representative=$h}
                $glyph=[string]$ramp[[int]($tones[$mean]*($ramp.Length-1)/255)]
                [int]$horizontal=($lb+$ld+$lf+$lh-$la-$lc-$le-$lg)/4
                [int]$vertical=($le+$lf+$lg+$lh-$la-$lb-$lc-$ld)/4
                if([Math]::Abs($horizontal) -gt 28 -and [Math]::Abs($horizontal) -gt 2*[Math]::Abs($vertical)){$glyph=$verticalGlyph}
                elseif([Math]::Abs($vertical) -gt 28 -and [Math]::Abs($vertical) -gt 2*[Math]::Abs($horizontal)){$glyph=$horizontalGlyph}
                $chunks[$n++]=$colors[$representative]+$glyph
            }
        }
    }
    return ,([Text.Encoding]::UTF8.GetBytes([string]::Concat($chunks)))
}
