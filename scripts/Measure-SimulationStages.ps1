#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Replay,[Parameter(Mandatory)][string]$Output,[switch]$Profile,[switch]$ActorProfile,
    [ValidateRange(1,1260000)][int]$MaxCommands=1200,
    [string]$SourceRoot=(Join-Path $PSScriptRoot '../src/ManagedDoom'),
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if($ActorProfile){$Profile=$true}
if(Test-Path -LiteralPath $Output){throw 'Use a fresh stage measurement report.'}
$owned=Join-Path "$PSScriptRoot/../local" ('game-profile-'+[guid]::NewGuid().ToString('N'))
$sourceRootPath=[IO.Path]::GetFullPath($SourceRoot)
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -SourceRoot $sourceRootPath -Output "$owned/baseline.ps1"
$baselineHash=(Get-FileHash $bundle).Hash
$labels=@('PlayerInterpolation','ThinkerInterpolation','SectorInterpolation','PlayerThink','ThinkersRun','Specials','RespawnSpecials','StatusBar','AutoMap')
if($Profile){
    $source=[IO.File]::ReadAllText($bundle)
    $tokens=$null;$issues=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$issues)
    $world=$ast.Find({param($node) $node -is [Management.Automation.Language.TypeDefinitionAst] -and $node.Name -eq 'World'},$false)
    $method=@($world.Members|Where-Object {$_.Name -eq 'Update' -and $_ -is [Management.Automation.Language.FunctionMemberAst] -and $_.Parameters.Count -eq 0})
    if($method.Count -ne 1){throw 'Expected one World.Update method.'}
    $body=$method[0].Body.Extent.Text
    function Replace-Once([string]$Text,[string]$Marker,[string]$Replacement){
        if([regex]::Matches($Text,[regex]::Escape($Marker)).Count -ne 1){throw "Missing or ambiguous profiler marker: $Marker"}
        return $Text.Replace($Marker,$Replacement)
    }
    function Replace-AllExpected([string]$Text,[string]$Marker,[string]$Replacement,[int]$Expected){
        $count=[regex]::Matches($Text,[regex]::Escape($Marker)).Count
        if($count -ne $Expected){throw "Unexpected profiler marker count ($count/$Expected): $Marker"}
        return $Text.Replace($Marker,$Replacement)
    }
    function Edit-MethodBody([string]$Text,[string]$TypeName,[string]$MethodName,[scriptblock]$Edit){
        $localTokens=$null;$localIssues=$null
        $localAst=[Management.Automation.Language.Parser]::ParseInput($Text,[ref]$localTokens,[ref]$localIssues)
        if($localIssues.Count){throw "Cannot parse source before profiling $TypeName.$MethodName."}
        $localType=$localAst.Find({param($node) $node -is [Management.Automation.Language.TypeDefinitionAst] -and $node.Name -eq $TypeName},$false)
        $localMethods=@($localType.Members|Where-Object {$_.Name -eq $MethodName -and $_ -is [Management.Automation.Language.FunctionMemberAst]})
        if($localMethods.Count -ne 1){throw "Expected one $TypeName.$MethodName method."}
        $oldBody=$localMethods[0].Body.Extent.Text
        $newBody=& $Edit $oldBody
        if($newBody -isnot [string]){throw "Profiler did not return a string for $TypeName.$MethodName."}
        return $Text.Remove($localMethods[0].Body.Extent.StartOffset,$oldBody.Length).Insert($localMethods[0].Body.Extent.StartOffset,$newBody)
    }
    function End-Stage([int]$Index){
        return ('$pfNow=[Diagnostics.Stopwatch]::GetTimestamp();$this.ProfileTicks['+$Index+']+=$pfNow-$pfStart;$pfStart=$pfNow;')
    }
    $changed=$body.Insert(1,"`n"+'[long]$pfStart=[Diagnostics.Stopwatch]::GetTimestamp();[long]$pfNow=0;' + "`n")
    $marker='$this.Thinkers.UpdateFrameInterpolationInfo()'
    $changed=Replace-Once $changed $marker ((End-Stage 0)+$marker+';'+(End-Stage 1))
    $marker='for ($i = 0; $i -lt [Player]::MaxPlayerCount; $i++) {'+"`r`n"+'            if ($players[$i].InGame) {'+"`r`n"+'                $this.PlayerBehavior.PlayerThink($players[$i])'
    if(-not $changed.Contains($marker)){$marker=$marker.Replace("`r`n","`n")}
    $changed=Replace-Once $changed $marker ((End-Stage 2)+$marker)
    $changed=Replace-Once $changed '$this.Thinkers.Run()' ((End-Stage 3)+'$this.Thinkers.Run();'+(End-Stage 4))
    $index=5
    foreach($marker in @('$this.Specials.Update()','$this.ThingAllocation.RespawnSpecials()','$this.StatusBar.Update()','$this.AutoMap.Update()')){
        $changed=Replace-Once $changed $marker ($marker+';'+(End-Stage $index));$index++
    }
    # Edit only this method body and the owned World's diagnostic property.
    $source=$source.Remove($method[0].Body.Extent.StartOffset,$body.Length).Insert($method[0].Body.Extent.StartOffset,$changed)
    $source=Replace-Once $source 'class World {' ('class World {'+"`n"+'    [long[]]$ProfileTicks=[long[]]::new(9)'+"`n"+'    [long[]]$ProfileActorTicks=[long[]]::new(4)'+"`n"+'    [long[]]$ProfileActorCounts=[long[]]::new(6)'+"`n"+'    [long[]]$ProfileSightCounts=[long[]]::new(12)'+"`n"+'    [long[]]$ProfileActionTicks=[long[]]::new(52)'+"`n"+'    [long[]]$ProfileActionCounts=[long[]]::new(52)'+"`n"+'    [long[]]$ProfileHitscanTicks=[long[]]::new(2)'+"`n"+'    [long[]]$ProfileHitscanCounts=[long[]]::new(2)'+"`n"+'    [long[]]$ProfilePathCounts=[long[]]::new(7)'+"`n"+'    [long[]]$ProfileInterceptBuckets=[long[]]::new(8)'+"`n"+'    [int]$ProfileMaxInterceptCount=0'+"`n")
    if($ActorProfile){
        $index=0
        foreach($axis in @('XY','Z')){
            $marker='$this.world.ThingMovement.'+$axis+'Movement($this)'
            $redundant=if($axis -eq 'XY'){'$this.momX.Data -eq 0 -and $this.momY.Data -eq 0 -and ($this.flags -band [MobjFlags]::SkullFly) -eq 0'}else{'$this.z.Data -eq $this.floorZ.Data -and $this.momZ.Data -eq 0'}
            $replacement='$this.world.ProfileActorCounts['+$index+']++;if('+$redundant+'){$this.world.ProfileActorCounts['+($index+2)+']++};[long]$pfActorStart=[Diagnostics.Stopwatch]::GetTimestamp();'+$marker+';$this.world.ProfileActorTicks['+$index+']+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfActorStart;'
            $source=Replace-Once $source $marker $replacement;$index++
        }
        $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$issues)
        if($issues.Count){throw 'Cannot parse the staged actor profiler source.'}
        $directActions=$ast.Find({param($node) $node -is [Management.Automation.Language.TypeDefinitionAst] -and $node.Name -eq 'MobjActions'},$false)
        $dispatch=@($directActions.Members|Where-Object {$_.Name -eq 'InvokeStateAction' -and $_ -is [Management.Automation.Language.FunctionMemberAst]})
        if($dispatch.Count -eq 1){
            $body=$dispatch[0].Body.Extent.Text
            $changed='{'+('$world.ProfileActorCounts[4]++;[long]$pfActionStart=[Diagnostics.Stopwatch]::GetTimestamp();try{')+$body.Substring(1,$body.Length-2)+'}finally{$world.ProfileActorTicks[2]+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfActionStart;}}'
            $source=$source.Remove($dispatch[0].Body.Extent.StartOffset,$body.Length).Insert($dispatch[0].Body.Extent.StartOffset,$changed)
            $actorActionInstrumentation='MobjActions.InvokeStateAction (inclusive)'

            $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$issues)
            if($issues.Count){throw 'Cannot parse direct router before per-action profiling.'}
            $actionType=$ast.Find({param($node) $node -is [Management.Automation.Language.TypeDefinitionAst] -and $node.Name -eq 'MobjActions'},$false)
            $actionMethod=@($actionType.Members|Where-Object {$_.Name -eq 'InvokeStateAction' -and $_ -is [Management.Automation.Language.FunctionMemberAst]})
            $actionSwitch=$actionMethod[0].Body.Find({param($node) $node -is [Management.Automation.Language.SwitchStatementAst]},$false)
            if($null -eq $actionSwitch -or $actionSwitch.Clauses.Count -ne 52){throw 'Expected 52 action cases for per-action timing.'}
            $actionNames=[Collections.Generic.List[string]]::new()
            $actionEdits=[Collections.Generic.List[object]]::new()
            for($actionIndex=0;$actionIndex -lt $actionSwitch.Clauses.Count;$actionIndex++){
                $clause=$actionSwitch.Clauses[$actionIndex]
                if($clause.Item1 -isnot [Management.Automation.Language.StringConstantExpressionAst]){throw 'Direct action case name is not a string constant.'}
                $actionName=[string]$clause.Item1.Value
                $actionNames.Add($actionName)
                $branch=$clause.Item2.Extent.Text
                $wrapped='{'+('$world.ProfileActionCounts['+$actionIndex+']++;[long]$pfOneActionStart=[Diagnostics.Stopwatch]::GetTimestamp();try{')+$branch.Substring(1,$branch.Length-2)+'}finally{$world.ProfileActionTicks['+$actionIndex+']+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfOneActionStart;}}'
                $actionEdits.Add(@{Offset=$clause.Item2.Extent.StartOffset;Length=$branch.Length;Text=$wrapped})
            }
            foreach($edit in ($actionEdits|Sort-Object Offset -Descending)){$source=$source.Remove($edit.Offset,$edit.Length).Insert($edit.Offset,$edit.Text)}
        }else{
            $marker='$st.MobjAction.Invoke($this.world, $this)'
            $source=Replace-Once $source $marker ('$this.world.ProfileActorCounts[4]++;[long]$pfActionStart=[Diagnostics.Stopwatch]::GetTimestamp();'+$marker+';$this.world.ProfileActorTicks[2]+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfActionStart;')
            $actorActionInstrumentation='PSMethod.Invoke (inclusive)'
            $actionNames=@()
        }
        $source=Edit-MethodBody $source 'Hitscan' 'AimLineAttack' {
            param($body)
            return '{[long]$pfHitscanStart=[Diagnostics.Stopwatch]::GetTimestamp();$this.World.ProfileHitscanCounts[0]++;try{'+$body.Substring(1,$body.Length-2)+'}finally{$this.World.ProfileHitscanTicks[0]+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfHitscanStart;}}'
        }
        $source=Edit-MethodBody $source 'Hitscan' 'LineAttack' {
            param($body)
            return '{[long]$pfHitscanStart=[Diagnostics.Stopwatch]::GetTimestamp();$this.World.ProfileHitscanCounts[1]++;try{'+$body.Substring(1,$body.Length-2)+'}finally{$this.World.ProfileHitscanTicks[1]+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfHitscanStart;}}'
        }
        $source=Edit-MethodBody $source 'PathTraversal' 'AddLineIntercepts' {param($body) $body.Insert(1,'$this.World.ProfilePathCounts[3]++;')}
        $source=Edit-MethodBody $source 'PathTraversal' 'AddThingIntercepts' {param($body) $body.Insert(1,'$this.World.ProfilePathCounts[4]++;')}
        $source=Edit-MethodBody $source 'PathTraversal' 'InterceptVector' {param($body) $body.Insert(1,'$this.World.ProfilePathCounts[5]++;')}
        $source=Edit-MethodBody $source 'PathTraversal' 'TraverseIntercepts' {
            param($body)
            return (Replace-Once $body 'for ($i = 0; $i -lt $this.InterceptCount; $i++) {' 'for ($i = 0; $i -lt $this.InterceptCount; $i++) {$this.World.ProfilePathCounts[6]++;')
        }
        $source=Edit-MethodBody $source 'PathTraversal' 'PathTraverse' {
            param($body)
            $body=$body.Insert(1,'$this.World.ProfilePathCounts[0]++;')
            $body=Replace-Once $body 'for ($count = 0; $count -lt 64; $count++) {' 'for ($count = 0; $count -lt 64; $count++) {$this.World.ProfilePathCounts[1]++;'
            $body=Replace-Once $body 'return $this.TraverseIntercepts($trav, [Fixed]::One)' '$n=$this.InterceptCount;$this.World.ProfilePathCounts[2]+=$n;if($n -gt $this.World.ProfileMaxInterceptCount){$this.World.ProfileMaxInterceptCount=$n};$bucket=if($n -le 0){0}elseif($n -le 2){1}elseif($n -le 4){2}elseif($n -le 8){3}elseif($n -le 16){4}elseif($n -le 32){5}elseif($n -le 64){6}else{7};$this.World.ProfileInterceptBuckets[$bucket]++;return $this.TraverseIntercepts($trav, [Fixed]::One)'
            return $body
        }
        $source=Edit-MethodBody $source 'VisibilityCheck' 'CrossBspNode' {param($body) $body.Insert(1,'$this.World.ProfileSightCounts[0]++;')}
        $source=Edit-MethodBody $source 'VisibilityCheck' 'CrossSubsector' {
            param($body)
            $body=$body.Insert(1,'$this.World.ProfileSightCounts[1]++;')
            $body=Replace-Once $body 'for ($i = 0; $i -lt $count; $i++) {' 'for ($i = 0; $i -lt $count; $i++) {$this.World.ProfileSightCounts[2]++;'
            $body=Replace-Once $body 'if ($line.ValidCount -eq $validCount) { continue }' 'if ($line.ValidCount -eq $validCount) { continue };$this.World.ProfileSightCounts[3]++;'
            $body=Replace-AllExpected $body 'if ($s1 -eq $s2) { continue }' 'if ($s1 -eq $s2) {$this.World.ProfileSightCounts[4]++;continue}' 2
            $body=Replace-Once $body 'if ($null -eq $line.BackSector) { return $false }' 'if ($null -eq $line.BackSector) {$this.World.ProfileSightCounts[5]++;return $false}'
            $body=Replace-Once $body 'if (($line.Flags -band [LineFlags]::TwoSided) -eq 0) { return $false }' 'if (($line.Flags -band [LineFlags]::TwoSided) -eq 0) {$this.World.ProfileSightCounts[5]++;return $false}'
            $body=Replace-Once $body 'if ($openBottom.Data -ge $openTop.Data) { return $false }' 'if ($openBottom.Data -ge $openTop.Data) {$this.World.ProfileSightCounts[6]++;return $false}'
            $body=Replace-Once $body '$fracData = $this.InterceptVectorData($this.Trace, $this.Occluder)' '$this.World.ProfileSightCounts[7]++;$fracData = $this.InterceptVectorData($this.Trace, $this.Occluder)'
            $body=Replace-AllExpected $body '$slopeData = $this.DivideFixedData($slopeNumerator, $fracData)' '$this.World.ProfileSightCounts[8]++;$slopeData = $this.DivideFixedData($slopeNumerator, $fracData)' 2
            $body=Replace-Once $body 'if ($this.TopSlope.Data -le $this.BottomSlope.Data) { return $false }' 'if ($this.TopSlope.Data -le $this.BottomSlope.Data) {$this.World.ProfileSightCounts[9]++;return $false}'
            return $body
        }
        $source=Edit-MethodBody $source 'VisibilityCheck' 'CheckSight' {
            param($body)
            $body=Replace-Once $body 'if ($map.Reject.Check($looker.Subsector.Sector, $target.Subsector.Sector)) {' 'if ($map.Reject.Check($looker.Subsector.Sector, $target.Subsector.Sector)) {$this.World.ProfileSightCounts[10]++;'
            return '{[long]$pfSightStart=[Diagnostics.Stopwatch]::GetTimestamp();$this.World.ProfileActorCounts[5]++;try{'+$body.Substring(1,$body.Length-2)+'}finally{$this.World.ProfileActorTicks[3]+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfSightStart;}}'
        }
    }
    $bundle="$owned/instrumented.ps1";[IO.File]::WriteAllText($bundle,$source,[Text.UTF8Encoding]::new($false))
}
. $bundle
. "$PSScriptRoot/FrameCodec.ps1";. "$PSScriptRoot/../src/InputReplay.ps1"
. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1"
$reference=Read-DoomInputReplay $Replay (Get-FileHash $Wad).Hash
$content=$null;$failure=$null;$completed=0;$verification=$null
$samples=[Collections.Generic.List[object]]::new();$points=[Collections.Generic.List[object]]::new()
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]([int]$reference.Skill-1),$reference.Episode,$reference.Map);$null=$game.Update($commands)
    $expected=@{};foreach($point in $reference.Checkpoints){$expected[[int]$point.Tic]=$true}
    $points.Add((Get-DoomReplayCheckpoint $game 0))
    for($i=0;$i -lt [Math]::Min($MaxCommands,$reference.InputCommands.Count);$i++){
        $entry=$reference.InputCommands[$i];$cmd=$commands[0];$cmd.Clear()
        $cmd.ForwardMove=$entry[0];$cmd.SideMove=$entry[1];$cmd.AngleTurn=$entry[2];$cmd.Buttons=$entry[3]
        $beforeWorld=$game.World;$before=if($Profile){$beforeWorld.ProfileTicks.Clone()}
        if($ActorProfile){$beforeActorTicks=$beforeWorld.ProfileActorTicks.Clone();$beforeActorCounts=$beforeWorld.ProfileActorCounts.Clone();$beforeSightCounts=$beforeWorld.ProfileSightCounts.Clone();$beforeActionTicks=$beforeWorld.ProfileActionTicks.Clone();$beforeActionCounts=$beforeWorld.ProfileActionCounts.Clone();$beforeHitscanTicks=$beforeWorld.ProfileHitscanTicks.Clone();$beforeHitscanCounts=$beforeWorld.ProfileHitscanCounts.Clone();$beforePathCounts=$beforeWorld.ProfilePathCounts.Clone();$beforeInterceptBuckets=$beforeWorld.ProfileInterceptBuckets.Clone()}
        $watch=[Diagnostics.Stopwatch]::StartNew();$null=$game.Update($commands);$elapsed=$watch.Elapsed.TotalMilliseconds;$completed++
        $sample=@{Command=$completed;GameUpdateMilliseconds=$elapsed;StagesMilliseconds=$null;MapChanged=(-not [object]::ReferenceEquals($beforeWorld,$game.World))}
        if($Profile){
            $sample.StagesMilliseconds=@{}
            for($stage=0;$stage -lt $labels.Count;$stage++){
                $ticks=$game.World.ProfileTicks[$stage]-$(if($sample.MapChanged){0}else{$before[$stage]})
                $sample.StagesMilliseconds[$labels[$stage]]=$ticks*1000.0/[Diagnostics.Stopwatch]::Frequency
            }
        }
        if($ActorProfile){
            $sample.ActorMilliseconds=@();$sample.ActorCounts=@();$sample.SightTraversalCounts=@();$sample.ActionMilliseconds=@();$sample.ActionCounts=@();$sample.HitscanMilliseconds=@();$sample.HitscanCounts=@();$sample.PathCounts=@();$sample.InterceptBuckets=@()
            for($stage=0;$stage -lt 4;$stage++){$sample.ActorMilliseconds+=($game.World.ProfileActorTicks[$stage]-$(if($sample.MapChanged){0}else{$beforeActorTicks[$stage]}))*1000.0/[Diagnostics.Stopwatch]::Frequency}
            for($stage=0;$stage -lt 6;$stage++){$sample.ActorCounts+=($game.World.ProfileActorCounts[$stage]-$(if($sample.MapChanged){0}else{$beforeActorCounts[$stage]}))}
            for($stage=0;$stage -lt 11;$stage++){$sample.SightTraversalCounts+=($game.World.ProfileSightCounts[$stage]-$(if($sample.MapChanged){0}else{$beforeSightCounts[$stage]}))}
            for($stage=0;$stage -lt $actionNames.Count;$stage++){
                $sample.ActionMilliseconds+=($game.World.ProfileActionTicks[$stage]-$(if($sample.MapChanged){0}else{$beforeActionTicks[$stage]}))*1000.0/[Diagnostics.Stopwatch]::Frequency
                $sample.ActionCounts+=($game.World.ProfileActionCounts[$stage]-$(if($sample.MapChanged){0}else{$beforeActionCounts[$stage]}))
            }
            for($stage=0;$stage -lt 2;$stage++){
                $sample.HitscanMilliseconds+=($game.World.ProfileHitscanTicks[$stage]-$(if($sample.MapChanged){0}else{$beforeHitscanTicks[$stage]}))*1000.0/[Diagnostics.Stopwatch]::Frequency
                $sample.HitscanCounts+=($game.World.ProfileHitscanCounts[$stage]-$(if($sample.MapChanged){0}else{$beforeHitscanCounts[$stage]}))
            }
            for($stage=0;$stage -lt 7;$stage++){$sample.PathCounts+=($game.World.ProfilePathCounts[$stage]-$(if($sample.MapChanged){0}else{$beforePathCounts[$stage]}))}
            for($stage=0;$stage -lt 8;$stage++){$sample.InterceptBuckets+=($game.World.ProfileInterceptBuckets[$stage]-$(if($sample.MapChanged){0}else{$beforeInterceptBuckets[$stage]}))}
        }
        $samples.Add($sample)
        if($expected.ContainsKey($completed)){$points.Add((Get-DoomReplayCheckpoint $game $completed))}
    }
    if($points[-1].Tic -ne $completed){$points.Add((Get-DoomReplayCheckpoint $game $completed))}
    $verification=Compare-DoomReplayCheckpoints $reference.Checkpoints $points.ToArray() $completed
    if(-not $verification.Matched){throw 'Instrumented/baseline replay differs from original checkpoints.'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    $stats=@{}
    if($samples.Count){
        $stats.GameUpdate=Get-SampleStats ([double[]]$samples.GameUpdateMilliseconds)
        if($Profile){foreach($label in $labels){$stats[$label]=Get-SampleStats ([double[]]@($samples|ForEach-Object {$_.StagesMilliseconds[$label]}))}}
    }
    @{Error=$failure;Profile=[bool]$Profile;ActorProfile=[bool]$ActorProfile;ActorActionInstrumentation=if($ActorProfile){$actorActionInstrumentation}else{$null};ActionNameOrder=if($ActorProfile){$actionNames}else{$null};ActorArrayOrder=@('XY','Z','StateActionInclusive','CheckSightInclusive');ActorCountOrder=@('XYCalls','ZCalls','NumericallyUnneededXY','NumericallyUnneededZ','StateActions','CheckSight');SightTraversalOrder=@('BspNodeVisits','SubsectorVisits','SegmentIterations','UniqueLines','SightSideRejects','OneSidedOrMissingBackBlocks','ClosedPortals','InterceptCalculations','SlopeDivisions','ClosedSlopeWindows','RejectMatrixCulls');HitscanArrayOrder=@('AimLineAttackInclusive','LineAttackInclusive');PathCounterOrder=@('PathTraverseCalls','BlockIterations','InterceptsAtTraversalEnd','LineInterceptCandidates','ThingInterceptCandidates','InterceptVectorCalls','SortComparisons');InterceptBucketOrder=@('0','1-2','3-4','5-8','9-16','17-32','33-64','65+');MaxInterceptCount=$game.World.ProfileMaxInterceptCount;Commands=$completed;FinishedUtc=(Get-Date).ToUniversalTime().ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
        BaselineBundleSha256=$baselineHash;ExecutedBundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        ReplaySha256=(Get-FileHash $Replay).Hash;WadSha256=(Get-FileHash $Wad).Hash;SourceRoot=$sourceRootPath;Statistics=$stats;Samples=$samples.ToArray();
        ReplayVerification=$verification;Checkpoints=$points.ToArray();OwnedBundle=$bundle;
        Meaning='Unpaced simulation-only replay. Diagnostic stage timers exist only in an owned bundle; gameplay sources are not instrumented. All cold/update samples retained. Times include profiling overhead and do not model the loaded rendering/audio host; checkpoints test selected-state compatibility.'}|ConvertTo-Json -Depth 10|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $completed commands; $($verification.Checked) original checkpoints."
