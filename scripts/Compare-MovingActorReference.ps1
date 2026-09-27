#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [ValidateRange(1,4)][int]$Episode=1,
    [ValidateRange(1,9)][int]$Map=1,
    [ValidateRange(1,700)][int]$Tics=140,
    [ValidateRange(1,70)][int]$Interval=35,
    [ValidateRange(1,32)][int]$Workers=16,
    [string]$InputReplay,
    [string]$Images,
    [Parameter(Mandatory)][string]$Output
)

$ErrorActionPreference='Stop'
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Output))
if($Images){
    $Images=[IO.Path]::GetFullPath($Images)
    if(Test-Path -LiteralPath $Images){throw 'Use a fresh image directory.'}
    [void][IO.Directory]::CreateDirectory($Images)
    Add-Type -AssemblyName System.Drawing
}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"

$content=$null
$failure=$null
$samples=[Collections.Generic.List[object]]::new()
$imagesWritten=[Collections.Generic.List[object]]::new()
$wadHash=(Get-FileHash -LiteralPath $Wad).Hash
$replayPath=$null
$replayHash=$null
$replayData=$null
if($InputReplay){
    if($Episode -ne 1 -or $Map -ne 1){throw 'The retained E1M1 replay can only be used for Episode 1 Map 1.'}
    $replayPath=[IO.Path]::GetFullPath($InputReplay)
    $replayData=Get-Content -LiteralPath $replayPath -Raw|ConvertFrom-Json
    $replayHash=(Get-FileHash -LiteralPath $replayPath).Hash
    if(-not $replayData.Passed -or $replayData.WadSha256 -cne $wadHash -or $replayData.InputCommands.Count -lt ($Tics-1)){
        throw 'Input replay must be a passing same-IWAD report with enough recorded commands.'
    }
}
$sourcePaths=@('scripts/Compare-MovingActorReference.ps1','src/FastRenderer.ps1','src/GameHost.ps1','src/RenderLighting.ps1','src/RenderFuzz.ps1')
$sources=@(foreach($path in $sourcePaths){@{Path=$path;Sha256=(Get-FileHash -LiteralPath (Join-Path "$PSScriptRoot/.." $path)).Hash}})

