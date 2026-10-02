# Preview.5 release scope

October 2, 2026. This source-inclusive playable community preview follows the
user's35-commit public-release cadence. It incorporates the fixes since frozen
Preview.4 and preserves Classic, Matrix and color art. Gameplay, rendering,
encoding, sound decoding/synthesis and mixing remain PowerShell. Standard
Windows/.NET APIs handle device input/output and process coordination.

## Changes and capabilities

Pickup/key-lock notices use original IWAD lettering in Classic and readable
terminal text in the character modes. Pollable map loads show separately counted
loading feedback while preserving renderer processes. Immutable resource caches
avoid repeatedly preparing the same WAD data. Owned worker logs replace idle
pipe readers. Bounded host catch-up sends already-due commands within the same
two-command queue and stops at exact replay-control boundaries.

Realtime audio accounts for intervals already covered by filler, then applies
caught-up controls/events on its current output clock. Controlled producer-gap
tests recover below30 ms digital processing age. Late emitter replacements can
coalesce; this does not reconstruct past audible events or establish acoustic
latency. Prepared music remains optional and user supplied.

Menus retain four episodes/five skills, pause, automap, preferences and six save
slots with confirmed overwrite/load. Saved graphs are validated before replacing
the session. All36 maps have load/idle/render smoke coverage, which differs from
ordinary-input completion. The complete E1 secret-map/finale human route is
documented in [the playthrough guide](episode1-playtest.md).

Strips/Pairs remain defaults. AsyncBatch is opt-in: three paired cycles lower
median p99 tic lateness, while display changes vary−1.65% to+3.47% and no complete
numerical pacing gate passes. ColorState and Ansi256 are separate experiments;
Ansi256 approximates the palette. An exact-image wall-wrap trial was rejected
after paired regressions. [Performance evidence](performance.md).

## Package and evidence

The fresh ZIP is built from committed inputs by Build-PreviewPackage.ps1. Its
manifest pins every payload and package-source commit. Extracted validation is
recorded in `results/preview5-package-validation-20261002.json` in the repository;
publication/download hashes follow in a separate receipt. The ZIP omits large
research results, local assets, tools, recordings and the untracked research PDF.
No commercial IWAD, soundfont, prepared music, native engine or emulator is
distributed. Supply an Ultimate Doom IWAD and optionally your qualified catalog.

Existing live WGC/loopback fixtures cover notices, save/load and audio across all
three styles; later opt-in profiling changes preserve compared images. Their
raw media stays local and their source hashes distinguish recorded from packaged
bytes. A retained original-DOS-executable screenshot is lossy visual evidence;
raw framebuffer and hidden-state parity remain unqualified. [Fidelity limits](rendering-fidelity.md).

## Remaining release gates

This is a playable preview, not the fully qualified Ultimate Doom release
candidate. Whole campaigns and ordinary boss/secret routes, independent moving
world/framebuffer fidelity, sustained35-tic/60-distinct-display pacing, physical
keyboard/resize/1080p-DPI, acoustic review and second hardware remain open.
Completed writes and ETW display events do not prove distinct optical game
frames. Current sampled private memory is roughly4.4–4.6 GiB and startup about
25–27 seconds on the measured machine; these are workload-specific results.

Continue the [roadmap](roadmap.md) after publication. Doom II, MyHouse,
multiplayer and general PWAD compatibility remain later scopes. The
[article](article-draft.md) retains capabilities, alternatives and measured
limitations without unmeasured competitor rankings.
