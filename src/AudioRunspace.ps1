# SPDX-License-Identifier: GPL-2.0-or-later
function Start-DoomAudioRunspace {
    param([hashtable]$Clips)
    $state=@{Queue=[Collections.Concurrent.BlockingCollection[object]]::new(32);Shared=[hashtable]::Synchronized(@{Ready=$false;Stop=$false;Paused=$true;Volume=1.0;AppliedVolume=1.0;LastSequence=-1;Epoch=0;Error=$null;Finished=$false;Report=$null});PowerShell=$null;Runspace=$null;Async=$null;MaxQueue=0;Closed=$false}
    try{
        $state.Runspace=[RunspaceFactory]::CreateRunspace();$state.Runspace.Open()
        $state.PowerShell=[PowerShell]::Create();$state.PowerShell.Runspace=$state.Runspace
        $null=$state.PowerShell.AddCommand("$PSScriptRoot/../scripts/Invoke-AudioWorker.ps1").AddParameter('Queue',$state.Queue).AddParameter('Shared',$state.Shared).AddParameter('Clips',$Clips)
        $state.Async=$state.PowerShell.BeginInvoke();$watch=[Diagnostics.Stopwatch]::StartNew()
        while(-not $state.Shared.Ready){
            if($state.Async.IsCompleted -or $state.Shared.Error){throw "Audio startup failed: $($state.Shared.Error) $($state.PowerShell.Streams.Error)"}
            if($watch.Elapsed.TotalSeconds -gt 15){throw 'Audio startup timed out.'};[Threading.Thread]::Sleep(5)
        }
        return $state
    }catch{try{$null=Stop-DoomAudioRunspace $state}catch{Write-Warning $_};throw}
}
function Send-DoomAudioPacket {
    param($Audio,$Packet)
    if($Audio.Shared.Error -or $Audio.Async.IsCompleted){throw "Audio worker failed: $($Audio.Shared.Error) $($Audio.PowerShell.Streams.Error)"}
    if(-not $Audio.Queue.TryAdd($Packet)){throw 'Audio packet queue overflow (32 tics); no silent drop performed.'}
    $Audio.MaxQueue=[Math]::Max($Audio.MaxQueue,$Audio.Queue.Count)
}
function Stop-DoomAudioRunspace {
    param($Audio)
    if($Audio.Closed){return $Audio.Shared.Report}
    $Audio.Shared.Stop=$true
    if($Audio.Async){
        if(-not $Audio.Async.AsyncWaitHandle.WaitOne(3000)){$Audio.PowerShell.Stop()}
        try{$null=$Audio.PowerShell.EndInvoke($Audio.Async)}catch{if(-not $Audio.Shared.Error){$Audio.Shared.Error=$_.ToString()}}
    }
    if($Audio.PowerShell){$Audio.PowerShell.Dispose()};if($Audio.Runspace){$Audio.Runspace.Dispose()}
    $Audio.Queue.Dispose();$Audio.Closed=$true
    if($Audio.Shared.Report){$Audio.Shared.Report.MaxPacketQueue=$Audio.MaxQueue}
    return $Audio.Shared.Report
}
