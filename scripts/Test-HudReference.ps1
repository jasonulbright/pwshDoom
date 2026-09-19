#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh report path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
. "$PSScriptRoot/../src/FastRenderer.ps1";. "$PSScriptRoot/../src/GameHost.ps1";. "$PSScriptRoot/../src/RenderAssets.ps1"
$sources=@('scripts/Test-HudReference.ps1','src/FastRenderer.ps1','src/GameHost.ps1','src/RenderAssets.ps1'|ForEach-Object {@{Path=$_;Sha256=(Get-FileHash "$PSScriptRoot/../$_").Hash}})
$content=$null;$failure=$null;$checks=[Collections.Generic.List[object]]::new()
$cache=Join-Path "$PSScriptRoot/../local" ('hud-reference-'+[guid]::NewGuid().ToString('N')+'.bin')
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$options=[GameOptions]::new()
    $options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$options);$commands=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$commands[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($commands)
    $screen=[DrawScreen]::new($content.Wad,320,200);$reference=[StatusBarRenderer]::new($content.Wad,$screen)
    $context=New-FastRenderContext $content $game.World
    $palette=[int[][]]::new(256);for($i=0;$i -lt 256;$i++){$palette[$i]=@($content.Palette.Data[3*$i],$content.Palette.Data[3*$i+1],$content.Palette.Data[3*$i+2])}
    Write-GameRenderAssets $context $palette $cache;$transport=Read-GameRenderAssets $cache
    $values=@(0,1,9,10,11,50,99,100,101,199,200,999,1000,1994,-1,-100)
    $p=$game.World.ConsolePlayer
    for($case=0;$case -lt 64;$case++){
        $p.Health=$values[$case%$values.Count];$p.ArmorPoints=$values[($case+3)%$values.Count]
        $p.ReadyWeapon=[WeaponType]($case%9);$game.World.StatusBar.FaceIndex=$case%$context.Hud.Faces.Count
        for($i=0;$i -lt 6;$i++){$p.WeaponOwned[$i+1]=[bool]($case -band (1 -shl $i));$p.Cards[$i]=[bool]($case -band (1 -shl $i))}
        for($i=0;$i -lt 4;$i++){$p.Ammo[$i]=$values[($case+$i)%$values.Count];$p.MaxAmmo[$i]=$values[($case+$i+5)%$values.Count]}
        [Array]::Clear($screen.Data);$reference.Render($p,$true)
        $snapshot=New-GameRenderSnapshot $game;Set-GameRenderSnapshot $context $snapshot;Set-GameRenderSnapshot $transport $snapshot
        [Array]::Clear($context.Pixels);[Array]::Clear($transport.Pixels);Draw-FastHud $context
        # Exercise cache transport and an uneven seven-way split across glyphs.
        $bounds=@(0,45,91,137,182,228,274,320)
        for($strip=0;$strip -lt 7;$strip++){Draw-FastHud $transport $bounds[$strip] $bounds[$strip+1]}
        $differences=0;$transportDifferences=0
        for($y=168;$y -lt 200;$y++){for($x=0;$x -lt 320;$x++){
            $i=$y*320+$x;if($context.Pixels[$i] -ne $screen.Data[$x*200+$y]){$differences++}
            if($context.Pixels[$i] -ne $transport.Pixels[$i]){$transportDifferences++}
        }}
        $checks.Add(@{Case=$case;Face=$game.World.StatusBar.FaceIndex;Health=$p.Health;Armor=$p.ArmorPoints;Weapon=$p.ReadyWeapon.ToString();ReferenceDifferences=$differences;TransportStripDifferences=$transportDifferences;ComparedPixels=10240})
        if($differences -or $transportDifferences){throw "HUD case $case differs: reference $differences, cached strips $transportDifferences."}
    }
    'PASS: 64 HUD states match the adopted reference and cached seven-strip output.'
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();Sources=$sources;SourcesChangedDuringRun=@($sources|Where-Object {$_.Sha256 -cne (Get-FileHash "$PSScriptRoot/../$($_.Path)").Hash}|ForEach-Object {$_.Path});
      WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;
      Meaning='Explicit synthetic single-player HUD fixtures cover all 64 weapon/key bit combinations, all face indices, ready weapons including no-ammo, and numeric boundaries. Exact 320x32 palette-index comparison to the adopted PowerShell status renderer plus binary asset transport and seven uneven strips. Not original-executable validation, multiplayer, terminal capture, gameplay or performance evidence.'}|ConvertTo-Json -Depth 7|Set-Content -LiteralPath $Output
}
