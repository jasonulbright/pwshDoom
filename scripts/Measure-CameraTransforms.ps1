#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Wad,
    [ValidateRange(8,256)][int]$Samples = 64,
    [ValidateRange(1,64)][int]$BatchesPerSample = 16,
    [string]$Output = (Join-Path $PSScriptRoot '../results/camera-transforms.json')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot/FrameCodec.ps1"
$scene = & "$PSScriptRoot/Measure-DoomScene.ps1" -Wad $Wad -InitializeOnly
$level = $scene.Level
[double[]]$vx = $level.vx
[double[]]$vy = $level.vy
$points = [Numerics.Vector2[]]::new($vx.Length)
for ($i=0; $i -lt $vx.Length; $i++) {
    $points[$i] = [Numerics.Vector2]::new($vx[$i], $vy[$i])
}
$data = @{
    X=$vx; Y=$vy; Points=$points; CameraX=[double]$level.startX; CameraY=[double]$level.startY;
    Depth=[double[]]::new($vx.Length); Lateral=[double[]]::new($vx.Length)
}

# Every candidate writes the same two preallocated double arrays. Matrix setup
# and field extraction are included; caching immutable input vectors is setup.
# No custom compiled helper or external Matrix module is executed.
$methods = [ordered]@{
    ScalarRelative = {
        param($data, [double]$angle)
        [double[]]$x=$data.X; [double[]]$y=$data.Y
        [double[]]$depth=$data.Depth; [double[]]$lateral=$data.Lateral
        [double]$px=$data.CameraX; [double]$py=$data.CameraY
        [double]$c=[Math]::Cos($angle); [double]$s=[Math]::Sin($angle)
        for ([int]$i=0; $i -lt $x.Length; $i++) {
            [double]$dx=$x[$i]-$px; [double]$dy=$y[$i]-$py
            $depth[$i]=$dx*$c+$dy*$s
            $lateral[$i]=$dx*$s-$dy*$c
        }
    }
    ScalarAffine = {
        param($data, [double]$angle)
        [double[]]$x=$data.X; [double[]]$y=$data.Y
        [double[]]$depth=$data.Depth; [double[]]$lateral=$data.Lateral
        [double]$px=$data.CameraX; [double]$py=$data.CameraY
        [double]$c=[Math]::Cos($angle); [double]$s=[Math]::Sin($angle)
        [double]$tx=-$px*$c-$py*$s; [double]$ty=-$px*$s+$py*$c
        for ([int]$i=0; $i -lt $x.Length; $i++) {
            $depth[$i]=$x[$i]*$c+$y[$i]*$s+$tx
            $lateral[$i]=$x[$i]*$s-$y[$i]*$c+$ty
        }
    }
    MatrixCachedVectors = {
        param($data, [double]$angle)
        [Numerics.Vector2[]]$points=$data.Points
        [double[]]$depth=$data.Depth; [double[]]$lateral=$data.Lateral
        [double]$px=$data.CameraX; [double]$py=$data.CameraY
        [double]$c=[Math]::Cos($angle); [double]$s=[Math]::Sin($angle)
        # System.Numerics uses row vectors. X becomes depth, Y becomes right.
        $matrix=[Numerics.Matrix3x2]::new($c,$s,$s,-$c,(-$px*$c-$py*$s),(-$px*$s+$py*$c))
        for ([int]$i=0; $i -lt $points.Length; $i++) {
            $point=[Numerics.Vector2]::Transform($points[$i],$matrix)
            $depth[$i]=$point.X; $lateral[$i]=$point.Y
        }
    }
    MatrixNewVectors = {
        param($data, [double]$angle)
        [double[]]$x=$data.X; [double[]]$y=$data.Y
        [double[]]$depth=$data.Depth; [double[]]$lateral=$data.Lateral
        [double]$px=$data.CameraX; [double]$py=$data.CameraY
        [double]$c=[Math]::Cos($angle); [double]$s=[Math]::Sin($angle)
        $matrix=[Numerics.Matrix3x2]::new($c,$s,$s,-$c,(-$px*$c-$py*$s),(-$px*$s+$py*$c))
        for ([int]$i=0; $i -lt $x.Length; $i++) {
            $point=[Numerics.Vector2]::Transform([Numerics.Vector2]::new($x[$i],$y[$i]),$matrix)
            $depth[$i]=$point.X; $lateral[$i]=$point.Y
        }
    }
    MatrixTypedVectors = {
        param($data, [double]$angle)
        [Numerics.Vector2[]]$points=$data.Points
        [double[]]$depth=$data.Depth; [double[]]$lateral=$data.Lateral
        [double]$px=$data.CameraX; [double]$py=$data.CameraY
        [double]$c=[Math]::Cos($angle); [double]$s=[Math]::Sin($angle)
        [Numerics.Matrix3x2]$matrix=[Numerics.Matrix3x2]::new($c,$s,$s,-$c,(-$px*$c-$py*$s),(-$px*$s+$py*$c))
        [Numerics.Vector2]$point=[Numerics.Vector2]::Zero
        for ([int]$i=0; $i -lt $points.Length; $i++) {
            $point=[Numerics.Vector2]::Transform($points[$i],$matrix)
            $depth[$i]=$point.X; $lateral[$i]=$point.Y
        }
    }
}
$names = @($methods.Keys)
$times = @{}; $errors = @{}
foreach ($name in $names) {
    $times[$name] = [double[]]::new($Samples)
    $errors[$name] = 0.0
}
# Non-cardinal headings exercise actual floating-point rotation, not just 0/1.
$angles = [double[]]::new(8)
for ($h=0; $h -lt 8; $h++) { $angles[$h]=$level.startA+0.137+$h*[Math]::PI/4 }
foreach ($angle in $angles) {
    & $methods.ScalarRelative $data $angle
    $referenceD=[double[]]$data.Depth.Clone(); $referenceL=[double[]]$data.Lateral.Clone()
    foreach ($name in $names) {
        [Array]::Fill($data.Depth,[double]::NaN); [Array]::Fill($data.Lateral,[double]::NaN)
        & $methods[$name] $data $angle
        for ($i=0; $i -lt $vx.Length; $i++) {
            if (-not [double]::IsFinite($data.Depth[$i]) -or -not [double]::IsFinite($data.Lateral[$i])) {
                throw "Unwritten or non-finite coordinate in $name at $i"
            }
            $coordinateError=[Math]::Max([Math]::Abs($data.Depth[$i]-$referenceD[$i]),[Math]::Abs($data.Lateral[$i]-$referenceL[$i]))
            $errors[$name]=[Math]::Max($errors[$name],$coordinateError)
        }
        $tolerance=if ($name.StartsWith('Matrix')) { 0.01 } else { 1e-8 }
        if ($errors[$name] -gt $tolerance) { throw "Transform mismatch in $name : $($errors[$name])" }
    }
}
for ($warm=0; $warm -lt 64; $warm++) {
    foreach ($name in $names) { & $methods[$name] $data $angles[$warm%8] }
}
# Rotate the method order to reduce fixed-order effects. Each sample times
# several complete map transformations; no console output occurs in the loop.
for ($sample=0; $sample -lt $Samples; $sample++) {
    for ($order=0; $order -lt $names.Count; $order++) {
        $name=$names[($sample+$order)%$names.Count]
        $method=$methods[$name]; $angle=$angles[$sample%8]
        $watch=[Diagnostics.Stopwatch]::StartNew()
        for ($batch=0; $batch -lt $BatchesPerSample; $batch++) { & $method $data $angle }
        $watch.Stop()
        $times[$name][$sample]=$watch.Elapsed.TotalMilliseconds/$BatchesPerSample
    }
}
$report = [ordered]@{
    RecordedUtc=[DateTime]::UtcNow.ToString('o'); PowerShell=$PSVersionTable.PSVersion.ToString();
    Runtime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;
    Executable=(Get-Process -Id $PID).Path; WadSha256=$scene.WadSha256; SourceSha256=$scene.SourceSha256;
    Map='E1M1'; VerticesPerBatch=$vx.Length; CameraX=$data.CameraX; CameraY=$data.CameraY;
    AnglesRadians=$angles; Samples=$Samples; BatchesPerSample=$BatchesPerSample; WarmupBatchesPerMethod=64;
    Meaning='Single-process coordinate-only microbenchmark over every E1M1 vertex. Includes camera setup and two double-array writes per point. Excludes loading, culling, projection, rasterization, encoding, IPC, terminal output, gameplay. Not frame times or FPS. The Matrix module was not benchmarked. Matrix3x2 and Vector2 use single precision.';
    Results=@()
}
foreach ($name in $names) {
    $report.Results += [ordered]@{
        Method=$name; MillisecondsPerMapTransform=(Get-SampleStats $times[$name]);
        MaxAbsoluteCoordinateErrorVsScalar=$errors[$name]; SamplesMsPerMapTransform=$times[$name]
    }
}
$report['FinishedUtc']=[DateTime]::UtcNow.ToString('o')
$destination=[IO.Path]::GetFullPath($Output)
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $destination -Encoding utf8
$report.Results | ForEach-Object {
    [pscustomobject]@{
        Method=$_.Method; MedianMs=$_.MillisecondsPerMapTransform.Median;
        MaxAbsoluteCoordinateErrorVsScalar=$_.MaxAbsoluteCoordinateErrorVsScalar
    }
}
