#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$reports=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Report([string]$Name){$path=Join-Path $root "results/$Name.json";$reports.Add(@{Path="results/$Name.json";Sha256=(Get-FileHash $path).Hash});return Get-Content $path -Raw|ConvertFrom-Json}
try{
    $unit=Report 'music-cache-unit-first';Check 'All 22 cache checks pass on current storage source' (-not $unit.Error -and $unit.Checks.Count -eq 22 -and @($unit.Checks|Where-Object {-not $_.Passed}).Count -eq 0 -and $unit.SourceSha256 -ceq (Get-FileHash "$root/src/MusicCache.ps1").Hash)
    $short=Report 'music-cache-short-first';$full=Report 'music-cache-full-extension';$warm=Report 'music-cache-full-warm'
    Check 'Cold opening builds requested prefix' (-not $short.Error -and $short.Details.ExistingChunks -eq 0 -and $short.Details.CommittedChunks -eq 14)
    Check 'Extension verifies prior prefix before appending' (-not $full.Error -and $full.Details.ExistingChunks -eq 14 -and $full.Details.ReplayedChunks -eq 14 -and $full.Details.CommittedChunks -eq 172)
    Check 'Warm run reuses complete prefix without synthesis replay' (-not $warm.Error -and $warm.Details.ExistingChunks -eq 172 -and $warm.Details.ReplayedChunks -eq 0 -and $warm.Details.CommittedChunks -eq 172)
    Check 'Independent processes derive identical cache keys' ($short.Details.Key -ceq $full.Details.Key -and $full.Details.Key -ceq $warm.Details.Key -and $short.Details.Identity -ceq $warm.Details.Identity)
    foreach($r in @($short,$full,$warm)){
        $d=$r.Details;$reference=if($d.RequestedChunks -eq 14){Report 'music-e1m1-dry-first'}else{Report 'music-e1m1-dry-numeric-loop'}
        Check 'Comparison covers the entire expected reference' (-not $reference.Error -and $d.Comparison.Exact -and $d.Comparison.Frames -eq $reference.Details.Frames -and $d.Comparison.ClippedSamples -eq 0)
        $bytes=[IO.File]::ReadAllBytes($reference.Details.WavPath);$pcm=[byte[]]::new($bytes.Length-44);[Buffer]::BlockCopy($bytes,44,$pcm,0,$pcm.Length)
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($pcm))
        Check 'Cache PCM digest matches canonical reference bytes independently' ((Get-FileHash $reference.Details.WavPath).Hash -ceq $reference.Details.WavSha256 -and $d.Comparison.ExpectedPcmSha256 -ceq $hash -and $d.Comparison.ActualPcmSha256 -ceq $hash)
        Check 'Output and observed disk byte counts use correct units' ($d.PayloadBytes -eq $d.CommittedChunks*403200 -and $d.Frames -eq $d.CommittedChunks*25200 -and $d.Comparison.PayloadBytesRead -eq [Math]::Ceiling($d.Comparison.Frames/25200.0)*403200)
        Check 'No source drift during build' ($r.SourcesChangedDuringRun.Count -eq 0)
        foreach($s in $r.Sources){Check "Current cache input source: $($s.Path)" ((Get-FileHash (Join-Path $root $s.Path)).Hash -ceq $s.Sha256)}
    }
    Check 'Final builder source matches warm and extension runs' ($full.ScriptSha256 -ceq $warm.ScriptSha256 -and $warm.ScriptSha256 -ceq (Get-FileHash "$root/scripts/Build-MusicCache.ps1").Hash)
    $directory=$warm.Details.CacheDirectory;$manifest=Get-Content (Join-Path $directory 'manifest.json') -Raw|ConvertFrom-Json
    Check 'Published manifest matches measured cache' ($manifest.Version -eq 1 -and $manifest.Key -ceq $warm.Details.Key -and $manifest.Identity -ceq $warm.Details.Identity -and $manifest.Chunks.Count -eq 172)
    foreach($c in $manifest.Chunks){
        Check "Manifest chunk $($c.Index) has bounded identifier" ($c.Sha256 -cmatch '^[0-9A-F]{64}$' -and $c.Frame -eq $c.Index*25200)
        $path=Join-Path $directory "$($c.Index)-$($c.Sha256).f64"
        Check "Stored chunk $($c.Index) has exact bytes and hash" ((Get-Item $path).Length -eq 403200 -and (Get-FileHash $path).Hash -ceq $c.Sha256)
    }
    foreach($path in 'src/MusicCache.ps1','scripts/Build-MusicCache.ps1','scripts/Test-MusicCache.ps1','scripts/Test-MusicCacheEvidence.ps1'){
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$errors);Check "Source parses: $path" ($errors.Count -eq 0)
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Reports=$reports.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Current synthetic cache behavior plus retained cold/extension/warm evidence, source identity, independently verified reference PCM digests and all on-disk chunk hashes. Finite prefix includes a score restart; not indefinite loop, device, paced-consumer, host or gameplay-load qualification.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) music cache evidence checks."
