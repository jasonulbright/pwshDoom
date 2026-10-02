#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Renderer="$PSScriptRoot/../src/FastRenderer.ps1",
    [ValidateRange(1,256)][int]$TextureHeight=128,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report.'}
$taskBundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $taskBundle
. $Renderer
function Draw-FastHud {}
function Draw-FastPlayerSprites {}
$taskContent=$null;$taskError=$null;$taskCases=[Collections.Generic.List[object]]::new()
$taskCompared=0;$taskMismatches=0
try {
    $taskContent=[GameContent]::new(@('-iwad',$Wad))
    $taskConfig=[Config]::new();$taskConfig.video_highresolution=$false;$taskConfig.video_gamescreensize=7
    $taskReference=[Renderer]::new($taskConfig,$taskContent)
    $taskRows=[byte[]](0..127);$taskColumn=[Column]::new(0,$taskRows,0,128)
    $taskTexels=[int[]]::new(64*$TextureHeight)
    for($taskU=0;$taskU -lt 64;$taskU++){for($taskV=0;$taskV -lt $TextureHeight;$taskV++){$taskTexels[$taskU*$TextureHeight+$taskV]=$taskV}}
    $taskMaskTexels=$taskTexels.Clone();for($taskI=0;$taskI -lt $taskMaskTexels.Length;$taskI++){if(($taskMaskTexels[$taskI]%11) -lt 2){$taskMaskTexels[$taskI]=-1}}
    $taskBackdrop=[int[]]::new(64*128);[Array]::Fill($taskBackdrop,201)
    $taskFlat=[byte[]]::new(4096);[Array]::Fill($taskFlat,[byte]200)
    $taskIdentity=[byte[]](0..255);$taskColors=@(for($taskI=0;$taskI -lt 33;$taskI++){,$taskIdentity})
    $taskContext=@{Pixels=[byte[]]::new(64000);Depth=[double[]]::new(64000);Planes=[int[]]::new(53760);
        TopClip=[int[]]::new(320);BottomClip=[int[]]::new(320);Stack=[int[]]::new(4);
        NodeGeometry=[double[]]::new(0);NodeChildren=[int[]]::new(0);Subsectors=@{32767=@{FirstSeg=0;SegCount=1}};
        SegmentGeometry=[double[]]::new(6);SegmentMetadata=[int[]]::new(4);
        Lighting=(New-FastLightingTables);Colors=$taskColors;SkyFlat=1;Sky=@{Data=[int[]]@(0);Width=1;Height=1};
        Sectors=@(@{FloorHeight=0;CeilingHeight=128;FloorFlat=0;CeilingFlat=0;LightLevel=255},@{FloorHeight=0;CeilingHeight=0;FloorFlat=0;CeilingFlat=0;LightLevel=255},@{FloorHeight=-8192;CeilingHeight=8192;FloorFlat=0;CeilingFlat=0;LightLevel=255});
        Flats=@(@{Data=$taskFlat});Sides=@(@{MiddleTexture=1;TopTexture=1;BottomTexture=1;TextureOffset=0;RowOffset=0},@{MiddleTexture=2;TopTexture=0;BottomTexture=0;TextureOffset=0;RowOffset=0});
        Textures=@{1=@{Width=64;Height=$TextureHeight;Data=$taskTexels};2=@{Width=64;Height=128;Data=$taskBackdrop}};MaskedColumns=[Collections.Generic.List[hashtable]]::new();
        World=@{Actors=@();ConsolePlayer=@{Mobj=@{X=0;Y=0;Angle=0};ViewZ=41;ExtraLight=0;FixedColorMap=0}}}
    $taskTables=Get-FastPlaneTables
    $taskContext.PlaneColumnAngles=$taskTables.ColumnAngles;$taskContext.PlaneDistanceScales=$taskTables.DistanceScales
    $taskContext.PlaneRowSlopes=$taskTables.RowSlopes;$taskContext.PlaneFineSine=$taskTables.FineSine
    $taskContext.TanToAngleTable=$taskTables.TanToAngle
    $taskContext.SkyColumns=[int[]]::new(320);$taskContext.RaySin=[int[]]::new(320);$taskContext.RayCos=[int[]]::new(320)
    foreach($taskKind in 'Solid','Upper','Lower','Masked'){
        $taskContext.Subsectors[32767].SegCount=if($taskKind -eq 'Masked'){2}else{1}
        $taskContext.SegmentMetadata=if($taskKind -eq 'Masked'){[int[]]@(0,0,1,0,1,2,-1,0)}else{[int[]]::new(4)}
        $taskContext.SegmentMetadata[2]=if($taskKind -eq 'Solid'){-1}else{1}
        $taskContext.SegmentMetadata[3]=if($taskKind -eq 'Upper'){8}elseif($taskKind -eq 'Lower'){16}else{0}
        $taskContext.Sectors[1].FloorHeight=if($taskKind -eq 'Lower'){128}else{0}
        $taskContext.Sectors[1].CeilingHeight=if($taskKind -in 'Lower','Masked'){128}else{0}
        $taskContext.Textures[1].Data=if($taskKind -eq 'Masked'){$taskMaskTexels}else{$taskTexels}
        Update-FastRenderSectorData $taskContext $taskContext.Sectors
        foreach($taskDistance in 16.0,24.0,24.25,64.0,80.0,128.0,128.125,160.0,256.0,512.0,1024.0){
            $taskContext.SegmentGeometry=[double[]]@($taskDistance,($taskDistance*2),$taskDistance,(-$taskDistance*2),($taskDistance*4),0)
            if($taskKind -eq 'Masked'){$taskContext.SegmentGeometry+=[double[]]@(($taskDistance*2),($taskDistance*4),($taskDistance*2),(-$taskDistance*4),($taskDistance*8),0)}
            # Independent integer projection scale for this front-facing, constant-distance wall.
            $taskRem=0L;$taskDistanceData=[long][Math]::Truncate($taskDistance*65536)
            $taskScale=[Math]::DivRem(687194767360L,$taskDistanceData,[ref]$taskRem)
            $taskScale=[Math]::Clamp($taskScale,256L,4194304L)
            $taskInv=[int][Math]::DivRem(4294967295L,$taskScale,[ref]$taskRem)
            foreach($taskOffset in 0.0,0.5,-0.5,-127.75){
                $taskContext.Sides[0].RowOffset=$taskOffset
                Invoke-FastRender $taskContext
                $taskY0=[Math]::Max(0,[Math]::Ceiling(84-160*87/$taskDistance-0.5))
                $taskY1=[Math]::Min(167,[Math]::Floor(84+160*41/$taskDistance-0.5))
                [Array]::Clear($taskReference.Screen.Data)
                $taskAlt=[int][Math]::Truncate((87+$taskOffset)*65536)
                $taskReference.ThreeD.DrawColumn($taskColumn,$taskIdentity,160,$taskY0,$taskY1,[Fixed]::new($taskInv),[Fixed]::new($taskAlt))
                $taskWrong=0;$taskCount=0;$taskExamples=[Collections.Generic.List[object]]::new()
                for($taskY=$taskY0;$taskY -le $taskY1;$taskY++){
                    # Reference screen is column-major; the candidate is row-major.
                    $taskExpected=$taskReference.Screen.Data[160*200+$taskY]
                    $taskExpectedDepth=$taskDistance
                    # All scalar values are exact integers below 2^53. Floor in
                    # double then DivRem exercises arbitrary-height wrapping
                    # independently of the candidate's shifted accumulator/mask.
                    $taskRawRow=[long][Math]::Floor(($taskAlt+[double]($taskY-84)*$taskInv)/65536.0)
                    if($TextureHeight -ne 128){
                        $taskRemainder=0L;[void][Math]::DivRem($taskRawRow,[long]$TextureHeight,[ref]$taskRemainder)
                        if($taskRemainder -lt 0){$taskRemainder+=$TextureHeight}
                        $taskExpected=[byte]$taskRemainder
                    }
                    if($taskKind -eq 'Masked'){
                        if($taskRawRow -lt 0 -or $taskRawRow -ge $TextureHeight -or ($taskExpected%11) -lt 2){$taskExpected=201;$taskExpectedDepth=$taskDistance*2}
                    }
                    for($taskX=0;$taskX -lt 320;$taskX++){
                        $taskIndex=$taskY*320+$taskX;$taskActual=$taskContext.Pixels[$taskIndex]
                        if($taskActual -ne $taskExpected -or $taskContext.Depth[$taskIndex] -ne $taskExpectedDepth){
                            $taskWrong++
                            if($taskExamples.Count -lt 4){$taskExamples.Add(@{X=$taskX;Y=$taskY;Actual=$taskActual;Expected=$taskExpected;Depth=$taskContext.Depth[$taskIndex]})}
                        }
                        $taskCount++
                    }
                }
                $taskCompared+=$taskCount;$taskMismatches+=$taskWrong
                $taskCases.Add(@{Kind=$taskKind;Distance=$taskDistance;RowOffset=$taskOffset;ScaleData=$taskScale;InverseScaleData=$taskInv;Y0=$taskY0;Y1=$taskY1;Compared=$taskCount;Mismatches=$taskWrong;Examples=$taskExamples.ToArray()})
            }
        }
    }
}catch{$taskError=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($taskContent){$taskContent.Dispose()}
    @{Error=$taskError;FinishedUtc=[DateTime]::UtcNow.ToString('o');TextureHeight=$TextureHeight;Cases=$taskCases.ToArray();Compared=$taskCompared;Mismatches=$taskMismatches;
        RendererSha256=(Get-FileHash $Renderer).Hash;ReferenceSha256=(Get-FileHash "$PSScriptRoot/../src/ManagedDoom/Video/ThreeDRenderer.sb.ps1").Hash;
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;WadSha256=(Get-FileHash $Wad).Hash;
        Meaning='Real candidate whole-scene wall drawing against adopted reference DrawColumn at height128, independent Floor/DivRem row and normalized remainder at other heights. Integer scale/inverse scale are independently computed. Authored row-pattern textures, three opaque bands plus finite masked rows/holes over a farther wall, eleven constant distances and four offsets; HUD/weapon no-ops. Compares only candidate-defined coverage, isolating texel stepping, transparency and depth. Mask bounds use the scalar unwrapped fraction; this does not qualify reference masked-post edge coverage, wall edges, general BSP projection, whole-map original fidelity or pacing.'}|ConvertTo-Json -Depth 7|Set-Content $Output
}
if($taskError){throw $taskError}
if($taskMismatches){throw "Wall vertical sampling mismatches: $taskMismatches of $taskCompared; report retained."}
"PASS: $taskCompared wall texels/depth samples in $($taskCases.Count) fixtures."
