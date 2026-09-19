# pwshDoom

**Doom, running in PowerShell. In your terminal. With a Matrix mode.**

Playable preview **0.1.0-preview.2** for Windows Terminal. Gameplay, software rendering, terminal encoding and sound-effects mixing are PowerShell. Bring your own Ultimate Doom `DOOM.WAD`.

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

Sound effects are enabled. Add `-Silent` to disable them or `-Ascii` if Japanese glyphs do not display correctly. Music is not included in the quick-start experience. No WADs, soundfonts or downloaded tools are distributed.

[Installation, troubleshooting and preview limits](docs/preview.md) · [PowerShell installation](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows) · [Windows Terminal installation](https://learn.microsoft.com/en-us/windows/terminal/install)

## Controls

**WASD** move/strafe · **← →** turn · **Ctrl** fire · **E / Space** use · **Shift** run · **1–7** weapons · **Tab** automap · **Escape** menu/save/load/quit.

The game opens in a maximized Terminal window. If it asks for more space, reduce the font with **Ctrl+minus**. Classic needs 320×100 cells; character styles need 160×50. Extra space surrounds the centered image. Shrinking below the required grid pauses gameplay.

## What ships

- Three display styles, menus, episode/difficulty selection, automap, save/load and sound effects.
- All 36 Ultimate Doom maps have load/simulation/render smoke coverage. E1M1–E1M4 have independently verified ordinary-input normal-exit routes.
- Damage, pickup and power-up palettes; an approximate parallel invisibility effect.
- Editable source, build/package scripts, attribution and the research ledger.

**This is an early playable preview.** Full campaign completion, visual fidelity, audio continuity and sustained 35-tick/60-display performance are unfinished. Recent workloads range from roughly 23 to 35 simulation ticks/sec; terminal writes are not proof of distinct displayed frames. Doom II, Final Doom, MyHouse, arbitrary add-on WADs and multiplayer are not supported claims for this release. See [known limitations](docs/preview.md).

## How it works—and who built the foundation

The gameplay core is an adapted, attributed GPL PowerShell translation of ManagedDoom by **Oleyska**, based on **Nobuaki Tanaka's ManagedDoom** and **id Software's Doom**. pwshDoom adds the terminal rasterizer/encoders, display styles, process coordination and integration work around that foundation. It is not the first PowerShell Doom, and it does not launch a compiled C/C# Doom engine behind the scenes.

PowerShell workers draw portions of the framebuffer and encode terminal output. Windows Terminal displays the characters; standard Windows/.NET APIs provide input, synchronization and audio-device access. See [credits](THIRD-PARTY-NOTICES.md), [source modifications](src/ManagedDoom/ORIGIN.md) and the [working article](docs/article-draft.md).

## Development

The packaged preview is the first public milestone; the project remains in development. [Roadmap](docs/roadmap.md) · [Research/development guide](docs/development-guide.md) · [Campaign coverage](docs/campaign-matrix.md) · [Investigation ledger](docs/ledger.md) · [Existing alternatives](docs/existing-implementations.md).

`Start-Doom.ps1` exposes advanced options. `Play.ps1 -Check -Wad 'D:\Games\DOOM.WAD'` checks prerequisites without starting a session. Research results live in the repository; the smaller release ZIP omits those large measurement files and all private local assets.

Report the version, map, style and reproduction steps in [Issues](https://github.com/jasonulbright/pwshDoom/issues). Inspect session reports for local paths before sharing, and never attach commercial WADs. Licensed **GPL-2.0-or-later**; see [LICENSE](LICENSE).
