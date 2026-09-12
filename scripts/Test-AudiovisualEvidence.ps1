#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh evidence report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$ffmpeg="$root/local/tools/ffmpeg/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe";$probe=Join-Path ([IO.Path]::GetDirectoryName($ffmpeg)) 'ffprobe.exe'
$checks=[Collections.Generic.List[object]]::new();$receipts=[Collections.Generic.List[object]]::new();$runs=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Read-Receipt([string]$Path){$full=Join-Path $root $Path;$receipts.Add(@{Path=$Path;Sha256=(Get-FileHash $full).Hash});return Get-Content $full -Raw|ConvertFrom-Json}
function BytesHash([byte[]]$Bytes){return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))}
function Preserve([string]$Source,[string]$Name){$destination="$root/results/$Name.json";if(-not (Test-Path $destination)){Copy-Item -LiteralPath $Source -Destination $destination};Check 'Portable raw receipt is byte-identical to local original' ((Get-FileHash $Source).Hash -ceq (Get-FileHash $destination).Hash)}
try{
    foreach($case in @(@('results/capture-timeline-unit-first.json',13),@('results/process-audio-capture-clock.json',10),@('results/music-e1m2-reader-first.json',6))){$r=Read-Receipt $case[0];Check 'Relevant current targeted checks pass' (-not $r.Error -and $r.Checks.Count -eq $case[1] -and @($r.Checks|Where-Object {-not $_.Passed}).Count -eq 0);foreach($s in $r.Sources){Check "Targeted source is current: $($s.Path)" ($s.Sha256 -ceq (Get-FileHash "$root/$($s.Path)").Hash)}}
    $build=Read-Receipt 'results/capture-recorder-recipe-first.json';Check 'Documented recorder recipe completed on fresh source tree' (-not $build.Error -and $build.RecipeSha256 -ceq (Get-FileHash "$root/scripts/Build-CaptureFfmpeg.ps1").Hash -and $build.BinarySha256 -ceq (Get-FileHash $build.Binary).Hash)
    foreach($case in @(@('Matrix','music-matrix-wgc-first','music-matrix-wgc-merged','music-matrix-wgc-play'),@('AnsiArt','music-color-wgc-first','music-color-wgc-first-av','music-color-wgc-play'),@('Classic','music-classic-wgc-first','music-classic-wgc-first-av','music-classic-wgc-play'))){
        $name=$case[0];$prefix="$root/local/recordings/$($case[1])";$mergePrefix="$root/local/recordings/$($case[2])";$clip="$root/local/recordings/$($case[3]).mp4"
        $g=Read-Receipt "local/recordings/$($case[1])-game.json";$capture=Read-Receipt "local/recordings/$($case[1])-recording.json";$audio=Read-Receipt "local/recordings/$($case[1])-audio.json";$m=Read-Receipt "local/recordings/$($case[2]).json"
        if($name -eq 'Matrix'){Check 'Matrix post-processing failure remains explicit before successful recovery' ($capture.Error -match "property 'Sum'")}
        else{Check "$name recorder reports delivered audiovisual output without source drift" (-not $capture.Error -and $capture.AudioCaptured -and $capture.SourcesChangedDuringRun.Count -eq 0);foreach($s in $capture.Sources){Check "$name capture source current: $($s.Path)" ($s.Sha256 -ceq (Get-FileHash "$root/$($s.Path)").Hash)}}
        Check "$name game and actual audio device close with all tics/frames" (-not $g.Error -and $g.ExitReason -ceq 'Duration' -and $g.SimulationTics -eq 279 -and -not $g.Simulation.Audio.Error -and -not $g.Simulation.Audio.CleanupError -and $g.Simulation.Audio.DeviceClosed -and $g.Simulation.Audio.SubmittedFrames -eq 351540 -and $g.Simulation.Audio.ReturnedCompletedFrames -eq 351540)
        Check "$name capture targets a newly created game window" (-not $capture.TargetWasPreexisting -and $capture.EncoderExitCode -eq 0 -and $capture.AudioExitCode -eq 0)
        $ready=Get-Content ($prefix+'-host-ready.json') -Raw|ConvertFrom-Json
        Check "$name audio captures the owned simulation PID" ($audio.TargetProcessId -eq $ready.SimulationPid -and $ready.CaptureGate -and -not $audio.Error -and $audio.Closed)
        Check "$name runtime recorder binary is retained unchanged" ($capture.FfmpegSha256 -ceq (Get-FileHash $capture.Ffmpeg).Hash)
        $match=[regex]::Match([IO.File]::ReadAllText($prefix+'-ffmpeg.log'),'PWSHDOOM_GFX_ORIGIN_QPC100NS=(\d+)')
        Check "$name original WGC QPC is the audio placement origin" ($match.Success -and [decimal]$match.Groups[1].Value -eq [decimal]$m.Clock.OriginQpc100ns -and $m.CaptureBackend -ceq 'GraphicsCapture')
        Check "$name merge preserves complete compressed video and packet clocks" (-not $m.Error -and $m.Validation.VideoFramesPreserved -and $m.Validation.VideoPacketTimestampsPreserved -and $m.VideoSha256 -ceq (Get-FileHash $m.Video).Hash)
        $raw=[IO.File]::ReadAllBytes($audio.WavPath);$placed=[IO.File]::ReadAllBytes($m.TimelineWav)
        Check "$name raw and placed PCM files match recorded hashes" ((BytesHash $raw) -ceq $audio.WavSha256 -and (BytesHash $placed) -ceq $m.TimelineWavSha256)
        $expected=[byte[]]::new($placed.Length-44);$copied=0L;$end=0L
        foreach($p in $audio.Packets){
            [long]$destination=[decimal]::Floor(([decimal]$p.Qpc100ns-[decimal]$m.Clock.OriginQpc100ns)*44100/10000000+[decimal]0.5)
            $skip=[Math]::Max(0,-$destination);$destination=[Math]::Max(0,$destination);$count=[Math]::Min($p.Frames-$skip,$expected.Length/4-$destination)
            if($count -gt 0){if($destination -lt $end){throw 'Live fixture contains timestamp overlap requiring separate audit.'};[Buffer]::BlockCopy($raw,[int](44+4*($p.OutputFrame+$skip)),$expected,[int](4*$destination),[int](4*$count));$copied+=$count;$end=$destination+$count}
        }
        $actual=[byte[]]::new($placed.Length-44);[Buffer]::BlockCopy($placed,44,$actual,0,$actual.Length)
        Check "$name entire placed PCM equals independent QPC-derived sample mapping" ((BytesHash $actual) -ceq (BytesHash $expected) -and $copied -eq $m.Timeline.CopiedFrames)
        $gameFirst=($g.FrameStats[0].EndQpc*10000000.0/$g.QpcFrequency-[double]$m.Clock.OriginQpc100ns)/10000000
        $gameLast=($g.FrameStats[-1].EndQpc*10000000.0/$g.QpcFrequency-[double]$m.Clock.OriginQpc100ns)/10000000
        $gapsDuringGame=@($m.Timeline.ZeroFilledIntervals|Where-Object {$_.Frame/44100.0 -lt $gameLast -and ($_.Frame+$_.Frames)/44100.0 -gt $gameFirst})
        Check "$name explicit zero-filled gaps stay outside observed gameplay interval" ($gapsDuringGame.Count -eq 0)
        $nonzero=0;for($sample=[int]($gameFirst*44100);$sample -lt [int]($gameLast*44100);$sample++){if([BitConverter]::ToInt16($actual,4*$sample) -ne 0){$nonzero++}}
        Check "$name observed gameplay has captured nonzero PCM" ($nonzero -gt 44100)
        & $ffmpeg -v error -i $m.Video -f null -;Check "$name full movie decodes audio and video" ($LASTEXITCODE -eq 0)
        & $ffmpeg -v error -i $clip -f null -;Check "$name six-second viewing copy decodes" ($LASTEXITCODE -eq 0)
        $clipInfo=(& $probe -v error -show_streams -of json $clip|Out-String)|ConvertFrom-Json
        Check "$name viewing copy contains picture and audio streams" ($LASTEXITCODE -eq 0 -and @($clipInfo.streams|Where-Object codec_type -eq video).Count -eq 1 -and @($clipInfo.streams|Where-Object codec_type -eq audio).Count -eq 1)
        foreach($pair in @(@(($prefix+'-game.json'),"av-$name-game"),@(($prefix+'-recording.json'),"av-$name-capture"),@(($prefix+'-audio.json'),"av-$name-audio"),@(($mergePrefix+'.json'),"av-$name-merge"))){Preserve $pair[0] $pair[1]}
        $runs.Add(@{Style=$name;FullMovie=$m.Video;FullMovieSha256=$m.VideoSha256;ViewingCopy=$clip;ViewingCopySha256=(Get-FileHash $clip).Hash;ViewingCopyStreams=$clipInfo.streams;ObservedGameFirstSeconds=$gameFirst;ObservedGameLastSeconds=$gameLast;ConsoleWrites=$g.CompletedFrames;SimulationTics=$g.SimulationTics;MaximumAudioMixMilliseconds=($g.Simulation.Audio.MixSamplesMs|Measure-Object -Maximum).Maximum;TimelinePcmSha256=(BytesHash $actual);ZeroFilledIntervals=$m.Timeline.ZeroFilledIntervals;NonzeroGameplayFrames=$nonzero})
    }
    $bad=Read-Receipt 'local/recordings/music-matrix-av-black-rejected.json';Check 'Known black GDI footage is rejected automatically' ($bad.Error -match 'over 99 percent black')
    Preserve "$root/local/recordings/music-matrix-av-black-rejected.json" 'av-gdi-black-rejected'
    Preserve "$root/local/recordings/music-matrix-av-verified.json" 'av-container-duration-rejected'
    Preserve "$root/local/recordings/music-matrix-wgc-first-av.json" 'av-empty-black-list-failure'
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Receipts=$receipts.ToArray();Runs=$runs.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Three actual eight-second WGC/music/effects game recordings, original QPC origin, independent entire PCM timestamp placement, video packet-preservation checks and complete media decode. Sampled visual review is separately documented. Recorded workloads overlap synthesis and are not clean performance trials, acoustic measurements or campaign completion.'}|ConvertTo-Json -Depth 10|Set-Content $Output
}
"PASS: $($checks.Count) audiovisual evidence checks."
