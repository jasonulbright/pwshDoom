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

Modifications, 2026-09-11:

- `Geometry.PointToAngleData` and discovery-only `ThreeDRenderer` projection:
  retain the adopted slope table, octants, rounding and binary-angle wrapping
  using numeric PowerShell operations. This avoids Fixed/Angle allocations
  in automap discovery; ordinary 3D rendering keeps its reference path.
  Comparisons cover 2,139 angle cases, sixteen fixed map/HUD images and 48
  moving-route discovery viewpoints, with eight legacy gameplay checkpoints.
- `ThreeDRenderer`: added an experimental discovery-only BSP traversal that
  marks visible lines without rasterizing pixels or processing sprites. It
  uses simulation-endpoint camera values and horizontal solid-range clipping.
  The host now uses it after simulation updates; reference buffer-limit parity
  and pacing remain unqualified. See `docs/automap.md` for the comparisons.
- `DrawScreen.DrawColumnExact`: unit-scale drawing uses the existing clipped
  bulk post copy instead of per-pixel Fixed operations. Sixteen baseline
  map/HUD hashes remain unchanged; expanded cached HUD checks are documented.
- `AutoMapRenderer`: clear the column-major map area with standard bulk array
  operations and skip transforms of undiscovered lines when neither cheating
  nor the all-map power exposes them. Sixteen baseline map/HUD images retain
  identical hashes; subsequent HUD caching and remaining pacing limits are
  documented in the automap investigation.
- `ThingAllocation.SpawnPlayer`: clear the previous damage attacker with the
  damage counter. Cross-map save qualification exposed an E1M1 actor retaining
  its old world after the player entered E1M2. This is an explicit lifecycle
  adaptation, not a claim of an additional vanilla compatibility result.
- `DoomGame`: route Ultimate Doom map-8 completions to the finale, return E4M9
  to E4M3, preserve secret-visit history, and convert par seconds to tics.
- `Finale`: choose each Ultimate Doom episode's text/flat, remove accidental
  here-string indentation/CR line endings, and request victory music.
- `FinaleRenderer`: read the instance text speed, cache immutable 320×200 flat
  pixels and incrementally reveal text. `IntermissionRenderer`: cache immutable
  320×200 map backgrounds. Reference pixel hashes are retained in the study.

The new game host and 3D rasterizer are in the parent `src` directory. They consume
the adopted data model. The session-screen path uses the adopted PowerShell
intermission/finale 2D renderers. Gameplay uses its 3D reference renderer only
for discovery, without 3D pixel rasterization, and its automap/HUD renderers for
map screens with a presentation-only HUD cache.
Further adaptations and validation are recorded in `docs/ledger.md` at the
repository root. This attribution does not claim vanilla compatibility.
