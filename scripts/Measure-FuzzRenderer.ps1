#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$ReferenceFuzz,
    [ValidateRange(1,20)][int]$Repeats=4,
    [string]$Replay="$PSScriptRoot/../results/fuzz-recording-fixture-third.json",
    [string]$SaveRoot="$PSScriptRoot/../local/fuzz-saves-third",
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/SaveState.ps1";. "$PSScriptRoot/../src/SaveSlots.ps1"
$content=$null;$failure=$null;$rows=[Collections.Generic.List[object]]::new();$checks=[Collections.Generic.List[object]]::new()
$sources=@('src/FastRenderer.ps1','src/RenderFuzz.ps1','scripts/Measure-FuzzRenderer.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}})
try{
    $r=Get-Content $Replay -Raw|ConvertFrom-Json;$null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    $path=Get-DoomReplaySavePath (Get-DoomSaveDirectory $SaveRoot $r.WadSha256) $r.ControlEvents[0].SaveHash
    $game=New-DoomGameFromSave (Read-DoomSaveState $path $r.WadSha256) $content
    $context=New-FastRenderContext $content $game.World;$cmd=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$cmd[$i]=[TicCmd]::new()}
    for($tic=0;$tic -le 350;$tic++){
        if($tic -gt 0){$null=$game.Update($cmd)}
        if($tic -notin 0,35,90,210,350){continue}
        $snapshot=New-GameRenderSnapshot $game;Set-GameRenderSnapshot $context $snapshot
        for($repeat=0;$repeat -lt $Repeats;$repeat++){
            $modes=if(-not $ReferenceFuzz){@('Current')}elseif($repeat%2){@('Current','Reference')}else{@('Reference','Current')}
            $images=@{};$depths=@{}
            foreach($mode in $modes){
                if($mode -eq 'Reference'){. $ReferenceFuzz}else{. "$PSScriptRoot/../src/RenderFuzz.ps1"}
                # Sequential worker-sized strips; no terminal/encoder/simulation
                # contention. Retain cold samples and every strip, not just means.
                $image=[byte[]]::new(64000);$depth=[double[]]::new(64000)
                for($strip=0;$strip -lt 16;$strip++){
                    $first=$strip*20;$end=$first+20;$watch=[Diagnostics.Stopwatch]::StartNew()
                    Invoke-FastRender $context $first $end;$elapsed=$watch.Elapsed.TotalMilliseconds
                    $rows.Add(@{Tic=$tic;Repeat=$repeat;Mode=$mode;Strip=$strip;Milliseconds=$elapsed;GeometryMs=$context.Profile.GeometryMs;ActorsMs=$context.Profile.ActorsMs;WeaponMs=$context.Profile.WeaponMs;HudMs=$context.Profile.HudMs})
                    for($y=0;$y -lt 200;$y++){[Array]::Copy($context.Pixels,$y*320+$first,$image,$y*320+$first,20);[Array]::Copy($context.Depth,$y*320+$first,$depth,$y*320+$first,20)}
                }
                $images[$mode]=$image;$depths[$mode]=$depth
            }
            if($ReferenceFuzz){
                $same=[Linq.Enumerable]::SequenceEqual[byte]($images.Current,$images.Reference) -and [Linq.Enumerable]::SequenceEqual[double]($depths.Current,$depths.Reference)
                $checks.Add(@{Tic=$tic;Repeat=$repeat;PixelsAndDepthEqual=$same});if(-not $same){throw 'Full frame/depth differs from previous fuzz implementation.'}
            }
        }
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Rows=$rows.ToArray();Checks=$checks.ToArray();Sources=$sources;SourcesChanged=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash "$PSScriptRoot/../$($_.Path)").Hash});
        ReferenceSha256=if($ReferenceFuzz){(Get-FileHash $ReferenceFuzz).Hash}else{$null};ReplaySha256=(Get-FileHash $Replay).Hash;BundleSha256=(Get-FileHash $bundle).Hash;
        Meaning='Five fixed states from the explicit saved Spectre/power fixture. Sixteen 20-column strips are executed sequentially in one process, with phase timings and all samples retained, including cold samples. Optional old/new order alternates by repeat and checks complete indexed image/depth equality. Not actual parallel-worker timing, full-host speedup or displayed FPS.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($rows.Count) profiled strips; $($checks.Count) complete frame/depth comparisons."
