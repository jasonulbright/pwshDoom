# SPDX-License-Identifier: GPL-2.0-or-later
# Load after engine definitions. Commands contain no engine objects.
class DoomMusicEvents : IMusic {
    [Collections.Generic.List[object]]$Events=[Collections.Generic.List[object]]::new()
    [int]$StoredVolume=15
    [void] StartMusic([Bgm]$bgm,[bool]$loop){
        if($bgm -eq [Bgm]::NONE){$this.Events.Add(@{Kind='Stop'});return}
        $track='D_'+[DoomInfo]::BgmNames[[int]$bgm].ToString().ToUpperInvariant()
        $this.Events.Add(@{Kind='Start';Track=$track;Loop=$loop})
    }
    [int] get_MaxVolume(){return 15}
    [int] get_Volume(){return $this.StoredVolume}
    [void] set_Volume([int]$value){$this.StoredVolume=[Math]::Clamp($value,0,15);$this.Events.Add(@{Kind='Gain';Value=.2*($this.StoredVolume/15.0)})}
    [object[]] Drain(){[object[]]$result=$this.Events.ToArray();$this.Events.Clear();return $result}
}
function Sync-DoomMusicSession {
    param([DoomMusicEvents]$Events,$Game)
    $Events.Events.Clear()
    if($Game.State -eq [GameState]::Level){$Events.StartMusic([Map]::GetMapBgm($Game.Options),$true)}
    elseif($Game.State -eq [GameState]::Intermission){$bgm=if($Game.Options.GameMode -eq [GameMode]::Commercial){[Bgm]::DM2INT}else{[Bgm]::INTER};$Events.StartMusic($bgm,$true)}
    elseif($Game.State -eq [GameState]::Finale){
        if($Game.Options.GameMode -eq [GameMode]::Commercial){throw 'Doom II finale music restoration is not qualified yet.'}
        $bgm=if($Game.Options.Episode -eq 3 -and $Game.Finale.stage -ge 1){[Bgm]::BUNNY}else{[Bgm]::VICTOR};$Events.StartMusic($bgm,$true)
    }else{throw 'Unknown music session state.'}
}
function Read-DoomMusicCatalog {
    param([string]$Path,$Content)
    $path=[IO.Path]::GetFullPath($Path)
    if(([IO.FileInfo]::new($path)).Length -gt 1MB){throw 'Music catalog exceeds size bound.'}
    $catalog=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable
    if($catalog -isnot [hashtable] -or $catalog.Count -eq 0 -or $catalog.Count -gt 128){throw 'Invalid music catalog.'}
    $reports=@{}
    foreach($track in $catalog.Keys){
        if($track -cnotmatch '^D_[A-Z0-9]+$' -or $catalog[$track] -isnot [string]){throw 'Invalid music catalog entry.'}
        $report=[IO.Path]::GetFullPath($catalog[$track],[IO.Path]::GetDirectoryName($path))
        $r=Get-Content $report -Raw|ConvertFrom-Json;$lump=$Content.Wad.GetLumpNumber($track)
        if($lump -lt 0 -or $r.Details.Track -cne $track -or [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Content.Wad.ReadLump($lump))) -cne $r.Details.MusSha256){throw 'Qualified music does not match the active WAD score.'}
        $reports[$track]=$report
    }
    return $reports
}
