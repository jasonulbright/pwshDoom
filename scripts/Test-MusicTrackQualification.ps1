#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Qualification,[Parameter(Mandatory)][string]$Reference,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/MusicLoopReader.ps1";. "$PSScriptRoot/../src/AudioMixer.ps1"
$checks=[Collections.Generic.List[object]]::new();$reader=$null;$digest=$null;$failure=$null;$details=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Hash([byte[]]$Bytes){[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
try{
    $r=Get-Content $Qualification -Raw|ConvertFrom-Json;$d=$r.Details;$ref=(Get-Content $Reference -Raw|ConvertFrom-Json).Details
    Check 'Continuous synthesis report qualified the matching score and bank' (-not $r.Error -and $d.Qualified -and $d.MusSha256 -ceq $ref.MusSha256 -and $d.BankSha256 -ceq $ref.SoundFontSha256 -and $d.SourcesChangedDuringRun.Count -eq 0)
    $reader=Open-DoomMusicLoopReader $Qualification
    Check 'Actual period exceeds old reader limit and opens under the new bound' ($d.PeriodFrames -gt 4410000 -and $d.PeriodFrames -le 52920000)
    $wav=[IO.File]::ReadAllBytes($ref.WavPath);$expected=[byte[]]::new($wav.Length-44);[Buffer]::BlockCopy($wav,44,$expected,0,$expected.Length)
    Check 'Independent reference WAV is intact and frame-aligned' ((Get-FileHash $ref.WavPath).Hash -ceq $ref.WavSha256 -and $expected.Length -eq $ref.Frames*4 -and $ref.Frames%1260 -eq 0)
    $mixer=New-DoomAudioMixer;$digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
    for($f=0;$f -lt $ref.Frames;$f+=1260){$b=Read-DoomMusicLoop $reader 1260;$pcm=Read-DoomAudioFrames $mixer 1260 -Music $b.Mix -MusicGain $ref.Volume;$bytes=[byte[]]::new(5040);[Buffer]::BlockCopy($pcm,0,$bytes,0,$bytes.Length);$digest.AppendData($bytes)}
    $actual=[Convert]::ToHexString($digest.GetHashAndReset());Check 'Reader plus game PCM mixer exactly reproduces independent opening' ($actual -ceq (Hash $expected))
    $reader.Frame=2L*$d.PeriodFrames-630;$block=Read-DoomMusicLoop $reader 1260
    $actualBytes=[byte[]]::new(20160);[Buffer]::BlockCopy($block.Mix,0,$actualBytes,0,20160);$expectedBytes=[byte[]]::new(20160)
    $file=[IO.File]::OpenRead($d.Periods[1].Path);try{$file.Position=($d.PeriodFrames-630)*16;$file.ReadExactly($expectedBytes,0,10080)}finally{$file.Dispose()}
    $file=[IO.File]::OpenRead($d.Periods[2].Path);try{$file.ReadExactly($expectedBytes,10080,10080)}finally{$file.Dispose()}
    Check 'Reusable boundary equals independently continuous second-to-third period bytes' ((Hash $actualBytes) -ceq (Hash $expectedBytes) -and $reader.Frame -eq 2L*$d.PeriodFrames+630)
    Close-DoomMusicLoopReader $reader;Check 'Qualified payload handles close' $reader.Closed
    $details=@{Track=$d.Track;PeriodFrames=$d.PeriodFrames;OpeningPcmSha256=$actual;BoundaryFloatSha256=(Hash $actualBytes);QualificationSha256=(Get-FileHash $Qualification).Hash;ReferenceSha256=(Get-FileHash $Reference).Hash}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($reader -and -not $reader.Closed){Close-DoomMusicLoopReader $reader};if($digest){$digest.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();Details=$details;Sources=@('src/MusicLoopReader.ps1','src/AudioMixer.ps1','scripts/Test-MusicTrackQualification.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});Meaning='Actual long-period reader with source/payload verification, independent original-renderer opening PCM through the game mixer, and exact boundary bytes against the independently synthesized following period. No device, campaign completion or performance claim.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) long-track reader checks."
