#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/AudioMixer.ps1"
$results=[Collections.Generic.List[object]]::new();$failure=$null
try{
    # Deterministic synthetic source: kept active throughout each finite trial.
    $samples=[single[]]::new(44100)
    for($i=0;$i -lt $samples.Length;$i++){$samples[$i]=(($i%64)-32)*256}
    $clip=@{Rate=11025;Samples=$samples;Name='synthetic saw'}
    foreach($voices in 0,1,5,16){
        $mixer=New-DoomAudioMixer 44100
        for($v=0;$v -lt $voices;$v++){$null=Add-DoomAudioVoice $mixer $clip -Source ($v+1) -Left .03 -Right .025}
        $times=[Collections.Generic.List[double]]::new();$digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
        try{
            for($block=0;$block -lt 90;$block++){
                $watch=[Diagnostics.Stopwatch]::StartNew();$pcm=Read-DoomAudioFrames $mixer 1260;$watch.Stop()
                if($block -ge 10){$times.Add($watch.Elapsed.TotalMilliseconds)}
                $bytes=[byte[]]::new($pcm.Length*2);[Buffer]::BlockCopy($pcm,0,$bytes,0,$bytes.Length);$digest.AppendData($bytes)
            }
            $sorted=@($times.ToArray()|Sort-Object);$sum=0.0;foreach($value in $sorted){$sum+=$value}
            $results.Add(@{Voices=$voices;SampleCount=$times.Count;WarmupBlocks=10;FramesPerBlock=1260;Rate=44100;MeanMs=$sum/$times.Count;MedianMs=$sorted[40];P95Ms=$sorted[75];MaxMs=$sorted[-1];BlocksOverAudioDuration=@($sorted|Where-Object {$_ -gt 1000/35}).Count;PcmSha256=[Convert]::ToHexString($digest.GetHashAndReset());RemainingVoices=$mixer.Voices.Count;ClippedSamples=$mixer.ClippedSamples})
        }finally{$digest.Dispose()}
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[datetime]::UtcNow.ToString('o');Error=$failure;Cases=$results.ToArray();Sources=@('src/AudioMixer.ps1','scripts/Measure-AudioMixer.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Finite synthetic isolated mixer cost; ten warmup blocks then eighty timed blocks per voice count. Hashing and sample generation excluded. No renderer/device load or live scheduling qualification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
$results|Select-Object Voices,MeanMs,P95Ms,MaxMs,BlocksOverAudioDuration|Format-Table
