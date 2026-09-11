#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string[]]$Maps=@('E1M1','E2M7','E3M8','E4M1'),[ValidateRange(1,35)][int]$Samples=10,[string]$ReferenceReport)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/automap-foundation-$PID.ps1";. $bundle
. "$PSScriptRoot/FrameCodec.ps1"
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new();$cases=[Collections.Generic.List[object]]::new()
$directory=Join-Path "$PSScriptRoot/../local" ('automap-foundation-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
$referenceCases=if($ReferenceReport){(Get-Content $ReferenceReport -Raw|ConvertFrom-Json).Cases}else{@()}
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$screen=[DrawScreen]::new($content.Wad,320,200)
    $renderer=[ThreeDRenderer]::new($content,$screen,7);$mapScreen=[DrawScreen]::new($content.Wad,320,200)
    $automap=[AutoMapRenderer]::new($content.Wad,$mapScreen);$hud=[StatusBarRenderer]::new($content.Wad,$mapScreen)
    foreach($name in $Maps){
        $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$game=[DoomGame]::new($content,$options)
        $commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
        $game.DeferedInitNew([GameSkill]::Medium,[int]::Parse($name.Substring(1,1)),[int]::Parse($name.Substring(3,1)));$null=$game.Update($commands)
        $world=$game.World;$player=$world.ConsolePlayer;$flags=@($world.Map.Lines|ForEach-Object Flags);$angle=$player.Mobj.Angle
        foreach($degrees in 0,90,180,270){
            $player.Mobj.Angle=$angle+[Angle]::FromDegree($degrees);$player.OldAngle=$player.Mobj.Angle
            for($i=0;$i -lt $flags.Count;$i++){$world.Map.Lines[$i].Flags=$flags[$i] -band (-bnot 256)}
            $renderer.Render($player,[Fixed]::One)
            $reference=@(for($i=0;$i -lt $flags.Count;$i++){if($world.Map.Lines[$i].Flags -band 256){$i}})
            for($i=0;$i -lt $flags.Count;$i++){$world.Map.Lines[$i].Flags=$flags[$i] -band (-bnot 256)}
            [Array]::Fill($screen.Data,[byte]77);$valid=$world.ValidCount;$sectorValid=@($world.Map.Sectors|ForEach-Object ValidCount)
            $watch=[Diagnostics.Stopwatch]::StartNew();$renderer.DiscoverMap($player);$discoveryMs=$watch.Elapsed.TotalMilliseconds
            $discovered=@(for($i=0;$i -lt $flags.Count;$i++){if($world.Map.Lines[$i].Flags -band 256){$i}})
            Check "$name heading $degrees matches reference mapped lines" (($discovered -join ',') -ceq ($reference -join ','))
            Check "$name heading $degrees changes no framebuffer pixels" (@($screen.Data|Where-Object {$_ -ne 77}).Count -eq 0)
            Check "$name heading $degrees leaves world/sector valid counters alone" ($world.ValidCount -eq $valid -and ($sectorValid -join ',') -eq (@($world.Map.Sectors|ForEach-Object ValidCount) -join ','))
            $world.AutoMap.Open();$world.AutoMap.Update();$watch.Restart();$automap.Render($player);$hud.Render($player,$true);$mapMs=$watch.Elapsed.TotalMilliseconds
            $path=Join-Path $directory "$name-$degrees.raw";[IO.File]::WriteAllBytes($path,$mapScreen.Data)
            if($ReferenceReport){$expected=@($referenceCases|Where-Object {$_.Map -eq $name -and $null -ne $_.PSObject.Properties['Heading'] -and $_.Heading -eq $degrees});Check "$name heading $degrees preserves baseline automap/HUD pixels" ($expected.Count -eq 1 -and $expected[0].FrameSha256 -eq (Get-FileHash $path).Hash)}
            $cases.Add(@{Map=$name;Heading=$degrees;MappedLines=$discovered;ReferenceLines=$reference;DiscoveryMs=$discoveryMs;MapRenderMs=$mapMs;Frame=$path;FrameSha256=(Get-FileHash $path).Hash})
        }
        $discoveryTimes=[Collections.Generic.List[double]]::new();$mapTimes=[Collections.Generic.List[double]]::new();$mapOnlyTimes=[Collections.Generic.List[double]]::new();$hudTimes=[Collections.Generic.List[double]]::new()
        for($i=0;$i -lt $Samples;$i++){$watch.Restart();$renderer.DiscoverMap($player);$discoveryTimes.Add($watch.Elapsed.TotalMilliseconds);$watch.Restart();$automap.Render($player);$mapOnly=$watch.Elapsed.TotalMilliseconds;$hud.Render($player,$true);$combined=$watch.Elapsed.TotalMilliseconds;$mapTimes.Add($combined);$mapOnlyTimes.Add($mapOnly);$hudTimes.Add($combined-$mapOnly)}
        $cases.Add(@{Map=$name;RepeatedDiscoveryMs=(Get-SampleStats $discoveryTimes.ToArray());RepeatedMapRenderMs=(Get-SampleStats $mapTimes.ToArray());RepeatedMapOnlyMs=(Get-SampleStats $mapOnlyTimes.ToArray());RepeatedHudMs=(Get-SampleStats $hudTimes.ToArray());DiscoverySamples=$discoveryTimes.ToArray();MapSamples=$mapTimes.ToArray();MapOnlySamples=$mapOnlyTimes.ToArray();HudSamples=$hudTimes.ToArray()})
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Cases=$cases.ToArray();WadSha256=(Get-FileHash $Wad).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;BundleSha256=(Get-FileHash $bundle).Hash;FrameDirectory=$directory;
        Meaning='Four fixed headings at each selected map spawn compare discovery flags against the inherited full 3D renderer, then render the automap/HUD. Discovery must leave framebuffer and renderer-related world counters untouched. Repeated stationary timings are preliminary operation costs, not live gameplay or display FPS. Reference buffer-limit parity and moving-world coverage are not implied.'}|ConvertTo-Json -Depth 8|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($checks.Count) automap foundation checks."
