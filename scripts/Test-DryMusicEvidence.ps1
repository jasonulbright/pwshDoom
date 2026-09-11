#requires -Version 7.4
param([Parameter(Mandatory)][string]$Output)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$root=Split-Path $PSScriptRoot;$checks=[Collections.Generic.List[object]]::new();$sources=[Collections.Generic.List[object]]::new();$failure=$null;$loopMetrics=$null
function Check([string]$Name,[bool]$Passed){$checks.Add(@{Name=$Name;Passed=$Passed});if(-not $Passed){throw $Name}}
try{
    $reports=@{}
    foreach($name in 'music-synth-unit-lifetime','music-e1m1-dry-loop','music-e1m1-reference-current','music-e1m1-reference-loop'){
        $r=Get-Content (Join-Path $root "results/$name.json") -Raw|ConvertFrom-Json;$reports[$name]=$r;Check "$name successful" (-not $r.Error)
        foreach($source in $r.Sources){Check "$name current source $($source.Path)" ((Get-FileHash (Join-Path $root $source.Path)).Hash -ceq $source.Sha256)}
    }
    $unit=$reports['music-synth-unit-lifetime'];Check 'All 34 named synthesis checks passed' ($unit.Checks.Count -eq 34 -and @($unit.Checks|Where-Object {-not $_.Passed}).Count -eq 0)
    $full=$reports['music-e1m1-dry-loop'];$reference=$reports['music-e1m1-reference-loop']
    Check 'Same 98-second score/bank/rate fixture' ($full.Details.Frames -eq 4321800 -and $reference.Details.Frames -eq 4321800 -and $full.Details.MusSha256 -ceq $reference.Details.MusSha256 -and $full.Details.SoundFontSha256 -ceq $reference.Details.SoundFontSha256)
    foreach($r in @($full,$reference)){Check 'Full WAV exists with retained hash' ((Get-FileHash $r.Details.WavPath).Hash -ceq $r.Details.WavSha256);Check 'No clipping in full fixture' ($r.Details.ClippedSamples -eq 0)}
    $bytes=[IO.File]::ReadAllBytes($full.Details.WavPath);Check 'Complete canonical stereo PCM payload length' ($bytes.Length -eq 44+4321800*4)
    $first=Get-Content (Join-Path $root 'results/music-e1m1-dry-first.json') -Raw|ConvertFrom-Json;$initial=[IO.File]::ReadAllBytes($first.Details.WavPath)
    $a=[byte[]]::new($initial.Length-44);$b=[byte[]]::new($a.Length);[Array]::Copy($initial,44,$a,0,$a.Length);[Array]::Copy($bytes,44,$b,0,$b.Length)
    Check 'Current full render preserves first eight-second PCM exactly' ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($a)) -ceq [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($b)))
    $loop=[int16[]]::new(2*44100*2);[Buffer]::BlockCopy($bytes,(44+96*44100*4),$loop,0,$loop.Length*2)
    $sum=0.0;$nonzero=0;foreach($sample in $loop){$sum+=[double]$sample*$sample;if($sample -ne 0){$nonzero++}}
    $loopMetrics=@{StartSecond=96;Seconds=2;NonzeroSamples=$nonzero;RmsPcm=[Math]::Sqrt($sum/$loop.Length);NoteOns=$full.Details.NoteOns}
    Check 'Output continues beyond the loop boundary' ($nonzero -gt 0 -and $full.Details.NoteOns -gt 2332)
    $comparison=Get-Content (Join-Path $root 'results/music-e1m1-reference-comparison.json') -Raw|ConvertFrom-Json
    Check 'Direct PCM comparison source and reference report hashes current' (-not $comparison.Error -and $comparison.SourceSha256 -ceq (Get-FileHash (Join-Path $root 'scripts/Compare-MusicPcm.ps1')).Hash -and $comparison.Reports.Reference -ceq (Get-FileHash (Join-Path $root 'results/music-e1m1-reference-current.json')).Hash)
    foreach($path in 'src/MusicControls.ps1','src/MusicSynth.ps1','scripts/Test-MusicSynth.ps1','scripts/Render-MusicScore.ps1','scripts/Render-MusicReference.ps1','scripts/Compare-MusicPcm.ps1','scripts/Test-DryMusicEvidence.ps1'){
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $path),[ref]$tokens,[ref]$errors);Check "Parse $path" ($errors.Count -eq 0)
        $sources.Add(@{Path=$path;Sha256=(Get-FileHash (Join-Path $root $path)).Hash})
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Checks=$checks.ToArray();Sources=$sources.ToArray();LoopWindow=$loopMetrics;Meaning='Current source hashes, synthetic dry-synth tests, complete E1M1 plus loop output and preserved opening PCM. No general SoundFont, full campaign, live audio or perceptual fidelity certification.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
"PASS: $($checks.Count) dry music evidence checks."
