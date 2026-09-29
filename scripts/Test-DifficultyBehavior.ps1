#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [string]$Wad = 'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Output = "$PSScriptRoot/../local/difficulty-behavior-r1.json"
)
$ErrorActionPreference = 'Stop'
$bundle = & "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
Set-StrictMode -Version Latest

$script:checks = [Collections.Generic.List[object]]::new()
$script:content = $null
$projectRoot = Split-Path $PSScriptRoot -Parent
$outputPath = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $outputPath) { throw "Use a fresh output path: $outputPath" }
$outputDirectory = Split-Path $outputPath -Parent
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory
}

function Add-BehaviorCheck([string]$Name, $Actual, $Expected, $Evidence = $null) {
    $actualJson = ConvertTo-Json -InputObject $Actual -Depth 10 -Compress
    $expectedJson = ConvertTo-Json -InputObject $Expected -Depth 10 -Compress
    $script:checks.Add([pscustomobject]@{
        Name = $Name
        Actual = $Actual
        Expected = $Expected
        Passed = $actualJson -ceq $expectedJson
        Evidence = $Evidence
    })
}

function Get-ExpectedKillCount([GameSkill]$Skill, [MapThing[]]$Things) {
    $mask = switch ($Skill) {
        ([GameSkill]::Baby) { [ThingFlags]::Easy }
        ([GameSkill]::Easy) { [ThingFlags]::Easy }
        ([GameSkill]::Medium) { [ThingFlags]::Normal }
        ([GameSkill]::Hard) { [ThingFlags]::Hard }
        ([GameSkill]::Nightmare) { [ThingFlags]::Hard }
    }
    $count = 0
    foreach ($thing in $Things) {
        if (($thing.Flags -band [ThingFlags]::MultiplayerOnly) -ne 0) { continue }
        $info = $null
        for ($i = 0; $i -lt [DoomInfo]::MobjInfos.Length; $i++) {
            if ([DoomInfo]::MobjInfos[$i].DoomEdNum -eq $thing.Type) {
                $info = [DoomInfo]::MobjInfos[$i]
                break
            }
        }
        if ($null -eq $info) { continue }
        if (($info.Flags -band [MobjFlags]::CountKill) -eq 0) { continue }
        if (($thing.Flags -band $mask) -ne 0) { $count++ }
    }
    return $count
}

function Find-Mobj([World]$World, [MobjType]$Type) {
    $cap = $World.Thinkers.Cap
    $thinker = $cap.Next
    while (-not [object]::ReferenceEquals($thinker, $cap)) {
        if ($thinker -is [Mobj] -and $thinker.Type -eq $Type -and $null -ne $thinker.SpawnPoint) {
            return $thinker
        }
        $thinker = $thinker.Next
    }
    return $null
}

function Find-RespawnCandidate([World]$World) {
    $cap = $World.Thinkers.Cap
    $thinker = $cap.Next
    while (-not [object]::ReferenceEquals($thinker, $cap)) {
        if ($thinker -is [Mobj] -and
            ($thinker.Flags -band [MobjFlags]::CountKill) -ne 0 -and
            $null -ne $thinker.SpawnPoint -and
            $World.ThingMovement.CheckPosition($thinker, $thinker.SpawnPoint.X, $thinker.SpawnPoint.Y)) {
            return $thinker
        }
        $thinker = $thinker.Next
    }
    return $null
}

function Test-RespawnedAtSpawn([World]$World, [Mobj]$OldMobj) {
    $cap = $World.Thinkers.Cap
    $thinker = $cap.Next
    while (-not [object]::ReferenceEquals($thinker, $cap)) {
        if ($thinker -is [Mobj] -and
            $thinker.Type -eq $OldMobj.Type -and
            [object]::ReferenceEquals($thinker.SpawnPoint, $OldMobj.SpawnPoint) -and
            -not [object]::ReferenceEquals($thinker, $OldMobj)) {
            return $true
        }
        $thinker = $thinker.Next
    }
    return $false
}

