#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/music-inventory-$PID.ps1";. $bundle
. "$PSScriptRoot/../src/MusScore.ps1"
$archive=$null;$failure=$null;$tracks=[Collections.Generic.List[object]]::new();$maps=[Collections.Generic.List[object]]::new();$seen=@{}
function Event-Hash($Events){
    $text=(@($Events|ForEach-Object {$_ -join ','}) -join '|')
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text)))
}
try{
    $archive=[Wad]::new([string[]]@($Wad))
    foreach($lump in $archive.lumpInfos){
        $name=$lump.getName();if($name -notmatch '^D_' -or $seen.ContainsKey($name)){continue};$seen[$name]=$true
        $data=$archive.ReadLump($archive.GetLumpNumber($name));$watch=[Diagnostics.Stopwatch]::StartNew()
        $score=ConvertFrom-DoomMus $data -Name $name;$decodeMs=$watch.Elapsed.TotalMilliseconds
        $held=[Collections.Generic.HashSet[int]]::new();$peak=0;$unmatched=0;$kinds=@{};$programs=[Collections.Generic.HashSet[int]]::new();$controllers=[Collections.Generic.HashSet[int]]::new();$drums=[Collections.Generic.HashSet[int]]::new()
        foreach($e in $score.Events){
            $kind=[int]$e[1];$ch=[int]$e[2];$key=$ch*128+[int]$e[3]
            $kindKey=[string]$kind
            if(-not $kinds.ContainsKey($kindKey)){$kinds[$kindKey]=0};$kinds[$kindKey]++
            if($kind -eq 0 -or ($kind -eq 1 -and $e[4] -eq 0)){if(-not $held.Remove($key)){$unmatched++}}
            elseif($kind -eq 1){$null=$held.Add($key);if($ch -eq 15){$null=$drums.Add([int]$e[3])}}
            elseif($kind -eq 3 -and $e[3] -in 10,11){foreach($heldKey in @($held)){if(($heldKey -shr 7) -eq $ch){$null=$held.Remove($heldKey)}}}
            elseif($kind -eq 4){$null=$controllers.Add([int]$e[3]);if($e[3] -eq 0){$null=$programs.Add([int]$e[4])}}
            $peak=[Math]::Max($peak,$held.Count)
        }
        $timeline=New-DoomMusicTimeline $score;$scheduled=[Collections.Generic.List[object]]::new()
        while(-not $timeline.Finished){$block=Read-DoomMusicFrames $timeline 192000;foreach($e in $block.Events){$scheduled.Add($e)}}
        $expected=@($score.Events|ForEach-Object {,[long[]]@(($_[0]*315),$_[1],$_[2],$_[3],$_[4],0)})
        $eventHash=Event-Hash $scheduled.ToArray();$matched=$eventHash -eq (Event-Hash $expected)
        if(-not $matched){throw "$name full timeline differs from independent tick*315 projection."}
        $tracks.Add(@{Name=$name;LumpSha256=$score.SourceSha256;Bytes=$data.Length;Events=$score.Events.Count;Kinds=$kinds;DurationTicks=$score.DurationTicks;Seconds=$score.DurationTicks/140.0;EndSample=$score.DurationTicks*315;
            Instruments=$score.Instruments;Programs=@($programs|Sort-Object);Controllers=@($controllers|Sort-Object);PercussionKeys=@($drums|Sort-Object);PeakDistinctDepressedKeys=$peak;UnmatchedNoteOffs=$unmatched;
            DecodeMilliseconds=$decodeMs;NormalizedValues=$score.NormalizedValues;TrailingScoreBytes=$score.TrailingScoreBytes;TrailingLumpBytes=$score.TrailingLumpBytes;ScheduledEventsMatched=$matched;ScheduledEventsSha256=$eventHash})
    }
    $options=[GameOptions]::new();$options.GameMode=[GameMode]::Retail
    for($ep=1;$ep -le 4;$ep++){for($map=1;$map -le 9;$map++){
        $options.Episode=$ep;$options.Map=$map;$bgm=[Map]::GetMapBgm($options);$name='D_'+[DoomInfo]::BgmNames[[int]$bgm].ToString().ToUpperInvariant()
        if(-not $seen.ContainsKey($name)){throw "Missing mapped music $name"}
        $maps.Add(@{Map="E${ep}M$map";Music=$name})
    }}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($archive){$archive.Dispose()}
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;WadSha256=(Get-FileHash $Wad).Hash;Tracks=$tracks.ToArray();MapMusic=$maps.ToArray();
      Sources=@('src/MusScore.ps1','scripts/Test-MusicInventory.ps1','src/ManagedDoom/Doom/Map/Map.sb.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
      Meaning='All D_ lumps in this IWAD parsed and scheduled at 44.1 kHz; exact event-sample hashes compared against independent tick*315 projection. Map table records the retained engine mapping, not independently proved routing. Depressed-key peak excludes sustain, release tails and layered soundfont voices. No synthesis or music playback qualification.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($tracks.Count) MUS tracks and $($maps.Count) map music references."
