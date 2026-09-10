# Persistent PowerShell workers with standard .NET shared memory and events.
. "$PSScriptRoot/ParallelScene.ps1"
function Get-WorkerError {
    param($Worker)
    if($Worker.View.ReadInt32(48) -eq 1) {
        $bytes=[byte[]]::new($Worker.View.ReadInt32(40))
        [void]$Worker.View.ReadArray(65664L,$bytes,0,$bytes.Length)
        throw [Text.Encoding]::UTF8.GetString($bytes)
    }
}
function New-ProcessScene {
    param([string]$Wad,[ValidateRange(1,20)][int]$Workers,[ValidateSet('TrueColor','Ansi256')][string]$ColorMode='TrueColor')
    $states=[Collections.Generic.List[object]]::new()
    $pool=@{Workers=$states;Buffer=[byte[]]::new(64000)}
    try {
        for($i=0;$i -lt $Workers;$i++) {
            $name='Local\pwshDoom-'+[guid]::NewGuid().ToString('N')
            $map=[IO.MemoryMappedFiles.MemoryMappedFile]::CreateNew($name,2097152)
            $view=$map.CreateViewAccessor()
            $ready=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$name+'-ready')
            $go=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,$name+'-go')
            $done=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset,$name+'-done')
            $start=[int][Math]::Floor($i*320.0/$Workers);$end=[int][Math]::Floor(($i+1)*320.0/$Workers)
            $info=[Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
            $info.UseShellExecute=$false;$info.CreateNoWindow=$true
            $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
            foreach($arg in @('-NoProfile','-File',"$PSScriptRoot/Invoke-SceneWorker.ps1",'-Wad',$Wad,'-Channel',$name,'-FirstColumn',"$start",'-EndColumn',"$end",'-ColorMode',$ColorMode)){
                $info.ArgumentList.Add($arg)
            }
            $process=[Diagnostics.Process]::Start($info)
            $states.Add(@{Map=$map;View=$view;Ready=$ready;Go=$go;Done=$done;Process=$process;
                FirstColumn=$start;EndColumn=$end;Bytes=$null})
        }
        foreach($state in $states){
            if(-not $state.Ready.WaitOne(30000)){throw 'Process worker startup timed out.'}
            Get-WorkerError $state
        }
        return $pool
    } catch {Close-ProcessScene $pool;throw}
}
function Invoke-ProcessScene {
    param($Pool,[double]$Angle,[bool]$Encode=$true)
    foreach($worker in $Pool.Workers){
        $worker.View.Write(0,$Angle);$worker.View.Write(12,[int]$Encode);[void]$worker.Go.Set()
    }
    foreach($worker in $Pool.Workers){
        if(-not $worker.Done.WaitOne(30000)){throw 'Process worker frame timed out.'}
        Get-WorkerError $worker
        if($Encode){
            $worker.Bytes=[byte[]]::new($worker.View.ReadInt32(40))
            [void]$worker.View.ReadArray(65664L,$worker.Bytes,0,$worker.Bytes.Length)
        } else {
            $pixels=[byte[]]::new(64000)
            [void]$worker.View.ReadArray(64L,$pixels,0,64000)
            for($y=0;$y -lt 200;$y++){
                $offset=$y*320+$worker.FirstColumn
                [Buffer]::BlockCopy($pixels,$offset,$Pool.Buffer,$offset,$worker.EndColumn-$worker.FirstColumn)
            }
        }
    }
}
function Close-ProcessScene {
    param($Pool)
    foreach($worker in $Pool.Workers){$worker.View.Write(8,1);[void]$worker.Go.Set()}
    foreach($worker in $Pool.Workers){
        if(-not $worker.Process.WaitForExit(5000)){$worker.Process.Kill()}
        $worker.Process.Dispose();$worker.View.Dispose();$worker.Map.Dispose();$worker.Go.Dispose();$worker.Done.Dispose();$worker.Ready.Dispose()
    }
}
