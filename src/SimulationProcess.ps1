# SPDX-License-Identifier: GPL-2.0-or-later
# Command ring and double-buffered snapshots for the dedicated simulation process.
. "$PSScriptRoot/SaveSlots.ps1"
function New-DoomSimulation {
    param([string]$Wad,[int]$Skill,[int]$Episode,[int]$Map,[switch]$StopAtLevelEnd,[switch]$ReplayCheckpoints,[string]$CheckpointReplay,[string]$SaveRoot,[switch]$Sound,[ValidateRange(0,100)][int]$SoundVolume=100,[string]$MusicCatalog)
    $root=Split-Path $PSScriptRoot;$id=[guid]::NewGuid().ToString('N');$name='Local\pwshDoom-sim-'+$id
    $state=@{Assets="$root/local/session-$id.assets";Report="$root/local/simulation-$id.json";Name=$name;Process=$null}
    try {
        $state.Map=[IO.MemoryMappedFiles.MemoryMappedFile]::CreateNew($name,3145728);$state.View=$state.Map.CreateViewAccessor()
        $state.View.Write(84,1) # Audio paused until the host's active clock runs.
        $state.View.Write(88,$SoundVolume)
        $state.Ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$name+'-ready')
        $state.Go=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,$name+'-go')
        $info=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        foreach($arg in @('-NoProfile','-File',"$root/scripts/Invoke-SimulationWorker.ps1",'-Wad',$Wad,'-Skill',"$Skill",'-Episode',"$Episode",'-Map',"$Map",'-Channel',$name,'-Assets',$state.Assets,'-Report',$state.Report,'-OwnerPid',"$PID")){$info.ArgumentList.Add($arg)}
        if($StopAtLevelEnd){$info.ArgumentList.Add('-StopAtLevelEnd')}
        if($Sound){$info.ArgumentList.Add('-Sound')}
        if($MusicCatalog){$info.ArgumentList.Add('-MusicCatalog');$info.ArgumentList.Add([IO.Path]::GetFullPath($MusicCatalog))}
        if($ReplayCheckpoints){$info.ArgumentList.Add('-ReplayCheckpoints')}
        if($CheckpointReplay){$info.ArgumentList.Add('-CheckpointReplay');$info.ArgumentList.Add([IO.Path]::GetFullPath($CheckpointReplay))}
        if($SaveRoot){$info.ArgumentList.Add('-SaveRoot');$info.ArgumentList.Add([IO.Path]::GetFullPath($SaveRoot))}
        $state.Process=[Diagnostics.Process]::Start($info);$state.Stdout=$state.Process.StandardOutput.ReadToEndAsync();$state.Stderr=$state.Process.StandardError.ReadToEndAsync()
        if(-not $state.Ready.WaitOne(30000)){throw 'Simulation startup timed out.'}
        if($state.View.ReadInt32(12) -eq 3){throw "Simulation startup failed. $($state.Stderr.Result)"}
        return $state
    } catch {Close-DoomSimulation $state;throw}
}
function Test-DoomSimulationCommandWindow {
    param($Simulation,[int]$Index,[ValidateRange(1,1024)][int]$Limit=2)
    # Check before sampling input or advancing replay/automap indices. The sole
    # consumer can only free slots between this check and the producer's write.
    return ($Index-$Simulation.View.ReadInt32(20)) -lt $Limit
}
function Send-DoomSimulationCommand {
    param($Simulation,[int]$Index,[int[]]$Command,[ValidateRange(0,1023)][int]$AutomapMask=0)
    if($Index-$Simulation.View.ReadInt32(20) -ge 1024){throw 'Simulation command ring overflow.'}
    [long]$offset=4096+($Index%1024)*16
    for($i=0;$i -lt 4;$i++){$Simulation.View.Write($offset+4*$i,[int]$Command[$i])}
    $Simulation.View.Write(98304+($Index%1024)*4,[int]$AutomapMask)
    [Threading.Thread]::MemoryBarrier();$Simulation.View.Write(0,$Index+1);[void]$Simulation.Go.Set()
}
function Read-DoomSimulationSnapshot {
    param($Simulation,$Previous)
    $view=$Simulation.View;[int]$slot=$view.ReadInt32(16);[long]$base=131072+$slot*1048576
    [int]$version=$view.ReadInt32($base)
    if(($version -band 1) -ne 0 -or $version -eq 0){return $Previous}
    if($null -ne $Previous -and $Previous.Version -eq $version){return $Previous}
    [int]$length=$view.ReadInt32($base+4);[int]$tic=$view.ReadInt32($base+8)
    [int]$generation=$view.ReadInt32($base+12);[int]$state=$view.ReadInt32($base+16)
    [int]$episode=$view.ReadInt32($base+20);[int]$map=$view.ReadInt32($base+24)
    [int]$health=$view.ReadInt32($base+28);[int]$kills=$view.ReadInt32($base+32)
    [int]$screenKind=$view.ReadInt32($base+36);[int]$menuRevision=$view.ReadInt32($base+40);[int]$menuScreen=$view.ReadInt32($base+44)
    [bool]$automapVisible=$view.ReadInt32($base+48) -ne 0
    if($state -lt 0 -or $state -gt 2 -or $screenKind -lt 0 -or $screenKind -gt 3 -or ($screenKind -ne 0 -and $length -ne 64000)){throw 'Invalid session snapshot state.'}
    if($length -lt 384 -or $length%8 -ne 0 -or $length*2+64 -gt 1048576){throw 'Invalid simulation snapshot size.'}
    $oldBytes=[byte[]]::new($length);$newBytes=[byte[]]::new($length)
    [void]$view.ReadArray($base+64,$oldBytes,0,$length);[void]$view.ReadArray($base+64+$length,$newBytes,0,$length)
    [Threading.Thread]::MemoryBarrier()
    if($version -ne $view.ReadInt32($base)){return $Previous}
    if($screenKind -ne 0){return @{Version=$version;Tic=$tic;Generation=$generation;State=$state;Episode=$episode;Map=$map;Health=$health;Kills=$kills;Pixels=$newBytes;ScreenKind=$screenKind;MenuRevision=$menuRevision;MenuScreen=$menuScreen;AutomapVisible=$automapVisible}}
    $oldValues=[double[]]::new($length/8);$newValues=[double[]]::new($length/8)
    [Buffer]::BlockCopy($oldBytes,0,$oldValues,0,$length);[Buffer]::BlockCopy($newBytes,0,$newValues,0,$length)
    return @{Version=$version;Tic=$tic;Previous=$oldValues;Current=$newValues;Generation=$generation;State=$state;Episode=$episode;Map=$map;Health=$health;Kills=$kills;ScreenKind=$screenKind;MenuRevision=$menuRevision;MenuScreen=$menuScreen;AutomapVisible=$automapVisible}
}
function Close-DoomSimulation {
    param($Simulation,[switch]$DrainAudio)
    # Stop code 2 requests bounded completion of already-produced audio. Ordinary
    # quit/error cleanup retains immediate stop code 1.
    if($Simulation.ContainsKey('View')){$Simulation.View.Write(4,[int]$(if($DrainAudio){2}else{1}))}
    if($Simulation.ContainsKey('Go')){[void]$Simulation.Go.Set()}
    if($null -ne $Simulation.Process) {
        if(-not $Simulation.Process.WaitForExit($(if($DrainAudio){10000}else{5000}))){$Simulation.Process.Kill();$Simulation.Process.WaitForExit()}
        $Simulation.Process.Dispose()
    }
    foreach($key in 'Go','Ready','View','Map'){if($Simulation.ContainsKey($key)){$Simulation[$key].Dispose()}}
    if(Test-Path -LiteralPath $Simulation.Assets){Remove-Item -LiteralPath $Simulation.Assets}
}
