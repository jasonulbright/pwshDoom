#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new()
function Check($Name,$Expected,$Actual){$checks.Add(@{Name=$Name;Expected=$Expected;Actual=$Actual;Passed=($Expected -ceq $Actual)})}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $world=$game.World;$p=$world.ConsolePlayer;$sector=$p.Mobj.Subsector.Sector
    # Isolated real-world fixture: edit test state, invoke actual sector/damage methods.
    # This is behavior testing, never ordinary-input campaign completion evidence.
    foreach($special in 5,7,4,16){
        foreach($tic in 31,32,33,64){
            foreach($boots in 0,100){
                foreach($airborne in $false,$true){
                    # Index 0 next yields 8 (boots protect); index 65 yields 4 (leak).
                    foreach($seed in 0,65){
                        $p.Health=100;$p.Mobj.Health=100;$p.ArmorPoints=0;$p.ArmorType=0;$p.Cheats=0
                        [Array]::Clear($p.Powers,0,$p.Powers.Length);$p.Powers[[PowerType]::IronFeet]=$boots
                        $p.Attacker=$p.Mobj;$sector.Special=[SectorSpecial]$special;$world.LevelTime=$tic;$world.Random.Index=$seed
                        $p.Mobj.Z=[Fixed]::new($sector.FloorHeight.Data+$(if($airborne){65536}else{0}))
                        $damage=0;$rng=$seed
                        if(-not $airborne){
                            if($boots -gt 0 -and $special -in 4,16){$rng=($seed+1)-band 255}
                            if($tic -in 32,64 -and ($boots -eq 0 -or ($special -in 4,16 -and $seed -eq 65))){
                                $damage=switch($special){5{10};7{5};default{20}}
                            }
                        }
                        # DamageMobj itself consumes one random byte for the living actor's pain test.
                        if($damage -gt 0){$rng=($rng+1)-band 255}
                        $world.PlayerBehavior.PlayerInSpecialSector($p)
                        $name="special=$special tic=$tic boots=$boots airborne=$airborne seed=$seed"
                        Check "$name health" (100-$damage) $p.Health
                        Check "$name actor health" (100-$damage) $p.Mobj.Health
                        Check "$name random index" $rng $world.Random.Index
                        Check "$name damage source" ($damage -gt 0) ($null -eq $p.Attacker)
                    }
                }
            }
        }
    }
    if(@($checks|Where-Object {-not $_.Passed}).Count){throw 'Sector damage behavior differs from the original damage/cadence/boots/grounding rules.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Passed=($null -eq $failure);Checks=$checks.ToArray();WadSha256=(Get-FileHash $Wad).Hash;BehaviorSourceSha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Doom/World/PlayerBehavior.sb.ps1").Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Reference='https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/p_spec.c#L944-L1004';Meaning='Actual E1M1 player, world, sector and damage methods with isolated fixture state; no campaign or live rendering claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $($checks.Count) sector damage checks."
