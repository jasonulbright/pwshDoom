# SPDX-License-Identifier: GPL-2.0-or-later
# Windows ABI only; window selection and ownership checks remain PowerShell.
function Get-DoomTerminalWindows {
    if(-not ('PwshDoomCapture.WindowApi' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace PwshDoomCapture {
 public delegate bool WindowCallback(IntPtr window, IntPtr parameter);
 public static class WindowApi {
  [DllImport("user32.dll")] public static extern bool EnumWindows(WindowCallback callback, IntPtr parameter);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextLength(IntPtr window);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, StringBuilder text, int count);
 }
}
'@
    }
    $processes=[Collections.Generic.HashSet[uint32]]::new();foreach($p in @(Get-Process WindowsTerminal -ErrorAction SilentlyContinue)){$null=$processes.Add([uint32]$p.Id)}
    $windows=[Collections.Generic.List[object]]::new()
    $callback=[PwshDoomCapture.WindowCallback]({param([IntPtr]$window,[IntPtr]$parameter)
        [uint32]$owner=0;$null=[PwshDoomCapture.WindowApi]::GetWindowThreadProcessId($window,[ref]$owner)
        if($processes.Contains($owner) -and [PwshDoomCapture.WindowApi]::IsWindowVisible($window)){
            $length=[PwshDoomCapture.WindowApi]::GetWindowTextLength($window);$title=[Text.StringBuilder]::new($length+1)
            $null=[PwshDoomCapture.WindowApi]::GetWindowText($window,$title,$title.Capacity)
            $windows.Add([pscustomobject]@{Id=[int]$owner;MainWindowHandle=$window;MainWindowTitle=$title.ToString()})
        }
        return $true
    }.GetNewClosure())
    if(-not [PwshDoomCapture.WindowApi]::EnumWindows($callback,[IntPtr]::Zero)){throw 'Window enumeration failed.'}
    return $windows.ToArray()
}
