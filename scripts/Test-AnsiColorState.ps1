#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh evidence path.'}
. "$PSScriptRoot/FrameCodec.ps1"
. "$PSScriptRoot/../src/TerminalCodec.ps1"
. "$PSScriptRoot/../src/AnsiColorState.ps1"
$checks=[Collections.Generic.List[object]]::new();$samples=[Collections.Generic.List[object]]::new();$content=$null;$failure=$null
$sources=@('scripts/Test-AnsiColorState.ps1','scripts/FrameCodec.ps1','src/TerminalCodec.ps1','src/AnsiColorState.ps1','src/FastRenderer.ps1','src/RenderLighting.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}})
function Decode-TrueColor([byte[]]$Bytes,[int]$Width,[int]$Height,[int]$Left,[int]$Top){
    $text=[Text.Encoding]::UTF8.GetString($Bytes);$pixels=[int[]]::new($Width*$Height);[Array]::Fill($pixels,-1)
    $fg=-1;$bg=-1;$x=0;$y=0;$consumed=0;$fgOnly=0;$bgOnly=0;$both=0
    foreach($m in [regex]::Matches($text,"$([char]27)\[([0-9;]+)([Hm])|$([char]0x2580)")){
        if($m.Index -ne $consumed){throw 'Unrecognized output byte sequence.'};$consumed+=$m.Length
        if($m.Groups[2].Value -ceq 'H'){
            $v=[int[]]$m.Groups[1].Value.Split(';');if($v.Count -ne 2){throw 'Unexpected cursor sequence.'}
            $x=$v[1]-1-$Left;$y=2*($v[0]-1-$Top)
        }elseif($m.Groups[2].Value -ceq 'm'){
            $v=[int[]]$m.Groups[1].Value.Split(';');$changedFg=$false;$changedBg=$false
            for($i=0;$i -lt $v.Length;$i+=5){
                if($i+4 -ge $v.Length -or $v[$i] -notin 38,48 -or $v[$i+1] -ne 2){throw 'Unexpected SGR instruction.'}
                for($j=2;$j -le 4;$j++){if($v[$i+$j] -lt 0 -or $v[$i+$j] -gt 255){throw 'Color component out of range.'}}
                $rgb=($v[$i+2] -shl 16) -bor ($v[$i+3] -shl 8) -bor $v[$i+4]
                if($v[$i] -eq 38){$fg=$rgb;$changedFg=$true}else{$bg=$rgb;$changedBg=$true}
            }
            if($changedFg -and $changedBg){$both++}elseif($changedFg){$fgOnly++}elseif($changedBg){$bgOnly++}
        }else{
            if($fg -lt 0 -or $bg -lt 0 -or $x -lt 0 -or $x -ge $Width -or $y -lt 0 -or $y -ge $Height){throw 'Uninitialized color or out-of-image write.'}
            $index=$y*$Width+$x;if($pixels[$index] -ne -1){throw 'A pixel was painted twice.'};$pixels[$index]=$fg
            if($y+1 -lt $Height){if($pixels[$index+$Width] -ne -1){throw 'A bottom pixel was painted twice.'};$pixels[$index+$Width]=$bg};$x++
        }
    }
    if($consumed -ne $text.Length){throw 'Output has an unrecognized suffix.'}
    return @{Pixels=$pixels;ForegroundOnly=$fgOnly;BackgroundOnly=$bgOnly;Both=$both}
}
function Encode-Parts($Frame,[int]$Parts,[string]$Mode){
    $stream=[IO.MemoryStream]::new()
    try{
        for($i=0;$i -lt $Parts;$i++){
            $first=[int][Math]::Floor($i*$Frame.Width/[double]$Parts);$end=[int][Math]::Floor(($i+1)*$Frame.Width/[double]$Parts)
            if($Mode -eq 'Baseline'){$bytes=ConvertTo-AnsiStrip $Frame.Pixels $Frame.Width $Frame.Height $first $end $Frame.Context -ColumnOffset 13 -RowOffset 9}
            else{$bytes=ConvertTo-AnsiColorStateStrip $Frame.Pixels $Frame.Width $Frame.Height $first $end $Frame.Context -ColumnOffset 13 -RowOffset 9}
            if($bytes -isnot [byte[]]){throw 'Byte array was enumerated.'};$stream.Write($bytes,0,$bytes.Length)
        }
        return ,$stream.ToArray()
    }finally{$stream.Dispose()}
}
function Check-Frame($Frame,[int]$Parts){
    $before=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Frame.Pixels))
    $baseline=Encode-Parts $Frame $Parts Baseline;$candidate=Encode-Parts $Frame $Parts Candidate
    $decoded=Decode-TrueColor $candidate $Frame.Width $Frame.Height 13 9
    for($i=0;$i -lt $Frame.Pixels.Length;$i++){
        $rgb=$Frame.Context.Palette[$Frame.Pixels[$i]];$expected=($rgb[0] -shl 16) -bor ($rgb[1] -shl 8) -bor $rgb[2]
        if($decoded.Pixels[$i] -ne $expected){throw "Decoded pixel differs at $i in $($Frame.Name)."}
    }
    if($before -cne [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Frame.Pixels))){throw 'Encoder modified source pixels.'}
    if($candidate.Length -gt $baseline.Length){throw 'Candidate increased output bytes.'}
    $checks.Add(@{Name=$Frame.Name;Parts=$Parts;Pixels=$Frame.Pixels.Length;PixelSha256=$before;BaselineBytes=$baseline.Length;CandidateBytes=$candidate.Length;
        ForegroundOnly=$decoded.ForegroundOnly;BackgroundOnly=$decoded.BackgroundOnly;Both=$decoded.Both;Passed=$true})
}
try{
    $testContext=New-AnsiColorStateContext (New-TestPalette 256)
    foreach($pattern in 'Coherent','Entropy'){
        $frame=@{Name="synthetic-$pattern";Width=17;Height=13;Pixels=(New-IndexedFrame 17 13 3 $pattern 256);Context=$testContext}
        foreach($parts in 1,3,7){Check-Frame $frame $parts}
    }
    # Explicitly require both single-component instructions and repeated cells.
    $frame=@{Name='component-transitions';Width=8;Height=2;Pixels=[byte[]]@(0,1,1,2,2,3,3,3, 0,0,2,2,2,3,4,4);Context=$testContext}
    Check-Frame $frame 1
    if($checks[-1].ForegroundOnly -lt 1 -or $checks[-1].BackgroundOnly -lt 1){throw 'The fixture did not exercise both component updates.'}
    $bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
    . "$PSScriptRoot/../src/FastRenderer.ps1";. "$PSScriptRoot/../src/GameHost.ps1"
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    $palette=[int[][]]::new(256);for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    $context=New-AnsiColorStateContext $palette;$frames=[Collections.Generic.List[object]]::new()
    foreach($map in 1,3){
        $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
        $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
        $game.DeferedInitNew([GameSkill]::Medium,1,$map);$null=$game.Update($commands);for($i=0;$i -lt 35;$i++){$null=$game.Update($commands)}
        $renderer=New-FastRenderContext $content $game.World
        foreach($angle in 0,90,180){
            $snapshot=New-GameRenderSnapshot $game;$snapshot.ConsolePlayer.Mobj.Angle=$angle*[Math]::PI/180
            Set-GameRenderSnapshot $renderer $snapshot;Invoke-FastRender $renderer
            $frame=@{Name="E1M$map-$angle";Width=320;Height=200;Pixels=[byte[]]$renderer.Pixels.Clone();Context=$context};$frames.Add($frame)
            Check-Frame $frame 16
        }
    }
    # All timing follows validation; both variants have run. No timed samples are excluded.
    for($round=0;$round -lt 4;$round++){
        foreach($frame in $frames){
            $order='Baseline','Candidate';if($round%2){$order='Candidate','Baseline'}
            foreach($mode in $order){
                $watch=[Diagnostics.Stopwatch]::StartNew();$bytes=Encode-Parts $frame 16 $mode;$watch.Stop()
                $samples.Add(@{Round=$round;Frame=$frame.Name;Mode=$mode;First=($mode -ceq $order[0]);Milliseconds=$watch.Elapsed.TotalMilliseconds;Bytes=$bytes.Length})
            }
        }
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    $summary=@{};foreach($mode in 'Baseline','Candidate'){$values=@($samples|Where-Object Mode -eq $mode);if($values.Count){$summary[$mode]=@{TimingMs=(Get-SampleStats @($values.Milliseconds));TotalBytes=($values|Measure-Object Bytes -Sum).Sum}}}
    @{Error=$failure;Checks=$checks.ToArray();Samples=$samples.ToArray();Summary=$summary;Sources=$sources;
        SourcesChangedDuringRun=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash "$PSScriptRoot/../$($_.Path)").Hash});WadSha256=(Get-FileHash $Wad).Hash;PowerShell=$PSVersionTable.PSVersion.ToString();
        Meaning='Experimental foreground/background state compression. Independently parse the entire stream and compare every painted RGB pixel to its source palette; no unrecognized bytes or duplicate painting accepted. Odd dimensions, uneven partitions and offsets plus six real static views. Alternating-order 16-strip serial encoding, including UTF8 and memory-stream assembly; setup/rendering and preceding correctness checks excluded. All timed samples retained. No concurrent study workload, terminal output, audio, display or full-game performance claim.'}|ConvertTo-Json -Depth 8|Set-Content $Output
}
"PASS: $($checks.Count) exact-color cases.";$summary|ConvertTo-Json -Depth 5