function Test-MobjActive([Mobj]$Target) {
    return ($Target.ThinkerState -eq [ThinkerState]::Active)
}
function Invoke-RespawnBoundary([GameSkill]$Skill, [bool]$RespawnMonsters, [bool]$FastMonsters, [int]$InitialMoveCount, [string]$Label) {
    $game.Options.RespawnMonsters = $RespawnMonsters
    $game.Options.FastMonsters = $FastMonsters
    $game.DeferedInitNew($Skill, 1, 1)
    foreach ($command in $commands) { $command.Clear() }
    $null = $game.Update($commands)

    $world = $game.World
    $mobj = Find-RespawnCandidate $world
    if ($null -eq $mobj) { throw "E1M1 has no clear count-kill spawn spot for respawn case $Label." }
    $world.ThingInteraction.DamageMobj($mobj, $null, $null, 10000)
    $mobj.Tics = -1
    $mobj.MoveCount = $InitialMoveCount
    $world.LevelTime = 32
    $world.Random.Index = 255
    $spawnSpotClearAfterDeath = [bool]$world.ThingMovement.CheckPosition($mobj, $mobj.SpawnPoint.X, $mobj.SpawnPoint.Y)

    $mobj.Run()
    $eligible = ($Skill -eq [GameSkill]::Nightmare -or $RespawnMonsters)
    $firstRunShouldRespawn = $eligible -and $InitialMoveCount -ge (12 * 35 - 1)
    $observedAfterFirst = [ordered]@{
        ReplacementAtSpawn = [bool](Test-RespawnedAtSpawn $world $mobj)
        OldActorActive = [bool](Test-MobjActive $mobj)
        MoveCount = $mobj.MoveCount
    }
    $expectedAfterFirst = [ordered]@{
        ReplacementAtSpawn = [bool]$firstRunShouldRespawn
        OldActorActive = [bool](-not $firstRunShouldRespawn)
        MoveCount = if ($eligible) { [Math]::Min($InitialMoveCount + 1, 12 * 35) } else { $InitialMoveCount }
    }
    Add-BehaviorCheck "$Label first respawn tick" $observedAfterFirst $expectedAfterFirst @{
        Skill = $Skill.ToString()
        FastMonsters = $FastMonsters
        RespawnMonsters = $RespawnMonsters
        LevelTime = $world.LevelTime
        InitialMoveCount = $InitialMoveCount
        RandomIndexSeededForImmediateSuccess = $true
        SpawnSpotClearAfterDeath = $spawnSpotClearAfterDeath
    }

    if ($eligible -and $InitialMoveCount -eq (12 * 35 - 2)) {
        $mobj.Run()
        $observedAtBoundary = [ordered]@{
            ReplacementAtSpawn = [bool](Test-RespawnedAtSpawn $world $mobj)
            OldActorActive = [bool](Test-MobjActive $mobj)
            MoveCount = $mobj.MoveCount
        }
        $expectedAtBoundary = [ordered]@{
            ReplacementAtSpawn = $true
            OldActorActive = $false
            MoveCount = 12 * 35
        }
        Add-BehaviorCheck "$Label respawn threshold tick" $observedAtBoundary $expectedAtBoundary @{
            Skill = $Skill.ToString()
            RespawnMonsters = $RespawnMonsters
            FastMonsters = $FastMonsters
            ThresholdTics = 12 * 35
            RandomIndexSeededForImmediateSuccess = $true
            SpawnSpotClearAfterDeath = $spawnSpotClearAfterDeath
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $Wad -PathType Leaf)) { throw "IWAD not found: $Wad" }
    $null = [DoomInfo]::SwitchNames
    $script:content = [GameContent]::new(@('-iwad', $Wad))
    $gameOptions = [GameOptions]::new()
    $gameOptions.GameMode = $script:content.Wad.GameMode
    $gameOptions.GameVersion = $script:content.Wad.GameVersion
    $gameOptions.MissionPack = $script:content.Wad.MissionPack
    $game = [DoomGame]::new($script:content, $gameOptions)
    $commands = [TicCmd[]]::new([Player]::MaxPlayerCount)
    for ($i = 0; $i -lt $commands.Length; $i++) { $commands[$i] = [TicCmd]::new() }

    $mapLump = $script:content.Wad.GetLumpNumber('E1M1')
    if ($mapLump -lt 0) { throw 'The selected IWAD has no E1M1 map.' }
    $mapThings = [MapThing]::FromWad($script:content.Wad, $mapLump + 1)
    $skills = [GameSkill[]]@(
        [GameSkill]::Baby,
        [GameSkill]::Easy,
        [GameSkill]::Medium,
        [GameSkill]::Hard,
        [GameSkill]::Nightmare
    )

    foreach ($skill in $skills) {
        $game.Options.FastMonsters = $false
        $game.Options.RespawnMonsters = $false
        $game.DeferedInitNew($skill, 1, 1)
        foreach ($command in $commands) { $command.Clear() }
        $null = $game.Update($commands)

        $world = $game.World
        $player = $world.ConsolePlayer
        $skillName = $skill.ToString()
        $expectedKills = Get-ExpectedKillCount $skill $mapThings
        Add-BehaviorCheck "$skillName E1M1 skill-filtered kill count" $world.TotalKills $expectedKills @{
            SkillThingFlagsParsedIndependently = $true
            RawMapThingCount = $mapThings.Length
        }

        $player.Health = 100
        $player.Mobj.Health = 100
        $player.ArmorPoints = 0
        $player.ArmorType = 0
        $player.Cheats = [CheatFlags]0
        $player.Powers[[int][PowerType]::Invulnerability] = 0
        $world.ThingInteraction.DamageMobj($player.Mobj, $null, $null, 10)
        $expectedHealth = if ($skill -eq [GameSkill]::Baby) { 95 } else { 90 }
        Add-BehaviorCheck "$skillName incoming player damage" $player.Health $expectedHealth @{
            AppliedDamage = 10
            Armor = 0
            GodMode = $false
        }

        $shell = [int][AmmoType]::Shell
        $player.Ammo[$shell] = 0
        $null = $world.ItemPickup.GiveAmmo($player, [AmmoType]::Shell, 1)
        $expectedAmmo = if ($skill -eq [GameSkill]::Baby -or $skill -eq [GameSkill]::Nightmare) { 8 } else { 4 }
        Add-BehaviorCheck "$skillName shell ammo amount" $player.Ammo[$shell] $expectedAmmo @{
            PickupAmount = 1
            ShellClipSize = [DoomInfo]::AmmoInfos.Clip[$shell]
        }

        $sargRun = [DoomInfo]::States.all[[int][MobjState]::SargRun1]
        $sargTics = $player.Mobj.GetTics($sargRun)
        $expectedSargTics = if ($skill -eq [GameSkill]::Nightmare) { 1 } else { $sargRun.Tics }
        Add-BehaviorCheck "$skillName fast-monster state cadence" $sargTics $expectedSargTics @{
            State = 'SargRun1'
            FastMonstersOption = $false
        }

        $troopshot = [MobjType]::Troopshot
        $baseSpeed = [DoomInfo]::MobjInfos[[int]$troopshot].Speed
        $expectedSpeed = if ($skill -eq [GameSkill]::Nightmare) { 20 * [Fixed]::FracUnit } else { $baseSpeed }
        $actualSpeed = $world.ThingAllocation.GetMissileSpeed($troopshot)
        Add-BehaviorCheck "$skillName Imp projectile speed" $actualSpeed $expectedSpeed @{
            Projectile = 'Imp fireball'
            FastMonstersOption = $false
            BaseSpeed = $baseSpeed
        }

        $imp = Find-Mobj $world ([MobjType]::Troop)
        if ($null -eq $imp) { throw "E1M1 did not spawn an Imp on $skillName." }
        $expectedReaction = if ($skill -eq [GameSkill]::Nightmare) { 0 } else { $imp.Info.ReactionTime }
        Add-BehaviorCheck "$skillName Imp initial reaction time" $imp.ReactionTime $expectedReaction @{
            Monster = 'Imp'
            ReferenceReactionTime = $imp.Info.ReactionTime
        }
    }

    $game.Options.FastMonsters = $false
    $game.Options.RespawnMonsters = $false
    $game.DeferedInitNew([GameSkill]::Medium, 1, 1)
    foreach ($command in $commands) { $command.Clear() }
    $null = $game.Update($commands)
    $game.Options.FastMonsters = $true
    $sargRun = [DoomInfo]::States.all[[int][MobjState]::SargRun1]
    Add-BehaviorCheck 'Fast Monsters option halves demon run tics' $game.World.ConsolePlayer.Mobj.GetTics($sargRun) 1 @{
        Skill = 'Medium'
        State = 'SargRun1'
    }
    $baseSpeed = [DoomInfo]::MobjInfos[[int][MobjType]::Troopshot].Speed
    Add-BehaviorCheck 'Fast Monsters option doubles Imp projectile speed' $game.World.ThingAllocation.GetMissileSpeed([MobjType]::Troopshot) (20 * [Fixed]::FracUnit) @{
        Skill = 'Medium'
        BaseSpeed = $baseSpeed
    }

    Invoke-RespawnBoundary ([GameSkill]::Nightmare) $false $false (12 * 35 - 2) 'Nightmare'
    Invoke-RespawnBoundary ([GameSkill]::Medium) $false $false (12 * 35 - 1) 'Medium'
    Invoke-RespawnBoundary ([GameSkill]::Medium) $false $true (12 * 35 - 1) 'Fast Monsters option'
    Invoke-RespawnBoundary ([GameSkill]::Medium) $true $false (12 * 35 - 1) 'Respawn Monsters option'

    $failed = @($script:checks | Where-Object { -not $_.Passed })
    $gitHead = (& git -C $projectRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not record the source commit.' }
    & git -C $projectRoot diff --quiet --exit-code -- src
    $engineSourceTreeClean = $LASTEXITCODE -eq 0
    $report = [ordered]@{
        Format = 'pwshDoom.DifficultyBehaviorQualification'
        Version = 1
        RecordedUtc = [DateTime]::UtcNow.ToString('o')
        SourceCommit = $gitHead
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        EngineSourceTreeClean = $engineSourceTreeClean
        ScriptSha256 = (Get-FileHash -LiteralPath $PSCommandPath).Hash
        WadPath = [IO.Path]::GetFileName($Wad)
        WadSha256 = (Get-FileHash -LiteralPath $Wad).Hash
        Map = 'E1M1'
        Scope = 'Five-skill real-IWAD checks for map thing filtering, player damage, shell ammo, fast-monster timing, Imp reaction/projectile behavior, and deterministic respawn thresholds. Medium-skill option overrides are checked independently.'
        Passed = ($failed.Count -eq 0 -and $engineSourceTreeClean)
        CheckCount = $script:checks.Count
        Checks = $script:checks.ToArray()
        Meaning = 'Focused component behavior qualification only. It does not claim complete campaign routes, every skill/map combination, or a human playthrough.'
    }
    $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $outputPath -Encoding utf8
    "Report: $outputPath"
    "Checks: $($script:checks.Count)"
    if ($failed.Count -gt 0) { throw "Difficulty behavior checks failed: $($failed.Name -join ', ')" }
    if (-not $engineSourceTreeClean) { throw 'Source files were modified during the difficulty behavior run.' }
    "PASS: all $($script:checks.Count) difficulty behavior checks."
} finally {
    if ($null -ne $script:content) { $script:content.Dispose() }
}
