#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/LoadingScreen.ps1"
$screen=New-DoomLoadingScreen;$checks=[Collections.Generic.List[object]]::new();$failure=$null
try{
    foreach($style in 'Classic','Matrix','AnsiArt'){
        foreach($size in @(@(1,1),@(8,1),@(42,10),@(43,11),@(320,100),@(160,50),@(688,123))){
            $previous=$null
            for($phase=0;$phase -lt 4;$phase++){
                $bytes=Get-DoomLoadingOutput $screen $size[0] $size[1] $phase -Style $style -Clear:($phase -eq 0)
                $text=[Text.Encoding]::UTF8.GetString($bytes);$painted=0;$x=0;$y=0;$consumed=0
                foreach($match in [regex]::Matches($text,"$([char]27)\[([0-9;]*)([HmJ])|[^$([char]27)]+")){
                    if($match.Index -ne $consumed){throw 'Unrecognized banner sequence.'};$consumed+=$match.Length
                    if($match.Groups[2].Value -eq 'H'){
                        $coordinates=[int[]]$match.Groups[1].Value.Split(';');$y=$coordinates[0];$x=$coordinates[1]
                    }elseif(-not $match.Groups[2].Success){
                        foreach($character in $match.Value.ToCharArray()){
                            if($x -lt 1 -or $x -ge $size[0] -or $y -lt 1 -or $y -gt $size[1]){throw "Banner wraps/out of bounds at $x,$y for $($size[0]),$($size[1])"}
                            if($character -ne ' '){$painted++};$x++
                        }
                    }
                }
                if($consumed -ne $text.Length){throw 'Unparsed banner bytes.'}
                if($size[0] -ge 43 -and $size[1] -ge 11 -and $painted -lt 100){throw 'Large loading banner missing.'}
                if($phase -gt 0 -and $size[0] -ge 43 -and $text -ceq $previous){throw 'Loading indicator did not animate.'}
                $previous=$text;$checks.Add(@{Style=$style;Columns=$size[0];Rows=$size[1];Phase=$phase;Bytes=$bytes.Length;PaintedCells=$painted;Passed=$true})
            }
        }
    }
}catch{$failure=$_.ToString();throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Runtime=$PSVersionTable.PSVersion.ToString();Sources=@('src/LoadingScreen.ps1','scripts/Test-LoadingScreen.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});Meaning='Independent cursor/text decoder bounds every painted cell in three styles, four animation phases and seven viewport sizes, including a one-cell terminal. This checks UI encoding/fit, not actual display timing or gameplay FPS.'}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $Output
}
"PASS: $($checks.Count) loading UI viewport/animation cases."
