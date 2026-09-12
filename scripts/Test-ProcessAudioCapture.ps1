#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$dir=Join-Path "$root/local" ('capture-test-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($dir)
$runtime=(Get-Process -Id $PID).Path;$owned=[Collections.Generic.List[object]]::new();$checks=[Collections.Generic.List[object]]::new();$failure=$null;$details=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Launch([string]$Script,[string[]]$Arguments){
    $psi=[Diagnostics.ProcessStartInfo]::new($runtime);$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.WorkingDirectory=$root;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    foreach($arg in @('-NoProfile','-File',"$PSScriptRoot/$Script")+$Arguments){$psi.ArgumentList.Add($arg)}
    $p=[Diagnostics.Process]::Start($psi);$entry=@{Process=$p;Out=$p.StandardOutput.ReadToEndAsync();Err=$p.StandardError.ReadToEndAsync()};$owned.Add($entry);return $entry
}
function WaitFile([string]$Path){$w=[Diagnostics.Stopwatch]::StartNew();while(-not (Test-Path $Path)){if($w.Elapsed.TotalSeconds -gt 15){throw "Fixture did not publish $Path"};foreach($entry in $owned){if($entry.Process.HasExited -and $entry.Process.ExitCode -ne 0){throw $entry.Err.Result}};Start-Sleep -Milliseconds 10}}
function MeasureTone([int16[]]$Samples,[int]$Start,[int]$Frames,[int]$Frequency){
    $s=0.0;$c=0.0;$energy=0.0
    for($i=0;$i -lt $Frames;$i++){$v=[double]$Samples[2*($Start+$i)];$a=2*[Math]::PI*$Frequency*$i/44100;$s+=$v*[Math]::Sin($a);$c+=$v*[Math]::Cos($a);$energy+=$v*$v}
    return @{Amplitude=2*[Math]::Sqrt($s*$s+$c*$c)/$Frames;Rms=[Math]::Sqrt($energy/$Frames)}
}
try{
    $target=Launch 'Invoke-CaptureTestTone.ps1' @('-ReadyFile',"$dir/target-ready.json",'-GoFile',"$dir/go",'-Output',"$dir/target.json",'-Frequency','350','-ToneSeconds','2')
    $other=Launch 'Invoke-CaptureTestTone.ps1' @('-ReadyFile',"$dir/other-ready.json",'-GoFile',"$dir/go",'-Output',"$dir/other.json",'-Frequency','700','-ToneSeconds','6')
    WaitFile "$dir/target-ready.json";WaitFile "$dir/other-ready.json"
    $capture=Launch 'Record-ProcessAudio.ps1' @('-TargetProcessId',"$($target.Process.Id)",'-OutputPrefix',"$dir/capture",'-ReadyFile',"$dir/capture-ready.json",'-Seconds','7')
    WaitFile "$dir/capture-ready.json";[IO.File]::WriteAllText("$dir/go",'start')
    foreach($entry in $owned){if(-not $entry.Process.WaitForExit(15000)){throw 'Owned fixture timeout.'};Check 'Owned fixture process exits successfully' ($entry.Process.ExitCode -eq 0)}
    $t=Get-Content "$dir/target.json" -Raw|ConvertFrom-Json;$o=Get-Content "$dir/other.json" -Raw|ConvertFrom-Json;$r=Get-Content "$dir/capture.json" -Raw|ConvertFrom-Json
    Check 'Both fixtures complete six seconds of device buffers' (-not $t.Error -and -not $o.Error -and $t.CompletedFrames -eq 264600 -and $o.CompletedFrames -eq 264600 -and $t.Closed -and $o.Closed)
    Check 'Capture targets only the intended sibling and closes' (-not $r.Error -and $r.TargetProcessId -eq $target.Process.Id -and $r.TargetProcessId -ne $other.Process.Id -and $r.Closed)
    $wav=[IO.File]::ReadAllBytes($r.WavPath);$samples=[int16[]]::new(($wav.Length-44)/2);[Buffer]::BlockCopy($wav,44,$samples,0,$wav.Length-44)
    Check 'WAV length and header account for captured frames' ($wav.Length -eq 44+$r.Frames*4 -and [BitConverter]::ToUInt32($wav,40) -eq $r.Frames*4)
    $start100ns=$t.StartedQpc*10000000.0/$t.QpcFrequency
    $active=@($r.Packets|Where-Object {$_.Qpc100ns -ge $start100ns+5000000})[0]
    $quiet=@($r.Packets|Where-Object {$_.Qpc100ns -ge $start100ns+35000000})[0]
    $a=MeasureTone $samples ([int]$active.OutputFrame) 22050 350;$b=MeasureTone $samples ([int]$active.OutputFrame) 22050 700;$q=MeasureTone $samples ([int]$quiet.OutputFrame) 22050 700
    Check 'Selected 350 Hz source reaches the digital loopback' ($a.Amplitude -gt 20 -and $a.Rms -gt 15)
    Check 'Concurrent sibling 700 Hz tone is suppressed below one percent' ($b.Amplitude -lt $a.Amplitude*.01)
    Check 'Selected silence stays quiet while sibling continues' ($q.Rms -lt [Math]::Max(2,$a.Rms*.01))
    Check 'No timestamp-error capture packets' (@($r.Packets|Where-Object {$_.Flags -band 4}).Count -eq 0)
    $details=@{Directory=$dir;CaptureReportSha256=(Get-FileHash "$dir/capture.json").Hash;Capture=$r;Target=$t;Sibling=$o;ActivePacket=$active;QuietPacket=$quiet;SelectedTone=$a;SiblingTone=$b;QuietWindow=$q;DiscontinuityPackets=@($r.Packets|Where-Object {$_.Flags -band 1})}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    $logs=@(foreach($entry in $owned){if(-not $entry.Process.HasExited){$entry.Process.Kill();$entry.Process.WaitForExit()};@{ProcessId=$entry.Process.Id;ExitCode=$entry.Process.ExitCode;Stdout=$entry.Out.Result;Stderr=$entry.Err.Result};$entry.Process.Dispose()})
    @{Error=$failure;Checks=$checks.ToArray();Details=$details;Logs=$logs;Sources=@('src/ProcessAudioCapture.ps1','scripts/Record-ProcessAudio.ps1','scripts/Invoke-CaptureTestTone.ps1','scripts/Test-ProcessAudioCapture.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$root/$_").Hash}});Meaning='Two owned sibling processes play distinct quiet tones. Target emits 350 Hz for two seconds then silence; sibling emits 700 Hz for six. Process-tree capture must include target and suppress sibling in active and silent target intervals. Digital loopback evidence, not microphone/acoustic or game-load qualification. Concurrent soundtrack qualification workloads may affect scheduling.'}|ConvertTo-Json -Depth 10|Set-Content $Output
}
"PASS: $($checks.Count) process capture checks."
