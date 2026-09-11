# SPDX-License-Identifier: GPL-2.0-or-later
# Session navigation is separate from Doom's simulation commands. Menu requests
# are acknowledged only after the simulation has consumed the issued prefix.
function New-DoomMenuState {
    param([ValidateRange(1,4)][int]$Episodes=4,[int]$Episode=1,[int]$Skill=3)
    return @{Screen=0;Choice=0;Episode=$Episode;Skill=$Skill;Episodes=$Episodes}
}
function Invoke-DoomMenuKey {
    param($Menu,[ValidateSet('Escape','Pause','Up','Down','Enter','Yes','No')][string]$Key)
    $screen=$Menu.Screen
    if($screen -eq 0){
        if($Key -eq 'Escape'){$Menu.Screen=1;$Menu.Choice=0}
        elseif($Key -eq 'Pause'){$Menu.Screen=7;$Menu.Choice=0}else{return $null}
    }elseif($screen -eq 7){
        if($Key -in 'Pause','Escape','Enter'){$Menu.Screen=0}else{return $null}
    }elseif($Key -eq 'Escape' -or ($Key -eq 'No' -and $screen -in 4,6)){
        $Menu.Screen=switch($screen){1{0};2{1};3{if($Menu.Episodes -gt 1){2}else{1}};4{3};default{1}}
        $Menu.Choice=if($Menu.Screen -eq 2){$Menu.Episode-1}elseif($Menu.Screen -eq 3){$Menu.Skill-1}else{0}
    }elseif($screen -eq 5){
        if($Key -eq 'Enter'){$Menu.Screen=1;$Menu.Choice=2}else{return $null}
    }elseif($Key -in 'Up','Down'){
        $count=switch($screen){1{4};2{$Menu.Episodes};3{5};default{2}}
        $delta=if($Key -eq 'Up'){-1}else{1};$Menu.Choice=($Menu.Choice+$delta+$count)%$count
    }elseif($Key -eq 'Enter' -or ($Key -eq 'Yes' -and $screen -in 4,6)){
        if($Key -eq 'Yes'){$Menu.Choice=1}
        switch($screen){
            1 {switch($Menu.Choice){0{$Menu.Screen=0};1{$Menu.Screen=if($Menu.Episodes -gt 1){2}else{3};$Menu.Choice=if($Menu.Screen -eq 2){$Menu.Episode-1}else{$Menu.Skill-1}};2{$Menu.Screen=5};3{$Menu.Screen=6;$Menu.Choice=0}}}
            2 {$Menu.Episode=$Menu.Choice+1;$Menu.Screen=3;$Menu.Choice=$Menu.Skill-1}
            3 {$Menu.Skill=$Menu.Choice+1;$Menu.Screen=4;$Menu.Choice=0}
            4 {if($Menu.Choice -eq 1){$Menu.Screen=0;return @{Action='NewGame';Skill=$Menu.Skill;Episode=$Menu.Episode;Map=1}}else{$Menu.Screen=3;$Menu.Choice=$Menu.Skill-1}}
            6 {if($Menu.Choice -eq 1){return @{Action='Quit'}}else{$Menu.Screen=1;$Menu.Choice=3}}
        }
    }else{return $null}
    return @{Action='ShowMenu';Screen=$Menu.Screen;Choice=$Menu.Choice;Episode=$Menu.Episode;Skill=$Menu.Skill}
}

