# SPDX-License-Identifier: GPL-2.0-or-later
# Original PowerShell decoder. Event rows: tick, kind, MUS channel, data1, data2.
# Kind 0=off, 1=on, 2=14-bit bend, 3=system, 4=controller/program, 6=end.
class DoomMusCursor {
    [byte[]]$Data
    [int]$Position
    [int]$End
    DoomMusCursor([byte[]]$data,[int]$start,[int]$end){$this.Data=$data;$this.Position=$start;$this.End=$end}
    [int] Read(){
        if($this.Position -ge $this.End){throw [IO.InvalidDataException]::new('Truncated MUS event or delay.')}
        return [int]$this.Data[$this.Position++]
    }
    [long] Delay(){
        [long]$value=0
        for($i=0;$i -lt 5;$i++){
            $part=$this.Read();$value=$value*128+($part -band 127)
            if(($part -band 128) -eq 0){return $value}
        }
        throw [IO.InvalidDataException]::new('MUS delay exceeds five bytes.')
    }
}
function ConvertFrom-DoomMus {
    param([Parameter(Mandatory)][byte[]]$Data,[string]$Name='score')
    if($Data.Length -lt 16 -or $Data.Length -gt 16MB -or $Data[0] -ne 77 -or $Data[1] -ne 85 -or $Data[2] -ne 83 -or $Data[3] -ne 26){throw 'Invalid MUS signature or size.'}
    [int]$length=[BitConverter]::ToUInt16($Data,4);[int]$start=[BitConverter]::ToUInt16($Data,6);[int]$count=[BitConverter]::ToUInt16($Data,12)
    if($length -eq 0 -or $start -lt 16+2*$count -or $start+$length -gt $Data.Length){throw 'Invalid MUS score or instrument bounds.'}
    $instruments=[int[]]::new($count);for($i=0;$i -lt $count;$i++){$instruments[$i]=[BitConverter]::ToUInt16($Data,16+2*$i)}
    $reader=[DoomMusCursor]::new($Data,$start,$start+$length)
    $velocities=[int[]]::new(16);for($i=0;$i -lt 16;$i++){$velocities[$i]=127}
    $events=[Collections.Generic.List[object]]::new();[long]$tick=0;$ended=$false;$normalized=0
    while($reader.Position -lt $reader.End){
        $descriptor=$reader.Read();$kind=($descriptor -shr 4) -band 7;$channel=$descriptor -band 15;$a=0;$b=0
        switch($kind){
            0 {$a=$reader.Read();if($a -gt 127){$normalized++};$a=$a -band 127}
            1 {
                $note=$reader.Read();$a=$note -band 127
                if($note -band 128){$velocity=$reader.Read();if($velocity -gt 127){$normalized++};$velocities[$channel]=$velocity -band 127}
                $b=$velocities[$channel]
            }
            2 {$a=$reader.Read()*64}
            3 {$a=$reader.Read();if($a -lt 10 -or $a -gt 14){throw 'Invalid MUS system controller.'}}
            4 {
                $a=$reader.Read();if($a -gt 9){throw 'Invalid MUS valued controller.'};$b=$reader.Read()
                if($b -gt 127){$normalized++;if($a -eq 0){$b=$b -band 127}else{$b=127}}
            }
            6 {$ended=$true}
            default {throw "Unsupported MUS event kind $kind."}
        }
        $events.Add([long[]]@($tick,$kind,$channel,$a,$b))
        if($ended){break}
        if($descriptor -band 128){$tick+=$reader.Delay();if($tick -gt 3024000){throw 'MUS duration exceeds the six-hour decoder bound.'}}
    }
    if(-not $ended){throw 'MUS score has no end event within its declared bounds.'}
    return @{Name=$Name;TicksPerSecond=140;DurationTicks=$tick;Events=$events.ToArray();Instruments=$instruments;
        PrimaryChannels=[BitConverter]::ToUInt16($Data,8);SecondaryChannels=[BitConverter]::ToUInt16($Data,10);NormalizedValues=$normalized;
        TrailingScoreBytes=$reader.End-$reader.Position;TrailingLumpBytes=$Data.Length-$reader.End;SourceSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Data))}
}
function Convert-DoomMusicTickToFrame {
    param([ValidateRange(0,1000000000000)][long]$Tick,[ValidateRange(8000,192000)][int]$Rate=44100)
    [long]$remainder=0
    return [Math]::DivRem(($Tick*[long]$Rate),140L,[ref]$remainder)
}
function New-DoomMusicTimeline {
    param($Score,[ValidateRange(8000,192000)][int]$Rate=44100,[switch]$Loop)
    if($Score.Events.Count -eq 0 -or $Score.Events[-1][1] -ne 6 -or ($Loop -and $Score.DurationTicks -le 0)){throw 'Timeline requires an ended score and positive loop duration.'}
    return @{Score=$Score;Rate=$Rate;Loop=[bool]$Loop;Cycle=0L;Index=0;Frame=0L;Paused=$false;Finished=$false}
}
function Read-DoomMusicFrames {
    param($Timeline,[ValidateRange(1,192000)][int]$Frames)
    $due=[Collections.Generic.List[object]]::new();[long]$begin=$Timeline.Frame;[long]$end=$begin+$Frames
    if($Timeline.Paused){return @{Frame=$begin;Frames=$Frames;Events=$due.ToArray()}}
    while(-not $Timeline.Finished){
        $event=$Timeline.Score.Events[$Timeline.Index]
        [long]$absoluteTick=$Timeline.Cycle*$Timeline.Score.DurationTicks+$event[0]
        [long]$sample=Convert-DoomMusicTickToFrame $absoluteTick $Timeline.Rate
        if($sample -ge $end){break}
        $due.Add([long[]]@($sample,$event[1],$event[2],$event[3],$event[4],$Timeline.Cycle))
        $Timeline.Index++
        if($Timeline.Index -ge $Timeline.Score.Events.Count){
            if($Timeline.Loop){$Timeline.Index=0;$Timeline.Cycle++}else{$Timeline.Finished=$true}
        }
    }
    $Timeline.Frame=$end;return @{Frame=$begin;Frames=$Frames;Events=$due.ToArray()}
}
