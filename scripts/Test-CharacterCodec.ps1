#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/CharacterCodec.ps1"
. "$PSScriptRoot/../src/Viewport.ps1"
# Independent terminal-cell decoder: reject unparsed bytes, duplicate writes,
# out-of-range colors, missing cells, and cursor positions outside the viewport.
function Read-CharacterCells {
    param([string]$Text,[int]$Columns,[int]$Rows,[int]$Left=0,[int]$Top=0)
    $cells=[object[]]::new($Columns*$Rows);$row=0;$column=0;$fg=$null;$bg=$null;$consumed=0
    foreach($match in [regex]::Matches($Text,"$([char]27)\[([0-9;]+)([Hm])|([^\x1b])")) {
        if($match.Index -ne $consumed){throw 'Unrecognized terminal sequence.'};$consumed+=$match.Length
        if($match.Groups[2].Value -eq 'H') {
            $v=[int[]]$match.Groups[1].Value.Split(';');if($v.Count -ne 2){throw 'Invalid cursor sequence.'}
            $row=$v[0]-1-$Top;$column=$v[1]-1-$Left
        } elseif($match.Groups[2].Value -eq 'm') {
            $v=[int[]]$match.Groups[1].Value.Split(';')
            if($v.Count -ne 10 -or $v[0] -ne 38 -or $v[1] -ne 2 -or $v[5] -ne 48 -or $v[6] -ne 2){throw 'Invalid truecolor sequence.'}
            foreach($i in 2,3,4,7,8,9){if($v[$i] -lt 0 -or $v[$i] -gt 255){throw 'Color out of range.'}}
            $fg=$v[2..4];$bg=$v[7..9]
        } else {
            if($row -lt 0 -or $row -ge $Rows -or $column -lt 0 -or $column -ge $Columns -or $null -eq $fg){throw 'Unpositioned or uncolored glyph.'}
            $i=$row*$Columns+$column;if($null -ne $cells[$i]){throw 'Cell written twice.'}
            $glyph=$match.Groups[3].Value
            $cells[$i]=@{Glyph=$glyph;Foreground=$fg;Background=$bg;Signature="$glyph|$($fg -join ',')|$($bg -join ',')"};$column++
        }
    }
    if($consumed -ne $Text.Length -or @($cells | Where-Object {$null -eq $_}).Count){throw 'Output is incomplete.'}
    return ,$cells
}
$checks=[Collections.Generic.List[object]]::new();$palette=New-TestPalette 256
foreach($style in 'AnsiArt','Matrix') {
    $ctx=New-CharacterCodecContext $palette $style
    foreach($pattern in 'Coherent','Entropy') {
        $source=New-IndexedFrame 34 24 3 $pattern 256;$before=[Convert]::ToBase64String($source)
        foreach($origin in @(@(0,0),@(13,9))) {
            foreach($time in 0,123,987) {
                $serial=ConvertTo-CharacterStrip $source 34 24 0 34 $ctx -ColumnOffset $origin[0] -RowOffset $origin[1] -FrameNumber $time -HudStart 16
                if($serial -isnot [byte[]]){throw 'Byte array was enumerated.'}
                $expected=Read-CharacterCells ([Text.Encoding]::UTF8.GetString($serial)) 17 6 $origin[0] $origin[1]
                foreach($workers in 1,3,7) {
                    $parts=[Collections.Generic.List[string]]::new()
                    for($i=0;$i -lt $workers;$i++) {
                        $first=2*[int][Math]::Floor($i*17.0/$workers);$end=2*[int][Math]::Floor(($i+1)*17.0/$workers)
                        $part=ConvertTo-CharacterStrip $source 34 24 $first $end $ctx -ColumnOffset $origin[0] -RowOffset $origin[1] -FrameNumber $time -HudStart 16
                        $parts.Add([Text.Encoding]::UTF8.GetString($part))
                    }
                    $actual=Read-CharacterCells ([string]::Concat($parts)) 17 6 $origin[0] $origin[1]
                    if(($actual.Signature -join ';') -cne ($expected.Signature -join ';')){throw 'Partition seam or origin mismatch.'}
                    $checks.Add(@{Style=$style;Pattern=$pattern;Workers=$workers;Origin=$origin;FrameNumber=$time;Cells=102})
                }
            }
        }
        if([Convert]::ToBase64String($source) -cne $before){throw 'Source framebuffer was mutated.'}
    }
    $source=New-IndexedFrame 320 200 3 Entropy 256
    $textA=[Text.Encoding]::UTF8.GetString((ConvertTo-CharacterStrip $source 320 200 0 320 $ctx -FrameNumber 180))
    $textB=[Text.Encoding]::UTF8.GetString((ConvertTo-CharacterStrip $source 320 200 0 320 $ctx -FrameNumber 240))
    $repeat=[Text.Encoding]::UTF8.GetString((ConvertTo-CharacterStrip $source 320 200 0 320 $ctx -FrameNumber 180))
    if($textA -cne $repeat){throw 'Same image and clock are not deterministic.'}
    $cellsA=Read-CharacterCells $textA 160 50;$cellsB=Read-CharacterCells $textB 160 50
    if(($cellsA[6720..7999].Signature -join ';') -cne ($cellsB[6720..7999].Signature -join ';')){throw 'Rain affected the HUD.'}
    foreach($cell in $cellsA[6720..7999]){if($cell.Glyph -cne [string][char]0x2580){throw 'HUD is not half blocks.'}}
    if($style -eq 'Matrix') {
        if($textA -ceq $textB){throw 'Matrix animation did not advance.'}
        foreach($cell in $cellsA){if($cell.Foreground[1] -lt $cell.Foreground[0] -or $cell.Foreground[1] -lt $cell.Foreground[2]){throw 'Matrix color is not green dominant.'}}
    } elseif($textA -cne $textB){throw 'Color art changed without a source-image change.'}
}
# Hand-defined brightness and edge probes do not use the encoder's lookup tables.
$gray=[int[][]]::new(256);for($i=0;$i -lt 256;$i++){$gray[$i]=@($i,$i,$i)}
$ctx=New-CharacterCodecContext $gray AnsiArt;$source=[byte[]]::new(32)
for($y=0;$y -lt 4;$y++){
    $source[$y*8+2]=255;$source[$y*8+3]=255 # white cell
    $source[$y*8+5]=255 # left/right edge
    if($y -ge 2){$source[$y*8+6]=255;$source[$y*8+7]=255} # top/bottom edge
}
$cells=Read-CharacterCells ([Text.Encoding]::UTF8.GetString((ConvertTo-CharacterStrip $source 8 4 0 8 $ctx -HudStart 4))) 4 1
if(($cells.Glyph -join '') -cne ' @|-'){throw 'Black/white/vertical/horizontal probes failed.'}
$guards=0
foreach($invalid in @(@(7,4,0,6,4),@(8,3,0,8,0),@(8,4,1,8,4),@(8,4,0,7,4),@(8,4,0,8,3),@(8,4,0,10,4))) {
    $failed=$false
    try{$null=ConvertTo-CharacterStrip ([byte[]]::new($invalid[0]*$invalid[1])) $invalid[0] $invalid[1] $invalid[2] $invalid[3] $ctx -HudStart $invalid[4]}catch{$failed=$true}
    if(-not $failed){throw 'Invalid dimensions were accepted.'};$guards++
}
$layouts=0
foreach($style in 'AnsiArt','Matrix') {
    foreach($case in @(@(160,50,$false,$true,0,0),@(160,52,$true,$true,0,2),@(159,50,$false,$false,0,0),@(160,49,$false,$false,0,0),@(320,98,$false,$true,80,24))) {
        $v=Get-DoomViewport $case[0] $case[1] -Diagnostics:$case[2] -Style $style
        if($v.Fits -ne $case[3] -or $v.Left -ne $case[4] -or $v.Top -ne $case[5] -or $v.Width -ne 160 -or $v.Height -ne 50){throw 'Character viewport mismatch.'};$layouts++
    }
}
@{FinishedUtc=[DateTime]::UtcNow.ToString('o');PartitionChecks=$checks.ToArray();FullFrameTemporalStyles=2;FullFrameCellsPerStyle=8000;
    IndependentBrightnessEdgeProbes=4;RejectedInvalidDimensions=$guards;ViewportCases=$layouts;
    CodecSha256=(Get-FileHash "$PSScriptRoot/../src/CharacterCodec.ps1").Hash;
    Meaning='Independent ANSI decoding checks full coverage, truecolor bounds, partition equivalence, determinism, stable block HUD, green dominance, immutable source pixels and hand-defined contrast/edge cases. Not a perceptual readability or displayed-frame-rate test.'} |
    ConvertTo-Json -Depth 8 | Set-Content "$PSScriptRoot/../results/character-codec-tests.json"
"PASS: $($checks.Count) character partition cases, full-frame temporal/HUD checks, 4 independent edge/brightness probes, $guards guards, $layouts viewport cases."
