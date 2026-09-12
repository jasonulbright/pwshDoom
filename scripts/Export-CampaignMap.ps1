#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$OutputPrefix,[int]$Episode=1,[int]$Map=2,[string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';$prefix=[IO.Path]::GetFullPath($OutputPrefix)
if((Test-Path ($prefix+'.json')) -or (Test-Path ($prefix+'.png'))){throw 'Use fresh map output paths under ignored local/.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
Add-Type -AssemblyName System.Drawing
$content=$null;$bitmap=$null;$graphics=$null;$font=$null;$pens=@{}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$game.InitNew([GameSkill]::Medium,$Episode,$Map);$world=$game.World
    $lines=@(for($i=0;$i -lt $world.Map.Lines.Count;$i++){$line=$world.Map.Lines[$i];@{Index=$i;X1=$line.Vertex1.X.Data/65536.0;Y1=$line.Vertex1.Y.Data/65536.0;X2=$line.Vertex2.X.Data/65536.0;Y2=$line.Vertex2.Y.Data/65536.0;Special=$line.Special;Tag=$line.Tag;TwoSided=($null -ne $line.BackSector)}})
    $things=@(foreach($thing in $world.Map.Things){@{X=$thing.X.Data/65536.0;Y=$thing.Y.Data/65536.0;Type=$thing.Type;Flags=[int]$thing.Flags}})
    $xs=@($lines.X1)+@($lines.X2);$ys=@($lines.Y1)+@($lines.Y2);$minX=($xs|Measure-Object -Minimum).Minimum;$maxX=($xs|Measure-Object -Maximum).Maximum;$minY=($ys|Measure-Object -Minimum).Minimum;$maxY=($ys|Measure-Object -Maximum).Maximum
    $scale=[Math]::Min(1700/($maxX-$minX),1100/($maxY-$minY));$width=[int](($maxX-$minX)*$scale)+120;$height=[int](($maxY-$minY)*$scale)+120
    $bitmap=[Drawing.Bitmap]::new($width,$height);$graphics=[Drawing.Graphics]::FromImage($bitmap);$graphics.Clear([Drawing.Color]::FromArgb(20,23,28));$font=[Drawing.Font]::new('Consolas',9)
    foreach($name in 'Gray','White','Gold','Lime','Cyan'){$pens[$name]=[Drawing.Pen]::new([Drawing.Color]::$name,1.5)}
    function PX($x){return [single](60+($x-$minX)*$scale)}
    function PY($y){return [single](60+($maxY-$y)*$scale)}
    for($x=[Math]::Ceiling($minX/256)*256;$x -le $maxX;$x+=256){$graphics.DrawString([string]$x,$font,[Drawing.Brushes]::Gray,(PX $x),[single]10)}
    for($y=[Math]::Ceiling($minY/256)*256;$y -le $maxY;$y+=256){$graphics.DrawString([string]$y,$font,[Drawing.Brushes]::Gray,[single]0,(PY $y))}
    foreach($line in $lines){
        $name=if($line.Special -in 11,51,52,124){'Lime'}elseif($line.Special){'Gold'}elseif($line.TwoSided){'Gray'}else{'White'}
        $graphics.DrawLine($pens[$name],(PX $line.X1),(PY $line.Y1),(PX $line.X2),(PY $line.Y2))
        if($line.Special){$graphics.DrawString("$($line.Index):$($line.Special)",$font,[Drawing.Brushes]::Gold,(PX (($line.X1+$line.X2)/2)),(PY (($line.Y1+$line.Y2)/2)))}
    }
    foreach($thing in $things){
        if($thing.Type -in 1,5,6,13,38,39,40,2001,2002){$graphics.DrawString("T$($thing.Type)",$font,[Drawing.Brushes]::Cyan,(PX $thing.X),(PY $thing.Y))}
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($prefix));$bitmap.Save($prefix+'.png',[Drawing.Imaging.ImageFormat]::Png)
    @{Episode=$Episode;Map=$Map;WadSha256=(Get-FileHash $Wad).Hash;Lines=$lines;Things=$things;Bounds=@($minX,$minY,$maxX,$maxY);Meaning='User-local map geometry for route planning. System.Drawing renders this documentation diagram only; no gameplay or game renderer uses it. Gold labels are linedef index:special; cyan labels are raw thing types.'}|ConvertTo-Json -Depth 5|Set-Content ($prefix+'.json')
}finally{foreach($pen in $pens.Values){$pen.Dispose()};if($font){$font.Dispose()};if($graphics){$graphics.Dispose()};if($bitmap){$bitmap.Dispose()};if($content){$content.Dispose()}}
$prefix+'.png'
