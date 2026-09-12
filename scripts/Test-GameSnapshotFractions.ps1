#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/GameHost.ps1"
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new();$samples=[Collections.Generic.List[object]]::new()
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    for($i=0;$i -lt 35;$i++){$commands[0].ForwardMove=25;$commands[0].AngleTurn=512;$null=$game.Update($commands)}
    $old=New-GameRenderSnapshot $game 0;$new=New-GameRenderSnapshot $game 1
    if([Math]::Abs($old.ConsolePlayer.Mobj.X-$new.ConsolePlayer.Mobj.X)+[Math]::Abs($old.ConsolePlayer.Mobj.Y-$new.ConsolePlayer.Mobj.Y) -lt .001){throw 'Fixture did not produce camera movement.'}
    foreach($fraction in @(-.5,0,.25,.5,.75,1,1.5)){
        $bounded=if($fraction -lt 0){0.0}elseif($fraction -gt 1){1.0}else{$fraction}
        $actual=New-GameRenderSnapshot $game $fraction
        foreach($field in 'X','Y','Angle'){
            $expected=$old.ConsolePlayer.Mobj[$field]+($new.ConsolePlayer.Mobj[$field]-$old.ConsolePlayer.Mobj[$field])*$bounded
            $value=$actual.ConsolePlayer.Mobj[$field]
            $checks.Add(@{Name="Camera $field at fraction $fraction";Passed=([Math]::Abs($value-$expected) -lt 1e-10);Expected=$expected;Actual=$value})
        }
        $expected=$old.ConsolePlayer.ViewZ+($new.ConsolePlayer.ViewZ-$old.ConsolePlayer.ViewZ)*$bounded
        $checks.Add(@{Name="View height at fraction $fraction";Passed=([Math]::Abs($actual.ConsolePlayer.ViewZ-$expected) -lt 1e-10);Expected=$expected;Actual=$actual.ConsolePlayer.ViewZ})
        $samples.Add(@{Requested=$fraction;ActualFraction=$actual.Fraction;Camera=$actual.ConsolePlayer.Mobj;ViewZ=$actual.ConsolePlayer.ViewZ})
    }
    if(@($checks|Where-Object {-not $_.Passed}).Count){throw 'Fractional snapshot camera differs from linear endpoint interpolation.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();Samples=$samples.ToArray();WadSha256=(Get-FileHash $Wad).Hash;SnapshotSourceSha256=(Get-FileHash "$PSScriptRoot/../src/GameHost.ps1").Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Real E1M1 world after 35 ordinary moving/turning commands. Camera position, angle and view height checked at quarter/midpoint/endpoints and out-of-range clamps. No live terminal window or displayed-rate claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $($checks.Count) real-world snapshot fraction checks."
