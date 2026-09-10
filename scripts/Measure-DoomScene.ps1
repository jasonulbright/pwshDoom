#requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Wad,
    [string]$Source = (Join-Path $PSScriptRoot '../local/upstream/nick-doom.ps1'),
    [ValidateRange(8,64)][int]$Samples = 16,
    [string]$Output = (Join-Path $PSScriptRoot '../results/doom-scene.json'),
    [switch]$Live
)
$ErrorActionPreference = 'Stop'
if ($Live -and (-not $env:WT_SESSION -or [Console]::IsOutputRedirected)) { throw '-Live requires an actual Windows Terminal window.' }
. "$PSScriptRoot/FrameCodec.ps1"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = Join-Path $root 'local/frames'
[void][IO.Directory]::CreateDirectory($cache)
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Output)))

# Test a pinned, separately acquired local renderer. No upstream source is vendored.
# Import only the inspected definitions; never run its interactive/network startup.
$expectedHash = '30624D2F6878FE6832997C1F2B65858E7C26BAC9A54A1C920BC06E649471E943'
if ((Get-FileHash -LiteralPath $Source).Hash -ne $expectedHash) { throw 'External renderer differs from the inspected revision. See docs/reproduce.md.' }
$tokens=$null; $parseErrors=$null
$ast = [Management.Automation.Language.Parser]::ParseFile((Resolve-Path -LiteralPath $Source).Path,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'External renderer has parse errors.' }
$required = @('Read-WadDirectory','Find-Lump','Read-Playpal','Read-Patch','Read-Pnames',
    'Read-TextureDefs','New-CompositeTexture','Read-Flat','Read-Colormap','Read-DoomMap',
    'Find-Subsector','Get-SubsectorSector','Get-BspFrame')
$definitions = $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)
foreach ($name in $required) {
    $matching = @($definitions | Where-Object Name -eq $name)
    if ($matching.Count -ne 1) { throw "Expected exactly one definition of $name." }
    . ([scriptblock]::Create($matching[0].Extent.Text))
}

