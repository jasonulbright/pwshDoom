#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$reports=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Read-Report([string]$Name){
    $path=Join-Path $root "results/$Name.json";$reports.Add(@{Path="results/$Name.json";Sha256=(Get-FileHash $path).Hash})
    $r=Get-Content $path -Raw|ConvertFrom-Json;Check "$Name has no error" (-not $r.Error);return $r
}
try{
    $unit=Read-Report 'music-synth-unit-fused-edges'
    Check 'All 51 synthesis checks pass' ($unit.Checks.Count -eq 51 -and @($unit.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
    foreach($source in $unit.Sources){Check "Unit source matches: $($source.Path)" ((Get-FileHash (Join-Path $root $source.Path)).Hash -ceq $source.Sha256)}
    $short=Read-Report 'music-e1m1-dry-first'
    foreach($name in 'music-profile-baseline','music-profile-static-cache','music-profile-pcm-cache','music-profile-fused-first'){
        $r=Read-Report $name
        Check "$name unchanged render inputs" ($r.WadSha256 -ceq $short.WadSha256 -and $r.Details.MusSha256 -ceq $short.Details.MusSha256 -and $r.Details.SoundFontSha256 -ceq $short.Details.SoundFontSha256 -and $r.Details.Volume -eq $short.Details.Volume -and $r.Details.Frames -eq $short.Details.Frames)
        Check "$name exact eight-second WAV" ($r.Details.WavSha256 -ceq $short.Details.WavSha256 -and (Get-FileHash $r.Details.WavPath).Hash -ceq $short.Details.WavSha256)
        Check "$name no source edits during rendering" ($r.SourcesChangedDuringRun.Count -eq 0)
    }
    $old=Read-Report 'music-e1m1-dry-loop';$current=Read-Report 'music-e1m1-dry-optimized-loop'
    foreach($key in 'MusSha256','SoundFontSha256','Volume','Frames','Seconds','NoteOns','PeakVoices','ExclusiveCuts','ClippedSamples','PeakPcm','RmsPcm','NonzeroSamples'){
        Check "Full loop preserves $key" ($old.Details.$key -ceq $current.Details.$key)
    }
    Check 'Full loop uses the same IWAD' ($old.WadSha256 -ceq $current.WadSha256)
    Check 'Complete 98-second WAV hash preserved' ($old.Details.WavSha256 -ceq $current.Details.WavSha256)
    foreach($r in @($old,$current)){Check "Local full WAV verified: $($r.Details.WavPath)" ((Get-FileHash $r.Details.WavPath).Hash -ceq $r.Details.WavSha256)}
    Check 'Final full render has no profiler' ($null -eq $current.Details.Profile)
    Check 'Final full render has no source drift' ($current.SourcesChangedDuringRun.Count -eq 0)
    foreach($source in $current.Sources){
        $path=Join-Path $root $source.Path;Check "Full render source matches: $($source.Path)" ((Get-FileHash $path).Hash -ceq $source.Sha256)
        $parseTokens=$null;$parseErrors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$parseTokens,[ref]$parseErrors)
        Check "Source parses: $($source.Path)" ($parseErrors.Count -eq 0)
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Reports=$reports.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Evidence audit of retained checks and exact canonical WAV identity across PowerShell optimization stages. Timings are observations, not repeated paired benchmarks. No device, deadline, acoustic or reference-model fidelity qualification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) music optimization evidence checks."
