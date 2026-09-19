# SPDX-License-Identifier: GPL-2.0-or-later
# Preserve the encoded terminal byte stream while selecting write granularity.
function New-DoomTerminalOutputContext {
    return @{Buffer=[byte[]]::new(0);Frames=0L;Bytes=0L;Writes=0L}
}
function Write-DoomTerminalFrame {
    param($Context,[IO.Stream]$Stream,$Results,[byte[]]$Start,[byte[]]$End,
        [byte[]]$Clear=[byte[]]::new(0),[byte[]]$Status=[byte[]]::new(0),[ValidateSet('Strips','Batch')][string]$Mode='Strips')
    [int]$length=$Start.Length+$End.Length+$Clear.Length+$Status.Length
    foreach($result in $Results){$length+=$result.Bytes.Length}
    if($Mode -eq 'Strips'){
        $Stream.Write($Start,0,$Start.Length)
        if($Clear.Length){$Stream.Write($Clear,0,$Clear.Length)}
        foreach($result in $Results){$Stream.Write($result.Bytes,0,$result.Bytes.Length)}
        if($Status.Length){$Stream.Write($Status,0,$Status.Length)}
        $Stream.Write($End,0,$End.Length)
        $Context.Writes+=2+$Results.Count+[int]($Clear.Length -gt 0)+[int]($Status.Length -gt 0)
    }else{
        if($Context.Buffer.Length -lt $length){$Context.Buffer=[byte[]]::new([int]([Math]::Ceiling($length/65536.0)*65536))}
        [byte[]]$buffer=$Context.Buffer;[int]$offset=0
        [Buffer]::BlockCopy($Start,0,$buffer,$offset,$Start.Length);$offset+=$Start.Length
        [Buffer]::BlockCopy($Clear,0,$buffer,$offset,$Clear.Length);$offset+=$Clear.Length
        foreach($result in $Results){[Buffer]::BlockCopy($result.Bytes,0,$buffer,$offset,$result.Bytes.Length);$offset+=$result.Bytes.Length}
        [Buffer]::BlockCopy($Status,0,$buffer,$offset,$Status.Length);$offset+=$Status.Length
        [Buffer]::BlockCopy($End,0,$buffer,$offset,$End.Length)
        $Stream.Write($buffer,0,$length);$Context.Writes++
    }
    $Stream.Flush();$Context.Frames++;$Context.Bytes+=$length
}
