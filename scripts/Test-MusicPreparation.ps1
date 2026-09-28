#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$dir=Join-Path "$root/local" ('music-prepare-test-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($dir)
$checks=[Collections.Generic.List[object]]::new();$attempts=[Collections.Generic.List[object]]::new();$failure=$null;$held=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Run([string]$Name,[string]$Track,[string]$PreparationRoot,[string]$Seed){
    $catalog=Join-Path $dir ($Name+'-catalog.json');$receipt=Join-Path $dir ($Name+'-report.json')
    $info=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path);$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-File',"$PSScriptRoot/Prepare-DoomMusic.ps1",'-Tracks',$Track,'-OutputDirectory',$PreparationRoot,'-Catalog',$catalog,'-Output',$receipt)){$info.ArgumentList.Add($arg)}
    if($Seed){$info.ArgumentList.Add('-ExistingCatalog');$info.ArgumentList.Add($Seed)}
    $process=[Diagnostics.Process]::Start($info);$outTask=$process.StandardOutput.ReadToEndAsync();$errorTask=$process.StandardError.ReadToEndAsync()
    try{if(-not $process.WaitForExit(45000)){$process.Kill($true);$process.WaitForExit();throw 'Finite preparation control fixture timed out.'};$code=$process.ExitCode}finally{$process.Dispose()}
    $outTask.Result|Set-Content (Join-Path $dir ($Name+'-stdout.log'));$errorTask.Result|Set-Content (Join-Path $dir ($Name+'-stderr.log'))
    $r=if(Test-Path $receipt){Get-Content $receipt -Raw|ConvertFrom-Json}else{$null}
    $attempts.Add(@{Name=$Name;ExitCode=$code;Report=$receipt;ReportSha256=if($r){(Get-FileHash $receipt).Hash}else{$null};Error=$errorTask.Result})
    return @{Code=$code;Report=$r;Catalog=$catalog}
}
try{
    $qualification="$root/results/music-loop-e1m1-hour-bound.json";$seed=Join-Path $dir 'seed.json';@{D_E1M1=$qualification}|ConvertTo-Json|Set-Content $seed
    $p=Run 'reuse' D_E1M1 (Join-Path $dir 'reuse') $seed
    Check 'Real current E1M1 payload verifies and publishes requested catalog' ($p.Code -eq 0 -and $p.Report.Published -and $p.Report.Tracks.Count -eq 1 -and $p.Report.Tracks[0].Action -ceq 'VerifiedExistingCatalog')
    $before=(Get-FileHash $p.Catalog).Hash
    $again=Run 'reuse' D_E1M1 (Join-Path $dir 'reuse') $seed
    Check 'Existing catalog and receipt are protected from overwrite' ($again.Code -ne 0 -and (Get-FileHash $p.Catalog).Hash -ceq $before)
    $resumeRoot=Join-Path $dir 'resume';$null=[IO.Directory]::CreateDirectory((Join-Path $resumeRoot 'D_E1M1'));Copy-Item $qualification (Join-Path $resumeRoot 'D_E1M1/qualified.json')
    $p=Run 'resume' D_E1M1 $resumeRoot ''
    Check 'Interrupted-batch resume revalidates real qualified payload without a seed catalog' ($p.Code -eq 0 -and $p.Report.Published -and $p.Report.Tracks[0].Action -ceq 'VerifiedPreviousPreparation')
    $episode1Catalog=Get-Content -LiteralPath (Join-Path $root 'local/music-prepared-episode1.json') -Raw|ConvertFrom-Json -AsHashtable
    if(-not $episode1Catalog.ContainsKey('D_E1M7')){throw 'Episode 1 alias fixture is missing its qualified D_E1M7 report.'}
    $aliasSeed=Join-Path $dir 'alias-seed.json';@{D_E1M7=$episode1Catalog['D_E1M7']}|ConvertTo-Json|Set-Content -LiteralPath $aliasSeed
    $aliasRoot=Join-Path $dir 'alias';$p=Run 'alias' D_E2M5 $aliasRoot $aliasSeed
    $aliasReportPath=Join-Path $aliasRoot 'D_E2M5/qualified.json';$aliasData=Get-Content -LiteralPath $aliasReportPath -Raw|ConvertFrom-Json -AsHashtable
    $aliasSourceData=Get-Content -LiteralPath $episode1Catalog['D_E1M7'] -Raw|ConvertFrom-Json -AsHashtable
    $aliasCatalog=Get-Content -LiteralPath $p.Catalog -Raw|ConvertFrom-Json -AsHashtable
    Check 'Byte-identical WAD music reuses a current qualification without rendering' ($p.Code -eq 0 -and $p.Report.Published -and $p.Report.Tracks[0].Action -ceq 'ReusedIdenticalPayloadAlias' -and $p.Report.Tracks[0].AliasOf -ceq 'D_E1M7' -and @((Get-ChildItem -LiteralPath (Join-Path $aliasRoot 'D_E2M5') -Directory)).Count -eq 0)
    Check 'Alias report records exact payload, bank, source report and target catalog identity' ($aliasData.Details.Track -ceq 'D_E2M5' -and $aliasData.AliasProvenance.SourceTrack -ceq 'D_E1M7' -and $aliasData.AliasProvenance.Method -ceq 'ExactMUSAndSoundFontHash' -and $aliasData.AliasProvenance.MusSha256 -ceq $aliasData.Details.MusSha256 -and $aliasData.Details.BankSha256 -ceq $aliasSourceData.Details.BankSha256 -and $aliasData.AliasProvenance.SoundFontSha256 -ceq $aliasData.Details.BankSha256 -and $aliasData.AliasProvenance.SourceQualificationSha256 -ceq (Get-FileHash $episode1Catalog['D_E1M7']).Hash -and $aliasCatalog.ContainsKey('D_E2M5') -and [IO.Path]::GetFullPath($aliasCatalog['D_E2M5']) -ceq [IO.Path]::GetFullPath($aliasReportPath))
    $p=Run 'missing' D_NOTREAL (Join-Path $dir 'missing') ''
    Check 'Missing WAD lump fails before track preparation or publication' ($p.Code -ne 0 -and -not $p.Report.Published -and $p.Report.Tracks.Count -eq 0 -and -not (Test-Path $p.Catalog) -and $p.Report.Error -match 'IWAD has no requested')
    $bad=Join-Path $dir 'wrong-bank.json';$data=Get-Content $qualification -Raw|ConvertFrom-Json -AsHashtable;$data.Details.BankSha256='0'*64;$data|ConvertTo-Json -Depth 12|Set-Content $bad
    $badSeed=Join-Path $dir 'bad-seed.json';@{D_E1M1=$bad}|ConvertTo-Json|Set-Content $badSeed
    $p=Run 'bank' D_E1M1 (Join-Path $dir 'bank') $badSeed
    Check 'Different soundfont identity rejects reuse without publishing' ($p.Code -ne 0 -and -not (Test-Path $p.Catalog) -and $p.Report.Error -match 'Qualified track assets differ')
    $lockRoot=Join-Path $dir 'locked';$null=[IO.Directory]::CreateDirectory($lockRoot)
    $held=[IO.File]::Open((Join-Path $lockRoot 'prepare.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $p=Run 'locked' D_E1M1 $lockRoot $seed
    Check 'Live exclusive preparation lock prevents a competing batch' ($p.Code -ne 0 -and -not (Test-Path $p.Catalog) -and $p.Report.Tracks.Count -eq 0)
    $held.Dispose();$held=$null
    $p=Run 'unlocked' D_E1M1 $lockRoot $seed
    Check 'Stale lock filename does not prevent a new owner after handle closure' ($p.Code -eq 0 -and $p.Report.Published)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($held){$held.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();Attempts=$attempts.ToArray();Directory=$dir;Sources=@('scripts/Prepare-DoomMusic.ps1','scripts/Test-MusicPreparation.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$root/$_").Hash}});
      Meaning='Real qualified-file reuse/resume and fresh-catalog publication, missing-lump and bank mismatch rejection, no overwrite, exclusive live lock and released-lock recovery. Does not exercise new synthesis; that requires its own preparation run.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) preparation control checks."
