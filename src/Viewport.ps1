# SPDX-License-Identifier: GPL-2.0-or-later
function Get-DoomViewport {
    param([int]$Columns,[int]$Rows,[switch]$Diagnostics)
    $statusRows=if($Diagnostics){2}else{0}
    $height=100+$statusRows;$fits=$Columns -ge 320 -and $Rows -ge $height
    $left=0;$top=0
    if($fits){$left=[int][Math]::Floor(($Columns-320)/2.0);$top=[int][Math]::Floor(($Rows-$height)/2.0)}
    return @{Columns=$Columns;Rows=$Rows;Fits=$fits;Left=$left;Top=$top+$statusRows;StatusTop=$top;
        Width=320;Height=100;RequiredRows=$height;Key="$Columns,$Rows,$statusRows"}
}
function Get-DoomViewportMessage {
    param($Viewport)
    $lines=@('pwshDoom paused',
        "Resize to 320 columns x $($Viewport.RequiredRows) rows, or zoom the terminal font out.",
        "Current size: $($Viewport.Columns) x $($Viewport.Rows). Esc quits.")
    $result=[Collections.Generic.List[string]]::new();$limit=[Math]::Max(0,$Viewport.Columns-1)
    for($i=0;$i -lt [Math]::Min($lines.Count,$Viewport.Rows);$i++) {
        $line=$lines[$i];if($line.Length -gt $limit){$line=$line.Substring(0,$limit)};$result.Add($line)
    }
    return [string]::Join("`r`n",$result)
}
