#requires -Version 7.4
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [int]$FirstColumn=0,[int]$EndColumn=320,[int]$Frames=12,[int]$Tics=0,
    [string]$Output="$PSScriptRoot/../results/fast-renderer.json")
$ErrorActionPreference='Stop'
. "$PSScriptRoot/FrameCodec.ps1"
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1"
. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"
$content=$null
try {
    $null=[DoomInfo]::SwitchNames
    $content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$cmd=[TicCmd[]]::new(4)
    for($i=0;$i -lt 4;$i++){$cmd[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($cmd)
    @{Lines=@($game.World.Map.Lines | ForEach-Object {@{X1=$_.Vertex1.X.Data/65536.0;Y1=$_.Vertex1.Y.Data/65536.0;
        X2=$_.Vertex2.X.Data/65536.0;Y2=$_.Vertex2.Y.Data/65536.0;Special=[int]$_.Special;Solid=$null -eq $_.BackSector}});
        Things=@($game.World.Map.Things | ForEach-Object {@{X=$_.X.Data/65536.0;Y=$_.Y.Data/65536.0;Type=$_.Type;Flags=[int]$_.Flags}})} |
        ConvertTo-Json -Depth 5 | Set-Content "$PSScriptRoot/../local/map-geometry.json"
    for($i=0;$i -lt $Tics;$i++){$cmd[0].ForwardMove=25;$null=$game.Update($cmd)}
    $ctx=New-FastRenderContext $content $game.World
    Set-GameRenderSnapshot $ctx (New-GameRenderSnapshot $game)
    $times=[double[]]::new($Frames)
    for($i=0;$i -lt $Frames;$i++) {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        Invoke-FastRender $ctx $FirstColumn $EndColumn
        $times[$i]=$watch.Elapsed.TotalMilliseconds
    }
    [IO.File]::WriteAllBytes("$PSScriptRoot/../local/fast-frame.bin",$ctx.Pixels)
    [IO.File]::WriteAllBytes("$PSScriptRoot/../local/palette.bin",$content.Palette.Data)
    $report=@{Profile=$ctx.Profile;FinishedUtc=[DateTime]::UtcNow.ToString('o');Tics=$Tics;FirstColumn=$FirstColumn;EndColumn=$EndColumn;RenderMs=(Get-SampleStats $times);SamplesMs=$times;WadSha256=(Get-FileHash $Wad).Hash}
    $report | ConvertTo-Json -Depth 5 | Set-Content $Output
    $report | ConvertTo-Json -Depth 5
} catch {[Console]::Error.WriteLine($_.ScriptStackTrace);throw}
finally {if($null -ne $content){$content.Dispose()}}
