##
## Copyright (C) 1993-1996 Id Software, Inc.
## Copyright (C) 2019-2020 Nobuaki Tanaka
## Copyright (C) 2026 Oleyska
##
## This file is a PowerShell port / modified version of code from ManagedDoom.
##
## This program is free software; you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 2 of the License, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
## GNU General Public License for more details.
##

# Retained numeric discovery method from 62576dc3cb111291bfb8a4f6a2e3641a9d9041d2.
# General Geometry.SlopeDiv/PointToAngle remain unchanged and are shared oracles.
class DiscoveryAngleReference {
    static [long] PointToAngleData([int] $fromX, [int] $fromY, [int] $toX, [int] $toY) {
        [long] $x = ([long]$toX - $fromX) -band 0xffffffffL
        [long] $y = ([long]$toY - $fromY) -band 0xffffffffL
        if ($x -ge 0x80000000L) { $x -= 0x100000000L }
        if ($y -ge 0x80000000L) { $y -= 0x100000000L }
        if ($x -eq 0 -and $y -eq 0) { return 0 }
        if ($x -eq -2147483648L -or $y -eq -2147483648L) {
            # Preserve the reference's overflow/error behavior at this edge.
            return [Geometry]::PointToAngle([Fixed]::new($fromX), [Fixed]::new($fromY), [Fixed]::new($toX), [Fixed]::new($toY)).Data
        }
        [bool] $negativeX = $x -lt 0
        [bool] $negativeY = $y -lt 0
        if ($negativeX) { $x = -$x }
        if ($negativeY) { $y = -$y }
        [bool] $wide = $x -gt $y
        [int] $slope = if ($wide) { [Geometry]::SlopeDiv([int]$y, [int]$x) } else { [Geometry]::SlopeDiv([int]$x, [int]$y) }
        [long] $angle = [Trig]::tanToAngleTable[$slope]
        if (-not $negativeX) {
            if (-not $negativeY) { if ($wide) { return $angle }; return 0x40000000L - 1 - $angle }
            if ($wide) { return (-$angle) -band 0xffffffffL }; return 0xc0000000L + $angle
        }
        if (-not $negativeY) { if ($wide) { return 0x80000000L - 1 - $angle }; return 0x40000000L + $angle }
        if ($wide) { return 0x80000000L + $angle }; return 0xc0000000L - 1 - $angle
    }
}
