#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$checks.Add(@{Name=$Name;Passed=$Pass});if(-not $Pass){throw $Name}}
function Background($Context,$Screen){
    for($x=0;$x -lt 320;$x++){for($y=0;$y -lt 200;$y++){
        [byte]$color=($x*13+$y*7)%256;$Context.Pixels[$y*320+$x]=$color;$Screen.Data[$x*200+$y]=$color
    }}
    [Array]::Fill($Context.Depth,[double]::PositiveInfinity)
    for($x=0;$x -lt 320;$x++){for($y=50;$y -lt 65;$y++){$Context.Depth[$y*320+$x]=10}}
}
function ReferencePixels($Screen){
    $b=[byte[]]::new(64000);for($x=0;$x -lt 320;$x++){for($y=0;$y -lt 200;$y++){$b[$y*320+$x]=$Screen.Data[$x*200+$y]}};return ,$b
}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $screen=[DrawScreen]::new($content.Wad,320,200);$reference=[ThreeDRenderer]::new($content,$screen,7)
    $context=New-FastRenderContext $content $game.World;Set-GameRenderSnapshot $context (New-GameRenderSnapshot $game)
    Check 'Adopted 50-entry offset table retained' ([Linq.Enumerable]::SequenceEqual[int]($script:DoomFuzzOffsets,[int[]][ThreeDRenderer]::fuzzTable))
    $patch=@{Width=13;Height=20;Data=[int[]]::new(260)}
    for($x=0;$x -lt 13;$x++){for($y=0;$y -lt 20;$y++){$patch.Data[$x*20+$y]=if(($x+$y)%5 -eq 0){-1}else{220}}}
    $caseIndex=0
    foreach($location in @(@(-3.25,-5.5),@(43.5,48.25),@(309.1,156.4))){foreach($scale in 0.5,1,2.3){foreach($flip in $false,$true){foreach($distance in 0,12){
        Background $context $screen;$before=[byte[]]$context.Pixels.Clone();$beforeDepth=[double[]]$context.Depth.Clone()
        $context.World.Tic=21;$left=$location[0];$top=$location[1]
        # Independent adopted column operation, invoked only at covered mask
        # pixels. Its mutable column-major framebuffer supplies the expected
        # neighbour lookup and color mapping, including in-place feedback.
        for($x=0;$x -lt 320;$x++){
            $reference.fuzzPos=(21*7+$x*168)%50
            $sx=[int][Math]::Floor(($x-$left)/$scale);if($sx -lt 0 -or $sx -ge 13){continue};if($flip){$sx=12-$sx}
            for($y=1;$y -lt 167;$y++){
                $sy=[int][Math]::Floor(($y-$top)/$scale);if($sy -lt 0 -or $sy -ge 20 -or $patch.Data[$sx*20+$sy] -lt 0){continue}
                if($distance -gt 0 -and $distance -ge $beforeDepth[$y*320+$x]){continue}
                $reference.DrawFuzzColumn($null,$x,$y,$y)
            }
        }
        $expected=ReferencePixels $screen
        Draw-FastFuzzPatch $context $patch $left $top $scale $distance $flip
        Check "Case $caseIndex reference pixels (clipping/scale/flip/depth)" ([Linq.Enumerable]::SequenceEqual[byte]($expected,$context.Pixels))
        $serial=[byte[]]$context.Pixels.Clone();$serialDepth=[double[]]$context.Depth.Clone()
        [Array]::Copy($before,$context.Pixels,64000);[Array]::Copy($beforeDepth,$context.Depth,64000)
        $bounds=0,45,91,137,182,228,274,320
        for($i=6;$i -ge 0;$i--){Draw-FastFuzzPatch $context $patch $left $top $scale $distance $flip $bounds[$i] $bounds[$i+1]}
        Check "Case $caseIndex reverse strip order pixels and depth" (([Linq.Enumerable]::SequenceEqual[byte]($serial,$context.Pixels)) -and ([Linq.Enumerable]::SequenceEqual[double]($serialDepth,$context.Depth)))
        $caseIndex++
    }}}}
    # Selection uses actual game power state and independent object/direct wire
    # producers; cutoff and flashing edges are explicit expected cases.
    $player=$game.World.ConsolePlayer;$player.PlayerSprites[0].Sx=[Fixed]::FromInt(160);$player.PlayerSprites[0].Sy=[Fixed]::FromInt(32)
    foreach($entry in @(@(0,$false),@(7,$false),@(8,$true),@(15,$true),@(16,$false),@(120,$true),@(127,$true),@(128,$false),@(129,$true),@(2100,$true))){
        $player.Powers[[int][PowerType]::Invisibility]=$entry[0]
        $snapshot=New-GameRenderSnapshot $game;$packet=ConvertTo-GameSnapshotBytes $snapshot
        Check "Timer $($entry[0]) object/direct wire equality" ([Linq.Enumerable]::SequenceEqual[byte]($packet,(Get-GameRenderSnapshotBytes $game)))
        $decoded=Read-GameSnapshotBytes $packet $null;Check "Timer $($entry[0]) decoded" ($decoded.ConsolePlayer.Invisibility -eq $entry[0])
        Set-GameRenderSnapshot $context $decoded;Background $context $screen
        Draw-FastPlayerSprites $context;$actual=[byte[]]$context.Pixels.Clone()
        Background $context $screen
        if($entry[1]){
            foreach($psp in $decoded.ConsolePlayer.PlayerSprites){$frame=$context.SpriteAtlas[$psp.Sprite][$psp.Frame -band 32767];$p=$frame.Patches[0]
                Draw-FastFuzzPatch $context $p ($psp.Sx-$p.Left) ($psp.Sy-$p.Top-16.25) 1 0 $frame.Flip[0]
            }
        }else{$decoded.ConsolePlayer.Invisibility=0;Draw-FastPlayerSprites $context}
        Check "Timer $($entry[0]) correct fuzz/opaque selection" ([Linq.Enumerable]::SequenceEqual[byte]($actual,$context.Pixels))
        if($entry[1]){
            Background $context $screen;$decoded.ConsolePlayer.Invisibility=0;Draw-FastPlayerSprites $context
            Check "Timer $($entry[0]) differs from old opaque weapon" (-not [Linq.Enumerable]::SequenceEqual[byte]($actual,$context.Pixels))
        }
    }
    # Fixed colormaps and fullbright muzzle flashes must not override fuzz.
    $player.Powers[[int][PowerType]::Invisibility]=129;$snapshot=New-GameRenderSnapshot $game
    Set-GameRenderSnapshot $context $snapshot;Background $context $screen;Draw-FastPlayerSprites $context;$baseline=[byte[]]$context.Pixels.Clone()
    $snapshot.ConsolePlayer.FixedColorMap=32;$snapshot.ConsolePlayer.PlayerSprites[0].Frame=$snapshot.ConsolePlayer.PlayerSprites[0].Frame -bor 32768
    Background $context $screen;Draw-FastPlayerSprites $context
    Check 'Fuzz has precedence over fullbright and fixed colormap' ([Linq.Enumerable]::SequenceEqual[byte]($baseline,$context.Pixels))
    $snapshot.Tic++;Background $context $screen;Draw-FastPlayerSprites $context
    Check 'Fuzz changes with game tic' (-not [Linq.Enumerable]::SequenceEqual[byte]($baseline,$context.Pixels))
    $actor=$game.World.Thinkers.Cap.Next
    while($actor -isnot [Mobj] -or [object]::ReferenceEquals($actor,$player.Mobj)){$actor=$actor.Next}
    $savedFlags=$actor.Flags
    foreach($flag in 0,0x40000,0x40020){
        $actor.Flags=[MobjFlags]$flag;$direct=Get-GameRenderSnapshotBytes $game;$decoded=Read-GameSnapshotBytes $direct $null
        Check "Actual actor flag $flag reaches decoder" ($decoded.Actors[0].Flags -eq $flag)
        Check "Actual actor flag $flag object/direct bytes" ([Linq.Enumerable]::SequenceEqual[byte]($direct,(ConvertTo-GameSnapshotBytes (New-GameRenderSnapshot $game))))
    }
    $actor.Flags=$savedFlags
    $snapshot=New-GameRenderSnapshot $game;$snapshot.ConsolePlayer.Mobj.Angle=0;$snapshot.ConsolePlayer.Invisibility=0
    $near=$snapshot.Actors[0].Clone();$near.X=$snapshot.ConsolePlayer.Mobj.X+32;$near.Y=$snapshot.ConsolePlayer.Mobj.Y
    $near.Z=$snapshot.ConsolePlayer.ViewZ-41;$near.Sprite=[int][Sprite]::SARG;$near.Frame=0;$near.Flags=0x40000
    $far=$near.Clone();$far.X+=16;$far.Flags=0;$far.Frame=32768
    $snapshot.Actors=@($near,$far);Set-GameRenderSnapshot $context $snapshot;Invoke-FastRender $context;$foreground=[byte[]]$context.Pixels.Clone()
    $snapshot.Actors=@($far,$near);Invoke-FastRender $context
    Check 'Overlapping shadow and opaque actors ignore thinker order' ([Linq.Enumerable]::SequenceEqual[byte]($foreground,$context.Pixels))
    $snapshot.Actors=@($near);Invoke-FastRender $context
    Check 'Spectre samples the actor behind it' (-not [Linq.Enumerable]::SequenceEqual[byte]($foreground,$context.Pixels))
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();Sources=@('src/RenderFuzz.ps1','src/FastRenderer.ps1','src/GameHost.ps1','src/SnapshotTransport.ps1','scripts/Test-FuzzRendering.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});
        BundleSha256=(Get-FileHash $bundle).Hash;WadSha256=(Get-FileHash $Wad).Hash;
        Meaning='Fuzz neighbour/color operation compared to adopted renderer with explicit per-column seed, not original global-phase parity. Synthetic clipping/scaling/holes/flip/depth fixtures and reversed uneven strips; real-game player timer transport and blink/precedence controls. Not campaign qualification or a live display measurement.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) fuzz checks."
