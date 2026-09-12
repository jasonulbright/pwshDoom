#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");foreach($name in 'MusScore','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','MusicGroup'){. "$root/src/$name.ps1"}
$checks=[Collections.Generic.List[object]]::new();$failure=$null;$ps=$null;$queue=$null;$cancel=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Fixture {
    $v=[int[]]::new(61);$v[8]=13500;$v[46]=-1;$v[47]=-1;$v[56]=100;$v[58]=-1
    foreach($op in 21,23,25,26,27,28,30,33,34,35,36){$v[$op]=-12000};$v[38]=0
    $r=@{Values=$v;RootKey=60;Sample=@{Rate=8000;Correction=0};Start=0;End=8;LoopStart=0;LoopEnd=8;LoopMode=1;KeyLow=0;KeyHigh=127;VelocityLow=0;VelocityHigh=127;InstrumentModulators=@();PresetModulators=@()}
    return @{Samples=[int16[]]@(0,1000,2000,1000,0,-1000,-2000,-1000);Presets=@{'0:0'=@{Name='Fixture';Regions=@($r)}}}
}
function Hash-Doubles([double[]]$Values){$bytes=[byte[]]::new($Values.Length*8);[Buffer]::BlockCopy($Values,0,$bytes,0,$bytes.Length);return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))}
try{
    $bank=Fixture;$score=@{DurationTicks=4;Events=@([long[]]@(0,1,0,60,100),[long[]]@(0,1,1,64,100),[long[]]@(1,2,1,1000,0),[long[]]@(1,4,0,8,127),[long[]]@(2,0,0,60,0),[long[]]@(2,0,1,64,0),[long[]]@(3,4,0,8,0),[long[]]@(4,6,0,0,0))}
    $longScore=@{DurationTicks=504000;Events=@(,[long[]]@(504000,6,0,0,0))}
    $longGroup=New-DoomMusicGroup $bank $longScore ([int[]]@(0)) 158760000
    Check 'One-hour horizon creates state without allocating the complete output' ($longGroup.Frames -eq 158760000 -and $longGroup.Synth.Frame -eq 0)
    $longGroup.Synth.Frame=158758740L;$longGroup.Timeline.Frame=158758740L;$tail=Read-DoomMusicGroup $longGroup 1
    Check 'Last subblock of the larger horizon retains exact integer bounds' ($tail.Frame -eq 158758740 -and $tail.Frames -eq 1260 -and $tail.Mix.Length -eq 2520 -and $longGroup.Synth.Frame -eq 158760000)
    $rejected=$false;try{$null=New-DoomMusicGroup $bank $score ([int[]]@(0)) 158760001}catch{$rejected=$true};Check 'Beyond one-hour horizon is rejected' $rejected
    foreach($channels in @([int[]]@(),[int[]]@(0,0),[int[]]@(-1),[int[]]@(16))){$rejected=$false;try{$null=New-DoomMusicGroup $bank $score $channels 1260}catch{$rejected=$true};Check "Invalid channel selection rejected: $($channels -join ',')" $rejected}
    $group=New-DoomMusicGroup $bank $score ([int[]]@(0)) 1260;$chunk=Read-DoomMusicGroup $group 1
    $reference=New-DoomMusicSynth $bank;$expected=[Collections.Generic.List[double]]::new()
    Invoke-DoomMusicEvent $reference ([long[]]@(0,1,0,60,100));$expected.AddRange((Read-DoomMusicSynth $reference 315))
    Invoke-DoomMusicEvent $reference ([long[]]@(315,4,0,8,127));$expected.AddRange((Read-DoomMusicSynth $reference 315))
    Invoke-DoomMusicEvent $reference ([long[]]@(630,0,0,60,0));$expected.AddRange((Read-DoomMusicSynth $reference 315))
    Invoke-DoomMusicEvent $reference ([long[]]@(945,4,0,8,0));$expected.AddRange((Read-DoomMusicSynth $reference 315))
    Check 'Owned-channel output equals manually scheduled reference at all boundaries' ((Hash-Doubles $chunk.Mix) -ceq (Hash-Doubles $expected.ToArray()))
    Check 'Unowned channel pitch and note state remain untouched' ($group.Synth.Channels[1].Bend -eq 8192 -and $group.Synth.NoteOns -eq 1)
    Check 'Group chunk metadata and clocks cover exactly one subblock' ($chunk.Index -eq 0 -and $chunk.Frame -eq 0 -and $chunk.Frames -eq 1260 -and $group.Synth.Frame -eq 1260 -and $group.Timeline.Frame -eq 1260)
    $rejected=$false;try{$null=Read-DoomMusicGroup $group 1}catch{$rejected=$true};Check 'Finished group rejects an extra read' $rejected
    $whole=New-DoomMusicGroup $bank $score ([int[]]@(0,1)) 2521;$parts=New-DoomMusicGroup $bank $score ([int[]]@(0,1)) 2521
    $a=Read-DoomMusicGroup $whole 3;$joined=[Collections.Generic.List[double]]::new()
    foreach($i in 1..3){$part=Read-DoomMusicGroup $parts 1;$joined.AddRange([double[]]$part.Mix)}
    Check 'Group batching preserves exact doubles through two loop boundaries' ((Hash-Doubles $a.Mix) -ceq (Hash-Doubles $joined.ToArray()))
    Check 'Global end releases older voices while new loop notes start' ($whole.Synth.NoteOns -eq 6 -and @($whole.Synth.Voices|Where-Object {$_.Released}).Count -gt 0 -and @($whole.Synth.Voices|Where-Object {-not $_.Released}).Count -eq 2)
    $noteBank=Fixture;$r=$noteBank.Presets['0:0'].Regions[0];$r.Values[57]=1;$noteBank.Presets['0:0'].Regions=@($r,$r)
    $exclusive=@{DurationTicks=4;Events=@([long[]]@(0,1,0,60,100),[long[]]@(1,1,0,64,100),[long[]]@(4,6,0,0,0))}
    $noteA=New-DoomMusicGroup $noteBank $exclusive ([int[]](0..15)) 316 -Partition Note -GroupCount 2 -GroupIndex 0
    $noteB=New-DoomMusicGroup $noteBank $exclusive ([int[]](0..15)) 316 -Partition Note -GroupCount 2 -GroupIndex 1
    $a=Read-DoomMusicGroup $noteA 1;$b=Read-DoomMusicGroup $noteB 1
    Check 'Note partition keeps every layer of the assigned note together' ($noteB.Synth.Voices.Count -eq 2 -and $noteB.Synth.Voices[0].NoteId -eq $noteB.Synth.Voices[1].NoteId -and $noteA.OwnedNoteOns -eq 1 -and $noteB.OwnedNoteOns -eq 1)
    Check 'Foreign note triggers exclusive cuts on the other worker' ($noteA.Synth.Voices.Count -eq 0 -and $noteA.Synth.ExclusiveCuts -eq 2 -and $noteB.Synth.ExclusiveCuts -eq 0)
    $full=New-DoomMusicGroup $noteBank $exclusive ([int[]](0..15)) 316;$expected=Read-DoomMusicGroup $full 1
    for($i=0;$i -lt $a.Mix.Length;$i++){$a.Mix[$i]+=$b.Mix[$i]}
    Check 'Cross-worker exclusive-note waveform equals unsplit reference' ((Hash-Doubles $a.Mix) -ceq (Hash-Doubles $expected.Mix))
    $monoBank=Fixture;$monoScore=@{DurationTicks=4;Events=@([long[]]@(0,3,0,12,0),[long[]]@(0,1,0,60,100),[long[]]@(1,1,0,64,100),[long[]]@(4,6,0,0,0))}
    $mono=New-DoomMusicGroup $monoBank $monoScore ([int[]](0..15)) 316 -Partition Note -GroupCount 2 -GroupIndex 0;$null=Read-DoomMusicGroup $mono 1
    Check 'Foreign mono note cuts the prior locally owned voice' ($mono.Synth.Voices.Count -eq 0 -and $mono.Synth.ExclusiveCuts -eq 1)
    $queue=[Collections.Concurrent.BlockingCollection[object]]::new(1);$cancel=[Threading.CancellationTokenSource]::new();$ps=[powershell]::Create()
    $null=$ps.AddScript([IO.File]::ReadAllText("$PSScriptRoot/Invoke-MusicGroupWorker.ps1")).AddArgument($root).AddArgument($bank).AddArgument($score).AddArgument([int[]]@(0)).AddArgument(12600).AddArgument(1).AddArgument($queue).AddArgument($cancel)
    $handle=$ps.BeginInvoke();$wait=[Diagnostics.Stopwatch]::StartNew()
    while($queue.Count -eq 0 -and -not $handle.IsCompleted -and $wait.Elapsed.TotalSeconds -lt 10){Start-Sleep -Milliseconds 20}
    Check 'Worker fills the bounded queue and remains live' ($queue.Count -eq 1 -and -not $handle.IsCompleted)
    $cancel.Cancel();Check 'Cancellation terminates a producer with a full queue' $handle.AsyncWaitHandle.WaitOne(10000)
    try{$null=$ps.EndInvoke($handle)}catch{}
    Check 'Cancelled worker completes queue publication' $queue.IsAddingCompleted
    $ps.Dispose();$ps=$null;$queue.Dispose();$queue=$null;$cancel.Dispose();$cancel=$null
    $bad=$score.Clone();$bad.Events=@([long[]]@(0,4,0,0,99),[long[]]@(0,1,0,60,100),[long[]]@(4,6,0,0,0))
    $queue=[Collections.Concurrent.BlockingCollection[object]]::new(1);$cancel=[Threading.CancellationTokenSource]::new();$ps=[powershell]::Create()
    $null=$ps.AddScript([IO.File]::ReadAllText("$PSScriptRoot/Invoke-MusicGroupWorker.ps1")).AddArgument($root).AddArgument($bank).AddArgument($bad).AddArgument([int[]]@(0)).AddArgument(1260).AddArgument(1).AddArgument($queue).AddArgument($cancel)
    $handle=$ps.BeginInvoke();Check 'Invalid preset worker terminates promptly' $handle.AsyncWaitHandle.WaitOne(10000)
    try{$null=$ps.EndInvoke($handle)}catch{}
    Check 'Worker errors are visible and leave no partial chunk' ($ps.HadErrors -and $queue.IsAddingCompleted -and $queue.Count -eq 0)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($cancel){$cancel.Cancel()};if($ps){$ps.Stop();$ps.Dispose()};if($queue){$queue.Dispose()};if($cancel){$cancel.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();Sources=@('src/MusScore.ps1','src/SoundFontRegions.ps1','src/MusicOscillator.ps1','src/MusicControls.ps1','src/MusicSynth.ps1','src/MusicGroup.ps1','scripts/Invoke-MusicGroupWorker.ps1','scripts/Test-MusicGroups.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path $root $_)).Hash}});
      Meaning='Synthetic ownership, event-boundary, exact-double batching, loop and actual runspace cancellation/error checks. No playback device or game integration.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) music group checks."
