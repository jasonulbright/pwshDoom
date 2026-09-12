#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh stair report.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$checks=[Collections.Generic.List[object]]::new();$failures=[Collections.Generic.List[string]]::new();$content=$null
function Check($Name,$Expected,$Actual){$checks.Add(@{Name=$Name;Expected=$Expected;Actual=$Actual;Passed=($Expected -ceq $Actual)})}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    foreach($kind in 'Build8','Turbo16'){
        try{
            $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
            $game=[DoomGame]::new($content,$options);$game.InitNew([GameSkill]::Medium,1,3);$w=$game.World
            $step=if($kind -eq 'Build8'){8}else{16};$speed=if($kind -eq 'Build8'){.25}else{4.0}
            # Installed E1M3 exit stair chain, in oriented linedef order. A direct
            # special fixture checks floor construction; it is not campaign completion.
            $chain=@(16,17,18,19,8,9,10,11,12,13)
            Check "$kind trigger tag" 14 ([int]$w.Map.Lines[967].Tag)
            Check "$kind creates staircase" $true ($w.SectorAction.BuildStairs($w.Map.Lines[967],[StairType]::$kind))
            $floors=[Collections.Generic.List[object]]::new()
            for($i=0;$i -lt $chain.Count;$i++){
                $s=$w.Map.Sectors[$chain[$i]];$f=$s.SpecialData
                Check "$kind sector $($chain[$i]) destination" (48+($i+1)*$step) ($f.FloorDestHeight.Data/65536.0)
                Check "$kind sector $($chain[$i]) speed" $speed ($f.Speed.Data/65536.0)
                $floors.Add($f)
            }
            Check "$kind active staircase ignores retrigger" $false ($w.SectorAction.BuildStairs($w.Map.Lines[967],[StairType]::$kind))
            for($tic=0;$tic -lt 1000;$tic++){
                $w.LevelTime=$tic
                foreach($f in $floors){if($null -ne $f.Sector.SpecialData){$f.Run()}}
            }
            for($i=0;$i -lt $chain.Count;$i++){
                $s=$w.Map.Sectors[$chain[$i]]
                Check "$kind sector $($chain[$i]) final height" (48+($i+1)*$step) ($s.FloorHeight.Data/65536.0)
                Check "$kind sector $($chain[$i]) releases ownership" $true ($null -eq $s.SpecialData)
            }
        }catch{$failures.Add("${kind}: $($_.ToString())`n$($_.ScriptStackTrace)")}
    }
}finally{
    if($content){$content.Dispose()}
    @{Passed=($failures.Count -eq 0 -and @($checks|Where-Object {-not $_.Passed}).Count -eq 0);Errors=$failures.ToArray();Checks=$checks.ToArray();WadSha256=(Get-FileHash $Wad).Hash;ActionSourceSha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Doom/World/SectorAction.sb.ps1").Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='Real installed E1M3 direct staircase fixture, both step types, destinations/speeds, active retrigger rejection and bounded actual floor thinker completion. No ordinary-input campaign or live performance claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
if($failures.Count -or @($checks|Where-Object {-not $_.Passed}).Count){throw 'Staircase fixture failed; inspect report.'}
"PASS: $($checks.Count) staircase checks."
