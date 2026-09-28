#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Qualification="$PSScriptRoot/../results/music-loop-e1m1-hour-bound.json",
    [string]$FinaleQualification,
    [string]$MapQualification,[ValidateRange(1,4)][int]$Episode=2,[ValidateRange(1,9)][int]$Map=7,
    [string]$CampaignCatalog)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$root/local/music-events-$PID.ps1";$bundleSha256=(Get-FileHash $bundle).Hash;$bundleBuilderSha256=(Get-FileHash "$root/scripts/Build-EngineBundle.ps1").Hash;. $bundle;. "$root/src/MusicEvents.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null;$content=$null;$mapSelection=$null;$finalePlayback=$null;$musicPlayback=$null;$campaignPlayback=$null;$campaignIntegration=$null
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
    $actualFinale=[Finale]::new($options);$initialFinaleMusic=$events.Drain()
    Check 'Actual Episode three finale constructor starts looping victory music' ($initialFinaleMusic.Count -eq 1 -and $initialFinaleMusic[0].Track -ceq 'D_VICTOR' -and $initialFinaleMusic[0].Loop)
    $actualFinale.TextSpeed=1;$actualFinale.TextWait=0;$actualFinale.count=$actualFinale.text.Length
    $finaleUpdate=$actualFinale.Update();$batch=$events.Drain()
    Check 'Actual Episode three finale text-to-art transition starts Bunny in loop mode' ($actualFinale.stage -eq 1 -and $finaleUpdate -eq [UpdateResult]::NeedWipe -and $batch.Count -eq 1 -and $batch[0].Track -ceq 'D_BUNNY' -and $batch[0].Loop)
    if($FinaleQualification){
        . "$root/src/MusicLoopReader.ps1";. "$root/src/MusicOneShotReader.ps1";. "$root/src/MusicPlayback.ps1"
        $finaleReport=[IO.Path]::GetFullPath($FinaleQualification);$finaleCatalog="$root/local/music-catalog-bunny-finale-$PID.json"
        @{D_BUNNY=$finaleReport}|ConvertTo-Json|Set-Content -LiteralPath $finaleCatalog
        $finaleReports=Read-DoomMusicCatalog $finaleCatalog $content
        Check 'Finale score catalog matches the installed Doom IWAD' ($finaleReports.Count -eq 1 -and $finaleReports.ContainsKey('D_BUNNY'))
        $musicPlayback=New-DoomMusicPlayback $finaleReports
        Update-DoomMusicPlayback $musicPlayback $batch
        $bunnyMix=Read-DoomMusicPlayback $musicPlayback 44100
        Check 'Finale loop callback starts verified Bunny playback and produces one second of music' ($musicPlayback.Selected -ceq 'D_BUNNY' -and $musicPlayback.ReaderModes.D_BUNNY -ceq 'Loop' -and $bunnyMix.Length -eq 88200 -and @($bunnyMix|Where-Object {$_ -ne 0}).Count -gt 0)
        $finalePlayback=@{Track=$musicPlayback.Selected;Loop=$batch[0].Loop;Frames=$bunnyMix.Length/2;QualificationSha256=(Get-FileHash -LiteralPath $finaleReport).Hash;CatalogSha256=(Get-FileHash -LiteralPath $finaleCatalog).Hash}
        Close-DoomMusicPlayback $musicPlayback;$musicPlayback=$null
    }
    $options.Episode=4;Sync-DoomMusicSession $events $fake;Check 'Other Ultimate Doom art finales retain victory score' ($events.Drain()[0].Track -ceq 'D_VICTOR')
    if($MapQualification){
        $mapReport=Get-Content -LiteralPath $MapQualification -Raw|ConvertFrom-Json
        $mapTrack=[string]$mapReport.Details.Track
        $mapOptions=[GameOptions]::new();$mapOptions.GameMode=$content.Wad.GameMode;$mapOptions.GameVersion=$content.Wad.GameVersion;$mapOptions.MissionPack=$content.Wad.MissionPack
        $mapEvents=[DoomMusicEvents]::new();$mapOptions.Music=$mapEvents;$mapGame=[DoomGame]::new($content,$mapOptions)
        $mapGame.InitNew([GameSkill]::Medium,$Episode,$Map);$mapBatch=$mapEvents.Drain()
        Check "Actual E${Episode}M${Map} initialization emits the qualified music track" ($mapBatch.Count -eq 1 -and $mapBatch[0].Kind -ceq 'Start' -and $mapBatch[0].Track -ceq $mapTrack -and $mapBatch[0].Loop)
        $mapCatalog="$root/local/music-catalog-map-$PID.json";@{$mapTrack=[IO.Path]::GetFullPath($MapQualification)}|ConvertTo-Json|Set-Content -LiteralPath $mapCatalog
        $mapReports=Read-DoomMusicCatalog $mapCatalog $content
        Check "Actual E${Episode}M${Map} score matches its one-track catalog" ($mapReports.Count -eq 1 -and $mapReports.ContainsKey($mapTrack))
        $mapSelection=@{Episode=$Episode;Map=$Map;Kind=$mapBatch[0].Kind;Track=$mapBatch[0].Track;Loop=$mapBatch[0].Loop;QualificationSha256=(Get-FileHash -LiteralPath $MapQualification).Hash;CatalogSha256=(Get-FileHash -LiteralPath $mapCatalog).Hash}
    }
    $catalog="$root/local/music-catalog-test-$PID.json";@{D_E1M1=[IO.Path]::GetFullPath($Qualification)}|ConvertTo-Json|Set-Content $catalog
    $reports=Read-DoomMusicCatalog $catalog $content;Check 'Catalog validates qualified score against actual IWAD bytes' ($reports.Count -eq 1 -and $reports.ContainsKey('D_E1M1'))
    $bad="$root/local/music-catalog-mismatch-$PID.json";@{D_E1M2=[IO.Path]::GetFullPath($Qualification)}|ConvertTo-Json|Set-Content $bad
    Reject 'Mismatched map/qualification catalog rejected' {$null=Read-DoomMusicCatalog $bad $content}
    if($CampaignCatalog){
        . "$root/src/MusicLoopReader.ps1";. "$root/src/MusicOneShotReader.ps1";. "$root/src/MusicPlayback.ps1"
        $campaignCatalogPath=[IO.Path]::GetFullPath($CampaignCatalog)
        $catalogWatch=[Diagnostics.Stopwatch]::StartNew()
        $campaignReports=Read-DoomMusicCatalog $campaignCatalogPath $content
        $catalogValidationSeconds=$catalogWatch.Elapsed.TotalSeconds
        $requiredSpecial=@('D_INTER','D_VICTOR','D_BUNNY')
        foreach($track in $requiredSpecial){Check "Campaign catalog contains $track" $campaignReports.ContainsKey($track)}
        $uniquePayloads=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase);[long]$uniquePayloadBytes=0;[long]$qualifiedPeriodBytes=0;[long]$playbackPayloadBytes=0;[long]$proofOnlyPayloadBytes=0
        foreach($track in $campaignReports.Keys){
            $qualificationData=Get-Content -LiteralPath $campaignReports[$track] -Raw|ConvertFrom-Json -AsHashtable
            $isLoop= -not ($qualificationData.Details.ContainsKey('Mode') -and $qualificationData.Details.Mode -ceq 'OneShot')
            Check "$track qualification is a looping score" ($isLoop -and $qualificationData.Details.Qualified -eq $true)
            $playbackPeriodCount=if($qualificationData.Details.Periods.Count -eq 3){2}else{$qualificationData.Details.Periods.Count}
            for($periodIndex=0;$periodIndex -lt $qualificationData.Details.Periods.Count;$periodIndex++){
                $period=$qualificationData.Details.Periods[$periodIndex]
                $qualifiedPeriodBytes+=[long]$period.Bytes
                if($periodIndex -lt $playbackPeriodCount){$playbackPayloadBytes+=[long]$period.Bytes}else{$proofOnlyPayloadBytes+=[long]$period.Bytes}
                $payloadPath=[IO.Path]::GetFullPath([string]$period.Path)
                if($uniquePayloads.Add($payloadPath)){$uniquePayloadBytes+=[long]([IO.FileInfo]::new($payloadPath)).Length}
            }
        }
        $openWatch=[Diagnostics.Stopwatch]::StartNew();$campaignPlayback=New-DoomMusicPlayback $campaignReports
        $playbackOpenSeconds=$openWatch.Elapsed.TotalSeconds
        Check 'All campaign loop readers open together with loop mode' ($campaignPlayback.Readers.Count -eq $campaignReports.Count -and @($campaignPlayback.ReaderModes.Values|Where-Object {$_ -cne 'Loop'}).Count -eq 0)
        Check 'Independent third periods remain proof-only while all playback readers use two verified payloads' (@($campaignPlayback.Readers.Values|Where-Object {$_.QualificationPeriods -eq 3 -and $_.PlaybackPeriods -eq 2 -and $_.Files.Count -eq 2}).Count -eq 15)

        $campaignOptions=[GameOptions]::new();$campaignOptions.GameMode=$content.Wad.GameMode;$campaignOptions.GameVersion=$content.Wad.GameVersion;$campaignOptions.MissionPack=$content.Wad.MissionPack
        $campaignEvents=[DoomMusicEvents]::new();$campaignOptions.Music=$campaignEvents;$campaignGame=[DoomGame]::new($content,$campaignOptions)
        $usedMapTracks=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$mapSelections=[Collections.Generic.List[object]]::new()
        for($campaignEpisode=1;$campaignEpisode -le 4;$campaignEpisode++){
            for($campaignMapNumber=1;$campaignMapNumber -le 9;$campaignMapNumber++){
                $campaignGame.InitNew([GameSkill]::Medium,$campaignEpisode,$campaignMapNumber);$commands=$campaignEvents.Drain();$label="E${campaignEpisode}M${campaignMapNumber}"
                $valid=$commands.Count -eq 1 -and $commands[0].Kind -ceq 'Start' -and $commands[0].Loop -and $campaignReports.ContainsKey([string]$commands[0].Track)
                Check "$label actual initialization selects a qualified campaign loop" $valid
                $track=[string]$commands[0].Track;$usedMapTracks.Add($track)|Out-Null
                Update-DoomMusicPlayback $campaignPlayback $commands;$null=Read-DoomMusicPlayback $campaignPlayback 1260
                Check "$label callback advances its selected reader" ($campaignPlayback.Selected -ceq $track -and $campaignPlayback.Readers[$track].Frame -eq 1260)
                $mapSelections.Add(@{Map=$label;Track=$track})
            }
        }
        Check 'All 36 map callbacks are covered by 27 distinct IWAD map scores' ($mapSelections.Count -eq 36 -and $usedMapTracks.Count -eq 27)

        $specialGame=@{State=[GameState]::Intermission;Options=$campaignOptions};Sync-DoomMusicSession $campaignEvents $specialGame;$commands=$campaignEvents.Drain()
        Check 'Intermission selects its qualified loop from the campaign catalog' ($commands.Count -eq 1 -and $commands[0].Track -ceq 'D_INTER' -and $campaignReports.ContainsKey('D_INTER'))
        Update-DoomMusicPlayback $campaignPlayback $commands;$null=Read-DoomMusicPlayback $campaignPlayback 1260
        $campaignOptions.Episode=1;$specialGame=@{State=[GameState]::Finale;Options=$campaignOptions;Finale=@{stage=0}}
        Sync-DoomMusicSession $campaignEvents $specialGame;$commands=$campaignEvents.Drain()
        Check 'Episode 1 finale selects qualified victory loop from campaign catalog' ($commands.Count -eq 1 -and $commands[0].Track -ceq 'D_VICTOR' -and $campaignReports.ContainsKey('D_VICTOR'))
        Update-DoomMusicPlayback $campaignPlayback $commands;$null=Read-DoomMusicPlayback $campaignPlayback 1260
        $campaignOptions.Episode=3;$actualCampaignFinale=[Finale]::new($campaignOptions);$commands=$campaignEvents.Drain()
        Check 'Actual Episode 3 finale constructor selects qualified victory loop' ($commands.Count -eq 1 -and $commands[0].Track -ceq 'D_VICTOR' -and $commands[0].Loop)
        Update-DoomMusicPlayback $campaignPlayback $commands;$null=Read-DoomMusicPlayback $campaignPlayback 1260
        $actualCampaignFinale.TextSpeed=1;$actualCampaignFinale.TextWait=0;$actualCampaignFinale.count=$actualCampaignFinale.text.Length
        $finaleResult=$actualCampaignFinale.Update();$commands=$campaignEvents.Drain()
        Check 'Actual Episode 3 text-to-art callback selects qualified Bunny loop' ($actualCampaignFinale.stage -eq 1 -and $finaleResult -eq [UpdateResult]::NeedWipe -and $commands.Count -eq 1 -and $commands[0].Track -ceq 'D_BUNNY' -and $commands[0].Loop)
        Update-DoomMusicPlayback $campaignPlayback $commands;$null=Read-DoomMusicPlayback $campaignPlayback 1260
        Check 'Map, intermission and finale events leave every catalog reader usable' ($campaignPlayback.Selected -ceq 'D_BUNNY' -and $campaignPlayback.Readers.D_BUNNY.Frame -eq 1260 -and $campaignPlayback.Frames -eq 40*1260)
        $campaignEntries=@(foreach($track in ($campaignReports.Keys|Sort-Object)){@{Track=$track;QualificationSha256=(Get-FileHash -LiteralPath $campaignReports[$track]).Hash}})
        $campaignIntegration=@{CatalogSha256=(Get-FileHash -LiteralPath $campaignCatalogPath).Hash;TrackCount=$campaignReports.Count;Entries=$campaignEntries;MapTrackCount=$usedMapTracks.Count;MapSelections=$mapSelections.ToArray();UniquePayloadCount=$uniquePayloads.Count;UniquePayloadBytes=$uniquePayloadBytes;QualifiedPeriodBytes=$qualifiedPeriodBytes;PlaybackPayloadBytes=$playbackPayloadBytes;ProofOnlyPayloadBytes=$proofOnlyPayloadBytes;CatalogValidationSeconds=$catalogValidationSeconds;PlaybackOpenSeconds=$playbackOpenSeconds;PlaybackFrames=$campaignPlayback.Frames;PlaybackTransitions=$campaignPlayback.Transitions.Count}
        Close-DoomMusicPlayback $campaignPlayback;$campaignPlayback=$null
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($musicPlayback){Close-DoomMusicPlayback $musicPlayback}
    if($campaignPlayback){Close-DoomMusicPlayback $campaignPlayback}
    if($content){$content.Dispose()}
    $sourcePaths=@('src/MusicEvents.ps1')
    if($FinaleQualification){$sourcePaths+=@('src/MusicLoopReader.ps1','src/MusicOneShotReader.ps1','src/MusicPlayback.ps1')}
    if($CampaignCatalog){$sourcePaths+=@('src/MusicLoopReader.ps1','src/MusicPlayback.ps1')}
    $sources=@($sourcePaths|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$root/$_").Hash}})
    @{Error=$failure;Checks=$checks.ToArray();MapSelection=$mapSelection;FinalePlayback=$finalePlayback;CampaignIntegration=$campaignIntegration;Sources=$sources;WadSha256=(Get-FileHash $Wad).Hash;EngineBundleSha256=$bundleSha256;EngineBundleBuilderSha256=$bundleBuilderSha256;FinaleSourceSha256=(Get-FileHash "$root/src/ManagedDoom/Doom/Intermission/Finale.sb.ps1").Hash;SourceSha256=(Get-FileHash "$root/src/MusicEvents.ps1").Hash;ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Actual engine initialization callback plus isolated Ultimate Doom save-state music selection and IWAD/catalog identity checks. Optional finale case sends the emitted looping Bunny event into the actual qualified music playback reader and records its real-mix output. Optional map cases record the exact emitted track and catalog/qualification hashes. Optional campaign catalog case opens all supplied qualified loop readers, advances every actual map callback and campaign intermission/finale callback through the persistent playback state, and records local payload verification cost; this does not prove campaign completion or acoustic continuity.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) music event checks."
