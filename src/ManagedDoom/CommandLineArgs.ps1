# pwshDoom modification, 2026-09-10: avoid reserved $args in class methods.
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

class Arg {
    [bool] $Present = $false

    Arg() { }

    Arg([bool] $present) {
        $this.Present = $present
    }
}

# PowerShell doesn't support generics, so create specific versions
class ArgString {
    [bool] $Present = $false
    [string] $Value

    ArgString() { }

    ArgString([string] $value) {
        $this.Present = $true
        $this.Value = $value
    }
}

class ArgStringArray {
    [bool] $Present = $false
    [string[]] $Value = @()

    ArgStringArray() { }

    ArgStringArray([string[]] $value) {
        $this.Present = $true
        $this.Value = $value
    }
}

class ArgInt {
    [bool] $Present = $false
    [int] $Value = 0

    ArgInt() { }

    ArgInt([int] $value) {
        $this.Present = $true
        $this.Value = $value
    }
}

class ArgTuple {
    [bool] $Present = $false
    [int] $Episode
    [int] $Map

    ArgTuple() { }

    ArgTuple([int] $episode, [int] $map) {
        $this.Present = $true
        $this.Episode = $episode
        $this.Map = $map
    }
}

class CommandLineArgs {
    [ArgString] $iwad
    [ArgStringArray] $file
    [ArgStringArray] $deh
    
    [ArgTuple] $warp
    [ArgInt] $episode
    [ArgInt] $skill

    [Arg] $deathmatch
    [Arg] $altdeath
    [Arg] $fast
    [Arg] $respawn
    [Arg] $nomonsters
    [Arg] $solonet

    [ArgString] $playdemo
    [ArgString] $timedemo
    
    [ArgInt] $loadgame

    [Arg] $nomouse
    [Arg] $nosound
    [Arg] $nosfx
    [Arg] $nomusic

    [Arg] $nodeh

    CommandLineArgs([string[]] $gameArguments) {
        $this.iwad = [CommandLineArgs]::GetString($gameArguments, "-iwad")
        $this.file = [CommandLineArgs]::Check_file($gameArguments) 
        $this.deh = [CommandLineArgs]::Check_deh($gameArguments)

        $this.warp = [CommandLineArgs]::Check_warp($gameArguments)
        $this.episode = [CommandLineArgs]::GetInt($gameArguments, "-episode")
        $this.skill = [CommandLineArgs]::GetInt($gameArguments, "-skill")

        # Handle switches (flags) properly
        $this.deathmatch = [Arg]::new($gameArguments -contains "-deathmatch")
        $this.altdeath = [Arg]::new($gameArguments -contains "-altdeath")
        $this.fast = [Arg]::new($gameArguments -contains "-fast")
        $this.respawn = [Arg]::new($gameArguments -contains "-respawn")
        $this.nomonsters = [Arg]::new($gameArguments -contains "-nomonsters")
        $this.solonet = [Arg]::new($gameArguments -contains "-solo-net")

        $this.playdemo = [CommandLineArgs]::GetString($gameArguments, "-playdemo")
        $this.timedemo = [CommandLineArgs]::GetString($gameArguments, "-timedemo")

        $this.loadgame = [CommandLineArgs]::GetInt($gameArguments, "-loadgame")

        $this.nomouse = [Arg]::new($gameArguments -contains "-nomouse")
        $this.nosound = [Arg]::new($gameArguments -contains "-nosound")
        $this.nosfx = [Arg]::new($gameArguments -contains "-nosfx")
        $this.nomusic = [Arg]::new($gameArguments -contains "-nomusic")

        $this.nodeh = [Arg]::new($gameArguments -contains "-nodeh")
    }

    static [ArgStringArray] Check_file([string[]] $gameArguments) {
        $values = [CommandLineArgs]::GetValues($gameArguments, "-file")
        if ($values.Count -ge 1) {
            return [ArgStringArray]::new($values)
        }
        return [ArgStringArray]::new()
    }

    static [ArgStringArray] Check_deh([string[]] $gameArguments) {
        $values = [CommandLineArgs]::GetValues($gameArguments, "-deh")
        if ($values.Count -ge 1) {
            return [ArgStringArray]::new($values)
        }
        return [ArgStringArray]::new()
    }

    static [ArgTuple] Check_warp([string[]] $gameArguments) {
        $values = [CommandLineArgs]::GetValues($gameArguments, "-warp")
    
        if ($values.Count -eq 1) {
            $localMap = 0
            if ([int]::TryParse($values[0], [ref]$localMap)) {
                return [ArgTuple]::new(1, $localMap)
            }
        } elseif ($values.Count -eq 2) {
            $localEpisode = 0
            $localMap = 0
            if ([int]::TryParse($values[0], [ref]$localEpisode) -and [int]::TryParse($values[1], [ref]$localMap)) {
                return [ArgTuple]::new($localEpisode, $localMap)
            }
        }
    
        return [ArgTuple]::new()
    }
    

    static [ArgString] GetString([string[]] $gameArguments, [string] $name) {
        $values = [CommandLineArgs]::GetValues($gameArguments, $name)
        if ($values.Count -eq 1) {
            return [ArgString]::new($values[0])
        }
        return [ArgString]::new()
    }

    static [ArgInt] GetInt([string[]] $gameArguments, [string] $name) {
        $values = [CommandLineArgs]::GetValues($gameArguments, $name)
        if ($values.Count -eq 1) {
            [int]$result = 0
            if ([int]::TryParse($values[0], [ref]$result)) {
                return [ArgInt]::new($result)
            }
        }
        return [ArgInt]::new()
    }

    static [string[]] GetValues([string[]] $gameArguments, [string] $name) {
        $index = [Array]::IndexOf($gameArguments, $name)
        if ($index -ge 0 -and $index -lt ($gameArguments.Length - 1)) {
            return $gameArguments[($index + 1)..($gameArguments.Length - 1)] | Where-Object { $_ -notmatch '^-' }
        }
        return @()

    }
}