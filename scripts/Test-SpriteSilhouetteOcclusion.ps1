#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Output="$PSScriptRoot/../results/sprite-silhouette-occlusion.json"
)

$ErrorActionPreference='Stop'
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Output))
$root=Split-Path $PSScriptRoot
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"; . $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"
$content=$null
$failure=$null
$affectedPixels=0
$repeatFrameDifferences=0
$clipRecordReused=$false
$clipBuffersReused=$false
$camera=@{X=355.806793212891;Y=-3259.86231994629;ViewZ=40.6085205078125;AngleDegrees=184.921875}
$target=@{Type='Misc2';Sprite='BON1';X=144.0;Y=-3136.0;Z=-8.0}
try{
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$game.DeferedInitNew([GameSkill]::Medium,1,1)
    $commands=[TicCmd[]]::new(4);for($i=0;$i -lt $commands.Length;$i++){$commands[$i]=[TicCmd]::new()};$null=$game.Update($commands)
    $context=New-FastRenderContext $content $game.World
    $snapshot=New-GameRenderSnapshot $game 1
    $snapshot.ConsolePlayer.Mobj.X=$camera.X
    $snapshot.ConsolePlayer.Mobj.Y=$camera.Y
    $snapshot.ConsolePlayer.Mobj.Angle=$camera.AngleDegrees*[Math]::PI/180
    $snapshot.ConsolePlayer.ViewZ=$camera.ViewZ
    $cameraSubsector=[Geometry]::PointInSubsector([Fixed]::FromDouble($camera.X),[Fixed]::FromDouble($camera.Y),$game.World.Map)
    $snapshot.ConsolePlayer.SectorLight=$cameraSubsector.Sector.LightLevel
    $targetSprite=[int][Enum]::Parse([Sprite],$target.Sprite)
    $targetActors=@($snapshot.Actors|Where-Object {$_.X -eq $target.X -and $_.Y -eq $target.Y -and $_.Z -eq $target.Z -and $_.Sprite -eq $targetSprite})
    if($targetActors.Count -ne 1){throw "Expected one target $($target.Sprite) actor at the recorded E1M1 location; found $($targetActors.Count)."}

    $background=$snapshot.Clone();$background.Actors=[object[]]::new(0)
    Set-GameRenderSnapshot $context $background;Invoke-FastRender $context
    [byte[]]$backgroundPixels=$context.Pixels.Clone()
    $isolated=$snapshot.Clone();$isolated.Actors=$targetActors
    Set-GameRenderSnapshot $context $isolated;Invoke-FastRender $context
    for([int]$i=0;$i -lt 53760;$i++){if($context.Pixels[$i] -ne $backgroundPixels[$i]){$affectedPixels++}}
    if($affectedPixels -ne 0){throw "Occluded $($target.Sprite) actor still changes $affectedPixels scene pixels."}
    [byte[]]$firstPixels=$context.Pixels.Clone()
    [int]$activeClipColumn=-1
    for([int]$x=0;$x -lt 320;$x++){if($context.SpriteClipCounts[$x] -gt 0){$activeClipColumn=$x;break}}
    if($activeClipColumn -lt 0){throw 'The target view produced no reusable sprite clip records.'}
    $firstClipRecord=$context.SpriteClipWalls[$activeClipColumn][0]
    $clipTopBuffer=$context.ActorClipTop;$clipBottomBuffer=$context.ActorClipBottom
    Invoke-FastRender $context
    for([int]$i=0;$i -lt $firstPixels.Length;$i++){if($context.Pixels[$i] -ne $firstPixels[$i]){$repeatFrameDifferences++}}
    $clipRecordReused=[object]::ReferenceEquals($firstClipRecord,$context.SpriteClipWalls[$activeClipColumn][0])
    $clipBuffersReused=[object]::ReferenceEquals($clipTopBuffer,$context.ActorClipTop) -and [object]::ReferenceEquals($clipBottomBuffer,$context.ActorClipBottom)
    if($repeatFrameDifferences -ne 0){throw "A repeated identical render differs by $repeatFrameDifferences pixels."}
    if(-not $clipRecordReused -or -not $clipBuffersReused){throw 'The repeated render did not reuse its clip records and actor buffers.'}
}catch{
    $failure=$_.ToString()+"`n"+$_.ScriptStackTrace
    throw
}finally{
    $rendererPath=Join-Path $root 'src/FastRenderer.ps1'
    $fuzzPath=Join-Path $root 'src/RenderFuzz.ps1'
    [ordered]@{
        FinishedUtc=[DateTime]::UtcNow.ToString('o')
        Map='E1M1'
        Camera=$camera
        OccludedActor=$target
        ChangedScenePixels=$affectedPixels
        ExpectedChangedScenePixels=0
        RepeatedFrameDifferences=$repeatFrameDifferences
        ExpectedRepeatedFrameDifferences=0
        ClipRecordReused=$clipRecordReused
        ActorClipBuffersReused=$clipBuffersReused
        Passed=($null -eq $failure -and $affectedPixels -eq 0)
        WadSha256=(Get-FileHash -LiteralPath $Wad).Hash
        BundleSha256=(Get-FileHash -LiteralPath $bundle).Hash
        Sources=@(@{Path='src/FastRenderer.ps1';Sha256=(Get-FileHash -LiteralPath $rendererPath).Hash},@{Path='src/RenderFuzz.ps1';Sha256=(Get-FileHash -LiteralPath $fuzzPath).Hash})
        Error=$failure
        Meaning='At the recorded E1M1 view, an actor behind a nearer lower-wall silhouette must not paint over the upper floor. The no-actor frame is the local pixel baseline. A repeated same-state render verifies stable pixels and reuse of per-context wall records and actor clip buffers. Reference-renderer parity is separately measured by Compare-ActorOcclusion.ps1.'
    }|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $Output
    if($content){$content.Dispose()}
}
"PASS: the occluded BON1 actor changes $affectedPixels scene pixels."
