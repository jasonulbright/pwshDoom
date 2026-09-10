# SPDX-License-Identifier: GPL-2.0-or-later
$ErrorActionPreference='Stop'
$path=Join-Path $env:LOCALAPPDATA 'Microsoft/Windows Terminal/Fragments/pwshDoom/game.json'
if(Test-Path -LiteralPath $path) {
    $profile=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if(@($profile.profiles).Count -ne 1 -or $profile.profiles[0].guid -ne '{10e095e7-c239-4a38-b6aa-14a957384ee5}') {throw 'The profile no longer matches pwshDoom; leaving it untouched.'}
    Remove-Item -LiteralPath $path
}
