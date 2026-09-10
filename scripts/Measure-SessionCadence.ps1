#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Session,[long]$QpcFrequency,
    [string]$Output="$PSScriptRoot/../results/game-cadence.json")
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$data=Get-Content -LiteralPath $Session -Raw | ConvertFrom-Json
if($data.PSObject.Properties['QpcFrequency']){$QpcFrequency=$data.QpcFrequency}
if($QpcFrequency -le 0){throw 'Supply the recorded machine QPC frequency for older session reports.'}
$intervals=[Collections.Generic.List[double]]::new()
for($i=1;$i -lt $data.FrameStats.Count;$i++) {
    $intervals.Add(($data.FrameStats[$i].EndQpc-$data.FrameStats[$i-1].EndQpc)*1000.0/$QpcFrequency)
}
$miss16=0;$miss17=0;$miss33=0
foreach($ms in $intervals){if($ms -gt 1000.0/60){$miss16++};if($ms -gt 1000.0/60+1){$miss17++};if($ms -gt 1000.0/30){$miss33++}}
$report=@{AnalyzedUtc=[DateTime]::UtcNow.ToString('o');SessionFile=[IO.Path]::GetFileName($Session);
    SessionSha256=(Get-FileHash -LiteralPath $Session).Hash;QpcFrequency=$QpcFrequency;
    CompletedUpdatesPerSecond=$data.CompletedUpdatesPerSecond;TicsPerSecond=$data.TicsPerSecond;
    WriteIntervalMs=(Get-SampleStats $intervals.ToArray());IntervalsOver16_667ms=$miss16;IntervalsOver17_667ms=$miss17;IntervalsOver33_333ms=$miss33;
    RenderToWriteLatencyMs=$data.FrameMs;SimulationWorkMs=$data.Simulation.SimulationMs;SnapshotPublishMs=$data.Simulation.SnapshotPublishMs;
    SimulationStartLatenessMs=$data.Simulation.TickLatenessMs;
    Meaning='Intervals between consecutive completed writes from EndQpc. Render-to-write latency overlaps with the next frame and is not an output interval. The 60 Hz scheduler catches up after stalls; average throughput does not establish steady cadence or monitor presentations.'}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Output
$report | ConvertTo-Json -Depth 6
