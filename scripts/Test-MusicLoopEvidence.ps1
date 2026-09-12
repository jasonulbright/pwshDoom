#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$Qualification='results/music-loop-e1m1-hour-bound.json',
    [string]$StateReport='results/music-loop-state-hour-bound.json',[string]$ReaderReport='results/music-loop-reader-hour-bound.json',
    [string]$MixerReport='results/music-effect-mix-unit-first.json')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");. "$root/src/MusicLoopReader.ps1";. "$root/src/AudioMixer.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null;$reader=$null;$digest=$null;$pcmDigest=$null;$details=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    foreach($case in @(@($StateReport,23,'MusicLoopState'),@($ReaderReport,15,'MusicLoopReader'),@($MixerReport,9,'AudioMixer'))){
        $unit=Get-Content (Join-Path $root $case[0]) -Raw|ConvertFrom-Json
        Check "$($case[0]) checks pass" (-not $unit.Error -and $unit.Checks.Count -eq $case[1] -and @($unit.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
        if($case[2] -ne 'MusicLoopState'){Check "$($case[2]) unit source is current" ($unit.SourceSha256 -ceq (Get-FileHash "$root/src/$($case[2]).ps1").Hash)}
        else{foreach($s in $unit.Sources){Check "State unit source current: $($s.Path)" ($s.Sha256 -ceq (Get-FileHash (Join-Path $root $s.Path)).Hash)}}
    }
    $r=Get-Content $Qualification -Raw|ConvertFrom-Json;$d=$r.Details
    Check 'Full E1M1 qualification succeeded without source drift' (-not $r.Error -and $d.Qualified -and $d.SourcesChangedDuringRun.Count -eq 0 -and $d.Track -ceq 'D_E1M1' -and $d.PeriodFrames -eq 4233600 -and $d.RenderedFrames -eq 12700800)
    Check 'Qualifier script is current' ($r.ScriptSha256 -ceq (Get-FileHash "$root/scripts/Qualify-MusicLoop.ps1").Hash)
    Check 'Loop states retain 35 live voices and exact component hashes' ($d.Snapshots[1].VoiceCount -eq 35 -and $d.Snapshots[2].VoiceCount -eq 35 -and $d.Snapshots[3].VoiceCount -eq 35 -and $d.Snapshots[1].StateSha256 -ceq $d.Snapshots[2].StateSha256 -and $d.Snapshots[2].StateSha256 -ceq $d.Snapshots[3].StateSha256)
    $reader=Open-DoomMusicLoopReader $Qualification
    $reference=Get-Content "$root/results/music-e1m1-dry-numeric-loop.json" -Raw|ConvertFrom-Json;$ref=$reference.Details
    $refBytes=[IO.File]::ReadAllBytes($ref.WavPath);$refPcm=[byte[]]::new($refBytes.Length-44);[Buffer]::BlockCopy($refBytes,44,$refPcm,0,$refPcm.Length)
    $expectedPcm=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($refPcm))
    Check 'Original PCM/WAV evidence agrees with qualification' ((Get-FileHash $ref.WavPath).Hash -ceq $ref.WavSha256 -and $expectedPcm -ceq $d.Reference.ActualPcmSha256 -and $reader.MusSha256 -ceq $ref.MusSha256 -and $reader.BankSha256 -ceq $ref.SoundFontSha256)
    $pcmDigest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256);$mixer=New-DoomAudioMixer;$periodHashes=[Collections.Generic.List[string]]::new()
    $watch=[Diagnostics.Stopwatch]::StartNew();$maximum=0.0
    for($period=0;$period -lt 4;$period++){
        $digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
        while($reader.Frame -lt ($period+1)*$d.PeriodFrames){
            $blockWatch=[Diagnostics.Stopwatch]::StartNew();$block=Read-DoomMusicLoop $reader 1260
            $bytes=[byte[]]::new($block.Mix.Length*8);[Buffer]::BlockCopy($block.Mix,0,$bytes,0,$bytes.Length);$digest.AppendData($bytes)
            if($block.Frame -lt $ref.Frames){
                $pcm=Read-DoomAudioFrames $mixer 1260 -Music $block.Mix -MusicGain $ref.Volume
                $pcmBytes=[byte[]]::new($pcm.Length*2);[Buffer]::BlockCopy($pcm,0,$pcmBytes,0,$pcmBytes.Length);$pcmDigest.AppendData($pcmBytes)
            }
            $maximum=[Math]::Max($maximum,$blockWatch.Elapsed.TotalMilliseconds)
        }
        $hash=[Convert]::ToHexString($digest.GetHashAndReset());$digest.Dispose();$digest=$null;$periodHashes.Add($hash)
        $expected=if($period -eq 0){$d.Periods[0].Sha256}elseif($period -eq 2){$d.Periods[2].Sha256}else{$d.Periods[1].Sha256}
        Check "Reader period $period reproduces every float byte" ($hash -ceq $expected)
    }
    $elapsed=$watch.Elapsed.TotalSeconds;$actualPcm=[Convert]::ToHexString($pcmDigest.GetHashAndReset())
    Check 'Combined effects mixer preserves complete 98-second music reference' ($actualPcm -ceq $expectedPcm -and $mixer.Frames -eq $ref.Frames -and $mixer.ClippedSamples -eq 0)
    Check 'Loop reader retains bounded page after four periods' ($reader.Loaded.Length -le 50400 -and $reader.Frame -eq 4*$d.PeriodFrames)
    Close-DoomMusicLoopReader $reader;Check 'Loop reader closes all playback files' $reader.Closed
    $details=@{ReadHashAndPartialPcmSeconds=$elapsed;MaximumBlockMilliseconds=$maximum;Frames=$reader.Frame;PeriodHashes=$periodHashes.ToArray();ReferencePcmSha256=$actualPcm;DiskBytesRead=$reader.DiskBytesRead}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($reader){Close-DoomMusicLoopReader $reader};if($digest){$digest.Dispose()};if($pcmDigest){$pcmDigest.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();Details=$details;QualificationSha256=(Get-FileHash $Qualification).Hash;ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Sources=@('MusicLoopReader','AudioMixer'|ForEach-Object {@{Path="src/$_.ps1";Sha256=(Get-FileHash "$root/src/$_.ps1").Hash}});
      Meaning='Real pinned E1M1 state/output qualification plus four periods of bounded cached reads, exact full float comparison and canonical first-98-second PCM through the combined effects mixer. Unpaced offline timing; fourth period is justified by normalized state recurrence, not a separately synthesized fourth reference. No device/host qualification.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) loop evidence checks."
