#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaselineImage,
    [Parameter(Mandatory)][string]$CandidateImage,
    [Parameter(Mandatory)][string]$BaselineReport,
    [Parameter(Mandatory)][string]$CandidateReport,
    [Parameter(Mandatory)][string]$BaselineRenderer,
    [Parameter(Mandatory)][string]$CandidateRenderer,
    [Parameter(Mandatory)][string]$Output,
    [ValidateRange(0,167)][int]$Height = 68
)

$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Resolve-RepoFile([string]$Path,[bool]$MustExist){
    $full=[IO.Path]::GetFullPath($Path)
    $relative=[IO.Path]::GetRelativePath($repo,$full)
    if([IO.Path]::IsPathRooted($relative) -or $relative -eq '..' -or $relative.StartsWith("..$([IO.Path]::DirectorySeparatorChar)")){
        throw "Path must remain inside the project: $Path"
    }
    if($MustExist -and -not (Test-Path -LiteralPath $full -PathType Leaf)){throw "Input file not found: $full"}
    if(-not $MustExist -and (Test-Path -LiteralPath $full)){throw "Use a fresh output path: $full"}
    return $full
}

$baselineImagePath=Resolve-RepoFile $BaselineImage $true
$candidateImagePath=Resolve-RepoFile $CandidateImage $true
$baselineReportPath=Resolve-RepoFile $BaselineReport $true
$candidateReportPath=Resolve-RepoFile $CandidateReport $true
$baselineRendererPath=Resolve-RepoFile $BaselineRenderer $true
$candidateRendererPath=Resolve-RepoFile $CandidateRenderer $true
$outputPath=Resolve-RepoFile $Output $false
$baseline=[IO.File]::ReadAllText($baselineReportPath)|ConvertFrom-Json
$candidate=[IO.File]::ReadAllText($candidateReportPath)|ConvertFrom-Json
if($baseline.Error -or $candidate.Error){throw 'Comparison report contains an error.'}
$baselineRendererSource=$baseline.Sources|Where-Object Path -eq 'src/FastRenderer.ps1'|Select-Object -First 1
if($null -eq $baselineRendererSource){throw 'Baseline report does not pin src/FastRenderer.ps1.'}
foreach($property in @('ReplaySha256','WadSha256','Episode','Map','InputTic','SectorIndex')){
    if($baseline.$property -cne $candidate.$property){throw "Comparison reports differ in $property."}
}
$baselineHeight=$baseline.Heights|Where-Object CeilingHeight -eq $Height
$candidateHeight=$candidate.Heights|Where-Object CeilingHeight -eq $Height
if($null -eq $baselineHeight -or $null -eq $candidateHeight){throw "Both reports must include height $Height."}
if($baselineHeight.ReferenceFrameSha256 -cne $candidateHeight.ReferenceFrameSha256){throw 'Reference frame hashes differ.'}

