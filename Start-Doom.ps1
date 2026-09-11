#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([string]$Wad,[ValidateRange(1,32)][int]$Workers=16,[ValidateRange(1,5)][int]$Skill=3,
    [ValidateRange(1,4)][int]$Episode=1,[ValidateRange(1,32)][int]$Map=1,
    [switch]$Here,[switch]$Scripted,[ValidateRange(0,3600)][int]$Seconds=0,[string]$Replay,[string]$RecordInput,[int]$CaptureEveryTics=0,
    [ValidateRange(4,24)][int]$FontSize=6,[switch]$Maximized,[switch]$Diagnostics,
    [ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic',
    [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Katakana',[string]$FontFace,
    [ValidateRange(0,30)][int]$ExitDelaySeconds=0,[string]$SessionSchedule,[string]$SaveRoot,
    [string]$Report="$PSScriptRoot/local/game-session.json")
$ErrorActionPreference='Stop'
if($Style -ne 'Classic' -and -not $PSBoundParameters.ContainsKey('FontSize')){$FontSize=12}
if(-not $FontFace){$FontFace=if($Style -ne 'Classic' -and $GlyphSet -eq 'Katakana'){'MS Gothic'}else{'Cascadia Mono'}}
if(-not $IsWindows){throw 'This prototype requires Windows and PowerShell 7.4 or later.'}
if(-not $Wad) {
    $candidates=@("${env:ProgramFiles(x86)}/Steam/steamapps/common/Ultimate Doom/base/DOOM.WAD",
        "${env:ProgramFiles(x86)}/Steam/steamapps/common/DOOM + DOOM II/rerelease/doom.wad")
    foreach($candidate in $candidates){if(Test-Path -LiteralPath $candidate){$Wad=$candidate;break}}
    if(-not $Wad){throw 'Supply your own classic Doom IWAD: .\Start-Doom.ps1 -Wad C:\path\DOOM.WAD'}
}
$Wad=(Resolve-Path -LiteralPath $Wad).Path
if($Replay){
    . "$PSScriptRoot/src/InputReplay.ps1"
    $inputReplay=Read-DoomInputReplay $Replay (Get-FileHash -LiteralPath $Wad).Hash
    $settings=Set-DoomReplaySettings $inputReplay $PSBoundParameters $Skill $Episode $Map
    $Skill=$settings.Skill;$Episode=$settings.Episode;$Map=$settings.Map
}
if($RecordInput -and (Test-Path -LiteralPath $RecordInput)){throw 'Input recording destination already exists; choose a new filename.'}
$arguments=@('-Wad',$Wad,'-Workers',"$Workers",'-Skill',"$Skill",'-Episode',"$Episode",'-Map',"$Map",'-Seconds',"$Seconds",'-Style',$Style,'-GlyphSet',$GlyphSet,'-Report',[IO.Path]::GetFullPath($Report))
if($RecordInput){$arguments+=@('-RecordInput',[IO.Path]::GetFullPath($RecordInput))}
if($SessionSchedule){$arguments+=@('-SessionSchedule',(Resolve-Path -LiteralPath $SessionSchedule).Path)}
if($SaveRoot){$arguments+=@('-SaveRoot',[IO.Path]::GetFullPath($SaveRoot))}
if($Scripted){$arguments+='-Scripted'}
if($Diagnostics){$arguments+='-Diagnostics'}
if($ExitDelaySeconds -gt 0){$arguments+=@('-ExitDelaySeconds',"$ExitDelaySeconds")}
if($Replay){$arguments+=@('-Replay',(Resolve-Path -LiteralPath $Replay).Path)}
if($CaptureEveryTics -gt 0){$arguments+=@('-CaptureEveryTics',"$CaptureEveryTics")}
$runtime=(Get-Process -Id $PID).Path
if($Here){& $runtime -NoProfile -File "$PSScriptRoot/scripts/Invoke-Doom.ps1" @arguments;exit $LASTEXITCODE}
$wt=Get-Command wt.exe -ErrorAction Stop
$profileDir=Join-Path $env:LOCALAPPDATA 'Microsoft/Windows Terminal/Fragments/pwshDoom'
[void][IO.Directory]::CreateDirectory($profileDir)
$profilePath=Join-Path $profileDir 'game.json';$guid='{10e095e7-c239-4a38-b6aa-14a957384ee5}'
if(Test-Path -LiteralPath $profilePath) {
    $existing=Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
    if(@($existing.profiles).Count -ne 1 -or $existing.profiles[0].guid -ne $guid){throw 'An unrelated profile occupies the game profile path.'}
}
# This is a separate removable profile. The user's defaults and settings.json are untouched.
@{profiles=@(@{guid=$guid;name='pwshDoom';commandline=$runtime;startingDirectory=$PSScriptRoot;
    font=@{face=$FontFace;size=$FontSize};antialiasingMode='aliased';padding='0';opacity=100;useAcrylic=$false;
    scrollbarState='hidden';closeOnExit='graceful';tabTitle='pwshDoom';suppressApplicationTitle=$true})} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $profilePath -Encoding utf8
$windowArguments=@('-w','new');if($Maximized){$windowArguments+='--maximized'}
$columns=if($Style -eq 'Classic'){320}else{160};$rows=if($Style -eq 'Classic'){100}else{50}
if($Diagnostics){$rows+=2}
& $wt.Source @windowArguments --size "$columns,$rows" new-tab -p 'pwshDoom' $runtime -NoProfile -File "$PSScriptRoot/scripts/Invoke-Doom.ps1" @arguments
if($LASTEXITCODE -ne 0){throw 'Windows Terminal launch failed.'}
