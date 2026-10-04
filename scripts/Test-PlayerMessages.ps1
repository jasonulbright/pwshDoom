#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[Parameter(Mandatory)][string]$Fixture,
    [Parameter(Mandatory)][string]$SaveRoot,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
foreach($path in $Output,$Fixture,$SaveRoot){if(Test-Path -LiteralPath $path){throw 'Use fresh message-test paths.'}}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/FrameCodec.ps1"
. "$PSScriptRoot/../src/TerminalCodec.ps1"
foreach($name in 'InputReplay','GameHost','SnapshotTransport','SaveState','SessionMenu','SimulationProcess','Viewport','TerminalOutput','AutomapSession','PaletteCodec','CharacterCodec'){
    . "$PSScriptRoot/../src/$name.ps1"
}
$checks=[Collections.Generic.List[object]]::new();$content=$null;$simulation=$null;$failure=$null
$commands=[Collections.Generic.List[object]]::new();$controls=[Collections.Generic.List[object]]::new()
$points=[Collections.Generic.List[object]]::new();$states=[Collections.Generic.List[object]]::new();$maps=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function New-MessageGame {
    $o=[GameOptions]::new();$o.GameMode=$content.Wad.GameMode;$o.GameVersion=$content.Wad.GameVersion;$o.MissionPack=$content.Wad.MissionPack
    $g=[DoomGame]::new($content,$o);$g.DeferedInitNew([GameSkill]::Medium,1,2);$null=$g.Update($cmd)
    return $g
}
function Await-Simulation([int]$Tic){
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($simulation.View.ReadInt32(20) -ne $Tic){
        if($watch.Elapsed.TotalSeconds -gt 25 -or $simulation.View.ReadInt32(12) -eq 3){throw 'Message worker command timed out.'}
        [Threading.Thread]::Sleep(5)
    }
    return Read-DoomSimulationSnapshot $simulation $null
}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$wadHash=(Get-FileHash $Wad).Hash
    $cmd=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$cmd[$i]=[TicCmd]::new()}
    $g=New-MessageGame;$p=$g.World.ConsolePlayer
    $font=@{Screen=[DrawScreen]::new($content.Wad,320,200);Text=$null;Pixels=[byte[]]::new(2560)}
    $glyphs=Get-DoomPlayerMessagePixels $font ([Text.Encoding]::ASCII.GetBytes('YOU NEED A RED KEY'))
    Check 'Bitmap notice contains original font pixels' (@($glyphs|Where-Object {$_ -ne 0}).Count -gt 40)
    $cached=Get-DoomPlayerMessagePixels $font ([Text.Encoding]::ASCII.GetBytes('YOU NEED A RED KEY'))
    Check 'Unchanged notice reuses bitmap without redrawing' ([object]::ReferenceEquals($glyphs,$cached))
    $long=Get-DoomPlayerMessagePixels $font ([Text.Encoding]::ASCII.GetBytes('X'*512))
    Check 'Long bitmap notice clips to the source width' ($long.Length -eq 2560)
    $line=$g.World.Map.Lines[0];$original=$line.Special
    foreach($lock in @(@(26,'PD_BLUEK'),@(27,'PD_YELLOWK'),@(28,'PD_REDK'))){
        try{$line.Special=[int]$lock[0];$g.World.SectorAction.DoLocalDoor($line,$p.Mobj)}finally{$line.Special=$original}
        Check "Locked-door handler emits $($lock[1]) for 140 tics" ($p.Message -ceq [DoomInfo]::Strings.($lock[1]).ToString() -and $p.MessageTime -eq 140)
    }
    $unsafe=@{Message="a$([char]27)[2J`r`nb";MessageTime=140}
    $safe=[Text.Encoding]::ASCII.GetString((Get-DoomPlayerMessageBytes $unsafe))
    Check 'Message transport strips controls and normalizes ASCII' ($safe -ceq 'A [2J  B')
    Check 'Message payload is bounded to 512 bytes' ((Get-DoomPlayerMessageBytes @{Message=('X'*1000);MessageTime=1}).Length -eq 512)
    Check 'Expired message has no payload' ((Get-DoomPlayerMessageBytes @{Message='OLD';MessageTime=0}).Length -eq 0)
    foreach($style in 'Classic','Matrix','AnsiArt'){
        $vp=Get-DoomViewport 400 120 -Style $style
        $outputBytes=Get-DoomPlayerMessageOutput ('X'*512) 140 0 $vp -Style $style
        $text=[Text.Encoding]::UTF8.GetString($outputBytes)
        Check "$style notice fits centered viewport" ($text.Contains("$([char]27)[$($vp.Top+1);$($vp.Left+1)H") -and ([regex]::Match($text,'X+').Length -eq $vp.Width))
        foreach($kind in 1,2){Check "$style hides notices on screen kind $kind" ((Get-DoomPlayerMessageOutput 'BLUE KEY' 1 $kind $vp -Style $style).Length -eq 0)}
        Check "$style hides expired notice" ((Get-DoomPlayerMessageOutput 'BLUE KEY' 0 0 $vp -Style $style).Length -eq 0)
        Check "$style preserves notices on automap" ((Get-DoomPlayerMessageOutput 'BLUE KEY' 1 3 $vp -Style $style).Length -gt 0)
        $present=@{Tic=40;ScreenKind=0;MenuScreen=0;PlayerMessage='BLUE KEY';PlayerMessageTics=100;PlayerMessagePixels=$null}
        $gammaOutput=Get-DoomDisplayMessageOutput $present $vp -GammaNotice 'GAMMA CORRECTION LEVEL 4' -GammaNoticeUntilWallMs 2100 -NowWallMs 100 -Style $style
        $gammaText=[Text.Encoding]::UTF8.GetString($gammaOutput)
        Check "$style shows the active gamma level over a game message" ($gammaText.Contains('GAMMA CORRECTION LEVEL 4') -and -not $gammaText.Contains('BLUE KEY'))
        $expiredOutput=Get-DoomDisplayMessageOutput $present $vp -GammaNotice 'GAMMA CORRECTION LEVEL 4' -GammaNoticeUntilWallMs 100 -NowWallMs 100 -Style $style
        Check "$style restores the game message after the gamma notice expires" ([Text.Encoding]::UTF8.GetString($expiredOutput).Contains('BLUE KEY'))
        $present.ScreenKind=2;$present.MenuScreen=7
        $pauseGammaOutput=Get-DoomDisplayMessageOutput $present $vp -GammaNotice 'GAMMA CORRECTION LEVEL 4' -GammaNoticeUntilWallMs 2100 -NowWallMs 100 -Style $style
        Check "$style shows the gamma level on the pause screen" ([Text.Encoding]::UTF8.GetString($pauseGammaOutput).Contains('GAMMA CORRECTION LEVEL 4'))
        $expiredPauseOutput=Get-DoomDisplayMessageOutput $present $vp -GammaNotice 'GAMMA CORRECTION LEVEL 4' -GammaNoticeUntilWallMs 100 -NowWallMs 100 -Style $style
        Check "$style expires the gamma notice while paused" ($expiredPauseOutput.Length -eq 0)
        $present.MenuScreen=1
        Check "$style hides gamma notices on other menus" ((Get-DoomDisplayMessageOutput $present $vp -GammaNotice 'GAMMA CORRECTION LEVEL 4' -GammaNoticeUntilWallMs 2100 -NowWallMs 100 -Style $style).Length -eq 0)
        $codecs=New-DoomPlayerMessageCodecs $content.Palette.Data $style
        $pixels=Get-DoomPlayerMessagePixels $font ([Text.Encoding]::ASCII.GetBytes('YOU NEED A RED KEY'))
        $bitmapBytes=Get-DoomPlayerMessageOutput 'YOU NEED A RED KEY' 140 0 $vp -Style $style -Pixels $pixels -Codecs $codecs
        if($style -eq 'Classic'){
            Check 'Classic bitmap output occupies multiple readable rows' ([Text.Encoding]::UTF8.GetString($bitmapBytes).Contains("$([char]27)[$($vp.Top+2);$($vp.Left+1)H"))
        }else{
            $notice=[Text.Encoding]::UTF8.GetString($bitmapBytes)
            Check "$style notice preserves complete readable letter shapes" ($notice.Contains('YOU NEED A RED KEY'))
            Check "$style notice has bright style color and black background" ($notice.Contains($(if($style -eq 'Matrix'){'38;2;32;255;80;48;2;0;0;0'}else{'38;2;255;80;80;48;2;0;0;0'})))
        }
        foreach($mode in 'Strips','Batch'){
            $stream=[IO.MemoryStream]::new();$context=New-DoomTerminalOutputContext
            Write-DoomTerminalFrame $context $stream @(@{Bytes=[byte[]]@(65,66)}) ([byte[]]@(1)) ([byte[]]@(2)) -Status $outputBytes -Mode $mode
            $bytes=$stream.ToArray();$stream.Dispose()
            Check "$style $mode overlays notice after render bytes before frame end" ($bytes[1] -eq 65 -and $bytes[2] -eq 66 -and $bytes[3] -eq 27 -and $bytes[-1] -eq 2 -and $bytes.Length -eq $outputBytes.Length+4)
        }
    }
    $directory=Get-DoomSaveDirectory $SaveRoot $wadHash;$tic=0;$initialHash=$null;$initialText=$null
    foreach($kind in 'RedLock','ArmorPickup'){
        $g=New-MessageGame;$p=$g.World.ConsolePlayer
        if($kind -eq 'RedLock'){
            $line=@($g.World.Map.Lines|Where-Object {[int]$_.Special -in 28,33})[0]
            $g.World.SectorAction.DoLocalDoor($line,$p.Mobj)
            Check 'Fixture uses an actual E1M2 red locked door' ($p.Message -ceq [DoomInfo]::Strings.PD_REDK.ToString())
        }else{
            $armor=$g.World.ThingAllocation.SpawnMobj($p.Mobj.X,$p.Mobj.Y,$p.Mobj.Z,[MobjType]::Misc0)
            $g.World.ItemPickup.TouchSpecialThing($armor,$p.Mobj)
            Check 'Real armor pickup supplies message and inventory' ($p.Message -ceq [DoomInfo]::Strings.GOTARMOR.ToString() -and $p.ArmorPoints -eq 100)
        }
        $save=Write-DoomSaveState $g (Join-Path $directory ($kind+'.pds')) $wadHash ('Player notice fixture: '+$kind)
        $archive=Get-DoomReplaySavePath $directory $save.Sha256;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($archive));Copy-Item -LiteralPath $save.Path -Destination $archive
        if($kind -eq 'RedLock'){$initialHash=$save.Sha256;$initialText=$p.Message.ToUpperInvariant()}
        $g=New-DoomGameFromSave (Read-DoomSaveState $archive $wadHash) $content
        $graphics=New-DoomAutomapGraphics $content;$graphics.Discovery.DiscoverMap($g.World.ConsolePlayer)
        $controls.Add(@{Tic=$tic;Action='LoadGame';SaveHash=$save.Sha256})
        if($points.Count -gt 0 -and $points[-1].Tic -eq $tic){$points.RemoveAt($points.Count-1)}
        $points.Add((Get-DoomReplayCheckpoint $g $tic))
        for($step=1;$step -le 175;$step++){
            $mask=if($step -in 35,70){1}else{0};if($mask){$maps.Add(@{Tic=$tic;Mask=$mask})}
            Set-DoomAutomapCommand $g $mask;$commands.Add(@(0,0,0,0));$null=$g.Update($cmd);$tic++
            $graphics.Discovery.DiscoverMap($g.World.ConsolePlayer)
            $p=$g.World.ConsolePlayer;$states.Add(@{Tic=$tic;Segment=$kind;Text=$p.Message;MessageTics=$p.MessageTime;Automap=$g.World.AutoMap.Visible})
            if($step%35 -eq 0){$points.Add((Get-DoomReplayCheckpoint $g $tic))}
        }
        Check "$kind expires after 140 simulation tics" ($p.MessageTime -eq 0)
    }
    $replay=@{Format='pwshDoom.InputReplay';Version=4;WadSha256=$wadHash;Skill=3;Episode=1;Map=2;ContinueCampaign=$true;
        InputCommands=$commands.ToArray();ControlEvents=$controls.ToArray();AutomapCommands=$maps.ToArray();Checkpoints=$points.ToArray();
        SourceFingerprint=(Get-DoomReplaySourceFingerprint);FixtureStates=$states.ToArray();
        Transitions=@(@{Tic=0;State='Level';Episode=1;Map=2},@{Tic=0;State='Level';Episode=1;Map=2},@{Tic=175;State='Level';Episode=1;Map=2});
        Meaning='Real locked-door and armor-pickup handlers invoked to prepare separate save fixtures. Normal save/replay controls then exercise notices and their expiry in world and automap. No navigation or campaign completion evidence.'}
    $null=Write-DoomInputReplay $Fixture $replay
    $simulation=New-DoomSimulation $Wad 3 1 2 -SaveRoot $SaveRoot
    $sequence=Send-DoomSessionAction $simulation @{Action='LoadGame';SaveHash=$initialHash} 0
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($simulation.View.ReadInt32(52) -ne $sequence){
        $generation=$simulation.View.ReadInt32(24);if($generation -gt $simulation.View.ReadInt32(28)){$simulation.View.Write(28,$generation);[void]$simulation.Go.Set()}
        if($watch.Elapsed.TotalSeconds -gt 30){throw 'Message load timed out.'};[Threading.Thread]::Sleep(5)
    }
    $reply=Read-DoomSessionPayload $simulation.View 65536;$s=Read-DoomSimulationSnapshot $simulation $null
    Check 'Actual simulation load publishes saved notice atomically' ($reply.Success -and $s.PlayerMessage -ceq $initialText -and $s.PlayerMessageTics -eq 140)
    $expectedPixels=Get-DoomPlayerMessagePixels $font ([Text.Encoding]::ASCII.GetBytes($initialText))
    Check 'Actual worker transports exact original-font bitmap' ([Linq.Enumerable]::SequenceEqual[byte]($expectedPixels,$s.PlayerMessagePixels))
    for($i=0;$i -lt 140;$i++){
        Send-DoomSimulationCommand $simulation $i @(0,0,0,0) -AutomapMask $(if($i -in 35,70){1}else{0})
        $s=Await-Simulation ($i+1)
        if($i -in 0,34,35,69,70,138,139){Check "Notice clock matches worker tic $($i+1)" ($s.PlayerMessageTics -eq [Math]::Max(0,139-$i))}
        if($i -eq 35){Check 'Actual automap snapshot retains active notice' ($s.ScreenKind -eq 3 -and $s.PlayerMessage -ceq $initialText)}
    }
    Check 'Actual worker clears expired message bytes' ($s.PlayerMessageTics -eq 0 -and $s.PlayerMessage.Length -eq 0)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($simulation){Close-DoomSimulation $simulation};if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();Fixture=$Fixture;SaveRoot=$SaveRoot;Meaning='Real key-lock/pickup handlers; bounded ASCII notice, centered all-style overlay, Strips/Batch ordering, saved-message IPC and 140-tic expiry with actual simulation worker. Save fixtures are not ordinary-input routes.'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
}
"PASS: $($checks.Count) player-message checks."
