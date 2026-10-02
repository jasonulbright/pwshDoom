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

## Extracted validation completed

The [repository receipt](../results/preview5-package-validation-20261002.json)
pins package source1681532d0ea63fd4fcdd95e153f74694a3cbb446. All559 payloads
match their manifest and that Git commit after checkout newline normalization.
The ZIP is1,735,913 bytes; SHA-256:
`3B767865F367A51D00F09BFEC1ECAA8CF9B4E6BDED28943375DA3C69FAEEED0C`.
The release tag adds this validation evidence to the package-source commit;
the manifest remains authoritative for the archive's exact source.

Extracted preflight recognizes36 maps and eleven prepared E1 tracks under
PowerShell7.6.6. Checks pass110 output,18 resource,125 menu/46 screen and15
music-enabled save/load assertions. Each style passes20 persistent16-worker
reload/fault checks with448,000 worker pixels and256,000 fresh-reference pixels.
Controlled audio recovery reaches19.4 ms maximum processing age. An eight-second
actual-device startup advances279 tics and returns all360,360 submitted frames.
Its short headless rate is not a release pacing qualification.

All36 maps pass35 idle tics and two indexed headings each. Three actual extracted
save/control fixtures retain350 commands, eleven checkpoints and14 admission/
audio checks per style. These checks do not navigate or finish maps. Retained
live footage matches35 of36 packaged sources; the differing renderer adds
opt-in profiling, with separately verified default image/strip equivalence.
The footage is not labeled as fully byte-identical final-source recording.

A wrapper initially captured the build summary as text and failed extraction.
The failure remains local; the existing archive was verified/extracted directly,
with no silent rebuild. Publication and fresh public-download verification
follow this35th commit. The full Ultimate Doom goal remains active.

## Public download verified

[Preview.5 is published](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.5).
The [publication receipt](../results/preview5-publication-20261002.json) verifies
a fresh download against the tested ZIP/checksum and GitHub asset digests,
all559 payload hashes and478 runtime files against the release tag. Publication
occurred at35 commits since Preview.4. The tag/manifest source distinction and
all remaining full-release gates stay explicit.
