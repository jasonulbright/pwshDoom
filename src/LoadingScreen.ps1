# SPDX-License-Identifier: GPL-2.0-or-later
# Loading UI uses a small PowerShell-built terminal banner, independent of
# workers that may be replacing their map assets. No gameplay/render FPS credit.
function New-DoomLoadingScreen {
    $glyphs=@{
        L=@('10000','10000','10000','10000','10000','10000','11111')
        O=@('01110','10001','10001','10001','10001','10001','01110')
        A=@('01110','10001','10001','11111','10001','10001','10001')
        D=@('11110','10001','10001','10001','10001','10001','11110')
        I=@('11111','00100','00100','00100','00100','00100','11111')
        N=@('10001','11001','11001','10101','10011','10011','10001')
        G=@('01110','10001','10000','10111','10001','10001','01110')
    }
    $lines=[string[]]::new(7)
    for($y=0;$y -lt 7;$y++){
        $parts=@(foreach($letter in 'LOADING'.ToCharArray()){$glyphs[$letter.ToString()][$y].Replace('1',[string][char]0x2588).Replace('0',' ')})
        $lines[$y]=[string]::Join(' ',$parts)
    }
    return @{Lines=$lines}
}
function Get-DoomLoadingOutput {
    param($Screen,[ValidateRange(1,32767)][int]$Columns,[ValidateRange(1,32767)][int]$Rows,[int]$FrameNumber,
        [ValidateSet('Classic','Matrix','AnsiArt')][string]$Style='Classic',[switch]$Clear)
    $esc=[char]27;$builder=[Text.StringBuilder]::new()
    [void]$builder.Append("$esc[0m")
    if($Clear){[void]$builder.Append("$esc[2J")}
    $color=if($Style -eq 'Matrix'){'85;255;119'}else{'255;100;100'}
    [void]$builder.Append("$esc[38;2;$($color)m$esc[48;2;0;0;0m")
    if($Columns -ge 43 -and $Rows -ge 11){
        $left=[int][Math]::Floor(($Columns-41)/2.0)+1
        $top=[int][Math]::Floor(($Rows-10)/2.0)+1
        for($y=0;$y -lt 7;$y++){[void]$builder.Append("$esc[$($top+$y);$($left)H$($Screen.Lines[$y])")}
        $text='Please wait'+('.'*($FrameNumber%4))+(' '*(3-$FrameNumber%4))
        $left=[int][Math]::Floor(($Columns-$text.Length)/2.0)+1
        [void]$builder.Append("$esc[$($top+9);$($left)H$text")
    }else{
        $text='Loading'+('.'*($FrameNumber%4))+(' '*(3-$FrameNumber%4))
        $text=$text.Substring(0,[Math]::Min($text.Length,[Math]::Max(0,$Columns-1)))
        [void]$builder.Append("$esc[1;1H$text")
    }
    return ,([Text.Encoding]::UTF8.GetBytes($builder.ToString()))
}
