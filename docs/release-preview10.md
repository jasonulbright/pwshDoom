# Preview.10 release scope

October 20, 2026. This cumulative playable community preview follows 35
commits since Preview.9. It preserves Classic, Matrix and AnsiArt, with
gameplay, rasterization, terminal encoding, music synthesis and audio mixing in
PowerShell. It does not certify the full Ultimate Doom release gates.

The fast renderer now computes wall-texture and scaled world-patch column
offsets once per screen column instead of once per sampled pixel. A fixed
serial E1M2 render preserved the complete 64,000-pixel frame hash. The
unpaired timing observations varied substantially and do not establish a
performance improvement. The offline renderer work-counter instrumenter was
updated to follow the current source write sites.

This release preparation used headless fixed-state rendering only. No live
game, display, keyboard, or audio-device test was run.

The complete human Episode 1 route, runtime interruption recovery,
independent original-frame comparisons, sustained simulation/display pacing,
physical keyboard and DPI/window review, acoustic listening, and a second
hardware configuration remain open. See the [roadmap](roadmap.md),
[performance findings](performance.md), [audio findings](audio.md), and
[working article](article-draft.md).

The package contains no IWAD, soundfont, prepared music, local research files,
review recordings, or downloaded tools.
