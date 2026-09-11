#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,[string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/SoundFontBank.ps1";. "$PSScriptRoot/../src/SoundFontRegions.ps1";. "$PSScriptRoot/../src/MusicOscillator.ps1"
$trials=[Collections.Generic.List[object]]::new();$failure=$null;$bank=$null
try{
    $bank=ConvertTo-DoomSoundFontRegions (ConvertFrom-DoomSoundFont ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($SoundFont))))
    $region=(Find-DoomSoundFontRegions $bank -Program 30 -Key 60 -Velocity 100)[0]
    if($region.LoopMode -notin 1,3){throw 'Expected a sustaining guitar region.'}
    foreach($count in 1,8,16){
        $voices=@(for($i=0;$i -lt $count;$i++){New-DoomMusicOscillator $bank $region})
        $times=[Collections.Generic.List[double]]::new();$digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)
        try{
            for($block=0;$block -lt 50;$block++){
                $watch=[Diagnostics.Stopwatch]::StartNew();$outputs=@(foreach($voice in $voices){,(Read-DoomMusicOscillator $voice 1260)});$ms=$watch.Elapsed.TotalMilliseconds
                if($block -ge 10){$times.Add($ms)}
                foreach($pcm in $outputs){$bytes=[byte[]]::new($pcm.Length*8);[Buffer]::BlockCopy($pcm,0,$bytes,0,$bytes.Length);$digest.AppendData($bytes)}
            }
            $sorted=@($times|Sort-Object);$trials.Add(@{Voices=$count;FramesPerBlock=1260;Rate=44100;WarmupBlocks=10;TimedBlocks=40;Milliseconds=$times.ToArray();
                MeanMilliseconds=($times|Measure-Object -Average).Average;P95Milliseconds=$sorted[37];MaximumMilliseconds=$sorted[-1];BlocksOverDuration=@($times|Where-Object {$_ -gt 1260/44100.0*1000}).Count;
                OutputFloat64Sha256=[Convert]::ToHexString($digest.GetHashAndReset())})
        }finally{$digest.Dispose()}
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Trials=$trials.ToArray();SoundFontSha256=if($bank){$bank.SourceSha256}else{$null};Program=30;Key=60;Velocity=100;
      Sources=@('src/SoundFontBank.ps1','src/SoundFontRegions.ps1','src/MusicOscillator.ps1','scripts/Measure-MusicOscillator.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});
      Meaning='Isolated sequential real-bank oscillator cost including output-array collection; excludes bank loading, hashing, envelopes, filters, mixing, devices, gameplay and rendering. Not a full synthesizer deadline benchmark.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($trials.Count) bounded oscillator cost trials."
