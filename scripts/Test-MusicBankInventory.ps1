#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2",[string]$MusicInventory="$PSScriptRoot/../results/music-iwad-inventory-program-mask.json")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/SoundFontBank.ps1"
$failure=$null;$details=$null
try{
    $inputReport=Get-Content $MusicInventory -Raw|ConvertFrom-Json
    if($inputReport.Error -or $inputReport.Tracks.Count -ne 32){throw 'Expected the successful Ultimate Doom music inventory.'}
    $bytes=[IO.File]::ReadAllBytes([IO.Path]::GetFullPath($SoundFont));$watch=[Diagnostics.Stopwatch]::StartNew();$bank=ConvertFrom-DoomSoundFont $bytes;$parseMs=$watch.Elapsed.TotalMilliseconds
    $presets=@($bank.Tables.phdr|Select-Object -SkipLast 1);$programs=@($inputReport.Tracks.Programs|Sort-Object -Unique)
    $missing=@($programs|Where-Object {$program=$_;@($presets|Where-Object {$_.Bank -eq 0 -and $_.Program -eq $program}).Count -eq 0})
    $gens=@($bank.Tables.igen|Select-Object -SkipLast 1|ForEach-Object {$_[0]}|Sort-Object -Unique)
    $pGens=@($bank.Tables.pgen|Select-Object -SkipLast 1|ForEach-Object {$_[0]}|Sort-Object -Unique)
    $details=@{SoundFontSha256=$bank.SourceSha256;Bytes=$bytes.Length;Version=$bank.Version;Metadata=$bank.Info;ParseMilliseconds=$parseMs;Presets=$presets;
        TableRecordCounts=@{};SampleFrames=$bank.Samples.Length;SampleRates=@($bank.Tables.shdr|Select-Object -SkipLast 1|ForEach-Object {$_.Rate}|Sort-Object -Unique);
        SampleTypes=@($bank.Tables.shdr|Select-Object -SkipLast 1|ForEach-Object {$_.Type}|Sort-Object -Unique);InstrumentGeneratorIds=$gens;PresetGeneratorIds=$pGens;
        RequiredMelodicPrograms=$programs;MissingMelodicPrograms=$missing;DrumPresets=@($presets|Where-Object {$_.Bank -eq 128});RequiredPercussionKeys=@($inputReport.Tracks.PercussionKeys|Sort-Object -Unique)}
    foreach($name in $bank.Tables.Keys){$details.TableRecordCounts[$name]=$bank.Tables[$name].Count}
    if($missing.Count){throw 'Instrument bank lacks requested melodic program headers.'}
    if($details.DrumPresets.Count -eq 0){throw 'Instrument bank lacks a percussion preset header.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Details=$details;MusicInventorySha256=(Get-FileHash $MusicInventory).Hash;Sources=@('src/SoundFontBank.ps1','scripts/Test-MusicBankInventory.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
      Meaning='Structural bank inventory and preset-header availability only. Percussion key/velocity zones, generator semantics, sound quality and synthesis cost remain unqualified. Bank/sample content remains ignored local data.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($presets.Count) presets; all $($programs.Count) requested melodic program headers found."
