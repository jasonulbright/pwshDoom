# Changelog

## Unreleased

Full Ultimate Doom campaign, independent fidelity, physical/acoustic review,
display pacing and second-hardware qualification continue after Preview.8.

## 0.1.0-preview.8 — 2026-10-04

Cumulative playable community preview after36 commits since Preview.7. It
preserves Classic, Matrix and AnsiArt. Gameplay, rendering and audio mixing
remain in PowerShell. See [scope and current limits](docs/release-preview8.md);
this is not full Ultimate Doom certification.

- Add saved gamma levels and an F11 shortcut; custom key bindings now report
  reserved keys and preserve rapid repeated menu taps.
- Use Doom's fixed-angle wall-span lookup when WAD geometry metadata is
  present. Numeric snapshot camera values retain their world-unit/radian form.
- Add offline synthetic renderer checks for wall order, camera representation
  parity and all four cardinal projection headings. No live game/device test or
  renderer-speed claim is included in this package preparation.
- Full Episode 1 human completion, original-frame fidelity, audio listening,
  physical-device review and 35-tic/60-display qualification remain open.

Published package: [v0.1.0-preview.8](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.8).

## 0.1.0-preview.7 — 2026-10-02

Cumulative playable community preview after35 commits since Preview.6. Preserves
Classic, Matrix and AnsiArt and keeps gameplay, rendering and audio mixing in
PowerShell. See [scope and current limits](docs/release-preview7.md); this is
not full Ultimate Doom certification.

- Add function-key access to controls (F1), save (F2), load (F3) and confirmed
  quit (F10). Canceling F10 returns to the game.
- Reuse per-renderer wall-parameter buffers and cached fixed-point WAD inputs.
  The E1M2 static image hash is unchanged. The paired benchmark could not reach
  timing because its isolated module could not resolve `[Patches]`; no speedup
  or pacing improvement is claimed.
- Full Episode 1 human completion, original-frame fidelity, audio listening,
  physical-device review and 35-tic/60-display qualification remain open.

Published package: [v0.1.0-preview.7](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.7).

## 0.1.0-preview.6 — 2026-10-02

