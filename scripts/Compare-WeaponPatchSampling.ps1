#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Renderer="$PSScriptRoot/../src/FastRenderer.ps1",
    [double[]]$HorizontalOffsets=@(-0.75,-0.5,-0.25,0,0.25,0.5,0.75),
    [Parameter(Mandatory)][string]$Output
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$rendererPath=[IO.Path]::GetFullPath($Renderer)
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/GameHost.ps1"
. $rendererPath
function Convert-ReferenceScreen {
    param($Screen)
    [byte[]]$pixels=[byte[]]::new(64000)
    for([int]$y=0;$y -lt 200;$y++){
        for([int]$x=0;$x -lt 320;$x++){$pixels[$y*320+$x]=$Screen.Data[$x*200+$y]}
    }
    return ,$pixels
}
function Copy-WithoutPlayerSprites {
    param($Snapshot)
    $copy=$Snapshot.Clone();$player=@{}
    foreach($key in $Snapshot.ConsolePlayer.Keys){$player[$key]=$Snapshot.ConsolePlayer[$key]}
    $player.PlayerSprites=@();$copy.ConsolePlayer=$player
    return $copy
}
$content=$null;$failure=$null;$passed=$false;$cases=[Collections.Generic.List[object]]::new()
try{
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for([int]$i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    for([int]$i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
    $active=@($game.World.ConsolePlayer.PlayerSprites|Where-Object {$null -ne $_.State})
    if($active.Count -eq 0){throw 'The pistol-start fixture has no active player sprite.'}
    $config=[Config]::new();$config.video_highresolution=$false;$config.video_gamescreensize=7;$config.video_gammacorrection=0
    $reference=[Renderer]::new($config,$content);$context=New-FastRenderContext $content $game.World
    foreach($offset in $HorizontalOffsets){
        $savedSx=@($active|ForEach-Object {$_.Sx})
        for([int]$i=0;$i -lt $active.Count;$i++){$active[$i].Sx=$savedSx[$i]+[Fixed]::FromDouble($offset)}
        try{
            $snapshot=New-GameRenderSnapshot $game 1
            Set-GameRenderSnapshot $context $snapshot;Invoke-FastRender $context
            [byte[]]$candidateWith=[byte[]]$context.Pixels.Clone()
            Set-GameRenderSnapshot $context (Copy-WithoutPlayerSprites $snapshot);Invoke-FastRender $context
            [byte[]]$candidateWithout=[byte[]]$context.Pixels.Clone()

            $reference.RenderGame($game,[Fixed]::One);[byte[]]$referenceWith=Convert-ReferenceScreen $reference.Screen
            $savedStates=@($active|ForEach-Object {$_.State})
            try{
                foreach($sprite in $active){$sprite.State=$null}
                $reference.RenderGame($game,[Fixed]::One);[byte[]]$referenceWithout=Convert-ReferenceScreen $reference.Screen
            }finally{for([int]$i=0;$i -lt $active.Count;$i++){$active[$i].State=$savedStates[$i]}}

            [int]$referenceAffected=0;[int]$candidateAffected=0;[int]$coverageMismatches=0;[int]$colorMismatches=0;[int]$finalPixelMismatches=0
            $coveragePoints=[Collections.Generic.List[object]]::new()
            [int]$coveredCompared=0
            for([int]$y=0;$y -lt 168;$y++){
                [int]$row=$y*320
                for([int]$x=0;$x -lt 320;$x++){
                    [int]$index=$row+$x
                    [bool]$referenceDrawn=$referenceWith[$index] -ne $referenceWithout[$index]
                    [bool]$candidateDrawn=$candidateWith[$index] -ne $candidateWithout[$index]
                    if($referenceDrawn){$referenceAffected++};if($candidateDrawn){$candidateAffected++}
                    if(($referenceDrawn -or $candidateDrawn) -and $referenceWith[$index] -ne $candidateWith[$index]){$finalPixelMismatches++}
                    if($referenceDrawn -ne $candidateDrawn){
                        $coverageMismatches++
                        if($coveragePoints.Count -lt 64){$coveragePoints.Add(@{X=$x;Y=$y;ReferenceDrawn=$referenceDrawn;CandidateDrawn=$candidateDrawn;
                            ReferencePixel=[int]$referenceWith[$index];ReferenceBackground=[int]$referenceWithout[$index];
                            CandidatePixel=[int]$candidateWith[$index];CandidateBackground=[int]$candidateWithout[$index]})}
                        continue
                    }
                    if($referenceDrawn){$coveredCompared++;if($referenceWith[$index] -ne $candidateWith[$index]){$colorMismatches++}}
                }
            }
            $cases.Add([ordered]@{HorizontalOffset=$offset;ActivePlayerSprites=$active.Count;ReferenceAffectedPixels=$referenceAffected;
                CandidateAffectedPixels=$candidateAffected;ContributorMaskMismatches=$coverageMismatches;ColorMismatches=$colorMismatches;
                FinalPixelMismatches=$finalPixelMismatches;ComparedOverlayPixels=$coveredCompared;CoveragePoints=$coveragePoints.ToArray();
                Matched=($finalPixelMismatches -eq 0)})
        }finally{for([int]$i=0;$i -lt $active.Count;$i++){$active[$i].Sx=$savedSx[$i]}}
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}
finally{
    if($content){$content.Dispose()}
    $passed=$cases.Count -gt 0 -and @($cases|Where-Object {-not $_.Matched}).Count -eq 0
    [ordered]@{FinishedUtc=[DateTime]::UtcNow.ToString('o');WadSha256=(Get-FileHash $Wad).Hash;
        Renderer=$rendererPath;RendererSha256=(Get-FileHash $rendererPath).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        BundleSha256=(Get-FileHash $bundle).Hash;
        Episode=1;Map=1;Skill=3;IdleTics=35;ActivePlayerSprites=$active.Count;Cases=$cases.ToArray();Passed=$passed;Error=$failure;
        Meaning='Compares final palette pixels within the union of changed weapon-coverage pixels in the real PowerShell reference renderer and numeric renderer while sweeping fractional weapon X offsets. Per-image coverage masks are ambiguous where a weapon pixel equals its own background, so final-pixel equality is the pass criterion. Diagnostic projection offsets are not gameplay completion evidence.'}|
        ConvertTo-Json -Depth 7|Set-Content -LiteralPath $Output
}
if(-not $passed){throw 'Player-sprite projection differs from the reference in the isolated overlay comparison.'}
"PASS: $($cases.Count) fractional offsets match the real PowerShell reference renderer."
