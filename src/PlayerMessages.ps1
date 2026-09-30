# SPDX-License-Identifier: GPL-2.0-or-later
# Bounded terminal notices. Game message timing stays on the 35 Hz simulation.
function Get-DoomPlayerMessagePixels {
    param($Graphics,[byte[]]$Message)
    $text=[Text.Encoding]::ASCII.GetString($Message)
    if($Graphics.Text -cne $text){
        [Array]::Clear($Graphics.Screen.Data)
        # Doom uses a seven-pixel baseline for its STCFN message font.
        $visible=[Text.StringBuilder]::new();$width=0
        foreach($ch in $text.ToCharArray()){
            $glyph=$Graphics.Screen.Chars[[int]$ch]
            $advance=if($ch -eq ' '){4}elseif($null -ne $glyph){$glyph.Width}else{0}
            if($width+$advance -gt 320){break}
            [void]$visible.Append($ch);$width+=$advance
        }
        $Graphics.Screen.DrawText($visible.ToString(),0,7,1)
        for($x=0;$x -lt 320;$x++){for($y=0;$y -lt 8;$y++){$Graphics.Pixels[$y*320+$x]=$Graphics.Screen.Data[$x*200+$y]}}
        $Graphics.Text=$text
    }
    return ,$Graphics.Pixels
}
function Get-DoomPlayerMessageBytes {
    param($Player)
    if($Player.MessageTime -le 0 -or -not $Player.Message){return ,([byte[]]::new(0))}
    # Never allow game/save text to supply terminal control sequences. Ultimate
    # Doom's notices are ASCII; unsupported characters become spaces.
    $text=([string]$Player.Message -replace '[^\x20-\x7e]',' ').ToUpperInvariant()
    if($text.Length -gt 512){$text=$text.Substring(0,512)}
    return ,([Text.Encoding]::ASCII.GetBytes($text))
}
function Get-DoomPlayerMessageOutput {
    param([string]$Message,[int]$MessageTics,[int]$ScreenKind,$Viewport,
        [ValidateSet('Classic','Matrix','AnsiArt')][string]$Style='Classic',
        [byte[]]$Pixels,$Codecs)
    if($MessageTics -le 0 -or -not $Message -or $ScreenKind -notin 0,3 -or -not $Viewport.Fits){return ,([byte[]]::new(0))}
    if($null -ne $Pixels){
        if($Pixels.Length -ne 2560 -or $null -eq $Codecs){throw 'Player notice requires its 320x8 pixels and codec.'}
        if($Style -eq 'Classic'){return ,(ConvertTo-AnsiStrip $Pixels 320 8 0 320 $Codecs[0] -ColumnOffset $Viewport.Left -RowOffset $Viewport.Top)}
        return ,(ConvertTo-MenuStrip $Pixels 320 8 0 320 $Codecs[0] -ColumnOffset $Viewport.Left -RowOffset $Viewport.Top)
    }
    $text=($Message -replace '[^\x20-\x7e]',' ').ToUpperInvariant()
    if($text.Length -gt $Viewport.RequiredColumns){$text=$text.Substring(0,$Viewport.RequiredColumns)}
    $color=if($Style -eq 'Matrix'){'38;2;32;255;80'}else{'38;2;255;80;80'}
    $esc=[char]27
    # The next complete frame restores scene cells when a message expires.
    return ,([Text.Encoding]::UTF8.GetBytes("$esc[$($Viewport.Top+1);$($Viewport.Left+1)H$esc[0;$color;48;2;0;0;0"+'m'+$text+"$esc[0m"))
}
