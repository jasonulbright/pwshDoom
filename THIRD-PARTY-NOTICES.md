# Credits and licenses

pwshDoom is GPL-2.0-or-later. The complete GPL version 2 text is in [LICENSE](LICENSE).

The gameplay foundation is [Oleyska's ManagedDoomPowershell](https://github.com/oleyska/ManagedDoomPowershell), a PowerShell translation of [Nobuaki Tanaka's ManagedDoom](https://github.com/sinshu/managed-doom), derived from id Software's Doom. Adopted revision: `e8440ae2f33f190318ebde4ef20ffec3bc804244`. Original copyright/license notices are retained. [Source provenance and modifications](src/ManagedDoom/ORIGIN.md) describe the adopted subset and subsequent changes.

pwshDoom adds a PowerShell terminal rasterizer and encoders, process coordination, presentation styles, menus, save/replay integration, and audio work around that foundation. It is not a claim to have invented the underlying engine or the first PowerShell Doom.

The release includes the editable PowerShell source and scripts needed to run it. Windows ABI declarations call operating-system services; they do not substitute a compiled gameplay engine or rasterizer.

Doom game data, WADs, soundfonts, prepared music, screenshots, recordings, PowerShell, Windows Terminal and external measurement/capture tools are not included. Supply your own legitimately obtained Ultimate Doom IWAD. Doom names belong to their respective owners; this project is not affiliated with or endorsed by them.
