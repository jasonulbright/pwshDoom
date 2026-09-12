#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string[]]$Tracks,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [Parameter(Mandatory)][string]$Catalog,
    [Parameter(Mandatory)][string]$Output,
    [string]$ExistingCatalog,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..")
$directory=[IO.Path]::GetFullPath($OutputDirectory);$catalogPath=[IO.Path]::GetFullPath($Catalog);$outputPath=[IO.Path]::GetFullPath($Output)
if($Tracks.Count -eq 0 -or $Tracks.Count -gt 64 -or @($Tracks|Sort-Object -Unique).Count -ne $Tracks.Count){throw 'Request one to 64 distinct track names.'}
foreach($track in $Tracks){if($track -cnotmatch '^D_[A-Z0-9]+$'){throw 'Use exact uppercase D_ lump names.'}}
if($catalogPath -eq $outputPath -or (Test-Path $catalogPath) -or (Test-Path $outputPath)){throw 'Choose distinct fresh catalog and preparation report paths.'}
$null=[IO.Directory]::CreateDirectory($directory)
foreach($p in $catalogPath,$outputPath){$null=[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p))}
$lock=$null;$archive=$null;$failure=$null;$published=$false;$receipts=[Collections.Generic.List[object]]::new();$reports=@{}
$sources=@('scripts/Prepare-DoomMusic.ps1','scripts/Render-MusicScore.ps1','scripts/Qualify-MusicLoop.ps1','src/MusicLoopReader.ps1','src/MusScore.ps1','src/SoundFontBank.ps1','src/SoundFontRegions.ps1','src/MusicOscillator.ps1','src/MusicControls.ps1','src/MusicSynth.ps1','src/MusicGroup.ps1','src/MusicLoopState.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$root/$_").Hash}})
$bankHash=(Get-FileHash -LiteralPath $SoundFont).Hash;$wadHash=(Get-FileHash -LiteralPath $Wad).Hash
$watch=[Diagnostics.Stopwatch]::StartNew()
function Test-QualifiedTrack([string]$Path,[string]$Track,[string]$MusHash){
    $r=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
    if($r.Details.Track -cne $Track -or $r.Details.MusSha256 -cne $MusHash -or $r.Details.BankSha256 -cne $bankHash){throw "Qualified track assets differ: $Track"}
    $reader=$null
    try{$reader=Open-DoomMusicLoopReader $Path}finally{if($reader){Close-DoomMusicLoopReader $reader}}
}
try{
    # File existence is not a lock: the open exclusive handle owns the batch.
    $lock=[IO.File]::Open((Join-Path $directory 'prepare.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$directory/engine-$PID.ps1";. $bundle
    . "$root/src/MusicLoopReader.ps1"
    $archive=[Wad]::new([string[]]@($Wad))
    $existing=@{}
    if($ExistingCatalog){
        $seed=[IO.Path]::GetFullPath($ExistingCatalog)
        if(([IO.FileInfo]::new($seed)).Length -gt 1MB){throw 'Existing catalog exceeds size bound.'}
        $existing=Get-Content -LiteralPath $seed -Raw|ConvertFrom-Json -AsHashtable
        if($existing -isnot [hashtable]){throw 'Existing catalog must be an object mapping tracks to reports.'}
        foreach($key in @($existing.Keys)){
            if($existing[$key] -isnot [string]){throw 'Existing catalog paths must be strings.'}
            $existing[$key]=[IO.Path]::GetFullPath($existing[$key],[IO.Path]::GetDirectoryName($seed))
        }
    }
    # Check every requested lump before spending time synthesizing any track.
    $musHashes=@{}
    foreach($track in $Tracks){
        $lump=$archive.GetLumpNumber($track)
        if($lump -lt 0){throw "IWAD has no requested music lump: $track"}
        $musHashes[$track]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($archive.ReadLump($lump)))
    }
    foreach($track in $Tracks){
        $trackRoot=Join-Path $directory $track;$null=[IO.Directory]::CreateDirectory($trackRoot)
        $resume=Join-Path $trackRoot 'qualified.json'
        if($existing.ContainsKey($track)){
            $report=$existing[$track];Test-QualifiedTrack $report $track $musHashes[$track]
            $action='VerifiedExistingCatalog'
        }elseif(Test-Path $resume){
            $report=$resume;Test-QualifiedTrack $report $track $musHashes[$track]
            $action='VerifiedPreviousPreparation'
        }else{
            $attempt=Join-Path $trackRoot ([guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($attempt)
            $reference=Join-Path $attempt 'reference.json';$report=Join-Path $attempt 'qualification.json'
            Write-Host "Preparing ${track}: independent opening, then three continuous aligned periods."
            & (Get-Process -Id $PID).Path -NoProfile -File "$PSScriptRoot/Render-MusicScore.ps1" -Wad $Wad -SoundFont $SoundFont -Track $track -Seconds 8 -Output $reference | Out-Host
            if($LASTEXITCODE -ne 0){throw "Opening render failed: $track; retained $reference"}
            $ref=Get-Content $reference -Raw|ConvertFrom-Json
            if($ref.Error -or $ref.SourcesChangedDuringRun.Count){throw "Opening reference changed or failed: $track"}
            & (Get-Process -Id $PID).Path -NoProfile -File "$PSScriptRoot/Qualify-MusicLoop.ps1" -Wad $Wad -SoundFont $SoundFont -Track $track -ReferenceReport $reference -Output $report | Out-Host
            if($LASTEXITCODE -ne 0){throw "Continuous qualification failed: $track; retained $report"}
            Test-QualifiedTrack $report $track $musHashes[$track]
            [IO.File]::Copy($report,$resume,$false);$report=$resume;$action='PreparedAndQualified'
        }
        $reports[$track]=$report
        $receipts.Add(@{Track=$track;Action=$action;Report=$report;ReportSha256=(Get-FileHash $report).Hash;MusSha256=$musHashes[$track]})
        Write-Host "Verified $track ($action)."
    }
    if(@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash "$root/$($_.Path)").Hash}).Count){throw 'Preparation sources changed; catalog publication rejected.'}
    if((Get-FileHash $Wad).Hash -cne $wadHash -or (Get-FileHash $SoundFont).Hash -cne $bankHash){throw 'Assets changed during preparation; catalog publication rejected.'}
    $temporary=$catalogPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temporary,($reports|ConvertTo-Json))
    try{[IO.File]::Move($temporary,$catalogPath,$false)}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
    $published=$true
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($archive){$archive.Dispose()};if($lock){$lock.Dispose()}
    @{Error=$failure;RequestedTracks=$Tracks;Published=$published;Catalog=$catalogPath;CatalogSha256=if($published){(Get-FileHash $catalogPath).Hash}else{$null};
      WadSha256=$wadHash;SoundFontSha256=$bankHash;Tracks=$receipts.ToArray();Sources=$sources;Seconds=$watch.Elapsed.TotalSeconds;
      Meaning='Finite sequential preparation of exactly the requested dry looping tracks. Existing/resumed tracks undergo source/runtime/complete payload and IWAD/SF2 identity checks. Catalog published only after all requests pass. Successful per-track reports survive failed/interrupted batches for explicit same-directory resume. No one-shot, full soundtrack, fidelity, live deadline or campaign completion claim.'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $outputPath
}
$catalogPath
