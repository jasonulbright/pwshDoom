#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string[]]$Maps,[ValidateRange(1,5)][int]$Skill=3,[ValidateRange(1,350)][int]$Tics=35,
    [string]$Output="$PSScriptRoot/../local/campaign-smoke.json")
$ErrorActionPreference='Stop'
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Choose a fresh report path to preserve previous smoke results.'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Output))
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1";. "$PSScriptRoot/../src/GameHost.ps1"
$content=$null;$cases=[Collections.Generic.List[object]]::new();$mapNames=@();$fatal=$null;$active=$null
$wadHash=(Get-FileHash -LiteralPath $Wad).Hash
$sourcePaths=@(Get-ChildItem "$PSScriptRoot/../src" -Recurse -Filter *.ps1 -File | ForEach-Object FullName)+@($PSCommandPath,"$PSScriptRoot/Build-EngineBundle.ps1")
$sources=@(foreach($path in ($sourcePaths | Sort-Object -Unique)){@{Path=[IO.Path]::GetRelativePath([IO.Path]::GetFullPath("$PSScriptRoot/.."),$path);Sha256=(Get-FileHash -LiteralPath $path).Hash}})
function Write-CampaignSmokeReport([bool]$Complete) {
    $data=@{UpdatedUtc=[DateTime]::UtcNow.ToString('o');Complete=$Complete;FatalError=$fatal;ActiveCase=$active;
        WadSha256=$wadHash;PowerShell=$PSVersionTable.PSVersion.ToString();Skill=$Skill;RequestedTics=$Tics;
        Maps=$mapNames;Cases=$cases.ToArray();SourceFiles=$sources;
        Passed=@($cases | Where-Object Passed).Count;Failed=@($cases | Where-Object {-not $_.Passed}).Count;
        Meaning='Headless map loading, bounded idle simulation, and two full 320x200 serial rasterizations at the resulting player position. Hashes are reproducibility fingerprints, not reference-image correctness. No navigation, exit, moving-special coverage, keyboard play, audio, parallel transport, or campaign completion is established. Stage timings include cold work and are not a gameplay FPS benchmark.'}
    $data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
}
try {
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    $available=@($content.Wad.lumpInfos | ForEach-Object {$_.getName()} | Where-Object {$_ -match '^E[1-4]M[1-9]$'} | Sort-Object -Unique)
    if(-not $available.Count){throw 'This smoke harness currently inventories Ultimate Doom episode/map markers.'}
    $mapNames=if($Maps){@($Maps | Sort-Object -Unique)}else{$available}
    foreach($name in $mapNames){if($name -notin $available){throw "Map is absent from the IWAD: $name"}}
    foreach($name in $mapNames) {
        $record=@{Map=$name;Passed=$false;Stage='Load';CompletedTics=0;FrameHashes=@();Error=$null;LoadMs=$null;SimulationMs=$null;ContextMs=$null;RenderMs=@()}
        $active=@{Map=$name;Stage='Load'};Write-CampaignSmokeReport $false
        try {
            $watch=[Diagnostics.Stopwatch]::StartNew();$options=[GameOptions]::new()
            $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
            $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4)
            for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
            $game.DeferedInitNew([GameSkill]($Skill-1),[int]::Parse($name.Substring(1,1)),[int]::Parse($name.Substring(3,1)))
            $null=$game.Update($commands);$record.LoadMs=$watch.Elapsed.TotalMilliseconds
            $record.Stage='Simulation';$active.Stage=$record.Stage;Write-CampaignSmokeReport $false;$watch.Restart()
            for($i=0;$i -lt $Tics;$i++){$null=$game.Update($commands);$record.CompletedTics++;if($game.State -ne [GameState]::Level){throw 'Idle simulation unexpectedly left the level.'}}
            $record.SimulationMs=$watch.Elapsed.TotalMilliseconds;$record.Health=$game.World.ConsolePlayer.Health
            $record.TotalKills=$game.World.TotalKills;$record.Lines=$game.World.Map.Lines.Count;$record.Sectors=$game.World.Map.Sectors.Count
            $record.Stage='RenderContext';$active.Stage=$record.Stage;Write-CampaignSmokeReport $false;$watch.Restart()
            $context=New-FastRenderContext $content $game.World;$record.ContextMs=$watch.Elapsed.TotalMilliseconds
            $record.Stage='Render';$active.Stage=$record.Stage;Write-CampaignSmokeReport $false
            foreach($headingOffset in 0,90) {
                $snapshot=New-GameRenderSnapshot $game;$snapshot.ConsolePlayer.Mobj.Angle+=$headingOffset*[Math]::PI/180
                Set-GameRenderSnapshot $context $snapshot;$watch.Restart();Invoke-FastRender $context
                $record.RenderMs+=,$watch.Elapsed.TotalMilliseconds
                if($context.Pixels.Length -ne 64000){throw 'Framebuffer dimensions changed.'}
                $varied=$false;foreach($pixel in $context.Pixels){if($pixel -ne $context.Pixels[0]){$varied=$true;break}}
                if(-not $varied){throw 'Framebuffer is a single color.'}
                $record.FrameHashes+=,@{HeadingOffset=$headingOffset;Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($context.Pixels))}
            }
            $record.Stage='Complete';$record.Passed=$true
        } catch {$record.Error=$_.ToString()+"`n"+$_.ScriptStackTrace}
        $cases.Add($record);$active=$null;Write-CampaignSmokeReport $false
        Write-Host "$name : $(if($record.Passed){'PASS'}else{'FAIL at '+$record.Stage})"
        $context=$null;$game=$null
    }
} catch {$fatal=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}
finally {Write-CampaignSmokeReport ($null -eq $fatal -and $cases.Count -eq $mapNames.Count);if($null -ne $content){$content.Dispose()}}
if(@($cases | Where-Object {-not $_.Passed}).Count){throw "Campaign smoke failures recorded in $Output"}
"PASS: $($cases.Count) map smoke cases. This does not establish campaign completion."
