#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[ValidateSet('DEMO1','DEMO2','DEMO3')][string]$Name='DEMO1',
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh output.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$content=$null;$failure=$null;$n=0;$trace=[Collections.Generic.List[object]]::new();$transitions=[Collections.Generic.List[object]]::new();$prior='';$firstDeath=$null;$demoHash=$null
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    $bytes=[byte[]]$content.Wad.ReadLump($Name);$demoHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));$demo=[Demo]::new($bytes)
    $demo.Options.GameMode=$content.Wad.GameMode;$demo.Options.GameVersion=$content.Wad.GameVersion;$demo.Options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$demo.Options);$game.DeferedInitNew()
    $cmds=[TicCmd[]]@([TicCmd]::new(),[TicCmd]::new(),[TicCmd]::new(),[TicCmd]::new())
    while($demo.ReadCmd($cmds)){
        if($n -ge 20000){throw 'Bounded demo command limit exceeded.'}
        $null=$game.Update($cmds);$n++;$p=$game.World.ConsolePlayer
        if($null -eq $firstDeath -and $p.Health -le 0){$firstDeath=$n}
        $key="$($game.State):$($game.Options.Episode):$($game.Options.Map)"
        if($prior -ne $key){$transitions.Add(@{Command=$n;State=$key});$prior=$key}
        if($n%35 -eq 0){$trace.Add(@{Command=$n;X=$p.Mobj.X.Data;Y=$p.Mobj.Y.Data;Z=$p.Mobj.Z.Data;Angle=$p.Mobj.Angle.Data;Health=$p.Health;Armor=$p.ArmorPoints;Kills=$p.KillCount;Rng=$game.World.Random.Index})}
    }
    $final=@{State=$game.State.ToString();Episode=$game.Options.Episode;Map=$game.Options.Map;Health=$p.Health;Armor=$p.ArmorPoints;Kills=$p.KillCount;Completed=$game.World.Completed}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Name=$Name;Commands=$n;FirstDeathCommand=$firstDeath;Final=$(if(Get-Variable final -ErrorAction SilentlyContinue){$final}else{$null});Transitions=$transitions.ToArray();Trace=$trace.ToArray();DemoSha256=$demoHash;WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Unpaced execution of user-owned IWAD vanilla input demo through the adopted decoder and DoomGame, including DemoPlayback semantics. No state edits. Selected trace only; no original-executable synchronization, campaign completion, rendered output, audio or performance guarantee.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"Executed $Name : $n commands; first death $firstDeath."
