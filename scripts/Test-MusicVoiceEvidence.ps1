#requires -Version 7.4
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=Split-Path $PSScriptRoot;$checks=[Collections.Generic.List[object]]::new();$sources=[Collections.Generic.List[object]]::new();$reports=@{};$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    foreach($name in 'music-regions-unit-first','music-oscillator-unit-final','music-note-coverage-first','music-oscillator-cost-quiescent'){
        $r=Get-Content (Join-Path $root "results/$name.json") -Raw|ConvertFrom-Json;$reports[$name]=$r
        Check "$name successful" (-not $r.Error)
        foreach($s in $r.Sources){Check "$name current source $($s.Path)" ((Get-FileHash (Join-Path $root $s.Path)).Hash -ceq $s.Sha256)}
    }
    foreach($name in 'music-regions-unit-first','music-oscillator-unit-final'){Check "$name every named check passed" (@($reports[$name].Checks|Where-Object {-not $_.Passed}).Count -eq 0)}
    Check '16 region and 11 oscillator checks' ($reports['music-regions-unit-first'].Checks.Count -eq 16 -and $reports['music-oscillator-unit-final'].Checks.Count -eq 11)
    $coverage=$reports['music-note-coverage-first']
    Check 'Every note in 32 full tracks resolves' ($coverage.Tracks.Count -eq 32 -and @($coverage.Tracks|Where-Object {-not $_.EveryNoteCovered}).Count -eq 0 -and ($coverage.Tracks|Measure-Object NoteOns -Sum).Sum -eq 71681)
    Check 'Region coverage includes layers and no skipped bank zones' ($coverage.Details.RegionStats.Regions -eq 2063 -and $coverage.Details.RegionStats.IgnoredZones -eq 0 -and ($coverage.Tracks|Measure-Object MaximumLayersPerNote -Maximum).Maximum -eq 6)
    $candidate=Get-Content (Join-Path $root 'results/music-oscillator-cost-segment.json') -Raw|ConvertFrom-Json
    $baseline=$reports['music-oscillator-cost-quiescent']
    for($i=0;$i -lt 3;$i++){
        Check "Candidate preserved $($baseline.Trials[$i].Voices)-voice sample hash" ($candidate.Trials[$i].OutputFloat64Sha256 -ceq $baseline.Trials[$i].OutputFloat64Sha256)
        Check "Forty measured blocks retained for $($baseline.Trials[$i].Voices) voices" ($baseline.Trials[$i].Milliseconds.Count -eq 40)
    }
    foreach($path in 'src/SoundFontRegions.ps1','src/MusicOscillator.ps1','scripts/Test-SoundFontRegions.ps1','scripts/Test-MusicOscillator.ps1','scripts/Test-MusicNoteCoverage.ps1','scripts/Measure-MusicOscillator.ps1','scripts/Test-MusicVoiceEvidence.ps1'){
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$errors)
        Check "Parse $path" ($errors.Count -eq 0);$sources.Add(@{Path=$path;Sha256=(Get-FileHash (Join-Path $root $path)).Hash})
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=$sources.ToArray();AcceptedReports=@($reports.Keys|Sort-Object);Meaning='Region/oscillator primitive correctness, full-score note coverage and bounded cost evidence. Complete synthesis, live music and real-time deadlines remain unqualified.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) music voice evidence checks."
