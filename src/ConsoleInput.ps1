# SPDX-License-Identifier: GPL-2.0-or-later
# Platform declarations only. Key state, command generation and all game algorithms
# remain PowerShell. No custom compiled method bodies.
function Initialize-DoomConsoleApi {
    if(-not ('PwshDoomPlatform.ConsoleApi' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PwshDoomPlatform {
  [StructLayout(LayoutKind.Explicit, Size=20)]
  public struct InputRecord {
    [FieldOffset(0)] public ushort EventType;
    [FieldOffset(4)] public int KeyDown;
    [FieldOffset(8)] public ushort Repeat;
    [FieldOffset(10)] public ushort VirtualKey;
    [FieldOffset(12)] public ushort ScanCode;
    [FieldOffset(14)] public char Character;
    [FieldOffset(16)] public uint ControlState;
  }
  public static class ConsoleApi {
    [DllImport("winmm.dll")] public static extern uint timeBeginPeriod(uint period);
    [DllImport("winmm.dll")] public static extern uint timeEndPeriod(uint period);
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr h, out uint mode);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr h, uint mode);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetNumberOfConsoleInputEvents(IntPtr h, out uint count);
    [DllImport("kernel32.dll", EntryPoint="ReadConsoleInputW", SetLastError=true)] public static extern bool ReadConsoleInput(IntPtr h, [Out] InputRecord[] records, uint length, out uint read);
  }
}
'@
    }
}

function Open-DoomConsoleInput {
    Initialize-DoomConsoleApi
    $handle=[PwshDoomPlatform.ConsoleApi]::GetStdHandle(-10);[uint32]$mode=0
    if(-not [PwshDoomPlatform.ConsoleApi]::GetConsoleMode($handle,[ref]$mode)){throw 'A Windows console input handle is required. Launch from Windows Terminal.'}
    $newMode=($mode -band (-bnot (1+2+4+16+64+512))) -bor 8 -bor 128
    if(-not [PwshDoomPlatform.ConsoleApi]::SetConsoleMode($handle,$newMode)){throw 'Cannot enable console key events.'}
    return @{Handle=$handle;Mode=$mode;Keys=[bool[]]::new(256);Pressed=[bool[]]::new(256);Suppressed=[bool[]]::new(256);Records=[PwshDoomPlatform.InputRecord[]]::new(128)}
}

function Read-DoomConsoleInput {
    param($State)
    [uint32]$count=0
    if(-not [PwshDoomPlatform.ConsoleApi]::GetNumberOfConsoleInputEvents($State.Handle,[ref]$count)){throw 'Console input was disconnected.'}
    while($count -gt 0) {
        [uint32]$read=0
        if(-not [PwshDoomPlatform.ConsoleApi]::ReadConsoleInput($State.Handle,$State.Records,[Math]::Min(128,$count),[ref]$read)){throw 'Console input read failed.'}
        Update-DoomInputRecords $State $State.Records $read
        $count-=$read
    }
}

function Update-DoomInputRecords {
    param($State,$Records,[int]$Count)
        for($i=0;$i -lt $Count;$i++) {
            $event=$Records[$i]
            if($event.EventType -eq 1 -and $event.VirtualKey -lt 256) {
                $key=[int]$event.VirtualKey;$down=$event.KeyDown -ne 0
                if($down -and -not $State.Keys[$key]){$State.Pressed[$key]=$true}
                $State.Keys[$key]=$down
                if(-not $down -and $State.ContainsKey('Suppressed')){$State.Suppressed[$key]=$false}
            } elseif($event.EventType -eq 16 -and $event.KeyDown -eq 0){[Array]::Clear($State.Keys);[Array]::Clear($State.Pressed);if($State.ContainsKey('Suppressed')){[Array]::Clear($State.Suppressed)}}
        }
}

function Reset-DoomInputForMenu {
    param($State)
    # Keep physical key state for repeat debouncing. Gameplay keys held through
    # a menu remain masked until release, including the Enter used to resume.
    $State.Suppressed=$State.Keys.Clone();[Array]::Clear($State.Pressed)
}

function Reset-DoomInputAfterSessionAction {
    param($State)
    # Discard taps queued while save/load/new-game work blocked navigation;
    # preserve physical held state and mask it until the key is released.
    Read-DoomConsoleInput $State
    Reset-DoomInputForMenu $State
}

function Set-DoomInputCommand {
    param($State,$Command,[switch]$AutomapVisible,[switch]$AlwaysRun,[ValidateSet(50,100,150)][int]$TurnSpeed=100)
    $keys=$State.Keys.Clone()
    foreach($key in 87,83,65,68,37,38,39,40,17,69,32,13,16){
        if($State.ContainsKey('Suppressed') -and $State.Suppressed[$key]){$keys[$key]=$false}
        elseif($State.Pressed[$key]){$keys[$key]=$true}
    }
    $Command.Clear();$run=$keys[16] -xor [bool]$AlwaysRun
    if($AutomapVisible){foreach($key in 37,38,39,40){$keys[$key]=$false}}
    $speed=if($run){50}else{25};$strafe=if($run){40}else{24};$turn=if($run){1280}else{640}
    $turn=[int]($turn*$TurnSpeed/100)
    if($keys[87] -or $keys[38]){$Command.ForwardMove+=$speed}
    if($keys[83] -or $keys[40]){$Command.ForwardMove-=$speed}
    if($keys[68]){$Command.SideMove+=$strafe};if($keys[65]){$Command.SideMove-=$strafe}
    if($keys[37]){$Command.AngleTurn+=$turn};if($keys[39]){$Command.AngleTurn-=$turn}
    if($keys[17]){$Command.Buttons=$Command.Buttons -bor 1}
    if($keys[69] -or $keys[32] -or $keys[13]){$Command.Buttons=$Command.Buttons -bor 2}
    for($key=49;$key -le 55;$key++) {if($State.Pressed[$key]){$Command.Buttons=$Command.Buttons -bor 4 -bor (($key-49) -shl 3)}}
    [Array]::Clear($State.Pressed)
}

function Get-DoomAutomapInputMask {
    param($State,[bool]$Visible)
    [int]$mask=0
    if($State.Pressed[9] -and -not $State.Suppressed[9]){$mask=1;$Visible=-not $Visible}
    $State.AutomapVisible=$Visible
    if($Visible){
        foreach($pair in @(@(70,2),@(77,4),@(67,8))){if($State.Pressed[$pair[0]] -and -not $State.Suppressed[$pair[0]]){$mask=$mask -bor $pair[1]}}
        foreach($pair in @(@(187,16),@(107,16),@(189,32),@(109,32),@(37,64),@(39,128),@(38,256),@(40,512))){
            if(($State.Keys[$pair[0]] -or $State.Pressed[$pair[0]]) -and -not $State.Suppressed[$pair[0]]){$mask=$mask -bor $pair[1]}
        }
    }
    return $mask
}

function Close-DoomConsoleInput {
    param($State)
    [void][PwshDoomPlatform.ConsoleApi]::SetConsoleMode($State.Handle,$State.Mode)
}
