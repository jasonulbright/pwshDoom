# Changelog

## Unreleased

### Added

- Optional prepared-music playback through `Play.ps1 -MusicCatalog`. PowerShell synthesizes and mixes the score; users prepare catalogs from their own IWAD and soundfont. Missing catalogs fail before launch, and `-MusicCatalog` cannot be combined with `-Silent`. Music remains opt-in and is not bundled.
- A complete Episode 1 human-playthrough handoff, pinned build evidence and a campaign/render/audio investigation ledger. The handoff is ready, but the human playthrough and broader campaign release gate are still pending.

### Changed

- Refined Doom-style rendering with integer-column wall rays, integer-row wall sampling, fixed-point plane and actor projection, sky sampling, sprite patch-column rules and wall-silhouette clipping. These changes improve specific reference comparisons; independent original-executable parity remains unmeasured, and the exact E1M1 pre-placed Gibs-through-wall sighting near the blue armor remains unreproduced.
- Reduced selected renderer allocations and optimized the PowerShell music mixer while preserving tested output. The 35-tic/60-displayed-frame goal remains unverified; one bounded Classic E1M1 run reached 34.959 simulation tics/sec and 59.67 Terminal updates/sec, which is not a monitor-presentation measurement.
- Warmed intermission backgrounds before their first visible frame and expanded source-pinned campaign, save/audio-worker, renderer and soundtrack checks.

### Fixed

- Corrected upstream arithmetic and angle-comparison behavior used by movement, weapons and homing actors; the E1M2 chainsaw-attack crash now passes a focused real-world hit regression.
- Fixed reproduced actor visibility leaks and renderer range/plane-depth cases; broader scene differences and other unverified reports remain.

### Qualification

- All 36 Ultimate Doom maps pass load/simulation/render smoke checks. Ordinary-input normal exits are independently verified for E1M1–E1M4; the complete E1 human playthrough is pending.
- The retained HMP E1M1 route driver passes again on current source in 1,560 commands. A separate maximized, no-audio PresentMon replay measured 47.73 display transitions/sec and 34.977 active tics/sec, but its older fixed input ended at `ReplayEnd` on E1M1; this is timing evidence, not route completion or a 35/60 FPS qualification. Repeated paired full-host trials remain open.
- Eleven Episode 1 loops are prepared locally. Nine Episode 2 map-track names have loop qualifications: D_E2M1–D_E2M3 and D_E2M7–D_E2M9 use two-period complete-state proofs, while D_E2M4–D_E2M6 use independently matching three-period outputs. D_E2M1–D_E2M4 and D_E2M6–D_E2M9 add eight byte-distinct payloads; D_E2M5 is byte-identical to D_E1M7. D_E3M1 is qualified as an exact MUS/soundfont-hash alias of D_E2M9, with its own map-selection and host checks. Short host-selection checks cover D_E2M4–D_E2M9 and D_E3M1. E2M4–E2M6 each reported one post-final-packet queue-starvation observation; E2M7 returned every frame; E2M8 completed 85,680 of 86,940 submitted frames before shutdown with a 1,260-frame canceled-tail upper bound; E2M9 completed 84,420 of 86,940 with a 2,520-frame bound; E3M1 completed 85,680 of 86,940 with a 1,260-frame upper bound. E2M8/E2M9/E3M1 had no starvation or rebuffer. Eight other Episode 2/3 map-track names and two one-shot scores remain open. These short checks do not establish full-campaign playback, acoustics or sustained queue timing.

## 0.1.0-preview.2

Gameplay and rendering fixes following the first playable preview. Qualification also adds 97 boss-trigger checks; these do not certify ordinary-input boss victories.

- Preserve fence/grille pixels when drawing scenery behind two-sided transparent walls; retain actor occlusion through their holes.
- Fix a missile-collision crash caused by looking up the sky flat on the map instead of its flat collection.
- Repair external vanilla demo file construction in the adopted engine; this does not yet expose `.lmp` playback in the preview launcher or establish demo synchronization.

## 0.1.0-preview.1

First packaged playable preview for Windows Terminal and PowerShell 7.

- Classic 320×200 half-block output; Matrix and color-art character modes with katakana or ASCII.
- PowerShell gameplay, software rendering, terminal encoding and sound-effects mixing.
- Menus, difficulty/episode selection, save/load, automap and keyboard controls.
- Ultimate Doom map-start coverage across all 36 maps; normal-exit routes verified for E1M1–E1M4.
- Damage/pickup/power-up palettes and an approximate parallel invisibility effect.
- Guided launcher, prerequisite/WAD checks, source-inclusive ZIP and checksum manifest.

This is an early preview, not full campaign certification or a 60 FPS guarantee. Music requires additional preparation and is not included in the quick-start experience. Doom II, Final Doom, MyHouse, arbitrary PWADs and multiplayer are not supported claims for this preview. See [known limitations](docs/preview.md).
