#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[ValidateRange(1,525)][int]$Chunks=172,
    [string]$CacheRoot="$PSScriptRoot/../local/music-cache",
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2",
    [ValidatePattern('^D_[A-Z0-9]+$')][string]$Track='D_E1M1',[string]$ReferenceReport)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$paths=@('MusScore','SoundFontBank','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','MusicGroup','MusicCache')
$sources=@($paths|ForEach-Object {[ordered]@{Path="src/$_.ps1";Sha256=(Get-FileHash "$root/src/$_.ps1").Hash}})
foreach($name in $paths){. "$root/src/$name.ps1"}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$root/local/music-cache-$PID.ps1";. $bundle
$archive=$null;$writer=$null;$failure=$null;$details=$null
try{
    $watch=[Diagnostics.Stopwatch]::StartNew();$archive=[Wad]::new([string[]]@($Wad))
    $score=ConvertFrom-DoomMus ($archive.ReadLump($archive.GetLumpNumber($Track))) -Name $Track
    $bankHash=(Get-FileHash $SoundFont).Hash
    $identity=([ordered]@{Version=1;Mus=$score.SourceSha256;Bank=$bankHash;Sources=$sources;Rate=44100;ChunkFrames=25200;BlockFrames=1260;MaxVoices=256;Partition='SingleContinuousGroup';Effects='Dry';SampleFormat='StereoFloat64LE';PowerShell=$PSVersionTable.PSVersion.ToString()}|ConvertTo-Json -Depth 5 -Compress)
    $writer=Open-DoomMusicCacheWriter $CacheRoot $identity;$existing=$writer.Manifest.Chunks.Count;$replayed=0
    $preparation=$watch.Elapsed.TotalSeconds;$build=[Diagnostics.Stopwatch]::StartNew()
    if($existing -lt $Chunks){
        $bank=ConvertTo-DoomSoundFontRegions (ConvertFrom-DoomSoundFont ([IO.File]::ReadAllBytes($SoundFont)))
        if($bank.SourceSha256 -cne $bankHash){throw 'SoundFont changed between identity hashing and decoding.'}
        $group=New-DoomMusicGroup $bank $score ([int[]](0..15)) ($Chunks*25200)
        for($i=0;$i -lt $Chunks;$i++){
            $chunk=Read-DoomMusicGroup $group 20
            if($i -lt $existing){
                $stored=Read-DoomMusicCacheChunk $writer.Directory $writer.Manifest.Chunks[$i]
                $bytes=[byte[]]::new(403200);[Buffer]::BlockCopy($chunk.Mix,0,$bytes,0,$bytes.Length)
                if([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -cne $writer.Manifest.Chunks[$i].Sha256){throw 'Reconstructed synthesis differs from committed cache prefix.'}
                $replayed++
            }else{Add-DoomMusicCacheChunk $writer $chunk.Frame $chunk.Mix}
            if(($i+1)%10 -eq 0 -or $i+1 -eq $Chunks){"Cached $($i+1)/$Chunks chunks; replayed $replayed."}
        }
    }
    $buildSeconds=$build.Elapsed.TotalSeconds
    $details=@{Track=$Track;CacheDirectory=$writer.Directory;Key=$writer.Manifest.Key;Identity=$identity;RequestedChunks=$Chunks;ExistingChunks=$existing;ReplayedChunks=$replayed;CommittedChunks=$writer.Manifest.Chunks.Count;Frames=[long]$writer.Manifest.Chunks.Count*25200;PayloadBytes=[long]$writer.Manifest.Chunks.Count*403200;PreparationSeconds=$preparation;BuildSeconds=$buildSeconds;Comparison=$null}
    Close-DoomMusicCacheWriter $writer;$writer=$null
    if($ReferenceReport){
        . "$root/src/AudioMixer.ps1"
        $reference=Get-Content $ReferenceReport -Raw|ConvertFrom-Json;$d=$reference.Details
        if($reference.Error -or $d.MusSha256 -cne $score.SourceSha256 -or $d.SoundFontSha256 -cne $bankHash -or $d.Frames -gt $details.Frames -or (Get-FileHash $d.WavPath).Hash -cne $d.WavSha256){throw 'Reference inputs or WAV differ.'}
        $refBytes=[IO.File]::ReadAllBytes($d.WavPath)
        if($refBytes.Length -ne 44+$d.Frames*4 -or [Text.Encoding]::ASCII.GetString($refBytes,36,4) -cne 'data'){throw 'Expected canonical PCM reference.'}
        $refPcm=[byte[]]::new($refBytes.Length-44);[Buffer]::BlockCopy($refBytes,44,$refPcm,0,$refPcm.Length)
        $expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($refPcm))
        $reader=Open-DoomMusicCacheReader $CacheRoot $identity;$pcmState=@{Volume=$d.Volume;ClippedSamples=0L}
        $digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
        try{
            $readWatch=[Diagnostics.Stopwatch]::StartNew();$maximum=0.0;$reads=0
            while($reader.Frame -lt $d.Frames){
                $blockWatch=[Diagnostics.Stopwatch]::StartNew();$count=[Math]::Min(1260,$d.Frames-$reader.Frame)
                $chunk=Read-DoomMusicCache $reader $count;$pcm=ConvertTo-DoomMusicPcm $pcmState $chunk.Mix
                $bytes=[byte[]]::new($pcm.Length*2);[Buffer]::BlockCopy($pcm,0,$bytes,0,$bytes.Length);$digest.AppendData($bytes)
                $maximum=[Math]::Max($maximum,$blockWatch.Elapsed.TotalMilliseconds);$reads++
            }
            $readSeconds=$readWatch.Elapsed.TotalSeconds;$actual=[Convert]::ToHexString($digest.GetHashAndReset())
        }finally{$digest.Dispose()}
        $details.Comparison=@{ReferenceReportSha256=(Get-FileHash $ReferenceReport).Hash;Frames=$reader.Frame;ExpectedPcmSha256=$expected;ActualPcmSha256=$actual;Exact=($actual -ceq $expected);ReadAndPcmSeconds=$readSeconds;MaximumBlockMilliseconds=$maximum;Blocks=$reads;PayloadBytesRead=$reader.PayloadBytesRead;ClippedSamples=$pcmState.ClippedSamples}
        if($actual -cne $expected){throw 'Cache playback PCM differs from reference.'}
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($writer){Close-DoomMusicCacheWriter $writer};if($archive){$archive.Dispose()}
    @{Error=$failure;Details=$details;Sources=$sources;SourcesChangedDuringRun=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash (Join-Path $root $_.Path)).Hash});ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Finite exact continuous synthesis prefix in immutable hashed float64 chunks. Cold/extension time includes bank decoding, synthesis, validation and durable disk publication. Extension reconstructs and verifies the prior prefix; warm hit skips synthesis. Cached read/PCM timing is unpaced offline and includes hashing, not physical playback or concurrent gameplay. Prefix exhaustion throws; no loop reuse or host integration.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
'PASS: finite PowerShell music cache built and requested reference checked.'
