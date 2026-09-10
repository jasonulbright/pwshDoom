#requires -Version 7.4
# SPDX-License-Identifier: GPL-2.0-or-later
param([string]$Wad='C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\DOOM.WAD')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath("$PSScriptRoot/..");$runtime=(Get-Process -Id $PID).Path
$checks=[Collections.Generic.List[object]]::new()
foreach($mode in 'Normal','OwnerKilled') {
    $id=[guid]::NewGuid().ToString('N');$ready="$root/local/lifecycle-$id-ready.json";$report="$root/local/lifecycle-$id-session.json"
    $hostProcess=$null;$owned=[Collections.Generic.List[Diagnostics.Process]]::new();$state=$null
    try {
        $info=[Diagnostics.ProcessStartInfo]::new($runtime);$info.UseShellExecute=$false;$info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
        $seconds=if($mode -eq 'Normal'){2}else{60}
        foreach($arg in @('-NoProfile','-File',"$root/scripts/Invoke-Doom.ps1",'-Wad',$Wad,'-Workers','2','-Headless','-Scripted','-Seconds',"$seconds",'-ReadyFile',$ready,'-Report',$report)){$info.ArgumentList.Add($arg)}
        $hostProcess=[Diagnostics.Process]::Start($info);$stdout=$hostProcess.StandardOutput.ReadToEndAsync();$stderr=$hostProcess.StandardError.ReadToEndAsync()
        $watch=[Diagnostics.Stopwatch]::StartNew()
        while(-not (Test-Path -LiteralPath $ready)) {
            if($hostProcess.HasExited){throw "Host exited before readiness: $($stderr.Result)"}
            if($watch.Elapsed.TotalSeconds -gt 40){throw 'Lifecycle startup timed out.'}
            [Threading.Thread]::Sleep(100)
        }
        $state=Get-Content -LiteralPath $ready -Raw | ConvertFrom-Json
        if($state.HostPid -ne $hostProcess.Id){throw 'Readiness PID mismatch.'}
        foreach($childId in @($state.SimulationPid)+@($state.WorkerPids)){$owned.Add([Diagnostics.Process]::GetProcessById($childId))}
        if(-not (Test-Path -LiteralPath $state.Assets)){throw 'Owned asset cache is missing during the session.'}
        $watch.Restart()
        if($mode -eq 'OwnerKilled'){$hostProcess.Kill()}
        if(-not $hostProcess.WaitForExit(10000)){throw 'Host failed to exit.'}
        if($mode -eq 'Normal' -and $hostProcess.ExitCode -ne 0){throw "Normal host failed: $($stderr.Result)"}
        foreach($child in $owned){if(-not $child.WaitForExit(5000)){throw "Owned child $($child.Id) remained alive."}}
        if(Test-Path -LiteralPath $state.Assets){throw 'Owned asset cache remained after children exited.'}
        if($mode -eq 'Normal') {
            $session=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
            if($session.ExitReason -ne 'Duration' -or $session.Error){throw 'Normal session did not finish cleanly.'}
        }
        $checks.Add(@{Mode=$mode;OwnedChildren=$owned.Count;AllExited=$true;AssetCacheRemoved=$true;WaitSeconds=$watch.Elapsed.TotalSeconds})
    } finally {
        if($null -ne $hostProcess){if(-not $hostProcess.HasExited){$hostProcess.Kill($true);$hostProcess.WaitForExit()};$hostProcess.Dispose()}
        foreach($child in $owned){if(-not $child.HasExited){$child.Kill();$child.WaitForExit()};$child.Dispose()}
        if($null -ne $state) {
            $assetPath=[IO.Path]::GetFullPath($state.Assets)
            if($assetPath.StartsWith("$root\local\",[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($assetPath) -match '^session-[a-f0-9]{32}\.assets$' -and (Test-Path -LiteralPath $assetPath)){Remove-Item -LiteralPath $assetPath}
        }
    }
}
@{FinishedUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks.ToArray();Meaning='Two owned headless sessions: finite normal exit and abrupt coordinator termination. Only test-created processes are terminated. This does not test terminal keyboard/visual restoration.'} |
    ConvertTo-Json -Depth 5 | Set-Content "$root/results/game-lifecycle.json"
'PASS: normal and abrupt-owner cleanup, including all children and asset caches.'