Cumulative community preview after35 commits. Preview.6 preserves Classic,
Matrix and AnsiArt and integrates the tested PowerShell wall-band preselection
trial. The bounded E1M2 median improvement does not establish full-host pacing.
[Scope and evidence](docs/release-preview6.md); the full Ultimate Doom route and
release gates remain open.
Published package: [v0.1.0-preview.6](https://github.com/jasonulbright/pwshDoom/releases/tag/v0.1.0-preview.6).

The extracted release package was checked against all569 manifest hashes and
passed launch prerequisites, 36 map-start smokes, and serial/16-worker parity
for 320,000 pixels per style across Classic, Matrix and AnsiArt. The 1,819,451-
byte ZIP SHA-256 is `60b04f6e0cccb6da7326bef5edabd85dec3c25c5bc6687c691e10b27decd8243`.

- Select eligible textured wall bands once per projected segment, reducing
  repeated wall-column branches while preserving band order and raster output.
  The fixed-view ABBA trial reports total renderer median −2.88% and wall-stage
  median −5.03%; exact pixels, three-style workers, all-map smoke and focused
  wall/fuzz regressions pass.
- Keep the complete Episode 1 human playthrough, original-frame fidelity,
  repeated 35-tic/60-display pacing, physical/acoustic review and second
  hardware qualification pending.

The broader Ultimate Doom objective remains active.

## 0.1.0-preview.5 — 2026-10-02

Community preview following the requested35-commit release cadence. All three
styles and PowerShell gameplay/rendering/mixing remain. [Scope and package
validation](docs/release-preview5.md); full release gates remain open.

- Catch up already-due simulation commands within a bounded pass and unchanged
  two-command window, stopping at exact replay control boundaries. All-style
  input/checkpoint/audio fixtures pass; repeated display pacing still fails.
- Add opt-in geometry-stage profiling and reproducible original-executable
  comparison fixtures. Original-game window evidence remains lossy; independent
  raw-framebuffer and moving-world parity are unqualified. Rejected wall-loop
  and output/encoding trials remain documented; defaults stay Strips/Pairs.

- Show separately counted loading feedback while map preparation/reloads remain pollable. Preserve renderer processes and propagate owned worker failures.
- Replace idle renderer pipe readers with owned PowerShell logs. Three clean loading-task upper bounds fall from about983 ms to below2.72 ms; startup is about27 seconds on the measured machine. Broader pacing remains below target.
- Recover interactive audio after producer gaps by accounting for intervals already covered by filler and applying caught-up controls on the current output clock. Ninety-six audio/save checks and three controlled recovery cases pass; final clean routes have no audio producer-backpressure waits. Acoustic/campaign qualification remains open.

- Restore key-lock, pickup and automap notices: original IWAD lettering in Classic, readable terminal lettering in Matrix and color art. All three actual Terminal/audio fixtures pass; physical/acoustic review remains open.
- Reuse immutable render resources between maps and verified resource bodies in persistent workers. Three live Classic/audio routes measure 1.54–2.03-second map loads; repeated display pacing still misses the release thresholds.
- Add optional `Start-Doom.ps1 -TerminalOutput AsyncBatch`, with bounded output ownership and resize guards. Byte/pipe tests and all-style live fixtures pass. Three paired cycles lower median p99 simulation lateness, while display-rate changes vary from−1.65% to+3.47% and no run passes all pacing gates. Strips remains the default.

Ultimate Doom campaign qualification, physical play, acoustic review, independent rendering comparisons and repeated display-pacing measurements remain open.

## 0.1.0-preview.4 — 2026-09-29

Cumulative release after 80 commits since Preview.3. Classic, Matrix and color art remain available. This is a community preview; [release scope and validation](docs/release-preview4.md).

### Fixed and added

- Reuse stationary automap discovery while the camera and relevant visible world state match; all 144 map-start comparisons match the uncached path.
- Fix the reproduced visibility-intercept zero denominator, with source-pinned regressions in the roadmap.

### Changed

- On normal, unpaused shutdown, the audio worker now waits briefly for queued Windows audio buffers to finish before closing the device. A current-source four-second E1M1 run completed all 186,480 submitted frames and drained its final 3,780 frames in 68.8 ms. This verifies clean buffer completion, not audible quality, campaign-length continuity, or player-facing audio fidelity. See the [R16 receipt](results/episode1-audio-shutdown-r16-20260929.json).

- Same-map restarts now reuse unchanged static renderer assets while preserving dynamic snapshots. One E1M1 PresentMon pair measured the reset handoff at 0.358 seconds versus 6.178 seconds on baseline; overall pacing remains below target and the single comparison does not establish a general speedup. See [the source-pinned measurement](results/renderer-same-map-reset-presentmon-20260929.json).

- A new sound from an emitter now replaces that emitter's active sound across sound categories, following Linux Doom 1.10 arbitration. Independent emitters still mix together. Deterministic mixer and production packet-path checks pass, and the current build starts the real music/effect worker cleanly under a scripted attack; audible effect quality and sustained-session playback remain unqualified.

- The PowerShell floor/ceiling sampler now carries Int64 coordinates between pixels and extracts the 64×64 flat-index bits only when reading a texel. All 120 paired fixed-view frames across two E1M1 runs and one E3M6 run match pixel-for-pixel. E1M1 fixed-state serial medians improve 10.68% and 5.70% in the two repeats; E3M6 is effectively unchanged. A full-host A-B-B-A comparison was inconclusive, so this does not establish live pacing or the 35-tic/60-display targets. See the [measurement](results/renderer-flat-texel-bit-extraction-20260929.json).
- Added an opt-in Classic `-AnsiEncoding Ansi256` path that maps Doom PLAYPAL colors to the nearest xterm 256-color entry. One same-frame measurement sends 28.65% fewer bytes than exact truecolor; live game timing is inconclusive, so `Pairs` remains the default. See the [experiment](docs/ansi-256-color.md).
- Interactive audio now advances active music and effect voices from the PowerShell output clock across short simulation-packet gaps. Pause, map resets, and explicit drains still stop that fill; deterministic headless runs remain packet-exact by default. This reduces software queue starvation under transient load but does not claim measured acoustic latency or uninterrupted full-campaign playback.
- The eleven-track Episode 1 music catalog opens its independent qualified readers through up to four PowerShell runspaces. Eager source/payload verification and read locks remain. Twenty-one focused checks pass; a warm-file-cache comparison cuts the reader-open stage median from 4.665 to 2.050 seconds (56.06%). This does not establish cold-launch or whole-game speedup.
- Dense renderer snapshots now cache fixed-point actor projections for workers, and each worker skips sprites outside its output stripe. Serial/worker pixels remain exact in exercised Classic, Matrix/Katakana and AnsiArt/Katakana scenes. E3M6 sequential worker CPU improved in two reversed-order pairs; E1M3 timing remained inconclusive, and this does not qualify 60 Hz presentation.
- Packed per-map BSP geometry reduces repeated object lookups in the PowerShell renderer, and engine-bundle publication is atomic before workers load it.
- Fixed-point visibility math now avoids per-intercept and sight-bound wrapper allocations while preserving tested arithmetic. Its paired E3M6 replay lowered the uninstrumented median by 3.88%; p95 did not improve, so this does not qualify the 35-tic goal.
- The launcher now rejects stale or unqualified music reports before opening Windows Terminal. It validates report metadata and source/runtime pins; the audio worker still verifies full payload hashes, and simulation startup still matches the score lumps to the active IWAD.

## 0.1.0-preview.3 — 2026-09-28

### Added

- Optional prepared-music playback through `Play.ps1 -MusicCatalog`. PowerShell synthesizes and mixes the score; users prepare catalogs from their own IWAD and soundfont. Missing catalogs fail before launch, and `-MusicCatalog` cannot be combined with `-Silent`. Music remains opt-in and is not bundled.
- A source-inclusive Windows ZIP with a per-file manifest and separate SHA-256 checksum asset. The game IWAD, soundfont, research PDF and generated recordings are excluded.

### Changed

- Refined Doom-style rendering with integer-column wall rays, integer-row wall sampling, fixed-point plane and actor projection, sky sampling, sprite patch-column rules and wall-silhouette clipping. These changes improve specific reference comparisons; independent original-executable parity remains unmeasured, and the exact E1M1 pre-placed Gibs-through-wall sighting near the blue armor remains unreproduced.
- Reduced selected renderer allocations and optimized the PowerShell music mixer while preserving tested output. The 35-tic/60-displayed-frame goal remains unverified; one bounded Classic E1M1 run reached 34.959 simulation tics/sec and 59.67 Terminal updates/sec, which is not a monitor-presentation measurement.
- Warmed intermission backgrounds before their first visible frame and expanded source-pinned campaign, save/audio-worker, renderer and soundtrack checks.

### Fixed

- Corrected upstream arithmetic and angle-comparison behavior used by movement, weapons and homing actors; the E1M2 chainsaw-attack crash now passes a focused real-world hit regression.
- Fixed reproduced actor visibility leaks and renderer range/plane-depth cases; broader scene differences and other unverified reports remain.
- Made prepared-music source checks accept identical PowerShell text across LF/CRLF checkouts while continuing to reject altered source content; verified clean-package audio startup on PowerShell 7.6.6.

### Qualification

- All 36 Ultimate Doom maps pass load/simulation/render smoke checks. Ordinary-input normal exits are independently verified for E1M1–E1M4; the complete E1 human playthrough is pending.
- The retained HMP E1M1 route driver passes again on current source in 1,560 commands. A separate maximized, no-audio PresentMon replay measured 47.73 display transitions/sec and 34.977 active tics/sec, but its older fixed input ended at `ReplayEnd` on E1M1; this is timing evidence, not route completion or a 35/60 FPS qualification. Repeated paired full-host trials remain open.
- Eleven Episode 1 loops are prepared locally. All nine Episode 2 map-track names have loop qualifications: D_E2M1–D_E2M3 and D_E2M7–D_E2M9 use two-period complete-state proofs, while D_E2M4–D_E2M6 use independently matching three-period outputs. D_E2M1–D_E2M4 and D_E2M6–D_E2M9 add eight byte-distinct payloads; D_E2M5 is byte-identical to D_E1M7. D_E3M1 and D_E3M4 are qualified as exact MUS/soundfont-hash aliases of D_E2M9 and D_E1M8. D_E3M2 adds a byte-distinct score with a 234.54-second period and a two-period complete-state proof; the independent opening PCM matches, and six reader/mixer, ten actual waveOut worker, fourteen map-selection and two-second host checks pass. The D_E3M2 host completed 85,680 of 86,940 submitted frames before shutdown with a 1,260-frame canceled-tail upper bound and no starvation or rebuffer. The D_E3M1/D_E3M4 aliases also have their own map-selection and host checks. D_E3M3 and D_E3M5 have complete-state recurrence proofs with 488.714-second and 150.857-second periods and matching 50- and 66-voice boundary states. D_E3M5 passes six reader/mixer, ten worker, fourteen map-selection, and two-second actual-host checks; its host returns all 86,940 submitted frames, with one queue-empty observation after the final packet. Existing E2M4–E2M6 short host checks each reported one post-final-packet queue-starvation observation; E2M7 returned every frame; E2M8 completed 85,680 of 86,940 submitted frames with a 1,260-frame tail bound; E2M9 completed 84,420 of 86,940 with a 2,520-frame bound. E2M8/E2M9/E3M1/E3M2/E3M4 had no starvation or rebuffer. All Episode 3 map-track names are qualified. D_BUNNY now passes a 62-second complete-state loop proof plus the actual Finale.Update transition, qualified catalog playback and waveOut worker checks; D_INTROA has finite-score evidence but is not called by current Ultimate Doom code. These short checks do not establish full-campaign playback, acoustics or sustained queue timing.

- D_E3M6–D_E3M9 now have complete-state loop qualifications and map-selection checks. D_E3M7 passes reader/mixer and actual-worker checks plus a clean two-second host start; D_E3M8 returns 85,680 of 86,940 frames with a bounded shutdown tail; D_E3M9 returns all 86,940 frames in its short host check. Longer D_E3M6 runs still show intermittent packet-queue starvation, so continuous music remains open.

This is a community test preview, not full campaign certification. One complete human Episode 1 playthrough remains pending; Doom II, Final Doom, MyHouse, general PWAD compatibility, full-campaign audio continuity, original-executable visual parity and the 35-tic/60-display targets are not claimed.

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