$loadClock = [Diagnostics.Stopwatch]::StartNew()
$wadBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Wad).Path)
$directory = Read-WadDirectory $wadBytes
$level = Read-DoomMap $wadBytes $directory 'E1M1'
if (-not $level.hasStart) { throw 'E1M1 has no player start.' }
$rgb = Read-Playpal $wadBytes $directory
$colormap = Read-Colormap $wadBytes $directory
if ($rgb.Count -ne 768 -or $colormap.Count -ne 8704) { throw 'Required Doom palette/colormap unavailable.' }
$palette = [int[][]]::new(256)
for ($i=0;$i -lt 256;$i++) { $palette[$i] = @($rgb[$i*3],$rgb[$i*3+1],$rgb[$i*3+2]) }
$patchNames = Read-Pnames $wadBytes $directory
$textureDefs = Read-TextureDefs $wadBytes $directory
$textures = [Collections.Generic.List[object]]::new(); $textures.Add($null)
$textureSlots = @{'-'=0;''=0}
$wallNames = @($level.sideUpper) + @($level.sideLower) + @($level.sideMid) + @('SKY1')
foreach ($name in ($wallNames | Sort-Object -Unique)) {
    if ($textureSlots.ContainsKey($name)) { continue }
    if (-not $textureDefs.ContainsKey($name)) { throw "Missing texture $name." }
    $textureSlots[$name] = $textures.Count
    $textures.Add((New-CompositeTexture $wadBytes $directory $patchNames $textureDefs[$name]))
}
foreach ($pair in @(@('sideUpTex','sideUpper'),@('sideLoTex','sideLower'),@('sideMidTex','sideMid'))) {
    $indices = [int[]]::new($level.nSides)
    for ($i=0;$i -lt $indices.Length;$i++) { $indices[$i] = $textureSlots[$level[$pair[1]][$i]] }
    $level[$pair[0]] = $indices
}
$flats = [Collections.Generic.List[object]]::new(); $flats.Add($null)
$flatSlots = @{'F_SKY1'=0}
foreach ($name in ((@($level.secFloorTex)+@($level.secCeilTex)) | Sort-Object -Unique)) {
    if ($flatSlots.ContainsKey($name)) { continue }
    $flat = Read-Flat $wadBytes $directory $name
    if ($null -eq $flat) { throw "Missing flat $name." }
    $flatSlots[$name] = $flats.Count; $flats.Add($flat)
}
foreach ($pair in @(@('secFloorFlat','secFloorTex'),@('secCeilFlat','secCeilTex'))) {
    $indices = [int[]]::new($level.nSectors)
    for ($i=0;$i -lt $indices.Length;$i++) { $indices[$i] = $flatSlots[$level[$pair[1]][$i]] }
    $level[$pair[0]] = $indices
}
$level.secSky = [bool[]]::new($level.nSectors)
for ($i=0;$i -lt $level.nSectors;$i++) { $level.secSky[$i] = $level.secCeilTex[$i] -eq 'F_SKY1' }
$ss = Find-Subsector $level.startX $level.startY $level.nodeX $level.nodeY $level.nodeDX $level.nodeDY $level.nodeC0 $level.nodeC1 $level.nNodes
$sector = Get-SubsectorSector $ss $level.ssFirst $level.segLine $level.segSide $level.lineRight $level.lineLeft $level.sideSector
$loadClock.Stop()
$ctx = New-CodecContext $palette
$frequency = [Diagnostics.Stopwatch]::Frequency
$report = [ordered]@{
    RecordedUtc=[DateTime]::UtcNow.ToString('o'); PowerShell=$PSVersionTable.PSVersion.ToString();
    Executable=(Get-Process -Id $PID).Path; SourceRepository='https://github.com/nick0451/doom-powershell';
    SourceCommit='6b0072973cd08fb83edc521e834e4070cda4b0a5'; SourceSha256=$expectedHash;
    WadFileName=[IO.Path]::GetFileName($Wad); WadSha256=(Get-FileHash -LiteralPath $Wad).Hash;
    WadBytes=$wadBytes.Length; Map='E1M1'; LoadAndAssetSetupMs=$loadClock.Elapsed.TotalMilliseconds;
    Camera=@{X=$level.startX;Y=$level.startY;Z=$level.secFloor[$sector]+41;StartAngleRadians=$level.startA;Headings=8};
    Meaning='Headless external PowerShell BSP walls/flats/sky, eight headings at player start. No sprites, weapon, HUD, input, AI, audio, or gameplay test. Not displayed FPS.';
    Samples=$Samples;WarmupFrames=3;Results=@();LiveCases=@()
}
$newEntries = [Collections.Generic.List[object]]::new()
$stream = $null
$originalEncoding = [Console]::OutputEncoding
$esc = [char]27
try {
if ($Live) {
    [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
    $stream = [Console]::OpenStandardOutput()
    $report['OutputCodePage'] = [Console]::OutputEncoding.CodePage
    $report['OriginalOutputCodePage'] = $originalEncoding.CodePage
    $report['GridWidth'] = [Console]::WindowWidth
    $report['GridHeight'] = [Console]::WindowHeight
    if ($report.GridWidth -lt 320 -or $report.GridHeight -lt 103) { throw 'Terminal grid too small for 320x200 ANSI.' }
    $control = [Text.Encoding]::UTF8.GetBytes("$esc[?1049h$esc[?25l$esc[?7l$esc[2J")
    $stream.Write($control,0,$control.Length)
}
foreach ($size in @(@(147,92),@(320,200))) {
    $width,$height = $size
    $render = @{ptx=$level.startX;pty=$level.startY;ptz=$report.Camera.Z;pang=$level.startA;
        W=$width;vres=$height;horiz=[int]($height/2);hScale=$width/2.0;vScale=$width/2.0;quant=2;
        buf=[byte[]]::new($width*$height);ceilClip=[int[]]::new($width);floorClip=[int[]]::new($width);
        stack=[int[]]::new(256);rowInv=[double[]]::new($height);textures=$textures.ToArray();flats=$flats.ToArray();
        colormap=$colormap;skyTex=$textures[$textureSlots.SKY1];texMode=$true;DSMAX=1024;
        dsX1=[int[]]::new(1024);dsX2=[int[]]::new(1024);dsIz1=[double[]]::new(1024);dsIzStep=[double[]]::new(1024);
        dsSolid=[bool[]]::new(1024);dsTopZ=[double[]]::new(1024);dsBotZ=[double[]]::new(1024)}
    foreach ($key in 'vx','vy','segV1','segV2','segLine','segSide','segOffset','lineRight','lineLeft','lineFlags',
        'sideSector','sideXoff','sideYoff','sideUpTex','sideLoTex','sideMidTex','secFloor','secCeil','secLight',
        'secFloorFlat','secCeilFlat','secSky','ssCount','ssFirst','nodeX','nodeY','nodeDX','nodeDY','nodeC0','nodeC1','nNodes') {
        $render[$key] = $level[$key]
    }
    for ($y=0;$y -lt $height;$y++) {
        $distance = [Math]::Abs($render.horiz-$y)
        $render.rowInv[$y] = if ($distance -eq 0) { 32000.0 } else { $render.vScale/$distance }
    }
    for ($warm=0;$warm -lt 3;$warm++) { $null = Get-BspFrame @render }
    $renderMs = [double[]]::new($Samples)
    $buffers = [Collections.Generic.List[byte[]]]::new()
    for ($i=0;$i -lt $Samples;$i++) {
        $render.pang = $level.startA + ($i % 8)*[Math]::PI/4
        $start = [Diagnostics.Stopwatch]::GetTimestamp()
        [Array]::Clear($render.buf)
        $null = Get-BspFrame @render
        $renderMs[$i] = ([Diagnostics.Stopwatch]::GetTimestamp()-$start)*1000.0/$frequency
        if ($i -lt 8) { $buffers.Add($render.buf.Clone()) }
    }
    foreach ($codec in 'AnsiFast','Sixel','SixelFast') {
        $id = "$codec-${width}x${height}-Doom-E1M1"
        $encoder = "ConvertTo-${codec}Frame"
        for ($warm=0;$warm -lt 3;$warm++) { $null = & $encoder $buffers[0] $width $height $ctx }
        $encodeMs = [double[]]::new($Samples); $bytes = [double[]]::new($Samples)
        $files = [Collections.Generic.List[string]]::new()
        for ($i=0;$i -lt $Samples;$i++) {
            $start = [Diagnostics.Stopwatch]::GetTimestamp()
            $encoded = [Text.Encoding]::UTF8.GetBytes((& $encoder $buffers[$i % 8] $width $height $ctx))
            $encodeMs[$i] = ([Diagnostics.Stopwatch]::GetTimestamp()-$start)*1000.0/$frequency
            $bytes[$i] = $encoded.Length
            if ($i -lt 8) {
                $file = "$id-$i.bin"; [IO.File]::WriteAllBytes((Join-Path $cache $file),$encoded); $files.Add($file)
            }
        }
        $entry = @{Id=$id;Width=$width;Height=$height;Codec=$codec;RenderMs=(Get-SampleStats $renderMs);
            EncodingIncludingUtf8Ms=(Get-SampleStats $encodeMs);Bytes=(Get-SampleStats $bytes);
            RenderSamplesMs=$renderMs;EncodingSamplesMs=$encodeMs;ByteSamples=$bytes}
        $report.Results += $entry
        # Manifest records the output protocol, not which implementation produced it.
        $newEntries.Add(@{Id=$id;Codec=$(if ($codec -eq 'AnsiFast') {'Ansi'} else {'Sixel'});
            Width=$width;Height=$height;Colors=256;Pattern='Doom-E1M1';Files=$files.ToArray()})
        Write-Host ('{0}: render {1:N2} ms; encode {2:N2} ms; {3:N0} bytes' -f $id,$entry.RenderMs.Median,$entry.EncodingIncludingUtf8Ms.Median,$entry.Bytes.Median)
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
    }
    if ($Live) {
        foreach ($repeat in 1,2) {
            $order = if ($repeat -eq 1) { @('AnsiFast','Sixel','SixelFast') } else { @('SixelFast','Sixel','AnsiFast') }
            foreach ($codec in $order) {
                $encoder = "ConvertTo-${codec}Frame"
                $control = [Text.Encoding]::UTF8.GetBytes("$esc[?2026l$esc[0m$esc[2J")
                $stream.Write($control,0,$control.Length)
                Start-Sleep -Milliseconds 700
                $costs = [Collections.Generic.List[object]]::new()
                $totalBytes = [long]0
                $start = [Diagnostics.Stopwatch]::GetTimestamp()
                $frameNumber = 0
                while (([Diagnostics.Stopwatch]::GetTimestamp()-$start)/[double]$frequency -lt 4) {
                    $before = [Diagnostics.Stopwatch]::GetTimestamp()
                    $render.pang = $level.startA + ($frameNumber % 8)*[Math]::PI/4
                    [Array]::Clear($render.buf)
                    $null = Get-BspFrame @render
                    $afterRender = [Diagnostics.Stopwatch]::GetTimestamp()
                    $text = & $encoder $render.buf $width $height $ctx
                    $payload = [Text.Encoding]::UTF8.GetBytes("$esc[?2026h$esc[0m$esc[1;1HE1M1 $codec ${width}x${height} phase=$($frameNumber % 8)$esc[K$esc[3;1H$text$esc[0m$esc[?2026l")
                    $afterEncode = [Diagnostics.Stopwatch]::GetTimestamp()
                    $stream.Write($payload,0,$payload.Length)
                    $afterWrite = [Diagnostics.Stopwatch]::GetTimestamp()
                    $costs.Add(@{Render=($afterRender-$before)*1000.0/$frequency;
                        Encode=($afterEncode-$afterRender)*1000.0/$frequency;Write=($afterWrite-$afterEncode)*1000.0/$frequency})
                    $totalBytes += $payload.Length
                    $frameNumber++
                }
                $elapsed = ([Diagnostics.Stopwatch]::GetTimestamp()-$start)/[double]$frequency
                $report.LiveCases += @{Codec=$codec;Width=$width;Height=$height;Repeat=$repeat;Sync=$true;
                    CompletedWrites=$frameNumber;ElapsedSeconds=$elapsed;CompletedWritesPerSecond=$frameNumber/$elapsed;
                    BytesWritten=$totalBytes;RenderMs=(Get-SampleStats @($costs | ForEach-Object Render));
                    EncodingIncludingUtf8Ms=(Get-SampleStats @($costs | ForEach-Object Encode));
                    WriteMs=(Get-SampleStats @($costs | ForEach-Object Write));Samples=$costs.ToArray()}
                $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
            }
        }
    }
    # An offline image verifies the renderer buffer, not the Terminal presentation.
    Add-Type -AssemblyName System.Drawing
    $bitmap = [Drawing.Bitmap]::new($width,$height)
    try {
        for ($y=0;$y -lt $height;$y++) { for ($x=0;$x -lt $width;$x++) {
            $color = $palette[$buffers[0][$y*$width+$x]]
            $bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb($color[0],$color[1],$color[2]))
        } }
        $bitmap.Save((Join-Path $root "local/doom-e1m1-${width}x${height}.png"),[Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
}
$manifestPath = Join-Path $cache 'manifest.json'
$existing = if (Test-Path -LiteralPath $manifestPath) { @(Get-Content -Raw $manifestPath | ConvertFrom-Json | Where-Object Id -NotLike '*-Doom-E1M1') } else { @() }
@($existing + $newEntries.ToArray()) | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath
$report['FinishedUtc'] = [DateTime]::UtcNow.ToString('o')
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
} finally {
    if ($null -ne $stream) {
        $control = [Text.Encoding]::UTF8.GetBytes("$esc[?2026l$esc[0m$esc[?7h$esc[?25h$esc[?1049l")
        $stream.Write($control,0,$control.Length)
        $stream.Dispose()
        [Console]::OutputEncoding = $originalEncoding
    }
}
