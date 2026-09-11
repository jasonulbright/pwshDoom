# SPDX-License-Identifier: GPL-2.0-or-later
# Session navigation is separate from Doom's simulation commands. Menu requests
# are acknowledged only after the simulation has consumed the issued prefix.
. "$PSScriptRoot/SaveSlots.ps1"; . "$PSScriptRoot/UserSettings.ps1"
function New-DoomMenuState {
    param([ValidateRange(1,4)][int]$Episodes=4,[int]$Episode=1,[int]$Skill=3)
    return @{Screen=0;Choice=0;Episode=$Episode;Skill=$Skill;Episodes=$Episodes;Slots=@(1..6|ForEach-Object {@{Slot=$_;State='Empty';Sha256=$null;Episode=0;Map=0;Skill=0;Time='';SourceMatches=$true}});SelectedSlot=1;MessageTitle='';MessageDetail='';ReturnScreen=1;Settings=(New-DoomUserSettings)}
}
function Invoke-DoomMenuKey {
    param($Menu,[ValidateSet('Escape','Pause','Up','Down','Left','Right','Enter','Yes','No')][string]$Key)
    $screen=$Menu.Screen;$settingsChanged=$false
    if($screen -eq 13){return $null}
    if($screen -eq 0){
        if($Key -eq 'Escape'){$Menu.Screen=1;$Menu.Choice=0}
        elseif($Key -eq 'Pause'){$Menu.Screen=7;$Menu.Choice=0}else{return $null}
    }elseif($screen -eq 7){
        if($Key -in 'Pause','Escape','Enter'){$Menu.Screen=0}else{return $null}
    }elseif($Key -eq 'Escape' -or ($Key -eq 'No' -and $screen -in 4,6,10,11)){
        $Menu.Screen=switch($screen){1{0};2{1};3{if($Menu.Episodes -gt 1){2}else{1}};4{3};10{8};11{9};12{$Menu.ReturnScreen};default{1}}
        $Menu.Choice=if($Menu.Screen -eq 2){$Menu.Episode-1}elseif($Menu.Screen -eq 3){$Menu.Skill-1}elseif($Menu.Screen -in 8,9){$Menu.SelectedSlot-1}else{0}
    }elseif($screen -eq 14 -and $Key -in 'Left','Right','Enter'){
        switch($Menu.Choice){
            0 {$Menu.Settings.AlwaysRun=-not $Menu.Settings.AlwaysRun;$settingsChanged=$true}
            1 {$speeds=@(50,100,150);$index=[Array]::IndexOf($speeds,[int]$Menu.Settings.TurnSpeed);$delta=if($Key -eq 'Left'){-1}else{1};$Menu.Settings.TurnSpeed=$speeds[($index+$delta+3)%3];$settingsChanged=$true}
            2 {$delta=if($Key -eq 'Left'){-10}else{10};$level=[Math]::Clamp($Menu.Settings.SoundVolume+$delta,0,100);$settingsChanged=$level -ne $Menu.Settings.SoundVolume;$Menu.Settings.SoundVolume=$level}
            3 {$Menu.Settings.SoundMuted=-not $Menu.Settings.SoundMuted;$settingsChanged=$true}
            4 {if($Key -eq 'Enter'){$Menu.Settings=New-DoomUserSettings;$settingsChanged=$true}else{return $null}}
            5 {if($Key -eq 'Enter'){$Menu.Screen=1;$Menu.Choice=5}else{return $null}}
        }
    }elseif($screen -eq 5){
        if($Key -eq 'Enter'){$Menu.Screen=1;$Menu.Choice=4}else{return $null}
    }elseif($screen -eq 12){
        if($Key -eq 'Enter'){$Menu.Screen=$Menu.ReturnScreen;$Menu.Choice=if($Menu.Screen -in 8,9){$Menu.SelectedSlot-1}else{0}}else{return $null}
    }elseif($Key -in 'Up','Down'){
        $count=switch($screen){1{7};14{6};2{$Menu.Episodes};3{5};8{6};9{6};default{2}}
        $delta=if($Key -eq 'Up'){-1}else{1};$Menu.Choice=($Menu.Choice+$delta+$count)%$count
    }elseif($Key -eq 'Enter' -or ($Key -eq 'Yes' -and $screen -in 4,6,10,11)){
        if($Key -eq 'Yes'){$Menu.Choice=1}
        switch($screen){
            1 {switch($Menu.Choice){0{$Menu.Screen=0};1{$Menu.Screen=if($Menu.Episodes -gt 1){2}else{3};$Menu.Choice=if($Menu.Screen -eq 2){$Menu.Episode-1}else{$Menu.Skill-1}};2{$Menu.Screen=8;$Menu.Choice=0};3{$Menu.Screen=9;$Menu.Choice=0};4{$Menu.Screen=5};5{$Menu.Screen=14;$Menu.Choice=0};6{$Menu.Screen=6;$Menu.Choice=0}}}
            2 {$Menu.Episode=$Menu.Choice+1;$Menu.Screen=3;$Menu.Choice=$Menu.Skill-1}
            3 {$Menu.Skill=$Menu.Choice+1;$Menu.Screen=4;$Menu.Choice=0}
            4 {if($Menu.Choice -eq 1){$Menu.Screen=0;return @{Action='NewGame';Skill=$Menu.Skill;Episode=$Menu.Episode;Map=1}}else{$Menu.Screen=3;$Menu.Choice=$Menu.Skill-1}}
            6 {if($Menu.Choice -eq 1){return @{Action='Quit'}}else{$Menu.Screen=1;$Menu.Choice=6}}
            {$_ -in 8,9} {
                $Menu.SelectedSlot=$Menu.Choice+1;$entry=$Menu.Slots[$Menu.Choice];$Menu.ReturnScreen=$screen
                if($screen -eq 9 -and $entry.State -ne 'Ready'){$Menu.Screen=12;$Menu.MessageTitle=if($entry.State -eq 'Empty'){'EMPTY SLOT'}else{'SAVE UNAVAILABLE'};$Menu.MessageDetail='CHOOSE ANOTHER SLOT'}
                elseif($screen -eq 8 -and $entry.State -eq 'Empty'){$Menu.Screen=13;$Menu.MessageTitle='SAVING GAME';return @{Action='SaveGame';Slot=$Menu.SelectedSlot;ExpectedHash=$null}}
                elseif($screen -eq 8 -and -not $entry.Sha256){$Menu.Screen=12;$Menu.MessageTitle='SLOT UNAVAILABLE';$Menu.MessageDetail='CHOOSE ANOTHER SLOT'}
                else{$Menu.Screen=if($screen -eq 8){10}else{11};$Menu.Choice=0}
            }
            {$_ -in 10,11} {
                if($Menu.Choice -eq 0){$Menu.Screen=if($screen -eq 10){8}else{9};$Menu.Choice=$Menu.SelectedSlot-1}
                else{$entry=$Menu.Slots[$Menu.SelectedSlot-1];$Menu.Screen=13;$Menu.MessageTitle=if($screen -eq 10){'SAVING GAME'}else{'LOADING GAME'}
                    return @{Action=if($screen -eq 10){'SaveGame'}else{'LoadGame'};Slot=$Menu.SelectedSlot;ExpectedHash=$entry.Sha256;AllowSourceMismatch=-not $entry.SourceMatches}}
            }
        }
    }else{return $null}
    return @{Action='ShowMenu';Screen=$Menu.Screen;Choice=$Menu.Choice;Episode=$Menu.Episode;Skill=$Menu.Skill;Slots=$Menu.Slots;SelectedSlot=$Menu.SelectedSlot;MessageTitle=$Menu.MessageTitle;MessageDetail=$Menu.MessageDetail;Settings=$Menu.Settings;SettingsChanged=$settingsChanged}
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
    $title=switch($Menu.Screen){1{'pwshDoom menu'};2{'Choose episode'};3{'Choose skill'};4{'Start a new game?'};5{'Controls'};6{'Quit Doom?'};7{'Paused'};8{'Save game'};9{'Load game'};10{'Replace this save?'};11{'Load this save?'};12{$Menu.MessageTitle};13{$Menu.MessageTitle};14{'Settings'};default{'pwshDoom'}}
    $items=switch($Menu.Screen){
        1 {@('Resume game','New game','Save game','Load game','Controls','Settings','Quit')}
        2 {@('Knee-Deep in the Dead','The Shores of Hell','Inferno','Thy Flesh Consumed')|Select-Object -First $Menu.Episodes}
        3 {@("I'm too young to die",'Hey, not too rough','Hurt me plenty','Ultra-Violence','Nightmare')}
        {$_ -in 4,6,10,11} {@('No','Yes')}
        5 {@('WASD move/strafe; arrows move/turn','Ctrl fire; E/Space/Enter use','Shift run; 1-7 weapons','Tab map; +/- zoom; F follow','Map: arrows pan; M mark; C clear','P pause; Esc menu/back')}
        7 {@('P / Enter / Esc to resume')}
        {$_ -in 8,9} {@($Menu.Slots|ForEach-Object {if($_.State -eq 'Ready'){"$($_.Slot)  E$($_.Episode)M$($_.Map)  $($_.Time)"}else{"$($_.Slot)  $($_.State)"}})}
        12 {@($Menu.MessageDetail,'Enter / Esc to return')}
        13 {@('Please wait...')}
        14 {@("Always run: $(if($Menu.Settings.AlwaysRun){'On'}else{'Off'})","Turn speed: $($Menu.Settings.TurnSpeed)%","Sound volume: $($Menu.Settings.SoundVolume)%","Mute sound: $(if($Menu.Settings.SoundMuted){'On'}else{'Off'})",'Reset defaults','Back')}
    }
    $lines=@($title)
    for($i=0;$i -lt $items.Count;$i++){$marker=if($Menu.Screen -notin 5,7 -and $i -eq $Menu.Choice){'> '}else{'  '};$lines+=$marker+$items[$i]}
    if($Menu.Screen -eq 11 -and -not $Menu.Slots[$Menu.SelectedSlot-1].SourceMatches){$lines+='Version changed; behavior may differ.'}
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
    param($Graphics,[int]$Screen,[int]$Choice,[int]$Episode,[int]$Skill,[int]$Episodes=4,$Details)
    [Array]::Clear($Graphics.Screen.Data)
    $patches=$Graphics.Patches;$draw=$Graphics.Screen
    switch($Screen){
        1 {
            $draw.DrawPatch($patches.M_DOOM,94,0,1)
            $labels=@('RESUME GAME','NEW GAME','SAVE GAME','LOAD GAME','CONTROLS','SETTINGS','QUIT')
            for($i=0;$i -lt $labels.Count;$i++){Draw-DoomMenuText $Graphics $labels[$i] 66 (64+14*$i) 2}
            $draw.DrawPatch($patches.M_SKULL1,36,(62+14*$Choice),1)
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
            $lines=@('WASD MOVE/STRAFE','ARROWS MOVE/TURN','CTRL FIRE / E USE','SHIFT RUN / 1-7','TAB MAP / +/- ZOOM','MAP: ARROWS PAN','F FOLLOW / M MARK','C CLEAR / P PAUSE','ESC MENU / ENTER')
            for($i=0;$i -lt $lines.Count;$i++){Draw-DoomMenuText $Graphics $lines[$i] 16 (30+18*$i)}
        }
        6 {
            Draw-DoomMenuText $Graphics 'QUIT DOOM?' 0 50 -Center
            Draw-DoomMenuText $Graphics 'NO' 135 100;Draw-DoomMenuText $Graphics 'YES' 135 130
            $draw.DrawPatch($patches.M_SKULL1,102,(98+30*$Choice),1)
        }
        7 {$draw.DrawPatch($patches.M_PAUSE,126,64,1);Draw-DoomMenuText $Graphics 'P / ENTER / ESC' 0 104 -Center;Draw-DoomMenuText $Graphics 'TO RESUME' 0 128 -Center}
        {$_ -in 8,9} {
            Draw-DoomMenuText $Graphics $(if($Screen -eq 8){'SAVE GAME'}else{'LOAD GAME'}) 0 18 -Center
            if($null -eq $Details -or $Details.Slots.Count -ne 6){throw 'Slot menu requires six entries.'}
            for($i=0;$i -lt 6;$i++){$entry=$Details.Slots[$i];$label=if($entry.State -eq 'Ready'){"$($i+1)  E$($entry.Episode)M$($entry.Map)  $($entry.Time)"}elseif($entry.State -eq 'Empty'){"$($i+1)  EMPTY"}else{"$($i+1)  UNAVAILABLE"};Draw-DoomMenuText $Graphics $label 48 (48+18*$i)}
            $draw.DrawPatch($patches.M_SKULL1,16,(46+18*$Choice),1)
        }
        {$_ -in 10,11} {
            Draw-DoomMenuText $Graphics $(if($Screen -eq 10){'REPLACE THIS SAVE?'}else{'LOAD THIS SAVE?'}) 0 22 -Center
            Draw-DoomMenuText $Graphics "SLOT $($Details.SelectedSlot)" 0 48 -Center
            if($Screen -eq 11 -and -not $Details.Slots[$Details.SelectedSlot-1].SourceMatches){Draw-DoomMenuText $Graphics 'VERSION CHANGED' 0 72 -Center;Draw-DoomMenuText $Graphics 'PLAY MAY DIFFER' 0 90 -Center}
            Draw-DoomMenuText $Graphics 'NO' 135 116;Draw-DoomMenuText $Graphics 'YES' 135 140
            $draw.DrawPatch($patches.M_SKULL1,102,(114+24*$Choice),1)
        }
        12 {Draw-DoomMenuText $Graphics $Details.MessageTitle 0 56 -Center;Draw-DoomMenuText $Graphics $Details.MessageDetail 0 84 -Center;Draw-DoomMenuText $Graphics 'ENTER / ESC: BACK' 0 132 -Center}
        13 {Draw-DoomMenuText $Graphics $Details.MessageTitle 0 64 -Center;Draw-DoomMenuText $Graphics 'PLEASE WAIT' 0 100 -Center}
        14 {
            $preferences=Copy-DoomUserSettings $Details.Settings
            Draw-DoomMenuText $Graphics 'SETTINGS' 0 16 -Center
            $labels=@("ALWAYS RUN: $(if($preferences.AlwaysRun){'ON'}else{'OFF'})","TURN SPEED: $($preferences.TurnSpeed)%","SOUND: $($preferences.SoundVolume)%","MUTE SOUND: $(if($preferences.SoundMuted){'ON'}else{'OFF'})",'RESET DEFAULTS','BACK')
            for($i=0;$i -lt $labels.Count;$i++){Draw-DoomMenuText $Graphics $labels[$i] 48 (48+18*$i)}
            $draw.DrawPatch($patches.M_SKULL1,16,(46+18*$Choice),1)
            Draw-DoomMenuText $Graphics 'LEFT/RIGHT: CHANGE' 0 164 -Center
            Draw-DoomMenuText $Graphics 'ENTER: OK  ESC: BACK' 0 184 -Center
        }
        default{throw 'Invalid visible menu screen.'}
    }
    if($Screen -in 1,2,3,4,6,8,9,10,11){Draw-DoomMenuText $Graphics 'ARROWS: CHOOSE' 0 166 -Center;Draw-DoomMenuText $Graphics 'ENTER: OK  ESC: BACK' 0 184 -Center}
    return ,$draw.Data
}

function Send-DoomSessionAction {
    param($Simulation,$Action,[int]$Tic)
    $view=$Simulation.View
    if($view.ReadInt32(48) -ne $view.ReadInt32(52)){throw 'A session action is already pending.'}
    $sequence=$view.ReadInt32(48)+1
    if($Action.Action -eq 'ShowMenu'){$kind=1;$values=@($Action.Screen,$Action.Choice,$Action.Episode,$Action.Skill)}
    elseif($Action.Action -eq 'NewGame'){$kind=2;$values=@($Action.Skill,$Action.Episode,$Action.Map,0)}
    elseif($Action.Action -eq 'SaveGame'){$kind=3;$values=@(0,0,0,0)}
    elseif($Action.Action -eq 'LoadGame'){$kind=4;$values=@(0,0,0,0)}
    else{throw 'Unsupported simulation session action.'}
    $view.Write(56,[int]$kind)
    for($i=0;$i -lt 4;$i++){$view.Write(60+4*$i,[int]$values[$i])}
    Write-DoomSessionPayload $view 32768 $Action
    $view.Write(76,$Tic);[Threading.Thread]::MemoryBarrier();$view.Write(48,$sequence);[void]$Simulation.Go.Set()
    return $sequence
}
