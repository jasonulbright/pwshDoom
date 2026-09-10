# PowerShell-only persistent runspace experiment. Standard .NET synchronization,
# no custom compiled helper. The external renderer remains a local dependency.
Set-StrictMode -Version Latest
. "$PSScriptRoot/FrameCodec.ps1"

function New-DoomRenderArguments {
    param([hashtable]$Scene,[byte[]]$Buffer,[int]$Width=320,[int]$Height=200)
    $level=$Scene.Level
    $render=@{ptx=$level.startX;pty=$level.startY;ptz=$Scene.EyeZ;pang=$level.startA;
        W=$Width;vres=$Height;horiz=[int]($Height/2);hScale=$Width/2.0;vScale=$Width/2.0;quant=2;
        buf=$Buffer;ceilClip=[int[]]::new($Width);floorClip=[int[]]::new($Width);stack=[int[]]::new(256);
        rowInv=[double[]]::new($Height);textures=$Scene.Textures;flats=$Scene.Flats;
        colormap=$Scene.Colormap;skyTex=$Scene.SkyTexture;texMode=$true;DSMAX=1024;
        dsX1=[int[]]::new(1024);dsX2=[int[]]::new(1024);dsIz1=[double[]]::new(1024);
        dsIzStep=[double[]]::new(1024);dsSolid=[bool[]]::new(1024);dsTopZ=[double[]]::new(1024);dsBotZ=[double[]]::new(1024)}
    foreach ($key in 'vx','vy','segV1','segV2','segLine','segSide','segOffset','lineRight','lineLeft','lineFlags',
        'sideSector','sideXoff','sideYoff','sideUpTex','sideLoTex','sideMidTex','secFloor','secCeil','secLight',
        'secFloorFlat','secCeilFlat','secSky','ssCount','ssFirst','nodeX','nodeY','nodeDX','nodeDY','nodeC0','nodeC1','nNodes') {
        $render[$key]=$level[$key]
    }
    for($y=0;$y -lt $Height;$y++) {
        $distance=[Math]::Abs($render.horiz-$y)
        $render.rowInv[$y]=if($distance -eq 0){32000.0}else{$render.vScale/$distance}
    }
    return $render
}

function ConvertTo-AnsiStrip {
    param([byte[]]$Pixels,[int]$Width,[int]$Height,[int]$FirstColumn,[int]$EndColumn,[hashtable]$Context)
    [string[]]$cells=$Context.Cells; [int]$count=$Context.Count; [string]$block=[char]0x2580
    [string[]]$chunks=[string[]]::new(($EndColumn-$FirstColumn+1)*[int][Math]::Ceiling($Height/2))
    [int]$n=0;[int]$last=-1
    for([int]$y=0;$y -lt $Height;$y+=2) {
        $chunks[$n++]="$([char]27)[$([int]($y/2)+3);$($FirstColumn+1)H"
        [int]$top=$y*$Width; [int]$bottom=[Math]::Min($y+1,$Height-1)*$Width
        for([int]$x=$FirstColumn;$x -lt $EndColumn;$x++) {
            [int]$pair=[int]$Pixels[$top+$x]*$count+[int]$Pixels[$bottom+$x]
            if($pair -eq $last){$chunks[$n++]=$block}else{$chunks[$n++]=$cells[$pair];$last=$pair}
        }
    }
    # Preserve the byte array as one object: pipeline enumeration of every byte
    # would dominate frame encoding and defeat the shared-memory transport.
    return ,([Text.Encoding]::UTF8.GetBytes([string]::Concat($chunks)))
}

function New-Ansi256Context {
    param([int[][]]$Palette)
    # Map to fixed xterm cube/grays (16..255), avoiding theme-dependent 0..15.
    $terminal=[int[][]]::new(256);$levels=@(0,95,135,175,215,255)
    for($r=0;$r -lt 6;$r++){for($g=0;$g -lt 6;$g++){for($b=0;$b -lt 6;$b++){
        $terminal[16+36*$r+6*$g+$b]=@($levels[$r],$levels[$g],$levels[$b])
    }}}
    for($i=0;$i -lt 24;$i++){$v=8+10*$i;$terminal[232+$i]=@($v,$v,$v)}
    $mapping=[int[]]::new(256)
    for($i=0;$i -lt 256;$i++){
        $best=[int]::MaxValue
        for($j=16;$j -lt 256;$j++){
            $dr=$Palette[$i][0]-$terminal[$j][0];$dg=$Palette[$i][1]-$terminal[$j][1];$db=$Palette[$i][2]-$terminal[$j][2]
            $distance=$dr*$dr+$dg*$dg+$db*$db
            if($distance -lt $best){$best=$distance;$mapping[$i]=$j}
        }
    }
    $cells=[string[]]::new(65536);$esc=[char]27;$block=[char]0x2580
    for($top=0;$top -lt 256;$top++){for($bottom=0;$bottom -lt 256;$bottom++){
        $cells[$top*256+$bottom]="$esc[38;5;$($mapping[$top]);48;5;$($mapping[$bottom])m$block"
    }}
    return @{Count=256;Cells=$cells;Mapping=$mapping;TerminalPalette=$terminal;Mode='Ansi256Approximate'}
}

