#requires -Version 7.4
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$ctx=New-CodecContext (New-TestPalette 256)
$rows=@()
foreach ($pattern in 'Coherent','Entropy') {
    $pixels=New-IndexedFrame 320 200 5 $pattern 256
    $original=ConvertTo-AnsiFrame $pixels 320 200 $ctx
    $optimized=ConvertTo-AnsiFastFrame $pixels 320 200 $ctx
    if ($original -cne $optimized) { throw 'Optimized encoder changed the output stream.' }
    for ($warm=0;$warm -lt 3;$warm++) { $null=ConvertTo-AnsiFastFrame $pixels 320 200 $ctx }
    foreach ($name in 'Ansi','AnsiFast') {
        $samples=[double[]]::new(16)
        for ($i=0;$i -lt $samples.Length;$i++) {
            $sw=[Diagnostics.Stopwatch]::StartNew()
            $text=& "ConvertTo-${name}Frame" $pixels 320 200 $ctx
            $bytes=[Text.Encoding]::UTF8.GetBytes($text)
            $samples[$i]=$sw.Elapsed.TotalMilliseconds
        }
        $rows+=@{Encoder=$name;Pattern=$pattern;Width=320;Height=200;Colors=256;EncodingIncludingUtf8Ms=(Get-SampleStats $samples);SamplesMs=$samples;Bytes=$bytes.Length}
    }
}
@{RecordedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();OutputVerifiedByteEquivalent=$true;Results=$rows} | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath "$PSScriptRoot/../results/ansi-optimization.json"
$rows | ForEach-Object { '{0} {1}: {2:N2} ms' -f $_.Encoder,$_.Pattern,$_.EncodingIncludingUtf8Ms.Median }
