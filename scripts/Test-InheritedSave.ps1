#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',[string]$Output="$PSScriptRoot/../results/save-inherited.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$content=$null;$observations=[Collections.Generic.List[object]]::new();$failure=$null
$directory=Join-Path "$PSScriptRoot/../local" ('save-probe-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $route=Read-DoomInputReplay "$PSScriptRoot/../results/e1m1-route.json"
    for($i=0;$i -lt 350;$i++){$v=$route.InputCommands[$i];$c=$commands[0];$c.ForwardMove=$v[0];$c.SideMove=$v[1];$c.AngleTurn=$v[2];$c.Buttons=$v[3];$null=$game.Update($commands)}
    $before=Get-DoomReplayCheckpoint $game 350;$beforeRng=$game.Options.Random.Index;$beforeWorld=$game.World
    try{
        $path=Join-Path $directory 'inherited.dsg';[SaveAndLoad]::Save($game,'study only',$path)
        [SaveAndLoad]::Load($game,$path)
        $after=Get-DoomReplayCheckpoint $game 350
        $observations.Add(@{Name='Inherited save/load';SaveBytes=(Get-Item $path).Length;BeforeRng=$beforeRng;AfterRng=$game.Options.Random.Index;CheckpointMatched=$before.Sha256 -eq $after.Sha256;Before=$before;After=$after;Error=$null})
    }catch{$observations.Add(@{Name='Inherited save/load';Error=$_.ToString();Stack=$_.ScriptStackTrace;BeforeRng=$beforeRng;AfterRng=$game.Options.Random.Index;LiveWorldReplaced=-not [object]::ReferenceEquals($beforeWorld,$game.World)})}
    $beforeWorld=$game.World;$beforeLevelTime=$game.World.LevelTime
    $bad=Join-Path $directory 'truncated.dsg';[IO.File]::WriteAllBytes($bad,[byte[]]::new(1));$rejected=$false
    try{[SaveAndLoad]::Load($game,$bad)}catch{$rejected=$true}
    $observations.Add(@{Name='Truncated save';Rejected=$rejected;LiveWorldReplaced=-not [object]::ReferenceEquals($beforeWorld,$game.World);BeforeLevelTime=$beforeLevelTime;AfterLevelTime=$game.World.LevelTime})
    $raw=[Runtime.CompilerServices.RuntimeHelpers]::GetUninitializedObject([DoomRandom]);$raw.Index=7
    try{$n=$raw.Next();$observations.Add(@{Name='Standard .NET object allocation probe';Type='DoomRandom';Returned=$n;Index=$raw.Index;MethodsWork=$raw.Index -eq 8})}catch{$observations.Add(@{Name='Standard .NET object allocation probe';Error=$_.ToString()})}
}catch{$failure=$_.ToString();throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;WadSha256=(Get-FileHash $Wad).Hash;Observations=$observations.ToArray();Sources=@('src/ManagedDoom/Doom/Game/SaveAndLoad.sb.ps1','src/ManagedDoom/Doom/Game/DoomGame.sb.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Bounded investigation of inherited serialization on 350 ordinary route commands, plus malformed input and standard .NET object allocation. Test saves stay in unique ignored local directories.'}|ConvertTo-Json -Depth 10|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
$observations|Select-Object Name,Error,CheckpointMatched,BeforeRng,AfterRng,Rejected,LiveWorldReplaced,MethodsWork|Format-Table
