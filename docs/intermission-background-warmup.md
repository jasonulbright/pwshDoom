# Warm the selected intermission background before play reaches it

2026-09-27. One retained 1,747-command Matrix route had 116 intermission
updates and a 131.494 ms maximum in the presentation interval after audio was
queued. The session-screen stage reached 124.412 ms on its first intermission
frame. This is one observed route, not a repeatability or audio-underrun claim;
the measurements and their limits are in [audio publication](audio-publication.md).

At 320x200, `IntermissionRenderer.DrawBackground` lazily decoded the selected
`WIMAP0`–`WIMAP2` or `INTERPIC` patch, rasterized it, and cached a 64,000-byte
indexed image on the first visible frame. `New-DoomSessionScreens` now warms
the active episode's background while constructing session screens. The
simulation repeats that selection when starting a different episode and when
loading a save. Warm-up restores the shared framebuffer after drawing, so it
does not publish or leave a partial image. Later session rendering copies the
same cached background used by the previous lazy path.

## Pixel and timing checks

[`Test-IntermissionBackgroundWarmup.ps1`](../scripts/Test-IntermissionBackgroundWarmup.ps1)
passed 48 checks across all four Ultimate Doom episodes. It verifies the
selected background for each episode, preservation of existing framebuffer
bytes, matching background buffers, and matching Stats/Next images against both
a fresh cold renderer and the pre-change
[`session-screens-render-final-20260927.json`](../results/session-screens-render-final-20260927.json)
receipt. The five alternating-order timing samples per screen prime PowerShell's
render path and the non-background patch cache before comparing the first
background raster with its warmed copy.

The full session-screen regression also renders all 24 Stats, Next, finale-text,
and finale-art states across four episodes; every output hash matches the prior
receipt. See [`session-screens-intermission-warmup-20260927.json`](../results/session-screens-intermission-warmup-20260927.json).

| Episode | Screen | Cold first-render median | Warmed first-render median | Warm-up median |
| --- | --- | ---: | ---: | ---: |
| 1 | Stats | 18.57 ms | 10.20 ms | 8.38 ms |
| 1 | Next | 13.86 ms | 5.84 ms | 8.48 ms |
| 2 | Stats | 19.21 ms | 10.72 ms | 8.01 ms |
| 2 | Next | 15.72 ms | 6.84 ms | 8.20 ms |
| 3 | Stats | 17.76 ms | 9.83 ms | 8.17 ms |
| 3 | Next | 15.37 ms | 6.66 ms | 7.99 ms |
| 4 | Stats | 17.07 ms | 9.04 ms | 7.92 ms |
| 4 | Next | 13.00 ms | 5.16 ms | 8.46 ms |

The isolated first-render medians are 7.84–8.88 ms lower after warm-up. The
roughly 8 ms cost moves into session setup, before the player reaches an
intermission. These are five small, alternating-order measurements on one
machine after JIT and patch-cache priming. They exclude process startup,
terminal presentation, audio playback, and full-game load, and do not establish
35-tic simulation pacing, 60 displayed frames per second, or uninterrupted
sound.

The simulation-worker save/load test passes all 12 checks while selecting
Episode 2 and then restoring an Episode 1 save. The full retained human input
still replays all 26,731 commands through E1M1 intermission into E1M2 with all
79 available checkpoints matching and no simulation exception. See the
[worker result](../results/save-worker-intermission-warmup-20260927.json) and
[crash-replay result](../results/episode1-human-crash-replay-warmup-20260927-r2.json).
This is regression evidence only; the one complete human Episode 1 playthrough
remains pending.
