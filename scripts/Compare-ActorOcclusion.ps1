#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [Parameter(Mandatory)][string]$InputReplay,
    [Parameter(Mandatory)][string]$Output,
    [string]$Images,
    [ValidateRange(2,1000000)][int]$Tics=280,
    [Alias('SampleLevelTics')][int[]]$SampleInputTics=@(),
    [switch]$AuditCandidateActors,
    [Alias('CandidateAuditLevelTics')][int[]]$CandidateAuditInputTics=@()
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
$InputReplay=[IO.Path]::GetFullPath($InputReplay)
$replay=Get-Content -LiteralPath $InputReplay -Raw|ConvertFrom-Json
$wadHash=(Get-FileHash -LiteralPath $Wad).Hash
$passedReplayReport=($replay.PSObject.Properties.Name -contains 'Passed') -and $replay.Passed
$rawEpisodeOneReplay=($replay.Format -ceq 'pwshDoom.InputReplay' -and $replay.Episode -eq 1 -and $replay.Map -eq 1)
if((-not $passedReplayReport -and -not $rawEpisodeOneReplay) -or $replay.WadSha256 -cne $wadHash -or $replay.InputCommands.Count -lt $Tics){
    throw 'Input must be a passing same-IWAD replay report or a raw E1M1 input prefix with enough commands.'
}
[int[]]$expectedSampleInputTics=if($SampleInputTics.Count){@($SampleInputTics)}else{@(for($inputTic=35;$inputTic -le $Tics;$inputTic+=35){$inputTic})}
if(@($expectedSampleInputTics|Sort-Object -Unique).Count -ne $expectedSampleInputTics.Count){throw 'SampleInputTics must be distinct.'}
foreach($sampleInputTic in $expectedSampleInputTics){if($sampleInputTic -lt 2 -or $sampleInputTic -gt $Tics){throw "Invalid selected input tic: $sampleInputTic"}}
if($CandidateAuditInputTics.Count -and -not $AuditCandidateActors){throw 'CandidateAuditInputTics requires -AuditCandidateActors.'}
[int[]]$candidateAuditInputTics=if($CandidateAuditInputTics.Count){@($CandidateAuditInputTics)}elseif($AuditCandidateActors){@($Tics)}else{@()}
if(@($candidateAuditInputTics|Sort-Object -Unique).Count -ne $candidateAuditInputTics.Count){throw 'CandidateAuditInputTics must be distinct.'}
foreach($auditInputTic in $candidateAuditInputTics){if($auditInputTic -notin $expectedSampleInputTics){throw "Candidate audit input tic $auditInputTic is not a selected sample tic."}}

$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"
$sourcePaths=@('scripts/Compare-ActorOcclusion.ps1','src/FastRenderer.ps1','src/GameHost.ps1','src/RenderLighting.ps1','src/RenderFuzz.ps1')
$sources=@(foreach($path in $sourcePaths){@{Path=$path;Sha256=(Get-FileHash -LiteralPath (Join-Path "$PSScriptRoot/.." $path)).Hash}})
$samples=[Collections.Generic.List[object]]::new()
$maskImages=[Collections.Generic.List[object]]::new()
$content=$null
$failure=$null
$blankSectorListsControl=$false

function Convert-ReferenceFrame {
    param($Reference)
    [byte[]]$pixels=[byte[]]::new(53760)
    [byte[]]$source=$Reference.Screen.Data
    for([int]$y=0;$y -lt 168;$y++){
        [int]$sourceRow=$y
        [int]$targetRow=$y*320
        for([int]$x=0;$x -lt 320;$x++){$pixels[$targetRow+$x]=$source[$x*200+$sourceRow]}
    }
    return ,$pixels
}

function Get-PaletteMismatchCount {
    param([byte[]]$Left,[byte[]]$Right)
    [int]$count=0
    for([int]$i=0;$i -lt 53760;$i++){if($Left[$i] -ne $Right[$i]){$count++}}
    return $count
}

