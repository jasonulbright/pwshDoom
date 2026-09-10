# Existing implementations

Checked 2026-09-10 through web search, GitHub repository search, source trees, and selected source files. No claim of an exhaustive proof of absence is made. Campaign completion has not been independently verified.

| Offering | Engine and display | Evidence and limits |
| --- | --- | --- |
| [oleyska/ManagedDoomPowershell](https://github.com/oleyska/ManagedDoomPowershell) | Managed Doom translated into PowerShell; a software renderer presents through Silk.NET/GLFW/OpenGL; additional native/.NET audio and helper libraries. | 217 PowerShell files at inspected commit `e8440ae2f33f190318ebde4ef20ffec3bc804244`. Gameplay and rendering code are present. Author reports PS 7.5.4/7.6 testing, poor performance, transition and frame-cap issues. Not a terminal renderer. |
| [nick0451/doom-powershell](https://github.com/nick0451/doom-powershell) | Single script with WAD reading, BSP rendering, ANSI half-block output, and gameplay. | Source contains WAD, BSP, collision, monster, and door routines. README reports textures, sprites, combat, doors, exits, and multiplayer; explicitly lacks lifts, moving floors, walk-over triggers, and sound. Some behavior is deliberately simplified. Performance claims are upstream claims until reproduced. |
| [spidychoipro/terminal-doom-pwsh](https://github.com/spidychoipro/terminal-doom-pwsh) | C doomgeneric engine and C Windows Terminal backend. PowerShell build/launch scripts. | Source and README identify ANSI truecolor half-block presentation of the Doom framebuffer. Qualifies as terminal Doom, not Doom game logic implemented in PowerShell. |
| [resumex/doom-over-dns](https://github.com/resumex/doom-over-dns) | PowerShell transports WAD/assemblies via DNS; compiled C# Managed Doom runs in a graphical window. | README and source tree identify the compiled engine and omitted audio. Not a PowerShell translation or terminal renderer. |
| [ray0911/Doom-Powershell](https://github.com/ray0911/Doom-Powershell) | Small PowerShell/Windows Forms grid raycaster. | Inspected `Test.ps1`: generated maze, drawn gun, basic movement. No WAD-based Doom engine. |
| [PrismRewind/PowerDoom](https://github.com/PrismRewind/PowerDoom) | Repository describing a Build-engine recreation. | Inspected tree contained only a README and license; no playable implementation in that tree. |

Other terminal implementations, such as [dcouple/terminal-doom](https://github.com/dcouple/terminal-doom), demonstrate alternative presentation paths but use a compiled/WASM engine. They are prior art for display experiments, not evidence of PowerShell engine performance.

## Assessment

A faithful, fast PowerShell terminal implementation remains a plausible improvement target, but its novelty and feasibility have not been established. Benchmark existing work before choosing between contribution, a fork, or an independent implementation. Determine licensing before copying implementation code, particularly where a repository lacks an explicit license.

**Measured follow-up:** the first batch evaluated nick0451's BSP walls/flats/sky renderer from commit `6b0072973cd08fb83edc521e834e4070cda4b0a5`, using a separately stored source file and the user's Steam Doom IWAD. The low-resolution combined renderer/encoder/write loop reached 75–76 completed writes/second with the study's ANSI encoder in the corrected UTF-8 runs. This excludes gameplay and displayed-frame verification. See [full findings](findings-2026-09-10.md); it is not a reproduced upstream full-game performance claim.

## Assets

Users supply commercial IWADs. The engine source release does not release commercial graphics, music, or maps. [Freedoom explains the separation](https://freedoom.github.io/about.html) and provides independent replacement content. [Chocolate Doom documents obtaining the shareware IWAD](https://www.chocolate-doom.org/wiki/index.php/FAQ#Why_does_the_game_crash_just_after_the_title_screen_appears?). Availability of a WAD does not prove a particular port supports its full feature set.
