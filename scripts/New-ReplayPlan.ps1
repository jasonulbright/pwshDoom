#requires -Version 7.4
[CmdletBinding()]
param([ValidateSet('Synthetic','Doom')][string]$Dataset='Synthetic',
    [ValidateRange(1,1000)][int]$TargetRate=165,
    [ValidateRange(1,60)][int]$Seconds=4,
    [string]$Output=(Join-Path $PSScriptRoot '../local/plan.json'))
$ErrorActionPreference='Stop'
$cases=[Collections.Generic.List[object]]::new()
foreach ($repeat in 1,2) {
    if ($Dataset -eq 'Synthetic') {
        foreach ($pattern in 'Coherent','Entropy') { foreach ($colors in 16,256) { foreach ($sync in $false,$true) {
            $order=if ($repeat -eq 1) { @('Ansi','Sixel') } else { @('Sixel','Ansi') }
            foreach ($codec in $order) { $cases.Add(@{Id="$codec-320x200-$colors-$pattern";Sync=$sync;Fps=$TargetRate;Seconds=$Seconds}) }
        } } }
    } else {
        foreach ($size in '147x92','320x200') {
            $order=if ($repeat -eq 1) { @('AnsiFast','Sixel','SixelFast') } else { @('SixelFast','Sixel','AnsiFast') }
            foreach ($codec in $order) { $cases.Add(@{Id="$codec-$size-Doom-E1M1";Sync=$true;Fps=$TargetRate;Seconds=$Seconds}) }
        }
    }
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Output)))
$cases.ToArray() | ConvertTo-Json | Set-Content -LiteralPath $Output
Write-Host "Wrote $($cases.Count) finite cases to $Output. Fps is a write pacing target, not a measured display rate."
