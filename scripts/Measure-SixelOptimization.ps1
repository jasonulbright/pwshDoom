#requires -Version 7.4
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$rows=@()
foreach($colors in 16,256) {
    $ctx=New-CodecContext (New-TestPalette $colors)
    foreach($pattern in 'Coherent','Entropy') {
        $pixels=New-IndexedFrame 320 200 5 $pattern $colors
        foreach($name in 'Sixel','SixelFast') {
            for($warm=0;$warm -lt 3;$warm++) { $null=& "ConvertTo-${name}Frame" $pixels 320 200 $ctx }
            $samples=[double[]]::new(12)
            for($i=0;$i -lt $samples.Length;$i++) {
                $sw=[Diagnostics.Stopwatch]::StartNew()
                $text=& "ConvertTo-${name}Frame" $pixels 320 200 $ctx
                $bytes=[Text.Encoding]::UTF8.GetBytes($text)
                $samples[$i]=$sw.Elapsed.TotalMilliseconds
            }
            $rows+=@{Encoder=$name;Pattern=$pattern;Width=320;Height=200;Colors=$colors;
                EncodingIncludingUtf8Ms=(Get-SampleStats $samples);SamplesMs=$samples;Bytes=$bytes.Length}
            '{0} {1} {2}: {3:N2} ms, {4:N0} bytes' -f $name,$colors,$pattern,($rows[-1].EncodingIncludingUtf8Ms.Median),$bytes.Length
        }
    }
}
@{RecordedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
    Meaning='Uncompressed Sixel trades stream size for less PowerShell work. Raster pixels independently round-trip checked.';
    Results=$rows} | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath "$PSScriptRoot/../results/sixel-optimization.json"
