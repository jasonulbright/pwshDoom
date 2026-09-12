# SPDX-License-Identifier: GPL-2.0-or-later
# Exact finite prefixes of continuously synthesized music. No implicit loop reuse.
function Get-DoomMusicCacheKey {
    param([string]$Identity)
    if([string]::IsNullOrWhiteSpace($Identity) -or $Identity.Length -gt 65536){throw 'Invalid music cache identity.'}
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Identity)))
}
function Read-DoomMusicCacheManifest {
    param([string]$Directory,[string]$Identity)
    $path=Join-Path $Directory 'manifest.json';$key=Get-DoomMusicCacheKey $Identity
    if(-not [IO.File]::Exists($path)){return @{Version=1;Key=$key;Identity=$Identity;Rate=44100;ChunkFrames=25200;Chunks=@()}}
    if(([IO.FileInfo]::new($path)).Length -gt 16MB){throw 'Music cache manifest exceeds size bound.'}
    $m=[IO.File]::ReadAllText($path)|ConvertFrom-Json -AsHashtable
    if($m.Version -ne 1 -or $m.Key -cne $key -or $m.Identity -cne $Identity -or $m.Rate -ne 44100 -or $m.ChunkFrames -ne 25200 -or $m.Chunks.Count -gt 37800){throw 'Music cache identity or format mismatch.'}
    for($i=0;$i -lt $m.Chunks.Count;$i++){
        $c=$m.Chunks[$i]
        if($c.Index -ne $i -or $c.Frame -ne [long]$i*25200 -or $c.Sha256 -cnotmatch '^[0-9A-F]{64}$'){throw 'Invalid music cache chunk manifest.'}
    }
    return $m
}
function Write-DoomMusicCacheManifest {
    param($Writer)
    $temp=Join-Path $Writer.Directory ('manifest-'+[guid]::NewGuid().ToString('N')+'.partial')
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Writer.Manifest|ConvertTo-Json -Depth 5 -Compress))
    $file=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$file.Write($bytes);$file.Flush($true)}finally{$file.Dispose()}
    [IO.File]::Move($temp,(Join-Path $Writer.Directory 'manifest.json'),$true)
}
function Open-DoomMusicCacheWriter {
    param([string]$Root,[string]$Identity)
    if(-not [BitConverter]::IsLittleEndian){throw 'Music cache v1 requires little endian doubles.'}
    $dir=Join-Path ([IO.Path]::GetFullPath($Root)) (Get-DoomMusicCacheKey $Identity)
    $null=[IO.Directory]::CreateDirectory($dir)
    $lock=[IO.File]::Open((Join-Path $dir 'writer.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        $writer=@{Directory=$dir;Manifest=(Read-DoomMusicCacheManifest $dir $Identity);Lock=$lock;Closed=$false}
        if(-not [IO.File]::Exists((Join-Path $dir 'manifest.json'))){Write-DoomMusicCacheManifest $writer}
        return $writer
    }catch{$lock.Dispose();throw}
}
function Close-DoomMusicCacheWriter {
    param($Writer)
    if(-not $Writer.Closed){$Writer.Lock.Dispose();$Writer.Closed=$true}
}
function Read-DoomMusicCacheChunk {
    param([string]$Directory,$Chunk)
    $path=Join-Path $Directory ("$($Chunk.Index)-$($Chunk.Sha256).f64")
    if(([IO.FileInfo]::new($path)).Length -ne 403200){throw 'Missing or truncated music cache chunk.'}
    $bytes=[IO.File]::ReadAllBytes($path)
    if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne $Chunk.Sha256){throw 'Music cache chunk checksum mismatch.'}
    $mix=[double[]]::new(50400);[Buffer]::BlockCopy($bytes,0,$mix,0,$bytes.Length)
    return ,$mix
}
function Add-DoomMusicCacheChunk {
    param($Writer,[long]$Frame,[double[]]$Mix)
    if($Writer.Closed){throw 'Music cache writer is closed.'}
    $index=$Writer.Manifest.Chunks.Count
    if($index -ge 37800 -or $Frame -ne [long]$index*25200 -or $Mix.Length -ne 50400){throw 'Music cache append must be one complete sequential chunk.'}
    foreach($value in $Mix){if(-not ($value -le [double]::MaxValue -and $value -ge -[double]::MaxValue)){throw 'Nonfinite music cache sample.'}}
    $bytes=[byte[]]::new(403200);[Buffer]::BlockCopy($Mix,0,$bytes,0,$bytes.Length)
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));$name="$index-$hash.f64"
    $temp=Join-Path $Writer.Directory ([guid]::NewGuid().ToString('N')+'.partial');$target=Join-Path $Writer.Directory $name
    $file=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$file.Write($bytes);$file.Flush($true)}finally{$file.Dispose()}
    if([IO.File]::Exists($target)){
        # A previous interrupted publication may have left the same immutable payload.
        if((Get-FileHash $target).Hash -cne $hash){throw 'Conflicting orphan music cache chunk.'}
        [IO.File]::Delete($temp)
    }else{[IO.File]::Move($temp,$target)}
    $before=$Writer.Manifest.Chunks
    $Writer.Manifest.Chunks=@($before)+@(@{Index=$index;Frame=$Frame;Sha256=$hash})
    try{Write-DoomMusicCacheManifest $Writer}catch{$Writer.Manifest.Chunks=$before;throw}
}
function Open-DoomMusicCacheReader {
    param([string]$Root,[string]$Identity)
    if(-not [BitConverter]::IsLittleEndian){throw 'Music cache v1 requires little endian doubles.'}
    $dir=Join-Path ([IO.Path]::GetFullPath($Root)) (Get-DoomMusicCacheKey $Identity)
    $m=Read-DoomMusicCacheManifest $dir $Identity
    return @{Directory=$dir;Manifest=$m;Frame=0L;Paused=$false;LoadedIndex=-1;Loaded=$null;PayloadBytesRead=0L}
}
function Read-DoomMusicCache {
    param($Reader,[ValidateRange(1,44100)][int]$Frames)
    $begin=$Reader.Frame;$mix=[double[]]::new($Frames*2)
    if($Reader.Paused){return @{Frame=$begin;Frames=$Frames;Mix=$mix;Paused=$true}}
    if($begin+$Frames -gt [long]$Reader.Manifest.Chunks.Count*25200){throw 'Music cache prefix exhausted; explicit extension is required.'}
    [int]$copied=0
    while($copied -lt $Frames){
        $absolute=$begin+$copied;[long]$offset=0;$index=[Math]::DivRem($absolute,25200L,[ref]$offset)
        if($Reader.LoadedIndex -ne $index){
            $Reader.Loaded=Read-DoomMusicCacheChunk $Reader.Directory $Reader.Manifest.Chunks[$index]
            $Reader.LoadedIndex=$index;$Reader.PayloadBytesRead+=403200
        }
        $count=[Math]::Min($Frames-$copied,25200-$offset)
        [Array]::Copy($Reader.Loaded,$offset*2,$mix,$copied*2,$count*2);$copied+=$count
    }
    $Reader.Frame+=$Frames
    return @{Frame=$begin;Frames=$Frames;Mix=$mix;Paused=$false}
}
