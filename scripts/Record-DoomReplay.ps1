#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# External window capture. FFmpeg is not an engine, renderer, or game dependency.
param([ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Matrix',
    [ValidateSet('Strips','Batch')][string]$TerminalOutput='Strips',
    [ValidateSet('Pairs','ColorState')][string]$AnsiEncoding='Pairs',
    [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Katakana',
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay="$PSScriptRoot/../results/e1m1-route.json",
    [string]$OutputPrefix="$PSScriptRoot/../local/recordings/matrix-katakana",
    [string]$Ffmpeg,[string]$MediaFfmpeg,[ValidateRange(1,600)][int]$Seconds=90,
    [ValidateRange(15,180)][int]$StartupTimeoutSeconds=60,
    [ValidateRange(60,240)][int]$CaptureLimit=240,
    [ValidateSet('GraphicsCapture','Gdi')][string]$CaptureBackend='GraphicsCapture',
    [ValidateRange(4,24)][int]$FontSize=12,[string]$FontFace,[switch]$Maximized,
    [string]$SessionSchedule,[switch]$RecordInput,[switch]$Sound,[switch]$CaptureAudio,[string]$MusicCatalog,[string]$SaveRoot,[string]$SettingsPath,[ValidateRange(3,30)][int]$ExitDelaySeconds=3,[ValidateSet('ReplayEnd','LevelComplete','ConfirmedQuit','Duration')][string]$ExpectedExit)
$ErrorActionPreference='Stop'
if($MusicCatalog){$Sound=$true}
if($CaptureAudio){
    $Sound=$true
    . "$PSScriptRoot/../src/CaptureClock.ps1"
}
$replayInfo=Get-Content -LiteralPath $Replay -Raw | ConvertFrom-Json
$expectedEnding=if($ExpectedExit){$ExpectedExit}elseif($replayInfo.ContinueCampaign){'ReplayEnd'}else{'LevelComplete'}
if(-not $Ffmpeg){
    if($CaptureAudio -and $CaptureBackend -eq 'GraphicsCapture'){
        throw 'Pass -Ffmpeg pointing to the diagnostic WGC recorder build that retains its original QPC timestamp.'
    }
    $found=@(Get-ChildItem "$PSScriptRoot/../local/tools/ffmpeg" -Recurse -Filter ffmpeg.exe -File -ErrorAction SilentlyContinue)
    if($found.Count -ne 1){throw 'Pass -Ffmpeg with the path to a local FFmpeg build supporting gfxcapture and h264_nvenc.'}
    $Ffmpeg=$found[0].FullName
}
if(-not $MediaFfmpeg){
    $mediaCandidates=@(Get-ChildItem "$PSScriptRoot/../local/tools/ffmpeg" -Recurse -Filter ffmpeg.exe -File -ErrorAction SilentlyContinue)
    $MediaFfmpeg=if($mediaCandidates.Count -eq 1){$mediaCandidates[0].FullName}else{$Ffmpeg}
}
if(-not $FontFace){$FontFace=if($Style -ne 'Classic' -and $GlyphSet -eq 'Katakana'){'MS Gothic'}else{'Cascadia Mono'}}
if($Style -eq 'Classic' -and -not $PSBoundParameters.ContainsKey('FontSize')){$FontSize=6}
. "$PSScriptRoot/WindowCaptureTargets.ps1"
$existingHandles=@(Get-DoomTerminalWindows|ForEach-Object {$_.MainWindowHandle.ToInt64()})
$prefix=[IO.Path]::GetFullPath($OutputPrefix);$gamePath=$prefix+'-game.json';$videoPath=$prefix+'.mp4'
$hostReady=$prefix+'-host-ready.json';$captureStart=$prefix+'-capture-start';$audioReady=$prefix+'-audio-ready.json';$audioStop=$prefix+'-audio-stop';$audioPrefix=$prefix+'-audio';$clockPath=$prefix+'-clock.json'
if($CaptureAudio){foreach($path in $hostReady,$captureStart,$audioReady,$audioStop,($audioPrefix+'.wav'),($audioPrefix+'.json'),$clockPath,($prefix+'-av.mp4'),($prefix+'-av.wav'),($prefix+'-av.json')){if(Test-Path $path){throw 'Choose a fresh audiovisual output prefix.'}}}
foreach($path in @($gamePath,$videoPath,$prefix+'-recording.json')){if(Test-Path -LiteralPath $path){throw 'Choose a fresh output prefix; recordings are never overwritten.'}}
if($RecordInput -and (Test-Path -LiteralPath ($prefix+'-input.json'))){throw 'Input recording already exists.'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($prefix))
$recorder=$null;$target=$null;$failure=$null;$captureQpc=$null;$exitCode=$null;$stderr='';$game=$null
$audioRecorder=$null;$audioExitCode=$null;$audioStdout=$null;$audioStderr=$null;$clockAnchors=[Collections.Generic.List[object]]::new()
$sourceNames=@('Start-Doom.ps1','scripts/Invoke-Doom.ps1','scripts/Record-DoomReplay.ps1','scripts/Record-ProcessAudio.ps1','scripts/Merge-DoomCaptureAudio.ps1','src/ProcessAudioCapture.ps1','src/CaptureClock.ps1','src/CaptureTimeline.ps1','src/TerminalOutput.ps1')
$sourceNames+=@('src/AnsiColorState.ps1','src/TerminalCodec.ps1','scripts/FrameCodec.ps1')
$sourceSnapshot=@($sourceNames|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}})
try {
    $launch=@{Wad=$Wad;Replay=$Replay;Style=$Style;GlyphSet=$GlyphSet;Seconds=$Seconds;FontSize=$FontSize;FontFace=$FontFace;Maximized=$Maximized;ExitDelaySeconds=$ExitDelaySeconds;Report=$gamePath}
    $launch.TerminalOutput=$TerminalOutput
    $launch.AnsiEncoding=$AnsiEncoding
    if($SessionSchedule){$launch.SessionSchedule=$SessionSchedule}
    if($SaveRoot){$launch.SaveRoot=$SaveRoot}
    if($SettingsPath){$launch.SettingsPath=$SettingsPath}
    if($RecordInput){$launch.RecordInput=$prefix+'-input.json'}
    if($Sound){$launch.Sound=$true}
    if($MusicCatalog){$launch.MusicCatalog=$MusicCatalog}
    if($CaptureAudio){$launch.ReadyFile=$hostReady;$launch.CaptureStartFile=$captureStart}
    & "$PSScriptRoot/../Start-Doom.ps1" @launch
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($null -eq $target){
        $candidates=@(Get-DoomTerminalWindows | Where-Object {$_.MainWindowHandle.ToInt64() -notin $existingHandles -and $_.MainWindowTitle -eq 'pwshDoom'})
        if($candidates.Count -gt 1){throw 'Ambiguous capture window.'}
        if($candidates.Count -eq 1){$target=$candidates[0];break}
        if($watch.Elapsed.TotalSeconds -gt 20){throw 'No target game window appeared.'}
        Start-Sleep -Milliseconds 100
    }
    if($CaptureBackend -eq 'Gdi'){
        # Capture only the observed game window. GDI samples at 60 Hz; it is a
        # separate workload from compositor-driven Graphics Capture.
        $captureArguments=@('-f','gdigrab','-framerate','60','-draw_mouse','0','-i',('hwnd='+$target.MainWindowHandle.ToInt64()),'-pix_fmt','yuv420p')
        $captureMeaning='Actual game-window GDI capture sampled at 60 Hz and passed to external NVENC H.264 encoding. CaptureLimit does not apply to this backend.'
    }else{
        $captureInput='gfxcapture=hwnd='+$target.MainWindowHandle.ToInt64()+":max_framerate=$($CaptureLimit):capture_cursor=0:display_border=1:width=-2:height=-2"
        $captureArguments=@('-filter_complex',$captureInput)
        $captureMeaning='Actual game-window Windows.Graphics.Capture at the recorded capture ceiling, with D3D11 frames passed to external NVENC H.264 encoding. The ceiling exceeds 60 to avoid capture-rate aliasing; actual arrival rate is compositor-driven.'
    }
    $clockArgs=if($CaptureAudio -and $CaptureBackend -eq 'Gdi'){@('-debug_ts')}else{@()}
    $filterArgs=if($CaptureAudio -and $CaptureBackend -eq 'Gdi'){@('-vf','setpts=PTS-STARTPTS')}else{@()}
    $arguments=@('-hide_banner','-n')+$clockArgs+$captureArguments+$filterArgs+@(
        '-an','-c:v','h264_nvenc','-preset','p4','-cq','18','-b:v','0',
        '-r','60','-fps_mode','cfr','-movflags','+faststart','-t',"$($Seconds+$StartupTimeoutSeconds+15)",$videoPath)
    $info=[Diagnostics.ProcessStartInfo]::new($Ffmpeg);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($arg in $arguments){$info.ArgumentList.Add($arg)}
    if($CaptureAudio){$clockAnchors.Add((Get-DoomCaptureClockAnchor))}
    $captureQpc=[Diagnostics.Stopwatch]::GetTimestamp();$recorder=[Diagnostics.Process]::Start($info)
    $stdoutTask=$recorder.StandardOutput.ReadToEndAsync();$stderrTask=$recorder.StandardError.ReadToEndAsync()
    $watch.Restart()
    if($CaptureAudio){
        while(-not (Test-Path $hostReady)){
            if($recorder.HasExited -or (Test-Path $gamePath) -or $watch.Elapsed.TotalSeconds -gt $StartupTimeoutSeconds){throw 'Game did not reach the capture startup gate.'}
            Start-Sleep -Milliseconds 20
        }
        $hostInfo=Get-Content $hostReady -Raw|ConvertFrom-Json
        if(-not $hostInfo.CaptureGate){throw 'Game readiness did not establish the capture gate.'}
        $audioInfo=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path);$audioInfo.UseShellExecute=$false;$audioInfo.CreateNoWindow=$true;$audioInfo.RedirectStandardOutput=$true;$audioInfo.RedirectStandardError=$true
        foreach($arg in @('-NoProfile','-File',"$PSScriptRoot/Record-ProcessAudio.ps1",'-TargetProcessId',"$($hostInfo.SimulationPid)",'-OutputPrefix',$audioPrefix,'-Seconds',"$($Seconds+35)",'-ReadyFile',$audioReady,'-StopFile',$audioStop)){$audioInfo.ArgumentList.Add($arg)}
        $audioRecorder=[Diagnostics.Process]::Start($audioInfo);$audioStdout=$audioRecorder.StandardOutput.ReadToEndAsync();$audioStderr=$audioRecorder.StandardError.ReadToEndAsync()
        $audioWait=[Diagnostics.Stopwatch]::StartNew()
        while(-not (Test-Path $audioReady)){
            if($audioRecorder.HasExited -or $recorder.HasExited -or $audioWait.Elapsed.TotalSeconds -gt 15){throw 'Scoped audio capture did not initialize before the game gate deadline.'}
            Start-Sleep -Milliseconds 10
        }
        [IO.File]::WriteAllText($captureStart,'recorders ready')
    }
    while(-not (Test-Path -LiteralPath $gamePath)){
        if($recorder.HasExited){throw 'Window capture exited before the game report; inspect the capture log.'}
        if($audioRecorder -and $audioRecorder.HasExited){throw 'Scoped audio capture exited before the game report.'}
        if($watch.Elapsed.TotalSeconds -gt $Seconds+$StartupTimeoutSeconds+15){throw 'Game report did not arrive before the capture deadline.'}
        Start-Sleep -Milliseconds 100
    }
    $game=Get-Content -LiteralPath $gamePath -Raw | ConvertFrom-Json
    if($game.Error -or $game.InputRecordingError){throw "Game/recording failed: $($game.Error) $($game.InputRecordingError)"}
    if(($Seconds -eq 90 -or $ExpectedExit) -and $game.ExitReason -ne $expectedEnding){throw "The replay did not reach its expected ending: $expectedEnding."}
    if(($Seconds -eq 90 -or $ExpectedExit -eq 'ReplayEnd') -and $replayInfo.ContinueCampaign){
        if($game.SimulationTics -ne $replayInfo.InputCommands.Count){throw 'The recorded session did not consume every replay command.'}
        $expectedTransitions=@($replayInfo.Transitions | Select-Object -Skip 1)
        $actualTransitions=@($game.Simulation.Transitions | Select-Object -Skip 1)
        if($actualTransitions.Count -ne $expectedTransitions.Count){throw 'Recorded session transition count differs from the qualified route.'}
        for($i=0;$i -lt $expectedTransitions.Count;$i++){
            foreach($field in 'Tic','State','Episode','Map'){
                if($actualTransitions[$i].$field -ne $expectedTransitions[$i].$field){throw "Recorded session transition $i differs in $field."}
            }
        }
        $last=$game.Simulation.Transitions[-1]
        if(-not @($game.FrameStats|Where-Object {$_.Generation -eq $last.Generation -and $_.State -eq 0}).Count){throw 'The destination world was not rendered.'}
    }
}catch{$failure=$_.ToString();throw}
finally {
    if($null -ne $recorder){
        if(-not $recorder.HasExited){$recorder.StandardInput.WriteLine('q');$recorder.StandardInput.Flush();if(-not $recorder.WaitForExit(10000)){$recorder.Kill();$recorder.WaitForExit()}}
        $stderr=$stderrTask.Result;$exitCode=$recorder.ExitCode;$recorder.Dispose()
    }
    if($null -ne $exitCode -and $exitCode -ne 0 -and -not $failure){$failure="FFmpeg exited with code $exitCode."}
    if($CaptureAudio){
        $clockAnchors.Add((Get-DoomCaptureClockAnchor));@{Anchors=$clockAnchors.ToArray()}|ConvertTo-Json -Depth 5|Set-Content $clockPath
        if($audioRecorder){
            [IO.File]::WriteAllText($audioStop,'game finished')
            if(-not $audioRecorder.WaitForExit(12000)){$audioRecorder.Kill();$audioRecorder.WaitForExit();$failure="${failure} Audio recorder failed to stop within its deadline."}
            $audioExitCode=$audioRecorder.ExitCode;$audioStdout.Result|Set-Content ($audioPrefix+'-stdout.log');$audioStderr.Result|Set-Content ($audioPrefix+'-stderr.log');$audioRecorder.Dispose()
            if($audioExitCode -ne 0){$failure="${failure} Audio recorder exited with code $audioExitCode."}
        }
    }
    $stderr | Set-Content -LiteralPath ($prefix+'-ffmpeg.log')
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Style=$Style;GlyphSet=$GlyphSet;FontFace=$FontFace;FontSize=$FontSize;Maximized=[bool]$Maximized;CaptureBackend=$CaptureBackend;CaptureLimit=if($CaptureBackend -eq 'GraphicsCapture'){$CaptureLimit}else{$null};VideoFps=60;ExpectedExit=$expectedEnding;ReplaySha256=(Get-FileHash -LiteralPath $Replay).Hash;StartupTimeoutSeconds=$StartupTimeoutSeconds;CaptureDeadlineSeconds=$Seconds+$StartupTimeoutSeconds+15;
        AnsiEncoding=$AnsiEncoding;TerminalOutput=$TerminalOutput;Sources=$sourceSnapshot;SourcesChangedDuringRun=@($sourceSnapshot|Where-Object {$_.Sha256 -cne (Get-FileHash "$PSScriptRoot/../$($_.Path)").Hash});SoundRequested=[bool]$Sound;MusicCatalogSha256=if($MusicCatalog){(Get-FileHash $MusicCatalog).Hash}else{$null};AudioCaptured=$false;AudioCaptureRequested=[bool]$CaptureAudio;AudioExitCode=$audioExitCode;
        AudioReport=if($CaptureAudio){$audioPrefix+'.json'}else{$null};ClockReport=if($CaptureAudio){$clockPath}else{$null};
        SessionScheduleSha256=if($SessionSchedule){(Get-FileHash -LiteralPath $SessionSchedule).Hash}else{$null};SaveRoot=$SaveRoot;ExitDelaySeconds=$ExitDelaySeconds;InputReplaySha256=if($RecordInput -and (Test-Path -LiteralPath ($prefix+'-input.json'))){(Get-FileHash -LiteralPath ($prefix+'-input.json')).Hash}else{$null};
        TerminalPid=if($null -ne $target){$target.Id}else{$null};WindowHandle=if($null -ne $target){$target.MainWindowHandle.ToInt64()}else{$null};
        PreexistingTerminalWindows=$existingHandles.Count;TargetWasPreexisting=if($target){$target.MainWindowHandle.ToInt64() -in $existingHandles}else{$null};
        CaptureStartQpc=$captureQpc;QpcFrequency=[Diagnostics.Stopwatch]::Frequency;EncoderExitCode=$exitCode;
        Ffmpeg=$Ffmpeg;FfmpegSha256=(Get-FileHash -LiteralPath $Ffmpeg).Hash;MediaFfmpeg=$MediaFfmpeg;MediaFfmpegSha256=(Get-FileHash -LiteralPath $MediaFfmpeg).Hash;Arguments=$arguments;
        Video=$videoPath;VideoSha256=if(Test-Path -LiteralPath $videoPath){(Get-FileHash -LiteralPath $videoPath).Hash}else{$null};GameReport=$gamePath;
        Meaning=$captureMeaning+' Output is resampled to 60 FPS and can contain duplicates. Video includes startup and a short console return. Recording can affect game/presentation timing; encoded 60 FPS does not prove 60 distinct displayed game images. No microphone or desktop audio is captured. The input selects only the game window; inspect footage for occlusion or capture artifacts.'} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath ($prefix+'-recording.json')
}
if($exitCode -ne 0){throw 'FFmpeg exited unsuccessfully; inspect the retained recording/log.'}
if($failure){throw $failure}
if($CaptureAudio){
    try{
        $combined=& "$PSScriptRoot/Merge-DoomCaptureAudio.ps1" -Video $videoPath -VideoLog ($prefix+'-ffmpeg.log') -AudioReport ($audioPrefix+'.json') -ClockReport $clockPath -OutputPrefix ($prefix+'-av') -Ffmpeg $MediaFfmpeg -CaptureBackend $CaptureBackend
        $metadata=Get-Content ($prefix+'-recording.json') -Raw|ConvertFrom-Json -AsHashtable
        $metadata.RawSilentVideo=$videoPath;$metadata.RawSilentVideoSha256=$metadata.VideoSha256;$metadata.Video=$combined;$metadata.VideoSha256=(Get-FileHash $combined).Hash;$metadata.AudioCaptured=$true;$metadata.AudioVideoReport=$prefix+'-av.json'
        $metadata.Meaning=$metadata.Meaning.Replace('No microphone or desktop audio is captured.','No microphone or unrelated application audio is captured.')
        $metadata.Meaning+=' Delivered movie includes scoped digital audio aligned by the retained capture timestamp and QPC clock model, with explicit zero-filled intervals in its audio/video report. Original silent video and raw captured PCM remain retained. This does not qualify acoustic output or physical A/V latency.'
        $metadata|ConvertTo-Json -Depth 7|Set-Content ($prefix+'-recording.json')
        $videoPath=$combined
    }catch{
        $metadata=Get-Content ($prefix+'-recording.json') -Raw|ConvertFrom-Json -AsHashtable;$metadata.Error="Audio/video merge failed: $_";$metadata|ConvertTo-Json -Depth 7|Set-Content ($prefix+'-recording.json');throw
    }
}
$videoPath
