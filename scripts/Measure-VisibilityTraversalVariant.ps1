#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param(
    [Parameter(Mandatory)][ValidateSet('Reference','Iterative')][string]$Variant,
    [Parameter(Mandatory)][string]$Replay,
    [Parameter(Mandatory)][string]$Output,
    [switch]$EveryTic,
    [string]$SourceRoot=(Join-Path $PSScriptRoot '../src/ManagedDoom'),
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD'
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh visibility variant report.'}
$owned=Join-Path "$PSScriptRoot/../local" ('visibility-variant-'+$Variant.ToLowerInvariant()+'-'+[guid]::NewGuid().ToString('N'))
$sourceRootPath=[IO.Path]::GetFullPath($SourceRoot)
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -SourceRoot $sourceRootPath -Output "$owned/engine.ps1"
$engineHash=(Get-FileHash $bundle).Hash
$source=[IO.File]::ReadAllText($bundle)
$sourceHasTraversalStack=$source.Contains('BspPendingNodeNumbers')
if($Variant -eq 'Iterative' -and -not $sourceHasTraversalStack){
    $source=$source.Replace('class VisibilityCheck {',"class VisibilityCheck {`n    [int[]]`$BspPendingNodeNumbers=[int[]]::new(64)`n    [int]`$BspPendingCount=0")
}
if($Variant -in @('Reference','Iterative')){
    $tokens=$null;$issues=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$issues)
    if($issues.Count){throw 'Cannot parse engine bundle before applying iterative BSP walk.'}
    $type=$ast.Find({param($node) $node -is [Management.Automation.Language.TypeDefinitionAst] -and $node.Name -eq 'VisibilityCheck'},$false)
    $method=@($type.Members|Where-Object {$_.Name -eq 'CrossBspNode' -and $_ -is [Management.Automation.Language.FunctionMemberAst]})
    if($method.Count -ne 1){throw 'Expected one visibility node walk method.'}
    $old=$method[0].Body.Extent.Text
    if($Variant -eq 'Iterative' -and $sourceHasTraversalStack){
        $replacement=$old
    } elseif($Variant -eq 'Iterative'){
        $replacement=@'
{
        $map = $this.World.Map
        if ($this.BspPendingNodeNumbers.Length -lt $map.Nodes.Length + 1) {
            $this.BspPendingNodeNumbers = [int[]]::new($map.Nodes.Length + 1)
        }
        $this.BspPendingCount = 0
        while ($true) {
            if ([Node]::IsSubsector($nodeNumber)) {
                if ($nodeNumber -eq -1) {
                    if (-not $this.CrossSubsector(0, $validCount)) { return $false }
                } else {
                    if (-not $this.CrossSubsector([Node]::GetSubsector($nodeNumber), $validCount)) { return $false }
                }
                if ($this.BspPendingCount -eq 0) { return $true }
                $this.BspPendingCount--
                $nodeNumber = $this.BspPendingNodeNumbers[$this.BspPendingCount]
                continue
            }

            $node = $map.Nodes[$nodeNumber]
            $side = [Geometry]::DivLineSide($this.Trace.X, $this.Trace.Y, $node)
            if ($side -eq 2) { $side = 0 }
            $targetSide = [Geometry]::DivLineSide($this.TargetX, $this.TargetY, $node)
            if ($side -ne $targetSide) {
                if ($this.BspPendingCount -ge $this.BspPendingNodeNumbers.Length) {
                    $grown = [int[]]::new($this.BspPendingNodeNumbers.Length * 2)
                    [Array]::Copy($this.BspPendingNodeNumbers, $grown, $this.BspPendingCount)
                    $this.BspPendingNodeNumbers = $grown
                }
                $this.BspPendingNodeNumbers[$this.BspPendingCount] = $node.Children[$side -bxor 1]
                $this.BspPendingCount++
            }
            $nodeNumber = $node.Children[$side]
        }
        return $false
    }
'@
    } else {
        $replacement=@'
{
        if ([Node]::IsSubsector($nodeNumber)) {
            if ($nodeNumber -eq -1) {
                return $this.CrossSubsector(0, $validCount)
            } else {
                return $this.CrossSubsector([Node]::GetSubsector($nodeNumber), $validCount)
            }
        }

        $node = $this.World.Map.Nodes[$nodeNumber]
        $side = [Geometry]::DivLineSide($this.Trace.X, $this.Trace.Y, $node)
        if ($side -eq 2) { $side = 0 }
        if (-not $this.CrossBspNode($node.Children[$side], $validCount)) { return $false }
        if ($side -eq [Geometry]::DivLineSide($this.TargetX, $this.TargetY, $node)) { return $true }
        return $this.CrossBspNode($node.Children[$side -bxor 1], $validCount)
    }
'@
    }
    $source=$source.Remove($method[0].Body.Extent.StartOffset,$old.Length).Insert($method[0].Body.Extent.StartOffset,$replacement.TrimEnd())
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$issues)
    if($issues.Count){$issueText=@($issues|ForEach-Object {$_.Message}) -join '; ';throw "$Variant visibility bundle parse failed: $issueText"}
    $bundle="$owned/$Variant-engine.ps1"
    [IO.File]::WriteAllText($bundle,$source,[Text.UTF8Encoding]::new($false))
}
$executedHash=(Get-FileHash $bundle).Hash
. $bundle
. "$PSScriptRoot/FrameCodec.ps1"
. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"
. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$reference=Read-DoomInputReplay $Replay (Get-FileHash $Wad).Hash
$content=$null;$failure=$null;$completed=0;$verification=$null
$samples=[Collections.Generic.List[double]]::new()
$timeline=[Collections.Generic.List[object]]::new()
$points=[Collections.Generic.List[object]]::new()
try{
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad))
    $options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode
    $options.GameVersion=$content.Wad.GameVersion
    $options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options)
    $commands=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]([int]$reference.Skill-1),$reference.Episode,$reference.Map)
    $null=$game.Update($commands)
    $expected=@{}
    foreach($point in $reference.Checkpoints){$expected[[int]$point.Tic]=$true}
    $points.Add((Get-DoomReplayCheckpoint $game 0))
    for($i=0;$i -lt [Math]::Min(1200,$reference.InputCommands.Count);$i++){
        $entry=$reference.InputCommands[$i]
        $cmd=$commands[0]
        $cmd.Clear()
        $cmd.ForwardMove=$entry[0]
        $cmd.SideMove=$entry[1]
        $cmd.AngleTurn=$entry[2]
        $cmd.Buttons=$entry[3]
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $null=$game.Update($commands)
        $samples.Add($watch.Elapsed.TotalMilliseconds)
        $completed++
        if($EveryTic){
            $point=Get-DoomReplayCheckpoint $game $completed
            $timeline.Add(@{Tic=$completed;Sha256=$point.Sha256;CurrentRenderSnapshotSha256=$point.CurrentRenderSnapshotSha256})
        }
        if($expected.ContainsKey($completed)){$points.Add((Get-DoomReplayCheckpoint $game $completed))}
    }
    if($points[-1].Tic -ne $completed){$points.Add((Get-DoomReplayCheckpoint $game $completed))}
    $verification=Compare-DoomReplayCheckpoints $reference.Checkpoints $points.ToArray() $completed
    if(-not $verification.Matched){throw 'Visibility variant diverged from a stored replay checkpoint.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    $result=@{
        Variant=$Variant;Error=$failure;Commands=$completed;EveryTic=[bool]$EveryTic
        FinishedUtc=(Get-Date).ToUniversalTime().ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString()
        EngineSourceBundleSha256=$engineHash;ExecutedBundleSha256=$executedHash
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;ReplaySha256=(Get-FileHash $Replay).Hash;WadSha256=(Get-FileHash $Wad).Hash
        ReplayVerification=$verification;Checkpoints=$points.ToArray();Timeline=$timeline.ToArray()
        UpdateMilliseconds=if($samples.Count){Get-SampleStats $samples.ToArray()}else{$null}
        Samples=$samples.ToArray()
        Meaning='Headless source-only replay. Game.Update time excludes the selected checkpoint/timeline hashing. Every-tic timeline entries compare combined state and current renderer snapshot checkpoint hashes; stored replay checkpoints cover selected endpoints, not every hidden state field. Timing is simulation-only and excludes renderer workers, terminal, audio/device mixing and display pacing.'
    }
    [IO.File]::WriteAllText((Join-Path (Get-Location) $Output),($result|ConvertTo-Json -Depth 8)+"`n",[Text.UTF8Encoding]::new($false))
}
if($failure){throw $failure}
"PASS: $Variant; $completed commands; $($verification.Checked) stored checkpoints."
