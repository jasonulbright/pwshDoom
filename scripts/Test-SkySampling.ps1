#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Output="$PSScriptRoot/../results/sky-sampling.json"
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1";. "$PSScriptRoot/../src/GameHost.ps1"
$content=$null;$headings=[Collections.Generic.List[object]]::new();$passed=$false
try {
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode
    $options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt $commands.Length;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $context=New-FastRenderContext $content $game.World
    $config=[Config]::new();$config.video_highresolution=$false
    $config.video_gamescreensize=7;$config.video_gammacorrection=0
    $reference=[Renderer]::new($config,$content)
    $sky=$game.World.Map.SkyTexture.Composite
    if($sky.Width -ne $context.Sky.Width -or $sky.Height -ne $context.Sky.Height -or $sky.Height -lt 128){throw 'Sky source dimensions are unsupported by this 128-row fixture.'}
    if($reference.ThreeD.skyInvScale.Data -ne 65536 -or $reference.ThreeD.skyTextureAlt.Data -ne 6553600 -or $reference.ThreeD.centerY -ne 84){
        throw 'The reference sky scale/origin changed; update the candidate sampling model before accepting this fixture.'
    }
    [int]$comparedPerHeading=320*168;$allAngleMismatches=0;$allPixelMismatches=0
    foreach($degrees in @(0,45,90,135,180,225,270,315)){
        $game.World.ConsolePlayer.Mobj.Angle=[Angle]::new([uint32][Math]::Floor($degrees*4294967296.0/360.0))
        Set-GameRenderSnapshot $context (New-GameRenderSnapshot $game 1);Invoke-FastRender $context
        $reference.RenderGame($game,[Fixed]::One)
        [uint32]$viewAngleData=$reference.ThreeD.viewAngleData
        [byte[]]$colorMap=$reference.ThreeD.defaultColorMap
        [int]$angleMismatches=0;$pixelMismatches=0
        for([int]$x=0;$x -lt 320;$x++){
            if($context.PlaneColumnAngles[$x] -ne $reference.ThreeD.xToAngleData[$x]){$angleMismatches++}
            $reference.ThreeD.DrawSkyColumn($x,0,167)
            [uint32]$angleData=([uint64]$viewAngleData+[uint64]$context.PlaneColumnAngles[$x]) -band 0xFFFFFFFFul
            [int]$referenceSkyU=[ThreeDRenderer]::WrapColumnIndex([int]($angleData -shr 22),$context.Sky.Width)
            [int]$skyU=$context.SkyColumns[$x]
            if($skyU -ne $referenceSkyU){$angleMismatches++}
            for([int]$y=0;$y -lt 168;$y++){
                [int]$fracData=6553600+(($y-84)*65536)
                [int]$skyV=($fracData -shr 16) -band 127
                [byte]$candidate=$colorMap[$context.Sky.Data[$skyU*$context.Sky.Height+$skyV]]
                [int]$referencePixel=$reference.Screen.Data[$x*200+$y]
                if($candidate -ne $referencePixel){$pixelMismatches++}
            }
        }
        if($angleMismatches -ne 0 -or $pixelMismatches -ne 0){throw "Heading $degrees`: angle mismatches $angleMismatches; sampled sky pixels differ $pixelMismatches of $comparedPerHeading."}
        $headings.Add(@{Degrees=$degrees;SourceTableAnglesCompared=320;ProducedSkyColumnsCompared=320;AngleMismatches=$angleMismatches;ComparedSkyPixels=$comparedPerHeading;SkyPixelMismatches=$pixelMismatches})
        $allAngleMismatches+=$angleMismatches;$allPixelMismatches+=$pixelMismatches
    }
    $passed=$true
    'PASS: exact sky columns and all 430,080 sky pixels match the adopted renderer across eight headings.'
}finally{
    if($content){$content.Dispose()}
    $sourcePaths=@('scripts/Test-SkySampling.ps1','src/FastRenderer.ps1','src/RenderAssets.ps1','src/GameHost.ps1','src/ManagedDoom/Video/ThreeDRenderer.sb.ps1')
    $sources=@($sourcePaths|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}})
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Passed=$passed;Fixture='Ultimate Doom E1M1 sky texture, isolated DrawSkyColumn reference output, 320x200/320x168 viewport';Headings=$headings.ToArray();AngleMismatches=$allAngleMismatches;SkyPixelMismatches=$allPixelMismatches;WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;Sources=$sources;Meaning='Direct sky-sampler equivalence against the adopted, locally adapted PowerShell Doom renderer. This isolates sky sampling and does not establish full-frame vanilla Doom equivalence or original-executable parity.'}|
        ConvertTo-Json -Depth 6|Set-Content -LiteralPath $Output
}
