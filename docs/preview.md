# Playable preview 0.1.0-preview.2

This update fixes a missile-collision crash and disappearing fence/grille pixels. It also repairs the adopted engine's external demo reader, which is not yet exposed by the launcher. See the [changelog](../CHANGELOG.md). Campaign and performance qualification remain incomplete.

## Start playing

1. Install 64-bit [PowerShell 7.4 or newer](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows) and [Windows Terminal](https://learn.microsoft.com/en-us/windows/terminal/install).
2. Download the preview ZIP and extract the entire folder somewhere writable. If Windows marks the downloaded ZIP as blocked, use its Properties → Unblock before extracting. No administrator rights or security-policy changes are requested by the launcher.
3. Double-click `Play.cmd`, choose Classic, Matrix or Color art, and supply your own Ultimate Doom `DOOM.WAD` if it is not found. The usual Steam installation and a WAD beside `Play.cmd` are detected.
4. Allow up to a minute for the first startup. A maximized Terminal window opens with a dedicated game profile. Sound effects are enabled. Music is not bundled.

From PowerShell, the equivalent is:

```powershell
.\Play.ps1 -Wad 'D:\Games\DOOM.WAD' -Style Matrix
```

Use `-Style Classic` or `-Style AnsiArt` for the other views, `-Silent` to disable effects, or `-Ascii` if Japanese glyphs do not display correctly. `-Check` validates the local prerequisites and IWAD without opening the game. The lower-level `Start-Doom.ps1` retains the research/development options.

## Controls

| Action | Keys |
| --- | --- |
| Move / strafe | W / S / A / D |
| Turn | Left / right arrows |
| Fire | Ctrl |
| Open / use | E or Space |
| Run | Shift |
| Select weapon | 1–7 |
| Menu / save / load / quit | Escape, then arrows and Enter |
| Automap | Tab |
| Pause | P |
| Respawn | Enter |

If a menu appears, release held gameplay keys before resuming. In the automap, +/− zoom, F toggles follow, arrows pan with follow off, and M/C place/clear marks.

## Preview limits

- **Ultimate Doom first.** All 36 maps have load/simulation/render smoke coverage. Ordinary-input normal exits are independently verified for E1M1–E1M4. Full episode playthroughs, all secrets, boss endings and harder difficulties remain unqualified. This does not mean the remaining maps are known broken.
- **Performance varies.** 35 game ticks/sec and 60 displayed frames/sec remain targets. Recorded workloads range substantially; recent color-art repeats ran at about 35 and 23 ticks/sec. High memory use and startup/loading delays remain. Plan for several GB free; the 16-worker renderer alone has used approximately 4–5.5 GB. Lower worker counts are available through `-Workers`, with a throughput tradeoff that depends on hardware.
- **Sound effects, no quick-start music.** PowerShell synthesis/preparation work exists, but portable soundtrack setup and audio continuity are unfinished. No soundfont or pre-rendered soundtrack is distributed.
- **Stylized and approximate.** Classic retains the source pixels; character modes intentionally lose detail. Projection/texture fidelity, dark-scene readability and some effects remain imperfect. Strong damage tints can obscure the character view. Vanilla pixel/demo compatibility is not claimed.
- **Windows keyboard play.** Mouse look, multiplayer, Linux/macOS, Doom II, Final Doom, MyHouse and general PWAD compatibility are outside this preview's supported scope.
- **Display fit.** Classic needs 320×100 terminal cells; character modes need 160×50. Resize below that and the game pauses with instructions. Ctrl+minus reduces the Terminal font size. A 1080p display is not categorically excluded, but the full DPI/hardware matrix remains untested.

The dedicated `pwshDoom` Terminal profile can be removed with `scripts/Remove-GameProfile.ps1`. Saves live in `%LOCALAPPDATA%\pwshDoom\saves`, settings in `%LOCALAPPDATA%\pwshDoom\settings.json`, and disposable session files/reports under the extracted folder's `local` directory. Keep saves before deleting them; removing the profile does not remove saves.

## Report an issue

Include the preview version, PowerShell/Terminal versions, style, map, difficulty, steps to reproduce, and whether sound was enabled. The latest session report is `local/game-session.json`; it can contain local paths and input/state details, so inspect it before attaching. Do not upload your WAD, extracted assets or saves containing game data.

The source and [research roadmap](roadmap.md) remain available for development. A reproducible input replay is useful evidence, but it is not a substitute for physical play feedback.
