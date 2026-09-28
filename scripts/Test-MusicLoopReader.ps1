#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
. "$PSScriptRoot/../src/MusicLoopReader.ps1"
$checks=[Collections.Generic.List[object]]::new();$failure=$null;$reader=$null
$dir=[IO.Path]::GetFullPath("$PSScriptRoot/../local/loop-reader-test-$([guid]::NewGuid().ToString('N'))");$null=[IO.Directory]::CreateDirectory($dir)
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
function Reject([string]$Name,[scriptblock]$Action){$rejected=$false;try{& $Action}catch{$rejected=$true};Check $Name $rejected}
try{
    # Trusted synthetic receipt exercises the reader only; it is NOT loop qualification evidence.
    $periods=@(for($i=0;$i -lt 2;$i++){
        $samples=[double[]]::new(5040);for($n=0;$n -lt $samples.Length;$n++){$samples[$n]=if($i -eq 0){-$n-1.0}else{$n+.25}}
        $bytes=[byte[]]::new($samples.Length*8);[Buffer]::BlockCopy($samples,0,$bytes,0,$bytes.Length);$path=Join-Path $dir "period-$i.f64";[IO.File]::WriteAllBytes($path,$bytes)
        @{Index=$i;Frames=2520;Bytes=$bytes.Length;Path=$path;Sha256=(Get-FileHash $path).Hash}
    })
    $sources=@('MusScore','SoundFontBank','SoundFontRegions','MusicOscillator','MusicControls','MusicSynth','MusicGroup','MusicLoopState'|ForEach-Object {@{Path="src/$_.ps1";Sha256=(Get-FileHash "$PSScriptRoot/../src/$_.ps1").Hash}})
    $receipt=@{Error=$null;Sources=$sources;Details=@{Qualified=$true;EvidenceMode='CompleteStateRecurrence';NormalizedStateRepeats=$true;NextPeriodFloatOutputRepeats=$null;Reference=@{Exact=$true};SourcesChangedDuringRun=@();PowerShell=$PSVersionTable.PSVersion.ToString();PeriodFrames=2520;LoopStartFrame=2520;LoopFrames=2520;Periods=$periods;Snapshots=@(1..3|ForEach-Object {@{StateSha256=('A'*64)}});MusSha256='synthetic';BankSha256='synthetic'}}
    $path=Join-Path $dir 'synthetic-reader-receipt.json';$receipt|ConvertTo-Json -Depth 8|Set-Content $path
    $oversizedReceipt=$receipt|ConvertTo-Json -Depth 8|ConvertFrom-Json -AsHashtable
    $oversizedReceipt.Details.PeriodFrames=52921260;$oversizedReceipt.Details.LoopStartFrame=52921260;$oversizedReceipt.Details.LoopFrames=52921260
    $oversizedPath=Join-Path $dir 'over-reader-bound-receipt.json';$oversizedReceipt|ConvertTo-Json -Depth 8|Set-Content $oversizedPath
    Reject 'Loop period above the reader bound is rejected before opening payload files' {$r=Open-DoomMusicLoopReader $oversizedPath;Close-DoomMusicLoopReader $r}
    $qualifiedVersion=$PSVersionTable.PSVersion
    $compatiblePatch=if($qualifiedVersion.Patch -gt 0){$qualifiedVersion.Patch-1}else{$qualifiedVersion.Patch+1}
    $receipt.Details.PowerShell=([version]::new($qualifiedVersion.Major,$qualifiedVersion.Minor,$compatiblePatch)).ToString()
    $compatiblePath=Join-Path $dir 'same-line-patch-receipt.json';$receipt|ConvertTo-Json -Depth 8|Set-Content $compatiblePath
    $compatibleReader=Open-DoomMusicLoopReader $compatiblePath
    Check 'Same major/minor qualification accepts a different PowerShell patch' ($compatibleReader.Files.Count -eq 2)
    Close-DoomMusicLoopReader $compatibleReader
    $receipt.Details.PowerShell=([version]::new($qualifiedVersion.Major,$qualifiedVersion.Minor+1,0)).ToString()
    $incompatiblePath=Join-Path $dir 'different-minor-receipt.json';$receipt|ConvertTo-Json -Depth 8|Set-Content $incompatiblePath
    Reject 'Different PowerShell minor line is rejected' {$r=Open-DoomMusicLoopReader $incompatiblePath;Close-DoomMusicLoopReader $r}
    $receipt.Details.PowerShell=([version]::new($qualifiedVersion.Major+1,$qualifiedVersion.Minor,0)).ToString()
    $incompatiblePath=Join-Path $dir 'different-major-receipt.json';$receipt|ConvertTo-Json -Depth 8|Set-Content $incompatiblePath
    Reject 'Different PowerShell major line is rejected' {$r=Open-DoomMusicLoopReader $incompatiblePath;Close-DoomMusicLoopReader $r}
    $receipt.Details.PowerShell='not-a-version'
    $malformedPath=Join-Path $dir 'malformed-runtime-receipt.json';$receipt|ConvertTo-Json -Depth 8|Set-Content $malformedPath
    Reject 'Malformed PowerShell version is rejected' {$r=Open-DoomMusicLoopReader $malformedPath;Close-DoomMusicLoopReader $r}
    $receipt.Details.PowerShell=$qualifiedVersion.ToString()
    $reader=Open-DoomMusicLoopReader $path
    Reject 'Playback file cannot be opened for writing while reader holds it' {$f=[IO.File]::Open($periods[1].Path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$f.Dispose()}
    $result=Read-DoomMusicLoop $reader 9000;$exact=$true
    for($n=0;$n -lt 18000;$n++){$expected=if($n -lt 5040){-$n-1.0}else{(($n-5040)%5040)+.25};if($result.Mix[$n] -ne $expected){$exact=$false;break}}
    Check 'Intro then multiple loop boundaries preserve every sample' ($exact -and $reader.Frame -eq 9000)
    $reader.Paused=$true;$pause=Read-DoomMusicLoop $reader 1260
    Check 'Paused loop is silent and freezes position' ($reader.Frame -eq 9000 -and $pause.Paused -and @($pause.Mix|Where-Object {$_ -ne 0}).Count -eq 0)
    $reader.Paused=$false;$resume=Read-DoomMusicLoop $reader 1
    Check 'Resume continues at the retained position' ($resume.Mix[0] -eq ((9000-2520)%2520)*2+.25 -and $reader.Frame -eq 9001)
    $reader.Frame=44100L*86400*7;$large=Read-DoomMusicLoop $reader 1
    Check 'Seven-day position uses exact integer loop mapping' ($large.Mix[0] -eq (($large.Frame-2520)%2520)*2+.25)
    Check 'Reader retains one bounded decoded page' ($reader.Loaded.Length -eq 5040)
    $reader.Frame=-1;Reject 'Negative cursor rejected' {$null=Read-DoomMusicLoop $reader 1};$reader.Frame=[long]::MaxValue;Reject 'Cursor overflow rejected' {$null=Read-DoomMusicLoop $reader 1}
    Close-DoomMusicLoopReader $reader;Reject 'Closed reader rejected' {$null=Read-DoomMusicLoop $reader 1};Close-DoomMusicLoopReader $reader;$reader=$null
    $f=[IO.File]::Open($periods[1].Path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None);$f.Dispose();Check 'Close releases playback file handles' $true
    $receipt.Details.Qualified=$false;$receipt|ConvertTo-Json -Depth 8|Set-Content $path;Reject 'Unqualified report rejected' {$r=Open-DoomMusicLoopReader $path;Close-DoomMusicLoopReader $r};$receipt.Details.Qualified=$true
    $sourceText=[IO.File]::ReadAllText("$PSScriptRoot/../src/MusScore.ps1")
    $sourceLf=[regex]::Replace($sourceText,"`r`n|`r|`n","`n")
    $crlfBytes=[Text.UTF8Encoding]::new($false).GetBytes($sourceLf.Replace("`n","`r`n"))
    $receipt.Sources[0].Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($crlfBytes));$receipt|ConvertTo-Json -Depth 8|Set-Content $path
    $lineEndingReader=Open-DoomMusicLoopReader $path
    Check 'Equivalent CRLF checkout source is accepted' ($lineEndingReader.Files.Count -eq 2)
    Close-DoomMusicLoopReader $lineEndingReader
    $changedBytes=[Text.UTF8Encoding]::new($false).GetBytes($sourceLf+"# altered content`n")
    $receipt.Sources[0].Sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($changedBytes));$receipt|ConvertTo-Json -Depth 8|Set-Content $path
    Reject 'Changed synthesis source rejected' {$r=Open-DoomMusicLoopReader $path;Close-DoomMusicLoopReader $r}
    $receipt.Sources[0].Sha256=(Get-FileHash "$PSScriptRoot/../src/MusScore.ps1").Hash
    $receipt.Details.Snapshots[2].StateSha256='different';$receipt|ConvertTo-Json -Depth 8|Set-Content $path;Reject 'Inconsistent state evidence rejected' {$r=Open-DoomMusicLoopReader $path;Close-DoomMusicLoopReader $r};$receipt.Details.Snapshots[2].StateSha256='A'*64
    $receipt|ConvertTo-Json -Depth 8|Set-Content $path
    $legacyThird=@{Index=2;Frames=2520;Bytes=$periods[1].Bytes;Path=$periods[1].Path;Sha256=$periods[1].Sha256}
    $legacyPeriods=@($periods)+@($legacyThird)
    $legacyReceipt=@{Error=$null;Sources=$sources;Details=@{Qualified=$true;NormalizedStateRepeats=$true;NextPeriodFloatOutputRepeats=$true;Reference=@{Exact=$true};SourcesChangedDuringRun=@();PowerShell=$PSVersionTable.PSVersion.ToString();PeriodFrames=2520;LoopStartFrame=2520;LoopFrames=2520;Periods=$legacyPeriods;Snapshots=@(1..4|ForEach-Object {@{StateSha256=('A'*64)}});MusSha256='synthetic';BankSha256='synthetic'}}
    $legacyPath=Join-Path $dir 'legacy-three-period-receipt.json';$legacyReceipt|ConvertTo-Json -Depth 8|Set-Content $legacyPath
    $legacyReader=Open-DoomMusicLoopReader $legacyPath
    Check 'Existing three-period receipt remains accepted and retains only intro plus loop readers' ($legacyReader.Files.Count -eq 2)
    Close-DoomMusicLoopReader $legacyReader
    $bytes=[IO.File]::ReadAllBytes($periods[1].Path);$bytes[0]=$bytes[0] -bxor 1;[IO.File]::WriteAllBytes($periods[1].Path,$bytes)
    Reject 'Corrupt loop rejected at open' {$r=Open-DoomMusicLoopReader $path;Close-DoomMusicLoopReader $r}
    $f=[IO.File]::Open($periods[0].Path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None);$f.Dispose();Check 'Failed open releases earlier handles' $true
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($reader){Close-DoomMusicLoopReader $reader}
    @{Error=$failure;Checks=$checks.ToArray();FixtureDirectory=$dir;SourceSha256=(Get-FileHash "$PSScriptRoot/../src/MusicLoopReader.ps1").Hash;ScriptSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Reader-only synthetic receipt and samples: intro/loop mapping, pause, long positions, bounded pages, file locking and rejection/cleanup. The fabricated receipt is test data and proves no real synthesizer loop.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) loop-reader checks."
