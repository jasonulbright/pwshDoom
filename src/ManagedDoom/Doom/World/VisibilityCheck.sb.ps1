# pwshDoom modification, 2026-09-10: initialize Fixed/Angle fields to their original struct defaults.
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

class VisibilityCheck {
    [World] $World

    # Eye z of looker.
    [Fixed] $SightZStart = [Fixed]::Zero
    [Fixed] $BottomSlope = [Fixed]::Zero
    [Fixed] $TopSlope = [Fixed]::Zero

    # From looker to target.
    [DivLine] $Trace
    [Fixed] $TargetX = [Fixed]::Zero
    [Fixed] $TargetY = [Fixed]::Zero

    [DivLine] $Occluder

    VisibilityCheck([World] $world) {
        $this.World = $world
        $this.Trace = [DivLine]::new()
        $this.Occluder = [DivLine]::new()
    }

    [Fixed] InterceptVector([DivLine] $v2, [DivLine] $v1) {
        # Preserve each Fixed operator's signed 32-bit wrap and arithmetic
        # shift while keeping its intermediate values in integers. Sight checks
        # call this for crossed two-sided lines on every simulation tic.
        [int]$v1DyShift = $v1.Dy.Data -shr 8
        [int]$v1DxShift = $v1.Dx.Data -shr 8
        [int]$denLeft = [Fixed]::ToInt32Unchecked(([long]$v1DyShift * [long]$v2.Dx.Data) -shr 16)
        [int]$denRight = [Fixed]::ToInt32Unchecked(([long]$v1DxShift * [long]$v2.Dy.Data) -shr 16)
        [int]$denData = [Fixed]::ToInt32Unchecked([long]$denLeft - [long]$denRight)

        if ($denData -eq 0) {
            return [Fixed]::Zero
        }

        [int]$xDelta = [Fixed]::ToInt32Unchecked([long]$v1.X.Data - [long]$v2.X.Data)
        [int]$yDelta = [Fixed]::ToInt32Unchecked([long]$v2.Y.Data - [long]$v1.Y.Data)
        [int]$numLeft = [Fixed]::ToInt32Unchecked(([long]($xDelta -shr 8) * [long]$v1.Dy.Data) -shr 16)
        [int]$numRight = [Fixed]::ToInt32Unchecked(([long]($yDelta -shr 8) * [long]$v1.Dx.Data) -shr 16)
        [int]$numData = [Fixed]::ToInt32Unchecked([long]$numLeft + [long]$numRight)

        # Match Fixed.op_Division's saturation threshold and double/truncate
        # path without allocating wrappers for the numerator and denominator.
        if (([Fixed]::CIntAbs($numData) -shr 14) -ge [Fixed]::CIntAbs($denData)) {
            $limit = if (($numData -bxor $denData) -lt 0) { [int]::MinValue } else { [int]::MaxValue }
            return [Fixed]::new($limit)
        }
        $quotient = ([double]$numData / [double]$denData) * [Fixed]::FracUnit
        if ($quotient -ge 2147483648.0 -or $quotient -lt -2147483648.0) {
            throw [DivideByZeroException]::new()
        }
        return [Fixed]::new([int][Math]::Truncate($quotient))
    }