function Get-StripBspDefinition {
    param([string]$Definition)
    # Adapt only viewport clipping in the inspected source, in memory. Retain a
    # full-width coordinate system; workers own disjoint columns of one buffer.
    $definition=$Definition
    $replacements=@{
        '$dsBotZ, $DSMAX)'='$dsBotZ, $DSMAX, $startColumn, $endColumn)';
        '$openCols = $W'='$openCols = $endColumn - $startColumn';
        '$cx1 = $sx1; if ($cx1 -lt 0) { $cx1 = 0 }'='$cx1 = $sx1; if ($cx1 -lt $startColumn) { $cx1 = $startColumn }';
        '$cx2 = $sx2 - 1; if ($cx2 -ge $W) { $cx2 = $W - 1 }'='$cx2 = $sx2 - 1; if ($cx2 -ge $endColumn) { $cx2 = $endColumn - 1 }';
        'for ($x = $cx1; $x -le $cx2; $x++) {'='for ($x = $cx1; $x -le $cx2; $x++) { $iz = $iz1 + ($x - $sx1) * $izStep; if ($texMode) { $uz = $uz1 + ($x - $sx1) * $uzStep }'
    }
    foreach($old in $replacements.Keys) {
        if(-not $definition.Contains($old)){throw "Missing expected renderer seam: $old"}
        $definition=$definition.Replace($old,$replacements[$old])
    }
    return $definition
}

function New-ParallelScene {
    param([hashtable]$Scene,[ValidateRange(1,20)][int]$Workers,[int]$Width=320,[int]$Height=200)
    $definition=Get-StripBspDefinition $Scene.BspDefinition
    $buffer=[byte[]]::new($Width*$Height)
    $states=[Collections.Generic.List[object]]::new()
    $workerBody=@'
param($state,$render,$context,$definition,$encoderDefinition)
$ErrorActionPreference='Stop'
. ([scriptblock]::Create($definition))
. ([scriptblock]::Create($encoderDefinition))
$frequency=[Diagnostics.Stopwatch]::Frequency
$state.Ready.Set() | Out-Null
while($state.Go.WaitOne()) {
    if($state.Stop){break}
    try {
        $before=[Diagnostics.Stopwatch]::GetTimestamp()
        $render.pang=$state.Angle
        $null=Get-BspFrame @render
        $afterRender=[Diagnostics.Stopwatch]::GetTimestamp()
        if($state.Encode){$state.Bytes=ConvertTo-AnsiStrip $render.buf $render.W $render.vres $render.startColumn $render.endColumn $context}
        $afterEncode=[Diagnostics.Stopwatch]::GetTimestamp()
        $state.RenderMs=($afterRender-$before)*1000.0/$frequency
        $state.EncodeMs=($afterEncode-$afterRender)*1000.0/$frequency
        $state.StartQpc=$before;$state.EndQpc=$afterEncode
    } catch {$state.Error=$_.ToString()}
    finally {[void]$state.Done.Set()}
}
'@
    $encoder='function ConvertTo-AnsiStrip {'+(Get-Item Function:\ConvertTo-AnsiStrip).Definition+'}'
    for($i=0;$i -lt $Workers;$i++) {
        $render=New-DoomRenderArguments $Scene $buffer $Width $Height
        $render.startColumn=[int][Math]::Floor($i*$Width/[double]$Workers)
        $render.endColumn=[int][Math]::Floor(($i+1)*$Width/[double]$Workers)
        $state=@{Go=[Threading.AutoResetEvent]::new($false);Done=[Threading.AutoResetEvent]::new($false);
            Ready=[Threading.ManualResetEvent]::new($false);Stop=$false;Angle=0.0;Encode=$true;Error=$null;
            RenderMs=0.0;EncodeMs=0.0;StartQpc=0L;EndQpc=0L;Bytes=$null;FirstColumn=$render.startColumn;EndColumn=$render.endColumn}
        $pipeline=[PowerShell]::Create()
        [void]$pipeline.AddScript($workerBody).AddArgument($state).AddArgument($render).AddArgument($Scene.Context).AddArgument($definition).AddArgument($encoder)
        $state.Pipeline=$pipeline; $state.Async=$pipeline.BeginInvoke()
        $states.Add($state)
        if(-not $state.Ready.WaitOne(30000)){throw 'Worker initialization timed out.'}
    }
    return @{Workers=$states.ToArray();Buffer=$buffer;Width=$Width;Height=$Height;Definition=$definition}
}

function Invoke-ParallelScene {
    param([hashtable]$Pool,[double]$Angle,[bool]$Encode=$true)
    [Array]::Clear($Pool.Buffer)
    foreach($worker in $Pool.Workers){$worker.Angle=$Angle;$worker.Encode=$Encode;[void]$worker.Go.Set()}
    foreach($worker in $Pool.Workers){
        if(-not $worker.Done.WaitOne(30000)){throw 'Worker frame timed out.'}
        if($worker.Error){throw $worker.Error}
    }
}

function Close-ParallelScene {
    param([hashtable]$Pool)
    foreach($worker in $Pool.Workers){$worker.Stop=$true;[void]$worker.Go.Set()}
    foreach($worker in $Pool.Workers){
        $null=$worker.Pipeline.EndInvoke($worker.Async)
        $worker.Pipeline.Dispose();$worker.Go.Dispose();$worker.Done.Dispose();$worker.Ready.Dispose()
    }
}
