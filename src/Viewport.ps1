# SPDX-License-Identifier: GPL-2.0-or-later
function Get-DoomViewport {
    param([int]$Columns,[int]$Rows,[switch]$Diagnostics,[ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic')
    $statusRows=if($Diagnostics){2}else{0}
    $width=if($Style -eq 'Classic'){320}else{160};$imageHeight=if($Style -eq 'Classic'){100}else{50}
    $height=$imageHeight+$statusRows;$fits=$Columns -ge $width -and $Rows -ge $height
    $left=0;$top=0
    if($fits){$left=[int][Math]::Floor(($Columns-$width)/2.0);$top=[int][Math]::Floor(($Rows-$height)/2.0)}
    return @{Columns=$Columns;Rows=$Rows;Fits=$fits;Left=$left;Top=$top+$statusRows;StatusTop=$top;
        Width=$width;Height=$imageHeight;RequiredColumns=$width;RequiredRows=$height;Style=$Style;Key="$Columns,$Rows,$statusRows,$Style"}
}
function Get-DoomViewportMessage {
    param($Viewport)
    $lines=@('pwshDoom paused',
        "Resize to $($Viewport.RequiredColumns) columns x $($Viewport.RequiredRows) rows, or zoom the terminal font out.",
        "Current size: $($Viewport.Columns) x $($Viewport.Rows). Esc quits.")
    $result=[Collections.Generic.List[string]]::new();$limit=[Math]::Max(0,$Viewport.Columns-1)
    for($i=0;$i -lt [Math]::Min($lines.Count,$Viewport.Rows);$i++) {
        $line=$lines[$i];if($line.Length -gt $limit){$line=$line.Substring(0,$limit)};$result.Add($line)
    }
    return [string]::Join("`r`n",$result)
}
