# SPDX-License-Identifier: GPL-2.0-or-later
# Adopted PowerShell 2D renderers draw native WAD intermission/finale graphics.
# Their indexed framebuffer is column-major; render workers transpose only their strips.
function New-DoomSessionScreens {
    param($Content,[int]$Episode=1)
    $screen=[DrawScreen]::new($Content.Wad,320,200)
    $intermission=[IntermissionRenderer]::new($Content.Wad,$screen)
    $intermission.WarmupBackground($Content.Wad.GameMode,$Episode)
    return @{Screen=$screen;Intermission=$intermission;Finale=[FinaleRenderer]::new($Content,$screen)}
}
function Get-DoomSessionScreen {
    param($Screens,$Game)
    if($Game.State -eq [GameState]::Intermission){$Screens.Intermission.Render($Game.Intermission)}
    elseif($Game.State -eq [GameState]::Finale){$Screens.Finale.Render($Game.Finale)}
    else{throw 'A session screen requires intermission or finale state.'}
    return ,$Screens.Screen.Data
}
