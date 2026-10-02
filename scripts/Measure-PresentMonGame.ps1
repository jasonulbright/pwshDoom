#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# PresentMon is external measurement software; it is not a game dependency.
param([string]$OutputPrefix="$PSScriptRoot/../results/presentmon-e1m1",
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay="$PSScriptRoot/../results/e1m1-route.json",
    [ValidateRange(4,24)][int]$FontSize=6,[switch]$Maximized,
    [ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic',
    [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Katakana',[string]$FontFace,
    [ValidateRange(1,32)][int]$Workers=16,[ValidateRange(1,3600)][int]$Seconds=90,
    [switch]$Sound,[string]$MusicCatalog,[string]$SaveRoot,[string]$SettingsPath,[string]$SessionSchedule,
    [ValidateSet('Strips','Batch','AsyncBatch')][string]$TerminalOutput='Strips',
    [ValidateSet('Pairs','ColorState','Ansi256')][string]$AnsiEncoding='Pairs')
$ErrorActionPreference='Stop'
if($Style -ne 'Classic' -and -not $PSBoundParameters.ContainsKey('FontSize')){$FontSize=12}
if(-not $FontFace){$FontFace=if($Style -ne 'Classic' -and $GlyphSet -eq 'Katakana'){'MS Gothic'}else{'Cascadia Mono'}}
. "$PSScriptRoot/PresentMonApi.ps1"
Initialize-PresentMonApi
$session=[IntPtr]::Zero;$query=[IntPtr]::Zero;$target=$null;$tracking=$false;$failure=$null
$rows=[Collections.Generic.List[object]]::new();$fields=[Collections.Generic.List[object]]::new()
$processSamples=[Collections.Generic.List[object]]::new();$ownedProcesses=@{};$lastProcessSample=-1000
$sourceRoot=[IO.Path]::GetFullPath("$PSScriptRoot/..")
$sourceLines=@(Get-ChildItem "$sourceRoot/src" -Recurse -File -Filter *.ps1|Sort-Object FullName|ForEach-Object {
    [IO.Path]::GetRelativePath($sourceRoot,$_.FullName).Replace('\','/')+' '+(Get-FileHash -LiteralPath $_.FullName).Hash
})
$runtimeSourceSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($sourceLines -join "`n")))
$launchSources=@(foreach($name in 'Start-Doom.ps1','scripts/Invoke-Doom.ps1','scripts/Invoke-SimulationWorker.ps1','scripts/Invoke-GameRenderWorker.ps1','scripts/Invoke-RenderWorkerWithLogs.ps1','scripts/Invoke-AudioWorker.ps1'){
    @{Path=$name;Sha256=(Get-FileHash -LiteralPath "$sourceRoot/$name").Hash}
})
$runtimeExecutable=(Get-Process -Id $PID).Path;$launchQpc=$null
$prefix=[IO.Path]::GetFullPath($OutputPrefix);$reportPath=$prefix+'-game.json'
$readyPath=$prefix+'-ready.json'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($prefix))
foreach($path in $reportPath,$readyPath,($prefix+'-capture.json'),($prefix+'-frames.csv')){
    if(Test-Path -LiteralPath $path){throw 'Choose a fresh output prefix to preserve the earlier capture.'}
}
$before=@(Get-Process WindowsTerminal -ErrorAction SilentlyContinue)
if($before.Count -ne 0){throw 'A Terminal process is already running. This experiment requires an isolated new Terminal process for unambiguous attribution.'}
$beforeQpc=[Diagnostics.Stopwatch]::GetTimestamp();$stopQpc=$null;$reason='Error';[uint32]$blobSize=0
try {
    Assert-PresentMonStatus ([PwshDoomMeasurement.PresentMonApi]::pmOpenSession([ref]$session)) 'open session'
    $metadata=Get-PresentMonMetricMetadata $session
    $spec=@(
        @('SwapChain','PM_METRIC_SWAP_CHAIN_ADDRESS'),@('CpuStartQpc','PM_METRIC_CPU_START_QPC'),
        @('PresentStartQpc','PM_METRIC_PRESENT_START_QPC'),@('CpuFrameMs','PM_METRIC_CPU_FRAME_TIME'),
        @('CpuBusyMs','PM_METRIC_CPU_BUSY'),@('CpuWaitMs','PM_METRIC_CPU_WAIT'),
        @('GpuTimeMs','PM_METRIC_GPU_TIME'),@('GpuBusyMs','PM_METRIC_GPU_BUSY'),
        @('Dropped','PM_METRIC_DROPPED_FRAMES'),@('DisplayedMs','PM_METRIC_DISPLAYED_TIME'),
        @('BetweenPresentsMs','PM_METRIC_BETWEEN_PRESENTS'),@('BetweenDisplayChangesMs','PM_METRIC_BETWEEN_DISPLAY_CHANGE'),
        @('UntilDisplayedMs','PM_METRIC_UNTIL_DISPLAYED'),@('DisplayLatencyMs','PM_METRIC_DISPLAY_LATENCY'),
        @('PresentMode','PM_METRIC_PRESENT_MODE'),@('PresentRuntime','PM_METRIC_PRESENT_RUNTIME'),
        @('SyncInterval','PM_METRIC_SYNC_INTERVAL'),@('AllowsTearing','PM_METRIC_ALLOWS_TEARING'),
        @('FrameType','PM_METRIC_FRAME_TYPE'))
    $elements=[PwshDoomMeasurement.QueryElement[]]::new($spec.Count)
    if([Runtime.InteropServices.Marshal]::SizeOf([type][PwshDoomMeasurement.QueryElement]) -ne 32){throw 'Query ABI layout mismatch.'}
    for($i=0;$i -lt $spec.Count;$i++) {
        $m=$metadata[$spec[$i][1]];if($null -eq $m -or $m.MetricType -notin 2,3){throw "Metric is not frame-query compatible: $($spec[$i][1])"}
        $element=[PwshDoomMeasurement.QueryElement]::new();$element.Metric=$m.Id;$elements[$i]=$element
    }
    Assert-PresentMonStatus ([PwshDoomMeasurement.PresentMonApi]::pmRegisterFrameQuery($session,[ref]$query,$elements,[uint64]$elements.Length,[ref]$blobSize)) 'register frame query'
    for($i=0;$i -lt $spec.Count;$i++) {
        $m=$metadata[$spec[$i][1]];$size=switch($m.FrameType){0{8}1{4}2{4}3{4}5{8}6{1}default{throw 'Unsupported field type.'}}
        if($elements[$i].DataSize -ne $size -or $elements[$i].DataOffset+$size -gt $blobSize){throw 'Returned field ABI/size mismatch.'}
        $fields.Add(@{Name=$spec[$i][0];Metric=$spec[$i][1];Id=$m.Id;Type=$m.FrameType;Unit=$m.Unit;Offset=$elements[$i].DataOffset;Size=$size})
    }
    $launch=@{Wad=$Wad;Replay=$Replay;Seconds=$Seconds;Report=$reportPath;FontSize=$FontSize;Maximized=$Maximized;Style=$Style;GlyphSet=$GlyphSet;FontFace=$FontFace;Workers=$Workers;Sound=$Sound;ReadyFile=$readyPath;TerminalOutput=$TerminalOutput;AnsiEncoding=$AnsiEncoding}
    foreach($name in 'MusicCatalog','SaveRoot','SettingsPath','SessionSchedule'){
        $value=Get-Variable -Name $name -ValueOnly;if($value){$launch[$name]=$value}
    }
    $launchQpc=[Diagnostics.Stopwatch]::GetTimestamp()
    & "$PSScriptRoot/../Start-Doom.ps1" @launch
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($null -eq $target) {
        $found=@(Get-Process WindowsTerminal -ErrorAction SilentlyContinue)
        if($found.Count -gt 1){throw 'More than one new Terminal process; attribution is ambiguous.'}
        if($found.Count -eq 1){$target=$found[0];break}
        if($watch.Elapsed.TotalSeconds -gt 20){throw 'No new Terminal process appeared.'}
        [Threading.Thread]::Sleep(100)
    }
    Assert-PresentMonStatus ([PwshDoomMeasurement.PresentMonApi]::pmStartTrackingProcess($session,[uint32]$target.Id)) 'track Terminal'
    $tracking=$true;$watch.Restart();$completedAt=$null;$buffer=[byte[]]::new($blobSize*1024)
    while($watch.Elapsed.TotalSeconds -lt $Seconds+90) {
        [uint32]$count=1024
        Assert-PresentMonStatus ([PwshDoomMeasurement.PresentMonApi]::pmConsumeFrames($query,[uint32]$target.Id,$buffer,[ref]$count)) 'consume frames'
        for($i=0;$i -lt $count;$i++) {
            $row=[ordered]@{ProcessId=$target.Id}
            foreach($field in $fields){$row[$field.Name]=Read-PresentMonField $buffer ([int]($i*$blobSize+$field.Offset)) $field.Type}
            $rows.Add([pscustomobject]$row)
        }
        if($ownedProcesses.Count -eq 0 -and (Test-Path -LiteralPath $readyPath)){
            $ids=Get-Content -LiteralPath $readyPath -Raw|ConvertFrom-Json
            foreach($entry in @(@{Id=$target.Id;Role='Terminal'},@{Id=$ids.HostPid;Role='Host'},@{Id=$ids.SimulationPid;Role='Simulation'})+@($ids.WorkerPids|ForEach-Object {@{Id=$_;Role='Renderer'}})){
                $p=[Diagnostics.Process]::GetProcessById($entry.Id)
                $ownedProcesses[$entry.Id]=@{Process=$p;Role=$entry.Role;StartUtc=$p.StartTime.ToUniversalTime()}
            }
        }
        if($watch.Elapsed.TotalMilliseconds-$lastProcessSample -ge 1000){
            $lastProcessSample=$watch.Elapsed.TotalMilliseconds
            foreach($entry in $ownedProcesses.Values){
                $p=$entry.Process
                try{$p.Refresh();if(-not $p.HasExited){$processSamples.Add(@{Qpc=[Diagnostics.Stopwatch]::GetTimestamp();Pid=$p.Id;Role=$entry.Role;StartUtc=$entry.StartUtc.ToString('o');CpuMilliseconds=$p.TotalProcessorTime.TotalMilliseconds;WorkingSetBytes=$p.WorkingSet64;PrivateBytes=$p.PrivateMemorySize64})}}catch{if(-not $p.HasExited){throw}}
            }
        }
        if($null -eq $completedAt -and (Test-Path -LiteralPath $reportPath)){$completedAt=$watch.Elapsed.TotalSeconds}
        if($null -ne $completedAt -and $watch.Elapsed.TotalSeconds-$completedAt -gt 3){$reason='GameReportAndDrain';break}
        [Threading.Thread]::Sleep(100)
    }
    if($reason -ne 'GameReportAndDrain'){throw 'Capture timed out before the game report was drained.'}
} catch {$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}
finally {
    $stopQpc=[Diagnostics.Stopwatch]::GetTimestamp()
    if($query -ne [IntPtr]::Zero){$null=[PwshDoomMeasurement.PresentMonApi]::pmFreeFrameQuery($query)}
    if($tracking){$null=[PwshDoomMeasurement.PresentMonApi]::pmStopTrackingProcess($session,[uint32]$target.Id)}
    if($session -ne [IntPtr]::Zero){$null=[PwshDoomMeasurement.PresentMonApi]::pmCloseSession($session)}
    foreach($entry in $ownedProcesses.Values){$entry.Process.Dispose()}
    $rows.ToArray() | Export-Csv -LiteralPath ($prefix+'-frames.csv') -NoTypeInformation
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;ExitReason=$reason;FrameRows=$rows.Count;
        TerminalPid=if($null -ne $target){$target.Id}else{$null};Fields=$fields.ToArray();BlobSize=$blobSize;
        CaptureBeforeQpc=$beforeQpc;CaptureStopQpc=$stopQpc;QpcFrequency=[Diagnostics.Stopwatch]::Frequency;
        LaunchQpc=$launchQpc;RuntimeVersion=$PSVersionTable.PSVersion.ToString();RuntimeExecutable=$runtimeExecutable;RuntimeExecutableSha256=(Get-FileHash -LiteralPath $runtimeExecutable).Hash;
        LaunchSources=$launchSources;SourcesChangedDuringRun=@($launchSources|Where-Object {$_.Sha256 -cne (Get-FileHash -LiteralPath "$sourceRoot/$($_.Path)").Hash});
        GameReport=[IO.Path]::GetFileName($reportPath);FramesFile=[IO.Path]::GetFileName($prefix+'-frames.csv');
        LaunchFontSize=$FontSize;LaunchMaximized=[bool]$Maximized;LaunchStyle=$Style;LaunchGlyphSet=$GlyphSet;LaunchFontFace=$FontFace;
        LaunchWorkers=$Workers;LaunchSeconds=$Seconds;LaunchSound=[bool]($Sound -or $MusicCatalog);ProcessSamples=$processSamples.ToArray();
        LaunchTerminalOutput=$TerminalOutput;LaunchAnsiEncoding=$AnsiEncoding;
        ReplaySha256=(Get-FileHash -LiteralPath $Replay).Hash;MusicCatalogSha256=if($MusicCatalog){(Get-FileHash -LiteralPath $MusicCatalog).Hash}else{$null};
        SessionScheduleSha256=if($SessionSchedule){(Get-FileHash -LiteralPath $SessionSchedule).Hash}else{$null};HarnessSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash;
        RuntimeSourceSha256=$runtimeSourceSha256;RuntimeSourceDigestMeaning='SHA-256 of sorted repository-relative src/*.ps1 paths and SHA-256 values separated by LF; measured before launch.';
        PresentMonDll='C:\Program Files\Intel\PresentMonSharedService\PresentMonAPI2.dll';
        PresentMonDllSha256=(Get-FileHash 'C:\Program Files\Intel\PresentMonSharedService\PresentMonAPI2.dll').Hash;
        Meaning='PresentMon service frame events for the isolated Windows Terminal process. Includes startup/cleanup and potentially multiple swapchains; analyze within game write timestamps and per swapchain. Does not identify the Doom frame contents of each presentation. Once-per-second owned-process samples include cumulative CPU from process start and sampled memory, not continuously measured peak memory. Sampling overhead is part of the measured workload.'} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath ($prefix+'-capture.json')
    "PresentMon captured $($rows.Count) frame events: $prefix"
}
