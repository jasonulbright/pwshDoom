#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# Make a viewing copy from verified screen-capture footage, never from a framebuffer.
param([Parameter(Mandatory)][string]$InputPrefix,[Parameter(Mandatory)][string]$OutputFile,
    [Parameter(Mandatory)][ValidateRange(0,10000)][int]$X,
    [Parameter(Mandatory)][ValidateRange(0,10000)][int]$Y,
    [Parameter(Mandatory)][ValidateRange(2,10000)][int]$Width,
    [Parameter(Mandatory)][ValidateRange(2,10000)][int]$Height)
$ErrorActionPreference='Stop'
$prefix=[IO.Path]::GetFullPath($InputPrefix);$output=[IO.Path]::GetFullPath($OutputFile)
if(Test-Path -LiteralPath $output){throw 'Use a new output path; the original capture is retained.'}
$recording=Get-Content -LiteralPath ($prefix+'-recording.json') -Raw | ConvertFrom-Json
$game=Get-Content -LiteralPath ($prefix+'-game.json') -Raw | ConvertFrom-Json
if($recording.Error -or $recording.EncoderExitCode -ne 0 -or $game.Error -or $game.ExitReason -notin 'LevelComplete','ReplayEnd','ConfirmedQuit','Duration'){throw 'A successful game recording is required.'}
if($game.ViewportChanges.Count -ne 1 -or $game.ViewportPauseCount -ne 0){throw 'The window changed during capture; inspect it before choosing a crop.'}
if((Get-FileHash -LiteralPath $recording.Video).Hash -ne $recording.VideoSha256){throw 'Original recording hash changed.'}
function Invoke-RecordingTool {
    param([string]$Executable,[string[]]$ToolArguments)
    $info=[Diagnostics.ProcessStartInfo]::new($Executable);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in $ToolArguments){$info.ArgumentList.Add($arg)}
    $process=[Diagnostics.Process]::Start($info);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
    $process.WaitForExit();$code=$process.ExitCode;$process.Dispose()
    return @{Code=$code;Out=$stdout.Result;Err=$stderr.Result}
}
$ffmpeg=$recording.Ffmpeg;$ffprobe=Join-Path (Split-Path $ffmpeg) ffprobe.exe
$probe=Invoke-RecordingTool $ffprobe @('-v','error','-show_entries','format=duration:stream=width,height,codec_name,avg_frame_rate,nb_frames,pix_fmt','-of','json',$recording.Video)
if($probe.Code -ne 0){throw $probe.Err};$sourceInfo=$probe.Out | ConvertFrom-Json;$stream=$sourceInfo.streams[0]
if($X+$Width -gt $stream.width -or $Y+$Height -gt $stream.height -or $Width%2 -or $Height%2){throw 'Crop is outside the recording or not aligned for H.264.'}
$crop='crop={0}:{1}:{2}:{3}' -f $Width,$Height,$X,$Y
# Loading text and window chrome are outside the manually verified game crop.
# A 10 Hz contrast scan finds the visible game; keep 0.1 s before and 0.2 s after sampled activity.
$scan=Invoke-RecordingTool $ffmpeg @('-hide_banner','-nostats','-i',$recording.Video,'-an','-vf',($crop+',fps=10,signalstats,metadata=print'),'-f','null','-')
$scan.Err | Set-Content -LiteralPath ($output+'.scan.log')
if($scan.Code -ne 0){throw 'Capture contrast scan failed.'}
$times=[Collections.Generic.List[double]]::new();$time=0.0;$minimum=0.0
foreach($line in ($scan.Err -split '\r?\n')){
    if($line -match 'pts_time:([0-9.]+)'){$time=[double]::Parse($Matches[1],[Globalization.CultureInfo]::InvariantCulture)}
    elseif($line -match 'lavfi.signalstats.YMIN=([0-9.]+)'){$minimum=[double]$Matches[1]}
    elseif($line -match 'lavfi.signalstats.YMAX=([0-9.]+)'){
        if([double]$Matches[1]-$minimum -gt 40){$times.Add($time)}
    }
}
$recordedGameDuration=if($game.WallDurationSeconds){$game.WallDurationSeconds}else{$game.DurationSeconds}
$minimumSamples=[Math]::Max(5,[Math]::Min(300,[Math]::Floor($recordedGameDuration*10*.8)))
if($times.Count -lt $minimumSamples){throw 'Too few visible game/menu samples; inspect the recording/crop.'}
$start=[Math]::Max(0,$times[0]-.1);$end=[Math]::Min([double]$sourceInfo.format.duration,$times[-1]+.2);$duration=$end-$start
if([Math]::Abs($duration-$recordedGameDuration) -gt 1.0){throw 'Detected gameplay duration does not agree with the game wall-clock report; inspect before exporting.'}
$exportArguments=@('-hide_banner','-n','-ss',$start.ToString('F3',[Globalization.CultureInfo]::InvariantCulture),'-i',$recording.Video,
    '-t',$duration.ToString('F3',[Globalization.CultureInfo]::InvariantCulture),'-an','-vf',$crop,'-c:v','libx264','-threads','4','-preset','medium','-crf','16','-pix_fmt','yuv420p','-movflags','+faststart',$output)
$export=Invoke-RecordingTool $ffmpeg $exportArguments;$export.Err | Set-Content -LiteralPath ($output+'.export.log')
if($export.Code -ne 0){throw 'Viewing-copy export failed.'}
$finalProbe=Invoke-RecordingTool $ffprobe @('-v','error','-count_frames','-show_entries','format=duration:stream=width,height,codec_name,avg_frame_rate,nb_read_frames,pix_fmt','-of','json',$output)
if($finalProbe.Code -ne 0){throw 'Viewing-copy decode verification failed.'}
$finalInfo=$finalProbe.Out | ConvertFrom-Json
@{CreatedUtc=[DateTime]::UtcNow.ToString('o');OriginalVideo=$recording.Video;OriginalSha256=$recording.VideoSha256;
    Style=$recording.Style;GlyphSet=$recording.GlyphSet;Crop=@{X=$X;Y=$Y;Width=$Width;Height=$Height};
    StartSeconds=$start;EndSeconds=$end;ContrastSampleRate=10;GameDurationSeconds=$game.DurationSeconds;GameWallDurationSeconds=$recordedGameDuration;VisibleSamples=$times.Count;
    Output=$output;OutputSha256=(Get-FileHash -LiteralPath $output).Hash;VerifiedVideo=$finalInfo;Arguments=$exportArguments;
    Meaning='Viewing copy of actual window-capture footage. Removes startup/console return and fixed empty margins; no game frames are synthesized and no speed change, tint, sharpening, shader, or rescaling is applied. Re-encoded H.264 is lossy; capture may already contain repeated frames. The untrimmed original is retained.'} |
    ConvertTo-Json -Depth 7 | Set-Content -LiteralPath ($output+'.json')
$output
