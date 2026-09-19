#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# Edit existing captured movies only; never launches a game or recorder.
param([Parameter(Mandatory)][string]$Ffmpeg,[Parameter(Mandatory)][string]$OutputDirectory,
    [string]$RecordingDirectory="$PSScriptRoot/../local/recordings")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$output=[IO.Path]::GetFullPath($OutputDirectory);[void][IO.Directory]::CreateDirectory($output)
$ff=[IO.Path]::GetFullPath($Ffmpeg);$recordings=[IO.Path]::GetFullPath($RecordingDirectory)
$plan=@(
    @{Name='matrix';Title='pwshDoom / MATRIX';Prefix='e1m3-matrix-third';Start=49.5;Crop='1280:800:96:122';Color='0x61ff83'},
    @{Name='color';Title='pwshDoom / COLOR ART';Prefix='e1m2-color-third';Start=45.5;Crop='1280:800:96:122';Color='0xffd179'},
    @{Name='classic';Title='pwshDoom / CLASSIC';Prefix='e1m2-classic-lighting-second';Start=46.0;Crop='1600:900:920:256';Color='white'}
)
foreach($name in @($plan.Name)+@('showcase')){if(Test-Path (Join-Path $output "pwshDoom-$name-x.mp4")){throw 'Use fresh export paths.'}}
function Run-Media([string[]]$Arguments,[string]$Log){
    $info=[Diagnostics.ProcessStartInfo]::new($ff);$info.WorkingDirectory=$output;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach($argument in $Arguments){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($info);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
    try{if(-not $process.WaitForExit(180000)){$process.Kill();$process.WaitForExit();throw 'Media export exceeded its finite deadline.'}
        $stderr.Result|Set-Content (Join-Path $output $Log);if($process.ExitCode -ne 0){throw "Media export failed; inspect $Log"}
    }finally{$process.Dispose()}
}
$font=(Join-Path $env:WINDIR 'Fonts/consolab.ttf').Replace('\','/').Replace(':','\:')
[IO.File]::WriteAllText((Join-Path $output 'footer.txt'),'PowerShell + Windows Terminal  /  github.com/jasonulbright/pwshDoom')
$receipts=[Collections.Generic.List[object]]::new()
foreach($item in $plan){
    $record=Get-Content (Join-Path $recordings ($item.Prefix+'-recording.json')) -Raw|ConvertFrom-Json
    $video=Join-Path $recordings ($item.Prefix+'-av.mp4')
    if($record.Error -or -not $record.AudioCaptured -or (Get-FileHash $video).Hash -cne $record.VideoSha256){throw 'Source movie is not an intact completed audiovisual recording.'}
    [IO.File]::WriteAllText((Join-Path $output ($item.Name+'-title.txt')),$item.Title)
    $filter="crop=$($item.Crop),scale=1600:1000:force_original_aspect_ratio=decrease:flags=neighbor,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=0x080b0a,setsar=1,fps=30,drawtext=fontfile='$font':textfile='$($item.Name)-title.txt':fontcolor=$($item.Color):fontsize=28:x=160:y=6,drawtext=fontfile='$font':textfile='footer.txt':fontcolor=0xaeb8b1:fontsize=22:x=(w-text_w)/2:y=1051"
    $name="pwshDoom-$($item.Name)-x.mp4"
    Run-Media @('-hide_banner','-n','-ss',$item.Start.ToString([cultureinfo]::InvariantCulture),'-i',$video,'-t','30','-map','0:v:0','-map','0:a:0',
        '-vf',$filter,'-af','afade=t=in:d=0.12,afade=t=out:st=29.88:d=0.12','-c:v','h264_nvenc','-preset','p5','-profile:v','high','-level:v','4.1','-cq','18','-b:v','8M','-maxrate','12M','-bufsize','24M',
        '-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-ar','48000','-ac','2','-movflags','+faststart','-map_metadata','-1',(Join-Path $output $name)) ($item.Name+'-export.log')
    $receipts.Add(@{Name=$item.Name;Source=$video;SourceSha256=$record.VideoSha256;StartSeconds=$item.Start;DurationSeconds=30;Crop=$item.Crop;Output=$name;Sha256=(Get-FileHash (Join-Path $output $name)).Hash})
    "Exported $name"
}
$concat=(@($plan|ForEach-Object {"file 'pwshDoom-$($_.Name)-x.mp4'"}) -join "`n")+"`n"
[IO.File]::WriteAllText((Join-Path $output 'concat.txt'),$concat)
Run-Media @('-hide_banner','-n','-f','concat','-safe','1','-i','concat.txt','-c','copy','-movflags','+faststart','-map_metadata','-1',(Join-Path $output 'pwshDoom-showcase-x.mp4')) 'showcase-export.log'
@{Clips=$receipts.ToArray();Showcase='pwshDoom-showcase-x.mp4';ShowcaseSha256=(Get-FileHash (Join-Path $output 'pwshDoom-showcase-x.mp4')).Hash;
    ExporterSha256=(Get-FileHash $PSCommandPath).Hash;FfmpegSha256=(Get-FileHash $ff).Hash;
    Meaning='Existing development gameplay with captured effects and separately prepared music. Cropped window margins, scaled without color enhancement, added mode/project labels, resampled60fps movie to30fps, and faded only120ms audio at cut boundaries. Three30-second excerpts concatenated in Matrix/color/Classic order. Original timing within excerpts and original source movies retained. Not a performance comparison or a claim that quick-start music is bundled.'}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $output 'export-receipt.json')
