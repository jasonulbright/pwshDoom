#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Qualification="$PSScriptRoot/../results/music-loop-e1m1-hour-bound.json")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$root/local/music-events-$PID.ps1";. $bundle;. "$root/src/MusicEvents.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null;$content=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $Name $rejected}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $events=[DoomMusicEvents]::new();$options.Music=$events;$game=[DoomGame]::new($content,$options);$game.InitNew([GameSkill]::Medium,1,1)
    $batch=$events.Drain();Check 'Actual world initialization emits E1M1 music callback' ($batch.Count -eq 1 -and $batch[0].Kind -ceq 'Start' -and $batch[0].Track -ceq 'D_E1M1' -and $batch[0].Loop)
    Check 'Draining callbacks is destructive exactly once' ($events.Drain().Count -eq 0)
    $events.set_Volume(30);$events.set_Volume(-5);$batch=$events.Drain()
    Check 'Engine music volume clamps to conventional range and emits gain' ($events.get_MaxVolume() -eq 15 -and $events.get_Volume() -eq 0 -and $batch[0].Value -eq .2 -and $batch[1].Value -eq 0)
    $events.StartMusic([Bgm]::INTRO,$false);$events.StartMusic([Bgm]::NONE,$true);$batch=$events.Drain()
    Check 'One-shot flag and explicit stop are preserved' ($batch[0].Track -ceq 'D_INTRO' -and -not $batch[0].Loop -and $batch[1].Kind -ceq 'Stop')
    Sync-DoomMusicSession $events $game;$batch=$events.Drain();Check 'Loaded level synchronizes its actual map music' ($batch.Count -eq 1 -and $batch[0].Track -ceq 'D_E1M1')
    $fake=@{State=[GameState]::Intermission;Options=$options};Sync-DoomMusicSession $events $fake;Check 'Ultimate Doom intermission mapping' ($events.Drain()[0].Track -ceq 'D_INTER')
    $options.Episode=1;$fake=@{State=[GameState]::Finale;Options=$options;Finale=@{stage=0}};Sync-DoomMusicSession $events $fake;Check 'Episode one finale restores victory score' ($events.Drain()[0].Track -ceq 'D_VICTOR')
    $options.Episode=3;$fake=@{State=[GameState]::Finale;Options=$options;Finale=@{stage=0}};Sync-DoomMusicSession $events $fake;Check 'Episode three text finale uses victory score' ($events.Drain()[0].Track -ceq 'D_VICTOR')
    $fake.Finale.stage=1;Sync-DoomMusicSession $events $fake;Check 'Episode three art stage restores bunny score' ($events.Drain()[0].Track -ceq 'D_BUNNY')
    $options.Episode=4;Sync-DoomMusicSession $events $fake;Check 'Other Ultimate Doom art finales retain victory score' ($events.Drain()[0].Track -ceq 'D_VICTOR')
    $catalog="$root/local/music-catalog-test-$PID.json";@{D_E1M1=[IO.Path]::GetFullPath($Qualification)}|ConvertTo-Json|Set-Content $catalog
    $reports=Read-DoomMusicCatalog $catalog $content;Check 'Catalog validates qualified score against actual IWAD bytes' ($reports.Count -eq 1 -and $reports.ContainsKey('D_E1M1'))
    $bad="$root/local/music-catalog-mismatch-$PID.json";@{D_E1M2=[IO.Path]::GetFullPath($Qualification)}|ConvertTo-Json|Set-Content $bad
    Reject 'Mismatched map/qualification catalog rejected' {$null=Read-DoomMusicCatalog $bad $content}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();WadSha256=(Get-FileHash $Wad).Hash;SourceSha256=(Get-FileHash "$root/src/MusicEvents.ps1").Hash;ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Actual engine initialization callback plus isolated Ultimate Doom save-state music selection and IWAD/catalog identity checks. Non-E1M1 tracks are selection tests only; they are not playback qualifications.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) music event checks."
