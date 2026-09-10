#requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Wad,[int[]]$WorkerCounts=@(1,2,4,8),[int]$Samples=32,
    [ValidateSet('TrueColor','Ansi256')][string]$ColorMode='TrueColor',
    [string]$Output=(Join-Path $PSScriptRoot '../results/process-scene.json'))
$ErrorActionPreference='Stop'
. "$PSScriptRoot/ProcessScene.ps1"
$scene=& "$PSScriptRoot/Measure-DoomScene.ps1" -Wad $Wad -InitializeOnly
. ([scriptblock]::Create((Get-StripBspDefinition $scene.BspDefinition)))
$reference=[byte[]]::new(64000);$render=New-DoomRenderArguments $scene $reference
$render.startColumn=0;$render.endColumn=320
$references=[Collections.Generic.List[byte[]]]::new()
for($i=0;$i -lt 8;$i++){
    $render.pang=$scene.Level.startA+$i*[Math]::PI/4
    [Array]::Clear($reference);$null=Get-BspFrame @render;$references.Add($reference.Clone())
}
$report=[ordered]@{RecordedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
    Width=320;Height=200;ColorMode=$ColorMode;WadSha256=$scene.WadSha256;SourceSha256=$scene.SourceSha256;
    Meaning='PowerShell persistent processes; geometry, strip encoding and shared-memory transfer. No terminal output/gameplay; not displayed FPS.';Results=@()}
$freq=[Diagnostics.Stopwatch]::Frequency
foreach($count in $WorkerCounts){
    $pool=$null
    try {
        $pool=New-ProcessScene $Wad $count $ColorMode
        $mismatches=@()
        for($i=0;$i -lt 8;$i++){
            Invoke-ProcessScene $pool ($scene.Level.startA+$i*[Math]::PI/4) $false
            $different=0
            for($p=0;$p -lt 64000;$p++){if($pool.Buffer[$p] -ne $references[$i][$p]){$different++}}
            $mismatches+=$different
        }
        if(($mismatches | Measure-Object -Sum).Sum -ne 0){throw 'Process rendering differs from the serial strip renderer.'}
        for($warm=0;$warm -lt 32;$warm++){Invoke-ProcessScene $pool ($scene.Level.startA+($warm%8)*[Math]::PI/4)}
        $times=[double[]]::new($Samples);$byteCounts=[double[]]::new($Samples)
        for($i=0;$i -lt $Samples;$i++){
            $before=[Diagnostics.Stopwatch]::GetTimestamp()
            Invoke-ProcessScene $pool ($scene.Level.startA+($i%8)*[Math]::PI/4)
            $times[$i]=([Diagnostics.Stopwatch]::GetTimestamp()-$before)*1000.0/$freq
            $byteCounts[$i]=($pool.Workers | ForEach-Object {$_.Bytes.Length} | Measure-Object -Sum).Sum
        }
        $result=@{Workers=$count;RenderAndEncodeTransferMs=(Get-SampleStats $times);Bytes=(Get-SampleStats $byteCounts);
            PixelMismatchesByHeading=$mismatches;SamplesMs=$times;
            LastWorkerTimings=@($pool.Workers | ForEach-Object { @{RenderMs=$_.View.ReadDouble(24);EncodeAndPublishMs=$_.View.ReadDouble(32)} })}
        $report.Results+=$result
        $report | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $Output
        Write-Host ("$count processes: {0:N2} ms median, {1:N2} ms p95; all pixels match serial" -f $result.RenderAndEncodeTransferMs.Median,$result.RenderAndEncodeTransferMs.P95)
    } finally {if($pool){Close-ProcessScene $pool}}
}
