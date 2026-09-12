#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$RouteResult,[Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh diagnostic report.'}
$reference=Get-Content $RouteResult -Raw|ConvertFrom-Json
if($reference.WadSha256 -cne (Get-FileHash $Wad).Hash){throw 'IWAD differs from recorded input.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$content=$null;$failure=$null;$events=[Collections.Generic.List[object]]::new();$n=0;$traceChecks=0
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]([int]$reference.Skill-1),$reference.Episode,$reference.Map);$null=$game.Update($commands)
    $expected=@{};foreach($sample in $reference.Trace){$expected[[int]$sample.Command]=$sample}
    foreach($entry in $reference.InputCommands){
        $p=$game.World.ConsolePlayer;$health=$p.Health;$preX=$p.Mobj.X.Data/65536.0;$preY=$p.Mobj.Y.Data/65536.0;$preZ=$p.Mobj.Z.Data
        $cmd=$commands[0];$cmd.Clear();$cmd.ForwardMove=$entry[0];$cmd.SideMove=$entry[1];$cmd.AngleTurn=$entry[2];$cmd.Buttons=$entry[3]
        $null=$game.Update($commands);$n++;$p=$game.World.ConsolePlayer;$s=$p.Mobj.Subsector.Sector
        if($p.Health -ne $health -or $p.Mobj.Z.Data -ne $preZ -or $n%35 -eq 0){
            $events.Add(@{Command=$n;LevelTime=$game.World.LevelTime;Input=$entry;HealthBefore=$health;Health=$p.Health;Armor=$p.ArmorPoints;X=$p.Mobj.X.Data/65536.0;Y=$p.Mobj.Y.Data/65536.0;Z=$p.Mobj.Z.Data/65536.0;Floor=$s.FloorHeight.Data/65536.0;Sector=[Array]::IndexOf($game.World.Map.Sectors,$s);Special=[int]$s.Special;Attacker=$(if($null -ne $p.Attacker){$p.Attacker.Type.ToString()}else{$null})})
        }
        if($expected.ContainsKey($n)){
            $e=$expected[$n]
            if($preX -ne $e.X -or $preY -ne $e.Y -or $p.Health -ne $e.Health -or $p.Mobj.Z.Data/65536.0 -ne $e.Z){throw "Recorded failure differs at command $n."}
            $traceChecks++
        }
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Commands=$n;TraceChecks=$traceChecks;Events=$events.ToArray();RouteResultSha256=(Get-FileHash $RouteResult).Hash;WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Fixed ordinary-command replay of a retained failure. End-of-tic attacker identifies the last damage source only; multiple same-tic sources are not separately instrumented. Selected original trace positions/health/height must match.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
if($failure){throw $failure}
"Reproduced $n commands and $traceChecks failure trace samples."
