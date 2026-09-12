#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/SaveState.ps1"
$checks=[Collections.Generic.List[object]]::new();$seen=[Collections.Generic.List[object]]::new();$content=$null;$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($n=0;$n -lt 4;$n++){$commands[$n]=[TicCmd]::new()}
    $hook={param($LoadingGame) $seen.Add($LoadingGame.World)}.GetNewClosure();$game.BeforeLevelLoad=$hook
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    Check 'Initial loading notification precedes world construction' ($seen.Count -eq 1 -and $null -eq $seen[0] -and $null -ne $game.World)
    foreach($n in 1..5){$null=$game.Update($commands)}
    Check 'Ordinary tics do not enter a loading boundary' ($seen.Count -eq 1)
    $old=$game.World;$game.DoLoadLevel()
    Check 'Reload notifies exactly once while the old world is still present' ($seen.Count -eq 2 -and [object]::ReferenceEquals($seen[1],$old) -and -not [object]::ReferenceEquals($game.World,$old))
    $catalog=New-DoomSaveCatalog
    Check 'Host callback is excluded from the data-only save schema' ('BeforeLevelLoad' -notin $catalog.DoomGame.Properties.Name)
    $first=ConvertTo-DoomSaveGraph $game|ConvertTo-Json -Depth 12 -Compress
    $game.BeforeLevelLoad={throw 'sentinel load boundary failure'}
    $second=ConvertTo-DoomSaveGraph $game|ConvertTo-Json -Depth 12 -Compress
    Check 'Changing the host callback does not change saved game data' ($first -ceq $second)
    $old=$game.World;$failed=$false;try{$game.DoLoadLevel()}catch{$failed=$_.ToString() -match 'sentinel load boundary failure'}
    Check 'A failing boundary aborts before replacing the world' ($failed -and [object]::ReferenceEquals($game.World,$old))
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();WadSha256=(Get-FileHash $Wad).Hash;Sources=@('src/ManagedDoom/Doom/Game/DoomGame.sb.ps1','src/SaveState.ps1','scripts/Test-LevelLoadBoundary.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});Meaning='Actual engine construction/reload boundaries and callback-free save data. Controller fixtures do not establish campaign completion.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) engine loading checks."
