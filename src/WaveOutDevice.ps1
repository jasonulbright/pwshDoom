# SPDX-License-Identifier: GPL-2.0-or-later
# Only Windows ABI declarations are compiled. Queueing and lifetime are PowerShell.
function Initialize-DoomWaveOutApi {
    if('PwshDoomAudio.WaveApi' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PwshDoomAudio {
 [StructLayout(LayoutKind.Sequential, Pack=2)]
 public struct Format { public ushort Tag, Channels; public uint Rate, BytesPerSecond; public ushort Align, Bits, Extra; }
 [StructLayout(LayoutKind.Sequential)]
 public struct Header { public IntPtr Data; public uint Length, Recorded; public UIntPtr User; public uint Flags, Loops; public IntPtr Next; public UIntPtr Reserved; }
 public static class WaveApi {
  [DllImport("winmm.dll")] public static extern uint waveOutOpen(out IntPtr handle, uint device, ref Format format, IntPtr callback, UIntPtr instance, uint flags);
  [DllImport("winmm.dll")] public static extern uint waveOutPrepareHeader(IntPtr handle, IntPtr header, uint size);
  [DllImport("winmm.dll")] public static extern uint waveOutWrite(IntPtr handle, IntPtr header, uint size);
  [DllImport("winmm.dll")] public static extern uint waveOutUnprepareHeader(IntPtr handle, IntPtr header, uint size);
  [DllImport("winmm.dll")] public static extern uint waveOutPause(IntPtr handle);
  [DllImport("winmm.dll")] public static extern uint waveOutRestart(IntPtr handle);
  [DllImport("winmm.dll")] public static extern uint waveOutReset(IntPtr handle);
  [DllImport("winmm.dll")] public static extern uint waveOutClose(IntPtr handle);
 }
}
'@
}
function Assert-DoomWaveResult([uint32]$Code,[string]$Operation){if($Code -ne 0){throw "$Operation failed with MMRESULT $Code"}}
function Open-DoomWaveOut {
    param([ValidateRange(8000,48000)][int]$Rate=44100,[ValidateRange(64,4800)][int]$BufferFrames=882,[ValidateRange(2,16)][int]$Buffers=4)
    Initialize-DoomWaveOutApi
    $state=@{Handle=[IntPtr]::Zero;Event=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset);Buffers=[Collections.Generic.List[object]]::new();Rate=$Rate;BufferFrames=$BufferFrames;HeaderSize=[Runtime.InteropServices.Marshal]::SizeOf([type][PwshDoomAudio.Header]);FlagsOffset=[int][Runtime.InteropServices.Marshal]::OffsetOf([type][PwshDoomAudio.Header],'Flags');SubmittedFrames=0L;CompletedFrames=0L;Closed=$false}
    try{
        $format=[PwshDoomAudio.Format]::new();$format.Tag=1;$format.Channels=2;$format.Rate=$Rate;$format.BytesPerSecond=$Rate*4;$format.Align=4;$format.Bits=16
        [IntPtr]$handle=[IntPtr]::Zero
        Assert-DoomWaveResult ([PwshDoomAudio.WaveApi]::waveOutOpen([ref]$handle,[uint32]::MaxValue,[ref]$format,$state.Event.SafeWaitHandle.DangerousGetHandle(),[UIntPtr]::Zero,0x50000)) 'waveOutOpen'
        $state.Handle=$handle;Assert-DoomWaveResult ([PwshDoomAudio.WaveApi]::waveOutPause($handle)) 'waveOutPause'
        for($i=0;$i -lt $Buffers;$i++){
            $slot=@{Data=[IntPtr]::Zero;Header=[IntPtr]::Zero;Prepared=$false;Queued=$false;Frames=0;Index=$i}
            $state.Buffers.Add($slot);$slot.Data=[Runtime.InteropServices.Marshal]::AllocHGlobal($BufferFrames*4);$slot.Header=[Runtime.InteropServices.Marshal]::AllocHGlobal($state.HeaderSize)
            $header=[PwshDoomAudio.Header]::new();$header.Data=$slot.Data;$header.Length=$BufferFrames*4
            [Runtime.InteropServices.Marshal]::StructureToPtr($header,$slot.Header,$false)
            Assert-DoomWaveResult ([PwshDoomAudio.WaveApi]::waveOutPrepareHeader($handle,$slot.Header,$state.HeaderSize)) 'waveOutPrepareHeader';$slot.Prepared=$true
        }
        $state.Event.Reset()|Out-Null;return $state
    }catch{try{Close-DoomWaveOut $state}catch{Write-Warning $_};throw}
}
function Update-DoomWaveOutBuffers {
    param($Device)
    foreach($slot in $Device.Buffers){
        if($slot.Queued -and ([Runtime.InteropServices.Marshal]::ReadInt32($slot.Header,$Device.FlagsOffset) -band 1)){
            $slot.Queued=$false;$Device.CompletedFrames+=$slot.Frames
        }
    }
}
function Submit-DoomWaveOut {
    param($Device,$Slot,[byte[]]$Pcm)
    if($Device.Closed -or $Slot.Queued -or $Pcm.Length -eq 0 -or $Pcm.Length%4 -or $Pcm.Length -gt $Device.BufferFrames*4){throw 'Invalid or occupied wave buffer.'}
    [Runtime.InteropServices.Marshal]::Copy($Pcm,0,$Slot.Data,$Pcm.Length)
    [Runtime.InteropServices.Marshal]::WriteInt32($Slot.Header,[IntPtr]::Size,$Pcm.Length)
    Assert-DoomWaveResult ([PwshDoomAudio.WaveApi]::waveOutWrite($Device.Handle,$Slot.Header,$Device.HeaderSize)) 'waveOutWrite'
    $Slot.Queued=$true;$Slot.Frames=$Pcm.Length/4;$Device.SubmittedFrames+=$Slot.Frames
}
function Set-DoomWaveOutPaused {
    param($Device,[bool]$Paused)
    if($Paused){Assert-DoomWaveResult ([PwshDoomAudio.WaveApi]::waveOutPause($Device.Handle)) 'waveOutPause'}
    else{Assert-DoomWaveResult ([PwshDoomAudio.WaveApi]::waveOutRestart($Device.Handle)) 'waveOutRestart'}
}
function Reset-DoomWaveOut {
    param($Device)
    Update-DoomWaveOutBuffers $Device
    $cancelled=0L;foreach($slot in $Device.Buffers){if($slot.Queued){$cancelled+=$slot.Frames}}
    Assert-DoomWaveResult ([PwshDoomAudio.WaveApi]::waveOutReset($Device.Handle)) 'waveOutReset'
    foreach($slot in $Device.Buffers){$slot.Queued=$false}
    return $cancelled
}
function Close-DoomWaveOut {
    param($Device)
    if($Device.Closed){return}
    $issues=[Collections.Generic.List[string]]::new()
    if($Device.Handle -ne [IntPtr]::Zero){
        $code=[PwshDoomAudio.WaveApi]::waveOutReset($Device.Handle)
        if($code -ne 0){throw "waveOutReset failed with MMRESULT $code; buffers retained for safe retry."}
    }
    foreach($slot in $Device.Buffers){
        if($slot.Prepared){
            $code=[PwshDoomAudio.WaveApi]::waveOutUnprepareHeader($Device.Handle,$slot.Header,$Device.HeaderSize)
            if($code -ne 0){$issues.Add("waveOutUnprepareHeader $code");continue};$slot.Prepared=$false
        }
        foreach($field in 'Header','Data'){if($slot[$field] -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::FreeHGlobal($slot[$field]);$slot[$field]=[IntPtr]::Zero}}
        $slot.Queued=$false
    }
    if($issues.Count){throw ($issues -join '; ')}
    if($Device.Handle -ne [IntPtr]::Zero){Assert-DoomWaveResult ([PwshDoomAudio.WaveApi]::waveOutClose($Device.Handle)) 'waveOutClose';$Device.Handle=[IntPtr]::Zero}
    $Device.Event.Dispose();$Device.Closed=$true
}
