# R20 development candidate — October 2, 2026 (UTC)

`0.1.0-dev.20261002.r20` is a local playable handoff for the complete Episode 1
human route in [the playthrough guide](episode1-playtest.md). It adds pollable
map loading with separately counted feedback, owned renderer logs and realtime
audio recovery to the frozen [R19 scope](candidate-r19.md). Gameplay, rendering,
terminal encoders and mixing remain PowerShell. Classic, Matrix and color art
remain available; output defaults remain Strips/Pairs.

The source-inclusive archive is built from committed inputs by
`scripts/Build-PreviewPackage.ps1`. Its manifest identifies each payload and
source commit. The package-validation receipt will record extracted checks;
this scope document does not predeclare them successful. The intended archive
is under `local/episode1-r20-package`, with a fresh extraction under
`local/episode1-r20-extracted`. R19 and its input/save/report paths stay available
for comparison. WADs, soundfonts, prepared music, tools, media and the research
PDF are excluded; provide the user-owned IWAD and optional music catalog.

Before packaging, all-style worker reload/fault checks preserve compared images
and processes. Ninety-six focused audio/save checks pass, and controlled
300/700 ms producer-gap tests recover below 30 ms processing age. Realtime
audio applies caught-up events on the current output clock; emitter replacements
may coalesce, and past sounds cannot be reconstructed. Packet-exact offline
playback retains its independent PCM checks. [Recovery evidence](../results/audio-realtime-recovery-20261002.json).

Three clean Classic/audio routes retain every command and submitted frame,
with zero audio producer-backpressure waits, median packet-processing ages
65–85 ms and startup 26.37–27.61 seconds. Global Terminal display events remain
52.6–53.8/sec; early tic delays and one sub-34.9 active-rate result remain.
[Loaded measurements](../results/audio-recovery-loaded-classic-20261002.json)
and [actual WGC/audio footage receipt](../results/audio-recovery-live-20261002.json)
keep timing and recording evidence separate. Neither qualifies acoustics,
physical input, distinct optical game frames or complete human campaigns.

This development candidate does not close the Ultimate Doom release gates.
Preview.4 remains the public release. Local packaging does not reset the
35-commit public release count. Continue the whole human E1 secret-map/finale
route, remaining campaigns, independent moving-world fidelity, broader pacing
and physical/acoustic/second-hardware qualification in the [roadmap](roadmap.md).
