#requires -Version 7.4
$ErrorActionPreference='Stop'
. "$PSScriptRoot/ParallelScene.ps1"
. "$PSScriptRoot/../src/TerminalCodec.ps1"
function Read-AnsiStripPixels {
    param([string]$Text,[int]$Width,[int]$Height,[int[][]]$TerminalPalette)
    $pixels=[int[]]::new($Width*$Height);[Array]::Fill($pixels,-1)
    $row=0;$column=0;$foreground=0;$background=0
    foreach($match in [regex]::Matches($Text,"$([char]27)\[([0-9;]+)([Hm])|$([char]0x2580)")){
        if($match.Groups[2].Value -eq 'H'){
            $coordinates=$match.Groups[1].Value.Split(';');$row=([int]$coordinates[0]-3)*2;$column=[int]$coordinates[1]-1
        } elseif($match.Groups[2].Value -eq 'm'){
            $v=[int[]]$match.Groups[1].Value.Split(';')
            if($v[1] -eq 2){$top=@($v[2],$v[3],$v[4]);$bottom=@($v[7],$v[8],$v[9])}
            else{$top=$TerminalPalette[$v[2]];$bottom=$TerminalPalette[$v[5]]}
            $foreground=($top[0] -shl 16)+($top[1] -shl 8)+$top[2]
            $background=($bottom[0] -shl 16)+($bottom[1] -shl 8)+$bottom[2]
        } else {
            if($column -ge $Width -or $row -lt 0 -or $row -ge $Height){throw 'ANSI strip painted outside its image.'}
            $pixels[$row*$Width+$column]=$foreground
            if($row+1 -lt $Height){$pixels[($row+1)*$Width+$column]=$background}
            $column++
        }
    }
    return ,$pixels
}
$cases=0
foreach($mode in 'TrueColor','Ansi256'){
    $palette=New-TestPalette 256
    $context=if($mode -eq 'TrueColor'){New-CodecContext $palette}else{New-Ansi256Context $palette}
    foreach($pattern in 'Coherent','Entropy'){
        $source=New-IndexedFrame 17 13 3 $pattern 256
        foreach($workers in 1,3,7){
            $parts=[Collections.Generic.List[string]]::new()
            for($i=0;$i -lt $workers;$i++){
                $first=[int][Math]::Floor($i*17.0/$workers);$end=[int][Math]::Floor(($i+1)*17.0/$workers)
                $bytes=ConvertTo-AnsiStrip $source 17 13 $first $end $context
                if($bytes -isnot [byte[]]){throw 'Byte array was enumerated through the pipeline.'}
                $parts.Add([Text.Encoding]::UTF8.GetString($bytes))
            }
            $terminalPalette=if($mode -eq 'Ansi256'){$context.TerminalPalette}else{$null}
            $actual=Read-AnsiStripPixels ([string]::Concat($parts)) 17 13 $terminalPalette
            for($i=0;$i -lt $source.Length;$i++){
                $rgb=if($mode -eq 'TrueColor'){$palette[$source[$i]]}else{$context.TerminalPalette[$context.Mapping[$source[$i]]]}
                $expected=($rgb[0] -shl 16)+($rgb[1] -shl 8)+$rgb[2]
                if($actual[$i] -ne $expected){throw "Pixel mismatch $mode $pattern $workers workers, pixel $i"}
            }
            $cases++
        }
    }
}
Write-Host "PASS: $cases ANSI strip round-trips, byte-array type, both color modes, odd dimensions and uneven partitions."
