# SPDX-License-Identifier: GPL-2.0-or-later
function ConvertTo-AnsiStrip {
    param([byte[]]$Pixels,[int]$Width,[int]$Height,[int]$FirstColumn,[int]$EndColumn,[hashtable]$Context)
    [string[]]$cells=$Context.Cells; [int]$count=$Context.Count; [string]$block=[char]0x2580
    [string[]]$chunks=[string[]]::new(($EndColumn-$FirstColumn+1)*[int][Math]::Ceiling($Height/2))
    [int]$n=0;[int]$last=-1
    for([int]$y=0;$y -lt $Height;$y+=2) {
        $chunks[$n++]="$([char]27)[$([int]($y/2)+3);$($FirstColumn+1)H"
        [int]$top=$y*$Width; [int]$bottom=[Math]::Min($y+1,$Height-1)*$Width
        for([int]$x=$FirstColumn;$x -lt $EndColumn;$x++) {
            [int]$pair=[int]$Pixels[$top+$x]*$count+[int]$Pixels[$bottom+$x]
            if($pair -eq $last){$chunks[$n++]=$block}else{$chunks[$n++]=$cells[$pair];$last=$pair}
        }
    }
    # Preserve the byte array as one object: pipeline enumeration of every byte
    # would dominate frame encoding and defeat the shared-memory transport.
    return ,([Text.Encoding]::UTF8.GetBytes([string]::Concat($chunks)))
}
