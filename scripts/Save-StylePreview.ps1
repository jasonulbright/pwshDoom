#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# Offline QA: render actual encoded terminal cells with GDI+. Not a game backend or Terminal screenshot.
param([string]$Frame="$PSScriptRoot/../local/capture-350.bin",[int]$FrameNumber=180,
    [string]$Output="$PSScriptRoot/../local/character-preview.png",
    [ValidateSet('Both','AnsiArt','Matrix')][string]$Style='Both',
    [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Katakana')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/CharacterCodec.ps1"
Add-Type -AssemblyName System.Drawing
$pixels=[IO.File]::ReadAllBytes($Frame);$rawPalette=[IO.File]::ReadAllBytes("$PSScriptRoot/../local/palette.bin")
$palette=[int[][]]::new(256);for($i=0;$i -lt 256;$i++){$palette[$i]=@($rawPalette[3*$i],$rawPalette[3*$i+1],$rawPalette[3*$i+2])}
$styles=if($Style -eq 'Both'){@('AnsiArt','Matrix')}else{@($Style)}
$bitmap=[Drawing.Bitmap]::new(1600,830*@($styles).Count);$graphics=[Drawing.Graphics]::FromImage($bitmap);$graphics.Clear([Drawing.Color]::Black)
$fontName=if($GlyphSet -eq 'Katakana'){'MS Gothic'}else{'Consolas'}
$font=[Drawing.Font]::new($fontName,16,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Pixel)
$format=[Drawing.StringFormat]::GenericTypographic.Clone();$format.FormatFlags=$format.FormatFlags -bor [Drawing.StringFormatFlags]::NoWrap
$graphics.TextRenderingHint=[Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$brush=[Drawing.SolidBrush]::new([Drawing.Color]::White)
try {
    $index=0
    foreach($selectedStyle in $styles) {
        $top=$index*830;$graphics.DrawString("$selectedStyle / $GlyphSet | actual encoded 160 x 50 cells | offline preview",$font,[Drawing.Brushes]::White,4,$top+3)
        $context=New-CharacterCodecContext $palette $selectedStyle -GlyphSet $GlyphSet
        $bytes=ConvertTo-CharacterStrip $pixels 320 200 0 320 $context -FrameNumber $FrameNumber
        [IO.File]::WriteAllBytes([IO.Path]::ChangeExtension($Output,"$selectedStyle.ansi"),$bytes)
        $row=0;$column=0;$fg=[Drawing.Color]::White;$bg=[Drawing.Color]::Black
        foreach($match in [regex]::Matches([Text.Encoding]::UTF8.GetString($bytes),"$([char]27)\[([0-9;]+)([Hm])|([^\x1b])")) {
            if($match.Groups[2].Value -eq 'H'){$v=[int[]]$match.Groups[1].Value.Split(';');$row=$v[0]-1;$column=$v[1]-1;continue}
            if($match.Groups[2].Value -eq 'm'){$v=[int[]]$match.Groups[1].Value.Split(';');$fg=[Drawing.Color]::FromArgb($v[2],$v[3],$v[4]);$bg=[Drawing.Color]::FromArgb($v[7],$v[8],$v[9]);continue}
            if($row -notin 0..49 -or $column -notin 0..159){throw 'Encoded glyph is out of bounds.'}
            $x=$column*10;$y=$top+30+$row*16;$brush.Color=$bg;$graphics.FillRectangle($brush,$x,$y,10,16)
            $brush.Color=$fg;$glyph=$match.Groups[3].Value
            if($glyph -eq [string][char]0x2580){$graphics.FillRectangle($brush,$x,$y,10,8)}
            elseif($glyph -ne ' '){$graphics.DrawString($glyph,$font,$brush,[single]$x,[single]$y,$format)}
            $column++
        }
        $index++
    }
    $bitmap.Save([IO.Path]::GetFullPath($Output),[Drawing.Imaging.ImageFormat]::Png)
} finally {$brush.Dispose();$format.Dispose();$font.Dispose();$graphics.Dispose();$bitmap.Dispose()}
[IO.Path]::GetFullPath($Output)
