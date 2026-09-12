#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$reports=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Read-Report([string]$Name){$path=Join-Path $root "results/$Name.json";$reports.Add(@{Path="results/$Name.json";Sha256=(Get-FileHash $path).Hash});return Get-Content $path -Raw|ConvertFrom-Json}
try{
    $unit=Read-Report 'music-groups-unit-notes';Check 'All 19 group and lifecycle checks pass' (-not $unit.Error -and $unit.Checks.Count -eq 19 -and @($unit.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
    foreach($source in $unit.Sources){Check "Unit source matches: $($source.Path)" ((Get-FileHash (Join-Path $root $source.Path)).Hash -ceq $source.Sha256)}
    $short=Read-Report 'music-e1m1-dry-first';$full=Read-Report 'music-e1m1-dry-numeric-loop';Check 'Original short and full references succeeded' (-not $short.Error -and -not $full.Error)
    foreach($name in 'music-groups-one-first','music-groups-two-serial-first','music-groups-two-parallel-fixed','music-groups-two-greedy-serial','music-groups-two-greedy-parallel','music-groups-two-greedy-full','music-groups-four-greedy-full','music-groups-notes-two-serial','music-groups-notes-two-parallel','music-groups-notes-two-full','music-groups-notes-four-full','music-groups-notes-four-function-short','music-groups-notes-four-inline-short','music-groups-notes-four-function-full'){
        $r=Read-Report $name;$d=$r.Details;Check "$name succeeded" (-not $r.Error)
        $reference=if($d.Seconds -eq 8){$short}else{$full}
        Check "$name preserves inputs and frame count" ($r.WadSha256 -ceq $reference.WadSha256 -and $d.MusSha256 -ceq $reference.Details.MusSha256 -and $d.SoundFontSha256 -ceq $reference.Details.SoundFontSha256 -and $d.Volume -eq $reference.Details.Volume -and $d.Frames -eq $reference.Details.Frames)
        Check "$name exact WAV verified on disk" ($d.WavSha256 -ceq $reference.Details.WavSha256 -and (Get-FileHash $d.WavPath).Hash -ceq $reference.Details.WavSha256)
        Check "$name comparison reports no changed samples" ($d.Comparison.ChangedSamples -eq 0 -and $d.Comparison.MaximumPcmDifference -eq 0 -and $d.Comparison.DifferenceRms -eq 0)
        $notes=0;$cuts=0;$peaks=0;foreach($worker in $d.Workers){$notes+=$worker.NoteOns;$cuts+=$worker.ExclusiveCuts;$peaks+=$worker.PeakVoices}
        Check "$name owns each reference note once and preserves cuts" ($notes -eq $reference.Details.NoteOns -and $cuts -eq $reference.Details.ExclusiveCuts)
        Check "$name stock fixture stays below the global voice bound" ($peaks -lt 256)
        Check "$name completed every worker and had no clipping" ($d.Workers.Count -eq $d.Groups -and @($d.Workers|Where-Object {$_.Frames -ne $d.Frames}).Count -eq 0 -and $d.ClippedSamples -eq 0)
        $cursor=0;$sequence=$true;foreach($chunk in $d.Chunks){if($chunk.Frame -ne $cursor -or $chunk.Frames -le 0){$sequence=$false};$cursor+=$chunk.Frames}
        Check "$name chunk sequence is complete" ($sequence -and $cursor -eq $d.Frames -and $d.QueueCapacityPerWorker -eq 2)
        Check "$name sources remained unchanged during rendering" ($r.SourcesChangedDuringRun.Count -eq 0)
        if($d.GroupPolicy -eq 'RoundRobinNotes'){
            $distribution=$true
            for($id=0;$id -lt $d.Groups;$id++){if($d.Workers[$id].ProcessedNoteOns -ne $notes -or $d.Workers[$id].NoteOns -ne [Math]::Floor(($notes+$d.Groups-1-$id)/[double]$d.Groups)){$distribution=$false}}
            Check "$name distributes whole notes and broadcasts their control events" $distribution
        }
    }
    foreach($source in $r.Sources){
        $path=Join-Path $root $source.Path;Check "Final full source matches: $($source.Path)" ((Get-FileHash $path).Hash -ceq $source.Sha256)
        $parseTokens=$null;$parseErrors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$parseTokens,[ref]$parseErrors);Check "Final source parses: $($source.Path)" ($parseErrors.Count -eq 0)
    }
    $failed=Read-Report 'music-groups-two-parallel-first';Check 'Initial result-unwrapping failure remains recorded' ([bool]$failed.Error -and $failed.Error -match 'BaseObject')
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Reports=$reports.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Retained synthetic/runspace checks and exact WAV identity across group policies. Verifies fixture-level voice bounds, not general global admission. Timing observations and retrospective startup are not actual device, paced-consumer or gameplay-load qualification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) music group evidence checks."
