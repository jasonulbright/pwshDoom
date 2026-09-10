#requires -Version 7.4
$ErrorActionPreference='Stop'
$directory=Join-Path $env:LOCALAPPDATA 'Microsoft/Windows Terminal/Fragments/pwshDoom-study'
$fragment=Join-Path $directory 'benchmark.json'
if (Test-Path -LiteralPath $fragment) {
    $data=Get-Content -LiteralPath $fragment -Raw | ConvertFrom-Json
    if (@($data.profiles).Count -ne 1 -or $data.profiles[0].guid -ne '{34f60d65-7977-49c3-9d73-39268493836f}') {
        throw 'The fragment does not match the study profile; leaving it in place.'
    }
    Remove-Item -LiteralPath $fragment
    if (@(Get-ChildItem -LiteralPath $directory -Force).Count -eq 0) { Remove-Item -LiteralPath $directory }
    Write-Host 'Removed only the study Terminal profile fragment.'
} else { Write-Host 'No study Terminal profile fragment is installed.' }
