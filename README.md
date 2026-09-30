# pwshDoom

**Doom, running in PowerShell. In your terminal. With a Matrix mode.**

**Latest tagged release: [0.1.0-preview.4](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.4).** This cumulative update adds audio continuity and shutdown fixes, renderer optimizations, stationary automap reuse and optional indexed-color output. Gameplay, software rendering, terminal encoding, decoding, music synthesis and mixing remain PowerShell. Bring your own Ultimate Doom `DOOM.WAD`.

This is a playable community preview. The complete Episode 1 human playthrough and broader Ultimate Doom qualification remain open. See the [playthrough instructions](docs/episode1-playtest.md), [release evidence](docs/release-preview4.md), and [roadmap](docs/roadmap.md).

| Classic | Matrix | Color art |
| --- | --- | --- |
| 320×200 pixels using truecolor half-blocks | Green katakana and animated highlights | Colored katakana following the scene |
| `-Style Classic` | `-Style Matrix` | `-Style AnsiArt` |

## Play

You need Windows, **64-bit PowerShell 7.4+**, Windows Terminal, and your own classic **Ultimate Doom IWAD**. This preview is demanding: allow several GB of free RAM and up to a minute for startup.

1. Get the ZIP from [Releases](https://github.com/jasonulbright/pwshDoom/releases) and extract the whole folder.
2. Double-click **`Play.cmd`**.
3. Choose a style. The launcher finds the usual Steam install or asks for your `DOOM.WAD`.

Or, from PowerShell in the extracted folder:

```powershell
.\Play.ps1 -Style Matrix -Wad 'D:\Games\DOOM.WAD'
```

Sound effects are enabled. Add `-Silent` to disable them or `-Ascii` if Japanese glyphs do not display correctly. Optional music requires a local catalog prepared from your own IWAD and soundfont as described in [music preparation](docs/music-preparation.md), then passed with `-MusicCatalog`. Neither assets nor prepared audio are packaged; continuous campaign playback and acoustic quality remain unqualified. No WADs, soundfonts or downloaded tools are distributed.

[Installation, troubleshooting and preview limits](docs/preview.md) · [PowerShell installation](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows) · [Windows Terminal installation](https://learn.microsoft.com/en-us/windows/terminal/install)

## Controls

**WASD** move/strafe · **← →** turn · **Ctrl** fire · **E / Space** use · **Shift** run · **1–7** weapons · **Tab** automap · **Escape** menu/save/load/quit.

The game opens in a maximized Terminal window. If it asks for more space, reduce the font with **Ctrl+minus**. Classic needs 320×100 cells; character styles need 160×50. Extra space surrounds the centered image. Shrinking below the required grid pauses gameplay.

Classic also accepts `-AnsiEncoding Ansi256` for an experimental indexed-color approximation. For example, add it to the `Play.ps1` launch command above. Exact truecolor `Pairs` remains the default; the measured byte saving has not established a live speed increase. See the [Ansi256 findings](docs/ansi-256-color.md).

## Current source status

- Three display styles, menus, episode/difficulty selection, automap, save/load and sound effects, with optional prepared music.
- All 36 Ultimate Doom maps have load/simulation/render smoke coverage. E1M1, E1M2, and E1M4 ordinary-input routes pass on the current gameplay source; the E1M3 route driver stalls without a reproduced defect. These regressions do not replace the complete Episode 1 human playthrough, which remains pending on the current handoff.
- Recent rendering work improves Doom-style wall, plane and actor sampling and clips world sprites to wall silhouettes. The R12 plane-sampler optimization preserves all compared pixels; full original-executable parity is not established.
- The R9 music-reader tests pass 21 checks. Opening all eleven local Episode 1 tracks is 56.06% faster in a warm-cache, reader-only comparison; this is not a cold-start or whole-game measurement.
- Damage, pickup and power-up palettes; an approximate parallel invisibility effect.
- Editable source, build/package scripts, attribution and the research ledger.

**This is an early playable preview.** Full campaign completion, visual fidelity, audio continuity and sustained 35-tick/60-display performance are unfinished. In one bounded, maximized Classic E1M1 run, the game completed 59.67 Terminal updates/sec and 34.959 simulation ticks/sec; this does not prove 60 distinct displayed frames/sec, and heavier workloads run slower. Doom II, Final Doom, MyHouse, arbitrary add-on WADs and multiplayer are not supported claims for this release. See [known limitations](docs/preview.md) and the [measurement details](docs/performance.md).

## How it works—and who built the foundation

The gameplay core is an adapted, attributed GPL PowerShell translation of ManagedDoom by **Oleyska**, based on **Nobuaki Tanaka's ManagedDoom** and **id Software's Doom**. pwshDoom adds the terminal rasterizer/encoders, display styles, process coordination and integration work around that foundation. It is not the first PowerShell Doom, and it does not launch a compiled C/C# Doom engine behind the scenes.

PowerShell workers draw portions of the framebuffer and encode terminal output. Windows Terminal displays the characters; standard Windows/.NET APIs provide input, synchronization and audio-device access. See [credits](THIRD-PARTY-NOTICES.md), [source modifications](src/ManagedDoom/ORIGIN.md) and the [working article](docs/article-draft.md).

## Development

The packaged preview is the first public milestone; the project remains in development. [Roadmap](docs/roadmap.md) · [Research/development guide](docs/development-guide.md) · [Campaign coverage](docs/campaign-matrix.md) · [Investigation ledger](docs/ledger.md) · [Existing alternatives](docs/existing-implementations.md).

`Start-Doom.ps1` exposes advanced options. `Play.ps1 -Check -Wad 'D:\Games\DOOM.WAD'` checks prerequisites and, when supplied, validates music qualification metadata without starting a session. Payload hashes and IWAD score identity are still checked when the audio workers start. Research results live in the repository; the smaller release ZIP omits those large measurement files and all private local assets.

Report the version, map, style and reproduction steps in [Issues](https://github.com/jasonulbright/pwshDoom/issues). Inspect session reports for local paths before sharing, and never attach commercial WADs. Licensed **GPL-2.0-or-later**; see [LICENSE](LICENSE).
