#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Video,[Parameter(Mandatory)][string]$VideoLog,[Parameter(Mandatory)][string]$AudioReport,
    [Parameter(Mandatory)][string]$ClockReport,[Parameter(Mandatory)][string]$OutputPrefix,[Parameter(Mandatory)][string]$Ffmpeg,
    [ValidateSet('Gdi','GraphicsCapture')][string]$CaptureBackend='Gdi')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. "$PSScriptRoot/../src/CaptureClock.ps1";. "$PSScriptRoot/../src/CaptureTimeline.ps1"
$prefix=[IO.Path]::GetFullPath($OutputPrefix);$outVideo=$prefix+'.mp4';$outWav=$prefix+'.wav';$outReport=$prefix+'.json'
foreach($path in $outVideo,$outWav,$outReport){if(Test-Path $path){throw 'Use fresh merge output paths.'}}
$failure=$null;$plan=$null;$clock=$null;$origin=$null;$videoInfo=$null;$muxCode=$null;$validation=$null;$blackIntervals=@()
try{
    $lines=[IO.File]::ReadAllText($VideoLog)
    if($CaptureBackend -eq 'GraphicsCapture'){
        $matches=[regex]::Matches($lines,'PWSHDOOM_GFX_ORIGIN_QPC100NS=(\d+)')
        if($matches.Count -ne 1){throw 'Exactly one original WGC timestamp from the diagnostic recorder build is required.'}
        [decimal]$origin=$matches[0].Groups[1].Value
    }else{
        $matches=[regex]::Matches($lines,'demuxer ->[^\r\n]*?pkt_pts:(\d+)')
        if($matches.Count -eq 0){throw 'No original GDI demux packet timestamps were retained.'}
        [decimal]$origin=$matches[0].Groups[1].Value
        if($origin -lt 1000000000000000 -or $origin -gt 10000000000000000){throw 'Expected GDI Unix microsecond packet clock.'}
    }
    $probe=Join-Path ([IO.Path]::GetDirectoryName($Ffmpeg)) 'ffprobe.exe'
    $videoInfo=(& $probe -v error -select_streams v:0 -show_streams -of json $Video|Out-String)|ConvertFrom-Json
    if($LASTEXITCODE -ne 0 -or $videoInfo.streams.Count -ne 1){throw 'Cannot inspect silent video stream.'}
    $v=$videoInfo.streams[0]
    if([double]$v.start_time -ne 0 -or $v.avg_frame_rate -cne '60/1'){throw 'Expected zero-origin 60 FPS video for timeline placement.'}
    & $Ffmpeg -hide_banner -i $Video -vf 'blackdetect=d=0.1:pix_th=0.001:pic_th=0.999' -an -f null - 2> ($prefix+'-blackdetect.log')
    if($LASTEXITCODE -ne 0){throw 'Video decode/black-frame verification failed.'}
    $blackIntervals=@([regex]::Matches([IO.File]::ReadAllText($prefix+'-blackdetect.log'),'black_start:([\d.]+) black_end:([\d.]+) black_duration:([\d.]+)')|ForEach-Object {@{Start=[double]::Parse($_.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture);End=[double]::Parse($_.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture);Seconds=[double]::Parse($_.Groups[3].Value,[Globalization.CultureInfo]::InvariantCulture)}})
    $blackSeconds=0.0;foreach($interval in $blackIntervals){$blackSeconds+=$interval.Seconds}
    if($blackSeconds -gt [double]$v.duration*.99){throw 'Captured video is over 99 percent black; audiovisual gameplay capture is rejected.'}
    $r=Get-Content $AudioReport -Raw|ConvertFrom-Json
    $parentClock=Get-Content $ClockReport -Raw|ConvertFrom-Json
    $anchors=@(@($parentClock.Anchors)+@($r.ClockAnchors)|Sort-Object QpcBefore)
    if($CaptureBackend -eq 'GraphicsCapture'){
        $clock=@{OriginQpc100ns=$origin;Meaning='Original first Windows Graphics Capture SystemRelativeTime, retained by the diagnostic FFmpeg build before its normal first-frame subtraction. Same 100 ns QPC domain as WASAPI packet timestamps; no wall-clock origin estimate.'}
    }else{$clock=ConvertTo-DoomCaptureQpcOrigin $anchors $origin}
    [int]$frames=[Math]::Round([decimal]$v.duration*44100,0,[MidpointRounding]::AwayFromZero)
    $plan=New-DoomCaptureTimelinePlan $r $clock.OriginQpc100ns $frames
    if($plan.CopiedFrames -lt 44100){throw 'Less than one second of actual captured audio overlaps the movie.'}
    Write-DoomCaptureTimeline $r $plan $outWav
    $args=@('-hide_banner','-n','-i',$Video,'-i',$outWav,'-map','0:v:0','-map','1:a:0','-c:v','copy','-c:a','aac','-b:a','192k','-movflags','+faststart',$outVideo)
    & $Ffmpeg @args 2> ($prefix+'-ffmpeg.log');$muxCode=$LASTEXITCODE
    if($muxCode -ne 0){throw 'Audio/video mux failed.'}
    $mergedInfo=(& $probe -v error -show_streams -of json $outVideo|Out-String)|ConvertFrom-Json
    if($LASTEXITCODE -ne 0){throw 'Cannot inspect merged movie.'}
    $mergedVideo=@($mergedInfo.streams|Where-Object codec_type -eq video);$mergedAudio=@($mergedInfo.streams|Where-Object codec_type -eq audio)
    if($mergedVideo.Count -ne 1 -or $mergedAudio.Count -ne 1 -or $mergedVideo[0].nb_frames -ne $v.nb_frames -or $mergedVideo[0].start_time -ne $v.start_time -or $mergedVideo[0].time_base -ne $v.time_base){throw 'Mux changed video frame accounting or time base.'}
    $originalPacketClocks=(& $probe -v error -select_streams v:0 -show_packets -show_entries packet=pts,dts -of csv=p=0 $Video|Out-String);if($LASTEXITCODE -ne 0){throw 'Original video packet timestamps cannot be read.'}
    $mergedPacketClocks=(& $probe -v error -select_streams v:0 -show_packets -show_entries packet=pts,dts -of csv=p=0 $outVideo|Out-String);if($LASTEXITCODE -ne 0 -or $mergedPacketClocks -cne $originalPacketClocks){throw 'Mux changed video packet PTS/DTS.'}
    $originalVideoDigest=(& $Ffmpeg -v error -i $Video -map 0:v:0 -c copy -f hash -hash sha256 -|Out-String).Trim();if($LASTEXITCODE -ne 0){throw 'Original compressed-video hash failed.'}
    $mergedVideoDigest=(& $Ffmpeg -v error -i $outVideo -map 0:v:0 -c copy -f hash -hash sha256 -|Out-String).Trim();if($LASTEXITCODE -ne 0 -or $mergedVideoDigest -cne $originalVideoDigest){throw 'Mux changed compressed video bytes.'}
    $validation=@{VideoFramesPreserved=$true;VideoPacketTimestampsPreserved=$true;CompressedVideoHash=$mergedVideoDigest;
        VideoPacketClockSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($originalPacketClocks)));
        OriginalContainerVideoDuration=$v.duration;MergedContainerVideoDuration=$mergedVideo[0].duration;AudioStream=$mergedAudio[0];VideoStream=$mergedVideo[0]}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Video=$outVideo;VideoSha256=if(Test-Path $outVideo){(Get-FileHash $outVideo).Hash}else{$null};TimelineWav=$outWav;TimelineWavSha256=if(Test-Path $outWav){(Get-FileHash $outWav).Hash}else{$null};
        OriginalVideoSha256=(Get-FileHash $Video).Hash;VideoLogSha256=(Get-FileHash $VideoLog).Hash;AudioReportSha256=(Get-FileHash $AudioReport).Hash;ClockReportSha256=(Get-FileHash $ClockReport).Hash;
        CaptureBackend=$CaptureBackend;OriginalVideoTimestamp=$origin;Clock=$clock;Timeline=$plan;VideoInfo=$videoInfo;MuxExitCode=$muxCode;Validation=$validation;BlackIntervals=$blackIntervals;
        Sources=@('src/CaptureClock.ps1','src/CaptureTimeline.ps1','scripts/Merge-DoomCaptureAudio.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});
        Meaning='Video original timestamp aligned to scoped digital PCM: WGC uses retained 100 ns QPC directly; GDI uses bracketed UTC/QPC anchors. Packet gaps are explicitly zero-filled and raw inputs retained. AAC is an external recording codec. All video packet bytes and PTS/DTS are checked, with container final-duration metadata differences retained. Visual quality and physical A/V latency require separate review.'}|ConvertTo-Json -Depth 9|Set-Content $outReport
}
$outVideo
