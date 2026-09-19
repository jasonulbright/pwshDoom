# Changelog

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
