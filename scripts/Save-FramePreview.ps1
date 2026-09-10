#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
# Offline inspection only. System.Drawing is not part of game rendering/output.
param([int[]]$Tics=@(350,700,1050,1400),[string]$Output="$PSScriptRoot/../local/e1m1-preview.png")
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$palette=[IO.File]::ReadAllBytes("$PSScriptRoot/../local/palette.bin")
$rows=[int][Math]::Ceiling($Tics.Count/2.0);$sheet=[Drawing.Bitmap]::new(1280,$rows*430)
$graphics=[Drawing.Graphics]::FromImage($sheet);$graphics.Clear([Drawing.Color]::Black)
$graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$graphics.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$font=[Drawing.Font]::new('Consolas',12)
try {
    for($i=0;$i -lt $Tics.Count;$i++) {
        $pixels=[IO.File]::ReadAllBytes("$PSScriptRoot/../local/capture-$($Tics[$i]).bin")
        if($pixels.Length -ne 64000 -or $palette.Length -ne 768){throw 'Invalid framebuffer or palette size.'}
        $frame=[Drawing.Bitmap]::new(320,200)
        try {
            for($y=0;$y -lt 200;$y++){for($x=0;$x -lt 320;$x++){$p=3*[int]$pixels[$y*320+$x];$frame.SetPixel($x,$y,[Drawing.Color]::FromArgb($palette[$p],$palette[$p+1],$palette[$p+2]))}}
            $left=($i%2)*640;$top=[int][Math]::Floor($i/2.0)*430
            $graphics.DrawString("Offline framebuffer / command tic $($Tics[$i])",$font,[Drawing.Brushes]::White,$left+8,$top+5)
            $graphics.DrawImage($frame,[Drawing.Rectangle]::new($left,$top+30,640,400))
        } finally {$frame.Dispose()}
    }
    $sheet.Save([IO.Path]::GetFullPath($Output),[Drawing.Imaging.ImageFormat]::Png)
} finally {$font.Dispose();$graphics.Dispose();$sheet.Dispose()}
[IO.Path]::GetFullPath($Output)
