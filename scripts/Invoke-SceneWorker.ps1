#requires -Version 7.4
param([Parameter(Mandatory)][string]$Wad,[Parameter(Mandatory)][string]$Channel,
    [int]$FirstColumn,[int]$EndColumn,[ValidateSet('TrueColor','Ansi256')][string]$ColorMode='TrueColor')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/ParallelScene.ps1"
$map=[IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting($Channel)
$view=$map.CreateViewAccessor()
$ready=[Threading.EventWaitHandle]::OpenExisting($Channel+'-ready')
$go=[Threading.EventWaitHandle]::OpenExisting($Channel+'-go')
$done=[Threading.EventWaitHandle]::OpenExisting($Channel+'-done')
$frequency=[Diagnostics.Stopwatch]::Frequency
try {
    $scene=& "$PSScriptRoot/Measure-DoomScene.ps1" -Wad $Wad -InitializeOnly
    if($ColorMode -eq 'Ansi256'){$scene.Context=New-Ansi256Context $scene.Palette}
    . ([scriptblock]::Create((Get-StripBspDefinition $scene.BspDefinition)))
    $buffer=[byte[]]::new(64000)
    $render=New-DoomRenderArguments $scene $buffer
    $render.startColumn=$FirstColumn;$render.endColumn=$EndColumn
    [void]$ready.Set()
    while($go.WaitOne(60000)) {
        if($view.ReadInt32(8) -eq 1){break}
        try {
            $before=[Diagnostics.Stopwatch]::GetTimestamp()
            $render.pang=$view.ReadDouble(0)
            [Array]::Clear($buffer)
            $null=Get-BspFrame @render
            $afterRender=[Diagnostics.Stopwatch]::GetTimestamp()
            if($view.ReadInt32(12) -eq 1) {
                $encoded=ConvertTo-AnsiStrip $buffer 320 200 $FirstColumn $EndColumn $scene.Context
                $view.Write(40,[int]$encoded.Length)
                $view.WriteArray(65664L,$encoded,0,$encoded.Length)
            } else { $view.WriteArray(64L,$buffer,0,$buffer.Length) }
            $afterEncode=[Diagnostics.Stopwatch]::GetTimestamp()
            $view.Write(24,[double](($afterRender-$before)*1000.0/$frequency))
            $view.Write(32,[double](($afterEncode-$afterRender)*1000.0/$frequency))
            $view.Write(48,0)
        } catch {
            $errorBytes=[Text.Encoding]::UTF8.GetBytes($_.ToString())
            $view.Write(40,[int]$errorBytes.Length);$view.WriteArray(65664L,$errorBytes,0,$errorBytes.Length);$view.Write(48,1)
        } finally {[void]$done.Set()}
    }
} catch {
    $errorBytes=[Text.Encoding]::UTF8.GetBytes($_.ToString())
    $view.Write(40,[int]$errorBytes.Length);$view.WriteArray(65664L,$errorBytes,0,$errorBytes.Length);$view.Write(48,1)
    [void]$ready.Set()
} finally {
    $view.Dispose();$map.Dispose();$ready.Dispose();$go.Dispose();$done.Dispose()
}
