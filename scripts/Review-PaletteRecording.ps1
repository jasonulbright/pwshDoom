#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Prefix,[Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh review receipt.'}
$g=Get-Content ($Prefix+'-game.json') -Raw|ConvertFrom-Json
$c=Get-Content ($Prefix+'-recording.json') -Raw|ConvertFrom-Json
$m=Get-Content ($Prefix+'-av.json') -Raw|ConvertFrom-Json
if($c.Error -or -not $c.AudioCaptured -or $m.Error){throw 'Review requires a successfully completed audiovisual capture.'}
$selections=@(@{Name='damage-world';Generation=2;Palette=8;Kind=0},@{Name='bonus-map';Generation=3;Palette=12;Kind=3},
    @{Name='berserk-world';Generation=4;Palette=2;Kind=0},@{Name='radiation-world';Generation=5;Palette=13;Kind=0},
    @{Name='restored-world';Generation=5;Palette=0;Kind=0})
$images=[Collections.Generic.List[object]]::new()
foreach($selection in $selections){
    $frames=@($g.FrameStats|Where-Object {$_.Generation -eq $selection.Generation -and $_.PaletteNumber -eq $selection.Palette -and $_.ScreenKind -eq $selection.Kind})
    if(-not $frames.Count){throw "Missing review state: $($selection.Name)"}
    $frame=$frames[[int][Math]::Floor($frames.Count/2)]
    $seconds=$frame.EndQpc/[double]$g.QpcFrequency-$m.Timeline.OriginQpc100ns/10000000.0+.05
    $path=[IO.Path]::GetFullPath($Prefix+'-'+$selection.Name+'.png')
    if(Test-Path $path){throw 'Review image already exists.'}
    & $c.MediaFfmpeg -v error -n -ss $seconds.ToString('F6',[Globalization.CultureInfo]::InvariantCulture) -i $c.Video -frames:v 1 $path
    if($LASTEXITCODE -ne 0){throw 'Review extraction failed.'}
    $images.Add(@{Name=$selection.Name;Path=$path;Sha256=(Get-FileHash $path).Hash;Seconds=$seconds;Tic=$frame.Tic;PaletteNumber=$frame.PaletteNumber;ScreenKind=$frame.ScreenKind})
}
@{Video=$c.Video;VideoSha256=$c.VideoSha256;Images=$images.ToArray();HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
    Meaning='Frames selected from actual captured video using host QPC and preserved capture origin, with a50-ms presentation allowance. Expected state is telemetry, not automatic visual confirmation; inspect every image separately. Original movie is unchanged.'}|ConvertTo-Json -Depth 5|Set-Content $Output
"Extracted $($images.Count) review frames."
