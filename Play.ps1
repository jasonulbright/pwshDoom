#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param([string]$Wad,[ValidateSet('Classic','Matrix','AnsiArt')][string]$Style,
    [ValidateRange(1,32)][int]$Workers=16,[switch]$Silent,[switch]$Ascii,
    [switch]$Check,[ValidateRange(0,3600)][int]$Seconds=0,[string]$Report,[string]$MusicCatalog)
$ErrorActionPreference='Stop'
try{
    if($Silent -and $MusicCatalog){throw 'Choose -Silent or -MusicCatalog, not both. Omit -MusicCatalog for sound effects only.'}
    if($MusicCatalog){
        if(-not (Test-Path -LiteralPath $MusicCatalog -PathType Leaf)){throw 'Music catalog not found. Supply a catalog created by scripts/Prepare-DoomMusic.ps1.'}
        $MusicCatalog=(Resolve-Path -LiteralPath $MusicCatalog).Path
    }
    if(-not $IsWindows -or -not [Environment]::Is64BitProcess){throw 'This preview requires 64-bit PowerShell 7.4 or later on Windows.'}
    if(-not (Get-Command wt.exe -ErrorAction SilentlyContinue)){throw 'Install Windows Terminal, then open Play.cmd again. See https://aka.ms/terminal'}
    if(-not $Wad){
        foreach($candidate in @((Join-Path $PSScriptRoot 'DOOM.WAD'),
            "${env:ProgramFiles(x86)}/Steam/steamapps/common/Ultimate Doom/base/DOOM.WAD",
            "${env:ProgramFiles(x86)}/Steam/steamapps/common/DOOM + DOOM II/rerelease/doom.wad")){
            if(Test-Path -LiteralPath $candidate -PathType Leaf){$Wad=$candidate;break}
        }
        if(-not $Wad -and -not $Check){$Wad=(Read-Host 'Path to your Ultimate Doom DOOM.WAD (or place it beside Play.cmd)').Trim().Trim('"')}
    }
    if(-not $Wad){throw 'Supply your own Ultimate Doom IWAD: .\Play.ps1 -Wad "D:\Games\DOOM.WAD". No game assets are included.'}
    $Wad=(Resolve-Path -LiteralPath $Wad).Path
    $stream=[IO.File]::OpenRead($Wad);$reader=[IO.BinaryReader]::new($stream)
    try{
        if($stream.Length -lt 12 -or [Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -cne 'IWAD'){throw 'Select the Ultimate Doom IWAD (DOOM.WAD), not an add-on PWAD.'}
        $count=$reader.ReadInt32();$directory=$reader.ReadInt32()
        if($count -lt 1 -or $count -gt 100000 -or $directory -lt 12 -or [long]$directory+16L*$count -gt $stream.Length){throw 'The WAD directory is invalid or truncated.'}
        $maps=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $stream.Position=$directory
        for($i=0;$i -lt $count;$i++){
            $null=$reader.ReadInt32();$null=$reader.ReadInt32();$name=[Text.Encoding]::ASCII.GetString($reader.ReadBytes(8)).TrimEnd([char]0)
            if($name -match '^E[1-4]M[1-9]$'){[void]$maps.Add($name)}
        }
        if($maps.Count -ne 36){throw 'This preview launcher targets the 36-map Ultimate Doom IWAD. Doom II, Final Doom and add-on compatibility are not qualified yet.'}
    }finally{$reader.Dispose()}
    # Cache/report files must be writable without administrator rights.
    $local=Join-Path $PSScriptRoot 'local';[void][IO.Directory]::CreateDirectory($local)
    $probe=Join-Path $local ('write-check-'+[guid]::NewGuid().ToString('N'))
    try{[IO.File]::WriteAllText($probe,'');[IO.File]::Delete($probe)}catch{throw 'Extract the complete ZIP into a writable folder, such as Documents\pwshDoom.'}
    if($Check){
        [pscustomobject]@{Ready=$true;PowerShell=$PSVersionTable.PSVersion.ToString();Wad=$Wad;EpisodeMaps=$maps.Count;Root=$PSScriptRoot;WindowsTerminal=(Get-Command wt.exe).Source;MusicCatalog=$MusicCatalog;MusicValidation=if($MusicCatalog){'Track qualification and WAD identity are checked at audio startup; -Check verifies path only.'}else{'Effects only; no music catalog requested.'}}
        return
    }
    Write-Host "`npwshDoom — playable preview" -ForegroundColor Green
    if(-not $Style){
        Write-Host '1  Classic Doom pixels'
        Write-Host '2  Matrix — green katakana'
        Write-Host '3  Color art — colored katakana'
        $choice=Read-Host 'Choose a style [1]'
        $Style=switch($choice){'2'{'Matrix'};'3'{'AnsiArt'};''{'Classic'};'1'{'Classic'};default{throw 'Choose 1, 2 or 3.'}}
    }
    Write-Host "Opening $Style. First startup can take a minute."
    Write-Host 'WASD move | arrows turn | Ctrl fire | E use | Escape menu | Tab map'
    if($MusicCatalog){Write-Host 'Prepared music enabled. Your catalog must cover the maps, intermissions and endings you play.'}
    else{Write-Host 'Sound effects are on unless -Silent is supplied. Use -MusicCatalog with your prepared catalog to enable music.'}
    Write-Host 'If the game asks for more space, reduce Terminal font size with Ctrl+minus.'
    $launch=@{Wad=$Wad;Style=$Style;Workers=$Workers;Maximized=$true;Sound=(-not $Silent);Seconds=$Seconds}
    if($Ascii){$launch.GlyphSet='Ascii'}
    if($Report){$launch.Report=[IO.Path]::GetFullPath($Report)}
    if($MusicCatalog){$launch.MusicCatalog=$MusicCatalog}
    & "$PSScriptRoot/Start-Doom.ps1" @launch
}catch{
    Write-Host "`npwshDoom could not start: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
