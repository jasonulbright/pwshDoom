#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Wad,
    [int[]]$WorkerCounts=@(1,2,4,6,8),[int]$Samples=32,
    [string]$Output=(Join-Path $PSScriptRoot '../results/parallel-scene.json'))
$ErrorActionPreference='Stop'
. "$PSScriptRoot/ParallelScene.ps1"
$scene=& "$PSScriptRoot/Measure-DoomScene.ps1" -Wad $Wad -InitializeOnly
. ([scriptblock]::Create($scene.BspDefinition))
$reference=[byte[]]::new(64000)
$render=New-DoomRenderArguments $scene $reference
$references=[Collections.Generic.List[byte[]]]::new()
for($i=0;$i -lt 8;$i++){
    $render.pang=$scene.Level.startA+$i*[Math]::PI/4
    [Array]::Clear($reference);$null=Get-BspFrame @render;$references.Add($reference.Clone())
}
$originalReferences=$references.ToArray()
. ([scriptblock]::Create((Get-StripBspDefinition $scene.BspDefinition)))
$render.startColumn=0;$render.endColumn=320
$references=[Collections.Generic.List[byte[]]]::new()
$serialChanges=@()
for($i=0;$i -lt 8;$i++){
    $render.pang=$scene.Level.startA+$i*[Math]::PI/4
    [Array]::Clear($reference);$null=Get-BspFrame @render;$references.Add($reference.Clone())
    $different=0
    for($p=0;$p -lt 64000;$p++){if($reference[$p] -ne $originalReferences[$i][$p]){$different++}}
    $serialChanges+=$different
}
$report=[ordered]@{RecordedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
    Width=320;Height=200;WadSha256=$scene.WadSha256;SourceSha256=$scene.SourceSha256;
    Meaning='PowerShell persistent worker runspaces; geometry and strip encoding. No output/gameplay; not displayed FPS.';
    InterpolationChangesAgainstUpstream=$serialChanges;Results=@()}
$freq=[Diagnostics.Stopwatch]::Frequency
foreach($count in $WorkerCounts){
    $pool=$null
    try {
        $pool=New-ParallelScene $scene $count
        $mismatches=@()
        for($i=0;$i -lt 8;$i++){
            Invoke-ParallelScene $pool ($scene.Level.startA+$i*[Math]::PI/4) $false
            $different=0
            for($p=0;$p -lt 64000;$p++){if($pool.Buffer[$p] -ne $references[$i][$p]){$different++}}
            $mismatches+=$different
        }
        for($warm=0;$warm -lt 64;$warm++){Invoke-ParallelScene $pool ($scene.Level.startA+($warm%8)*[Math]::PI/4)}
        $times=[double[]]::new($Samples);$byteCounts=[double[]]::new($Samples)
        for($i=0;$i -lt $Samples;$i++){
            $before=[Diagnostics.Stopwatch]::GetTimestamp()
            Invoke-ParallelScene $pool ($scene.Level.startA+($i%8)*[Math]::PI/4)
            $times[$i]=([Diagnostics.Stopwatch]::GetTimestamp()-$before)*1000.0/$freq
            $byteCounts[$i]=($pool.Workers | ForEach-Object {$_.Bytes.Length} | Measure-Object -Sum).Sum
        }
        $result=@{Workers=$count;RenderAndEncodeMs=(Get-SampleStats $times);Bytes=(Get-SampleStats $byteCounts);
            PixelMismatchesByHeading=$mismatches;SamplesMs=$times;
            LastWorkerTimings=@($pool.Workers | ForEach-Object { @{RenderMs=$_.RenderMs;EncodeMs=$_.EncodeMs;StartQpc=$_.StartQpc;EndQpc=$_.EndQpc} })}
        $report.Results+=$result
        $report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $Output
        Write-Host ("$count workers: {0:N2} ms median, {1:N2} ms p95; reference mismatches: {2}" -f $result.RenderAndEncodeMs.Median,$result.RenderAndEncodeMs.P95,($mismatches -join ','))
    } finally {if($pool){Close-ParallelScene $pool}}
}
