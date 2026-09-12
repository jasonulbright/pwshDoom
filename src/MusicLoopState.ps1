# SPDX-License-Identifier: GPL-2.0-or-later
# Exact state comparison for the pinned single-group dry synthesizer.
function Write-DoomMusicStateValue {
    param([IO.BinaryWriter]$Writer,$Value)
    if($null -eq $Value){$Writer.Write('null');return}
    if($Value -is [Collections.IDictionary]){
        $Writer.Write('map');[string[]]$keys=@($Value.Keys);[Array]::Sort($keys,[StringComparer]::Ordinal);$Writer.Write([int]$keys.Length)
        foreach($key in $keys){$Writer.Write($key);Write-DoomMusicStateValue $Writer $Value[$key]};return
    }
    $type=$Value.GetType();$Writer.Write($type.FullName)
    if($Value -is [Array]){
        if($Value.Rank -ne 1){throw 'Unsupported state array rank.'}
        $Writer.Write([int]$Value.Length)
        if($type.GetElementType().IsPrimitive){
            $bytes=[byte[]]::new([Buffer]::ByteLength($Value));[Buffer]::BlockCopy($Value,0,$bytes,0,$bytes.Length);$Writer.Write($bytes)
        }else{foreach($item in $Value){Write-DoomMusicStateValue $Writer $item}}
        return
    }
    if($Value -is [double]){$Writer.Write([double]$Value);return}
    if($Value -is [single]){$Writer.Write([single]$Value);return}
    if($Value -is [bool]){$Writer.Write([bool]$Value);return}
    if($Value -is [string]){$Writer.Write([string]$Value);return}
    if($type.IsPrimitive -and $Value -is [IFormattable]){$Writer.Write($Value.ToString($null,[Globalization.CultureInfo]::InvariantCulture));return}
    throw "Unsupported state value type: $($type.FullName)"
}
function Get-DoomMusicStateHash {
    param($Value)
    $stream=[IO.MemoryStream]::new();$writer=[IO.BinaryWriter]::new($stream)
    try{Write-DoomMusicStateValue $writer $Value;$writer.Flush();return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream.ToArray()))}
    finally{$writer.Dispose();$stream.Dispose()}
}
function Get-DoomMusicLoopSnapshot {
    param($Group)
    $s=$Group.Synth;$t=$Group.Timeline
    if($Group.Partition -ne 'Channel' -or @($Group.Owned|Where-Object {-not $_}).Count -ne 0 -or $s.Rate -ne 44100 -or $s.EffectMode -ne 'Dry' -or -not $t.Loop -or $s.Paused -or $t.Paused -or $s.Frame -ne $t.Frame -or $s.Frame%1260 -ne 0){throw 'Loop state requires aligned continuous unpaused single-group dry synthesis at 44100 Hz.'}
    [string[]]$allowed='Bank','Rate','Channels','Voices','Frame','NextNote','MaxVoices','PeakVoices','NoteOns','ExclusiveCuts','Paused','Volume','ClippedSamples','EffectMode','NonzeroReverbVoices','NonzeroChorusVoices'
    if($s.Count -ne $allowed.Length -or @($s.Keys|Where-Object {$_ -notin $allowed}).Count){throw 'Unknown synthesizer state; review loop normalization before qualification.'}
    # Frame/cycle are translated together; diagnostic counters cannot affect output.
    # Revisions preserve each voice's pending-control relationship to its channel.
    $channels=@($s.Channels|ForEach-Object {$copy=$_.Clone();$copy.Revision=0L;,$copy})
    $voices=@(foreach($voice in $s.Voices){
        if(-not [object]::ReferenceEquals($voice.Oscillator.Samples,$s.Bank.Samples) -or -not [object]::ReferenceEquals($voice.Oscillator.Region,$voice.Region)){throw 'Unexpected oscillator asset ownership.'}
        $copy=$voice.Clone();$copy.NoteId=[long]$voice.NoteId-[long]$s.NextNote
        $copy.ChannelRevision=[long]$voice.ChannelRevision-[long]$s.Channels[$voice.Channel].Revision
        $osc=$voice.Oscillator.Clone();$osc.Remove('Samples');$copy.Oscillator=$osc;,$copy
    })
    $clock=@{Index=$t.Index;PhaseFrames=[long]$s.Frame-(Convert-DoomMusicTickToFrame ($t.Cycle*$t.Score.DurationTicks) 44100);Finished=$t.Finished;Loop=$t.Loop;BlockPhase=[long]($s.Frame%1260)}
    $config=@{BankSha256=$s.Bank.SourceSha256;ScoreSha256=$t.Score.SourceSha256;Rate=$s.Rate;MaxVoices=$s.MaxVoices;Volume=$s.Volume;EffectMode=$s.EffectMode}
    return @{Frame=$s.Frame;Cycle=$t.Cycle;VoiceCount=$s.Voices.Count;ChannelsSha256=(Get-DoomMusicStateHash $channels);VoicesSha256=(Get-DoomMusicStateHash $voices);ClockSha256=(Get-DoomMusicStateHash $clock);ConfigurationSha256=(Get-DoomMusicStateHash $config);
        StateSha256=(Get-DoomMusicStateHash @{Version=1;Channels=$channels;Voices=$voices;Clock=$clock;Configuration=$config});
        VoiceFields=@(foreach($v in $voices){$fields=@{};foreach($key in $v.Keys){$fields[$key]=Get-DoomMusicStateHash $v[$key]};$fields})}
}
