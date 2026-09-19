#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([Parameter(Mandatory)][string]$Output,
    [string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a fresh map comparison report.'}
$owned=Join-Path "$PSScriptRoot/../local" ('discovery-maps-'+[guid]::NewGuid().ToString('N'))
$original=& "$PSScriptRoot/Build-EngineBundle.ps1" -Output "$owned/baseline.ps1"
$builder="$PSScriptRoot/experiments/Add-IndexedDiscoveryCache.ps1"
$bundle=& $builder -Bundle $original -Output "$owned/candidate.ps1"
. $bundle
$content=$null;$failure=$null;$maps=0;$cases=[Collections.Generic.List[object]]::new()
try{
    $null=[DoomInfo]::SwitchNames;$content=[GameContent]::new(@('-iwad',$Wad))
    $screens=@([DrawScreen]::new($content.Wad,320,200),[DrawScreen]::new($content.Wad,320,200))
    $renderers=@([ThreeDRenderer]::new($content,$screens[0],7),[ThreeDRenderer]::new($content,$screens[1],7))
    $renderers[1].CacheDiscoveryAngles=$true
    $sentinel=[byte[]]::new(64000);[Array]::Fill($sentinel,[byte]77)
    $commands=[TicCmd[]]::new(4);for($j=0;$j -lt 4;$j++){$commands[$j]=[TicCmd]::new()}
    foreach($episode in 1..4){foreach($map in 1..9){
        $options=[GameOptions]::new();$options.GameMode=$content.Wad.GameMode;$options.GameVersion=$content.Wad.GameVersion;$options.MissionPack=$content.Wad.MissionPack
        $game=[DoomGame]::new($content,$options);$game.DeferedInitNew([GameSkill]::Medium,$episode,$map);$null=$game.Update($commands)
        $world=$game.World;$player=$world.ConsolePlayer;$angle=$player.Mobj.Angle;$lines=$world.Map.Lines
        $originalFlags=[int[]]::new($lines.Length);for($j=0;$j -lt $lines.Length;$j++){$originalFlags[$j]=[int]$lines[$j].Flags}
        foreach($degrees in 0,90,180,270){
            $player.Mobj.Angle=$angle+[Angle]::FromDegree($degrees)
            $hashes=[string[]]::new(2);$counts=[int[]]::new(2)
            foreach($which in 0,1){
                for($j=0;$j -lt $lines.Length;$j++){$lines[$j].Flags=$originalFlags[$j] -band (-bnot 256)}
                [Array]::Copy($sentinel,$screens[$which].Data,64000)
                $valid=$world.ValidCount;$sectors=@($world.Map.Sectors|ForEach-Object ValidCount)
                $renderers[$which].DiscoverMap($player)
                if($valid -ne $world.ValidCount -or ($sectors -join ',') -cne (@($world.Map.Sectors|ForEach-Object ValidCount) -join ',')){throw "E${episode}M$map heading $degrees changes renderer validity counters"}
                if(-not [Linq.Enumerable]::SequenceEqual[byte]($sentinel,$screens[$which].Data)){throw 'Discovery changes framebuffer pixels'}
                $bits=[byte[]]::new($lines.Length)
                for($j=0;$j -lt $lines.Length;$j++){
                    if(([int]$lines[$j].Flags -band (-bnot 256)) -ne ($originalFlags[$j] -band (-bnot 256))){throw 'Non-discovery line flags changed'}
                    $bits[$j]=[byte](($lines[$j].Flags -band 256) -ne 0);$counts[$which]+=$bits[$j]
                }
                $hashes[$which]=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bits))
            }
            if($hashes[0] -cne $hashes[1]){throw "E${episode}M$map heading $degrees differs"}
            if(-not [object]::ReferenceEquals($renderers[1].DiscoveryIndexedMap,$world.Map)){throw 'Cached indices belong to a different map'}
            $cases.Add(@{Episode=$episode;Map=$map;Heading=$degrees;BaselineSha256=$hashes[0];CacheSha256=$hashes[1];MappedLines=$counts[1];FramebufferUnchanged=$true;CountersUnchanged=$true;OtherFlagsUnchanged=$true})
        }
        $maps++;"Compared E${episode}M$map"
    }}
    if($maps -ne 36 -or $cases.Count -ne 144 -or $renderers[1].DiscoveryCacheSetupSamples.Count -ne 36){throw 'Incomplete map/rebuild coverage'}
}catch{$failure=$_.ToString()+"`n"+$_.ScriptStackTrace}finally{
    if($content){$content.Dispose()}
    @{Error=$failure;Maps=$maps;Cases=$cases.ToArray();CacheSetupSamplesMs=if($renderers){$renderers[1].DiscoveryCacheSetupSamples.ToArray()}else{@()};
        BaselineBundleSha256=(Get-FileHash $original).Hash;ExecutedBundleSha256=(Get-FileHash $bundle).Hash;BuilderSha256=(Get-FileHash $builder).Hash;
        HarnessSha256=(Get-FileHash $PSCommandPath).Hash;WadSha256=(Get-FileHash $Wad).Hash;OwnedBundle=$bundle;
        Meaning='All 36 Ultimate Doom map spawns at four synthetic headings. Clear discovery flags independently, compare full line bitsets, preserve framebuffer, world/sector validity counters and other flags. Reuse one candidate renderer across all maps to require cache rebuilds. No campaign completion, full-renderer buffer-limit parity, or FPS claim.'}|
        ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Output
}
if($failure){throw $failure}
"PASS: $maps maps, $($cases.Count) discovery cases."
