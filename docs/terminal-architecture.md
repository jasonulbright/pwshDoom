# PowerShell and Windows Terminal

PowerShell is the script runtime. Windows Terminal provides a tab/pane UI and rendering. ConPTY connects console applications to the terminal; it handles compatibility with Windows console APIs. Terminal's GPU does not automatically execute PowerShell arithmetic.

```text
PowerShell game/simulation -> indexed framebuffer -> output encoder
    -> console/ConPTY -> Windows Terminal parser and renderer
    -> Windows compositor -> monitor
```

Inputs travel back through the console connection. A program may execute quickly while output queues lag behind it. Process completion, successful writes, GPU presents, and unique monitor-visible frames are different observations.

On Windows, raw bytes written through a console handle still depend on its output code page. PowerShell 7 and a modern Terminal do not by themselves guarantee that a new console uses UTF-8. The study's fresh profile inherited code page 437. Its corrected harnesses set `[Console]::OutputEncoding` to UTF-8 before sending UTF-8 half-block glyphs, record code page 65001, and restore the original encoding afterward. See [.NET output encoding](https://learn.microsoft.com/en-us/dotnet/api/system.console.outputencoding?view=net-10.0) and [Windows console output code pages](https://learn.microsoft.com/en-us/windows/console/setconsoleoutputcp).

## Relevant capabilities

- ANSI truecolor foreground/background plus half-block glyphs can represent two colored pixels per character cell. A 320x200 image therefore needs 320 columns and 100 rows; font size and window geometry matter.
- Sixel encodes raster pixels into the terminal stream. Windows Terminal added support in 1.22. It avoids using a character cell for each pair of pixels, but adds palette/encoding work and is not a shared GPU framebuffer.
- DECSET 2026 synchronized output can defer rendering until an update ends. It is supported in the installed 1.24 build and was backported to 1.23.20211.0. It is not a delivery acknowledgement or an FPS guarantee.
- `antialiasingMode` changes glyph rasterization (`grayscale`, `cleartype`, `aliased`). It is distinct from scene antialiasing.
- The Atlas renderer in tag `v1.24.11911.0` uses a frame-latency waitable object and `Present1(1, ...)`. This follows presentation synchronization; it does not impose a universal 60 FPS maximum. Actual high-refresh behavior remains to be measured.
- Terminal 1.22's revised hosting subsystem reported workload-specific output throughput gains. These cannot be directly converted into game FPS.

## Primary references

- [Console, shell, terminal definitions](https://learn.microsoft.com/en-us/windows/console/definitions)
- [ConPTY](https://learn.microsoft.com/en-us/windows/console/pseudoconsoles)
- [Virtual terminal sequences](https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences)
- [Antialiasing settings](https://learn.microsoft.com/en-us/windows/terminal/customize-settings/profile-advanced#text-antialiasing)
- [1.22 Sixel and hosting changes](https://devblogs.microsoft.com/commandline/windows-terminal-preview-1-22-release/)
- [Synchronized output servicing announcement](https://github.com/microsoft/terminal/discussions/19779)
- [Atlas renderer design](https://github.com/microsoft/terminal/blob/main/src/renderer/atlas/README.md)
- [Installed-version presentation source](https://github.com/microsoft/terminal/blob/v1.24.11911.0/src/renderer/atlas/AtlasEngine.r.cpp)
- [DXGI Present1 semantics](https://learn.microsoft.com/en-us/windows/win32/api/dxgi1_2/nf-dxgi1_2-idxgiswapchain1-present1)

For a faithful port, classic Doom uses BSP traversal and sectors rather than a simple grid raycaster: [original BSP source](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_bsp.c).
