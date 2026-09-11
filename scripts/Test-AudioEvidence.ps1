#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Read-Report([string]$Name){Get-Content (Join-Path $root "results/$Name.json") -Raw|ConvertFrom-Json}
function Get-CanonicalEvents($Events){
    # Hashtable property serialization order can differ across PowerShell processes.
    return (($Events|ForEach-Object {($_.PSObject.Properties|Sort-Object Name|ForEach-Object {"$($_.Name)=$($_.Value)"}) -join ';'}) -join '|')
}
try{
    $unit=Read-Report audio-mixer-cast;$device=Read-Report audio-device-first
    $initial=Read-Report audio-replay-legacy;$route=Read-Report audio-replay-cast
    $before=Read-Report audio-mixer-cost-baseline;$after=Read-Report audio-mixer-cost-cast
    Check 'Mixer checks pass' ($null -eq $unit.Error -and $unit.Checks.Count -eq 22 -and @($unit.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
    Check 'Playback checks and cleanup pass' ($null -eq $device.Error -and $null -eq $device.CleanupError -and $device.Checks.Count -eq 11 -and @($device.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
    foreach($report in $route,$after,$device){
        Check 'Accepted report has no error' ($null -eq $report.Error)
        foreach($source in $report.Sources){Check "Current source hash: $($source.Path)" ((Get-FileHash (Join-Path $root $source.Path)).Hash -eq $source.Sha256)}
    }
    Check 'Optimized replay matches all eight checkpoints' ($route.CheckpointComparison.Matched -and $route.CheckpointComparison.Checked -eq 8)
    Check 'Optimized route retains complete PCM hash' ($initial.WaveSha256 -eq $route.WaveSha256 -and (Get-FileHash $route.Wave).Hash -eq $route.WaveSha256)
    Check 'Optimized route retains ordered event stream' ((Get-CanonicalEvents $initial.Events) -ceq (Get-CanonicalEvents $route.Events))
    for($i=0;$i -lt 4;$i++){Check "Synthetic PCM identity: $($after.Cases[$i].Voices) voices" ($before.Cases[$i].PcmSha256 -eq $after.Cases[$i].PcmSha256)}
    foreach($path in 'src/AudioMixer.ps1','src/WaveOutDevice.ps1','scripts/Test-AudioMixer.ps1','scripts/Render-AudioReplay.ps1','scripts/Measure-AudioMixer.ps1','scripts/Test-WaveOutPlayback.ps1','scripts/Test-AudioEvidence.ps1'){
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$errors)
        Check "Standalone parse: $path" ($errors.Count -eq 0)
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Reports=@('audio-mixer-cast','audio-device-first','audio-replay-first','audio-replay-legacy','audio-replay-cast','audio-mixer-cost-baseline','audio-mixer-cost-cast'|ForEach-Object {@{Path="results/$_.json";Sha256=(Get-FileHash (Join-Path $root "results/$_.json")).Hash}});
      Sources=@('src/AudioMixer.ps1','src/AudioEvents.ps1','src/WaveOutDevice.ps1','scripts/Test-AudioMixer.ps1','scripts/Render-AudioReplay.ps1','scripts/Measure-AudioMixer.ps1','scripts/Test-WaveOutPlayback.ps1','scripts/Test-AudioEvidence.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path $root $_)).Hash}});
      Meaning='Accepted audio evidence hash/semantic audit. AudioEvents class loading is exercised by the actual engine replay, not standalone parsing. Historical reports pin earlier source versions. No live audio/render synchronization qualification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) audio evidence checks."
