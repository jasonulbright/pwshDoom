#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
$checks=[Collections.Generic.List[object]]::new();$lumps=[Collections.Generic.List[object]]::new();$content=$null;$failure=$null
$temp=Join-Path "$PSScriptRoot/../local" ('demo-reader-'+[guid]::NewGuid().ToString('N')+'.lmp')
function Check($Name,$Expected,$Actual){$checks.Add(@{Name=$Name;Expected=$Expected;Actual=$Actual;Passed=($Expected -ceq $Actual)});if($Expected -cne $Actual){throw "$Name : $Actual != $Expected"}}
function Commands {return ,([TicCmd[]]@([TicCmd]::new(),[TicCmd]::new(),[TicCmd]::new(),[TicCmd]::new()))}
try{
    # Authored signed movement/turn boundaries, with an explicit terminator.
    $bytes=[byte[]]@(109,2,1,1,0,0,0,0,0,1,0,0,0,127,128,128,255,255,1,127,0,128)
    [IO.File]::WriteAllBytes($temp,$bytes);$demo=[Demo]::new($temp);$cmds=Commands
    Check 'First signed command exists' $true ($demo.ReadCmd($cmds))
    Check 'Positive movement' 127 ([int]$cmds[0].ForwardMove)
    Check 'Negative sidemove' -128 ([int]$cmds[0].SideMove)
    Check 'Negative turn' -32768 ([int]$cmds[0].AngleTurn)
    Check 'All button bits' 255 ([int]$cmds[0].Buttons)
    Check 'Second command exists' $true ($demo.ReadCmd($cmds))
    Check 'Negative forward' -1 ([int]$cmds[0].ForwardMove)
    Check 'Positive turn' 32512 ([int]$cmds[0].AngleTurn)
    Check 'Terminator ends input' $false ($demo.ReadCmd($cmds))
    Check 'Terminator remains terminal' $false ($demo.ReadCmd($cmds))
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    foreach($name in 'DEMO1','DEMO2','DEMO3'){
        $bytes=[byte[]]$content.Wad.ReadLump($name);[IO.File]::WriteAllBytes($temp,$bytes)
        $memory=[Demo]::new($bytes);$file=[Demo]::new($temp);$a=Commands;$b=Commands;$n=0;$equal=$true
        Check "$name options match" ($memory.Options|Select-Object Skill,Episode,Map,Deathmatch,RespawnMonsters,FastMonsters,NoMonsters,ConsolePlayer,DemoPlayback,NetGame|ConvertTo-Json -Compress) ($file.Options|Select-Object Skill,Episode,Map,Deathmatch,RespawnMonsters,FastMonsters,NoMonsters,ConsolePlayer,DemoPlayback,NetGame|ConvertTo-Json -Compress)
        while($memory.ReadCmd($a)){
            if(-not $file.ReadCmd($b)){throw "$name file ends early"}
            for($i=0;$i -lt 4;$i++){if($a[$i].ForwardMove -ne $b[$i].ForwardMove -or $a[$i].SideMove -ne $b[$i].SideMove -or $a[$i].AngleTurn -ne $b[$i].AngleTurn -or $a[$i].Buttons -ne $b[$i].Buttons){$equal=$false}}
            if(++$n -gt $bytes.Length){throw 'Reader did not terminate.'}
        }
        Check "$name every command matches" $true $equal
        Check "$name file ends with lump" $false ($file.ReadCmd($b))
        $lumps.Add(@{Name=$name;Commands=$n;Episode=$file.Options.Episode;Map=$file.Options.Map;Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))})
    }
}catch{$failure=$_.ToString();throw}finally{
    if($content){$content.Dispose()};if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}
    @{Error=$failure;Checks=$checks.ToArray();Lumps=$lumps.ToArray();WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;Meaning='External-file and WAD-byte decoder parity plus authored signed boundaries. No simulation synchronization or campaign-completion claim. Temporary extracted demo removed.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) demo reader checks."
