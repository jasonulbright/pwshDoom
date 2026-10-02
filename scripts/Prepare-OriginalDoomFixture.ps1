#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# Diagnostic fixtures only. The original executable/emulator is never a game dependency.
param([Parameter(Mandatory)][string]$Replay,[Parameter(Mandatory)][string]$Directory,
    [ValidateRange(1,10000)][int]$Commands=315,[ValidateRange(35,10500)][int]$PausedCommands=2100,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD',
    [string]$OriginalExecutable='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.EXE',
    [string]$Emulator='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\dosbox\dosbox.exe')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath($Directory)
if(Test-Path -LiteralPath $root){throw 'Use a fresh fixture directory; original assets and prior attempts are never overwritten.'}
$inputData=Get-Content -LiteralPath $Replay -Raw|ConvertFrom-Json
if($inputData.InputCommands.Count -lt $Commands){throw 'Insufficient supplied commands.'}
if($inputData.WadSha256 -ne (Get-FileHash -LiteralPath $Wad).Hash){throw 'Supplied replay/IWAD identity differs.'}
if($inputData.Skill -notin 1..5 -or $inputData.Episode -notin 1..4 -or $inputData.Map -notin 1..9){throw 'Invalid single-player map/skill options.'}
foreach($path in $OriginalExecutable,$Emulator){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing installed reference resource: $path"}}
$bytes=[Collections.Generic.List[byte]]::new()
$bytes.AddRange([byte[]]@(109,($inputData.Skill-1),$inputData.Episode,$inputData.Map,0,0,0,0,0,1,0,0,0))
for($n=0;$n -lt $Commands;$n++){
    $v=$inputData.InputCommands[$n]
    if(@($v|Where-Object {$_ -isnot [ValueType] -or [double]$_ -ne [Math]::Truncate([double]$_)}).Count){throw "Command $n contains a non-integer field."}
    if($v.Count -ne 4 -or $v[0] -lt -127 -or $v[0] -gt 127 -or $v[1] -lt -128 -or $v[1] -gt 127 -or $v[2] -lt -32768 -or $v[2] -gt 32767 -or $v[2]%256 -ne 0 -or $v[3] -lt 0 -or $v[3] -gt 127){throw "Command $n is not an exact vanilla single-player movement packet; provide explicitly quantized input without special controls."}
    $bytes.Add([byte]($v[0] -band 255));$bytes.Add([byte]($v[1] -band 255));$bytes.Add([byte](($v[2] -shr 8) -band 255));$bytes.Add([byte]$v[3])
}
# An ordinary original-demo pause packet freezes the world after the prefix.
# Following empty demo packets provide a finite capture interval, then terminate.
$bytes.AddRange([byte[]]@(0,0,0,129))
for($n=0;$n -lt $PausedCommands;$n++){$bytes.AddRange([byte[]]@(0,0,0,0))}
$bytes.Add(128)
[void][IO.Directory]::CreateDirectory($root)
Copy-Item -LiteralPath $Wad -Destination "$root/DOOM.WAD"
Copy-Item -LiteralPath $OriginalExecutable -Destination "$root/DOOM.EXE"
[IO.File]::WriteAllBytes("$root/FROZEN.LMP",$bytes.ToArray())
@'
screenblocks 10
detaillevel 0
usegamma 0
use_mouse 0
use_joystick 0
show_messages 0
snd_musicdevice 0
snd_sfxdevice 0
'@|Set-Content -LiteralPath "$root/DEFAULT.CFG" -Encoding ascii
# Doom saves its configuration on exit. Preserve the emitted input separately.
Copy-Item -LiteralPath "$root/DEFAULT.CFG" -Destination "$root/DEFAULT.initial.CFG"
@'
[sdl]
fullscreen=false
windowresolution=640x400
output=texturenb
vsync=off
[render]
aspect=off
glshader=none
[capture]
capture_dir=capture
default_image_capture_formats=raw
[midi]
mididevice=none
'@|Set-Content -LiteralPath "$root/reference.conf" -Encoding ascii
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1"
. "$PSScriptRoot/../src/GameHost.ps1"
$content=$null;$failure=$null;$endpoint=$null
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    $demo=[Demo]::new("$root/FROZEN.LMP")
    $demo.Options.GameMode=$content.Wad.GameMode;$demo.Options.GameVersion=$content.Wad.GameVersion;$demo.Options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$demo.Options);$game.DeferedInitNew()
    $cmds=[TicCmd[]]@([TicCmd]::new(),[TicCmd]::new(),[TicCmd]::new(),[TicCmd]::new())
    for($n=0;$n -lt $Commands;$n++){
        if(-not $demo.ReadCmd($cmds)){throw 'Generated demo terminates inside its input prefix.'}
        $actual=@($cmds[0].ForwardMove,$cmds[0].SideMove,$cmds[0].AngleTurn,$cmds[0].Buttons)
        for($field=0;$field -lt 4;$field++){if($actual[$field] -ne $inputData.InputCommands[$n][$field]){throw "Decoded command $n field $field differs."}}
        $null=$game.Update($cmds)
    }
    $tic=$game.World.LevelTime
    if(-not $demo.ReadCmd($cmds) -or $cmds[0].Buttons -ne 129){throw 'Missing pause command.'}
    $null=$game.Update($cmds)
    if(-not $game.Paused -or $game.World.LevelTime -ne $tic){throw 'Pause packet did not freeze the candidate world.'}
    $snapshot=New-GameRenderSnapshot $game 1
    $context=New-FastRenderContext $content $game.World
    Set-GameRenderSnapshot $context $snapshot;Invoke-FastRender $context
    [IO.File]::WriteAllBytes("$root/candidate-indexed.bin",$context.Pixels)
    $paletteNumber=[Renderer]::GetPaletteNumber($game.World.ConsolePlayer)
    $palette=$content.Wad.ReadLump('PLAYPAL');$paletteOffset=768*$paletteNumber
    $bitmap=[Drawing.Bitmap]::new(320,200)
    try{
        for($y=0;$y -lt 200;$y++){for($x=0;$x -lt 320;$x++){
            $offset=$paletteOffset+3*$context.Pixels[$y*320+$x]
            $bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb($palette[$offset],$palette[$offset+1],$palette[$offset+2]))
        }}
        $bitmap.Save("$root/candidate.png",[Drawing.Imaging.ImageFormat]::Png)
    }finally{$bitmap.Dispose()}
    $p=$game.World.ConsolePlayer
    $endpoint=@{LevelTime=$tic;Paused=$game.Paused;X=$p.Mobj.X.Data;Y=$p.Mobj.Y.Data;Z=$p.Mobj.Z.Data;Angle=$p.Mobj.Angle.Data;ViewZ=$p.ViewZ.Data;Health=$p.Health;Armor=$p.ArmorPoints;Kills=$p.KillCount;Rng=$game.World.Random.Index;PaletteNumber=$paletteNumber;SnapshotTic=$snapshot.Tic}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Commands=$Commands;PausedCommands=$PausedCommands;Episode=$inputData.Episode;Map=$inputData.Map;Skill=$inputData.Skill;Endpoint=$endpoint;
        Sources=@('src/FastRenderer.ps1','src/GameHost.ps1','src/ManagedDoom/Doom/Game/DoomGame.sb.ps1','src/ManagedDoom/Doom/Game/Demo.sb.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}});
        InputReplaySha256=(Get-FileHash -LiteralPath $Replay).Hash;OriginalExecutableSha256=(Get-FileHash -LiteralPath $OriginalExecutable).Hash;EmulatorSha256=(Get-FileHash -LiteralPath $Emulator).Hash;WadSha256=(Get-FileHash -LiteralPath $Wad).Hash;HarnessSha256=(Get-FileHash $PSCommandPath).Hash;EngineBundleSha256=(Get-FileHash -LiteralPath $bundle).Hash;
        GeneratedFiles=@('FROZEN.LMP','DEFAULT.CFG','DEFAULT.initial.CFG','reference.conf','candidate-indexed.bin','candidate.png'|Where-Object {Test-Path -LiteralPath "$root/$_"}|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$root/$_").Hash}});
        Meaning='Diagnostic fixture only: explicitly quantized ordinary-input prefix followed by a vanilla pause packet and finite empty packets. Candidate executes the generated demo including DemoPlayback with no boot/idle command before the prefix; all four decoded fields agree. Candidate world pause/endpoint is verified, original binary execution/capture/synchronization remain separate. Original exe and emulator are external comparison tools, never production game/render/audio dependencies. Derived assets and human-input bytes remain local.'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath "$root/fixture.json"
}
"Prepared original-executable frozen fixture: $root"
