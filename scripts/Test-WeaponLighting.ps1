#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1";. "$PSScriptRoot/../src/RenderAssets.ps1"
$sources=@('scripts/Test-WeaponLighting.ps1','src/FastRenderer.ps1','src/GameHost.ps1','src/SnapshotTransport.ps1','src/RenderLighting.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}})
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new();$oldMismatchCases=0
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $player=$game.World.ConsolePlayer;$screen=[DrawScreen]::new($content.Wad,320,200);$reference=[ThreeDRenderer]::new($content,$screen,7)
    $context=New-FastRenderContext $content $game.World
    $palette=[int[][]]::new(256);for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $cache="$PSScriptRoot/../local/weapon-lighting-$([guid]::NewGuid().ToString('N')).assets"
    Write-GameRenderAssets $context $palette $cache;$cached=Read-GameRenderAssets $cache
    $fixtures=[Collections.Generic.List[object]]::new()
    for($band=0;$band -lt 16;$band++){foreach($bright in 0,32768){foreach($fixed in 0,16,32){
        $fixtures.Add(@{Weapon=1;Phase='ReadyState';Light=$band*16;Extra=0;Bright=$bright;Fixed=$fixed})
    }}}
    for($weapon=0;$weapon -lt 8;$weapon++){foreach($phase in 'ReadyState','FlashState'){
        if([int][DoomInfo]::WeaponInfos[$weapon].$phase -eq 0){continue}
        foreach($lighting in @(@(-16,-2),@(64,2),@(300,2))){$fixtures.Add(@{Weapon=$weapon;Phase=$phase;Light=$lighting[0];Extra=$lighting[1];Bright=0;Fixed=0})}
    }}
    foreach($case in $fixtures){
        $state=[DoomInfo]::States.All[[int][DoomInfo]::WeaponInfos[$case.Weapon].($case.Phase)]
        $player.PlayerSprites[0].State=[pscustomobject]@{Sprite=$state.Sprite;Frame=($state.Frame -bor $case.Bright)}
        $player.PlayerSprites[0].Sx=[Fixed]::FromInt(160);$player.PlayerSprites[0].Sy=[Fixed]::FromInt(32);$player.PlayerSprites[1].State=$null
        $player.Mobj.Subsector.Sector.LightLevel=$case.Light;$player.ExtraLight=$case.Extra;$player.FixedColorMap=$case.Fixed
        $reference.extraLight=$case.Extra;$reference.fixedColorMap=$case.Fixed;$reference.ClearLighting()
        [Array]::Fill($screen.Data,[byte]42);$reference.DrawPlayerSprites($player)
        $expected=[byte[]]::new(64000);for($x=0;$x -lt 320;$x++){for($y=0;$y -lt 200;$y++){$expected[$y*320+$x]=$screen.Data[$x*200+$y]}}
        $snapshot=New-GameRenderSnapshot $game;$bytes=ConvertTo-GameSnapshotBytes $snapshot
        if(-not [Linq.Enumerable]::SequenceEqual[byte]($bytes,(Get-GameRenderSnapshotBytes $game))){throw 'Object/direct snapshot light transport differs.'}
        $decoded=Read-GameSnapshotBytes $bytes $null
        if($decoded.ConsolePlayer.SectorLight -ne $case.Light){throw 'Player sector light did not survive the wire.'}
        Set-GameRenderSnapshot $context $snapshot;Set-GameRenderSnapshot $cached $decoded
        [Array]::Fill($context.Pixels,[byte]42);[Array]::Fill($cached.Pixels,[byte]42)
        Draw-FastPlayerSprites $context
        $bounds=0,45,91,137,182,228,274,320;for($i=0;$i -lt 7;$i++){Draw-FastPlayerSprites $cached $bounds[$i] $bounds[$i+1]}
        $differences=0;for($i=0;$i -lt 64000;$i++){if($expected[$i] -ne $context.Pixels[$i]){$differences++}}
        $cachedMatch=[Linq.Enumerable]::SequenceEqual[byte]($context.Pixels,$cached.Pixels)
        # Reproduce the former always-full-bright weapon call on the same geometry.
        $actual=[byte[]]$context.Pixels.Clone();[Array]::Fill($context.Pixels,[byte]42)
        $psp=$snapshot.ConsolePlayer.PlayerSprites[0];$frame=$context.SpriteAtlas[$psp.Sprite][$psp.Frame -band 32767];$patch=$frame.Patches[0]
        Draw-FastPatch $context $patch ($psp.Sx-$patch.Left) ($psp.Sy-$patch.Top-16.25) 1 0 $frame.Flip[0] 0 0 320 168
        $oldMatches=[Linq.Enumerable]::SequenceEqual[byte]($expected,$context.Pixels);if(-not $oldMatches){$oldMismatchCases++}
        $checks.Add(@{Fixture=$case;ReferenceDifferences=$differences;CachedSevenStripsMatch=$cachedMatch;PreviousFullBrightMatches=$oldMatches;Pixels=64000})
        if($differences -or -not $cachedMatch){throw "Weapon reference mismatch: $($case|ConvertTo-Json -Compress), pixels $differences, cached $cachedMatch"}
    }
    if($oldMismatchCases -eq 0){throw 'The fixtures did not distinguish the previous defect.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();PreviousMismatchCases=$oldMismatchCases;Sources=$sources;SourcesChangedDuringRun=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash "$PSScriptRoot/../$($_.Path)").Hash});
        BundleSha256=(Get-FileHash $bundle).Hash;WadSha256=(Get-FileHash $Wad).Hash;
        Meaning='Isolated player-sprite indexed images compared to adopted ThreeDRenderer, then cached assets and seven uneven strips after snapshot wire transport. Covers light bands, extra-light clamps, full-bright frames, fixed maps, ready/flash states for Ultimate Doom weapons. Previous always-full-bright call is a negative control. Invisibility, original-executable fidelity, whole-world rendering and full-game pacing remain separate.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) weapon images; previous renderer mismatches $oldMismatchCases cases."
