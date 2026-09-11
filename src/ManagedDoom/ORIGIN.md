# Adopted PowerShell engine source

Source: https://github.com/oleyska/ManagedDoomPowershell

Revision: `e8440ae2f33f190318ebde4ef20ffec3bc804244`

This directory contains the 206 PowerShell source files outside the upstream
`Silk` and `PowershellHandler` directories. No WAD, soundfont, assembly, native
library, launcher, or upstream build helper is included. The original checkout
is kept separately under ignored `local/upstream/`.

Copyright notices are retained in each file. This is a PowerShell translation
by Oleyska of ManagedDoom by Nobuaki Tanaka, derived from id Software's Doom.
The source is GPL-2.0-or-later; the complete GPL v2 text is at ../../LICENSE.
pwshDoom's adaptations and integration code are also GPL-2.0-or-later.

Modifications, 2026-09-10:

- `Video/Renderer.sb.ps1`: replaced the custom compiled BufferHelper call with
  a PowerShell RGBA conversion. The terminal backend consumes indexed pixels
  directly and does not need this conversion.
- Seven argument-handling files: renamed reserved `$args` parameters to
  `$gameArguments`. `GameContent` now passes the raw argument array to consumers
  that parse it instead of reparsing a `CommandLineArgs` object.
- `DoomInfo.Strings`: repaired instance string references and used the existing
  `Replaced` text property. `DoomAnimation`/`DoomInfo`: corrected instance versus
  static access and the animation array type.
- `FlatLookup`: count marker results as arrays, including zero/one matches.
  `SpriteLookup`: exclude the enum Count sentinel, resolve names through the
  names array, and allocate only actual sprite definitions.
- `LineDef`: guard absent front/back sides. `BlockMap`: use the static block
  size constant. `World`: initialize the console player before the status bar.
  `Hitscan`: read the sky-flat identifier from the flat lookup.
- `LineDef`: retain the WAD's signed 16-bit flags in an integer instead of a
  validated PowerShell enum. E2M7 contains bits outside the named flags; preserving
  them avoids rejecting the map and keeps named bit tests/automap updates valid.
- Initialized 126 instance `Fixed`/`Angle` fields across 26 files to zero, restoring
  the defaults of the original C# structs. See `docs/engine-defaults.json` at the
  repository root. These objects are used as immutable values.
- `Config`: added a parameterless constructor using the existing defaults.
- `DrawScreen`/`ThreeDRenderer`: added experimental horizontal bounds for the
  reference-renderer strip baseline. These are not the game presentation path;
  scaled drawing paths have not been validated as independent strips.

The new game host and rasterizer are in the parent `src` directory. They consume
the adopted data model but do not call its reference renderer during play.
Further adaptations and validation are recorded in `docs/ledger.md` at the
repository root. This attribution does not claim vanilla compatibility.
