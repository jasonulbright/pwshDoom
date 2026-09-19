#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Replay,[Parameter(Mandatory)][string]$Output,[switch]$Profile,[switch]$ActorProfile,
    [ValidateRange(1,1260000)][int]$MaxCommands=1200,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if($ActorProfile){$Profile=$true}
if(Test-Path -LiteralPath $Output){throw 'Use a fresh stage measurement report.'}
$owned=Join-Path "$PSScriptRoot/../local" ('game-profile-'+[guid]::NewGuid().ToString('N'))
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$owned/baseline.ps1"
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
    $source=Replace-Once $source 'class World {' ('class World {'+"`n"+'    [long[]]$ProfileTicks=[long[]]::new(9)'+"`n"+'    [long[]]$ProfileActorTicks=[long[]]::new(4)'+"`n"+'    [long[]]$ProfileActorCounts=[long[]]::new(6)'+"`n")
    if($ActorProfile){
        $index=0
        foreach($axis in @('XY','Z')){
            $marker='$this.world.ThingMovement.'+$axis+'Movement($this)'
            $redundant=if($axis -eq 'XY'){'$this.momX.Data -eq 0 -and $this.momY.Data -eq 0 -and ($this.flags -band [MobjFlags]::SkullFly) -eq 0'}else{'$this.z.Data -eq $this.floorZ.Data -and $this.momZ.Data -eq 0'}
            $replacement='$this.world.ProfileActorCounts['+$index+']++;if('+$redundant+'){$this.world.ProfileActorCounts['+($index+2)+']++};[long]$pfActorStart=[Diagnostics.Stopwatch]::GetTimestamp();'+$marker+';$this.world.ProfileActorTicks['+$index+']+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfActorStart;'
            $source=Replace-Once $source $marker $replacement;$index++
        }
        $marker='$st.MobjAction.Invoke($this.world, $this)'
        $source=Replace-Once $source $marker ('$this.world.ProfileActorCounts[4]++;[long]$pfActionStart=[Diagnostics.Stopwatch]::GetTimestamp();'+$marker+';$this.world.ProfileActorTicks[2]+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfActionStart;')
        $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$issues)
        $type=$ast.Find({param($node) $node -is [Management.Automation.Language.TypeDefinitionAst] -and $node.Name -eq 'VisibilityCheck'},$false)
        $method=@($type.Members|Where-Object {$_.Name -eq 'CheckSight' -and $_ -is [Management.Automation.Language.FunctionMemberAst]})
        if($method.Count -ne 1){throw 'Expected one visibility method.'}
        $body=$method[0].Body.Extent.Text
        $changed='{[long]$pfSightStart=[Diagnostics.Stopwatch]::GetTimestamp();$this.World.ProfileActorCounts[5]++;try{'+$body.Substring(1,$body.Length-2)+'}finally{$this.World.ProfileActorTicks[3]+=[Diagnostics.Stopwatch]::GetTimestamp()-$pfSightStart;}}'
        $source=$source.Remove($method[0].Body.Extent.StartOffset,$body.Length).Insert($method[0].Body.Extent.StartOffset,$changed)
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
        if($ActorProfile){$beforeActorTicks=$beforeWorld.ProfileActorTicks.Clone();$beforeActorCounts=$beforeWorld.ProfileActorCounts.Clone()}
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
            $sample.ActorMilliseconds=@();$sample.ActorCounts=@()
            for($stage=0;$stage -lt 4;$stage++){$sample.ActorMilliseconds+=($game.World.ProfileActorTicks[$stage]-$(if($sample.MapChanged){0}else{$beforeActorTicks[$stage]}))*1000.0/[Diagnostics.Stopwatch]::Frequency}
            for($stage=0;$stage -lt 6;$stage++){$sample.ActorCounts+=($game.World.ProfileActorCounts[$stage]-$(if($sample.MapChanged){0}else{$beforeActorCounts[$stage]}))}
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
    @{Error=$failure;Profile=[bool]$Profile;ActorProfile=[bool]$ActorProfile;ActorArrayOrder=@('XY','Z','StateActionInclusive','CheckSightInclusive');ActorCountOrder=@('XYCalls','ZCalls','NumericallyUnneededXY','NumericallyUnneededZ','StateActions','CheckSight');Commands=$completed;FinishedUtc=[DateTime]::UtcNow.ToString('o');PowerShell=$PSVersionTable.PSVersion.ToString();
        BaselineBundleSha256=$baselineHash;ExecutedBundleSha256=(Get-FileHash $bundle).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;
        ReplaySha256=(Get-FileHash $Replay).Hash;WadSha256=(Get-FileHash $Wad).Hash;Statistics=$stats;Samples=$samples.ToArray();
        ReplayVerification=$verification;Checkpoints=$points.ToArray();OwnedBundle=$bundle;
        Meaning='Unpaced simulation-only replay. Diagnostic stage timers exist only in an owned bundle; gameplay sources are not instrumented. All cold/update samples retained. Times include profiling overhead and do not model the loaded rendering/audio host; checkpoints test selected-state compatibility.'}|ConvertTo-Json -Depth 10|Set-Content $Output
}
if($failure){throw $failure}
"PASS: $completed commands; $($verification.Checked) original checkpoints."
