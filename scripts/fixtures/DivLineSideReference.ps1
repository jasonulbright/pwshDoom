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

# Retained from commit 6bdc5a1 for independent numeric-side comparisons.
class RetainedDivLineSide {
static [int] DivLineSide([Fixed] $x, [Fixed] $y, [DivLine] $line) {
        if ($line.Dx.Data -eq [Fixed]::Zero.Data) {
            if ($x.Data -eq $line.X.Data) {
                return 2
            }

            if ($x.Data -le $line.X.Data) {
                return $(if ($line.Dy.Data -gt [Fixed]::Zero.Data) { 1 } else { 0 })
            }

            return $(if ($line.Dy.Data -lt [Fixed]::Zero.Data) { 1 } else { 0 })
        }

        if ($line.Dy.Data -eq [Fixed]::Zero.Data) {
            if ($y.Data -eq $line.Y.Data) {
                return 2
            }

            if ($y.Data -le $line.Y.Data) {
                return $(if ($line.Dx.Data -lt [Fixed]::Zero.Data) { 1 } else { 0 })
            }

            return $(if ($line.Dx.Data -gt [Fixed]::Zero.Data) { 1 } else { 0 })
        }

        $dx = $x - $line.X
        $dy = $y - $line.Y

        $left = [Fixed]::new(($line.Dy.Data -shr [Fixed]::FracBits) * ($dx.Data -shr [Fixed]::FracBits))
        $right = [Fixed]::new(($dy.Data -shr [Fixed]::FracBits) * ($line.Dx.Data -shr [Fixed]::FracBits))

        if ($right.Data -lt $left.Data) {
            # Front side.
            return 0
        }

        if ($left.Data -eq $right.Data) {
            return 2
        } else {
            # Back side.
            return 1
        }
    }
static [int] DivLineSide([Fixed] $x, [Fixed] $y, [Node] $node) {
        if ($node.Dx.Data -eq [Fixed]::Zero.Data) {
            if ($x.Data -eq $node.X.Data) {
                return 2
            }

            if ($x.Data -le $node.X.Data) {
                return $(if ($node.Dy.Data -gt [Fixed]::Zero.Data) { 1 } else { 0 })
            }

            return $(if ($node.Dy.Data -lt [Fixed]::Zero.Data) { 1 } else { 0 })
        }

        if ($node.Dy.Data -eq [Fixed]::Zero.Data) {
            if ($y.Data -eq $node.Y.Data) {
                return 2
            }

            if ($y.Data -le $node.Y.Data) {
                return $(if ($node.Dx.Data -lt [Fixed]::Zero.Data) { 1 } else { 0 })
            }

            return $(if ($node.Dx.Data -gt [Fixed]::Zero.Data) { 1 } else { 0 })
        }

        $dx = $x - $node.X
        $dy = $y - $node.Y

        $left = [Fixed]::new(($node.Dy.Data -shr [Fixed]::FracBits) * ($dx.Data -shr [Fixed]::FracBits))
        $right = [Fixed]::new(($dy.Data -shr [Fixed]::FracBits) * ($node.Dx.Data -shr [Fixed]::FracBits))

        if ($right.Data -lt $left.Data) {
            # Front side.
            return 0
        }

        if ($left.Data -eq $right.Data) {
            return 2
        } else {
            # Back side.
            return 1
        }
    }
}