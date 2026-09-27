# SPDX-License-Identifier: GPL-2.0-or-later
[CmdletBinding()]
param(
    [ValidateRange(5,200)][int]$IterationsPerBlock=40,
    [ValidateRange(4,30)][int]$Rounds=10,
    [string]$Output=(Join-Path $PSScriptRoot '../results/ansi-strip-reuse-measurement-20260927.json')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$baselineCommit='37391e3e391c465bbadc88f52cb1ba90c2d3fa6d'
$candidateCommit='1fcda3ddfef9bd135ebbc75ed5d03a4ddd2abeaa'
$repoRoot=Split-Path $PSScriptRoot -Parent
$headCommit=(git -C $repoRoot rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'Could not identify the current source commit.'}
function Get-GitSource {
    param([string]$Commit,[string]$Path)
    $content=git -C $repoRoot show "${Commit}:${Path}"
    if($LASTEXITCODE -ne 0){throw "Could not read $Path at $Commit."}
    return ($content -join "`n")+"`n"
}
function Get-GitBlobId {
    param([string]$Commit,[string]$Path)
    $value=(git -C $repoRoot rev-parse "${Commit}:${Path}").Trim()
    if($LASTEXITCODE -ne 0){throw "Could not identify $Path at $Commit."}
    return $value
}
$sourcePaths=@('scripts/FrameCodec.ps1','src/TerminalCodec.ps1','src/AnsiColorState.ps1')
$sourceTexts=@{}
foreach($path in $sourcePaths){
    $sourceTexts[$path]=@{
        Baseline=Get-GitSource $baselineCommit $path
        Candidate=Get-GitSource $candidateCommit $path
    }
}
$factory='scripts/FrameCodec.ps1';$pairs='src/TerminalCodec.ps1';$colorState='src/AnsiColorState.ps1'
if(-not $sourceTexts[$factory].Baseline.Contains('function New-CodecContext {') -or
   -not $sourceTexts[$factory].Candidate.Contains('function New-CodecContext {') -or
   -not $sourceTexts[$pairs].Baseline.Contains('function ConvertTo-AnsiStrip {') -or
   -not $sourceTexts[$pairs].Candidate.Contains('function ConvertTo-AnsiStrip {') -or
   -not $sourceTexts[$colorState].Baseline.Contains('function ConvertTo-AnsiColorStateStrip {') -or
   -not $sourceTexts[$colorState].Candidate.Contains('function ConvertTo-AnsiColorStateStrip {')){
    throw 'A pinned source revision no longer has the expected encoder functions.'
}
$sourceTexts[$factory].Baseline=$sourceTexts[$factory].Baseline.Replace('function New-CodecContext {','function New-CodecContextBaseline {')
$sourceTexts[$factory].Candidate=$sourceTexts[$factory].Candidate.Replace('function New-CodecContext {','function New-CodecContextCandidate {')
$sourceTexts[$pairs].Baseline=$sourceTexts[$pairs].Baseline.Replace('function ConvertTo-AnsiStrip {','function ConvertTo-AnsiStripBaseline {')
$sourceTexts[$pairs].Candidate=$sourceTexts[$pairs].Candidate.Replace('function ConvertTo-AnsiStrip {','function ConvertTo-AnsiStripCandidate {')
$sourceTexts[$colorState].Baseline=$sourceTexts[$colorState].Baseline.Replace('function ConvertTo-AnsiColorStateStrip {','function ConvertTo-AnsiColorStateStripBaseline {')
$sourceTexts[$colorState].Candidate=$sourceTexts[$colorState].Candidate.Replace('function ConvertTo-AnsiColorStateStrip {','function ConvertTo-AnsiColorStateStripCandidate {')
foreach($path in $sourcePaths){
    Invoke-Expression $sourceTexts[$path].Baseline
    Invoke-Expression $sourceTexts[$path].Candidate
}
. (Join-Path $PSScriptRoot 'FrameCodec.ps1')

function Get-StripHash {
    param([byte[]]$Bytes)
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Measure-StripBlock {
    param([scriptblock]$Encoder,[byte[]]$Pixels,[hashtable]$Context,[int]$Calls)
    [Diagnostics.Stopwatch]$watch=[Diagnostics.Stopwatch]::new()
    [byte[]]$last=[byte[]]::new(0)
    [long]$allocatedBefore=[GC]::GetAllocatedBytesForCurrentThread()
    $watch.Start()
    for([int]$i=0;$i -lt $Calls;$i++){
        $last=[byte[]](& $Encoder $Pixels $Context)
    }
    $watch.Stop()
    [long]$allocated=[GC]::GetAllocatedBytesForCurrentThread()-$allocatedBefore
    [pscustomobject]@{
        Calls=$Calls
        ElapsedMs=$watch.Elapsed.TotalMilliseconds
        MsPerCall=$watch.Elapsed.TotalMilliseconds/$Calls
        AllocatedBytesPerCall=$allocated/$Calls
        OutputBytes=$last.Length
    }
}

function Get-BlockStatistics {
    param([object[]]$Samples)
    [double[]]$times=@($Samples | ForEach-Object MsPerCall | Sort-Object)
    [double[]]$allocations=@($Samples | ForEach-Object AllocatedBytesPerCall | Sort-Object)
    $middle=[int][Math]::Floor($times.Length/2)
    $medianTime=if($times.Length%2){$times[$middle]}else{($times[$middle-1]+$times[$middle])/2}
    $medianAllocation=if($allocations.Length%2){$allocations[$middle]}else{($allocations[$middle-1]+$allocations[$middle])/2}
    [ordered]@{
        Blocks=$Samples.Count
        CallsPerBlock=$Samples[0].Calls
        MedianMsPerCall=$medianTime
        P95MsPerCall=$times[[int][Math]::Ceiling($times.Length*0.95)-1]
        MaximumMsPerCall=$times[-1]
        MedianAllocatedBytesPerCall=$medianAllocation
        P95AllocatedBytesPerCall=$allocations[[int][Math]::Ceiling($allocations.Length*0.95)-1]
        OutputBytes=$Samples[0].OutputBytes
    }
}
function New-ColorStateBenchmarkContext {
    param([scriptblock]$Factory,[int[][]]$Palette)
    $context=& $Factory $Palette
    [string[]]$foreground=[string[]]::new($Palette.Length)
    [string[]]$background=[string[]]::new($Palette.Length)
    [char]$esc=[char]27;[char]$block=[char]0x2580
    for([int]$i=0;$i -lt $Palette.Length;$i++){
        $rgb=$Palette[$i]
        $foreground[$i]="$esc[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$block"
        $background[$i]="$esc[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m$block"
    }
    $context.ForegroundCells=$foreground;$context.BackgroundCells=$background
    return $context
}

$palette=New-TestPalette 256
$modeEncoders=@{
    Pairs=@{
        Baseline=({param($p,$c) ConvertTo-AnsiStripBaseline -Pixels $p -Width 320 -Height 200 -FirstColumn 0 -EndColumn 20 -Context $c}.GetNewClosure())
        Candidate=({param($p,$c) ConvertTo-AnsiStripCandidate -Pixels $p -Width 320 -Height 200 -FirstColumn 0 -EndColumn 20 -Context $c}.GetNewClosure())
    }
    ColorState=@{
        Baseline=({param($p,$c) ConvertTo-AnsiColorStateStripBaseline -Pixels $p -Width 320 -Height 200 -FirstColumn 0 -EndColumn 20 -Context $c}.GetNewClosure())
        Candidate=({param($p,$c) ConvertTo-AnsiColorStateStripCandidate -Pixels $p -Width 320 -Height 200 -FirstColumn 0 -EndColumn 20 -Context $c}.GetNewClosure())
    }
}
$rows=[Collections.Generic.List[object]]::new()
foreach($pattern in @('Coherent','Entropy')){
    $pixels=New-IndexedFrame -Width 320 -Height 200 -Pattern $pattern -Colors 256
    foreach($mode in @('Pairs','ColorState')){
        if($mode -eq 'Pairs'){
            $baselineContext=New-CodecContextBaseline $palette
            $candidateContext=New-CodecContextCandidate $palette
        }else{
            $baselineContext=New-ColorStateBenchmarkContext {param($p) New-CodecContextBaseline $p -LazyCells} $palette
            $candidateContext=New-ColorStateBenchmarkContext {param($p) New-CodecContextCandidate $p -LazyCells} $palette
        }
        $baselineEncoder=[scriptblock]$modeEncoders[$mode].Baseline
        $candidateEncoder=[scriptblock]$modeEncoders[$mode].Candidate
        [byte[]]$baselineBytes=& $baselineEncoder $pixels $baselineContext
        [byte[]]$candidateBytes=& $candidateEncoder $pixels $candidateContext
        $baselineHash=Get-StripHash $baselineBytes
        $candidateHash=Get-StripHash $candidateBytes
        if($baselineHash -ne $candidateHash){throw "$mode/$pattern output differs between the pinned versions."}

        for([int]$warm=0;$warm -lt 4;$warm++){
            $null=& $baselineEncoder $pixels $baselineContext
            $null=& $candidateEncoder $pixels $candidateContext
        }
        $samples=[Collections.Generic.List[object]]::new()
        for([int]$round=0;$round -lt $Rounds;$round++){
            $order=if($round%2){@('Candidate','Baseline','Baseline','Candidate')}else{@('Baseline','Candidate','Candidate','Baseline')}
            foreach($version in $order){
                if($version -eq 'Baseline'){
                    $sample=Measure-StripBlock $baselineEncoder $pixels $baselineContext $IterationsPerBlock
                }else{
                    $sample=Measure-StripBlock $candidateEncoder $pixels $candidateContext $IterationsPerBlock
                }
                $samples.Add([pscustomobject]@{Round=$round+1;Version=$version;ElapsedMs=$sample.ElapsedMs;
                    MsPerCall=$sample.MsPerCall;AllocatedBytesPerCall=$sample.AllocatedBytesPerCall;
                    Calls=$sample.Calls;OutputBytes=$sample.OutputBytes})
            }
        }
        $baselineSamples=@($samples | Where-Object Version -eq 'Baseline')
        $candidateSamples=@($samples | Where-Object Version -eq 'Candidate')
        $baselineStats=Get-BlockStatistics $baselineSamples
        $candidateStats=Get-BlockStatistics $candidateSamples
        $rows.Add([ordered]@{
            Mode=$mode;Pattern=$pattern;StripColumns=20;Frame='320x200';WarmupCallsPerVersion=4
            BaselineOutputSha256=$baselineHash;CandidateOutputSha256=$candidateHash;OutputsByteExact=$true
            Baseline=$baselineStats;Candidate=$candidateStats
            MedianTimeReductionPercent=if($baselineStats.MedianMsPerCall -gt 0){100*($baselineStats.MedianMsPerCall-$candidateStats.MedianMsPerCall)/$baselineStats.MedianMsPerCall}else{$null}
            MedianAllocationReductionPercent=if($baselineStats.MedianAllocatedBytesPerCall -gt 0){100*($baselineStats.MedianAllocatedBytesPerCall-$candidateStats.MedianAllocatedBytesPerCall)/$baselineStats.MedianAllocatedBytesPerCall}else{$null}
            Samples=$samples.ToArray()
        })
    }
}

$sources=[ordered]@{}
foreach($path in $sourcePaths){
    $sources[$path]=@{
        BaselineGitBlob=(Get-GitBlobId $baselineCommit $path)
        CandidateGitBlob=(Get-GitBlobId $candidateCommit $path)
    }
}
$report=[ordered]@{
    Format='pwshDoom.AnsiStripReuseMeasurement';CreatedUtc=[DateTime]::UtcNow.ToString('o')
    BaselineCommit=$baselineCommit;CandidateSourceCommit=$candidateCommit;WorkingHead=$headCommit
    PowerShell=$PSVersionTable.PSVersion.ToString();DotNet=[Environment]::Version.ToString()
    OS=[Environment]::OSVersion.VersionString;ProcessArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    Processor=$env:PROCESSOR_IDENTIFIER;SourceGitBlobs=$sources
    Protocol='Pinned pre-change functions and candidate functions are warmed, then measured in ABBA order on the same thread. Each call encodes one production-width 20-column by 200-pixel strip from the same 320x200 indexed frame. Context construction and caches are outside timed blocks. Managed allocation counts are GetAllocatedBytesForCurrentThread deltas. No workers, engine rendering, simulation, terminal writes, concurrent load or display pacing are included.'
    IterationsPerBlock=$IterationsPerBlock;Rounds=$Rounds;WorkersRepresented=16
    Workloads=@('Synthetic coherent tiled indexed frame','Synthetic high-entropy indexed frame')
    Results=$rows.ToArray()
    Conclusion='Isolated per-strip timing and current-thread allocation only; exact output is required. This does not establish whole-image, worker-contention, live game, terminal display, or 35-tic/60-display performance.'
}
$resolved=[IO.Path]::GetFullPath($Output)
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($resolved))
[IO.File]::WriteAllText($resolved,($report|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
$saved=Get-Content -LiteralPath $resolved -Raw|ConvertFrom-Json
foreach($row in $saved.Results){
    Write-Output ('{0}/{1}: median {2:N2} -> {3:N2} ms/call; allocated {4:N0} -> {5:N0} B/call; exact={6}' -f
        $row.Mode,$row.Pattern,$row.Baseline.MedianMsPerCall,$row.Candidate.MedianMsPerCall,
        $row.Baseline.MedianAllocatedBytesPerCall,$row.Candidate.MedianAllocatedBytesPerCall,$row.OutputsByteExact)
}
Write-Output "Raw measurements: $resolved"
