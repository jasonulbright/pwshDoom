#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [int[]]$SaveAt=@(700),[int]$ContinueTics=140,[string]$Output="$PSScriptRoot/../results/save-state-first.json")
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/InputReplay.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/SnapshotTransport.ps1";. "$PSScriptRoot/../src/SaveState.ps1"
Set-StrictMode -Version Latest
$directory=Join-Path "$PSScriptRoot/../local" ('save-state-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($directory)
$checks=[Collections.Generic.List[object]]::new();$runs=[Collections.Generic.List[object]]::new();$failure=$null;$content=$null
function Assert-Save([string]$Name,[bool]$Condition){$checks.Add(@{Name=$Name;Passed=$Condition});if(-not $Condition){throw $Name}}
function Get-IndependentState($Game){
    $w=$Game.World;$all=[Collections.Generic.List[object]]::new();$ids=[Collections.Generic.Dictionary[object,int]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    $cap=$w.Thinkers.Cap;$t=$cap.Next
    while(-not [object]::ReferenceEquals($t,$cap)){$ids.Add($t,$all.Count);$all.Add($t);$t=$t.Next;if($all.Count -gt 100000){throw 'Thinker cycle in test input.'}}
    function Get-Ref($Value){if($null -eq $Value){return -1};$id=0;if($ids.TryGetValue($Value,[ref]$id)){return $id};return -2}
    $thinkers=@(foreach($t in $all){
        if($t -is [Mobj]){[ordered]@{Kind='Mobj';Type=[int]$t.Type;ThinkerState=[int]$t.ThinkerState;XYZ=@($t.X.Data,$t.Y.Data,$t.Z.Data);Momentum=@($t.MomX.Data,$t.MomY.Data,$t.MomZ.Data);Angle=$t.Angle.Data;State=$t.State.Number;Tics=$t.Tics;Flags=[int]$t.Flags;Health=$t.Health;Target=(Get-Ref $t.Target);Tracer=(Get-Ref $t.Tracer);Reaction=$t.ReactionTime;Threshold=$t.Threshold;MoveCount=$t.MoveCount;Direction=[int]$t.MoveDir;Sector=$t.Subsector.Sector.Number}}
        else{[ordered]@{Kind=$t.GetType().Name;ThinkerState=[int]$t.ThinkerState;Sector=$t.Sector.Number;Fields=@($t.GetType().GetProperties([Reflection.BindingFlags]'Public,Instance')|Where-Object {$_.PropertyType.IsPrimitive -or $_.PropertyType.IsEnum -or $_.PropertyType -eq [Fixed]}|Sort-Object Name|ForEach-Object {$v=$_.GetValue($t);[ordered]@{Name=$_.Name;Value=if($v -is [Fixed]){$v.Data}else{[long]$v}}})}}
    })
    $sectors=@(foreach($s in $w.Map.Sectors){,@($s.FloorHeight.Data,$s.CeilingHeight.Data,$s.OldFloorHeight.Data,$s.OldCeilingHeight.Data,$s.LightLevel,[int]$s.Special,(Get-Ref $s.SoundTarget),(Get-Ref $s.ThingList),(Get-Ref $s.SpecialData))})
    $buttons=@(foreach($b in $w.Specials.ButtonList){,@($b.Timer,$b.Texture,[int]$b.Position)})
    return ([ordered]@{Checkpoint=(Get-DoomReplayCheckpoint $Game $Game.GameTic).Sha256;Thinkers=$thinkers;Sectors=$sectors;Buttons=$buttons;Hud=@($w.StatusBar.FaceIndex,$w.StatusBar.FaceCount,$w.StatusBar.Random.Index)}|ConvertTo-Json -Depth 10 -Compress)
}
function Apply-Input($Game,[int]$Index){
    foreach($c in $commands){$c.Clear()}
    if($Index -lt $route.InputCommands.Count){$v=$route.InputCommands[$Index];$c=$commands[0];$c.ForwardMove=$v[0];$c.SideMove=$v[1];$c.AngleTurn=$v[2];$c.Buttons=$v[3]}
    $null=$Game.Update($commands)
}
try{
    $content=[GameContent]::new(@('-iwad',$Wad));$wadHash=(Get-FileHash $Wad).Hash;$route=Read-DoomInputReplay "$PSScriptRoot/../results/input-session-replay.json" $wadHash
    $commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    foreach($point in $SaveAt){
        foreach($c in $commands){$c.Clear()}
        $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
        $game=[DoomGame]::new($content,$options);$game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
        for($i=0;$i -lt $point;$i++){Apply-Input $game $i}
        $before=Get-IndependentState $game;$path=Join-Path $directory "at-$point.pds"
        $write=Write-DoomSaveState $game $path $wadHash "Test at $point"
        Assert-Save "Save at $point leaves live state unchanged" ((Get-IndependentState $game) -ceq $before)
        $wire=Read-DoomSaveState $path $wadHash;$clock=[Diagnostics.Stopwatch]::StartNew();$loaded=New-DoomGameFromSave $wire $content;$loadMs=$clock.Elapsed.TotalMilliseconds
        Assert-Save "Independent state matches on load at $point" ((Get-IndependentState $loaded) -ceq $before)
        Assert-Save "Serialized graph matches on load at $point" (($wire.Graph|ConvertTo-Json -Depth 12 -Compress) -ceq (ConvertTo-DoomSaveGraph $loaded|ConvertTo-Json -Depth 12 -Compress))
        $startState=[string]$game.State
        for($i=$point;$i -lt $point+$ContinueTics;$i++){
            Apply-Input $game $i;Apply-Input $loaded $i
            if(($i-$point)%35 -eq 34 -or $i -eq $point+$ContinueTics-1){Assert-Save "Continued independent state matches at command $($i+1)" ((Get-IndependentState $game) -ceq (Get-IndependentState $loaded))}
        }
        Assert-Save "Continued graph matches after $point+$ContinueTics" ((ConvertTo-DoomSaveGraph $game|ConvertTo-Json -Depth 12 -Compress) -ceq (ConvertTo-DoomSaveGraph $loaded|ConvertTo-Json -Depth 12 -Compress))
        $runs.Add(@{SaveAt=$point;ContinueTics=$ContinueTics;StartState=$startState;EndState=[string]$loaded.State;EndEpisode=$loaded.Options.Episode;EndMap=$loaded.Options.Map;Save=$write;LoadMs=$loadMs;FinalCheckpoint=Get-DoomReplayCheckpoint $loaded ($point+$ContinueTics)})
        "PASS: save at $point, continue $ContinueTics commands."
    }
    $liveBefore=Get-IndependentState $game;$originalHash=(Get-FileHash $path).Hash
    $rejected=$false;try{$null=Write-DoomSaveState $game $path $wadHash}catch{$rejected=$true}
    Assert-Save 'Existing save is preserved without overwrite confirmation' ($rejected -and (Get-FileHash $path).Hash -eq $originalHash)
    $rejected=$false;try{$null=Write-DoomSaveState $game $path $wadHash -ReplaceExpectedHash ('A'*64)}catch{$rejected=$true}
    Assert-Save 'Stale overwrite confirmation preserves original' ($rejected -and (Get-FileHash $path).Hash -eq $originalHash)
    $replace=Write-DoomSaveState $game $path $wadHash -ReplaceExpectedHash $originalHash
    Assert-Save 'Confirmed overwrite retains exact prior save as backup' ((Get-FileHash $replace.Backup).Hash -eq $originalHash)
    foreach($case in @(
        @('Unknown version',{param($d)$d.Version=9}),@('Wrong IWAD',{param($d)$d.WadSha256='B'*64}),@('Wrong schema',{param($d)$d.SchemaSha256='C'*64}),
        @('Checksum corruption',{param($d)$d.GraphSha256='D'*64}),@('Out-of-range settings',{param($d)$d.Episode=5})
    )){
        $bad=Get-Content $path -Raw|ConvertFrom-Json;& $case[1] $bad;$badPath=Join-Path $directory ($case[0]+'.pds');$bad|ConvertTo-Json -Depth 4 -Compress|Set-Content $badPath
        $rejected=$false;try{$null=Read-DoomSaveState $badPath $wadHash}catch{$rejected=$true};Assert-Save ($case[0]+' rejected') $rejected
    }
    foreach($case in @(
        @('Unknown graph type',{param($g)$g.Nodes[0].Type='System.Diagnostics.Process'}),
        @('Bad reference',{param($g)$g.Nodes[0].Values[1]=@(2,999999)}),
        @('Missing properties',{param($g)$g.Nodes[0].Values=@()}),
        @('Forged binding',{param($g)$g.Nodes[0].Binding='not-a-game'}),
        @('Invalid scalar type',{param($g)$g.Nodes[0].Values[2]=@(1,'String','NewGame')}),
        @('Executable game action',{param($g)$g.Nodes[0].Values[2]=@(1,'GameAction',4)}),
        @('String root',{param($g)$g.Root='2,0'})
    )){
        $bad=Read-DoomSaveState $path $wadHash;& $case[1] $bad.Graph
        # JSON normalizes deliberately injected numbers to the wire's Int64 types.
        $bad.Graph=$bad.Graph|ConvertTo-Json -Depth 12 -Compress|ConvertFrom-Json -Depth 12
        $rejected=$false;try{$null=New-DoomGameFromSave $bad $content}catch{$rejected=$true};Assert-Save ($case[0]+' rejected in candidate') $rejected
    }
    Assert-Save 'Failed loads leave live state unchanged' ((Get-IndependentState $game) -ceq $liveBefore)
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    @{FinishedUtc=[DateTime]::UtcNow.ToString('o');Error=$failure;Checks=$checks.ToArray();Runs=$runs.ToArray();SourceSha256=(Get-FileHash "$PSScriptRoot/../src/SaveState.ps1").Hash;SaveDirectory=$directory;Meaning='Same-process save reconstruction, independent actor/sector/player/HUD projection, canonical graph round trip and continued ordinary input. Corruption is tested against a separate candidate. This does not yet prove fresh-process loading or menu integration.'}|ConvertTo-Json -Depth 12|Set-Content $Output
    if($null -ne $content){$content.Dispose()}
}
"PASS: $($checks.Count) save-state checks."