function Invoke-ReferenceRenderAtFuzzSeed {
    param($Reference,$Game,[int]$FuzzSeed)
    # The adopted renderer advances this frame-global sequence while drawing
    # Spectres. Reset it for each same-state control so a changing fuzz phase
    # is not mistaken for a failure to restore the actor lists.
    $Reference.ThreeD.fuzzPos=$FuzzSeed
    $Reference.RenderGame($Game,[Fixed]::One)
}

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
    $game.DeferedInitNew([GameSkill]::Medium,1,1)
    $null=$game.Update($commands)

    $config=[Config]::new()
    $config.video_highresolution=$false
    $config.video_gamescreensize=7
    $config.video_gammacorrection=0
    $reference=[Renderer]::new($config,$content)
    $context=New-FastRenderContext $content $game.World
    $sectorCount=$game.World.Map.Sectors.Length
    $sectorHeads=[object[]]::new($sectorCount)
    for([int]$i=0;$i -lt $sectorCount;$i++){$sectorHeads[$i]=$game.World.Map.Sectors[$i].ThingList}

    for([int]$tic=2;$tic -le $Tics;$tic++){
        $commands[0].Clear()
        $entry=$replay.InputCommands[$tic-2]
        $commands[0].ForwardMove=[sbyte][int]$entry[0]
        $commands[0].SideMove=[sbyte][int]$entry[1]
        $commands[0].AngleTurn=[int16][int]$entry[2]
        $commands[0].Buttons=[byte][int]$entry[3]
        $null=$game.Update($commands)
        if($tic -notin $expectedSampleInputTics){continue}
        [int]$inputTic=$tic
        [int]$levelTic=$game.World.LevelTime
        if($game.State -ne [GameState]::Level){throw "Replay left gameplay at input tic $inputTic ($($game.State), level tic $levelTic)."}

        $snapshot=New-GameRenderSnapshot $game 1
        # Sector actor heads change throughout play as objects spawn, move,
        # and are removed. Capture the endpoint state, not the map-start heads.
        for([int]$i=0;$i -lt $sectorCount;$i++){$sectorHeads[$i]=$game.World.Map.Sectors[$i].ThingList}
        Set-GameRenderSnapshot $context $snapshot
        Invoke-FastRender $context
        [byte[]]$candidateFull=$context.Pixels.Clone()
        $withoutActors=$snapshot.Clone()
        $withoutActors.Actors=[object[]]::new(0)
        Set-GameRenderSnapshot $context $withoutActors
        Invoke-FastRender $context
        [byte[]]$candidateBackground=$context.Pixels.Clone()
        [double[]]$candidateBackgroundDepth=$context.Depth.Clone()
        [int[]]$candidateBackgroundPlaneIds=$context.Planes.Clone()
        Set-GameRenderSnapshot $context $snapshot
        Invoke-FastRender $context
        [byte[]]$candidateRepeat=$context.Pixels.Clone()
        [int]$candidateRepeatDifferences=Get-PaletteMismatchCount $candidateFull $candidateRepeat

        [int]$referenceFuzzSeed=0
        Invoke-ReferenceRenderAtFuzzSeed $reference $game $referenceFuzzSeed
        [byte[]]$referenceFull=Convert-ReferenceFrame $reference
        [int]$fullReferenceVisibleWorldSprites=$reference.ThreeD.visSpriteCount
        $referenceSprites=[Collections.Generic.List[object]]::new()
        for([int]$i=0;$i -lt $reference.ThreeD.visSpriteCount;$i++){
            $sprite=$reference.ThreeD.visSprites[$i]
            $liveActor=$null;$snapshotActor=$null
            [int]$snapshotIndex=0
            $cap=$game.World.Thinkers.Cap;$thinker=$cap.Next
            while(-not [object]::ReferenceEquals($thinker,$cap)){
                if($thinker -is [Mobj] -and -not [object]::ReferenceEquals($thinker,$game.World.ConsolePlayer.Mobj)){
                    $record=$snapshot.Actors[$snapshotIndex]
                    if($thinker.X.Data -eq $sprite.GlobalX.Data -and $thinker.Y.Data -eq $sprite.GlobalY.Data -and
                        $thinker.Z.Data -eq $sprite.GlobalBottomZ.Data -and [int]$thinker.Sprite -eq [int]$record.Sprite -and
                        $thinker.Frame -eq $record.Frame -and $thinker.Flags -eq $record.Flags){
                        $liveActor=$thinker;$snapshotActor=$record;break
                    }
                    $snapshotIndex++
                }
                $thinker=$thinker.Next
            }
            if($null -eq $liveActor){throw "Could not bind reference sprite $i at tic $levelTic to its snapshot mobj."}
            $referenceSprites.Add(@{Sprite=$sprite;LiveActor=$liveActor;SnapshotActor=$snapshotActor;SnapshotIndex=$snapshotIndex})
        }
        try{
            for([int]$i=0;$i -lt $sectorCount;$i++){$game.World.Map.Sectors[$i].ThingList=$null}
            Invoke-ReferenceRenderAtFuzzSeed $reference $game $referenceFuzzSeed
            [byte[]]$referenceBackground=Convert-ReferenceFrame $reference
        }finally{
            for([int]$i=0;$i -lt $sectorCount;$i++){$game.World.Map.Sectors[$i].ThingList=$sectorHeads[$i]}
        }
        Invoke-ReferenceRenderAtFuzzSeed $reference $game $referenceFuzzSeed
        [byte[]]$referenceRepeat=Convert-ReferenceFrame $reference
        [int]$referenceRepeatDifferences=Get-PaletteMismatchCount $referenceFull $referenceRepeat
        [bool]$restored=$true
        for([int]$i=0;$i -lt $sectorCount;$i++){
            if(-not [object]::ReferenceEquals($game.World.Map.Sectors[$i].ThingList,$sectorHeads[$i])){$restored=$false;break}
        }
        if(-not $restored){throw "Reference actor-list control did not restore sector lists at tic $levelTic."}
        if($candidateRepeatDifferences -ne 0 -or $referenceRepeatDifferences -ne 0){
            throw "Render isolation control changed output at tic $levelTic (candidate=$candidateRepeatDifferences, reference=$referenceRepeatDifferences)."
        }

        [byte[]]$referenceMask=[byte[]]::new(53760)
        [byte[]]$candidateMask=[byte[]]::new(53760)
        [int]$referenceActorPixels=0;[int]$candidateActorPixels=0;[int]$intersection=0;[int]$union=0
        [int]$candidateOnly=0;[int]$referenceOnly=0
        [int]$fullMismatch=0;[int]$backgroundMismatch=0;[int]$sharedActorMismatch=0
        [int]$candidateOnlyMismatch=0;[int]$referenceOnlyMismatch=0
        $isolatedSprites=[Collections.Generic.List[object]]::new()
        for([int]$i=0;$i -lt 53760;$i++){
            [bool]$rActor=$referenceFull[$i] -ne $referenceBackground[$i]
            [bool]$cActor=$candidateFull[$i] -ne $candidateBackground[$i]
            if($rActor){$referenceMask[$i]=1;$referenceActorPixels++}
            if($cActor){$candidateMask[$i]=1;$candidateActorPixels++}
            if($rActor -or $cActor){$union++}
            if($rActor -and $cActor){$intersection++}
            if($cActor -and -not $rActor){$candidateOnly++}
            if($rActor -and -not $cActor){$referenceOnly++}
            [bool]$mismatch=$candidateFull[$i] -ne $referenceFull[$i]
            if($mismatch){
                $fullMismatch++
                if($rActor -or $cActor){
                    if($rActor -and $cActor){$sharedActorMismatch++}
                    elseif($rActor){$referenceOnlyMismatch++}
                    else{$candidateOnlyMismatch++}
                }else{$backgroundMismatch++}
            }
        }
        $iou=if($union){$intersection/[double]$union}else{1.0}
        [int]$actorIsolationIndex=0
        foreach($visible in $referenceSprites){
            $sprite=$visible.Sprite;$liveActor=$visible.LiveActor;$snapshotActor=$visible.SnapshotActor
            $singleSnapshot=$snapshot.Clone();$singleSnapshot.Actors=@($snapshotActor)
            Set-GameRenderSnapshot $context $singleSnapshot
            Invoke-FastRender $context
            [byte[]]$candidateSingle=$context.Pixels.Clone()
            $savedSectorNext=$liveActor.SectorNext
            try{
                for([int]$i=0;$i -lt $sectorCount;$i++){$game.World.Map.Sectors[$i].ThingList=$null}
                $liveActor.SectorNext=$null
                $liveActor.Subsector.Sector.ThingList=$liveActor
                Invoke-ReferenceRenderAtFuzzSeed $reference $game $referenceFuzzSeed
                [byte[]]$referenceSingle=Convert-ReferenceFrame $reference
            }finally{
                for([int]$i=0;$i -lt $sectorCount;$i++){$game.World.Map.Sectors[$i].ThingList=$sectorHeads[$i]}
                $liveActor.SectorNext=$savedSectorNext
            }
            [byte[]]$referenceSingleMask=[byte[]]::new(53760)
            [byte[]]$candidateSingleMask=[byte[]]::new(53760)
            [int]$referenceSinglePixels=0;[int]$candidateSinglePixels=0;[int]$singleIntersection=0;[int]$singleUnion=0
            [int]$singleReferenceOnly=0;[int]$singleCandidateOnly=0;[int]$singleSharedMismatch=0
            [int]$singleReferenceOnlyFullMismatch=0;[int]$singleCandidateOnlyFullMismatch=0
            [int]$singleActualMismatch=0
            [int]$referenceOnlyDepthCloser=0;[int]$referenceOnlyDepthTied=0;[int]$referenceOnlyDepthFarther=0;[int]$referenceOnlyDepthInfinite=0
            [int]$referenceOnlyPlaneDepthPixels=0;[int]$referenceOnlyNonPlaneDepthPixels=0
            $depthExamples=[Collections.Generic.List[object]]::new()
            [double]$spriteDistance=10485760.0/[double]$sprite.Scale.Data
            [int]$singleReferenceMinX=320;[int]$singleReferenceMinY=168;[int]$singleReferenceMaxX=-1;[int]$singleReferenceMaxY=-1
            [int]$singleCandidateMinX=320;[int]$singleCandidateMinY=168;[int]$singleCandidateMaxX=-1;[int]$singleCandidateMaxY=-1
            [int]$singleReferenceOnlyMinX=320;[int]$singleReferenceOnlyMinY=168;[int]$singleReferenceOnlyMaxX=-1;[int]$singleReferenceOnlyMaxY=-1
            for([int]$i=0;$i -lt 53760;$i++){
                [bool]$r=$referenceSingle[$i] -ne $referenceBackground[$i]
                [bool]$c=$candidateSingle[$i] -ne $candidateBackground[$i]
                [int]$x=$i%320;[int]$y=[int][Math]::Floor($i/320.0)
                if($r){
                    $referenceSingleMask[$i]=1;$referenceSinglePixels++
                    $singleReferenceMinX=[Math]::Min($singleReferenceMinX,$x);$singleReferenceMaxX=[Math]::Max($singleReferenceMaxX,$x)
                    $singleReferenceMinY=[Math]::Min($singleReferenceMinY,$y);$singleReferenceMaxY=[Math]::Max($singleReferenceMaxY,$y)
                }
                if($c){
                    $candidateSingleMask[$i]=1;$candidateSinglePixels++
                    $singleCandidateMinX=[Math]::Min($singleCandidateMinX,$x);$singleCandidateMaxX=[Math]::Max($singleCandidateMaxX,$x)
                    $singleCandidateMinY=[Math]::Min($singleCandidateMinY,$y);$singleCandidateMaxY=[Math]::Max($singleCandidateMaxY,$y)
                }
                if($r -or $c){$singleUnion++};if($r -and $c){$singleIntersection++}
                if($r -and -not $c){
                    $singleReferenceOnly++
                    $singleReferenceOnlyMinX=[Math]::Min($singleReferenceOnlyMinX,$x);$singleReferenceOnlyMaxX=[Math]::Max($singleReferenceOnlyMaxX,$x)
                    $singleReferenceOnlyMinY=[Math]::Min($singleReferenceOnlyMinY,$y);$singleReferenceOnlyMaxY=[Math]::Max($singleReferenceOnlyMaxY,$y)
                    if($referenceSingle[$i] -ne $candidateSingle[$i]){$singleReferenceOnlyFullMismatch++}
                    [double]$backgroundDepth=$candidateBackgroundDepth[$i]
                    [int]$planeId=$candidateBackgroundPlaneIds[$i]
                    [bool]$depthMatchesPlane=$false
                    if($planeId -gt 0){
                        [int]$planeKind=($planeId-1)-band 1
                        [int]$sectorIndex=($planeId-1)-shr 1
                        $planeSector=$withoutActors.Sectors[$sectorIndex]
                        [double]$planeHeight=if($planeKind){$planeSector.FloorHeight}else{$planeSector.CeilingHeight}
                        [int]$planeHeightData=[Math]::Truncate(65536.0*$planeHeight)
                        [long]$planeHeightDelta=[Math]::Abs([long]$planeHeightData-[long][Math]::Truncate(65536.0*$withoutActors.ConsolePlayer.ViewZ))
                        [long]$planeDistanceWide=($planeHeightDelta*[long]$context.PlaneRowSlopes[$y])-shr 16
                        $planeDistanceWide=$planeDistanceWide-band 0xFFFFFFFFL
                        if($planeDistanceWide -ge 0x80000000L){$planeDistanceWide-=0x100000000L}
                        $depthMatchesPlane=[Math]::Abs(($planeDistanceWide/65536.0)-$backgroundDepth) -le 0.00002
                    }
                    if($depthMatchesPlane){$referenceOnlyPlaneDepthPixels++}else{$referenceOnlyNonPlaneDepthPixels++}
                    if([double]::IsPositiveInfinity($backgroundDepth)){$referenceOnlyDepthInfinite++}
                    elseif($backgroundDepth -lt ($spriteDistance-0.00002)){$referenceOnlyDepthCloser++}
                    elseif([Math]::Abs($backgroundDepth-$spriteDistance) -le 0.00002){$referenceOnlyDepthTied++}
                    else{$referenceOnlyDepthFarther++}
                    if($depthExamples.Count -lt 16){$depthExamples.Add(@{X=$x;Y=$y;CandidateBackgroundDepth=$backgroundDepth;SpriteDistance=$spriteDistance;Delta=$backgroundDepth-$spriteDistance;PlaneId=$planeId;DepthMatchesPlane=$depthMatchesPlane})}
                }
                if($c -and -not $r){$singleCandidateOnly++;if($referenceSingle[$i] -ne $candidateSingle[$i]){$singleCandidateOnlyFullMismatch++}}
                if($r -and $c -and $referenceSingle[$i] -ne $candidateSingle[$i]){$singleSharedMismatch++}
                if(($r -or $c) -and $referenceSingle[$i] -ne $candidateSingle[$i]){$singleActualMismatch++}
            }
            $singleIou=if($singleUnion){$singleIntersection/[double]$singleUnion}else{1.0}
            $singleImage=$null
            if($Images){
                $imagePath=Join-Path $Images ("e1m1-tic{0}-actor{1}-{2}.png" -f $levelTic,$actorIsolationIndex,$sprite.Patch.Name)
                $bitmap=[Drawing.Bitmap]::new(1280,168)
                try{
                    for([int]$y=0;$y -lt 168;$y++){
                        for([int]$x=0;$x -lt 320;$x++){
                            [int]$i=$y*320+$x
                            [bool]$r=$referenceSingleMask[$i] -ne 0;[bool]$c=$candidateSingleMask[$i] -ne 0
                            [int]$referenceColor=if($r){$referenceSingle[$i]}else{0}
                            [int]$candidateColor=if($c){$candidateSingle[$i]}else{0}
                            $bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb([int]$content.Palette.Data[3*$referenceColor],[int]$content.Palette.Data[3*$referenceColor+1],[int]$content.Palette.Data[3*$referenceColor+2]))
                            $bitmap.SetPixel($x+320,$y,[Drawing.Color]::FromArgb([int]$content.Palette.Data[3*$candidateColor],[int]$content.Palette.Data[3*$candidateColor+1],[int]$content.Palette.Data[3*$candidateColor+2]))
                            $maskColor=if($r -and $c){[Drawing.Color]::White}elseif($r){[Drawing.Color]::Red}elseif($c){[Drawing.Color]::Lime}else{[Drawing.Color]::Black}
                            $bitmap.SetPixel($x+640,$y,$maskColor)
                            $refMaskColor=if($r){[Drawing.Color]::White}else{[Drawing.Color]::Black}
                            $candidateMaskColor=if($c){[Drawing.Color]::White}else{[Drawing.Color]::Black}
                            $bitmap.SetPixel($x+960,$y,$refMaskColor)
                        }
                    }
                    $bitmap.Save($imagePath,[Drawing.Imaging.ImageFormat]::Png)
                }finally{$bitmap.Dispose()}
                $singleImage=@{Path=$imagePath;Sha256=(Get-FileHash -LiteralPath $imagePath).Hash;Panels='Reference actor | candidate actor | overlap white / reference-only red / candidate-only green | reference mask'}
                $maskImages.Add(@{LevelTic=$levelTic;ActorIndex=$actorIsolationIndex;Patch=$sprite.Patch.Name;Path=$imagePath;Sha256=$singleImage.Sha256})
            }
            $isolatedSprites.Add(@{
                Patch=$sprite.Patch.Name
                Sprite=[int]$liveActor.Sprite
                Frame=$liveActor.Frame
                Type=[string]$liveActor.Type
                WorldXData=$liveActor.X.Data
                WorldYData=$liveActor.Y.Data
                WorldZData=$liveActor.Z.Data
                ReferenceX1=$sprite.X1
                ReferenceX2=$sprite.X2
                ReferenceScaleData=$sprite.Scale.Data
                ReferenceVisiblePixels=$referenceSinglePixels
                CandidateVisiblePixels=$candidateSinglePixels
                MaskIntersection=$singleIntersection
                MaskUnion=$singleUnion
                MaskIoU=$singleIou
                ReferenceOnlyPixels=$singleReferenceOnly
                CandidateOnlyPixels=$singleCandidateOnly
                SharedMaskPaletteMismatches=$singleSharedMismatch
                ReferenceOnlyFullFrameMismatchPixels=$singleReferenceOnlyFullMismatch
                CandidateOnlyFullFrameMismatchPixels=$singleCandidateOnlyFullMismatch
                ActualMismatchPixelsInActorUnion=$singleActualMismatch
                ReferenceBounds=@($singleReferenceMinX,$singleReferenceMinY,$singleReferenceMaxX,$singleReferenceMaxY)
                CandidateBounds=@($singleCandidateMinX,$singleCandidateMinY,$singleCandidateMaxX,$singleCandidateMaxY)
                ReferenceOnlyBounds=@($singleReferenceOnlyMinX,$singleReferenceOnlyMinY,$singleReferenceOnlyMaxX,$singleReferenceOnlyMaxY)
                SpriteDistance=$spriteDistance
                ReferenceOnlyDepthCloserPixels=$referenceOnlyDepthCloser
                ReferenceOnlyDepthTiedPixels=$referenceOnlyDepthTied
                ReferenceOnlyDepthFartherPixels=$referenceOnlyDepthFarther
                ReferenceOnlyDepthInfinitePixels=$referenceOnlyDepthInfinite
                ReferenceOnlyPlaneDepthPixels=$referenceOnlyPlaneDepthPixels
                ReferenceOnlyNonPlaneDepthPixels=$referenceOnlyNonPlaneDepthPixels
                ReferenceOnlyDepthExamples=$depthExamples.ToArray()
                CandidateActorRecordIndex=$visible.SnapshotIndex
                Image=$singleImage
            })
            $actorIsolationIndex++
        }
        $candidateActorAudit=[Collections.Generic.List[object]]::new()
        if($AuditCandidateActors -and $inputTic -in $candidateAuditInputTics){
            $liveActors=[Collections.Generic.List[object]]::new();$cap=$game.World.Thinkers.Cap;$thinker=$cap.Next
            while(-not [object]::ReferenceEquals($thinker,$cap)){
                if($thinker -is [Mobj] -and -not [object]::ReferenceEquals($thinker,$game.World.ConsolePlayer.Mobj)){$liveActors.Add($thinker)}
                $thinker=$thinker.Next
            }
            if($liveActors.Count -ne $snapshot.Actors.Count){throw 'Candidate actor audit could not align snapshot actors to the live thinker list.'}
            for([int]$actorIndex=0;$actorIndex -lt $snapshot.Actors.Count;$actorIndex++){
                $singleSnapshot=$snapshot.Clone();$singleSnapshot.Actors=@($snapshot.Actors[$actorIndex])
                Set-GameRenderSnapshot $context $singleSnapshot
                Invoke-FastRender $context
                $live=$liveActors[$actorIndex];$record=$snapshot.Actors[$actorIndex]
                [byte[]]$singlePixels=$context.Pixels.Clone()
                [int]$affected=0;[int]$minX=320;[int]$minY=168;[int]$maxX=-1;[int]$maxY=-1
                for([int]$i=0;$i -lt 53760;$i++){
                    if($singlePixels[$i] -ne $candidateBackground[$i]){
                        $affected++;[int]$x=$i%320;[int]$y=[int][Math]::Floor($i/320.0)
                        $minX=[Math]::Min($minX,$x);$maxX=[Math]::Max($maxX,$x);$minY=[Math]::Min($minY,$y);$maxY=[Math]::Max($maxY,$y)
                    }
                }
                if($affected -gt 0){
                    $frame=$content.Sprites.spriteDefs[$record.Sprite].Frames[$record.Frame -band 0x7F]
                    $patchName=if($null -ne $frame -and $frame.Patches.Count){$frame.Patches[0].Name}else{$null}
                    $candidateActorAudit.Add(@{ActorIndex=$actorIndex;Type=[string]$live.Type;Sprite=[int]$record.Sprite;Patch=$patchName;Frame=$record.Frame;X=$record.X;Y=$record.Y;Z=$record.Z;AffectedPixels=$affected;Bounds=@($minX,$minY,$maxX,$maxY)})
                }
            }
        }
        $sample=[ordered]@{
            InputTic=$inputTic
            LevelTic=$levelTic
            ActorCount=@($snapshot.Actors).Count
            ReferenceVisibleWorldSprites=$fullReferenceVisibleWorldSprites
            ReferenceActorAffectedPixels=$referenceActorPixels
            CandidateActorAffectedPixels=$candidateActorPixels
            ActorMaskIntersection=$intersection
            ActorMaskUnion=$union
            ActorMaskIoU=$iou
            CandidateOnlyActorPixels=$candidateOnly
            ReferenceOnlyActorPixels=$referenceOnly
            FullSceneMismatchPixels=$fullMismatch
            BackgroundMismatchPixels=$backgroundMismatch
            SharedActorRegionMismatchPixels=$sharedActorMismatch
            CandidateOnlyRegionMismatchPixels=$candidateOnlyMismatch
            ReferenceOnlyRegionMismatchPixels=$referenceOnlyMismatch
            IndividuallyIsolatedSprites=$isolatedSprites.ToArray()
            CandidateActorsWithAffectedPixels=$candidateActorAudit.ToArray()
            CandidateIsolationRepeatDifferences=$candidateRepeatDifferences
            ReferenceIsolationRepeatDifferences=$referenceRepeatDifferences
            SectorListsRestored=$restored
            ReferenceActorMaskSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($referenceMask))
            CandidateActorMaskSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($candidateMask))
        }

        if($Images){
            $imagePath=Join-Path $Images ("e1m1-tic{0}-actor-masks.png" -f $levelTic)
            $bitmap=[Drawing.Bitmap]::new(1280,168)
            try{
                for([int]$y=0;$y -lt 168;$y++){
                    for([int]$x=0;$x -lt 320;$x++){
                        [int]$i=$y*320+$x
                        [bool]$r=$referenceMask[$i] -ne 0;[bool]$c=$candidateMask[$i] -ne 0
                        $colors=@(
                            $(if($r){[Drawing.Color]::White}else{[Drawing.Color]::Black}),
                            $(if($c){[Drawing.Color]::White}else{[Drawing.Color]::Black}),
                            $(if($r -and $c){[Drawing.Color]::White}else{[Drawing.Color]::Black}),
                            $(if($c -and -not $r){[Drawing.Color]::Lime}else{if($r -and -not $c){[Drawing.Color]::Red}else{[Drawing.Color]::Black}})
                        )
                        for([int]$panel=0;$panel -lt 4;$panel++){$bitmap.SetPixel($x+$panel*320,$y,$colors[$panel])}
                    }
                }
                $bitmap.Save($imagePath,[Drawing.Imaging.ImageFormat]::Png)
            }finally{$bitmap.Dispose()}
            $maskImages.Add(@{LevelTic=$levelTic;Path=$imagePath;Sha256=(Get-FileHash -LiteralPath $imagePath).Hash;Panels='Reference mask | candidate mask | intersection | candidate-only green / reference-only red'})
        }
        $samples.Add($sample)
        Write-Host ("tic {0}: actor-mask IoU {1:P1}; mismatch background/shared/candidate-only/reference-only {2}/{3}/{4}/{5}" -f $levelTic,$iou,$backgroundMismatch,$sharedActorMismatch,$candidateOnlyMismatch,$referenceOnlyMismatch)
    }
    $blankSectorListsControl=$true
}catch{
    $failure=$_.ToString()+"`n"+$_.ScriptStackTrace
    throw
}finally{
    if($content){$content.Dispose()}
    [ordered]@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o')
        Episode=1
        Map=1
        Skill=3
        Tics=$Tics
        InputTicEndpoint=$Tics
        SampleInterval=35
        SampleInputTics=$expectedSampleInputTics
        CandidateAuditInputTics=$candidateAuditInputTics
        InputReplay=$InputReplay
        InputReplaySha256=(Get-FileHash -LiteralPath $InputReplay).Hash
        InputReplayValidation=if($passedReplayReport){'Passing replay report'}else{'Raw E1M1 input prefix; requested endpoints checked for gameplay state'}
        WadSha256=$wadHash
        BundleSha256=(Get-FileHash -LiteralPath $bundle).Hash
        Sources=$sources
        SourcesChangedDuringRun=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash -LiteralPath (Join-Path "$PSScriptRoot/.." $_.Path)).Hash}|ForEach-Object {$_.Path})
        SameStateIsolationControlsPassed=($blankSectorListsControl -and $samples.Count -eq $expectedSampleInputTics.Count)
        Samples=$samples.ToArray()
        MaskImages=$maskImages.ToArray()
        Error=$failure
        Meaning='Compares world-actor-affected pixel masks at selected recorded input-command indices by rerendering the exact same saved-replay states with world actors suppressed in each renderer. InputTic is distinct from in-game LevelTic, which can reset after death. Player weapon, HUD, geometry, and other scene state remain. This localizes full-scene differences to broad background, shared actor-affected, or renderer-exclusive actor-affected regions. It is adopted-reference parity evidence, not original-executable validation, gameplay completion, or performance.'
    }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
}

if($failure){throw 'Actor-isolation comparison failed; the partial report is retained.'}
if(-not $blankSectorListsControl -or $samples.Count -ne $expectedSampleInputTics.Count){throw 'The expected actor-isolation sample set was not fully analyzed.'}
"Recorded $($samples.Count) actor-isolation comparisons."
