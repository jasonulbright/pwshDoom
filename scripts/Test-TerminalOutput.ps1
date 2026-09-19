#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/FrameCodec.ps1"
. "$PSScriptRoot/../src/TerminalCodec.ps1"
. "$PSScriptRoot/../src/CharacterCodec.ps1"
. "$PSScriptRoot/../src/TerminalOutput.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null
$esc=[char]27;$utf8=[Text.Encoding]::UTF8
$start=$utf8.GetBytes("$esc[?2026h");$end=$utf8.GetBytes("$esc[0m$esc[?2026l")
$contexts=@{Strips=(New-DoomTerminalOutputContext);Batch=(New-DoomTerminalOutputContext)}
$total=0L;$frames=0L;$expectedStripWrites=0L
try{
    $palette=New-TestPalette -Count 256;$classic=New-CodecContext $palette
    foreach($style in 'Classic','Matrix','AnsiArt'){
        $codec=$classic
        if($style -ne 'Classic'){$codec=New-CharacterCodecContext $palette $style -GlyphSet Katakana}
        # Large, then much smaller, then coherent: exercise growth and stale-tail reuse.
        foreach($fixture in @(@{Width=320;Height=200;Pattern='Entropy'},@{Width=64;Height=40;Pattern='Coherent'},@{Width=320;Height=200;Pattern='Coherent'})){
            $width=$fixture.Width;$height=$fixture.Height
            $pixels=New-IndexedFrame $width $height -Phase 7 -Pattern $fixture.Pattern -Colors 256
            $strips=@(for($i=0;$i -lt 7;$i++){
                $first=2*[int][Math]::Floor($i*($width/2)/7);$last=2*[int][Math]::Floor(($i+1)*($width/2)/7)
                $bytes=if($style -eq 'Classic'){ConvertTo-AnsiStrip $pixels $width $height $first $last $codec -ColumnOffset 17 -RowOffset 5}
                    else{ConvertTo-CharacterStrip $pixels $width $height $first $last $codec -ColumnOffset 17 -RowOffset 5 -FrameNumber 123 -HudStart ($height-32)}
                @{Bytes=$bytes}
            })
            foreach($decorations in 0,1,2,3){
                [byte[]]$clear=[byte[]]::new(0);[byte[]]$status=[byte[]]::new(0)
                if($decorations -band 1){$clear=$utf8.GetBytes("$esc[0m$esc[2J")}
                if($decorations -band 2){$status=$utf8.GetBytes("$esc[108;18Hdiagnostics: $([char]0xff76)$([char]0xff80)$([char]0xff76)$([char]0xff85)$esc[K")}
                # Independent oracle: the original direct stream-write sequence.
                $reference=[IO.MemoryStream]::new()
                try{
                    $reference.Write($start,0,$start.Length)
                    if($clear.Length){$reference.Write($clear,0,$clear.Length)}
                    foreach($strip in $strips){$reference.Write($strip.Bytes,0,$strip.Bytes.Length)}
                    if($status.Length){$reference.Write($status,0,$status.Length)}
                    $reference.Write($end,0,$end.Length);$reference.Flush()
                    $expected=$reference.ToArray()
                }finally{$reference.Dispose()}
                $total+=$expected.Length;$frames++;$expectedStripWrites+=9+[int]($clear.Length -gt 0)+[int]($status.Length -gt 0)
                foreach($mode in 'Strips','Batch'){
                    $stream=[IO.MemoryStream]::new();$context=$contexts[$mode]
                    try{
                        Write-DoomTerminalFrame $context $stream $strips $start $end $clear $status -Mode $mode
                        if([Convert]::ToBase64String($stream.ToArray()) -cne [Convert]::ToBase64String($expected)){throw "$mode output differs: $style/$width/$decorations"}
                        if($context.Bytes -ne $total -or $context.Frames -ne $frames){throw 'Output accounting differs.'}
                        $expectedWrites=$expectedStripWrites;if($mode -eq 'Batch'){$expectedWrites=$frames}
                        if($context.Writes -ne $expectedWrites){throw 'Write-call accounting differs.'}
                        $checks.Add(@{Style=$style;Width=$width;Height=$height;Pattern=$fixture.Pattern;Decorations=$decorations;Mode=$mode;ComparedBytes=$expected.Length;Capacity=$context.Buffer.Length;Passed=$true})
                    }finally{$stream.Dispose()}
                }
            }
        }
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();FramesPerMode=$frames;BytesPerMode=$total;
        Sources=@('scripts/Test-TerminalOutput.ps1','scripts/FrameCodec.ps1','src/TerminalCodec.ps1','src/CharacterCodec.ps1','src/TerminalOutput.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});
        Meaning='Byte-exact comparison to the original stream-write sequence using actual Classic/Matrix/AnsiArt katakana codecs, seven uneven strips, viewport offsets, clear/status combinations and reused growing/shrinking buffers. Memory-stream correctness only; no terminal throughput or displayed-FPS claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) terminal byte-stream comparisons."
