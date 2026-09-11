#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# PresentMon is external measurement software; it is not a game dependency.
param([string]$OutputPrefix="$PSScriptRoot/../results/presentmon-e1m1",
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$Replay="$PSScriptRoot/../results/e1m1-route.json",
    [ValidateRange(4,24)][int]$FontSize=6,[switch]$Maximized,
    [ValidateSet('Classic','AnsiArt','Matrix')][string]$Style='Classic',
    [ValidateSet('Ascii','Katakana')][string]$GlyphSet='Katakana',[string]$FontFace)
$ErrorActionPreference='Stop'
if($Style -ne 'Classic' -and -not $PSBoundParameters.ContainsKey('FontSize')){$FontSize=12}
if(-not $FontFace){$FontFace=if($Style -ne 'Classic' -and $GlyphSet -eq 'Katakana'){'MS Gothic'}else{'Cascadia Mono'}}
. "$PSScriptRoot/PresentMonApi.ps1"
Initialize-PresentMonApi
$session=[IntPtr]::Zero;$query=[IntPtr]::Zero;$target=$null;$tracking=$false;$failure=$null
$rows=[Collections.Generic.List[object]]::new();$fields=[Collections.Generic.List[object]]::new()
$prefix=[IO.Path]::GetFullPath($OutputPrefix);$reportPath=$prefix+'-game.json'
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($prefix))
if(Test-Path -LiteralPath $reportPath){throw 'Choose a fresh output prefix to preserve the earlier capture.'}
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
    & "$PSScriptRoot/../Start-Doom.ps1" -Wad $Wad -Replay $Replay -Seconds 90 -Report $reportPath -FontSize $FontSize -Maximized:$Maximized -Style $Style -GlyphSet $GlyphSet -FontFace $FontFace
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
    while($watch.Elapsed.TotalSeconds -lt 105) {
        [uint32]$count=1024
        Assert-PresentMonStatus ([PwshDoomMeasurement.PresentMonApi]::pmConsumeFrames($query,[uint32]$target.Id,$buffer,[ref]$count)) 'consume frames'
        for($i=0;$i -lt $count;$i++) {
            $row=[ordered]@{ProcessId=$target.Id}
            foreach($field in $fields){$row[$field.Name]=Read-PresentMonField $buffer ([int]($i*$blobSize+$field.Offset)) $field.Type}
            $rows.Add([pscustomobject]$row)
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
    $rows.ToArray() | Export-Csv -LiteralPath ($prefix+'-frames.csv') -NoTypeInformation
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;ExitReason=$reason;FrameRows=$rows.Count;
        TerminalPid=if($null -ne $target){$target.Id}else{$null};Fields=$fields.ToArray();BlobSize=$blobSize;
        CaptureBeforeQpc=$beforeQpc;CaptureStopQpc=$stopQpc;QpcFrequency=[Diagnostics.Stopwatch]::Frequency;
        GameReport=[IO.Path]::GetFileName($reportPath);FramesFile=[IO.Path]::GetFileName($prefix+'-frames.csv');
        LaunchFontSize=$FontSize;LaunchMaximized=[bool]$Maximized;LaunchStyle=$Style;LaunchGlyphSet=$GlyphSet;LaunchFontFace=$FontFace;
        PresentMonDll='C:\Program Files\Intel\PresentMonSharedService\PresentMonAPI2.dll';
        PresentMonDllSha256=(Get-FileHash 'C:\Program Files\Intel\PresentMonSharedService\PresentMonAPI2.dll').Hash;
        Meaning='PresentMon service frame events for the isolated Windows Terminal process. Includes startup/cleanup and potentially multiple swapchains; analyze within game write timestamps and per swapchain. Does not identify the Doom frame contents of each presentation.'} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath ($prefix+'-capture.json')
    "PresentMon captured $($rows.Count) frame events: $prefix"
}
