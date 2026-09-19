#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
if(Test-Path $Output){throw 'Use a fresh evidence path.'}
$bundle=& "$PSScriptRoot/Build-EngineBundle.ps1";. $bundle
foreach($file in 'GameHost','SnapshotTransport','TerminalCodec','AnsiColorState','CharacterCodec','PaletteCodec'){. "$PSScriptRoot/../src/$file.ps1"}
. "$PSScriptRoot/FrameCodec.ps1"
$checks=[Collections.Generic.List[object]]::new();$content=$null;$failure=$null
function Check([string]$Name,[bool]$Pass){$checks.Add(@{Name=$Name;Passed=$Pass});if(-not $Pass){throw $Name}}
function EqualBytes([byte[]]$A,[byte[]]$B){return [Linq.Enumerable]::SequenceEqual[byte]($A,$B)}
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad));$o=[GameOptions]::new()
    $o.GameMode=$content.Wad.GameMode;$o.GameVersion=$content.Wad.GameVersion;$o.MissionPack=$content.Wad.MissionPack
    $game=[DoomGame]::new($content,$o);$cmd=[TicCmd[]]::new(4);for($i=0;$i -lt 4;$i++){$cmd[$i]=[TicCmd]::new()}
    $game.DeferedInitNew([GameSkill]::Medium,1,1);$null=$game.Update($cmd);$p=$game.World.ConsolePlayer
    # Independent expected boundaries from id Software ST_doPaletteStuff.
    # Damage, bonus, strength elapsed tics, ironfeet remaining tics, expected index.
    $cases=@(@(0,0,0,0,0),@(1,0,0,0,2),@(8,0,0,0,2),@(9,0,0,0,3),@(48,0,0,0,7),@(49,0,0,0,8),@(100,0,0,0,8),
        @(0,1,0,0,10),@(0,8,0,0,10),@(0,9,0,0,11),@(0,16,0,0,11),@(0,17,0,0,12),@(0,100,0,0,12),
        @(0,0,1,0,3),@(0,0,255,0,3),@(0,0,256,0,2),@(0,0,767,0,2),@(0,0,768,0,0),
        @(0,0,0,129,13),@(0,0,0,128,0),@(0,0,0,120,13),@(0,0,0,8,13),@(0,0,0,7,0),
        @(1,100,0,129,2),@(0,1,1,129,3),@(0,1,768,129,10),@(0,0,768,129,13),@(64,0,1,0,8))
    $caseId=0
    foreach($c in $cases){
        $p.DamageCount=$c[0];$p.BonusCount=$c[1];$p.Powers[[int][PowerType]::Strength]=$c[2];$p.Powers[[int][PowerType]::IronFeet]=$c[3]
        $snap=New-GameRenderSnapshot $game;$object=ConvertTo-GameSnapshotBytes $snap;$direct=Get-GameRenderSnapshotBytes $game
        Check "Selection/precedence $caseId" ($snap.ConsolePlayer.PaletteNumber -eq $c[4])
        Check "Object and direct packet $caseId" (EqualBytes $object $direct)
        $pair=Get-GameRenderSnapshotPair $game
        $old=[double[]]::new($pair.Previous.Length/8);$current=[double[]]::new($pair.Current.Length/8)
        [Buffer]::BlockCopy($pair.Previous,0,$old,0,$pair.Previous.Length);[Buffer]::BlockCopy($pair.Current,0,$current,0,$pair.Current.Length)
        foreach($fraction in 0,.5,1){$decoded=Read-GameSnapshotBytes (Get-InterpolatedSnapshotBytes $old $current $fraction) $null
            Check "Discrete palette $caseId at $fraction" ($decoded.ConsolePlayer.PaletteNumber -eq $c[4])}
        $caseId++
    }
    # Enumerate every top/bottom combination, not just colors seen in one room.
    $pixels=[byte[]]::new(256*512)
    for($top=0;$top -lt 256;$top++){for($bottom=0;$bottom -lt 256;$bottom++){$pixels[2*$top*256+$bottom]=[byte]$top;$pixels[(2*$top+1)*256+$bottom]=[byte]$bottom}}
    $small=New-IndexedFrame 32 16 7 Entropy 256
    for($number=0;$number -lt 14;$number++){
        $rgb=Get-DoomPaletteRgb $content.Palette.Data $number
        $rgbMatches=$true;for($i=0;$i -lt 256;$i++){for($j=0;$j -lt 3;$j++){if($rgb[$i][$j] -ne $content.Palette.Data[$number*768+$i*3+$j]){$rgbMatches=$false}}}
        Check "PLAYPAL RGB $number" $rgbMatches
        $eager=New-AnsiColorStateContext $rgb;$lazy=New-AnsiColorStateContext $rgb -LazyCells
        Check "Empty lazy pair table $number" (@($lazy.Cells|Where-Object {$null -ne $_}).Count -eq 0)
        Check "All 65,536 Classic pairs $number" (EqualBytes (ConvertTo-AnsiStrip $pixels 256 512 0 256 $eager) (ConvertTo-AnsiStrip $pixels 256 512 0 256 $lazy))
        Check "All color-state pairs $number" (EqualBytes (ConvertTo-AnsiColorStateStrip $pixels 256 512 0 256 $eager) (ConvertTo-AnsiColorStateStrip $pixels 256 512 0 256 $lazy))
        foreach($style in 'Matrix','AnsiArt'){
            $full=New-CharacterCodecContext $rgb $style -GlyphSet Katakana;$sparse=New-CharacterCodecContext $rgb $style -GlyphSet Katakana -LazyCells
            Check "$style scene/HUD $number" (EqualBytes (ConvertTo-CharacterStrip $small 32 16 0 32 $full -HudStart 12 -FrameNumber 123) (ConvertTo-CharacterStrip $small 32 16 0 32 $sparse -HudStart 12 -FrameNumber 123))
            foreach($hudStart in -1,12){Check "$style menu/map $number HUD $hudStart" (EqualBytes (ConvertTo-MenuStrip $small 32 16 0 32 $full -HudStart $hudStart) (ConvertTo-MenuStrip $small 32 16 0 32 $sparse -HudStart $hudStart))}
        }
    }
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace;throw}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Checks=$checks.ToArray();WadSha256=(Get-FileHash $Wad).Hash;BundleSha256=(Get-FileHash $bundle).Hash;
        Sources=@('src/PaletteCodec.ps1','scripts/FrameCodec.ps1','src/CharacterCodec.ps1','src/AnsiColorState.ps1','src/TerminalCodec.ps1','src/GameHost.ps1','src/SnapshotTransport.ps1',$PSCommandPath|ForEach-Object {$path=if([IO.Path]::IsPathRooted($_)){$_}else{"$PSScriptRoot/../$_"};@{Path=$_;Sha256=(Get-FileHash $path).Hash}});
        Meaning='Explicit palette-selection boundaries and precedence, actual object/direct snapshots and interpolation, all PLAYPAL RGB entries, exhaustive Classic pair encoding and character scene/menu/HUD equivalence to eager tables. No campaign completion or displayed-frame performance claim.'}|ConvertTo-Json -Depth 6|Set-Content $Output
}
"PASS: $($checks.Count) palette checks."
