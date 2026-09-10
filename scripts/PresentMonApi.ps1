# SPDX-License-Identifier: GPL-2.0-or-later
# Optional measurement adapter, never loaded by the game.
# ABI declarations follow the user's installed Intel PresentMon SDK header.
# https://github.com/GameTechDev/PresentMon/blob/v2.5.1/README-Service.md
function Initialize-PresentMonApi {
    param([string]$DllPath='C:\Program Files\Intel\PresentMonSharedService\PresentMonAPI2.dll')
    if('PwshDoomMeasurement.PresentMonApi' -as [type]){return}
    $DllPath=(Resolve-Path -LiteralPath $DllPath).Path
    $literal=$DllPath.Replace('\','\\').Replace('"','\"')
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace PwshDoomMeasurement {
  [StructLayout(LayoutKind.Sequential)]
  public struct QueryElement {
    public int Metric; public int Stat; public uint DeviceId; public uint ArrayIndex;
    public ulong DataOffset; public ulong DataSize;
  }
  public static class PresentMonApi {
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmOpenSession(out IntPtr session);
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmCloseSession(IntPtr session);
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmGetApiVersion(IntPtr version);
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmStartTrackingProcess(IntPtr session, uint processId);
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmStopTrackingProcess(IntPtr session, uint processId);
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmGetIntrospectionRoot(IntPtr session, out IntPtr root);
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmFreeIntrospectionRoot(IntPtr root);
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmRegisterFrameQuery(IntPtr session, out IntPtr query, [In, Out] QueryElement[] elements, ulong count, out uint blobSize);
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmConsumeFrames(IntPtr query, uint processId, [Out] byte[] blobs, ref uint count);
    [DllImport("$literal", CallingConvention=CallingConvention.Cdecl)] public static extern int pmFreeFrameQuery(IntPtr query);
  }
}
"@
}
function Assert-PresentMonStatus([int]$Status,[string]$Operation) {
    if($Status -ne 0){throw "PresentMon $Operation failed with PM_STATUS $Status."}
}
function Get-PresentMonMetricMetadata {
    param([IntPtr]$Session,[string]$HeaderPath='C:\Program Files\Intel\PresentMon\SDK\PresentMonAPI.h')
    if([IntPtr]::Size -ne 8){throw 'This measurement adapter requires a 64-bit process.'}
    $header=Get-Content -LiteralPath $HeaderPath -Raw
    $block=[regex]::Match($header,'enum PM_METRIC\s*\{([^}]+)\}').Groups[1].Value
    $names=@([regex]::Matches($block,'\bPM_METRIC_[A-Z0-9_]+\b') | ForEach-Object {$_.Value})
    $root=[IntPtr]::Zero
    try {
        Assert-PresentMonStatus ([PwshDoomMeasurement.PresentMonApi]::pmGetIntrospectionRoot($Session,[ref]$root)) 'introspection'
        # Layouts from the installed header: root->metrics, object pointer array,
        # metric record (four int32s, then three pointers), and type-info record.
        $array=[Runtime.InteropServices.Marshal]::ReadIntPtr($root,0)
        $data=[Runtime.InteropServices.Marshal]::ReadIntPtr($array,0)
        $count=[Runtime.InteropServices.Marshal]::ReadInt64($array,8)
        if($count -lt 1 -or $count -gt 4096){throw 'Unexpected metric metadata count.'}
        $result=@{}
        for($i=0;$i -lt $count;$i++) {
            $metric=[Runtime.InteropServices.Marshal]::ReadIntPtr($data,$i*8)
            $id=[Runtime.InteropServices.Marshal]::ReadInt32($metric,0)
            if($id -lt 0 -or $id -ge $names.Count){throw 'SDK/service metric IDs differ.'}
            $typeInfo=[Runtime.InteropServices.Marshal]::ReadIntPtr($metric,16)
            $result[$names[$id]]=@{Id=$id;MetricType=[Runtime.InteropServices.Marshal]::ReadInt32($metric,4);
                Unit=[Runtime.InteropServices.Marshal]::ReadInt32($metric,8);FrameType=[Runtime.InteropServices.Marshal]::ReadInt32($typeInfo,4)}
        }
        return $result
    } finally {if($root -ne [IntPtr]::Zero){$null=[PwshDoomMeasurement.PresentMonApi]::pmFreeIntrospectionRoot($root)}}
}
function Read-PresentMonField([byte[]]$Bytes,[int]$Offset,[int]$Type) {
    switch($Type) {
        0 {[BitConverter]::ToDouble($Bytes,$Offset)}
        1 {[BitConverter]::ToInt32($Bytes,$Offset)}
        2 {[BitConverter]::ToUInt32($Bytes,$Offset)}
        3 {[BitConverter]::ToInt32($Bytes,$Offset)}
        5 {[BitConverter]::ToUInt64($Bytes,$Offset)}
        6 {[BitConverter]::ToBoolean($Bytes,$Offset)}
        default {throw "Unsupported PresentMon field type: $Type"}
    }
}
