#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/MusScore.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Fixture([byte[]]$Body){
    $bytes=[byte[]]::new(18+$Body.Length);([byte[]]@(77,85,83,26)).CopyTo($bytes,0)
    [BitConverter]::GetBytes([uint16]$Body.Length).CopyTo($bytes,4);[BitConverter]::GetBytes([uint16]18).CopyTo($bytes,6)
    $bytes[8]=2;$bytes[12]=1;$bytes[16]=24;$Body.CopyTo($bytes,18);return ,$bytes
}
try{
    # Program, explicit/cached velocity, another channel's default, pitch center,
    # drum note, system and volume controller, then release and end.
    $bytes=Fixture ([byte[]]@(0x40,0,24,0x10,188,100,0x90,64,2,0x11,65,0x20,128,0x9f,163,80,1,0x30,11,0xc0,3,200,10,0x80,60,0,0x60))
    $score=ConvertFrom-DoomMus $bytes
    $expected=@('0,4,0,0,24','0,1,0,60,100','0,1,0,64,100','2,1,1,65,127','2,2,0,8192,0','2,1,15,35,80','3,3,0,11,0','3,4,0,3,127','13,0,0,60,0','13,6,0,0,0')
    Check 'Independent event/timing/channel vector' ((@($score.Events|ForEach-Object {$_ -join ','}) -join '|') -ceq ($expected -join '|'))
    Check 'Instrument, duration and normalization metadata' ($score.Instruments[0] -eq 24 -and $score.DurationTicks -eq 13 -and $score.NormalizedValues -eq 1)
    $normalized=ConvertFrom-DoomMus (Fixture ([byte[]]@(0x40,0,200,0x10,188,200,0x00,188,0xe0)))
    Check 'Program and note/velocity high bits are masked; end flag consumes no delay' ((($normalized.Events|ForEach-Object {$_ -join ','}) -join '|') -ceq '0,4,0,0,72|0,1,0,60,72|0,0,0,60,0|0,6,0,0,0')
    Check 'Masking normalization counter' ($normalized.NormalizedValues -eq 3)
    foreach($kind in 'short','signature','scorestart','scorelength','instrumentcount','truncatednote','truncateddelay','missingend','reserved','system','controller','longdelay','duration'){
        $bad=$bytes.Clone()
        switch($kind){
            short {$bad=[byte[]]::new(15)};signature {$bad[3]=0};scorestart {$bad[6]=16};scorelength {$bad[4]=255;$bad[5]=255};instrumentcount {$bad[12]=255}
            truncatednote {$bad=Fixture ([byte[]]@(0x10,188))};truncateddelay {$bad=Fixture ([byte[]]@(0x90,60,128))};missingend {$bad=Fixture ([byte[]]@(0x10,60))}
            reserved {$bad=Fixture ([byte[]]@(0x50,0x60))};system {$bad=Fixture ([byte[]]@(0x30,9,0x60))};controller {$bad=Fixture ([byte[]]@(0x40,10,0,0x60))}
            longdelay {$bad=Fixture ([byte[]]@(0x90,60,128,128,128,128,128,0,0x60))};duration {$bad=Fixture ([byte[]]@(0x90,60,255,255,255,127,0x60))}
        }
        $rejected=$false;try{$null=ConvertFrom-DoomMus $bad}catch{$rejected=$true};Check "Reject malformed $kind" $rejected
    }
    $long=ConvertFrom-DoomMus (Fixture ([byte[]]@(0x90,60,129,0,0x60)))
    Check 'Big-endian base-128 delay' ($long.DurationTicks -eq 128)
    Check 'Music tick maps exactly to 315 frames at 44.1 kHz' ((Convert-DoomMusicTickToFrame 1) -eq 315 -and (Convert-DoomMusicTickToFrame 140) -eq 44100)
    $a=New-DoomMusicTimeline $score;$first=Read-DoomMusicFrames $a 630;$second=Read-DoomMusicFrames $a 1
    Check 'Events on block endpoint belong to next block' ($first.Events.Count -eq 3 -and $second.Events.Count -eq 3 -and $second.Events[0][0] -eq 630)
    $a=New-DoomMusicTimeline $score -Loop;$whole=Read-DoomMusicFrames $a 10000
    $b=New-DoomMusicTimeline $score -Loop;$parts=[Collections.Generic.List[object]]::new()
    foreach($size in 1,127,315,1260,17,8280){$block=Read-DoomMusicFrames $b $size;foreach($event in $block.Events){$parts.Add($event)}}
    Check 'Loop event sequence independent of audio block partition' (($whole.Events|ConvertTo-Json -Compress) -ceq ($parts.ToArray()|ConvertTo-Json -Compress))
    $c=New-DoomMusicTimeline $score;$c.Paused=$true;$block=Read-DoomMusicFrames $c 5000
    Check 'Pause retains music position and pending events' ($block.Events.Count -eq 0 -and $c.Frame -eq 0 -and $c.Index -eq 0)
    $c.Paused=$false;$block=Read-DoomMusicFrames $c 5000;$after=Read-DoomMusicFrames $c 5000
    Check 'Nonlooping score ends once' ($c.Finished -and $block.Events.Count -eq 10 -and $after.Events.Count -eq 0)
    $odd=ConvertFrom-DoomMus (Fixture ([byte[]]@(0x90,60,1,0x60)));$t=New-DoomMusicTimeline $odd -Rate 22050 -Loop;$result=Read-DoomMusicFrames $t 22051
    $ends=@($result.Events|Where-Object {$_[1] -eq 6})
    Check 'Nonintegral loop length accumulates no rounded-cycle drift' ($ends.Count -eq 140 -and $ends[0][0] -eq 157 -and $ends[1][0] -eq 315 -and $ends[-1][0] -eq 22050)
    $zero=ConvertFrom-DoomMus (Fixture ([byte[]]@(0x60)));$rejected=$false;try{$null=New-DoomMusicTimeline $zero -Loop}catch{$rejected=$true};Check 'Zero-duration infinite loop rejected' $rejected
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=@('src/MusScore.ps1','scripts/Test-MusScore.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash (Join-Path "$PSScriptRoot/.." $_)).Hash}});Meaning='Independent synthetic MUS bytes, malformed bounds and exact sample scheduling. No synthesis, playback or whole-IWAD compatibility claim.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) MUS score checks."
