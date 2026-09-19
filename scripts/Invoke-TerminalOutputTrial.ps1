#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][ValidateSet('Strips','Batch')][string]$Mode,
    [ValidateSet('Pairs','ColorState')][string]$AnsiEncoding='Pairs',
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Name)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");Push-Location $root
try{
    $prefix="local/recordings/$Name";$sourcesPath=$prefix+'-route-sources.json'
    foreach($path in $sourcesPath,"results/$Name-route-sources.json","results/$Name-recorded.json","results/$Name-timing.json"){
        if(Test-Path $path){throw 'Use a fresh trial name.'}
    }
    . ./src/InputReplay.ps1
    $prior=Get-Content results/e1m2-classic-lighting-second-route-sources.json -Raw|ConvertFrom-Json
    $names=@(@($prior.Sources.Path)+@('src/TerminalOutput.ps1','src/AnsiColorState.ps1','src/TerminalCodec.ps1','scripts/FrameCodec.ps1','scripts/Invoke-TerminalOutputTrial.ps1')|Sort-Object -Unique)
    @{CreatedUtc=[DateTime]::UtcNow.ToString('o');AnsiEncoding=$AnsiEncoding;TerminalOutput=$Mode;CurrentSourceFingerprint=(Get-DoomReplaySourceFingerprint);
        Sources=@($names|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash $_).Hash}})}|ConvertTo-Json -Depth 5|Set-Content $sourcesPath
    Copy-Item -LiteralPath $sourcesPath -Destination "results/$Name-route-sources.json"
    $replay='results/e1m2-qualified-declared-destination.json';$catalog='local/music-prepared-seven.json'
    ./scripts/Record-DoomReplay.ps1 -Style Classic -TerminalOutput $Mode -AnsiEncoding $AnsiEncoding -Replay $replay -OutputPrefix $prefix `
        -Ffmpeg local/tools/capture-build/FFmpeg-n9.0.1/ffmpeg.exe -MediaFfmpeg local/tools/ffmpeg/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe `
        -Seconds 180 -StartupTimeoutSeconds 180 -CaptureLimit 240 -Maximized -RecordInput -CaptureAudio -MusicCatalog $catalog -ExpectedExit ReplayEnd
    ./scripts/Test-CampaignRecording.ps1 -Prefix $prefix -Replay $replay -Catalog $catalog -StartTrack D_E1M2 -EndTrack D_E1M3 -Output "results/$Name-recorded.json"
    ./scripts/Summarize-CampaignCapture.ps1 -Prefix $prefix -Output "results/$Name-timing.json"
}finally{Pop-Location}
