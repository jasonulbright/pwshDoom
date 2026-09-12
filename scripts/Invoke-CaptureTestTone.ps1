#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# Quiet, finite owned-process fixture for capture isolation; no game assets.
param([Parameter(Mandatory)][string]$ReadyFile,[Parameter(Mandatory)][string]$GoFile,
    [Parameter(Mandatory)][string]$Output,[ValidateSet(350,700)][int]$Frequency=350,[ValidateRange(1,6)][int]$ToneSeconds=2)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. "$PSScriptRoot/../src/WaveOutDevice.ps1"
$device=$null;$failure=$null;$started=0L
try{
    $samples=[int16[]]::new(2520)
    for($i=0;$i -lt 1260;$i++){$v=[int16][Math]::Round(1000*[Math]::Sin(2*[Math]::PI*$Frequency*$i/44100));$samples[2*$i]=$v;$samples[2*$i+1]=$v}
    $tone=[byte[]]::new(5040);[Buffer]::BlockCopy($samples,0,$tone,0,5040);$silence=[byte[]]::new(5040)
    $device=Open-DoomWaveOut -BufferFrames 1260 -Buffers 4
    @{ProcessId=$PID;Frequency=$Frequency}|ConvertTo-Json|Set-Content $ReadyFile
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while(-not (Test-Path $GoFile)){if($watch.Elapsed.TotalSeconds -gt 20){throw 'Fixture gate timeout.'};Start-Sleep -Milliseconds 5}
    $started=[Diagnostics.Stopwatch]::GetTimestamp();$block=0
    while($block -lt 210){
        Update-DoomWaveOutBuffers $device
        foreach($slot in $device.Buffers){
            if(-not $slot.Queued -and $block -lt 210){$pcm=if($block -lt $ToneSeconds*35){$tone}else{$silence};Submit-DoomWaveOut $device $slot $pcm;$block++}
        }
        if($device.SubmittedFrames -eq 5040){Set-DoomWaveOutPaused $device $false}
        $null=$device.Event.WaitOne(2);$null=$device.Event.Reset()
    }
    $drain=[Diagnostics.Stopwatch]::StartNew()
    do{Update-DoomWaveOutBuffers $device;if($drain.Elapsed.TotalSeconds -gt 2){throw 'Fixture drain timeout.'};Start-Sleep -Milliseconds 2}while(@($device.Buffers|Where-Object Queued).Count)
}catch{$failure=$_.ToString();throw}finally{
    if($device){Close-DoomWaveOut $device}
    @{Error=$failure;ProcessId=$PID;Frequency=$Frequency;ToneSeconds=$ToneSeconds;StartedQpc=$started;QpcFrequency=[Diagnostics.Stopwatch]::Frequency;SubmittedFrames=if($device){$device.SubmittedFrames}else{0};CompletedFrames=if($device){$device.CompletedFrames}else{0};Closed=if($device){$device.Closed}else{$true}}|ConvertTo-Json|Set-Content $Output
}
