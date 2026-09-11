#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',[string]$Output="$PSScriptRoot/../results/menu-unit.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Choose a fresh report path.'}
. "$PSScriptRoot/../src/SessionMenu.ps1";. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/TerminalCodec.ps1";. "$PSScriptRoot/../src/CharacterCodec.ps1"
$checks=[Collections.Generic.List[object]]::new();$frames=[Collections.Generic.List[object]]::new();$failure=$null;$content=$null;$directory=$null
function Assert-Menu([string]$Name,[bool]$Condition){if(-not $Condition){throw $Name};$checks.Add(@{Name=$Name;Passed=$true})}
try{
    $m=New-DoomMenuState
    $null=Invoke-DoomMenuKey $m Escape;Assert-Menu 'Escape opens main' ($m.Screen -eq 1)
    $null=Invoke-DoomMenuKey $m Up;Assert-Menu 'Choice wraps upwards' ($m.Choice -eq 6)
    $null=Invoke-DoomMenuKey $m Enter;Assert-Menu 'Quit defaults to no' ($m.Screen -eq 6 -and $m.Choice -eq 0)
    $a=Invoke-DoomMenuKey $m Enter;Assert-Menu 'Quit cancellation returns to menu' ($a.Action -eq 'ShowMenu' -and $m.Screen -eq 1)
    $null=Invoke-DoomMenuKey $m Enter;$a=Invoke-DoomMenuKey $m Yes;Assert-Menu 'Quit requires confirmation' ($a.Action -eq 'Quit')
    $m=New-DoomMenuState;foreach($k in 'Escape','Down','Enter'){$null=Invoke-DoomMenuKey $m $k};Assert-Menu 'New game opens episodes' ($m.Screen -eq 2)
    $null=Invoke-DoomMenuKey $m Up;$null=Invoke-DoomMenuKey $m Enter;Assert-Menu 'Episode selection preserves episode four' ($m.Screen -eq 3 -and $m.Episode -eq 4)
    foreach($k in 'Down','Down','Enter'){$null=Invoke-DoomMenuKey $m $k};Assert-Menu 'Nightmare selection asks before replacing game' ($m.Screen -eq 4 -and $m.Skill -eq 5 -and $m.Choice -eq 0)
    $null=Invoke-DoomMenuKey $m No;Assert-Menu 'New-game cancellation returns to skill' ($m.Screen -eq 3 -and $m.Choice -eq 4)
    $null=Invoke-DoomMenuKey $m Enter;$a=Invoke-DoomMenuKey $m Yes;Assert-Menu 'Confirmed new game carries settings' ($a.Action -eq 'NewGame' -and $a.Episode -eq 4 -and $a.Skill -eq 5 -and $a.Map -eq 1 -and $m.Screen -eq 0)
    $null=Invoke-DoomMenuKey $m Pause;Assert-Menu 'Pause opens paused screen' ($m.Screen -eq 7)
    $null=Invoke-DoomMenuKey $m Enter;Assert-Menu 'Enter resumes pause' ($m.Screen -eq 0)
    $m=New-DoomMenuState 1;foreach($k in 'Escape','Down','Enter'){$null=Invoke-DoomMenuKey $m $k};Assert-Menu 'Single-episode content skips unavailable episodes' ($m.Screen -eq 3)
    $null=Invoke-DoomMenuKey $m Escape;Assert-Menu 'Single-episode skill back returns home' ($m.Screen -eq 1)
    foreach($size in @(@(8,1),@(40,2),@(320,98))){
        $text=Get-DoomCompactMenu $m $size[0] $size[1];$lines=$text.Split("`r`n")
        Assert-Menu "Compact menu fits $($size -join 'x')" ($lines.Count -le $size[1] -and @($lines|Where-Object {$_.Length -ge $size[0]}).Count -eq 0)
    }
    $palette=New-TestPalette 256;$pixels=New-IndexedFrame 32 16 7 -Pattern Entropy -Colors 256
    foreach($style in 'Matrix','AnsiArt'){
        $ctx=New-CharacterCodecContext $palette $style -GlyphSet Katakana
        $expected=[byte[]]::new(16*8)
        for($y=0;$y -lt 8;$y++){for($x=0;$x -lt 16;$x++){
            $offset=2*$y*32+2*$x
            $candidates=@($pixels[$offset],$pixels[$offset+1],$pixels[$offset+32],$pixels[$offset+33])
            $expected[$y*16+$x]=@($candidates|Sort-Object { $ctx.Luma[$_] } -Descending -Stable)[0]
        }}
        foreach($origin in @(@(0,0),@(11,3))){
            for($part=0;$part -lt 7;$part++){
                $first=2*[int][Math]::Floor($part*16/7);$end=2*[int][Math]::Floor(($part+1)*16/7)
                $actual=ConvertTo-MenuStrip $pixels 32 16 $first $end $ctx -ColumnOffset $origin[0] -RowOffset $origin[1]
                $reference=ConvertTo-AnsiStrip $expected 16 8 ($first/2) ($end/2) $ctx.Hud -ColumnOffset $origin[0] -RowOffset $origin[1]
                Assert-Menu "$style max-brightness reference / origin $($origin -join ',') / strip $part" ([Convert]::ToBase64String($actual) -ceq [Convert]::ToBase64String($reference))
                $mapExpected=$expected.Clone()
                for($hy=4;$hy -lt 8;$hy++){for($hx=0;$hx -lt 16;$hx++){$mapExpected[$hy*16+$hx]=$pixels[(2*$hy+1)*32+2*$hx+1]}}
                $mapActual=ConvertTo-MenuStrip $pixels 32 16 $first $end $ctx -ColumnOffset $origin[0] -RowOffset $origin[1] -HudStart 8
                $mapReference=ConvertTo-AnsiStrip $mapExpected 16 8 ($first/2) ($end/2) $ctx.Hud -ColumnOffset $origin[0] -RowOffset $origin[1]
                Assert-Menu "$style map lines plus gameplay HUD / origin $($origin -join ',') / strip $part" ([Convert]::ToBase64String($mapActual) -ceq [Convert]::ToBase64String($mapReference))
            }
        }
    }
    foreach($dimensions in @(@(32,0,0,32),@(31,16,0,30),@(32,15,0,32),@(32,16,1,32),@(32,16,0,34),@(32,16,4,4))){
        $rejected=$false;try{$null=ConvertTo-MenuStrip ([byte[]]::new($dimensions[0]*$dimensions[1])) $dimensions[0] $dimensions[1] $dimensions[2] $dimensions[3] $ctx}catch{$rejected=$true}
        Assert-Menu "Invalid menu dimensions $($dimensions -join ',')" $rejected
    }
    $bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
    $content=[GameContent]::new(@('-iwad',$Wad));$graphics=New-DoomMenuGraphics $content
    $directory=Join-Path "$PSScriptRoot/../local" ('menu-unit-frames-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
    $details=New-DoomMenuState;$details.MessageTitle='SAVE FAILED';$details.MessageDetail='SELECT SLOT AGAIN';$details.Slots[0]=@{Slot=1;State='Ready';Episode=4;Map=9;Skill=5;Time='23:59';Sha256=('A'*64);SourceMatches=$false}
    for($screen=1;$screen -le 14;$screen++){
        $count=switch($screen){1{7};14{6};2{4};3{5};4{2};6{2};8{6};9{6};10{2};11{2};default{1}}
        for($choice=0;$choice -lt $count;$choice++){
            $frame=Get-DoomMenuPixels $graphics $screen $choice 4 5 4 -Details $details
            Assert-Menu "Menu $screen / choice $choice draws nonblank pixels" (@($frame|Where-Object {$_ -ne 0}).Count -gt 100)
            $path=Join-Path $directory "$screen-$choice.bin";[IO.File]::WriteAllBytes($path,$frame)
            $frames.Add(@{Screen=$screen;Choice=$choice;Sha256=(Get-FileHash $path).Hash})
        }
    }
    [IO.File]::WriteAllBytes((Join-Path $directory 'palette.bin'),$content.Palette.Data[0..767])
}catch{$failure=$_.ToString();throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Frames=$frames.ToArray();FrameDirectory=$directory;WadSha256=(Get-FileHash $Wad).Hash;
        Sources=@('src/SessionMenu.ps1','src/CharacterCodec.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
        Meaning='Menu navigation/confirmation and native WAD screen fixtures; independent stable-sort brightness reduction versus actual menu encoders at uneven partitions/origins. Screen draws are not a live keyboard test.'}|ConvertTo-Json -Depth 6|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($checks.Count) menu checks and $($frames.Count) screen fixtures."
