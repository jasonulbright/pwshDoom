#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',[string]$CompareRenderer,
    [ValidateRange(1,32)][int]$Workers=7,
    [ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic',
    [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Ascii',
    [ValidateSet('Pairs','ColorState')][string]$AnsiEncoding='Pairs',
    [string]$Report="$PSScriptRoot/../results/render-partitions.json",[switch]$Fuzz,[switch]$Palettes,
    [ValidateRange(1,4)][int]$Episode=1,[ValidateRange(1,9)][int]$Map=1,[ValidateRange(1,5)][int]$Skill=3)
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
    $game.DeferedInitNew([GameSkill]($Skill-1),$Episode,$Map);$null=$game.Update($commands)
    for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    $context=New-FastRenderContext $content $game.World
    $palette=[int[][]]::new(256)
    for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $pool=New-GameRenderPool $context (New-CodecContext $palette) $Workers -Style $Style -GlyphSet $GlyphSet -AnsiEncoding $AnsiEncoding
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
            # Keep the opaque control renders off the serial image context. Fuzz
            # samples neighboring framebuffer rows, so an extra diagnostic frame
            # would otherwise change the history seen by later worker comparisons.
            $fixtureContext=New-FastRenderContext $content $game.World;$fixtureContext.PlaneSpanBoundaries=$context.PlaneSpanBoundaries
            Set-GameRenderSnapshot $fixtureContext $snapshot;Invoke-FastRender $fixtureContext
            [byte[]]$fuzzFixturePixels=$fixtureContext.Pixels.Clone()
            $flags=$snapshot.Actors[0].Flags;$snapshot.Actors[0].Flags=$flags -band (-bnot 0x40000)
            Set-GameRenderSnapshot $fixtureContext $snapshot;Invoke-FastRender $fixtureContext
            for($pixel=0;$pixel -lt 64000;$pixel++){if($fixtureContext.Pixels[$pixel] -ne $fuzzFixturePixels[$pixel]){$opaqueDifferences++}}
            $snapshot.Actors[0].Flags=$flags
            if($opaqueDifferences -eq 0){throw 'The shadow actor fixture did not distinguish an opaque actor.'}
        }
        . "$PSScriptRoot/../src/FastRenderer.ps1"
        $workerInput=$snapshot
        if($Fuzz){
            [byte[]]$endpoint=ConvertTo-GameSnapshotBytes $snapshot
            [double[]]$endpointValues=[double[]]::new($endpoint.Length/8);[Buffer]::BlockCopy($endpoint,0,$endpointValues,0,$endpoint.Length)
            $workerInput=Get-InterpolatedSnapshotBytes $endpointValues $endpointValues 1
        }
        [byte[]]$workerPacket=if($workerInput -is [byte[]]){$workerInput}else{ConvertTo-GameSnapshotBytes $workerInput}
        [int]$unfilteredLength=$workerPacket.Length
        $workerPacket=Add-GameRenderActorWorkerMasks $workerPacket $pool
        [double[]]$workerValues=[double[]]::new($workerPacket.Length/8);[Buffer]::BlockCopy($workerPacket,0,$workerValues,0,$workerPacket.Length)
        if($workerValues[0] -ne 4){throw 'Renderer pool did not receive a NumericV4 actor-visibility packet.'}
        [int]$workerActorCount=$workerValues[5];[int]$workerMaskStart=$workerValues.Length-$workerActorCount
        [long]$includedActorWorkerPairs=0;[long]$allActorWorkerPairs=[long]$workerActorCount*$Workers
        for($actorIndex=0;$actorIndex -lt $workerActorCount;$actorIndex++){
            [long]$mask=$workerValues[$workerMaskStart+$actorIndex]
            for($workerIndex=0;$workerIndex -lt $Workers;$workerIndex++){if(($mask -band (1L -shl $workerIndex)) -ne 0){$includedActorWorkerPairs++}}
        }
        Submit-GameRender $pool $workerPacket -ColumnOffset 17 -RowOffset 5 -FrameNumber 123;Wait-GameRender $pool
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
                if([Convert]::ToBase64String($result.Bytes) -cne [Convert]::ToBase64String($serialBytes)){
                    [int]$pixelMismatchCount=0;[int]$firstPixelMismatch=-1;$pixelDetails=[Collections.Generic.List[string]]::new()
                    for([int]$py=0;$py -lt 200;$py++){
                        for([int]$px=$worker.First;$px -lt $worker.End;$px++){
                            [int]$pixelIndex=$py*320+$px
                            if($result.Pixels[$pixelIndex] -ne $expected[$pixelIndex]){$pixelMismatchCount++;if($firstPixelMismatch -lt 0){$firstPixelMismatch=$pixelIndex};if($pixelDetails.Count -lt 24){$pixelDetails.Add("$pixelIndex`($($pixelIndex%320),$([int]($pixelIndex/320))):$($expected[$pixelIndex])->$($result.Pixels[$pixelIndex])")}}
                        }
                    }
                    throw "Worker Classic output differs at $angle degrees, columns [$($worker.First),$($worker.End)): $pixelMismatchCount pixels; first mismatch index $firstPixelMismatch; pixels $($pixelDetails -join '; ')."
                }
            }
            for($y=0;$y -lt 200;$y++){[Array]::Copy($result.Pixels,$y*320+$worker.First,$actual,$y*320+$worker.First,$worker.End-$worker.First)}
        }
        $differences=0
        for($i=0;$i -lt 64000;$i++){if($actual[$i] -ne $expected[$i]){$differences++}}
        if($differences -ne 0){throw "$differences pixels differ at $angle degrees between serial rendering and $Workers process strips."}
        $checks.Add(@{AngleDegrees=$angle;ComparedPixels=64000;Differences=$differences;Invisibility=$snapshot.ConsolePlayer.Invisibility;OpaqueActorDifferences=$opaqueDifferences;PaletteNumber=$snapshot.ConsolePlayer.PaletteNumber;
            WorkerPacketVersion=$workerValues[0];ActorCount=$workerActorCount;ActorWorkerPairsIncluded=$includedActorWorkerPairs;ActorWorkerPairsSkipped=$allActorWorkerPairs-$includedActorWorkerPairs;UnfilteredPacketBytes=$unfilteredLength;FilteredPacketBytes=$workerPacket.Length})
    }
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Episode=$Episode;Map=$Map;Skill=$Skill;Style=$Style;GlyphSet=$GlyphSet;AnsiEncoding=$AnsiEncoding;Workers=$Workers;FuzzFixture=[bool]$Fuzz;Checks=$checks.ToArray();EncodedStripByteChecks=$checks.Count*$Workers;CharacterStripByteChecks=if($Style -ne 'Classic'){$checks.Count*$Workers}else{0};BaselineRendererSha256=if($CompareRenderer){(Get-FileHash -LiteralPath $CompareRenderer).Hash}else{(Get-FileHash "$PSScriptRoot/../src/FastRenderer.ps1").Hash};Meaning='Exact serial/partition equivalence, including NumericV4 worker visibility masks over the NumericV3 simulation snapshot and drawseg silhouette depth. The host projects each world actor once to identify the process stripes its actual rotated patch overlaps; workers skip other actors before fixed-point projection. Fuzz fixtures explicitly place a shadow demon ahead of the camera and set the player invisibility timer. These are not ordinary gameplay completion evidence. All modes compare encoded bytes against serial encoding at fixed viewports. No vanilla pixel-equivalence claim.'} |
        ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Report
    "PASS: 320,000 pixels match across five views and $Workers uneven process strips."
} catch {[Console]::Error.WriteLine($_.ScriptStackTrace);throw}
finally {if($null -ne $pool){Close-GameRenderPool $pool};if($null -ne $content){$content.Dispose()}}
