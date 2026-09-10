# SPDX-License-Identifier: GPL-2.0-or-later
# Command ring and double-buffered snapshots for the dedicated simulation process.
function New-DoomSimulation {
    param([string]$Wad,[int]$Skill,[int]$Episode,[int]$Map)
    $root=Split-Path $PSScriptRoot;$id=[guid]::NewGuid().ToString('N');$name='Local\pwshDoom-sim-'+$id
    $state=@{Assets="$root/local/session-$id.assets";Report="$root/local/simulation-$id.json";Name=$name;Process=$null}
    try {
        $state.Map=[IO.MemoryMappedFiles.MemoryMappedFile]::CreateNew($name,3145728);$state.View=$state.Map.CreateViewAccessor()
        $state.Ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$name+'-ready')
        $state.Go=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,$name+'-go')
        $info=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        foreach($arg in @('-NoProfile','-File',"$root/scripts/Invoke-SimulationWorker.ps1",'-Wad',$Wad,'-Skill',"$Skill",'-Episode',"$Episode",'-Map',"$Map",'-Channel',$name,'-Assets',$state.Assets,'-Report',$state.Report,'-OwnerPid',"$PID")){$info.ArgumentList.Add($arg)}
        $state.Process=[Diagnostics.Process]::Start($info);$state.Stdout=$state.Process.StandardOutput.ReadToEndAsync();$state.Stderr=$state.Process.StandardError.ReadToEndAsync()
        if(-not $state.Ready.WaitOne(30000)){throw 'Simulation startup timed out.'}
        if($state.View.ReadInt32(12) -eq 3){throw "Simulation startup failed. $($state.Stderr.Result)"}
        return $state
    } catch {Close-DoomSimulation $state;throw}
}
function Send-DoomSimulationCommand {
    param($Simulation,[int]$Index,[int[]]$Command)
    if($Index-$Simulation.View.ReadInt32(20) -ge 1024){throw 'Simulation command ring overflow.'}
    [long]$offset=4096+($Index%1024)*16
    for($i=0;$i -lt 4;$i++){$Simulation.View.Write($offset+4*$i,[int]$Command[$i])}
    [Threading.Thread]::MemoryBarrier();$Simulation.View.Write(0,$Index+1);[void]$Simulation.Go.Set()
}
function Read-DoomSimulationSnapshot {
    param($Simulation,$Previous)
    $view=$Simulation.View;[int]$slot=$view.ReadInt32(16);[long]$base=131072+$slot*1048576
    [int]$version=$view.ReadInt32($base)
    if(($version -band 1) -ne 0 -or $version -eq 0){return $Previous}
    if($null -ne $Previous -and $Previous.Version -eq $version){return $Previous}
    [int]$length=$view.ReadInt32($base+4);[int]$tic=$view.ReadInt32($base+8)
    if($length -lt 384 -or $length%8 -ne 0 -or $length*2+64 -gt 1048576){throw 'Invalid simulation snapshot size.'}
    $oldBytes=[byte[]]::new($length);$newBytes=[byte[]]::new($length)
    [void]$view.ReadArray($base+64,$oldBytes,0,$length);[void]$view.ReadArray($base+64+$length,$newBytes,0,$length)
    [Threading.Thread]::MemoryBarrier()
    if($version -ne $view.ReadInt32($base)){return $Previous}
    $oldValues=[double[]]::new($length/8);$newValues=[double[]]::new($length/8)
    [Buffer]::BlockCopy($oldBytes,0,$oldValues,0,$length);[Buffer]::BlockCopy($newBytes,0,$newValues,0,$length)
    return @{Version=$version;Tic=$tic;Previous=$oldValues;Current=$newValues}
}
function Close-DoomSimulation {
    param($Simulation)
    if($Simulation.ContainsKey('View')){$Simulation.View.Write(4,1)}
    if($Simulation.ContainsKey('Go')){[void]$Simulation.Go.Set()}
    if($null -ne $Simulation.Process) {
        if(-not $Simulation.Process.WaitForExit(5000)){$Simulation.Process.Kill();$Simulation.Process.WaitForExit()}
        $Simulation.Process.Dispose()
    }
    foreach($key in 'Go','Ready','View','Map'){if($Simulation.ContainsKey($key)){$Simulation[$key].Dispose()}}
    if(Test-Path -LiteralPath $Simulation.Assets){Remove-Item -LiteralPath $Simulation.Assets}
}
