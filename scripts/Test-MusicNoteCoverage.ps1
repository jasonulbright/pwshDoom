#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',[string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$PSScriptRoot/../local/music-coverage-$PID.ps1";. $bundle
. "$PSScriptRoot/../src/MusScore.ps1";. "$PSScriptRoot/../src/SoundFontBank.ps1";. "$PSScriptRoot/../src/SoundFontRegions.ps1"
$failure=$null;$archive=$null;$tracks=[Collections.Generic.List[object]]::new();$bank=$null;$usedSamples=[Collections.Generic.HashSet[int]]::new();$mods=@{}
try{
    $raw=ConvertFrom-DoomSoundFont ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($SoundFont)));$watch=[Diagnostics.Stopwatch]::StartNew();$bank=ConvertTo-DoomSoundFontRegions $raw;$buildMs=$watch.Elapsed.TotalMilliseconds
    $archive=[Wad]::new([string[]]@($Wad));$seen=@{};$cache=@{}
    foreach($lump in $archive.lumpInfos){
        $name=$lump.getName();if($name -notmatch '^D_' -or $seen.ContainsKey($name)){continue};$seen[$name]=$true
        $score=ConvertFrom-DoomMus ($archive.ReadLump($archive.GetLumpNumber($name))) -Name $name
        $programs=[int[]]::new(16);$noteOns=0;$layered=0;$peak=0;$trackSamples=[Collections.Generic.HashSet[int]]::new();$bankValues=[Collections.Generic.HashSet[int]]::new()
        foreach($event in $score.Events){
            $ch=[int]$event[2]
            if($event[1] -eq 4 -and $event[3] -eq 0){$programs[$ch]=[int]$event[4]}
            elseif($event[1] -eq 4 -and $event[3] -eq 1){$null=$bankValues.Add([int]$event[4]);if($event[4] -ne 0){throw 'Nonzero MUS bank selection needs an explicit mapping before qualification.'}}
            elseif($event[1] -eq 1 -and $event[4] -gt 0){
                $noteOns++;$bankNumber=if($ch -eq 15){128}else{0};$key='{0}:{1}:{2}:{3}' -f $bankNumber,$programs[$ch],$event[3],$event[4]
                if(-not $cache.ContainsKey($key)){$cache[$key]=Find-DoomSoundFontRegions $bank -BankNumber $bankNumber -Program $programs[$ch] -Key $event[3] -Velocity $event[4]}
                $regions=$cache[$key];if($regions.Count -eq 0){throw "No sample region for $name event $key at tick $($event[0])."}
                $peak=[Math]::Max($peak,$regions.Count);if($regions.Count -gt 1){$layered++}
                foreach($region in $regions){
                    $null=$trackSamples.Add($region.SampleId);$null=$usedSamples.Add($region.SampleId)
                    foreach($mod in $region.InstrumentModulators){$identity=$mod -join ',';if(-not $mods.ContainsKey($identity)){$mods[$identity]=$mod}}
                    foreach($mod in $region.PresetModulators){$identity=$mod -join ',';if(-not $mods.ContainsKey($identity)){$mods[$identity]=$mod}}
                }
            }
        }
        $tracks.Add(@{Name=$name;NoteOns=$noteOns;LayeredNoteOns=$layered;MaximumLayersPerNote=$peak;DistinctSamples=$trackSamples.Count;BankControllerValues=@($bankValues|Sort-Object);EveryNoteCovered=$true})
    }
    $details=@{BuildRegionsMilliseconds=$buildMs;RegionStats=$bank.Stats;UniqueNoteQueries=$cache.Count;DistinctSamples=$usedSamples.Count;
        ExplicitModulatorConfigurations=@($mods.Keys|Sort-Object|ForEach-Object {,$mods[$_]});SoundFontSha256=$bank.SourceSha256}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($archive){$archive.Dispose()}
    @{Error=$failure;Tracks=$tracks.ToArray();Details=if(Get-Variable details -ErrorAction SilentlyContinue){$details}else{$null};WadSha256=(Get-FileHash $Wad).Hash;
      Sources=@('src/MusScore.ps1','src/SoundFontBank.ps1','src/SoundFontRegions.ps1','scripts/Test-MusicNoteCoverage.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
      Meaning='Every actual note-on in every IWAD MUS track resolves using its program, key and velocity. Region bounds are checked. No PCM, envelopes, modulation evaluation or complete music fidelity claim.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($tracks.Count) complete music tracks have sample coverage."
