#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2",
    [ValidatePattern('^D_[A-Z0-9]+$')][string]$Track='D_E1M1',[string]$ReferenceReport='results/music-e1m1-dry-numeric-loop.json')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$names='MusScore','SoundFontBank','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','MusicGroup','MusicLoopState'
$sources=@($names|ForEach-Object {[ordered]@{Path="src/$_.ps1";Sha256=(Get-FileHash "$root/src/$_.ps1").Hash}})
foreach($name in $names){. "$root/src/$name.ps1"}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$root/local/music-loop-$PID.ps1";. $bundle
$archive=$null;$file=$null;$digest=$null;$failure=$null;$details=$null
try{
    $archive=[Wad]::new([string[]]@($Wad));$score=ConvertFrom-DoomMus ($archive.ReadLump($archive.GetLumpNumber($Track))) -Name $Track
    $bank=ConvertTo-DoomSoundFontRegions (ConvertFrom-DoomSoundFont ([IO.File]::ReadAllBytes($SoundFont)))
    [long]$cycleFrames=$score.DurationTicks*315;[int]$cyclesPerPeriod=1
    while(($cycleFrames*$cyclesPerPeriod)%1260 -ne 0){$cyclesPerPeriod++}
    [long]$periodFrames=$cycleFrames*$cyclesPerPeriod
    if($periodFrames -le 0 -or $periodFrames*3 -gt 158760000){throw 'Three aligned periods exceed this finite 3600-second qualification bound.'}
    $reference=Get-Content $ReferenceReport -Raw|ConvertFrom-Json;$ref=$reference.Details
    if($reference.Error -or $ref.MusSha256 -cne $score.SourceSha256 -or $ref.SoundFontSha256 -cne $bank.SourceSha256 -or $ref.Frames -gt 3*$periodFrames -or (Get-FileHash $ref.WavPath).Hash -cne $ref.WavSha256){throw 'Reference assets, duration or bytes differ.'}
    $refBytes=[IO.File]::ReadAllBytes($ref.WavPath)
    if($refBytes.Length -ne 44+$ref.Frames*4 -or [Text.Encoding]::ASCII.GetString($refBytes,36,4) -cne 'data'){throw 'Expected canonical reference WAV.'}
    $refPcm=[byte[]]::new($refBytes.Length-44);[Buffer]::BlockCopy($refBytes,44,$refPcm,0,$refPcm.Length)
    $expected=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($refPcm))
    $digest=[Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256);$pcmState=@{Volume=$ref.Volume;ClippedSamples=0L}
    $dir=Join-Path "$root/local" ('music-loop-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($dir)
    $g=New-DoomMusicGroup $bank $score ([int[]](0..15)) ([int]($periodFrames*3))
    $snapshots=[Collections.Generic.List[object]]::new();$periods=[Collections.Generic.List[object]]::new();$snapshots.Add((Get-DoomMusicLoopSnapshot $g))
    $watch=[Diagnostics.Stopwatch]::StartNew();$chunks=0;$referenceFrames=0
    for($period=0;$period -lt 3;$period++){
        $path=Join-Path $dir "period-$period.f64";$file=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        while($g.Synth.Frame -lt ($period+1)*$periodFrames){
            $blocks=[int][Math]::Min(20,(($period+1)*$periodFrames-$g.Synth.Frame)/1260)
            $chunk=Read-DoomMusicGroup $g $blocks;$bytes=[byte[]]::new($chunk.Mix.Length*8);[Buffer]::BlockCopy($chunk.Mix,0,$bytes,0,$bytes.Length);$file.Write($bytes)
            if($referenceFrames -lt $ref.Frames){
                $count=[int][Math]::Min($chunk.Frames,$ref.Frames-$referenceFrames);$part=[double[]]::new($count*2);[Array]::Copy($chunk.Mix,$part,$part.Length)
                $pcm=ConvertTo-DoomMusicPcm $pcmState $part;$pcmBytes=[byte[]]::new($pcm.Length*2);[Buffer]::BlockCopy($pcm,0,$pcmBytes,0,$pcmBytes.Length);$digest.AppendData($pcmBytes);$referenceFrames+=$count
            }
            $chunks++;if($chunks%20 -eq 0){"Rendered $([Math]::Round($g.Synth.Frame/44100.0,2))/$($periodFrames*3/44100.0) seconds."}
        }
        $file.Flush($true);$file.Dispose();$file=$null
        $periods.Add(@{Index=$period;Path=$path;Frames=$periodFrames;Bytes=(Get-Item $path).Length;Sha256=(Get-FileHash $path).Hash})
        $snapshots.Add((Get-DoomMusicLoopSnapshot $g));"Period $period complete; voices $($g.Synth.Voices.Count); state $($snapshots[-1].StateSha256)."
    }
    $elapsed=$watch.Elapsed.TotalSeconds;$actual=[Convert]::ToHexString($digest.GetHashAndReset())
    $stateMatch=$snapshots[1].StateSha256 -ceq $snapshots[2].StateSha256 -and $snapshots[2].StateSha256 -ceq $snapshots[3].StateSha256
    $outputMatch=$periods[1].Sha256 -ceq $periods[2].Sha256
    $drift=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash (Join-Path $root $_.Path)).Hash})
    $details=@{Track=$Track;BankSha256=$bank.SourceSha256;MusSha256=$score.SourceSha256;CycleFrames=$cycleFrames;CyclesPerPeriod=$cyclesPerPeriod;PeriodFrames=$periodFrames;RenderedFrames=$g.Synth.Frame;RenderWriteAndSnapshotSeconds=$elapsed;
        Snapshots=$snapshots.ToArray();Periods=$periods.ToArray();NormalizedStateRepeats=$stateMatch;NextPeriodFloatOutputRepeats=$outputMatch;
        Reference=@{Frames=$referenceFrames;ExpectedPcmSha256=$expected;ActualPcmSha256=$actual;Exact=($expected -ceq $actual);ReportSha256=(Get-FileHash $ReferenceReport).Hash};
        Qualified=($stateMatch -and $outputMatch -and $expected -ceq $actual -and $drift.Count -eq 0);LoopStartFrame=$periodFrames;LoopFrames=$periodFrames;SourcesChangedDuringRun=$drift;PowerShell=$PSVersionTable.PSVersion.ToString()}
    if($expected -cne $actual){throw 'Continuous loop qualification changed reference PCM.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($file){$file.Dispose()};if($digest){$digest.Dispose()};if($archive){$archive.Dispose()}
    @{Error=$failure;Details=$details;Sources=$sources;ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Three continuously synthesized aligned periods. Candidate loops the second only when its start/end and following end normalized states match, the full following float output matches, canonical reference PCM is retained and sources stay fixed. Restricted to this pinned dry single-group model/assets/runtime, not other synthesizers or full SF2 fidelity. No playback device or host integration.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"Completed loop qualification; qualified: $($details.Qualified)."