try{
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode
    $options.GameVersion=$content.Wad.GameVersion
    $options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options)
    $commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt $commands.Length;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,$Episode,$Map)
    $null=$game.Update($commands)

    $config=[Config]::new()
    $config.video_highresolution=$false
    $config.video_gamescreensize=7
    $config.video_gammacorrection=0
    $reference=[Renderer]::new($config,$content)
    $context=New-FastRenderContext $content $game.World
    $boundaries=[int[]]::new($Workers)
    for([int]$i=1;$i -le $Workers;$i++){$boundaries[$i-1]=[int][Math]::Floor($i*320.0/$Workers)}
    $context.PlaneSpanBoundaries=$boundaries
    $firstActorHash=$null
    $firstVisibleSpriteHash=$null
    $firstVisiblePositionHash=$null
    [byte[]]$previousMismatchMask=$null

    for([int]$tic=2;$tic -le $Tics;$tic++){
        $commands[0].Clear()
        if($replayData){
            $entry=$replayData.InputCommands[$tic-2]
            $commands[0].ForwardMove=[sbyte][int]$entry[0]
            $commands[0].SideMove=[sbyte][int]$entry[1]
            $commands[0].AngleTurn=[int16][int]$entry[2]
            $commands[0].Buttons=[byte][int]$entry[3]
        }elseif($tic -eq 71){$commands[0].Buttons=[TicCmdButtons]::Attack}
        $null=$game.Update($commands)
        [int]$levelTic=$game.World.LevelTime
        if(($levelTic % $Interval) -ne 0 -and $levelTic -ne $Tics){continue}
        if($game.State -ne [GameState]::Level){throw "Idle-input fixture left gameplay at level tic $levelTic ($($game.State))."}

        $snapshot=New-GameRenderSnapshot $game 1
        $actorJson=ConvertTo-Json -InputObject @($snapshot.Actors) -Depth 4 -Compress
        $actorHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($actorJson)))
        if($null -eq $firstActorHash){$firstActorHash=$actorHash}

        Set-GameRenderSnapshot $context $snapshot
        Invoke-FastRender $context
        [byte[]]$candidate=$context.Pixels.Clone()
        $reference.RenderGame($game,[Fixed]::One)
        [int]$visibleWorldSprites=$reference.ThreeD.visSpriteCount
        $visibleSpriteStates=[Collections.Generic.List[object]]::new()
        for([int]$i=0;$i -lt $visibleWorldSprites;$i++){
            $sprite=$reference.ThreeD.visSprites[$i]
            $visibleSpriteStates.Add(@{
                Patch=$sprite.Patch.Name
                X1=$sprite.X1
                X2=$sprite.X2
                ScaleData=$sprite.Scale.Data
                GlobalX=$sprite.GlobalX.Data
                GlobalY=$sprite.GlobalY.Data
                BottomZ=$sprite.GlobalBottomZ.Data
                Flags=[int]$sprite.MobjFlags
            })
        }
        $visibleSpriteJson=ConvertTo-Json -InputObject $visibleSpriteStates.ToArray() -Depth 4 -Compress
        $visibleSpriteHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($visibleSpriteJson)))
        if($null -eq $firstVisibleSpriteHash){$firstVisibleSpriteHash=$visibleSpriteHash}
        $visiblePositionStates=@($visibleSpriteStates.ToArray()|ForEach-Object {@{X1=$_.X1;X2=$_.X2;ScaleData=$_.ScaleData;GlobalX=$_.GlobalX;GlobalY=$_.GlobalY;BottomZ=$_.BottomZ}})
        $visiblePositionJson=ConvertTo-Json -InputObject $visiblePositionStates -Depth 3 -Compress
        $visiblePositionHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($visiblePositionJson)))
        if($null -eq $firstVisiblePositionHash){$firstVisiblePositionHash=$visiblePositionHash}

        [int]$sceneDifferences=0
        [int]$hudDifferences=0
        [long]$absoluteRgbError=0
        [byte[]]$mismatchMask=[byte[]]::new(53760)
        for([int]$y=0;$y -lt 200;$y++){
            for([int]$x=0;$x -lt 320;$x++){
                [int]$index=$y*320+$x
                [int]$actual=$candidate[$index]
                [int]$expected=$reference.Screen.Data[$x*200+$y]
                if($actual -ne $expected){if($y -lt 168){$sceneDifferences++;$mismatchMask[$index]=1}else{$hudDifferences++}}
                $absoluteRgbError += [Math]::Abs([int]$content.Palette.Data[3*$actual]-[int]$content.Palette.Data[3*$expected])
                $absoluteRgbError += [Math]::Abs([int]$content.Palette.Data[3*$actual+1]-[int]$content.Palette.Data[3*$expected+1])
                $absoluteRgbError += [Math]::Abs([int]$content.Palette.Data[3*$actual+2]-[int]$content.Palette.Data[3*$expected+2])
            }
        }
        $changedMismatchLocations=$null
        if($null -ne $previousMismatchMask){
            [int]$changedMismatchLocations=0
            for([int]$i=0;$i -lt $mismatchMask.Length;$i++){if($mismatchMask[$i] -ne $previousMismatchMask[$i]){$changedMismatchLocations++}}
        }
        $mismatchHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($mismatchMask))
        $imageInfo=$null
        if($Images){
            $imagePath=Join-Path $Images ("e{0}m{1}-tic{2}.png" -f $Episode,$Map,$snapshot.Tic)
            $bitmap=[Drawing.Bitmap]::new(960,200)
            try{
                for([int]$y=0;$y -lt 200;$y++){
                    for([int]$x=0;$x -lt 320;$x++){
                        [int]$index=$y*320+$x
                        [int]$actual=$candidate[$index]
                        [int]$expected=$reference.Screen.Data[$x*200+$y]
                        [int]$r=[int]$content.Palette.Data[3*$expected]
                        [int]$g=[int]$content.Palette.Data[3*$expected+1]
                        [int]$b=[int]$content.Palette.Data[3*$expected+2]
                        $bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb($r,$g,$b))
                        $r=[int]$content.Palette.Data[3*$actual]
                        $g=[int]$content.Palette.Data[3*$actual+1]
                        $b=[int]$content.Palette.Data[3*$actual+2]
                        $bitmap.SetPixel($x+320,$y,[Drawing.Color]::FromArgb($r,$g,$b))
                        $maskValue=if($actual -eq $expected){0}else{255}
                        $bitmap.SetPixel($x+640,$y,[Drawing.Color]::FromArgb($maskValue,$maskValue,$maskValue))
                    }
                }
                $bitmap.Save($imagePath,[Drawing.Imaging.ImageFormat]::Png)
            }finally{$bitmap.Dispose()}
            $imageInfo=@{Path=[IO.Path]::GetFullPath($imagePath);Sha256=(Get-FileHash -LiteralPath $imagePath).Hash;Panels='Reference | Numeric | differing-pixel mask'}
            $imagesWritten.Add($imageInfo)
        }
        $samples.Add([ordered]@{
            LevelTic=$snapshot.Tic
            PlayerHealth=$snapshot.ConsolePlayer.Health
            ActorCount=@($snapshot.Actors).Count
            ReferenceVisibleWorldSprites=$visibleWorldSprites
            VisibleSpriteStateSha256=$visibleSpriteHash
            VisibleSpriteStateChangedSinceFirst=($visibleSpriteHash -cne $firstVisibleSpriteHash)
            VisibleSpritePositionSha256=$visiblePositionHash
            VisibleSpritePositionChangedSinceFirst=($visiblePositionHash -cne $firstVisiblePositionHash)
            ActorStateSha256=$actorHash
            ActorStateChangedSinceFirst=($actorHash -cne $firstActorHash)
            SceneComparedPixels=53760
            SceneDifferentIndices=$sceneDifferences
            SceneMismatchMaskSha256=$mismatchHash
            SceneMismatchLocationsChangedSincePrevious=$changedMismatchLocations
            HudComparedPixels=10240
            HudDifferentIndices=$hudDifferences
            MeanAbsoluteRgbChannelError=$absoluteRgbError/192000.0
            Image=$imageInfo
        })
        Write-Host ("Tic {0}: actors={1}; scene differences={2}/53760; HUD differences={3}/10240" -f $snapshot.Tic,@($snapshot.Actors).Count,$sceneDifferences,$hudDifferences)
        $previousMismatchMask=$mismatchMask
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}
finally{
    if($content){$content.Dispose()}
    [ordered]@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o')
        Episode=$Episode
        Map=$Map
        Skill=3
        Input=if($replayData){"Recorded command prefix from $replayPath; not a newly designed route."}else{'One pistol-attack tic after 70 idle level tics; zero input otherwise. No navigation or exit automation.'}
        InputReplaySha256=$replayHash
        RequestedTics=$Tics
        Interval=$Interval
        Workers=$Workers
        WadSha256=$wadHash
        BundleSha256=(Get-FileHash -LiteralPath $bundle).Hash
        Sources=$sources
        SourcesChangedDuringRun=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash -LiteralPath (Join-Path "$PSScriptRoot/.." $_.Path)).Hash}|ForEach-Object {$_.Path})
        Samples=$samples.ToArray()
        Images=$imagesWritten.ToArray()
        Error=$failure
        Meaning='Bounded dynamic actor/scene comparison between the numeric PowerShell renderer and the adopted PowerShell reference at matching live simulation states. Input may be a validated existing replay prefix or a single alerting attack followed by idle input. Pixel counts are full-scene diagnostics, not actor-only attribution, an original-executable comparison, map completion, worker-process equivalence, or a performance claim.'
    }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
}

if($failure){throw 'Dynamic renderer comparison failed; the partial report is retained.'}
"Recorded $($samples.Count) dynamic renderer comparisons."
