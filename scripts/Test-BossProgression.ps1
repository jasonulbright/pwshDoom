#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$checks=[Collections.Generic.List[object]]::new();$errors=[Collections.Generic.List[string]]::new();$content=$null
function Check($Name,$Expected,$Actual){
    $checks.Add(@{Name=$Name;Expected=$Expected;Actual=$Actual;Passed=($Expected -ceq $Actual)})
    if($Expected -cne $Actual){throw "$Name : expected $Expected, actual $Actual"}
}
function Check-Untriggered($Name,$World,$Sectors){
    Check "$Name no level exit" $false $World.Completed
    Check "$Name no tagged mover" 0 @($Sectors|Where-Object {$null -ne $_.SpecialData}).Count
}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    foreach($case in @(@(1,8,'Bruiser','BossDie7','Floor'),@(2,8,'Cyborg','CyberDie10','Exit'),@(3,8,'Spider','SpidDie11','Exit'),@(4,6,'Cyborg','CyberDie10','Door'),@(4,8,'Spider','SpidDie11','Floor'))){
        $label="E$($case[0])M$($case[1])"
        try{
            $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
            $game=[DoomGame]::new($content,$options);$game.InitNew([GameSkill]::Medium,$case[0],$case[1]);$w=$game.World
            $bosses=[Collections.Generic.List[object]]::new();$cap=$w.Thinkers.Cap;$mo=$cap.Next
            while(-not [object]::ReferenceEquals($mo,$cap)){
                if($mo -is [Mobj] -and $mo.Type -eq [MobjType]::$($case[2])){$bosses.Add($mo)}
                $mo=$mo.Next
            }
            Check "$label has expected boss" $true ($bosses.Count -gt 0)
            $actor=$bosses[0];$tagged=@($w.Map.Sectors|Where-Object Tag -eq 666)
            if($case[4] -ne 'Exit'){Check "$label has tag 666 geometry" $true ($tagged.Count -gt 0)}
            foreach($boss in $bosses){$boss.Health=0}
            # Explicit dead-boss fixtures exercise trigger guards, not player combat.
            $actor.Type=[MobjType]::Troop;$w.MonsterBehavior.BossDeath($actor)
            Check-Untriggered "$label wrong actor" $w $tagged
            $actor.Type=[MobjType]::$($case[2]);$options.Map=1;$w.MonsterBehavior.BossDeath($actor)
            Check-Untriggered "$label wrong map" $w $tagged
            $options.Map=$case[1]
            $w.ConsolePlayer.Health=0;$w.MonsterBehavior.BossDeath($actor)
            Check-Untriggered "$label no living player" $w $tagged
            $w.ConsolePlayer.Health=100
            $other=[Mobj]::new($w);$other.Type=$actor.Type;$other.Health=1;$w.Thinkers.Add($other)
            $w.MonsterBehavior.BossDeath($actor)
            Check-Untriggered "$label another living boss" $w $tagged
            $other.Health=0
            # Enter the actual final death state, including its action dispatch.
            $null=$actor.SetState([MobjState]::$($case[3]))
            if($case[4] -eq 'Exit'){
                Check "$label last boss exits" $true $w.Completed
                Check "$label normal exit" $false $w.SecretExit
            }else{
                Check "$label geometry trigger does not exit" $false $w.Completed
                foreach($s in $tagged){
                    $mover=$s.SpecialData;$prefix="$label sector $($s.Number)"
                    $neighbors=@(foreach($line in $s.Lines){
                        if($null -ne $line.FrontSector -and $null -ne $line.BackSector){
                            if([object]::ReferenceEquals($line.FrontSector,$s)){$line.BackSector}else{$line.FrontSector}
                        }
                    })
                    if($case[4] -eq 'Floor'){
                        Check "$prefix floor mover" $true ($mover -is [FloorMove])
                        $destination=$s.FloorHeight.Data
                        foreach($neighbor in $neighbors){$destination=[Math]::Min($destination,$neighbor.FloorHeight.Data)}
                        Check "$prefix lower-to-lowest type" 'LowerFloorToLowest' $mover.Type.ToString()
                        Check "$prefix direction" -1 $mover.Direction
                        Check "$prefix speed" 65536 $mover.Speed.Data
                        Check "$prefix target" $destination $mover.FloorDestHeight.Data
                    }else{
                        Check "$prefix door mover" $true ($mover -is [VerticalDoor])
                        $destination=([int]::MaxValue)
                        foreach($neighbor in $neighbors){$destination=[Math]::Min($destination,$neighbor.CeilingHeight.Data)}
                        $destination-=4*65536
                        Check "$prefix blaze-open type" 'BlazeOpen' $mover.Type.ToString()
                        Check "$prefix direction" 1 $mover.Direction
                        Check "$prefix speed" (8*65536) $mover.Speed.Data
                        Check "$prefix target" $destination $mover.TopHeight.Data
                    }
                    for($tic=0;$tic -lt 4096 -and $null -ne $s.SpecialData;$tic++){$w.LevelTime=$tic;$mover.Run()}
                    Check "$prefix mover completes" $true ($null -eq $s.SpecialData)
                    $actual=if($case[4] -eq 'Floor'){$s.FloorHeight.Data}else{$s.CeilingHeight.Data}
                    Check "$prefix final height" $destination $actual
                }
            }
        }catch{$errors.Add("${label}: $($_.ToString())`n$($_.ScriptStackTrace)")}
    }
}finally{
    if($content){$content.Dispose()}
    @{Passed=($errors.Count -eq 0);Errors=$errors.ToArray();Checks=$checks.ToArray();WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Reference='https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/p_enemy.c';Meaning='HMP real-map boss-trigger fixtures: explicit health/type/map changes and a synthetic same-type thinker test guards, then actual final death-state dispatch and bounded tagged mover execution. Independent neighbor-height targets. No ordinary-input victory, full-world continuation, live rendering or performance claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
if($errors.Count){throw 'Boss progression checks failed; inspect result.'}
"PASS: $($checks.Count) boss progression checks."
