#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# External diagnostic recorder only. Prerequisites/download identities are in
# docs/audiovisual-recording.md; source archives and binaries remain under local/.
param([string]$VisualStudio='C:\Program Files\Microsoft Visual Studio\18\Community',
    [string]$GitBash='C:\Program Files\Git\usr\bin\bash.exe',
    [string]$BuildRoot="$PSScriptRoot/../local/tools/capture-build",
    [Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh build receipt path.'}
$root=[IO.Path]::GetFullPath($BuildRoot);$src=Join-Path $root 'FFmpeg-n9.0.1';$make=Join-Path $root 'make-4.4.1/WinRel/gnumake.exe'
$vcvars=Join-Path $VisualStudio 'VC/Auxiliary/Build/vcvars64.bat';$pkgconf=Join-Path $root 'pkgconf-wheel/pkgconf/.bin/pkgconf.exe'
foreach($path in $root,$VisualStudio,$GitBash){if($path -match '[\r\n"%]'){throw 'Build paths cannot contain quotes, percent expansion or newlines.'}}
foreach($path in $vcvars,$GitBash,$make,$pkgconf,(Join-Path $src 'configure'),(Join-Path $root 'nv-codec-headers-n13.0.19.0/ffnvcodec.pc.in')){if(-not (Test-Path $path)){throw "Missing documented build prerequisite: $path"}}
$sourcePath=Join-Path $src 'libavfilter/vsrc_gfxcapture_winrt.cpp';$source=[IO.File]::ReadAllText($sourcePath)
$original="    if (!ctx->first_pts)`n        ctx->first_pts = frame->pts;"
$replacement=@'
    if (!ctx->first_pts) {
        ctx->first_pts = frame->pts;
        av_log(avctx, AV_LOG_INFO, "PWSHDOOM_GFX_ORIGIN_QPC100NS=%lld\n", (long long)frame->pts);
    }
'@
if($source.Contains($original)){[IO.File]::WriteAllText($sourcePath,$source.Replace($original,$replacement.TrimEnd()))}
elseif(-not $source.Contains($replacement.TrimEnd())){throw 'Unexpected capture source; refusing an unreviewed patch.'}
$includeRoot=(Join-Path $root 'nv-codec-headers-n13.0.19.0').Replace('\','/')
$pc=[IO.File]::ReadAllText((Join-Path $includeRoot 'ffnvcodec.pc.in')).Replace('@@PREFIX@@',$includeRoot)
[IO.File]::WriteAllText((Join-Path $includeRoot 'ffnvcodec.pc'),$pc)
$awk=@'
/including/ { sub(/^.*file: */, ""); gsub(/\\/, "/"); if (!match($0, / /)) print target ":", $0 }
'@
[IO.File]::WriteAllText((Join-Path $root 'capture-deps.awk'),$awk)
$unixRoot=$root.Replace('\','/');$unixSrc=$src.Replace('\','/');$unixPkg=$pkgconf.Replace('\','/')
$configure=@'
#!/usr/bin/env bash
set -e
cd "@SOURCE@"
export PKG_CONFIG_PATH="@INCLUDES@"
./configure --toolchain=msvc --arch=x86_64 --disable-autodetect --disable-everything --disable-doc --disable-debug --disable-x86asm --enable-static --disable-shared --enable-ffmpeg --enable-ffprobe --enable-avdevice --enable-avfilter --enable-swscale --enable-protocol=file,pipe --enable-filter=gfxcapture,setpts,scale,format --enable-encoder=h264_nvenc,aac --enable-decoder=h264,aac,pcm_s16le --enable-demuxer=mov,wav --enable-muxer=mp4,wav,hash,null --enable-parser=h264,aac --enable-d3d11va --enable-ffnvcodec --enable-nvenc --pkg-config="@PKGCONF@"
'@
$configure=$configure.Replace('@SOURCE@',$unixSrc).Replace('@INCLUDES@',$includeRoot).Replace('@PKGCONF@',$unixPkg)
$configurePath=Join-Path $root 'configure-recorder.sh';[IO.File]::WriteAllText($configurePath,$configure)
function Invoke-BuildShell([string]$Script,[string]$Log){
    $wrapper=@'
@echo off
call "@VCVARS@"
if errorlevel 1 exit /b 1
set "PATH=%VCToolsInstallDir%bin\Hostx64\x64;@MAKEPATH@;@BASHPATH@;%PATH%"
"@BASH@" --noprofile --norc "@SCRIPT@"
'@
    $wrapper=$wrapper.Replace('@VCVARS@',$vcvars).Replace('@MAKEPATH@',[IO.Path]::GetDirectoryName($make)).Replace('@BASHPATH@',[IO.Path]::GetDirectoryName($GitBash)).Replace('@BASH@',$GitBash).Replace('@SCRIPT@',$Script.Replace('\','/'))
    $cmd=Join-Path $root 'run-recorder-build.cmd';[IO.File]::WriteAllText($cmd,$wrapper)
    & cmd.exe /d /c $cmd *> $Log
    if($LASTEXITCODE -ne 0){throw "Recorder build phase failed; inspect $Log"}
}
$failure=$null;$watch=[Diagnostics.Stopwatch]::StartNew()
try{
    Invoke-BuildShell $configurePath (Join-Path $root 'configure-recorder.log')
    # Move the generated inline AWK program to a file to avoid native Make/MSYS
    # quoting changes. This retains the same dependency extraction algorithm.
    $configPath=Join-Path $src 'ffbuild/config.mak';$lines=[IO.File]::ReadAllText($configPath) -split "`n"
    for($i=0;$i -lt $lines.Length;$i++){if($lines[$i] -match '^(CCDEP|CXXDEP|ASDEP|HOSTCCDEP)='){$prefix=$lines[$i].Substring(0,$lines[$i].IndexOf(' | awk '));$lines[$i]=$prefix+' | awk -v target=$@ -f ../capture-deps.awk > $(@:.o=.d)'}}
    [IO.File]::WriteAllText($configPath,($lines -join "`n"))
    $compilePath=Join-Path $root 'compile-recorder.sh'
    $compile='#!/usr/bin/env bash'+"`nset -e`n"+'cd "'+$unixSrc+'"'+"`n"+'gnumake.exe -r -j4'+"`n"
    [IO.File]::WriteAllText($compilePath,$compile)
    Invoke-BuildShell $compilePath (Join-Path $root 'compile-recorder.log')
}catch{$failure=$_.ToString();throw}finally{
    $binary=Join-Path $src 'ffmpeg.exe'
    @{Error=$failure;Seconds=$watch.Elapsed.TotalSeconds;VisualStudio=$VisualStudio;GitBash=$GitBash;SourceArchiveSha256=(Get-FileHash (Join-Path $root 'ffmpeg-n9.0.1.tar.gz')).Hash;
      PatchedSourceSha256=(Get-FileHash $sourcePath).Hash;Binary=$binary;BinarySha256=if(Test-Path $binary){(Get-FileHash $binary).Hash}else{$null};
      RecipeSha256=(Get-FileHash $PSCommandPath).Hash;ConfigurationSha256=if(Test-Path (Join-Path $src 'ffbuild/config.mak')){(Get-FileHash (Join-Path $src 'ffbuild/config.mak')).Hash}else{$null};
      Meaning='External FFmpeg 9.0.1 recorder built from prepared, pinned local prerequisites with one original-WGC-timestamp diagnostic and a generated dependency-command quoting adaptation. No game/engine/mixer algorithm is compiled. Compilation is not live capture qualification.'}|ConvertTo-Json -Depth 5|Set-Content $Output
}
$binary
