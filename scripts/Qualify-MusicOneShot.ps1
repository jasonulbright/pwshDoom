#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$SoundFont="$PSScriptRoot/../local/upstream/ManagedDoomPowershell/ManagedDoomPowershell/src/TimGM6mb.sf2",
    [ValidatePattern('^D_[A-Z0-9]+$')][string]$Track='D_INTRO',
    [ValidateRange(1,30)][int]$TailLimitSeconds=20
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a fresh qualification path.'}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Output))
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..")
$sourceNames=@('MusScore','SoundFontBank','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth')
$sourcePaths=@(@($sourceNames|ForEach-Object {"src/$_.ps1"})+'scripts/Qualify-MusicOneShot.ps1')
$sources=@(foreach($path in $sourcePaths){@{Path=$path;Sha256=(Get-FileHash -LiteralPath (Join-Path $root $path)).Hash}})
$wadHash=(Get-FileHash -LiteralPath $Wad).Hash
$soundFontHash=(Get-FileHash -LiteralPath $SoundFont).Hash
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$root/local/music-one-shot-$PID.ps1"
. $bundle
foreach($name in $sourceNames){. (Join-Path $root "src/$name.ps1")}

function Write-OneShotPass {
    param($Bank,$Score,[long]$ScoreFrames,[long]$MaximumFrames,[string]$Path)
    $timeline=New-DoomMusicTimeline $Score
    $synth=New-DoomMusicSynth $Bank
    $synth.Volume=.2
    $stream=[IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $finished=$false
    try{
        while($synth.Frame -lt $MaximumFrames){
            [int]$count=[Math]::Min(1260,$MaximumFrames-$synth.Frame)
            $block=Read-DoomMusicFrames $timeline $count
            foreach($event in $block.Events){
                [int]$span=[int]($event[0]-$synth.Frame)
                if($span -gt 0){
                    [double[]]$mix=Read-DoomMusicSynth $synth $span
                    [byte[]]$bytes=[byte[]]::new($mix.Length*8)
                    [Buffer]::BlockCopy($mix,0,$bytes,0,$bytes.Length)
                    $stream.Write($bytes)
                }
                Invoke-DoomMusicEvent $synth $event
            }
            [int]$span=[int]($block.Frame+$count-$synth.Frame)
            if($span -gt 0){
                [double[]]$mix=Read-DoomMusicSynth $synth $span
                [byte[]]$bytes=[byte[]]::new($mix.Length*8)
                [Buffer]::BlockCopy($mix,0,$bytes,0,$bytes.Length)
                $stream.Write($bytes)
            }
            if($timeline.Finished -and $synth.Voices.Count -eq 0){$finished=$true;break}
        }
        $stream.Flush($true)
    }finally{$stream.Dispose()}
    if(-not $timeline.Finished){throw 'One-shot score did not reach its MUS end event.'}
    if(-not $finished){throw "One-shot release tail exceeded $TailLimitSeconds seconds with $($synth.Voices.Count) voices still active."}
    if($synth.Frame -gt $MaximumFrames -or (Get-Item -LiteralPath $Path).Length -ne $synth.Frame*16){throw 'One-shot payload frame count or byte length is invalid.'}
    return @{
        Path=[IO.Path]::GetFullPath($Path)
        Frames=[long]$synth.Frame
        ScoreFrames=$ScoreFrames
        TailFrames=[long]($synth.Frame-$ScoreFrames)
        Bytes=(Get-Item -LiteralPath $Path).Length
        Sha256=(Get-FileHash -LiteralPath $Path).Hash
        PeakVoices=$synth.PeakVoices
        NoteOns=$synth.NoteOns
        ClippedSamples=$synth.ClippedSamples
        EndEventReached=$timeline.Finished
        VoicesAtEnd=$synth.Voices.Count
    }
}

$archive=$null
$details=$null
$failure=$null
$passes=[Collections.Generic.List[object]]::new()
try{
    $archive=[Wad]::new([string[]]@($Wad))
    $lump=$archive.GetLumpNumber($Track)
    if($lump -lt 0){throw "The active IWAD does not contain $Track."}
    $score=ConvertFrom-DoomMus ($archive.ReadLump($lump)) -Name $Track
    if($score.DurationTicks -le 0){throw 'One-shot score has no positive duration.'}
    $scoreFrames=Convert-DoomMusicTickToFrame $score.DurationTicks
    $maximumFrames=$scoreFrames+[long]$TailLimitSeconds*44100
    $bank=ConvertTo-DoomSoundFontRegions (ConvertFrom-DoomSoundFont ([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($SoundFont))))
    $dir=Join-Path $root ('local/music-one-shot-'+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($dir)
    for($pass=0;$pass -lt 2;$pass++){
        $path=Join-Path $dir ("{0}-pass{1}.f64" -f $Track,$pass)
        $record=Write-OneShotPass $bank $score $scoreFrames $maximumFrames $path
        $passes.Add($record)
        ("Pass {0}: {1} frames; {2} tail frames; {3} peak voices." -f $pass,$record.Frames,$record.TailFrames,$record.PeakVoices)
    }
    $sameFrames=$passes[0].Frames -eq $passes[1].Frames
    $samePayload=$passes[0].Sha256 -ceq $passes[1].Sha256
    $drift=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash -LiteralPath (Join-Path $root $_.Path)).Hash})
    $details=@{
        Mode='OneShot'
        Track=$Track
        WadSha256=$wadHash
        MusSha256=$score.SourceSha256
        SoundFontSha256=$bank.SourceSha256
        ScoreTicks=$score.DurationTicks
        ScoreFrames=$scoreFrames
        TailLimitFrames=([long]$TailLimitSeconds*44100)
        Frames=$passes[0].Frames
        TailFrames=$passes[0].TailFrames
        Payload=$passes[0]
        RepeatPayload=$passes[1]
        DeterministicFrames=$sameFrames
        DeterministicPayload=$samePayload
        Qualified=($sameFrames -and $samePayload -and $drift.Count -eq 0)
        SourcesChangedDuringRun=$drift
        PowerShell=$PSVersionTable.PSVersion.ToString()
    }
    if(-not $details.Qualified){throw 'The two one-shot synthesis passes differ or sources changed.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}
finally{
    if($archive){$archive.Dispose()}
    [ordered]@{
        Error=$failure
        Details=$details
        Sources=$sources
        BundleSha256=(Get-FileHash -LiteralPath $bundle).Hash
        ScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
        Meaning='Two exact dry PowerShell renders of one finite MUS score, including the MUS end event and all voices until release completion. Repeated payload equality establishes deterministic output for the pinned WAD, soundfont, source, and runtime; it is not original-synth fidelity, acoustic review, or live-deadline qualification.'
    }|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
}
("Qualified deterministic one-shot {0}: {1} float64 frames." -f $Track,$details.Frames)
