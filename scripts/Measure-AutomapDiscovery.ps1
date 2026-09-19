#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Replay,[Parameter(Mandatory)][string]$Output,
    [switch]$Profile,[string]$ReferenceReport,[ValidateRange(1,1260000)][int]$MaxCommands=1200,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh discovery report.'}
$owned=Join-Path "$PSScriptRoot/../local" ('discovery-profile-'+[guid]::NewGuid().ToString('N'))
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$owned/baseline.ps1"
$baselineHash=(Get-FileHash $bundle).Hash
$methods=@(@('Geometry','PointOnSide'),@('Geometry','PointToAngleData'),
    @('ThreeDRenderer','DiscoverSeg'),@('ThreeDRenderer','ProjectDiscoveryAngles'),
    @('ThreeDRenderer','IsPotentiallyVisible'),@('ThreeDRenderer','DrawSolidWall'),@('ThreeDRenderer','DrawPassWall'))
if($Profile){
    $source=[IO.File]::ReadAllText($bundle)
    $tokens=$null;$issues=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$issues)
    $edits=@(for($index=0;$index -lt $methods.Count;$index++){
        $typeName=$methods[$index][0];$methodName=$methods[$index][1]
        $type=$ast.Find({param($n) $n -is [Management.Automation.Language.TypeDefinitionAst] -and $n.Name -eq $typeName},$false)
        $member=@($type.Members|Where-Object {$_ -is [Management.Automation.Language.FunctionMemberAst] -and $_.Name -eq $methodName})
        if($member.Count -ne 1){throw "Ambiguous profile method $typeName.$methodName"}
        $body=$member[0].Body.Extent
        $changed='{[long]$profileStart=[Diagnostics.Stopwatch]::GetTimestamp();[Geometry]::DiscoveryProfileCounts['+$index+']++;try{'+$body.Text.Substring(1,$body.Text.Length-2)+
            '}finally{[Geometry]::DiscoveryProfileTicks['+$index+']+=[Diagnostics.Stopwatch]::GetTimestamp()-$profileStart;}}'
        @{Start=$body.StartOffset;Length=$body.Text.Length;Text=$changed}
    })
    foreach($edit in @($edits|Sort-Object Start -Descending)){$source=$source.Remove($edit.Start,$edit.Length).Insert($edit.Start,$edit.Text)}
    $source=$source.Replace('class Geometry {',('class Geometry {'+"`n"+'static [long[]]$DiscoveryProfileTicks=[long[]]::new(7)'+"`n"+'static [long[]]$DiscoveryProfileCounts=[long[]]::new(7)'+"`n"))
    $bundle="$owned/instrumented.ps1";[IO.File]::WriteAllText($bundle,$source,[Text.UTF8Encoding]::new($false))
}
. $bundle
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$reference=Read-DoomInputReplay $Replay (Get-FileHash $Wad).Hash
$baseline=if($ReferenceReport){Get-Content $ReferenceReport -Raw|ConvertFrom-Json}else{$null}
if($baseline -and ($baseline.Error -or $baseline.ReplaySha256 -cne (Get-FileHash $Replay).Hash -or $baseline.BaselineBundleSha256 -cne $baselineHash)){throw 'Reference is failed or has different source/commands.'}
$samples=[Collections.Generic.List[object]]::new();$points=[Collections.Generic.List[object]]::new()
$content=$null;$failure=$null;$completed=0;$verification=$null;$mappingComparisons=0
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]([int]$reference.Skill-1),$reference.Episode,$reference.Map);$null=$game.Update($commands)
    $renderer=[ThreeDRenderer]::new($content,[DrawScreen]::new($content.Wad,320,200),7)
    $renderer.DiscoverMap($game.World.ConsolePlayer)
    $expected=@{};foreach($point in $reference.Checkpoints){$expected[[int]$point.Tic]=$true}
    $points.Add((Get-DoomReplayCheckpoint $game 0))
    for($i=0;$i -lt [Math]::Min($MaxCommands,$reference.InputCommands.Count);$i++){
        $entry=$reference.InputCommands[$i];$cmd=$commands[0];$cmd.Clear()
        $cmd.ForwardMove=$entry[0];$cmd.SideMove=$entry[1];$cmd.AngleTurn=$entry[2];$cmd.Buttons=$entry[3]
        $null=$game.Update($commands);$completed++
        if($Profile){[Array]::Clear([Geometry]::DiscoveryProfileTicks);[Array]::Clear([Geometry]::DiscoveryProfileCounts)}
        $watch=[Diagnostics.Stopwatch]::StartNew()
        if([int]$game.State -eq 0){$renderer.DiscoverMap($game.World.ConsolePlayer)}
        $elapsed=$watch.Elapsed.TotalMilliseconds
        $mapped=[byte[]]::new($game.World.Map.Lines.Length)
        for($line=0;$line -lt $mapped.Length;$line++){$mapped[$line]=[byte](($game.World.Map.Lines[$line].Flags -band 256) -ne 0)}
        $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($mapped))
        if($baseline){if($i -ge $baseline.Samples.Count -or $hash -cne $baseline.Samples[$i].MappedSha256){throw "Discovery mapping differs at $completed"};$mappingComparisons++}
        $samples.Add(@{Command=$completed;State=[int]$game.State;Episode=$game.Options.Episode;Map=$game.Options.Map;
            DiscoveryMs=$elapsed;MappedSha256=$hash;ProfileTicks=if($Profile){[Geometry]::DiscoveryProfileTicks.Clone()}else{$null};
            ProfileCounts=if($Profile){[Geometry]::DiscoveryProfileCounts.Clone()}else{$null}})
        if($expected.ContainsKey($completed)){$points.Add((Get-DoomReplayCheckpoint $game $completed))}
    }
    if($points[-1].Tic -ne $completed){$points.Add((Get-DoomReplayCheckpoint $game $completed))}
    $verification=Compare-DoomReplayCheckpoints $reference.Checkpoints $points.ToArray() $completed
    if(-not $verification.Matched){throw 'Discovery replay differs from original gameplay checkpoints.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Profile=[bool]$Profile;Commands=$completed;MappingComparisons=$mappingComparisons;
        BaselineBundleSha256=$baselineHash;ExecutedBundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        ReplaySha256=(Get-FileHash $Replay).Hash;WadSha256=(Get-FileHash $Wad).Hash;ReferenceReportSha256=if($ReferenceReport){(Get-FileHash $ReferenceReport).Hash}else{$null};
        QpcFrequency=[Diagnostics.Stopwatch]::Frequency;MethodOrder=@($methods|ForEach-Object {$_ -join '.'});
        DiscoveryMs=(Get-SampleStats ([double[]]$samples.DiscoveryMs));Samples=$samples.ToArray();ReplayVerification=$verification;Checkpoints=$points.ToArray();OwnedBundle=$bundle;
        Meaning='Unpaced simulation and endpoint discovery only. Optional method timers exist in an owned bundle and include substantial instrumentation overhead; nested inclusive times overlap. Timers reset after gameplay. All post-command discovery samples retained; initial discovery is outside timing. Complete per-command mapped-line bitsets are hashed outside timing and may be compared with an uninstrumented run. Not loaded-host or display FPS.'}|
        ConvertTo-Json -Depth 10|Set-Content -LiteralPath $Output
}
if($failure){throw $failure}
"PASS: $completed commands, $($verification.Checked) original checkpoints, $mappingComparisons mapping comparisons."
