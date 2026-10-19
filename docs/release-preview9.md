# Preview.9 release scope

October 19, 2026. This cumulative playable community preview follows 35
commits since Preview.8. It preserves Classic, Matrix and AnsiArt, with
gameplay, rasterization, terminal encoding, music synthesis and audio mixing in
PowerShell. It does not certify the full Ultimate Doom release gates.

## Changes and offline evidence

The opt-in input recorder writes checksummed journal batches. The reader
validates batch ranges and event ordering, and the writer rejects malformed
commands and checkpoints before appending. Its offline contract has 28 checks;
actual recovery after a live process interruption remains unverified.

The fast renderer now computes wall-derived plane spans from fixed-point wall
boundaries and includes the fixed-point upper-portal edge row. In the saved
E1M1 lineflags replay at tic 315, scene differences fall from 215 to 4 at
ceiling height 34 and from 440 to 353 at height 68. Heights 0 and 6 remain
exact. A diagnostic-only trace classifies 14 remaining height-68 plane pixels
as different-owner reference plane writes around two-sided portal boundaries;
production rendering remains unchanged for those pixels. These comparisons
use the local PowerShell reference and do not establish original-executable
parity or broad moving-world fidelity.

This release candidate was prepared without live game, display, keyboard or
audio-device tests. The saved-replay comparison is offline evidence only.

## Remaining release gates

The complete human Episode 1 route, runtime interruption recovery, independent
original-frame comparisons, sustained simulation/display pacing, physical
keyboard and DPI/window review, acoustic listening, and a second hardware
configuration remain open. See the [roadmap](roadmap.md),
[performance findings](performance.md), [audio findings](audio.md), and
[working article](article-draft.md).

The package contains no IWAD, soundfont, prepared music, local research files,
review recordings or downloaded tools.
