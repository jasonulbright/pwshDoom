#requires -Version 7.4
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=Split-Path $PSScriptRoot;$checks=[Collections.Generic.List[object]]::new();$sources=[Collections.Generic.List[object]]::new();$reports=@{};$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    foreach($name in 'music-mus-unit-program-explicit','music-bank-unit-unsigned','music-iwad-inventory-program-mask','music-bank-inventory-current'){
        $report=Get-Content (Join-Path $root "results/$name.json") -Raw|ConvertFrom-Json;$reports[$name]=$report
        Check "$name successful" (-not $report.Error)
        foreach($source in $report.Sources){Check "$name current source $($source.Path)" ((Get-FileHash (Join-Path $root $source.Path)).Hash -ceq $source.Sha256)}
    }
    foreach($name in 'music-mus-unit-program-explicit','music-bank-unit-unsigned'){
        $r=$reports[$name];Check "$name all named checks passed" (@($r.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
    }
    Check '25 MUS and 21 bank named checks' ($reports['music-mus-unit-program-explicit'].Checks.Count -eq 25 -and $reports['music-bank-unit-unsigned'].Checks.Count -eq 21)
    $iwad=$reports['music-iwad-inventory-program-mask'];$bank=$reports['music-bank-inventory-current'];$previous=Get-Content (Join-Path $root 'results/music-iwad-inventory-stringkeys.json') -Raw|ConvertFrom-Json
    Check '32 complete track schedules and 36 map references' ($iwad.Tracks.Count -eq 32 -and $iwad.MapMusic.Count -eq 36 -and @($iwad.Tracks|Where-Object {-not $_.ScheduledEventsMatched}).Count -eq 0)
    $same=$true
    foreach($track in $iwad.Tracks){$old=@($previous.Tracks|Where-Object {$_.Name -ceq $track.Name});if($old.Count -ne 1 -or $old[0].ScheduledEventsSha256 -cne $track.ScheduledEventsSha256){$same=$false}}
    Check 'Program high-bit correction preserves all actual IWAD event hashes' $same
    Check 'Bank inventory uses current IWAD report' ($bank.MusicInventorySha256 -ceq (Get-FileHash (Join-Path $root 'results/music-iwad-inventory-program-mask.json')).Hash)
    Check '136 preset headers cover 52 observed melodic programs' ($bank.Details.Presets.Count -eq 136 -and $bank.Details.RequiredMelodicPrograms.Count -eq 52 -and $bank.Details.MissingMelodicPrograms.Count -eq 0)
    Check 'Bank has default drum preset' (@($bank.Details.DrumPresets|Where-Object {$_.Bank -eq 128 -and $_.Program -eq 0}).Count -eq 1)
    foreach($path in 'src/MusScore.ps1','src/SoundFontBank.ps1','scripts/Test-MusScore.ps1','scripts/Test-SoundFontBank.ps1','scripts/Test-MusicInventory.ps1','scripts/Test-MusicBankInventory.ps1','scripts/Test-MusicFoundationEvidence.ps1'){
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$errors)
        Check "Parse $path" ($errors.Count -eq 0);$sources.Add(@{Path=$path;Sha256=(Get-FileHash (Join-Path $root $path)).Hash})
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=$sources.ToArray();AcceptedReports=@($reports.Keys|Sort-Object);Meaning='Source freshness, bounded format/timeline tests and local asset inventories only. No music PCM synthesis, playback, fidelity or real-time deadline qualification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) music foundation evidence checks."
