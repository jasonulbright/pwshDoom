#requires -Version 7.4
param([Parameter(Mandatory)][string]$Output,[string]$PowerShellReport="$PSScriptRoot/../results/music-e1m1-dry-first.json",[string]$ReferenceReport="$PSScriptRoot/../results/music-e1m1-reference-current.json")
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh report path.'}
$failure=$null;$details=$null
try{
    $a=Get-Content $PowerShellReport -Raw|ConvertFrom-Json;$b=Get-Content $ReferenceReport -Raw|ConvertFrom-Json
    if($a.Error -or $b.Error -or $a.Details.Frames -ne $b.Details.Frames -or $a.Details.SoundFontSha256 -cne $b.Details.SoundFontSha256 -or $a.Details.MusSha256 -cne $b.Details.MusSha256){throw 'Reference inputs differ.'}
    $streams=@();foreach($r in @($a,$b)){
        if((Get-FileHash $r.Details.WavPath).Hash -cne $r.Details.WavSha256){throw 'Wave hash changed.'}
        $bytes=[IO.File]::ReadAllBytes($r.Details.WavPath)
        if($bytes.Length -ne 44+$r.Details.Frames*4 -or [Text.Encoding]::ASCII.GetString($bytes,36,4) -cne 'data' -or [BitConverter]::ToUInt32($bytes,24) -ne 44100){throw 'Expected canonical renderer PCM WAV.'}
        $samples=[int16[]]::new(($bytes.Length-44)/2);[Buffer]::BlockCopy($bytes,44,$samples,0,$bytes.Length-44);$streams+=,$samples
    }
    [double]$xx=0;[double]$yy=0;[double]$xy=0;[double]$sumX=0;[double]$sumY=0;[double]$diff=0
    for($i=0;$i -lt $streams[0].Length;$i++){
        [double]$x=$streams[0][$i];[double]$y=$streams[1][$i];$xx+=$x*$x;$yy+=$y*$y;$xy+=$x*$y;$sumX+=$x;$sumY+=$y;$diff+=($x-$y)*($x-$y)
    }
    $n=$streams[0].Length;$corr=($xy-$sumX*$sumY/$n)/[Math]::Sqrt(($xx-$sumX*$sumX/$n)*($yy-$sumY*$sumY/$n))
    $details=@{Samples=$n;Frames=$n/2;PowerShellRms=[Math]::Sqrt($xx/$n);ReferenceRms=[Math]::Sqrt($yy/$n);LevelDifferenceDb=10*[Math]::Log10($xx/$yy);
        ZeroLagCorrelation=$corr;DifferenceRms=[Math]::Sqrt($diff/$n);SameWaveHash=($a.Details.WavSha256 -ceq $b.Details.WavSha256);PowerShellWavSha256=$a.Details.WavSha256;ReferenceWavSha256=$b.Details.WavSha256}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{Error=$failure;Details=$details;Reports=@{PowerShell=(Get-FileHash $PowerShellReport).Hash;Reference=(Get-FileHash $ReferenceReport).Hash};SourceSha256=(Get-FileHash $PSCommandPath).Hash;
      Meaning='Direct signed-16 PCM comparison at zero lag without gain normalization. Differences include block event latency, model/precision and level choices. Correlation/RMS are diagnostic, not perceptual fidelity or audibility certification.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
'PASS: PCM comparison recorded.'
