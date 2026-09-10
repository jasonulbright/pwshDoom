#requires -Version 7.4
[CmdletBinding()]
param([string]$Plan = (Join-Path $PSScriptRoot '../local/plan.json'),
    [string]$Output = (Join-Path $PSScriptRoot '../results/terminal.json'),
    [int]$HoldSeconds = 0, [switch]$Live, [string]$DoomWad, [switch]$Probe)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$runtime=(Get-Process -Id $PID).Path
$fragmentDir=Join-Path $env:LOCALAPPDATA 'Microsoft/Windows Terminal/Fragments/pwshDoom-study'
[void][IO.Directory]::CreateDirectory($fragmentDir)
$fragment=Join-Path $fragmentDir 'benchmark.json'
if (Test-Path -LiteralPath $fragment) {
    $existing=Get-Content -LiteralPath $fragment -Raw | ConvertFrom-Json
    if (@($existing.profiles).Count -ne 1 -or $existing.profiles[0].guid -ne '{34f60d65-7977-49c3-9d73-39268493836f}') {
        throw 'An unrelated fragment occupies the study path; leaving it unchanged.'
    }
}
$profile=@{profiles=@(@{guid='{34f60d65-7977-49c3-9d73-39268493836f}';name='pwshDoom Study';commandline=$runtime;
    startingDirectory=$root;font=@{face='Cascadia Mono';size=7};antialiasingMode='aliased';padding='0';
    useAcrylic=$false;opacity=100;scrollbarState='hidden';closeOnExit='graceful';suppressApplicationTitle=$true;tabTitle='pwshDoom benchmark'})}
$profile | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $fragment -Encoding utf8
# Adds only a study profile, never edits the user's settings.json or default profile.
if ($Probe) {
    & wt.exe -w new --size 324,105 new-tab -p 'pwshDoom Study' $runtime -NoProfile -File (Join-Path $PSScriptRoot 'Get-TerminalProbe.ps1') -VerifyGlyphWidth -Output ([IO.Path]::GetFullPath($Output))
} elseif ($DoomWad) {
    & wt.exe -w new --size 324,105 new-tab -p 'pwshDoom Study' $runtime -NoProfile -File (Join-Path $PSScriptRoot 'Measure-DoomScene.ps1') -Live -Wad ([IO.Path]::GetFullPath($DoomWad)) -Output ([IO.Path]::GetFullPath($Output))
} elseif ($Live) {
    & wt.exe -w new --size 324,105 new-tab -p 'pwshDoom Study' $runtime -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-LiveTerminalBench.ps1') -Output ([IO.Path]::GetFullPath($Output))
} else {
    & wt.exe -w new --size 324,105 new-tab -p 'pwshDoom Study' $runtime -NoProfile -File (Join-Path $PSScriptRoot 'Invoke-TerminalBench.ps1') -Plan ([IO.Path]::GetFullPath($Plan)) -Output ([IO.Path]::GetFullPath($Output)) -HoldSeconds $HoldSeconds
}
