#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Prefix,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$prefix=[IO.Path]::GetFullPath($Prefix)
foreach($p in $Output,($prefix+'-transitions.mp4'),($prefix+'-intermission.png'),($prefix+'-e1m2.png')){if(Test-Path $p){throw 'Use fresh clip/image/report paths.'}}
$g=Get-Content ($prefix+'-game.json') -Raw|ConvertFrom-Json
$m=Get-Content ($prefix+'-av.json') -Raw|ConvertFrom-Json
$c=Get-Content ($prefix+'-recording.json') -Raw|ConvertFrom-Json
if($g.Error -or $m.Error -or $c.Error -or $m.VideoSha256 -cne (Get-FileHash $m.Video).Hash){throw 'Expected intact successful route movie.'}
$firstInter=@($g.FrameStats|Where-Object State -eq 1)[0];$firstMap2=@($g.FrameStats|Where-Object Map -eq 2)[0]
$interTime=($firstInter.EndQpc*10000000.0/$g.QpcFrequency-[double]$m.Clock.OriginQpc100ns)/10000000
$mapTime=($firstMap2.EndQpc*10000000.0/$g.QpcFrequency-[double]$m.Clock.OriginQpc100ns)/10000000
$endTime=($g.FrameStats[-1].EndQpc*10000000.0/$g.QpcFrequency-[double]$m.Clock.OriginQpc100ns)/10000000
$start=$interTime-1.5;$duration=$endTime-$start
if($start -lt 0 -or $duration -le 0 -or $duration -gt 30 -or $mapTime -le $interTime){throw 'Unexpected route excerpt bounds.'}
function Number([double]$Value){return $Value.ToString('F6',[cultureinfo]::InvariantCulture)}
$ff=$c.MediaFfmpeg;$failure=$null
try{
    & $ff -v error -n -ss (Number $start) -i $m.Video -t (Number $duration) -c:v h264_nvenc -preset p4 -cq 18 -c:a aac -b:a 192k -movflags +faststart ($prefix+'-transitions.mp4')
    if($LASTEXITCODE -ne 0){throw 'Viewing copy failed'}
    & $ff -v error -n -ss (Number ($interTime+.5)) -i $m.Video -frames:v 1 ($prefix+'-intermission.png')
    if($LASTEXITCODE -ne 0){throw 'Intermission image failed'}
    & $ff -v error -n -ss (Number ($mapTime+.7)) -i $m.Video -frames:v 1 ($prefix+'-e1m2.png')
    if($LASTEXITCODE -ne 0){throw 'Map image failed'}
    & $ff -v error -i ($prefix+'-transitions.mp4') -f null -
    if($LASTEXITCODE -ne 0){throw 'Viewing copy decode failed'}
}catch{$failure=$_.ToString();throw}finally{
    @{Error=$failure;Video=$m.Video;VideoSha256=$m.VideoSha256;ViewingCopy=$prefix+'-transitions.mp4';ViewingCopySha256=if(Test-Path ($prefix+'-transitions.mp4')){(Get-FileHash ($prefix+'-transitions.mp4')).Hash}else{$null};
      StartSeconds=$start;DurationSeconds=$duration;IntermissionImageSeconds=$interTime+.5;MapImageSeconds=$mapTime+.7;DecodePassed=(-not $failure);ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Actual movie excerpt around E1M1 exit, intermission and E1M2 entry, with sampled PNGs for separate visual review. Original full-window capture retained; no speed changes or discarded handoff time. Decode is not a visual or listening review.'}|ConvertTo-Json|Set-Content $Output
}
