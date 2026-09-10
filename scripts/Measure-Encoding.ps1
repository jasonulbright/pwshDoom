#requires -Version 7.4
[CmdletBinding()]
param([int]$Samples = 12, [int]$CacheFrames = 8,
    [string]$Output = (Join-Path $PSScriptRoot '../results/encoding.json'))
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cache = Join-Path $root 'local/frames'
[void][IO.Directory]::CreateDirectory($cache)
$results = [Collections.Generic.List[object]]::new()
$manifest = [Collections.Generic.List[object]]::new()
$frequency = [Diagnostics.Stopwatch]::Frequency
foreach ($colors in 16,256) {
    $ctx = New-CodecContext (New-TestPalette $colors)
    foreach ($size in @(@(160,100),@(320,200))) {
        $w,$h = $size
        foreach ($pattern in 'Coherent','Entropy') {
            foreach ($codec in 'Ansi','Sixel') {
                $id = "$codec-${w}x${h}-$colors-$pattern"
                $function = "ConvertTo-${codec}Frame"
                $pixels = New-IndexedFrame $w $h 0 $pattern $colors
                for ($warm = 0; $warm -lt 3; $warm++) { $null = & $function $pixels $w $h $ctx }
                $generation = [double[]]::new($Samples)
                $encoding = [double[]]::new($Samples)
                $bytes = [double[]]::new($Samples)
                $files = [Collections.Generic.List[string]]::new()
                for ($i = 0; $i -lt $Samples; $i++) {
                    $start = [Diagnostics.Stopwatch]::GetTimestamp()
                    $pixels = New-IndexedFrame $w $h $i $pattern $colors
                    $afterGenerate = [Diagnostics.Stopwatch]::GetTimestamp()
                    $encoded = & $function $pixels $w $h $ctx
                    $utf8 = [Text.Encoding]::UTF8.GetBytes($encoded)
                    $afterEncode = [Diagnostics.Stopwatch]::GetTimestamp()
                    $generation[$i] = ($afterGenerate - $start) * 1000.0 / $frequency
                    $encoding[$i] = ($afterEncode - $afterGenerate) * 1000.0 / $frequency
                    $bytes[$i] = $utf8.Length
                    if ($i -lt $CacheFrames) {
                        $file = "$id-$i.bin"
                        [IO.File]::WriteAllBytes((Join-Path $cache $file), $utf8)
                        $files.Add($file)
                    }
                }
                $item = [ordered]@{ Id=$id; Codec=$codec; Width=$w; Height=$h; Colors=$colors; Pattern=$pattern;
                    GenerationMs=(Get-SampleStats $generation); EncodingIncludingUtf8Ms=(Get-SampleStats $encoding);
                    Bytes=(Get-SampleStats $bytes); GenerationSamplesMs=$generation; EncodingSamplesMs=$encoding }
                $results.Add($item)
                $manifest.Add(@{Id=$id;Codec=$codec;Width=$w;Height=$h;Colors=$colors;Pattern=$pattern;Files=$files.ToArray()})
                Write-Host ('{0}: generate {1:N2} ms, encode {2:N2} ms, {3:N0} bytes' -f $id,$item.GenerationMs.Median,$item.EncodingIncludingUtf8Ms.Median,$item.Bytes.Median)
            }
        }
    }
}
$report = [ordered]@{ RecordedUtc=[DateTime]::UtcNow.ToString('o'); PowerShell=$PSVersionTable.PSVersion.ToString();
    Executable=(Get-Process -Id $PID).Path; Samples=$Samples; WarmupFrames=3; SecuritySettingsChanged=$false;
    Meaning='Headless costs, not displayed FPS. Context/palette construction excluded. Encoder includes UTF-8 conversion.'; Results=$results.ToArray() }
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Output
$manifest.ToArray() | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $cache 'manifest.json')