Add-Type -AssemblyName System.Drawing
$baselineBitmap=[Drawing.Bitmap]::new($baselineImagePath)
$candidateBitmap=[Drawing.Bitmap]::new($candidateImagePath)
$fixed=0;$introduced=0;$remaining=0;$candidateChanged=0;$referenceChanged=0;$remainingColorChanged=0
$introducedExamples=[Collections.Generic.List[object]]::new()
try{
    if($baselineBitmap.Width -ne 960 -or $baselineBitmap.Height -ne 168 -or
        $candidateBitmap.Width -ne 960 -or $candidateBitmap.Height -ne 168){
        throw 'Expected 960x168 triptych images from Compare-MovingSectorHeightSweep.ps1.'
    }
    for([int]$y=0;$y -lt 168;$y++){
        for([int]$x=0;$x -lt 320;$x++){
            $baseReference=$baselineBitmap.GetPixel($x,$y)
            $candidateReference=$candidateBitmap.GetPixel($x,$y)
            if($baseReference.ToArgb() -ne $candidateReference.ToArgb()){$referenceChanged++}
            $basePixel=$baselineBitmap.GetPixel($x+320,$y)
            $candidatePixel=$candidateBitmap.GetPixel($x+320,$y)
            $candidatePixelChanged=$basePixel.ToArgb() -ne $candidatePixel.ToArgb()
            if($candidatePixelChanged){$candidateChanged++}
            $baseMismatch=$baselineBitmap.GetPixel($x+640,$y).R -ne 0
            $candidateMismatch=$candidateBitmap.GetPixel($x+640,$y).R -ne 0
            if($baseMismatch -and -not $candidateMismatch){$fixed++}
            elseif(-not $baseMismatch -and $candidateMismatch){
                $introduced++
                $introducedExamples.Add([ordered]@{X=$x;Y=$y})
            }elseif($candidateMismatch){
                $remaining++
                if($candidatePixelChanged){$remainingColorChanged++}
            }
        }
    }
}finally{
    $baselineBitmap.Dispose()
    $candidateBitmap.Dispose()
}
$baselineMismatchCount=[int]$baselineHeight.SceneDifferentIndices
$candidateMismatchCount=[int]$candidateHeight.SceneDifferentIndices
if($fixed+$remaining -ne $baselineMismatchCount){
    throw 'Pixel-mask counts do not reconcile with the baseline mismatch count.'
}
if($candidateMismatchCount -ne $introduced+$remaining){
    throw 'Pixel-mask counts do not reconcile with the candidate mismatch count.'
}
$stableOtherHeights=$true
foreach($baselineSweepHeight in $baseline.Heights){
    if($baselineSweepHeight.CeilingHeight -eq $Height){continue}
    $candidateSweepHeight=$candidate.Heights|Where-Object CeilingHeight -eq $baselineSweepHeight.CeilingHeight
    if($null -eq $candidateSweepHeight -or
        $baselineSweepHeight.CandidateFrameSha256 -cne $candidateSweepHeight.CandidateFrameSha256 -or
        $baselineSweepHeight.ReferenceFrameSha256 -cne $candidateSweepHeight.ReferenceFrameSha256){$stableOtherHeights=$false}
}
$receipt=[ordered]@{
    SchemaVersion=1
    FinishedUtc=[DateTime]::UtcNow.ToString('o')
    Height=$Height
    SourceCommit=(git -C $repo rev-parse HEAD).Trim()
    AnalysisScriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    ReplaySha256=$baseline.ReplaySha256
    WadSha256=$baseline.WadSha256
    BaselineComparisonReport=[IO.Path]::GetRelativePath($repo,$baselineReportPath).Replace('\','/')
    BaselineComparisonReportSha256=(Get-FileHash -LiteralPath $baselineReportPath).Hash
    CandidateComparisonReport=[IO.Path]::GetRelativePath($repo,$candidateReportPath).Replace('\','/')
    CandidateComparisonReportSha256=(Get-FileHash -LiteralPath $candidateReportPath).Hash
    BaselineTriptychSha256=(Get-FileHash -LiteralPath $baselineImagePath).Hash
    CandidateTriptychSha256=(Get-FileHash -LiteralPath $candidateImagePath).Hash
    BaselineRendererSha256=$baselineRendererSource.Sha256
    CandidateRendererSha256=(Get-FileHash -LiteralPath $candidateRendererPath).Hash
    BaselineDiagnosticRendererSha256=($baseline.Sources|Select-Object -First 1 -ExpandProperty Sha256)
    CandidateDiagnosticRendererSha256=($candidate.Sources|Select-Object -First 1 -ExpandProperty Sha256)
    BaselineReferenceFrameSha256=$baselineHeight.ReferenceFrameSha256
    CandidateReferenceFrameSha256=$candidateHeight.ReferenceFrameSha256
    BaselineCandidateFrameSha256=$baselineHeight.CandidateFrameSha256
    CandidateCandidateFrameSha256=$candidateHeight.CandidateFrameSha256
    BaselineMismatchPixels=$baselineMismatchCount
    CandidateMismatchPixels=$candidateMismatchCount
    FixedMismatchPixels=$fixed
    IntroducedMismatchPixels=$introduced
    RemainingMismatchPixels=$remaining
    CandidatePixelsChanged=$candidateChanged
    ReferencePixelsChanged=$referenceChanged
    RemainingMismatchPixelsWithChangedCandidateColor=$remainingColorChanged
    OtherSweepHeightsFrameHashesUnchanged=$stableOtherHeights
    IntroducedMismatchExamples=$introducedExamples.ToArray()
    Interpretation='Pixelwise comparison of saved-replay diagnostic triptychs (reference, candidate, mismatch mask); not a live test or original-executable comparison.'
}
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath))
[IO.File]::WriteAllText($outputPath,($receipt|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$receipt
