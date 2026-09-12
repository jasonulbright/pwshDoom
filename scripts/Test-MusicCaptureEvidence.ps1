#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$receipts=[Collections.Generic.List[object]]::new();$failure=$null;$sources=@();$timing=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Receipt([string]$Name){$path="$root/results/$Name.json";$receipts.Add(@{Path="results/$Name.json";Sha256=(Get-FileHash $path).Hash});return Get-Content $path -Raw|ConvertFrom-Json}
try{
    foreach($case in @(@('music-groups-hour-bound',22),@('music-loop-state-hour-bound',23),@('music-loop-reader-hour-bound',15),@('music-playback-hour-bound',13),@('music-events-hour-bound',11),@('music-audio-worker-hour-bound',10),@('music-loop-evidence-hour-bound-current',23),@('process-audio-capture-first',10))){
        $r=Receipt $case[0];Check "$($case[0]) targeted checks pass" (-not $r.Error -and $r.Checks.Count -eq $case[1] -and @($r.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
        if($r.PSObject.Properties['Sources']){foreach($s in $r.Sources){Check "Current receipt source: $($s.Path)" ($s.Sha256 -ceq (Get-FileHash "$root/$($s.Path)").Hash)}}
    }
    $old=Receipt 'music-loop-e1m1-first';$new=Receipt 'music-loop-e1m1-hour-bound'
    Check 'Requalification passed with unchanged canonical PCM' ($new.Details.Qualified -and -not $new.Error -and $new.Details.Reference.Exact -and $new.Details.Reference.ActualPcmSha256 -ceq $old.Details.Reference.ActualPcmSha256)
    foreach($s in $new.Sources){Check "Requalification source is current: $($s.Path)" ($s.Sha256 -ceq (Get-FileHash "$root/$($s.Path)").Hash)}
    for($i=0;$i -lt 3;$i++){$p=$new.Details.Periods[$i];Check "Complete period $i unchanged and retained on disk" ($p.Sha256 -ceq $old.Details.Periods[$i].Sha256 -and $p.Sha256 -ceq (Get-FileHash $p.Path).Hash -and $p.Bytes -eq (Get-Item $p.Path).Length)}
    $failed=Receipt 'music-loop-evidence-hour-bound';Check 'Stale state-test source failure remains recorded' ($failed.Error -match 'State unit source current: src/MusicGroup.ps1')
    $capture=Receipt 'process-audio-capture-first';$d=$capture.Details;$r=$d.Capture
    Check 'Retained capture WAV has the recorded digest and exact frame length' ((Get-FileHash $r.WavPath).Hash -ceq $r.WavSha256 -and (Get-Item $r.WavPath).Length -eq 44+4*$r.Frames)
    Check 'Retained local capture report matches portable embedded report receipt' ((Get-FileHash "$($d.Directory)/capture.json").Hash -ceq $d.CaptureReportSha256)
    [long]$frames=0;[long]$nextDevice=-1;[ulong]$previousQpc=0;$continuous=$true;$deviceContinuous=$true;$timestamps=$true;$gaps=[Collections.Generic.List[object]]::new()
    for($i=0;$i -lt $r.Packets.Count;$i++){
        $p=$r.Packets[$i]
        if($p.Index -ne $i -or $p.OutputFrame -ne $frames -or $p.Frames -le 0){$continuous=$false}
        if($nextDevice -ge 0 -and $p.DevicePosition -ne $nextDevice){$deviceContinuous=$false}
        if(($p.Flags -band 5) -or $p.Qpc100ns -le $previousQpc){$timestamps=$false}
        if($i -gt 0){$residual=$p.Qpc100ns-$previousQpc-$r.Packets[$i-1].Frames*10000000.0/$r.Rate;if([Math]::Abs($residual) -gt 2){$gaps.Add(@{Packet=$i;OutputFrame=$p.OutputFrame;Residual100ns=$residual;Flags=$p.Flags})}}
        $frames+=$p.Frames;$nextDevice=$p.DevicePosition+$p.Frames;$previousQpc=$p.Qpc100ns
    }
    Check 'All captured packets account for contiguous WAV output frames' ($continuous -and $frames -eq $r.Frames)
    Check 'Packet QPC values increase and no API error flags are set in this fixture' $timestamps
    $timing=@{DevicePositionsContiguous=$deviceContinuous;DevicePositionsAllZero=(@($r.Packets|Where-Object {$_.DevicePosition -ne 0}).Count -eq 0);QpcGaps=$gaps.ToArray();
        ContinuousTimelineQualified=($deviceContinuous -and $timestamps -and $gaps.Count -eq 0);Meaning='Passing evidence integrity does not qualify capture timeline continuity. Nonzero QPC residuals are retained even without API discontinuity flags; their cause is unclassified.'}
    $timingFailure=Receipt 'music-capture-milestone-validation';Check 'Initial device-position continuity rejection is preserved' ($timingFailure.Error -match 'All captured packets have contiguous device/output frame positions')
    Check 'Owned source identities and scoped capture are distinct' ($d.Target.ProcessId -eq $r.TargetProcessId -and $d.Target.ProcessId -ne $d.Sibling.ProcessId)
    Check 'Frequency windows establish selected audio and sibling suppression' ($d.SelectedTone.Amplitude -gt 20 -and $d.SiblingTone.Amplitude -lt $d.SelectedTone.Amplitude*.01 -and $d.QuietWindow.Rms -lt [Math]::Max(2,$d.SelectedTone.Rms*.01))
    $sources='src/ProcessAudioCapture.ps1','scripts/Record-ProcessAudio.ps1','scripts/Invoke-CaptureTestTone.ps1','scripts/Test-ProcessAudioCapture.ps1','scripts/Test-MusicCaptureEvidence.ps1'
    foreach($path in $sources){$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile("$root/$path",[ref]$tokens,[ref]$errors);Check "Parse $path" ($errors.Count -eq 0)}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Receipts=$receipts.ToArray();CaptureTiming=$timing;Sources=@($sources|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$root/$_").Hash}});
      Meaning='Current-source receipt audit, complete E1M1 sample retention and process-capture packet continuity/scope evidence. Longer soundtrack jobs are still in progress and are excluded from qualification. No new campaign completion, game-load capture, audiovisual synchronization, acoustic measurement or performance qualification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) music/capture evidence checks."
