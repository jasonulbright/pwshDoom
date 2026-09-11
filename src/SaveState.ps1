# SPDX-License-Identifier: GPL-2.0-or-later
# Data-only graph snapshots. Types and callback bindings come from this code,
# never from executable expressions or assembly names supplied by a save file.
function Get-DoomSaveTypeKey {
    param([type]$Type)
    if($Type.IsArray){return (Get-DoomSaveTypeKey $Type.GetElementType())+'[]'}
    if($Type.IsGenericType){return $Type.Name.Split('`')[0]+'['+(@($Type.GenericTypeArguments|ForEach-Object {Get-DoomSaveTypeKey $_}) -join ',')+']'}
    return $Type.Name
}
function New-DoomSaveCatalog {
    $classes='DoomGame GameOptions World Thinkers Thinker Mobj Player DoomRandom TicCmd IntermissionInfo PlayerScores Intermission Finale Animation CastInfo Map Sector SideDef LineDef BlockMap MapThing Vertex Specials Button ThingAllocation ThingMovement ThingInteraction MapCollision MapInteraction PathTraversal Intercept DivLine Hitscan VisibilityCheck SectorAction PlayerBehavior ItemPickup WeaponBehavior MonsterBehavior LightingChange StatusBar AutoMap Cheat PlayerSpriteDef DoomString CeilingMove VerticalDoor FloorMove Platform LightFlash StrobeFlash GlowingLight FireFlicker'.Split(' ')
    $catalog=@{};$queue=[Collections.Generic.Queue[type]]::new()
    foreach($name in $classes){$t=[DoomGame].Assembly.GetType($name);if($null -eq $t){throw "Save catalog type unavailable: $name"};$queue.Enqueue($t)}
    foreach($t in [object],[string],[bool],[char],[byte],[sbyte],[int16],[uint16],[int],[uint],[long],[Fixed],[Angle]){$queue.Enqueue($t)}
    $selected=@{Map=@('sectors','sides','lines','blockMap');BlockMap=@('thingLists');Sector=@('floorHeight','ceilingHeight','floorFlat','ceilingFlat','lightLevel','special','soundTraversed','soundTarget','soundOrigin','validCount','thingList','specialData','oldFloorHeight','oldCeilingHeight');LineDef=@('flags','special','tag','validCount','specialData','soundOrigin');SideDef=@('textureOffset','rowOffset','topTexture','bottomTexture','middleTexture')}
    while($queue.Count){
        $t=$queue.Dequeue();$key=Get-DoomSaveTypeKey $t;if($catalog.ContainsKey($key)){continue}
        $kind=if($t.IsArray){'Array'}elseif($t.IsGenericType -and $t.GetGenericTypeDefinition().FullName -eq 'System.Collections.Generic.List`1'){'List'}elseif($t.IsEnum -or $t.IsPrimitive -or $t -in [string],[Fixed],[Angle]){'Scalar'}elseif($t.Name -in $classes){'Object'}else{'External'}
        $properties=@()
        if($kind -eq 'Object'){
            $properties=@($t.GetProperties([Reflection.BindingFlags]'Public,Instance')|Where-Object {
                $_.CanRead -and $_.CanWrite -and $_.PropertyType -ne [scriptblock] -and -not [Delegate].IsAssignableFrom($_.PropertyType) -and
                ($t.Name -ne 'GameOptions' -or $_.Name -notin 'Video','Sound','Music','UserInput') -and
                (-not $selected.ContainsKey($t.Name) -or $_.Name -in $selected[$t.Name])
            }|Sort-Object Name)
            foreach($p in $properties){$queue.Enqueue($p.PropertyType)}
        }elseif($kind -eq 'Array'){$queue.Enqueue($t.GetElementType())}elseif($kind -eq 'List'){$queue.Enqueue($t.GenericTypeArguments[0])}
        $catalog[$key]=@{Type=$t;Kind=$kind;Properties=$properties;Element=if($kind -eq 'Array'){$t.GetElementType()}elseif($kind -eq 'List'){$t.GenericTypeArguments[0]}else{$null}}
    }
    # Concrete object[] values (including finale cast data) use the same catalog.
    $catalog['Object[]']=@{Type=[object[]];Kind='Array';Properties=@();Element=[object]}
    return $catalog
}
function New-DoomSaveBindings {
    param($Game)
    $bound=[Collections.Generic.Dictionary[object,string]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    $external=[Collections.Generic.Dictionary[object,string]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    $boundValues=@{};$externalValues=@{}
    function Add-Binding([string]$Key,$Value,[bool]$Mutable){
        if($null -eq $Value){return}
        $lookup=if($Mutable){$bound}else{$external};$values=if($Mutable){$boundValues}else{$externalValues}
        if(-not $lookup.ContainsKey($Value)){$lookup.Add($Value,$Key);$values[$Key]=$Value}
    }
    Add-Binding 'game' $Game $true;Add-Binding 'options' $Game.Options $true;Add-Binding 'world' $Game.World $true
    Add-Binding 'content' $Game.Content $false
    foreach($p in $Game.World.GetType().GetProperties([Reflection.BindingFlags]'Public,Instance')){
        $value=$p.GetValue($Game.World)
        if($null -ne $value -and $p.PropertyType.IsClass -and -not $p.PropertyType.IsArray -and $p.PropertyType -ne [string] -and $p.Name -notin 'ConsolePlayer','DisplayPlayer','Dummy','Random','Options','Game'){
            Add-Binding ('world/'+$p.Name) $value $true
        }
    }
    $map=$Game.World.Map
    Add-Binding 'world/MonsterBehavior/junk' $Game.World.MonsterBehavior.junk $true
    Add-Binding 'map/blockMap' $map.BlockMap $true
    foreach($name in 'Sectors','Lines','Sides'){
        $items=$map.$name
        for($i=0;$i -lt $items.Count;$i++){Add-Binding ('map/'+$name+'/'+$i) $items[$i] $true}
    }
    foreach($name in 'Vertices','Segs','Subsectors','Nodes','Things'){
        $items=$map.$name;Add-Binding ('map/'+$name) $items $false
        for($i=0;$i -lt $items.Count;$i++){Add-Binding ('map/'+$name+'/'+$i) $items[$i] $false}
    }
    foreach($set in @(@('states',[DoomInfo]::States.all),@('mobjInfo',[DoomInfo]::MobjInfos))){
        for($i=0;$i -lt $set[1].Count;$i++){Add-Binding ($set[0]+'/'+$i) $set[1][$i] $false}
    }
    return @{Bound=$bound;External=$external;BoundValues=$boundValues;ExternalValues=$externalValues}
}
function ConvertTo-DoomSaveGraph {
    param($Game)
    $catalog=New-DoomSaveCatalog;$bindings=New-DoomSaveBindings $Game
    $ids=[Collections.Generic.Dictionary[object,int]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    $objects=[Collections.Generic.List[object]]::new();$nodes=[Collections.Generic.List[object]]::new()
    function Encode-Value($Value){
        if($null -eq $Value){return ,@(0)}
        $t=$Value.GetType();$key=Get-DoomSaveTypeKey $t
        $externalKey='';if($bindings.External.TryGetValue($Value,[ref]$externalKey)){return ,@(3,$externalKey)}
        if(-not $catalog.ContainsKey($key)){throw "Uncatalogued save value: $key"}
        if($catalog[$key].Kind -eq 'Scalar'){
            $data=if($t -in [Fixed],[Angle]){$Value.Data}elseif($t -eq [char]){[int]$Value}elseif($t.IsEnum){[long]$Value}else{$Value}
            return ,@(1,$key,$data)
        }
        if($catalog[$key].Kind -eq 'External'){throw "Unbound external save value: $key"}
        $id=0;if(-not $ids.TryGetValue($Value,[ref]$id)){$id=$objects.Count;$ids.Add($Value,$id);$objects.Add($Value)}
        if($objects.Count -gt 200000){throw 'Save graph exceeds its node limit.'}
        return ,@(2,$id)
    }
    $root=Encode-Value $Game
    for($n=0;$n -lt $objects.Count;$n++){
        $value=$objects[$n];$key=Get-DoomSaveTypeKey $value.GetType();$entry=$catalog[$key]
        $values=[Collections.Generic.List[object]]::new()
        if($entry.Kind -eq 'Object'){foreach($p in $entry.Properties){$values.Add((Encode-Value $p.GetValue($value)))}}
        else{foreach($item in $value){$values.Add((Encode-Value $item))}}
        $binding='';$null=$bindings.Bound.TryGetValue($value,[ref]$binding)
        $nodes.Add([ordered]@{Type=$key;Binding=$binding;Values=$values.ToArray()})
    }
    return [ordered]@{Root=$root;Nodes=$nodes.ToArray()}
}
function Restore-DoomSaveGraph {
    param($Graph,$Candidate)
    if($Graph.Nodes -isnot [array] -or $Graph.Nodes.Count -lt 3 -or $Graph.Nodes.Count -gt 200000 -or $Graph.Root -isnot [array] -or $Graph.Root.Count -ne 2 -or $Graph.Root[0] -isnot [long] -or $Graph.Root[1] -isnot [long] -or ($Graph.Root -join ',') -ne '2,0'){throw 'Invalid save graph root or node count.'}
    $catalog=New-DoomSaveCatalog;$bindings=New-DoomSaveBindings $Candidate
    $objects=[object[]]::new($Graph.Nodes.Count);$usedBindings=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $totalValues=0
    for($i=0;$i -lt $Graph.Nodes.Count;$i++){
        $node=$Graph.Nodes[$i]
        if($node.Type -isnot [string] -or -not $catalog.ContainsKey($node.Type) -or $node.Values -isnot [array]){throw 'Invalid save node shape or type.'}
        $entry=$catalog[$node.Type];$totalValues+=$node.Values.Count
        if($totalValues -gt 2000000 -or $node.Values.Count -gt 100000){throw 'Save graph exceeds its value limit.'}
        if($entry.Kind -eq 'Object' -and $node.Values.Count -ne $entry.Properties.Count){throw 'Save node property count differs from the installed schema.'}
        if($null -ne $node.Binding -and $node.Binding -isnot [string]){throw 'Invalid save binding.'}
        if($node.Binding){
            if(-not $bindings.BoundValues.ContainsKey($node.Binding) -or -not $usedBindings.Add($node.Binding)){throw 'Unknown or repeated save binding.'}
            $objects[$i]=$bindings.BoundValues[$node.Binding]
            if($objects[$i].GetType() -ne $entry.Type){throw 'Save binding type mismatch.'}
        }else{
            switch($entry.Kind){
                'Object' {
                    if($node.Type -in @('DoomGame','GameOptions','World','Map','Sector','SideDef','LineDef','BlockMap') -or @($entry.Type.GetProperties([Reflection.BindingFlags]'Public,Instance')|Where-Object {$_.PropertyType -eq [scriptblock] -or [Delegate].IsAssignableFrom($_.PropertyType)}).Count){throw 'This engine object requires a constructed binding.'}
                    $objects[$i]=[Runtime.CompilerServices.RuntimeHelpers]::GetUninitializedObject($entry.Type)
                }
                'Array' {$objects[$i]=[Array]::CreateInstance($entry.Element,$node.Values.Count)}
                'List' {$objects[$i]=[Activator]::CreateInstance($entry.Type)}
                default {throw 'Scalar or external objects cannot be graph nodes.'}
            }
        }
    }
    if(-not [object]::ReferenceEquals($objects[0],$Candidate)){throw 'Save root must bind the candidate game.'}
    function Decode-Value($Token,[type]$Expected){
        if($Token -isnot [array] -or $Token.Count -lt 1 -or $Token[0] -isnot [long]){throw 'Invalid save value token.'}
        $result=$null
        switch($Token[0]){
            0 {if($Token.Count -ne 1 -or $Expected.IsValueType){throw 'Invalid null save value.'}}
            1 {
                if($Token.Count -ne 3 -or $Token[1] -isnot [string] -or -not $catalog.ContainsKey($Token[1]) -or $catalog[$Token[1]].Kind -ne 'Scalar'){throw 'Invalid scalar save value.'}
                $t=$catalog[$Token[1]].Type;$value=$Token[2]
                if($t -eq [string]){if($value -isnot [string] -or $value.Length -gt 16384){throw 'Invalid save string.'};$result=$value}
                elseif($t -eq [bool]){if($value -isnot [bool]){throw 'Invalid save boolean.'};$result=$value}
                else{
                    if($value -isnot [long]){throw 'Save numeric values must be integers.'}
                    if($t -eq [Fixed]){if($value -lt [int]::MinValue -or $value -gt [int]::MaxValue){throw 'Fixed value outside range.'};$result=[Fixed]::new([int]$value)}
                    elseif($t -eq [Angle]){if($value -lt 0 -or $value -gt [uint]::MaxValue){throw 'Angle value outside range.'};$result=[Angle]::new([uint]$value)}
                    elseif($t -eq [char]){if($value -lt 0 -or $value -gt 65535){throw 'Character outside range.'};$result=[char]$value}
                    elseif($t.IsEnum){
                        $underlying=[Convert]::ChangeType($value,[Enum]::GetUnderlyingType($t),[Globalization.CultureInfo]::InvariantCulture)
                        $result=[Enum]::ToObject($t,$underlying)
                        if(-not $t.IsDefined([FlagsAttribute],$false) -and -not [Enum]::IsDefined($t,$result)){throw 'Unknown save enum value.'}
                    }else{$result=[Convert]::ChangeType($value,$t,[Globalization.CultureInfo]::InvariantCulture)}
                }
            }
            2 {if($Token.Count -ne 2 -or $Token[1] -isnot [long] -or $Token[1] -lt 0 -or $Token[1] -ge $objects.Count){throw 'Save reference outside graph.'};$result=$objects[$Token[1]]}
            3 {if($Token.Count -ne 2 -or $Token[1] -isnot [string] -or -not $bindings.ExternalValues.ContainsKey($Token[1])){throw 'Unknown external save binding.'};$result=$bindings.ExternalValues[$Token[1]]}
            default {throw 'Unknown save value token.'}
        }
        if($null -ne $result -and -not $Expected.IsInstanceOfType($result)){throw "Save value type does not match $($Expected.Name)."}
        return ,$result
    }
    for($i=0;$i -lt $Graph.Nodes.Count;$i++){
        $node=$Graph.Nodes[$i];$entry=$catalog[$node.Type];$target=$objects[$i]
        for($j=0;$j -lt $node.Values.Count;$j++){
            if($entry.Kind -eq 'Object'){$property=$entry.Properties[$j];$decoded=Decode-Value $node.Values[$j] $property.PropertyType;$property.SetValue($target,$decoded)}
            else{$decoded=Decode-Value $node.Values[$j] $entry.Element;if($entry.Kind -eq 'Array'){$target.SetValue($decoded,$j)}else{$null=$target.Add($decoded)}}
        }
    }
    Assert-DoomSaveGraph $Candidate $bindings $objects
    return $Candidate
}
function Assert-DoomSaveGraph {
    param($Game,$Bindings,[object[]]$Objects)
    $w=$Game.World;$o=$Game.Options
    if($w -isnot [World] -or $o -isnot [GameOptions]){throw 'Invalid saved world/options.'}
    if($Game.GameAction -ne [GameAction]::Nothing -or $Game.State -ne $Game.GameState){throw 'Save must be at a completed simulation boundary.'}
    if(-not [object]::ReferenceEquals($w.Game,$Game) -or -not [object]::ReferenceEquals($w.Options,$o) -or -not [object]::ReferenceEquals($w.Random,$o.Random)){throw 'Inconsistent saved world ownership.'}
    if($o.NetGame -or $o.Deathmatch -ne 0 -or $o.ConsolePlayer -ne 0 -or $o.Players.Count -ne 4 -or -not $o.Players[0].InGame -or @($o.Players|Select-Object -Skip 1|Where-Object InGame).Count){throw 'Save is not a supported single-player session.'}
    if($w.LevelTime -lt 0 -or $o.Random.Index -lt 0 -or $o.Random.Index -gt 255 -or $w.StatusBar.Random.Index -lt 0 -or $w.StatusBar.Random.Index -gt 255){throw 'Invalid saved clock or RNG state.'}
    foreach($name in 'Sectors','Lines','Sides'){
        $items=$w.Map.$name;$prefix='map/'+$name+'/'
        $count=@($Bindings.BoundValues.Keys|Where-Object {$_.StartsWith($prefix,[StringComparison]::Ordinal)}).Count
        if($items.Count -ne $count){throw 'Saved map entity count changed.'}
        for($i=0;$i -lt $count;$i++){if(-not [object]::ReferenceEquals($items[$i],$Bindings.BoundValues[$prefix+$i])){throw 'Saved map entity ordering changed.'}}
    }
    $seen=[Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    if($w.Thinkers -isnot [Thinkers] -or $w.Thinkers.Cap -isnot [Thinker]){throw 'Invalid saved thinker ring.'}
    $cap=$w.Thinkers.Cap;$previous=$cap;$thinker=$cap.Next
    while(-not [object]::ReferenceEquals($thinker,$cap)){
        if($null -eq $thinker -or -not $seen.Add($thinker) -or $seen.Count -gt $Objects.Count -or -not [object]::ReferenceEquals($thinker.Prev,$previous)){throw 'Invalid saved thinker links.'}
        $previous=$thinker;$thinker=$thinker.Next
    }
    if(-not [object]::ReferenceEquals($cap.Prev,$previous)){throw 'Invalid saved thinker tail.'}
    $map=$w.Map
    if($map.BlockMap.ThingLists.Count -ne $map.BlockMap.Width*$map.BlockMap.Height){throw 'Invalid saved collision-grid size.'}
    foreach($kind in 'Sector','Block'){
        $heads=if($kind -eq 'Sector'){@($map.Sectors|ForEach-Object {$_.ThingList})}else{$map.BlockMap.ThingLists}
        $next=$kind+'Next';$prev=$kind+'Prev';$linked=[Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
        foreach($head in $heads){$mobj=$head;$previous=$null
            while($null -ne $mobj){
                if(-not $linked.Add($mobj) -or -not [object]::ReferenceEquals($mobj.$prev,$previous)){throw 'Invalid saved spatial links.'}
                $previous=$mobj;$mobj=$mobj.$next
            }
        }
    }
    foreach($object in $Objects){
        if($object -is [Mobj] -and -not [object]::ReferenceEquals($object.World,$w)){throw 'Saved actor belongs to another world.'}
    }
    if(-not [object]::ReferenceEquals($w.ConsolePlayer,$o.Players[0]) -or -not [object]::ReferenceEquals($o.Players[0].Mobj.Player,$o.Players[0])){throw 'Invalid saved player ownership.'}
}
function Get-DoomSaveSchemaHash {
    $catalog=New-DoomSaveCatalog
    $lines=@($catalog.Keys|Sort-Object|ForEach-Object {$key=$_;$e=$catalog[$key];$key+' '+$e.Kind+' '+(@($e.Properties|ForEach-Object {$_.Name+':'+(Get-DoomSaveTypeKey $_.PropertyType)}) -join ',')})
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($lines -join "`n")))
}
function Write-DoomSaveState {
    param($Game,[string]$Path,[string]$WadSha256,[string]$Description='Saved game',[string]$ReplaceExpectedHash)
    if($WadSha256 -notmatch '^[a-fA-F0-9]{64}$' -or $Description.Length -gt 48 -or $Description -match '[\x00-\x1f\x7f]'){throw 'Invalid save metadata.'}
    if($Game.Options.NetGame -or $Game.Options.Deathmatch -ne 0){throw 'Only single-player saves are supported.'}
    $destination=[IO.Path]::GetFullPath($Path)
    if((Test-Path -LiteralPath $destination) -and -not $ReplaceExpectedHash){throw 'Save exists; overwriting requires its confirmed hash.'}
    if($ReplaceExpectedHash -and ($ReplaceExpectedHash -notmatch '^[a-fA-F0-9]{64}$' -or -not (Test-Path -LiteralPath $destination))){throw 'Confirmed save no longer exists.'}
    $watch=[Diagnostics.Stopwatch]::StartNew();$graph=ConvertTo-DoomSaveGraph $Game;$graphJson=$graph|ConvertTo-Json -Depth 12 -Compress
    $graphBytes=[Text.Encoding]::UTF8.GetBytes($graphJson)
    if($graphBytes.Length -gt 32MB){throw 'Save graph exceeds 32 MiB.'}
    $document=[ordered]@{Format='pwshDoom.SaveState';Version=1;CreatedUtc=[DateTime]::UtcNow.ToString('o');Description=$Description;WadSha256=$WadSha256;
        SchemaSha256=(Get-DoomSaveSchemaHash);EngineSourceFingerprint=(Get-DoomReplaySourceFingerprint);Skill=[int]$Game.Options.Skill+1;Episode=$Game.Options.Episode;Map=$Game.Options.Map;
        GraphSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($graphBytes));GraphJson=$graphJson}
    $json=$document|ConvertTo-Json -Depth 4 -Compress
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
    $temporary=$destination+'.'+[guid]::NewGuid().ToString('N')+'.tmp';$backup=$null
    try{
        [IO.File]::WriteAllText($temporary,$json,[Text.UTF8Encoding]::new($false))
        $null=Read-DoomSaveState $temporary $WadSha256
        if($ReplaceExpectedHash){
            if((Get-FileHash -LiteralPath $destination).Hash -ne $ReplaceExpectedHash){throw 'Save changed after overwrite confirmation.'}
            $backup=$destination+'.'+[guid]::NewGuid().ToString('N')+'.bak'
            [IO.File]::Replace($temporary,$destination,$backup)
        }else{[IO.File]::Move($temporary,$destination,$false)}
    }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}}
    return @{Path=$destination;Sha256=(Get-FileHash $destination).Hash;Backup=$backup;Bytes=(Get-Item $destination).Length;Nodes=$graph.Nodes.Count;Milliseconds=$watch.Elapsed.TotalMilliseconds}
}
function Read-DoomSaveState {
    param([string]$Path,[string]$WadSha256)
    $file=Get-Item -LiteralPath $Path
    if($file.Length -gt 64MB){throw 'Save exceeds 64 MiB.'}
    $document=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json -Depth 4
    if($document -isnot [pscustomobject] -or $document.Format -ne 'pwshDoom.SaveState' -or $document.Version -isnot [long] -or $document.Version -ne 1){throw 'Unsupported save format/version.'}
    if($document.WadSha256 -notmatch '^[a-fA-F0-9]{64}$' -or ($WadSha256 -and $document.WadSha256 -ne $WadSha256)){throw 'Save IWAD does not match.'}
    if($document.SchemaSha256 -ne (Get-DoomSaveSchemaHash)){throw 'Save schema differs from the installed version.'}
    if($document.EngineSourceFingerprint -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid saved source fingerprint.'}
    foreach($pair in @(@('Skill',5),@('Episode',4),@('Map',9))){$v=$document.($pair[0]);if($v -isnot [long] -or $v -lt 1 -or $v -gt $pair[1]){throw 'Invalid saved starting settings.'}}
    if($document.Description -isnot [string] -or $document.Description.Length -gt 48 -or $document.Description -match '[\x00-\x1f\x7f]'){throw 'Invalid save description.'}
    if($document.GraphJson -isnot [string] -or $document.GraphJson.Length -gt 32MB){throw 'Invalid save graph payload.'}
    $bytes=[Text.Encoding]::UTF8.GetBytes($document.GraphJson)
    if($bytes.Length -gt 32MB -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) -ne $document.GraphSha256){throw 'Save graph checksum failed.'}
    $graph=$document.GraphJson|ConvertFrom-Json -Depth 12
    return @{Metadata=$document;Graph=$graph;Path=$file.FullName;Sha256=(Get-FileHash -LiteralPath $Path).Hash;SourceMatches=$document.EngineSourceFingerprint -eq (Get-DoomReplaySourceFingerprint)}
}
function New-DoomGameFromSave {
    param($Save,$Content)
    # Candidate construction uses null devices. A failed reconstruction cannot
    # reset the live world's input/audio or replace the caller's game object.
    $meta=$Save.Metadata
    if($Content.Wad.Streams.Count -ne 1 -or $Content.Wad.Streams[0] -isnot [IO.FileStream] -or
        (Get-FileHash -LiteralPath $Content.Wad.Streams[0].Name).Hash -ne $meta.WadSha256){throw 'Candidate content does not match the saved single IWAD.'}
    $options=[GameOptions]::new()
    $options.GameMode=$Content.Wad.GameMode;$options.GameVersion=$Content.Wad.GameVersion;$options.MissionPack=$Content.Wad.MissionPack
    $episodes=if($options.GameMode -eq [GameMode]::Shareware){1}elseif($options.GameMode -eq [GameMode]::Retail){4}elseif($options.GameMode -eq [GameMode]::Registered){3}else{0}
    if($episodes -eq 0 -or $meta.Episode -gt $episodes){throw 'Save episode is unavailable in this Ultimate Doom IWAD.'}
    $candidate=[DoomGame]::new($Content,$options);$candidate.InitNew([GameSkill]($meta.Skill-1),$meta.Episode,$meta.Map)
    $game=Restore-DoomSaveGraph $Save.Graph $candidate
    if($game.Options.Skill -ne $meta.Skill-1 -or $game.Options.Episode -ne $meta.Episode -or $game.Options.Map -ne $meta.Map -or $game.Options.GameMode -ne $Content.Wad.GameMode -or $game.Options.GameVersion -ne $Content.Wad.GameVersion -or $game.Options.MissionPack -ne $Content.Wad.MissionPack){throw 'Saved graph disagrees with its IWAD/settings header.'}
    return $game
}
