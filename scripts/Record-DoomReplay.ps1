#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# External window capture. FFmpeg is not an engine, renderer, or game dependency.
param([ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Matrix',
    [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Katakana',
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay="$PSScriptRoot/../results/e1m1-route.json",
    [string]$OutputPrefix="$PSScriptRoot/../local/recordings/matrix-katakana",
    [string]$Ffmpeg,[ValidateRange(1,90)][int]$Seconds=90,
    [ValidateRange(60,240)][int]$CaptureLimit=240,
    [ValidateRange(4,24)][int]$FontSize=12,[string]$FontFace,[switch]$Maximized)
$ErrorActionPreference='Stop'
if(-not $Ffmpeg){
    $found=@(Get-ChildItem "$PSScriptRoot/../local/tools/ffmpeg" -Recurse -Filter ffmpeg.exe -File -ErrorAction SilentlyContinue)
    if($found.Count -ne 1){throw 'Pass -Ffmpeg with the path to a local FFmpeg build supporting gfxcapture and h264_nvenc.'}
    $Ffmpeg=$found[0].FullName
}
if(-not $FontFace){$FontFace=if($Style -ne 'Classic' -and $GlyphSet -eq 'Katakana'){'MS Gothic'}else{'Cascadia Mono'}}
if($Style -eq 'Classic' -and -not $PSBoundParameters.ContainsKey('FontSize')){$FontSize=6}
if(@(Get-Process WindowsTerminal -ErrorAction SilentlyContinue).Count){throw 'This capture requires an isolated Terminal process. Existing Terminal windows were left untouched.'}
$prefix=[IO.Path]::GetFullPath($OutputPrefix);$gamePath=$prefix+'-game.json';$videoPath=$prefix+'.mp4'
foreach($path in @($gamePath,$videoPath,$prefix+'-recording.json')){if(Test-Path -LiteralPath $path){throw 'Choose a fresh output prefix; recordings are never overwritten.'}}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($prefix))
$recorder=$null;$target=$null;$failure=$null;$captureQpc=$null;$exitCode=$null;$stderr='';$game=$null
try {
    & "$PSScriptRoot/../Start-Doom.ps1" -Wad $Wad -Replay $Replay -Style $Style -GlyphSet $GlyphSet -Seconds $Seconds -FontSize $FontSize -FontFace $FontFace -Maximized:$Maximized -ExitDelaySeconds 3 -Report $gamePath
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($null -eq $target){
        $candidates=@(Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -eq 'pwshDoom'})
        if($candidates.Count -gt 1){throw 'Ambiguous capture window.'}
        if($candidates.Count -eq 1){$target=$candidates[0];break}
        if($watch.Elapsed.TotalSeconds -gt 20){throw 'No target game window appeared.'}
        Start-Sleep -Milliseconds 100
    }
    $captureInput='gfxcapture=hwnd='+$target.MainWindowHandle.ToInt64()+":max_framerate=$($CaptureLimit):capture_cursor=0:display_border=1:width=-2:height=-2"
    $arguments=@('-hide_banner','-n','-filter_complex',$captureInput,
        '-an','-c:v','h264_nvenc','-preset','p4','-cq','18','-b:v','0',
        '-r','60','-fps_mode','cfr','-movflags','+faststart','-t',"$($Seconds+35)",$videoPath)
    $info=[Diagnostics.ProcessStartInfo]::new($Ffmpeg);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in $arguments){$info.ArgumentList.Add($arg)}
    $captureQpc=[Diagnostics.Stopwatch]::GetTimestamp();$recorder=[Diagnostics.Process]::Start($info)
    $stdoutTask=$recorder.StandardOutput.ReadToEndAsync();$stderrTask=$recorder.StandardError.ReadToEndAsync()
    $watch.Restart()
    while(-not (Test-Path -LiteralPath $gamePath)){
        if($recorder.HasExited){throw 'Window capture exited before the game report; inspect the capture log.'}
        if($watch.Elapsed.TotalSeconds -gt $Seconds+35){throw 'Game report did not arrive before the capture deadline.'}
        Start-Sleep -Milliseconds 100
    }
    $game=Get-Content -LiteralPath $gamePath -Raw | ConvertFrom-Json
    if($game.Error){throw "Game failed: $($game.Error)"}
    if($Seconds -eq 90 -and $game.ExitReason -ne 'LevelComplete'){throw 'The full replay did not complete the level.'}
}catch{$failure=$_.ToString();throw}
finally {
    if($null -ne $recorder){
        if(-not $recorder.HasExited){$recorder.StandardInput.WriteLine('q');$recorder.StandardInput.Flush();if(-not $recorder.WaitForExit(10000)){$recorder.Kill();$recorder.WaitForExit()}}
        $stderr=$stderrTask.Result;$exitCode=$recorder.ExitCode;$recorder.Dispose()
    }
    $stderr | Set-Content -LiteralPath ($prefix+'-ffmpeg.log')
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Style=$Style;GlyphSet=$GlyphSet;FontFace=$FontFace;FontSize=$FontSize;Maximized=[bool]$Maximized;CaptureLimit=$CaptureLimit;VideoFps=60;
        TerminalPid=if($null -ne $target){$target.Id}else{$null};WindowHandle=if($null -ne $target){$target.MainWindowHandle.ToInt64()}else{$null};
        CaptureStartQpc=$captureQpc;QpcFrequency=[Diagnostics.Stopwatch]::Frequency;EncoderExitCode=$exitCode;
        Ffmpeg=$Ffmpeg;FfmpegSha256=(Get-FileHash -LiteralPath $Ffmpeg).Hash;Arguments=$arguments;
        Video=$videoPath;VideoSha256=if(Test-Path -LiteralPath $videoPath){(Get-FileHash -LiteralPath $videoPath).Hash}else{$null};GameReport=$gamePath;
        Meaning='Actual game-window Windows.Graphics.Capture at the recorded capture ceiling, with D3D11 frames passed to external NVENC H.264 encoding. The ceiling exceeds 60 to avoid capture-rate aliasing; actual arrival rate is compositor-driven. Output is resampled to 60 FPS and can contain duplicates. Video includes startup and a short console return. Recording can affect game/presentation timing; encoded 60 FPS does not prove 60 distinct displayed game images. No microphone, desktop audio, or other windows are captured.'} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath ($prefix+'-recording.json')
}
if($exitCode -ne 0){throw 'FFmpeg exited unsuccessfully; inspect the retained recording/log.'}
$videoPath