function New-DoomMenuGraphics {
    param($Content)
    $patches=@{}
    foreach($name in 'M_DOOM','M_NEWG','M_EPISOD','M_SKILL','M_JKILL','M_ROUGH','M_HURT','M_ULTRA','M_NMARE','M_EPI1','M_EPI2','M_EPI3','M_EPI4','M_QUITG','M_SKULL1','M_PAUSE'){
        $lump=$Content.Wad.GetLumpNumber($name)
        if($lump -ge 0){$patches[$name]=[Patch]::FromData($name,$Content.Wad.ReadLump($lump))}
    }
    return @{Screen=[DrawScreen]::new($Content.Wad,320,200);Patches=$patches}
}
function Get-DoomCompactMenu {
    param($Menu,[int]$Columns,[int]$Rows)
    $title=switch($Menu.Screen){1{'pwshDoom menu'};2{'Choose episode'};3{'Choose skill'};4{'Start a new game?'};5{'Controls'};6{'Quit Doom?'};7{'Paused'};default{'pwshDoom'}}
    $items=switch($Menu.Screen){
        1 {@('Resume game','New game','Controls','Quit')}
        2 {@('Knee-Deep in the Dead','The Shores of Hell','Inferno','Thy Flesh Consumed')|Select-Object -First $Menu.Episodes}
        3 {@("I'm too young to die",'Hey, not too rough','Hurt me plenty','Ultra-Violence','Nightmare')}
        {$_ -in 4,6} {@('No','Yes')}
        5 {@('WASD move/strafe; arrows move/turn','Ctrl fire; E/Space/Enter use','Shift run; 1-7 weapons','P pause; Esc menu/back')}
        7 {@('P / Enter / Esc to resume')}
    }
    $lines=@($title)
    for($i=0;$i -lt $items.Count;$i++){$marker=if($Menu.Screen -notin 5,7 -and $i -eq $Menu.Choice){'> '}else{'  '};$lines+=$marker+$items[$i]}
    $lines+=@('Arrows choose; Enter selects; Esc back.','Resize the window to restore the game view.')
    $limit=[Math]::Max(0,$Columns-1)
    return (($lines|Select-Object -First ([Math]::Max(0,$Rows))|ForEach-Object {if($_.Length -gt $limit){$_.Substring(0,$limit)}else{$_}}) -join "`r`n")
}
function Draw-DoomMenuText {
    param($Graphics,[string]$Text,[int]$X,[int]$Y,[int]$Scale=2,[switch]$Center)
    if($Center){
        $width=0
        foreach($letter in $Text.ToUpperInvariant().ToCharArray()){
            $glyph=$Graphics.Screen.Chars[[int]$letter]
            $width+=if($null -ne $glyph){($glyph.Width+1)*$Scale}else{4*$Scale}
        }
        $X=[int][Math]::Floor((320-$width)/2)
    }
    foreach($letter in $Text.ToUpperInvariant().ToCharArray()){
        $glyph=$Graphics.Screen.Chars[[int]$letter]
        if($null -ne $glyph){
            $left=$X-$Scale*$glyph.LeftOffset;$top=$Y-$Scale*$glyph.TopOffset
            if($left -lt 0 -or $top -lt 0 -or $left+$glyph.Width*$Scale -gt 320 -or $top+$glyph.Height*$Scale -gt 200){throw "Menu text does not fit: $Text"}
            $Graphics.Screen.DrawPatch($glyph,$X,$Y,$Scale);$X+=($glyph.Width+1)*$Scale
        }else{$X+=4*$Scale}
    }
}
function Get-DoomMenuPixels {
    param($Graphics,[int]$Screen,[int]$Choice,[int]$Episode,[int]$Skill,[int]$Episodes=4)
    [Array]::Clear($Graphics.Screen.Data)
    $patches=$Graphics.Patches;$draw=$Graphics.Screen
    switch($Screen){
        1 {
            $draw.DrawPatch($patches.M_DOOM,94,2,1)
            Draw-DoomMenuText $Graphics 'RESUME GAME' 66 76 2
            $draw.DrawPatch($patches.M_NEWG,66,94,1)
            Draw-DoomMenuText $Graphics 'CONTROLS' 66 116 2
            $draw.DrawPatch($patches.M_QUITG,66,134,1)
            $draw.DrawPatch($patches.M_SKULL1,36,(76+20*$Choice),1)
        }
        2 {
            $draw.DrawPatch($patches.M_EPISOD,54,30,1)
            for($i=0;$i -lt $Episodes;$i++){$draw.DrawPatch($patches['M_EPI'+($i+1)],48,(65+22*$i),1)}
            $draw.DrawPatch($patches.M_SKULL1,16,(65+22*$Choice),1)
        }
        3 {
            $draw.DrawPatch($patches.M_SKILL,54,25,1)
            $names=@('M_JKILL','M_ROUGH','M_HURT','M_ULTRA','M_NMARE')
            for($i=0;$i -lt 5;$i++){$draw.DrawPatch($patches[$names[$i]],48,(55+22*$i),1)}
            $draw.DrawPatch($patches.M_SKULL1,16,(55+22*$Choice),1)
        }
        4 {
            Draw-DoomMenuText $Graphics 'START A NEW GAME?' 0 38 -Center
            Draw-DoomMenuText $Graphics "EPISODE $Episode - SKILL $Skill" 0 64 -Center
            if($Skill -eq 5){Draw-DoomMenuText $Graphics 'NIGHTMARE!' 0 86 -Center}
            Draw-DoomMenuText $Graphics 'NO' 135 112;Draw-DoomMenuText $Graphics 'YES' 135 138
            $draw.DrawPatch($patches.M_SKULL1,102,(110+26*$Choice),1)
        }
        5 {
            Draw-DoomMenuText $Graphics 'CONTROLS' 0 6 -Center
            $lines=@('WASD: MOVE/STRAFE','ARROWS: MOVE/TURN','CTRL: FIRE','E/SPACE/ENTER: USE','SHIFT: RUN','1-7: WEAPONS','P: PAUSE/RESUME','ESC: MENU/BACK','ENTER: RETURN')
            for($i=0;$i -lt $lines.Count;$i++){Draw-DoomMenuText $Graphics $lines[$i] 16 (30+18*$i)}
        }
        6 {
            Draw-DoomMenuText $Graphics 'QUIT DOOM?' 0 50 -Center
            Draw-DoomMenuText $Graphics 'NO' 135 100;Draw-DoomMenuText $Graphics 'YES' 135 130
            $draw.DrawPatch($patches.M_SKULL1,102,(98+30*$Choice),1)
        }
        7 {$draw.DrawPatch($patches.M_PAUSE,126,64,1);Draw-DoomMenuText $Graphics 'P / ENTER / ESC' 0 104 -Center;Draw-DoomMenuText $Graphics 'TO RESUME' 0 128 -Center}
        default{throw 'Invalid visible menu screen.'}
    }
    if($Screen -in 1,2,3,4,6){Draw-DoomMenuText $Graphics 'ARROWS: CHOOSE' 0 166 -Center;Draw-DoomMenuText $Graphics 'ENTER: OK  ESC: BACK' 0 184 -Center}
    return ,$draw.Data
}

function Send-DoomSessionAction {
    param($Simulation,$Action,[int]$Tic)
    $view=$Simulation.View
    if($view.ReadInt32(48) -ne $view.ReadInt32(52)){throw 'A session action is already pending.'}
    $sequence=$view.ReadInt32(48)+1
    if($Action.Action -eq 'ShowMenu'){$kind=1;$values=@($Action.Screen,$Action.Choice,$Action.Episode,$Action.Skill)}
    elseif($Action.Action -eq 'NewGame'){$kind=2;$values=@($Action.Skill,$Action.Episode,$Action.Map,0)}
    else{throw 'Unsupported simulation session action.'}
    $view.Write(56,[int]$kind)
    for($i=0;$i -lt 4;$i++){$view.Write(60+4*$i,[int]$values[$i])}
    $view.Write(76,$Tic);[Threading.Thread]::MemoryBarrier();$view.Write(48,$sequence);[void]$Simulation.Go.Set()
    return $sequence
}
