# Experimental indexed-color ANSI output

Classic Doom normally uses exact truecolor ANSI: each upper-half-block cell carries the RGB value of its top and bottom framebuffer pixels. The optional `Ansi256` encoder maps each color in the current Doom PLAYPAL to the nearest indexed color among xterm entries 16–255, using squared Euclidean distance in RGB. It emits the standard indexed foreground/background form (`38;5;n` and `48;5;n`) while keeping the same 320×200 framebuffer, half-block glyphs, and geometry. Microsoft's [console virtual-terminal documentation](https://learn.microsoft.com/windows/console/console-virtual-terminal-sequences) defines these indexed SGR sequences.

This is a color approximation. The terminal chooses the actual RGB values for its indexed palette, so the displayed color depends on its palette configuration. `Pairs` remains the exact truecolor default; `ColorState` is also exact truecolor. Matrix and AnsiArt continue using their own encoders.

Launch it through either entry point:

```powershell
./Play.ps1 -Style Classic -AnsiEncoding Ansi256 -Wad 'D:\Games\DOOM.WAD'
./Start-Doom.ps1 -Style Classic -AnsiEncoding Ansi256 -Wad 'D:\Games\DOOM.WAD'
```

## What the current measurements show

Encoding one identical 320×200 E1M1 indexed frame and palette into 16 equivalent strips produced 666,169 bytes with `Pairs` and 475,310 bytes with `Ansi256`, a reduction of 190,859 bytes (28.65%). The indexed frame and palette hashes are in the [portable measurement receipt](../results/ansi256-runtime-20260929.json). This is a byte-count comparison for one fixed frame; it says nothing by itself about encoder time or live presentation rate.

The production strip tests pass 24 decoder round-trips across truecolor and indexed output, odd dimensions, uneven strip counts and two screen origins. Five fixed E1M1 views also compare serial rendering and 16-worker rendering over 320,000 source pixels; their encoded strips match for the chosen mode. These verify the output path and partitioning, not color parity with exact truecolor or the original Doom executable.

One 15-second Windows Terminal run on PowerShell 7.6.5 with the local Ultimate Doom IWAD, 16 workers, Classic and no audio completed 647 Terminal writes (43.12 writes/sec) and 524 simulation tics (34.92 tics/sec). It did not reach 60 writes/sec or 35 tics/sec. A single later `Pairs` run under nominally the same settings completed 156 writes (10.38/sec) and 169 tics (11.25/sec), with much larger frame-time tails and a substantially smaller worker working set. These sequential runs are not a controlled or repeated comparison; system load was not captured, and the large difference makes the timing pair unsuitable for attributing a gain or loss to the encoder. Terminal writes are not measured monitor presentations. Full details and raw-report hashes are in the receipt; raw reports remain in the ignored local folder.

Keep Ansi256 optional for people who prefer lower terminal output volume and accept palette approximation. It has not demonstrated a live speedup, passed the 35-tic/60-display goal, or displaced exact truecolor as the default. A useful next performance comparison would interleave repeated real-game runs from matched state, capture machine-load conditions, and report encoded bytes/frame separately from output intervals and monitor presentation.
