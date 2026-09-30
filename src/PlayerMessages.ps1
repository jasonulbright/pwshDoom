# SPDX-License-Identifier: GPL-2.0-or-later
# Bounded terminal notices. Game message timing stays on the 35 Hz simulation.
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
        [ValidateSet('Classic','Matrix','AnsiArt')][string]$Style='Classic')
    if($MessageTics -le 0 -or -not $Message -or $ScreenKind -notin 0,3 -or -not $Viewport.Fits){return ,([byte[]]::new(0))}
    $text=($Message -replace '[^\x20-\x7e]',' ').ToUpperInvariant()
    if($text.Length -gt $Viewport.RequiredColumns){$text=$text.Substring(0,$Viewport.RequiredColumns)}
    $color=if($Style -eq 'Matrix'){'38;2;32;255;80'}else{'38;2;255;80;80'}
    $esc=[char]27
    # The next complete frame restores scene cells when a message expires.
    return ,([Text.Encoding]::UTF8.GetBytes("$esc[$($Viewport.Top+1);$($Viewport.Left+1)H$esc[0;$color;48;2;0;0;0"+'m'+$text+"$esc[0m"))
}