    [bool] CrossSubsector([int] $subsectorNumber, [int] $validCount) {
        $map = $this.World.Map
        $subsector = $map.Subsectors[$subsectorNumber]
        $count = $subsector.SegCount

        for ($i = 0; $i -lt $count; $i++) {
            $seg = $map.Segs[$subsector.FirstSeg + $i]
            $line = $seg.LineDef

            if ($line.ValidCount -eq $validCount) { continue }

            $line.ValidCount = $validCount

            $v1 = $line.Vertex1
            $v2 = $line.Vertex2
            $s1 = [Geometry]::DivLineSide($v1.X, $v1.Y, $this.Trace)
            $s2 = [Geometry]::DivLineSide($v2.X, $v2.Y, $this.Trace)

            if ($s1 -eq $s2) { continue }

            $this.Occluder.MakeFrom($line)
            $s1 = [Geometry]::DivLineSide($this.Trace.X, $this.Trace.Y, $this.Occluder)
            $s2 = [Geometry]::DivLineSide($this.TargetX, $this.TargetY, $this.Occluder)

            if ($s1 -eq $s2) { continue }

            if ($null -eq $line.BackSector) { return $false }

            if (($line.Flags -band [LineFlags]::TwoSided) -eq 0) { return $false }

            $front = $seg.FrontSector
            $back = $seg.BackSector

            if ($front.FloorHeight.Data -eq $back.FloorHeight.Data -and $front.CeilingHeight.Data -eq $back.CeilingHeight.Data) {
                continue
            }

            $openTop = [Fixed]::Zero
            if ($front.CeilingHeight.Data -lt $back.CeilingHeight.Data) {
                $openTop = $front.CeilingHeight
            } else {
                $openTop = $back.CeilingHeight
            }

            $openBottom = [Fixed]::Zero
            if ($front.FloorHeight.Data -gt $back.FloorHeight.Data) {
                $openBottom = $front.FloorHeight
            } else {
                $openBottom = $back.FloorHeight
            }

            if ($openBottom.Data -ge $openTop.Data) { return $false }

            $frac = $this.InterceptVector($this.Trace, $this.Occluder)

            if ($front.FloorHeight.Data -ne $back.FloorHeight.Data) {
                $slope = ($openBottom - $this.SightZStart) / $frac
                if ($slope.Data -gt $this.BottomSlope.Data) {
                    $this.BottomSlope = $slope
                }
            }

            if ($front.CeilingHeight.Data -ne $back.CeilingHeight.Data) {
                $slope = ($openTop - $this.SightZStart) / $frac
                if ($slope.Data -lt $this.TopSlope.Data) {
                    $this.TopSlope = $slope
                }
            }

            if ($this.TopSlope.Data -le $this.BottomSlope.Data) { return $false }
        }

        return $true
    }

    [bool] CrossBspNode([int] $nodeNumber, [int] $validCount) {
        if ([Node]::IsSubsector($nodeNumber)) {
            if ($nodeNumber -eq -1) {
                return $this.CrossSubsector(0, $validCount)
            } else {
                return $this.CrossSubsector([Node]::GetSubsector($nodeNumber), $validCount)
            }
        }

        $node = $this.World.Map.Nodes[$nodeNumber]
        $side = [Geometry]::DivLineSide($this.Trace.X, $this.Trace.Y, $node)

        if ($side -eq 2) { $side = 0 }

        if (-not $this.CrossBspNode($node.Children[$side], $validCount)) {
            return $false
        }

        if ($side -eq [Geometry]::DivLineSide($this.TargetX, $this.TargetY, $node)) {
            return $true
        }

        return $this.CrossBspNode($node.Children[$side -bxor 1], $validCount)
    }

    [bool] CheckSight([Mobj] $looker, [Mobj] $target) {
        $map = $this.World.Map

        if ($map.Reject.Check($looker.Subsector.Sector, $target.Subsector.Sector)) {
            return $false
        }

        $this.SightZStart = $looker.Z + $looker.Height - ($looker.Height -shr 2)
        $this.TopSlope = ($target.Z + $target.Height) - $this.SightZStart
        $this.BottomSlope = $target.Z - $this.SightZStart

        $this.Trace.X = $looker.X
        $this.Trace.Y = $looker.Y
        $this.Trace.Dx = $target.X - $looker.X
        $this.Trace.Dy = $target.Y - $looker.Y

        $this.TargetX = $target.X
        $this.TargetY = $target.Y

        return $this.CrossBspNode($map.Nodes.Length - 1, $this.World.GetNewValidCount())
    }
}
