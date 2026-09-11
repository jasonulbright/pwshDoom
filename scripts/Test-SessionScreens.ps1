#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Output="$PSScriptRoot/../local/session-screens.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh result path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/SessionScreens.ps1"
$content=$null;$checks=[Collections.Generic.List[object]]::new();$failure=$null
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$o=[GameOptions]::new();$o.GameMode=$content.Wad.GameMode
    $game=[DoomGame]::new($content,$o);$cmds=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$cmds[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($cmds)
    $screens=New-DoomSessionScreens $content
    foreach($episode in 1..4){
        $o.Episode=$episode;$o.Map=1;$game.DoCompleted()
        foreach($phase in 'Stats','Next'){
            if($phase -eq 'Next'){$game.Intermission.InitShowNextLoc()}
            $watch=[Diagnostics.Stopwatch]::StartNew();$pixels=Get-DoomSessionScreen $screens $game
            $checks.Add(@{Episode=$episode;Screen=$phase;Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($pixels));Milliseconds=$watch.Elapsed.TotalMilliseconds})
            [IO.File]::WriteAllBytes("$PSScriptRoot/../local/session-e$episode-$phase.columns.bin",$pixels)
        }
        $o.Map=8;$game.DoCompleted()
        foreach($line in $game.Finale.Text.Split("`n")){
            if($line.Length -gt 0 -and ($line[0] -eq ' ' -or $screens.Screen.MeasureText($line,1) -gt 310)){throw "Episode $episode finale line would be indented or clipped."}
        }
        foreach($count in 10,100,2000){
            $game.Finale.Stage=0;$game.Finale.Count=$count
            $watch=[Diagnostics.Stopwatch]::StartNew();$pixels=Get-DoomSessionScreen $screens $game
            $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($pixels))
            if($episode -eq 1 -and $count -eq 10 -and $hash -ne 'EFC956D018419E95AE4313BF6E6C62A142112DEE476FA1DFD28134447A5FEFE3'){throw 'Cached finale background differs from the original reference fill.'}
            $checks.Add(@{Episode=$episode;Screen="Text$count";Sha256=$hash;Milliseconds=$watch.Elapsed.TotalMilliseconds})
            if($count -eq 2000){[IO.File]::WriteAllBytes("$PSScriptRoot/../local/session-e$episode-text.columns.bin",$pixels)}
        }
        $game.Finale.Stage=1;$game.Finale.Count=0
        $pixels=Get-DoomSessionScreen $screens $game
        $checks.Add(@{Episode=$episode;Screen='Art';Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($pixels))})
        [IO.File]::WriteAllBytes("$PSScriptRoot/../local/session-e$episode-art.columns.bin",$pixels)
    }
}catch{$failure=$_.ToString();throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();WadSha256=(Get-FileHash -LiteralPath $Wad).Hash;
        Meaning='All four episodes: isolated stats, next-map, three text reveal states, and end-art rendering. E1 blank text background matches the pre-fix reference fill exactly. Screen hashes and smoke success are not complete visual fidelity qualification.'}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($checks.Count) session screens rendered."
