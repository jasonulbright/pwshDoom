#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string[]]$Names,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh comparison report.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$checks=[Collections.Generic.List[object]]::new();$runs=[Collections.Generic.List[object]]::new()
$receipts=[Collections.Generic.List[object]]::new();$reference=$null;$failure=$null
function Read-Receipt([string]$Path){$receipts.Add(@{Path=$Path;Sha256=(Get-FileHash $Path).Hash});Get-Content $Path -Raw|ConvertFrom-Json}
function Check([string]$Name,[bool]$Pass){$checks.Add(@{Name=$Name;Passed=$Pass});if(-not $Pass){throw $Name}}
function Stats($Values){
    $v=@($Values|Sort-Object);if(-not $v.Count){throw 'No timing observations.'}
    @{Count=$v.Count;Mean=($v|Measure-Object -Average).Average;P50=$v[[Math]::Ceiling(.5*$v.Count)-1];P95=$v[[Math]::Ceiling(.95*$v.Count)-1];P99=$v[[Math]::Ceiling(.99*$v.Count)-1];Max=$v[-1]}
}
try{
    Check 'Four distinct trial names were supplied' ($Names.Count -eq 4 -and @($Names|Sort-Object -Unique).Count -eq 4)
    $expectedModes='Strips','Batch','Batch','Strips'
    for($n=0;$n -lt $Names.Count;$n++){
        $name=$Names[$n];$prefix="$root/local/recordings/$name"
        $g=Read-Receipt ($prefix+'-game.json');$c=Read-Receipt ($prefix+'-recording.json');$s=Read-Receipt ($prefix+'-route-sources.json')
        $audit=Read-Receipt "$root/results/$name-recorded.json";$timing=Read-Receipt "$root/results/$name-timing.json"
        Check "$name passed its complete recorded campaign audit" (-not $audit.Error -and $audit.Checks.Count -gt 50 -and @($audit.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
        Check "$name uses the declared mode and retains every frame timestamp" ($g.TerminalOutput.Mode -ceq $expectedModes[$n] -and $c.TerminalOutput -ceq $expectedModes[$n] -and $g.FrameStats.Count -eq $g.CompletedFrames)
        Check "$name has one unchanged fitting viewport" ($g.ViewportChanges.Count -eq 1 -and $g.ViewportChanges[0].Fits -and $g.ViewportPauseCount -eq 0 -and $g.DiscardedResizeFrames -eq 0)
        $pins=@(@($s.Sources)+@($c.Sources)|Sort-Object Path,Sha256 -Unique)
        foreach($pin in $pins){Check "$name current source matches $($pin.Path)" ($pin.Sha256 -ceq (Get-FileHash "$root/$($pin.Path)").Hash)}
        $signature=[ordered]@{Sources=@($pins|ForEach-Object {[ordered]@{Path=$_.Path;Sha256=$_.Sha256}});Engine=$s.CurrentSourceFingerprint;
            Replay=$c.ReplaySha256;Wad=$g.WadSha256;Catalog=$c.MusicCatalogSha256;Pcm=$g.Simulation.Audio.PcmSha256;
            Style=$g.OutputStyle;FontFace=$c.FontFace;FontSize=$c.FontSize;Maximized=$c.Maximized;Columns=$g.TerminalColumns;Rows=$g.TerminalRows;
            Viewport=($g.ViewportChanges[0]|Select-Object Columns,Rows,Left,Top);Workers=$g.Workers;PowerShell=$g.PowerShell;
            InitialSettings=($g.InitialSettings|Select-Object Version,AlwaysRun,TurnSpeed,SoundVolume,SoundMuted);Diagnostics=$g.Diagnostics;SourceWidth=$g.SourceWidth;SourceHeight=$g.SourceHeight;
            CaptureBackend=$c.CaptureBackend;CaptureLimit=$c.CaptureLimit;Recorder=$c.FfmpegSha256;Media=$c.MediaFfmpegSha256}
        $json=$signature|ConvertTo-Json -Depth 7 -Compress
        if($null -eq $reference){$reference=$json}else{Check "$name matches first-run source, workload, PCM, viewport and capture configuration" ($json -ceq $reference)}
        $gaps=@(for($i=1;$i -lt $g.FrameStats.Count;$i++){($g.FrameStats[$i].EndQpc-$g.FrameStats[$i-1].EndQpc)*1000.0/$g.QpcFrequency})
        $gapStats=Stats $gaps;$endpointMean=($g.FrameStats[-1].EndQpc-$g.FrameStats[0].EndQpc)*1000.0/$g.QpcFrequency/($g.FrameStats.Count-1)
        Check "$name gap mean agrees with endpoint identity and saved summary" ([Math]::Abs($gapStats.Mean-$endpointMean) -lt 1e-7 -and [Math]::Abs($gapStats.Mean-$timing.AllConsecutiveWriteGapsMs.Mean) -lt 1e-7)
        $level=@($g.FrameStats|Where-Object {$_.State -eq 0})
        $runs.Add(@{Name=$name;Mode=$g.TerminalOutput.Mode;ConsoleWritesPerActiveSecond=$g.CompletedUpdatesPerSecond;TicsPerActiveSecond=$g.TicsPerSecond;
            ActiveSeconds=$g.DurationSeconds;WallSeconds=$g.WallDurationSeconds;Output=$g.TerminalOutput;
            AllFrameOutputMs=(Stats $g.FrameStats.OutputMs);LevelOutputMs=(Stats $level.OutputMs);LevelSubmitMs=(Stats $level.SubmitMs);LevelHarvestMs=(Stats $level.HarvestMs);
            AllWriteGapsMs=$gapStats;SameWorldWriteGapsMs=$timing.SameWorldWriteGapsMs;Audio=$timing.Audio;Video=$timing.Video;
            MeanBytesPerImage=$g.TerminalOutput.Bytes/[double]$g.CompletedFrames;VideoPath=$c.Video;VideoSha256=$c.VideoSha256})
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Runs=$runs.ToArray();SharedConfiguration=$reference;Receipts=$receipts.ToArray();SourceSha256=(Get-FileHash $PSCommandPath).Hash;
        Meaning='Four captured complete routes in declared Strips/Batch/Batch/Strips order. Same source/workload/audio/viewport/capture configuration verified; all frame observations retained. Level output and same-world gaps are explicit subsets. Two trials per mode expose variation but do not establish statistical confidence or universality. Console image completion is not distinct displayed FPS; capture is an added workload. Audio queue observations are not acoustic measurements.'}|ConvertTo-Json -Depth 10|Set-Content $Output
}
$runs|Select-Object Name,Mode,TicsPerActiveSecond,ConsoleWritesPerActiveSecond,@{n='LevelOutputMeanMs';e={$_.LevelOutputMs.Mean}},@{n='GapP95Ms';e={$_.SameWorldWriteGapsMs.P95}}|Format-Table
