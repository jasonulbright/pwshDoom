# SPDX-License-Identifier: GPL-2.0-or-later
# Experimental truecolor encoder: update only the color component that changed.
function New-AnsiColorStateContext {
    param([int[][]]$Palette,[switch]$LazyCells)
    $context=New-CodecContext $Palette -LazyCells:$LazyCells
    $foreground=[string[]]::new($Palette.Length);$background=[string[]]::new($Palette.Length)
    $esc=[char]27;$block=[char]0x2580
    for($i=0;$i -lt $Palette.Length;$i++){
        $rgb=$Palette[$i]
        $foreground[$i]="$esc[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$block"
        $background[$i]="$esc[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$block"
    }
    $context.ForegroundCells=$foreground;$context.BackgroundCells=$background
    return $context
}
function ConvertTo-AnsiColorStateStrip {
    param([byte[]]$Pixels,[int]$Width,[int]$Height,[int]$FirstColumn,[int]$EndColumn,[hashtable]$Context,
        [int]$ColumnOffset=0,[int]$RowOffset=0)
    [string[]]$cells=$Context.Cells;[string[]]$fgCells=$Context.ForegroundCells;[string[]]$bgCells=$Context.BackgroundCells
    [int]$count=$Context.Count;[string]$block=[char]0x2580
    [string[]]$chunks=[string[]]::new(($EndColumn-$FirstColumn+1)*[int][Math]::Ceiling($Height/2))
    [int]$n=0;[int]$lastTop=-1;[int]$lastBottom=-1
    for([int]$y=0;$y -lt $Height;$y+=2){
        $chunks[$n++]="$([char]27)[$([int]($y/2)+1+$RowOffset);$($FirstColumn+1+$ColumnOffset)H"
        [int]$top=$y*$Width;[int]$bottom=[Math]::Min($y+1,$Height-1)*$Width
        for([int]$x=$FirstColumn;$x -lt $EndColumn;$x++){
            [int]$t=$Pixels[$top+$x];[int]$b=$Pixels[$bottom+$x]
            if($t -eq $lastTop){
                if($b -eq $lastBottom){$chunks[$n++]=$block}else{$chunks[$n++]=$bgCells[$b]}
            }elseif($b -eq $lastBottom){$chunks[$n++]=$fgCells[$t]}
            else{
                [int]$pair=$t*$count+$b
                if($null -eq $cells[$pair]){$cells[$pair]=$Context.TopPrefixes[$t]+$Context.BottomSuffixes[$b]}
                $chunks[$n++]=$cells[$pair]
            }
            $lastTop=$t;$lastBottom=$b
        }
    }
    return ,([Text.Encoding]::UTF8.GetBytes([string]::Concat($chunks)))
}
