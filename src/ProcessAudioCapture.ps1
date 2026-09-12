# SPDX-License-Identifier: GPL-2.0-or-later
# Recording instrumentation only. Compiled code is COM ABI forwarding and the
# cross-thread activation callback; packet processing and file output are PowerShell.
function Initialize-DoomProcessCaptureApi {
    if('PwshDoomCapture.Api' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Threading;
namespace PwshDoomCapture {
 [StructLayout(LayoutKind.Sequential, Pack=2)]
 public struct Format { public ushort Tag, Channels; public uint Rate, BytesPerSecond; public ushort Align, Bits, Extra; }
 [ComImport, Guid("72A22D78-CDE4-431D-B8CC-843A71199B6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 public interface IOperation { [PreserveSig] int GetActivateResult(out int result, out IntPtr instance); }
 [Guid("41D949AB-9862-444A-80F6-C261334DA5EB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown), ComVisible(true)]
 public interface ICompletion { [PreserveSig] int ActivateCompleted(IOperation operation); }
 [Guid("94EA2B94-E9CC-49E0-C0FF-EE64CA8F5B90"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown), ComVisible(true)]
 public interface IAgileObject { }
 [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
 public sealed class Completion : ICompletion, IAgileObject {
  public readonly ManualResetEventSlim Done = new ManualResetEventSlim(false);
  public int Result = unchecked((int)0x80004005); public IntPtr Instance;
  public int ActivateCompleted(IOperation operation) {
   try { int hr = operation.GetActivateResult(out Result, out Instance); if(hr < 0) Result = hr; }
   catch(Exception e) { Result = Marshal.GetHRForException(e); }
   finally { Done.Set(); }
   return 0;
  }
 }
 [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 public interface IClient {
  [PreserveSig] int Initialize(int mode, uint flags, long duration, long periodicity, ref Format format, IntPtr session);
  [PreserveSig] int GetBufferSize(out uint frames);
  [PreserveSig] int GetStreamLatency(out long latency);
  [PreserveSig] int GetCurrentPadding(out uint frames);
  [PreserveSig] int IsFormatSupported(int mode, IntPtr format, out IntPtr closest);
  [PreserveSig] int GetMixFormat(out IntPtr format);
  [PreserveSig] int GetDevicePeriod(out long normal, out long minimum);
  [PreserveSig] int Start();
  [PreserveSig] int Stop();
  [PreserveSig] int Reset();
  [PreserveSig] int SetEventHandle(IntPtr handle);
  [PreserveSig] int GetService(ref Guid iid, out IntPtr instance);
 }
 [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
 public interface ICapture {
  [PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong device, out ulong qpc);
  [PreserveSig] int ReleaseBuffer(uint frames);
  [PreserveSig] int GetNextPacketSize(out uint frames);
 }
 // Typed forwarding is needed because these COM interfaces have no IDispatch.
 public sealed class Client : IDisposable {
  private IClient value;
  public Client(IntPtr ptr) { value = (IClient)Marshal.GetObjectForIUnknown(ptr); }
  public int Initialize(ref Format format) { return value.Initialize(0, 0x80060000, 0, 0, ref format, IntPtr.Zero); }
  public int GetBufferSize(out uint frames) { return value.GetBufferSize(out frames); }
  public int SetEventHandle(IntPtr handle) { return value.SetEventHandle(handle); }
  public int GetService(ref Guid iid, out IntPtr ptr) { return value.GetService(ref iid, out ptr); }
  public int Start() { return value.Start(); }
  public int Stop() { return value.Stop(); }
  public void Dispose() { if(value != null) { Marshal.ReleaseComObject(value); value = null; } }
 }
 public sealed class Capture : IDisposable {
  private ICapture value;
  public Capture(IntPtr ptr) { value = (ICapture)Marshal.GetObjectForIUnknown(ptr); }
  public int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong device, out ulong qpc) { return value.GetBuffer(out data, out frames, out flags, out device, out qpc); }
  public int ReleaseBuffer(uint frames) { return value.ReleaseBuffer(frames); }
  public int GetNextPacketSize(out uint frames) { return value.GetNextPacketSize(out frames); }
  public void Dispose() { if(value != null) { Marshal.ReleaseComObject(value); value = null; } }
 }
 public static class Api {
  [DllImport("Mmdevapi.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
  public static extern int ActivateAudioInterfaceAsync(string path, ref Guid iid, IntPtr parameters, ICompletion callback, out IOperation operation);
 }
}
'@
}
function Assert-DoomCaptureResult([int]$Code,[string]$Operation){
    if($Code -lt 0){throw "$Operation failed: 0x$($Code.ToString('X8')). $([Runtime.InteropServices.Marshal]::GetExceptionForHR($Code).Message)"}
}
function Open-DoomProcessCapture {
    param([ValidateRange(1,2147483647)][int]$TargetProcessId)
    if(-not $IsWindows -or -not [Environment]::Is64BitProcess){throw 'Process capture currently requires 64-bit PowerShell on Windows.'}
    Initialize-DoomProcessCaptureApi
    $target=Get-Process -Id $TargetProcessId -ErrorAction Stop
    $state=@{TargetProcessId=$TargetProcessId;TargetStartUtc=$target.StartTime.ToUniversalTime().ToString('o');Client=$null;Capture=$null;Event=$null;Started=$false;Closed=$false;Frames=0L;Packets=0L;Rate=44100;BufferFrames=0;StartQpc=0L}
    $blob=[Runtime.InteropServices.Marshal]::AllocHGlobal(12);$variant=[Runtime.InteropServices.Marshal]::AllocHGlobal(24)
    $callback=[PwshDoomCapture.Completion]::new();$operation=$null;$activationPending=$false
    try{
        # AUDIOCLIENT_ACTIVATION_PARAMS: PROCESS_LOOPBACK, PID, INCLUDE_TREE.
        [Runtime.InteropServices.Marshal]::WriteInt32($blob,0,1)
        [Runtime.InteropServices.Marshal]::WriteInt32($blob,4,$TargetProcessId)
        [Runtime.InteropServices.Marshal]::WriteInt32($blob,8,0)
        [Runtime.InteropServices.Marshal]::Copy([byte[]]::new(24),0,$variant,24)
        [Runtime.InteropServices.Marshal]::WriteInt16($variant,0,65) # VT_BLOB
        [Runtime.InteropServices.Marshal]::WriteInt32($variant,8,12)
        [Runtime.InteropServices.Marshal]::WriteIntPtr($variant,16,$blob)
        [guid]$iid='1CB9AD4C-DBFA-4c32-B178-C2F568A703B2'
        Assert-DoomCaptureResult ([PwshDoomCapture.Api]::ActivateAudioInterfaceAsync('VAD\Process_Loopback',[ref]$iid,$variant,$callback,[ref]$operation)) 'ActivateAudioInterfaceAsync'
        $activationPending=$true
        if(-not $callback.Done.Wait(10000)){throw 'Process capture activation timed out; pending callback storage is retained until this process exits.'}
        $activationPending=$false
        Assert-DoomCaptureResult $callback.Result 'Process loopback activation'
        $state.Client=[PwshDoomCapture.Client]::new($callback.Instance)
        $format=[PwshDoomCapture.Format]::new();$format.Tag=1;$format.Channels=2;$format.Rate=44100;$format.BytesPerSecond=176400;$format.Align=4;$format.Bits=16
        Assert-DoomCaptureResult ($state.Client.Initialize([ref]$format)) 'IAudioClient.Initialize'
        [uint32]$frames=0;Assert-DoomCaptureResult ($state.Client.GetBufferSize([ref]$frames)) 'GetBufferSize';$state.BufferFrames=$frames
        [guid]$captureId='C8ADBD64-E71E-48a0-A4DE-185C395CD317';[IntPtr]$ptr=[IntPtr]::Zero
        Assert-DoomCaptureResult ($state.Client.GetService([ref]$captureId,[ref]$ptr)) 'GetService'
        try{$state.Capture=[PwshDoomCapture.Capture]::new($ptr)}finally{if($ptr -ne [IntPtr]::Zero){$null=[Runtime.InteropServices.Marshal]::Release($ptr)}}
        $state.Event=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::AutoReset)
        Assert-DoomCaptureResult ($state.Client.SetEventHandle($state.Event.SafeWaitHandle.DangerousGetHandle())) 'SetEventHandle'
        $state.StartQpc=[Diagnostics.Stopwatch]::GetTimestamp()
        Assert-DoomCaptureResult ($state.Client.Start()) 'IAudioClient.Start';$state.Started=$true
        return $state
    }catch{Close-DoomProcessCapture $state;throw}finally{
        if($activationPending){
            # Never dispose an event/native argument while Windows may still use it.
            if(-not (Get-Variable DoomPendingCaptureActivations -Scope Script -ErrorAction SilentlyContinue)){$script:DoomPendingCaptureActivations=[Collections.Generic.List[object]]::new()}
            $script:DoomPendingCaptureActivations.Add(@{Callback=$callback;Operation=$operation;Blob=$blob;Variant=$variant})
        }else{
            if($callback.Instance -ne [IntPtr]::Zero){$null=[Runtime.InteropServices.Marshal]::Release($callback.Instance)}
            if($operation){$null=[Runtime.InteropServices.Marshal]::ReleaseComObject($operation)}
            $callback.Done.Dispose();[Runtime.InteropServices.Marshal]::FreeHGlobal($blob);[Runtime.InteropServices.Marshal]::FreeHGlobal($variant)
        }
    }
}
function Read-DoomProcessCapture {
    param($State)
    if($State.Closed){throw 'Capture is closed.'}
    [uint32]$available=0;Assert-DoomCaptureResult ($State.Capture.GetNextPacketSize([ref]$available)) 'GetNextPacketSize'
    if(-not $available){return $null}
    [IntPtr]$data=[IntPtr]::Zero;[uint32]$frames=0;[uint32]$flags=0;[uint64]$device=0;[uint64]$qpc=0
    Assert-DoomCaptureResult ($State.Capture.GetBuffer([ref]$data,[ref]$frames,[ref]$flags,[ref]$device,[ref]$qpc)) 'GetBuffer'
    if(-not $frames){return $null}
    try{
        if($frames -gt $State.BufferFrames){throw 'Capture packet exceeds the negotiated buffer.'}
        $bytes=[byte[]]::new($frames*4)
        if(-not ($flags -band 2)){[Runtime.InteropServices.Marshal]::Copy($data,$bytes,0,$bytes.Length)}
    }finally{Assert-DoomCaptureResult ($State.Capture.ReleaseBuffer($frames)) 'ReleaseBuffer'}
    $packet=@{Index=$State.Packets;OutputFrame=$State.Frames;Frames=$frames;Flags=$flags;DevicePosition=$device;Qpc100ns=$qpc;ObservedQpc=[Diagnostics.Stopwatch]::GetTimestamp();Bytes=$bytes}
    $State.Frames+=$frames;$State.Packets++
    return $packet
}
function Close-DoomProcessCapture {
    param($State)
    if($State.Closed){return}
    try{if($State.Started){Assert-DoomCaptureResult ($State.Client.Stop()) 'IAudioClient.Stop'}}finally{
        if($State.Capture){$State.Capture.Dispose()};if($State.Client){$State.Client.Dispose()};if($State.Event){$State.Event.Dispose()}
        $State.Started=$false;$State.Closed=$true
    }
}
