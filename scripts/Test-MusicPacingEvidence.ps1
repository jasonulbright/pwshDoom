#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Report,[Parameter(Mandatory)][string]$Output,
    [string]$ReferenceReport='results/music-e1m1-dry-numeric-loop.json')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$failure=$null;$qualification=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $r=Get-Content $Report -Raw|ConvertFrom-Json;$reference=Get-Content $ReferenceReport -Raw|ConvertFrom-Json
    Check 'Both renders completed' (-not $r.Error -and -not $reference.Error)
    $d=$r.Details;$p=$d.Pacing;$ref=$reference.Details
    Check 'Paced parallel note fixture' ($p.Enabled -and $d.Execution -eq 'Parallel' -and $d.GroupPolicy -eq 'RoundRobinNotes')
    Check 'Identical source assets, duration and volume' ($r.WadSha256 -ceq $reference.WadSha256 -and $d.MusSha256 -ceq $ref.MusSha256 -and $d.SoundFontSha256 -ceq $ref.SoundFontSha256 -and $d.Volume -eq $ref.Volume -and $d.Frames -eq $ref.Frames)
    Check 'Exact canonical WAVs verified on disk' ($d.WavSha256 -ceq $ref.WavSha256 -and (Get-FileHash $d.WavPath).Hash -ceq $ref.WavSha256 -and (Get-FileHash $ref.WavPath).Hash -ceq $ref.WavSha256)
    Check 'Sample comparison agrees' ($d.Comparison.ChangedSamples -eq 0 -and $d.Comparison.MaximumPcmDifference -eq 0 -and $d.Comparison.DifferenceRms -eq 0 -and $d.Comparison.ReportSha256 -ceq (Get-FileHash $ReferenceReport).Hash)
    Check 'Capacity and duration have consistent frame units' ($p.PrefillFrames -eq $p.PrefillChunks*$d.BlocksPerChunk*1260 -and $d.Frames -eq $d.Seconds*44100 -and $d.Frames -gt $p.PrefillFrames)
    Check 'Consumer actually waited and producers use bounded queues' ($p.ConsumerWaitSeconds -gt 0 -and $p.ConsumerWaitSeconds -lt $d.RenderSeconds -and $d.QueueCapacityPerWorker -eq 2)
    $startChunk=$d.Chunks[$p.PrefillChunks-1]
    Check 'Clock starts when prefill completes' ($startChunk.Frame+$startChunk.Frames -eq $p.PrefillFrames -and $p.PlaybackStartSeconds -eq $startChunk.CompletedSeconds -and $p.PlaybackStartSeconds -gt 0)
    [long]$cursor=0;[double]$previous=0;[int]$late=0;[double]$worst=0;[double]$peak=0;$firstLate=$null
    foreach($c in $d.Chunks){
        Check "Chunk $cursor has valid sequence and monotonic completion" ($c.Frame -eq $cursor -and $c.Frames -gt 0 -and $c.Frames -le $d.BlocksPerChunk*1260 -and $c.CompletedSeconds -ge $previous -and $c.CompletedSeconds -le $d.RenderSeconds)
        # Independently derive wall-clock deadlines from absolute sample positions.
        $deadline=$p.PlaybackStartSeconds+$c.Frame/44100.0
        $miss=if($c.Frame -lt $p.PrefillFrames -or $c.CompletedSeconds -le $deadline){0.0}else{$c.CompletedSeconds-$deadline}
        Check "Chunk $cursor recorded lateness matches deadline" ([Math]::Abs($c.LatenessSeconds-$miss) -lt 0.0000001)
        if($miss -gt 0){$late++;if($null -eq $firstLate){$firstLate=$c.Frame/44100.0};if($miss -gt $worst){$worst=$miss}}
        $cursor+=$c.Frames;$previous=$c.CompletedSeconds
        $played=if($c.CompletedSeconds -gt $p.PlaybackStartSeconds){($c.CompletedSeconds-$p.PlaybackStartSeconds)*44100.0}else{0.0}
        $ready=$cursor-$played
        Check "Chunk $($c.Frame) respects virtual ready-audio capacity" ($ready -le $p.PrefillFrames+0.001)
        if($ready -gt $peak){$peak=$ready}
    }
    Check 'Complete frame sequence' ($cursor -eq $d.Frames)
    Check 'Recorded timing aggregates agree' ($late -eq $p.LateChunks -and [Math]::Abs($worst*1000-$p.MaximumLatenessMilliseconds) -lt 0.0001 -and [Math]::Abs($peak-$p.PeakReadyFrames) -lt 0.001)
    Check 'Virtual end includes entire requested audio' ([Math]::Abs($p.VirtualPlaybackEndSeconds-($p.PlaybackStartSeconds+$d.Seconds)) -lt 0.0000001)
    $notes=0;$cuts=0;$peaks=0
    foreach($w in $d.Workers){$notes+=$w.NoteOns;$cuts+=$w.ExclusiveCuts;$peaks+=$w.PeakVoices;Check 'Worker completed all frames and broadcast notes' ($w.Frames -eq $d.Frames -and $w.ProcessedNoteOns -eq $ref.NoteOns)}
    Check 'Fixture notes, cuts, voice bounds and clipping preserved' ($d.Workers.Count -eq $d.Groups -and $notes -eq $ref.NoteOns -and $cuts -eq $ref.ExclusiveCuts -and $peaks -lt 256 -and $d.ClippedSamples -eq 0)
    Check 'No source changes during run' ($r.SourcesChangedDuringRun.Count -eq 0)
    foreach($s in $r.Sources){Check "Current source matches: $($s.Path)" ((Get-FileHash (Join-Path $root $s.Path)).Hash -ceq $s.Sha256)}
    $qualification=@{MeetsVirtualDeadlines=($late -eq 0);LateChunks=$late;MaximumLatenessMilliseconds=$worst*1000;FirstLateAudioSeconds=$firstLate;PeakReadyFrames=$peak;DevicePlaybackQualified=$false;GameplayLoadQualified=$false}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Qualification=$qualification;ReportSha256=(Get-FileHash $Report).Hash;ReferenceReportSha256=(Get-FileHash $ReferenceReport).Hash;SourceSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Evidence-integrity checks can pass while deadline qualification fails. Recomputes virtual deadlines and ready-audio capacity from retained chunks; exact WAV identity preserves the chosen dry model. No device, acoustic, gameplay-load or arbitrary-score qualification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) evidence checks; virtual deadlines met: $($qualification.MeetsVirtualDeadlines)."
