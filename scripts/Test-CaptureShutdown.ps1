#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Ffmpeg,[Parameter(Mandatory)][string]$MediaFfmpeg,
    [Parameter(Mandatory)][string]$OutputPrefix,[Parameter(Mandatory)][string]$Output,
    [ValidateRange(2,40)][int]$Runs=12,[switch]$RequireModulePin)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$prefix=[IO.Path]::GetFullPath($OutputPrefix)
if(@(Get-ChildItem ($prefix+'*') -ErrorAction SilentlyContinue).Count){throw 'Use a fresh media prefix.'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($prefix))
. "$PSScriptRoot/WindowCaptureTargets.ps1"
$runtime=(Get-Process -Id $PID).Path;$wt=(Get-Command wt.exe).Source
$rows=[Collections.Generic.List[object]]::new();$failure=$null
$binaryHash=(Get-FileHash $Ffmpeg).Hash
try{
    for($i=0;$i -lt $Runs;$i++){
        $runPrefix=$prefix+'-'+$i.ToString('D2');$title='pwshDoom-capture-'+[Guid]::NewGuid().ToString('N')
        $before=@(Get-DoomTerminalWindows|ForEach-Object {$_.MainWindowHandle.ToInt64()})
        $target=$null;$recorder=$null;$stderrTask=$null;$stdoutTask=$null;$runFailure=$null;$code=$null;$decodeCode=$null;$forced=$false;$log='';$closed=$false
        $mode=if(($i%2) -eq 0){'RecorderQuit'}else{'WindowClose'}
        $captureSeconds=2+($i%3)*0.5
        $arguments=@()
        try{
            & $wt -w new --size 100,30 new-tab -p pwshDoom --title $title $runtime -NoProfile -File "$PSScriptRoot/Invoke-CaptureTestWindow.ps1" -Prefix $runPrefix -Title $title
            if($LASTEXITCODE){throw 'Test window launch failed.'}
            $watch=[Diagnostics.Stopwatch]::StartNew()
            do{
                $matches=@(Get-DoomTerminalWindows|Where-Object {$_.MainWindowHandle.ToInt64() -notin $before -and $_.MainWindowTitle -eq $title})
                if($matches.Count -gt 1){throw 'Ambiguous test window.'}
                if($matches.Count -eq 1){$target=$matches[0]}
                if($watch.Elapsed.TotalSeconds -gt 15){throw 'Owned test window not found.'}
                Start-Sleep -Milliseconds 50
            }while(-not $target -or -not (Test-Path ($runPrefix+'-ready.json')))
            $arguments=@('-hide_banner','-n','-filter_complex',('gfxcapture=hwnd='+$target.MainWindowHandle.ToInt64()+':max_framerate=120:capture_cursor=0:display_border=1:width=-2:height=-2'),
                '-an','-c:v','h264_nvenc','-preset','p4','-cq','18','-b:v','0','-r','60','-fps_mode','cfr','-movflags','+faststart','-t','15',($runPrefix+'.mp4'))
            $info=[Diagnostics.ProcessStartInfo]::new([IO.Path]::GetFullPath($Ffmpeg));$info.UseShellExecute=$false;$info.CreateNoWindow=$true
            $info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
            foreach($arg in $arguments){$info.ArgumentList.Add($arg)}
            $recorder=[Diagnostics.Process]::Start($info);$stdoutTask=$recorder.StandardOutput.ReadToEndAsync();$stderrTask=$recorder.StandardError.ReadToEndAsync()
            Start-Sleep -Milliseconds ([int]($captureSeconds*1000))
            if($recorder.HasExited){throw 'Recorder exited before requested shutdown.'}
            if($mode -eq 'RecorderQuit'){$recorder.StandardInput.WriteLine('q');$recorder.StandardInput.Flush()}
            else{[IO.File]::WriteAllText($runPrefix+'-stop','close owned target')}
            if(-not $recorder.WaitForExit(10000)){throw 'Recorder did not finish within shutdown deadline.'}
            $code=$recorder.ExitCode;$log=$stderrTask.Result
            if($code -ne 0){throw "Recorder exit: $code"}
            if($RequireModulePin -and $log -notmatch 'PWSHDOOM_GFX_MODULE_PINNED=1'){throw 'Module-pin diagnostic absent.'}
            if($log -notmatch 'PWSHDOOM_GFX_ORIGIN_QPC100NS=\d+'){throw 'No captured frame origin.'}
            & $MediaFfmpeg -v error -i ($runPrefix+'.mp4') -f null - 2> ($runPrefix+'-decode.log')
            $decodeCode=$LASTEXITCODE
            if($decodeCode -ne 0){throw 'Complete movie decoding failed.'}
        }catch{$runFailure=$_.ToString()}
        finally{
            [IO.File]::WriteAllText($runPrefix+'-stop','finish owned target')
            if($recorder){
                if(-not $recorder.HasExited){$forced=$true;$recorder.Kill();$recorder.WaitForExit()}
                $code=$recorder.ExitCode;$log=$stderrTask.Result;$stdoutTask.Result|Set-Content ($runPrefix+'-stdout.log');$recorder.Dispose()
            }
            $log|Set-Content ($runPrefix+'-ffmpeg.log')
            if($target){
                $watch=[Diagnostics.Stopwatch]::StartNew()
                do{$closed=-not @(Get-DoomTerminalWindows|Where-Object {$_.MainWindowHandle -eq $target.MainWindowHandle -and $_.MainWindowTitle -eq $title}).Count;if(-not $closed){Start-Sleep -Milliseconds 50}}while(-not $closed -and $watch.Elapsed.TotalSeconds -lt 10)
                if(-not $closed){$runFailure="${runFailure} Owned target did not close."}
            }
            $rows.Add(@{Run=$i;Mode=$mode;CaptureSeconds=$captureSeconds;Error=$runFailure;EncoderExitCode=$code;DecoderExitCode=$decodeCode;ForcedRecorderStop=$forced;TargetClosed=$closed;
                TargetHandle=if($target){$target.MainWindowHandle.ToInt64()}else{$null};TargetTitle=$title;TargetWasPreexisting=if($target){$target.MainWindowHandle.ToInt64() -in $before}else{$null};
                ModulePinObserved=$log.Contains('PWSHDOOM_GFX_MODULE_PINNED=1');Arguments=$arguments;Video=$runPrefix+'.mp4';
                VideoSha256=if(Test-Path ($runPrefix+'.mp4')){(Get-FileHash ($runPrefix+'.mp4')).Hash}else{$null}})
        }
        if($runFailure){throw $runFailure}
    }
}catch{$failure=$_.ToString();throw}
finally{
    @{Error=$failure;RequestedRuns=$Runs;Runs=$rows.ToArray();Ffmpeg=[IO.Path]::GetFullPath($Ffmpeg);FfmpegSha256=$binaryHash;
        BinaryUnchanged=((Get-FileHash $Ffmpeg).Hash -eq $binaryHash);MediaFfmpegSha256=(Get-FileHash $MediaFfmpeg).Hash;
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;TargetScriptSha256=(Get-FileHash "$PSScriptRoot/Invoke-CaptureTestWindow.ps1").Hash;
        Meaning='Finite owned-window recorder lifecycle trial, alternating explicit recorder quit and target closure. All movies retained and fully decoded. Repeated success is bounded regression evidence, not proof that an intermittent platform fault cannot recur. No Doom gameplay or performance claim.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"Completed $($rows.Count) recorder shutdown trials."
