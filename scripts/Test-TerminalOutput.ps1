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
$contexts=@{Strips=(New-DoomTerminalOutputContext);Batch=(New-DoomTerminalOutputContext);AsyncBatch=(New-DoomTerminalOutputContext)}
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
                foreach($mode in 'Strips','Batch','AsyncBatch'){
                    $stream=[IO.MemoryStream]::new();$context=$contexts[$mode]
                    try{
                        if($mode -eq 'AsyncBatch'){
                            $job=Start-DoomTerminalFrame $context $stream $strips $start $end $clear $status
                            $rejected=$false;try{$null=Start-DoomTerminalFrame $context $stream $strips $start $end}catch{$rejected=$true}
                            if(-not $rejected){throw 'Pending write did not retain exclusive buffer ownership.'}
                            foreach($syncMode in 'Strips','Batch'){
                                $rejected=$false;try{Write-DoomTerminalFrame $context $stream $strips $start $end -Mode $syncMode}catch{$rejected=$true}
                                if(-not $rejected){throw 'Synchronous output interleaved with a pending asynchronous frame.'}
                            }
                            $done=Complete-DoomTerminalFrame $context $stream -Wait
                            if(-not [object]::ReferenceEquals($done,$job) -or $null -ne $context.Pending){throw 'Asynchronous completion ownership differs.'}
                        }else{Write-DoomTerminalFrame $context $stream $strips $start $end $clear $status -Mode $mode}
                        if([Convert]::ToBase64String($stream.ToArray()) -cne [Convert]::ToBase64String($expected)){throw "$mode output differs: $style/$width/$decorations"}
                        if($context.Bytes -ne $total -or $context.Frames -ne $frames){throw 'Output accounting differs.'}
                        $expectedWrites=$expectedStripWrites;if($mode -ne 'Strips'){$expectedWrites=$frames}
                        if($context.Writes -ne $expectedWrites){throw 'Write-call accounting differs.'}
                        $checks.Add(@{Style=$style;Width=$width;Height=$height;Pattern=$fixture.Pattern;Decorations=$decorations;Mode=$mode;ComparedBytes=$expected.Length;Capacity=$context.Buffer.Length;Passed=$true})
                    }finally{$stream.Dispose()}
                }
            }
        }
    }
    # A real asynchronous pipe supplies bounded backpressure that a memory
    # stream cannot exercise. No custom stream/helper implementation is used.
    $pipeName='pwshDoom-output-'+[guid]::NewGuid().ToString('N')
    $server=[IO.Pipes.NamedPipeServerStream]::new($pipeName,[IO.Pipes.PipeDirection]::Out,1,[IO.Pipes.PipeTransmissionMode]::Byte,[IO.Pipes.PipeOptions]::Asynchronous,4096,4096)
    $client=[IO.Pipes.NamedPipeClientStream]::new('.',$pipeName,[IO.Pipes.PipeDirection]::In,[IO.Pipes.PipeOptions]::Asynchronous)
    try{
        $connect=$server.WaitForConnectionAsync();$client.Connect(2000);[void]$connect.GetAwaiter().GetResult()
        $payload=[byte[]]::new(2MB);for($i=0;$i -lt $payload.Length;$i+=256){$payload[$i]=[byte](($i/256)%256)}
        $context=New-DoomTerminalOutputContext
        $job=Start-DoomTerminalFrame $context $server @(@{Bytes=$payload}) $start $end
        if($job.Task.IsCompleted -or $context.Frames -ne 0 -or $context.Bytes -ne 0){throw 'Blocked write was reported as completed.'}
        if($null -ne (Complete-DoomTerminalFrame $context $server)){throw 'Polling blocked output falsely completed it.'}
        $expected=[byte[]]::new($start.Length+$payload.Length+$end.Length)
        [Buffer]::BlockCopy($start,0,$expected,0,$start.Length);[Buffer]::BlockCopy($payload,0,$expected,$start.Length,$payload.Length)
        [Buffer]::BlockCopy($end,0,$expected,$start.Length+$payload.Length,$end.Length)
        $actual=[byte[]]::new($expected.Length);$offset=0
        while($offset -lt $actual.Length){
            $read=$client.ReadAsync($actual,$offset,$actual.Length-$offset)
            if(-not $read.Wait(5000)){throw 'Pipe fixture read timed out.'}
            $count=$read.GetAwaiter().GetResult();if($count -le 0){throw 'Pipe fixture ended early.'};$offset+=$count
        }
        $done=Complete-DoomTerminalFrame $context $server -Wait
        if(-not [Linq.Enumerable]::SequenceEqual([byte[]]$expected,[byte[]]$actual)){throw 'Backpressured output bytes differ.'}
        if($context.Frames -ne 1 -or $context.Bytes -ne $actual.Length -or $context.Writes -ne 1){throw 'Backpressured completion accounting differs.'}
        $checks.Add(@{Style='Transport';Mode='AsyncBatch';Fixture='Bounded named-pipe backpressure';ComparedBytes=$actual.Length;Passed=$true})
        $job=Start-DoomTerminalFrame $context $server @(@{Bytes=$payload}) $start $end
        $client.Dispose();$rejected=$false
        try{$null=Complete-DoomTerminalFrame $context $server -Wait}catch{$rejected=$true}
        if(-not $rejected -or $context.Frames -ne 1){throw 'Failed output was counted as a completed frame.'}
        $checks.Add(@{Style='Transport';Mode='AsyncBatch';Fixture='Broken pipe propagates failure without counting a frame';Passed=$true})
    }finally{$client.Dispose();$server.Dispose()}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();FramesPerMode=$frames;BytesPerMode=$total;
        Sources=@('scripts/Test-TerminalOutput.ps1','scripts/FrameCodec.ps1','src/TerminalCodec.ps1','src/CharacterCodec.ps1','src/TerminalOutput.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});
        Meaning='Byte-exact comparison to the original stream-write sequence using actual Classic/Matrix/AnsiArt katakana codecs, seven uneven strips, viewport offsets, clear/status combinations and reused growing/shrinking buffers. AsyncBatch also requires exclusive buffer ownership, correct pending/completed accounting and real bounded named-pipe backpressure/failure propagation. No terminal throughput or displayed-FPS claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) terminal byte-stream comparisons."
