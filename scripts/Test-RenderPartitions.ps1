#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',[string]$CompareRenderer,
    [ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic',
    [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Ascii',
    [ValidateSet('Pairs','ColorState')][string]$AnsiEncoding='Pairs',
    [string]$Report="$PSScriptRoot/../results/render-partitions.json",[switch]$Fuzz,[switch]$Palettes)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
. "$PSScriptRoot/../src/CharacterCodec.ps1"
. "$PSScriptRoot/../src/TerminalCodec.ps1";. "$PSScriptRoot/../src/AnsiColorState.ps1"
. "$PSScriptRoot/../src/PaletteCodec.ps1"
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/GameProcesses.ps1"
$content=$null;$pool=$null;$checks=[Collections.Generic.List[object]]::new()
try {
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    $context=New-FastRenderContext $content $game.World
    $palette=[int[][]]::new(256)
    for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $pool=New-GameRenderPool $context (New-CodecContext $palette) 7 -Style $Style -GlyphSet $GlyphSet -AnsiEncoding $AnsiEncoding
    $classicCodec=if($AnsiEncoding -eq 'ColorState'){New-AnsiColorStateContext $palette}else{New-CodecContext $palette}
    $characterCodec=if($Style -ne 'Classic'){New-CharacterCodecContext $palette $Style -GlyphSet $GlyphSet}else{$null}
    foreach($angle in 0,37,89,173,269) {
        $snapshot=New-GameRenderSnapshot $game;$snapshot.ConsolePlayer.Mobj.Angle=$angle*[Math]::PI/180
        if($Palettes){
            $snapshot.ConsolePlayer.PaletteNumber=@{0=0;37=3;89=8;173=12;269=13}[$angle]
            $rgb=Get-DoomPaletteRgb $content.Palette.Data $snapshot.ConsolePlayer.PaletteNumber
            $classicCodec=if($AnsiEncoding -eq 'ColorState'){New-AnsiColorStateContext $rgb}else{New-CodecContext $rgb}
            if($Style -ne 'Classic'){$characterCodec=New-CharacterCodecContext $rgb $Style -GlyphSet $GlyphSet}
        }
        if($Fuzz){
            $snapshot.ConsolePlayer.Invisibility=@{0=129;37=128;89=120;173=8;269=0}[$angle]
            $shadow=$snapshot.Actors[0];$shadow.Flags=$shadow.Flags -bor 0x40000;$shadow.Sprite=[int][Sprite]::SARG;$shadow.Frame=0
            $a=$snapshot.ConsolePlayer.Mobj.Angle;$shadow.X=$snapshot.ConsolePlayer.Mobj.X+32*[Math]::Cos($a)
            $shadow.Y=$snapshot.ConsolePlayer.Mobj.Y+32*[Math]::Sin($a);$shadow.Z=$snapshot.ConsolePlayer.ViewZ-41
        }
        if($angle -eq 37){$snapshot.ConsolePlayer.ExtraLight=2;foreach($sector in $snapshot.Sectors){$sector.LightLevel=255}}
        if($CompareRenderer){. $CompareRenderer}
        $serial=$context.Clone();Set-GameRenderSnapshot $serial $snapshot;Invoke-FastRender $serial
        $expected=[byte[]]$serial.Pixels.Clone()
        $opaqueDifferences=0
        if($Fuzz){
            $flags=$snapshot.Actors[0].Flags;$snapshot.Actors[0].Flags=$flags -band (-bnot 0x40000)
            Invoke-FastRender $serial
            for($pixel=0;$pixel -lt 64000;$pixel++){if($serial.Pixels[$pixel] -ne $expected[$pixel]){$opaqueDifferences++}}
            $snapshot.Actors[0].Flags=$flags
            if($opaqueDifferences -eq 0){throw 'The shadow actor fixture did not distinguish an opaque actor.'}
        }
        . "$PSScriptRoot/../src/FastRenderer.ps1"
        Submit-GameRender $pool $snapshot -ColumnOffset 17 -RowOffset 5 -FrameNumber 123;Wait-GameRender $pool
        $actual=[byte[]]::new(64000)
        for($i=0;$i -lt $pool.Count;$i++) {
            $worker=$pool.Workers[$i];$result=$pool.Results[$i]
            $startColumn=if($Style -eq 'Classic'){$worker.First}else{$worker.First/2}
            $prefix="$([char]27)[6;$($startColumn+18)H"
            if(-not [Text.Encoding]::UTF8.GetString($result.Bytes).StartsWith($prefix)){throw 'Worker did not apply the requested viewport origin.'}
            if($result.Tic -ne $snapshot.Tic){throw 'Worker returned a different simulation tic.'}
            if($result.PaletteNumber -ne $snapshot.ConsolePlayer.PaletteNumber){throw 'Worker selected a different palette.'}
            if($Style -ne 'Classic'){
                $serialBytes=ConvertTo-CharacterStrip $expected 320 200 $worker.First $worker.End $characterCodec -ColumnOffset 17 -RowOffset 5 -FrameNumber 123
                if([Convert]::ToBase64String($result.Bytes) -cne [Convert]::ToBase64String($serialBytes)){throw 'Worker character output differs from encoding the serial reference image.'}
            }else{
                $serialBytes=if($AnsiEncoding -eq 'ColorState'){ConvertTo-AnsiColorStateStrip $expected 320 200 $worker.First $worker.End $classicCodec -ColumnOffset 17 -RowOffset 5}
                    else{ConvertTo-AnsiStrip $expected 320 200 $worker.First $worker.End $classicCodec -ColumnOffset 17 -RowOffset 5}
                if([Convert]::ToBase64String($result.Bytes) -cne [Convert]::ToBase64String($serialBytes)){throw 'Worker Classic output differs from the selected serial encoder.'}
            }
            for($y=0;$y -lt 200;$y++){[Array]::Copy($result.Pixels,$y*320+$worker.First,$actual,$y*320+$worker.First,$worker.End-$worker.First)}
        }
        $differences=0
        for($i=0;$i -lt 64000;$i++){if($actual[$i] -ne $expected[$i]){$differences++}}
        if($differences -ne 0){throw "$differences pixels differ at $angle degrees between serial rendering and seven process strips."}
        $checks.Add(@{AngleDegrees=$angle;ComparedPixels=64000;Differences=$differences;Invisibility=$snapshot.ConsolePlayer.Invisibility;OpaqueActorDifferences=$opaqueDifferences;PaletteNumber=$snapshot.ConsolePlayer.PaletteNumber})
    }
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Style=$Style;GlyphSet=$GlyphSet;AnsiEncoding=$AnsiEncoding;FuzzFixture=[bool]$Fuzz;Checks=$checks.ToArray();EncodedStripByteChecks=35;CharacterStripByteChecks=if($Style -ne 'Classic'){35}else{0};BaselineRendererSha256=if($CompareRenderer){(Get-FileHash -LiteralPath $CompareRenderer).Hash}else{(Get-FileHash "$PSScriptRoot/../src/FastRenderer.ps1").Hash};Meaning='Exact serial/partition equivalence, including binary assets and NumericV3 snapshots. Fuzz fixtures explicitly place a shadow demon ahead of the camera and set the player invisibility timer; these are not ordinary gameplay completion evidence. All modes compare encoded bytes against serial encoding at a fixed time and viewport. No vanilla pixel-equivalence claim.'} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Report
    'PASS: 320,000 pixels match across five views and seven uneven process strips.'
} catch {[Console]::Error.WriteLine($_.ScriptStackTrace);throw}
finally {if($null -ne $pool){Close-GameRenderPool $pool};if($null -ne $content){$content.Dispose()}}
