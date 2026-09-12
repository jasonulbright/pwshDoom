#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/MusicCache.ps1"
$root=[IO.Path]::GetFullPath("$PSScriptRoot/../local/music-cache-test-$([guid]::NewGuid().ToString('N'))")
$checks=[Collections.Generic.List[object]]::new();$writer=$null;$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $Name $rejected}
try{
    $identity='synthetic-continuous-v1';$writer=Open-DoomMusicCacheWriter $root $identity
    Check 'New cache has empty committed prefix' ($writer.Manifest.Chunks.Count -eq 0)
    Reject 'Concurrent writer cannot acquire lock' {$other=Open-DoomMusicCacheWriter $root $identity;Close-DoomMusicCacheWriter $other}
    $a=[double[]]::new(50400);for($i=0;$i -lt $a.Length;$i++){$a[$i]=$i*.125-500}
    Reject 'Out-of-sequence append rejected' {Add-DoomMusicCacheChunk $writer 1 $a}
    Reject 'Partial chunks rejected' {Add-DoomMusicCacheChunk $writer 0 ([double[]]@(1,2))}
    $a[7]=[double]::NaN;Reject 'Nonfinite samples rejected before publication' {Add-DoomMusicCacheChunk $writer 0 $a};$a[7]=7*.125-500
    Add-DoomMusicCacheChunk $writer 0 $a
    $reader=Open-DoomMusicCacheReader $root $identity
    Check 'Append publishes a complete prefix' ($reader.Manifest.Chunks.Count -eq 1)
    $reader.Paused=$true;$paused=Read-DoomMusicCache $reader 123
    Check 'Pause outputs silence and freezes frame' ($reader.Frame -eq 0 -and $paused.Paused -and @($paused.Mix|Where-Object {$_ -ne 0}).Count -eq 0)
    $reader.Paused=$false;$first=Read-DoomMusicCache $reader 123
    Check 'Resume starts with original samples' ($reader.Frame -eq 123 -and $first.Mix[0] -eq $a[0] -and $first.Mix[-1] -eq $a[245])
    $reader.Frame=25199;Reject 'Exhaustion does not invent a loop' {$null=Read-DoomMusicCache $reader 2}
    Check 'Failed exhaustion leaves cursor unchanged' ($reader.Frame -eq 25199)
    # Orphan payload simulates a crash after data publication but before manifest commit.
    $b=[double[]]::new(50400);for($i=0;$i -lt $b.Length;$i++){$b[$i]=8000-$i*.25}
    $bytes=[byte[]]::new(403200);[Buffer]::BlockCopy($b,0,$bytes,0,$bytes.Length)
    $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    [IO.File]::WriteAllBytes((Join-Path $writer.Directory "1-$hash.f64"),$bytes)
    [IO.File]::WriteAllText((Join-Path $writer.Directory 'abandoned.partial'),'incomplete')
    $dir=$writer.Directory;Close-DoomMusicCacheWriter $writer;$writer=Open-DoomMusicCacheWriter $root $identity
    Check 'Reopen ignores uncommitted payload and partial files' ($writer.Manifest.Chunks.Count -eq 1)
    Add-DoomMusicCacheChunk $writer 25200 $b
    Check 'Identical orphan recovered into committed prefix' ($writer.Manifest.Chunks.Count -eq 2)
    Reject 'Existing reader retains immutable prefix snapshot' {$null=Read-DoomMusicCache $reader 2}
    $reader=Open-DoomMusicCacheReader $root $identity;$reader.Frame=25199;$cross=Read-DoomMusicCache $reader 3
    Check 'Reads cross chunk boundary without sample changes' ($cross.Mix[0] -eq $a[50398] -and $cross.Mix[1] -eq $a[50399] -and $cross.Mix[2] -eq $b[0] -and $cross.Mix[5] -eq $b[3])
    Check 'Reader retains one chunk and bounds disk reads' ($reader.Loaded.Length -eq 50400 -and $reader.PayloadBytesRead -eq 806400)
    Close-DoomMusicCacheWriter $writer;Reject 'Closed writer cannot append' {Add-DoomMusicCacheChunk $writer 50400 $a};$writer=$null
    Reject 'Manifest identity mismatch rejected' {$null=Read-DoomMusicCacheManifest $dir 'different-synthesis'}
    Check 'Different synthesis identity uses different directory' ((Get-DoomMusicCacheKey $identity) -cne (Get-DoomMusicCacheKey 'different-synthesis'))
    $chunkPath=Join-Path $dir "1-$hash.f64";$bytes[0]=$bytes[0] -bxor 1;[IO.File]::WriteAllBytes($chunkPath,$bytes)
    $reader=Open-DoomMusicCacheReader $root $identity;$reader.Frame=25200
    Reject 'Corrupt sample payload rejected' {$null=Read-DoomMusicCache $reader 1}
    Check 'Corrupt read does not advance frame' ($reader.Frame -eq 25200)
    [IO.File]::WriteAllBytes($chunkPath,[byte[]]@(0,1));Reject 'Truncated payload rejected' {$null=Read-DoomMusicCache $reader 1}
    $m=Read-DoomMusicCacheManifest $dir $identity;$m.Chunks[0].Sha256='../invalid';[IO.File]::WriteAllText((Join-Path $dir 'manifest.json'),($m|ConvertTo-Json -Depth 5))
    Reject 'Malformed payload identifier rejected' {$null=Open-DoomMusicCacheReader $root $identity}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($writer){Close-DoomMusicCacheWriter $writer}
    @{Error=$failure;Checks=$checks.ToArray();FixtureDirectory=$root;SourceSha256=(Get-FileHash "$PSScriptRoot/../src/MusicCache.ps1").Hash;ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Synthetic exact samples, pause/cursor, boundary reads, explicit exhaustion, writer exclusion, orphan recovery and corruption checks. No device or crash/power-loss durability certification.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) music cache checks."
