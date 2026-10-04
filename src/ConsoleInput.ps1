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
    return @{Handle=$handle;Mode=$mode;Keys=[bool[]]::new(256);Pressed=[bool[]]::new(256);PressedOrder=[Collections.Generic.List[int]]::new();Suppressed=[bool[]]::new(256);Records=[PwshDoomPlatform.InputRecord[]]::new(128)}
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
                if($down -and -not $State.Keys[$key]){
                    if(-not $State.Pressed[$key]){$State.Pressed[$key]=$true}
                    if($State.ContainsKey('PressedOrder') -and $key -gt 0){[void]$State.PressedOrder.Add($key)}
                }
                $State.Keys[$key]=$down
                if(-not $down -and $State.ContainsKey('Suppressed')){$State.Suppressed[$key]=$false}
            } elseif($event.EventType -eq 16 -and $event.KeyDown -eq 0){[Array]::Clear($State.Keys);[Array]::Clear($State.Pressed);if($State.ContainsKey('PressedOrder')){$State.PressedOrder.Clear()};if($State.ContainsKey('Suppressed')){[Array]::Clear($State.Suppressed)}}
        }
}

function Get-DoomPressedKeysInOrder {
    param($State)
    $ordered=[Collections.Generic.List[int]]::new()
    if($State.ContainsKey('PressedOrder')){
        foreach($key in $State.PressedOrder){if($key -gt 0 -and $key -lt $State.Pressed.Length -and $State.Pressed[$key]){$ordered.Add([int]$key)}}
    }else{
        for($key=1;$key -lt $State.Pressed.Length;$key++){if($State.Pressed[$key]){$ordered.Add($key)}}
    }
    return ,$ordered.ToArray()
}

function Remove-DoomInputPress {
    param($State,[int]$VirtualKey)
    if($State.ContainsKey('PressedOrder')){
        [void]$State.PressedOrder.Remove($VirtualKey)
        if($VirtualKey -gt 0 -and $VirtualKey -lt $State.Pressed.Length){$State.Pressed[$VirtualKey]=$State.PressedOrder.Contains($VirtualKey)}
    }elseif($VirtualKey -gt 0 -and $VirtualKey -lt $State.Pressed.Length){$State.Pressed[$VirtualKey]=$false}
}

function Reset-DoomInputForMenu {
    param($State,[switch]$PreservePending)
    # Keep physical key state for repeat debouncing. Gameplay keys held through
    # a menu remain masked until release, including the Enter used to resume.
    $State.Suppressed=$State.Keys.Clone()
    if(-not $PreservePending){[Array]::Clear($State.Pressed);if($State.ContainsKey('PressedOrder')){$State.PressedOrder.Clear()}}
}

function Reset-DoomInputAfterSessionAction {
    param($State)
    # Discard taps queued while save/load/new-game work blocked navigation;
    # preserve physical held state and mask it until the key is released.
    Read-DoomConsoleInput $State
    Reset-DoomInputForMenu $State
}

function Set-DoomInputCommand {
    param($State,$Command,[switch]$AutomapVisible,[switch]$AlwaysRun,[ValidateSet(50,100,150)][int]$TurnSpeed=100,$Bindings)
    $keys=$State.Keys.Clone()
    if($null -eq $Bindings){$Bindings=@{Forward=87;Backward=83;StrafeLeft=65;StrafeRight=68;TurnLeft=37;TurnRight=39;Fire=17;Use=69;Run=16}}
    foreach($key in @([int]$Bindings.Forward,[int]$Bindings.Backward,[int]$Bindings.StrafeLeft,[int]$Bindings.StrafeRight,[int]$Bindings.TurnLeft,[int]$Bindings.TurnRight,[int]$Bindings.Fire,[int]$Bindings.Use,[int]$Bindings.Run,38,40,32,13,16)){
        if($State.ContainsKey('Suppressed') -and $State.Suppressed[$key]){$keys[$key]=$false}
        elseif($State.Pressed[$key]){$keys[$key]=$true}
    }
    $shiftRunAlias=([int]$Bindings.Forward -ne 16 -and [int]$Bindings.Backward -ne 16 -and [int]$Bindings.StrafeLeft -ne 16 -and [int]$Bindings.StrafeRight -ne 16 -and [int]$Bindings.TurnLeft -ne 16 -and [int]$Bindings.TurnRight -ne 16 -and [int]$Bindings.Fire -ne 16 -and [int]$Bindings.Use -ne 16)
    $spaceUseAlias=([int]$Bindings.Forward -ne 32 -and [int]$Bindings.Backward -ne 32 -and [int]$Bindings.StrafeLeft -ne 32 -and [int]$Bindings.StrafeRight -ne 32 -and [int]$Bindings.TurnLeft -ne 32 -and [int]$Bindings.TurnRight -ne 32 -and [int]$Bindings.Fire -ne 32 -and [int]$Bindings.Run -ne 32)
    $Command.Clear();$run=($keys[[int]$Bindings.Run] -or ($keys[16] -and $shiftRunAlias)) -xor [bool]$AlwaysRun
    if($AutomapVisible){foreach($key in 37,38,39,40){$keys[$key]=$false}}
    $speed=if($run){50}else{25};$strafe=if($run){40}else{24};$turn=if($run){1280}else{640}
    $turn=[int]($turn*$TurnSpeed/100)
    if($keys[[int]$Bindings.Forward] -or $keys[38]){$Command.ForwardMove+=$speed}
    if($keys[[int]$Bindings.Backward] -or $keys[40]){$Command.ForwardMove-=$speed}
    if($keys[[int]$Bindings.StrafeRight]){$Command.SideMove+=$strafe};if($keys[[int]$Bindings.StrafeLeft]){$Command.SideMove-=$strafe}
    if($keys[[int]$Bindings.TurnLeft]){$Command.AngleTurn+=$turn};if($keys[[int]$Bindings.TurnRight]){$Command.AngleTurn-=$turn}
    if($keys[[int]$Bindings.Fire]){$Command.Buttons=$Command.Buttons -bor 1}
    if($keys[[int]$Bindings.Use] -or ($keys[32] -and $spaceUseAlias) -or $keys[13]){$Command.Buttons=$Command.Buttons -bor 2}
    for($key=49;$key -le 55;$key++) {if($State.Pressed[$key]){$Command.Buttons=$Command.Buttons -bor 4 -bor (($key-49) -shl 3)}}
    [Array]::Clear($State.Pressed);if($State.ContainsKey('PressedOrder')){$State.PressedOrder.Clear()}
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
