#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Replay="$PSScriptRoot/../results/e1m2-qualified-declared-destination.json",
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1";. "$PSScriptRoot/../src/InputReplay.ps1"
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new()
function Check([string]$Name,[bool]$Pass){$checks.Add(@{Name=$Name;Passed=$Pass});if(-not $Pass){throw $Name}}
try{
    $r=Get-Content $Replay -Raw|ConvertFrom-Json;$null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]([int]$r.Skill-1),$r.Episode,$r.Map);$null=$game.Update($commands)
    $original=Get-DoomReplayCheckpoint $game 0;$legacy=@($r.Checkpoints|Where-Object Tic -eq 0)[0]
    Check 'Historical initial checkpoint hash is preserved exactly' ($original.Sha256 -ceq $legacy.Sha256)
    $packet=Get-GameRenderSnapshotBytes $game
    Check 'Complete current packet hash is retained separately' ($original.CurrentRenderSnapshotSha256 -ceq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($packet)))
    $player=$game.World.ConsolePlayer;$sector=$player.Mobj.Subsector.Sector;$light=$sector.LightLevel
    $sector.LightLevel=$light+16;$changed=Get-DoomReplayCheckpoint $game 0
    Check 'Changing sector lighting still changes the historical-compatible hash' ($changed.Sha256 -cne $original.Sha256)
    Check 'Changing sector lighting changes the complete packet hash' ($changed.CurrentRenderSnapshotSha256 -cne $original.CurrentRenderSnapshotSha256)
    $sector.LightLevel=$light;$player.Health--;$changed=Get-DoomReplayCheckpoint $game 0
    Check 'Changing health still changes the checkpoint hash' ($changed.Sha256 -cne $original.Sha256)
    $player.Health++;$restored=Get-DoomReplayCheckpoint $game 0
    Check 'Restoring state restores both exact hashes' ($restored.Sha256 -ceq $original.Sha256 -and $restored.CurrentRenderSnapshotSha256 -ceq $original.CurrentRenderSnapshotSha256)
    $power=$player.Powers[[int][PowerType]::Invisibility];$player.Powers[[int][PowerType]::Invisibility]=129
    $changed=Get-DoomReplayCheckpoint $game 0
    Check 'Invisibility is covered by the new packet digest' ($changed.CurrentRenderSnapshotSha256 -cne $original.CurrentRenderSnapshotSha256)
    Check 'Schema1 retains its historical absence of invisibility' ($changed.Sha256 -ceq $original.Sha256)
    Check 'New replay comparison rejects changed invisibility' (-not (Compare-DoomReplayCheckpoints @($original) @($changed) 0).Matched)
    $player.Powers[[int][PowerType]::Invisibility]=$power
    $actor=$game.World.Thinkers.Cap.Next
    while($actor -isnot [Mobj] -or [object]::ReferenceEquals($actor,$player.Mobj)){$actor=$actor.Next}
    $flags=$actor.Flags;$actor.Flags=$flags -bxor [MobjFlags]::Shadow;$changed=Get-DoomReplayCheckpoint $game 0
    Check 'Actor flags are covered by the new packet digest' ($changed.CurrentRenderSnapshotSha256 -cne $original.CurrentRenderSnapshotSha256)
    Check 'Schema1 retains its historical absence of actor flags' ($changed.Sha256 -ceq $original.Sha256)
    Check 'New replay comparison rejects changed actor flags' (-not (Compare-DoomReplayCheckpoints @($original) @($changed) 0).Matched)
    Check 'New replay comparison accepts matching serialized checkpoints' ((Compare-DoomReplayCheckpoints @((($original|ConvertTo-Json -Depth 7)|ConvertFrom-Json)) @($original) 0).Matched)
    $actor.Flags=$flags
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();ReplaySha256=(Get-FileHash $Replay).Hash;BundleSha256=(Get-FileHash $bundle).Hash;WadSha256=(Get-FileHash $Wad).Hash;
        Sources=@('scripts/Test-CheckpointSnapshotSchema.ps1','src/InputReplay.ps1','src/GameHost.ps1','src/SnapshotTransport.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});
        Meaning='Original Schema1 checkpoint digest preserved against an existing independent route; complete new packet digest retained. Negative controls demonstrate lighting and health changes remain detectable, with exact restoration. No campaign-completion claim.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}
"PASS: $($checks.Count) checkpoint schema checks."
