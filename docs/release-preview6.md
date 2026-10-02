# Preview.6 release scope

October 2, 2026. This cumulative source-inclusive community preview preserves
Classic, Matrix and color art. Gameplay, rendering, terminal encoding, sound
decoding, music synthesis and mixing remain PowerShell; standard Windows/.NET
APIs provide input, process coordination and device I/O. Bring your own
Ultimate Doom IWAD; optional music preparation requires your own licensed
assets.

## Renderer update

The PowerShell renderer selects eligible textured wall bands once per projected
segment, then traverses that ordered list for each wall column. A four-run ABBA
fixed-E1M2 profile retains 640 samples for each condition. The candidate matches
the baseline full-frame and all 64 worker-stripe hashes. Median total renderer
time changes from 10.033 to 9.744 ms (−2.88%), and the wall/BSP phase changes
from 6.024 to 5.721 ms (−5.03%). Total p99 changes −4.20%; wall p99 changes
−6.42%. Median thread-local managed allocation is flat within0.11%.

This is a serial 16-stripe measurement on one fixed Classic view. It is not a
full-host frame rate, concurrent-worker latency, displayed-frame count, or
general map speedup. The [trial receipt](../results/wall-band-preselection-trial-20261002.json)
retains source, harness, run hashes and limits.

## Qualification completed for this renderer change

The integrated source passes all36 Ultimate Doom map-start smokes with35 idle
tics and two nonblank serial headings per map. Classic, Matrix and AnsiArt each
match 16 production worker strips across five E1M1 headings: 320,000 compared
pixels per style and zero differences. The focused renderer suite passes 20
masked-wall ordering checks, 20,023 signed wall-column wrap inputs, 7,029,760
vertical wall-sampling comparisons, 20,049 wall-U comparisons (11 reference and
candidate errors match), and122 fuzz checks. See the [integration receipt](../results/wall-band-renderer-integration-20261002.json).

These checks establish map loading and internal serial/worker rendering parity;
they do not complete routes, qualify campaign progression, or prove fidelity to
an independent original-game framebuffer. No new gameplay or audio behavior
was changed in this preview. Preview.5 menu, save/load, and digital-audio checks
remain the latest broader session evidence; speaker quality, long campaign
continuity and latency under full load remain open.

## Release limits

This is a playable preview, not the fully qualified Ultimate Doom release.
Ordinary-input completion remains open for the full Episode 1 route, including
the E1M3 secret path through E1M9, its return to E1M4 and the E1M8 boss/finale.
The clean 35-tic simulation and 60-distinct-display gates, independent moving-
world/original framebuffer comparison, physical keyboard/DPI/resize testing,
acoustic review and a second hardware configuration also remain open. The
[human playthrough guide](episode1-playtest.md) contains the complete route and
fresh local paths. Completed map smoke and terminal writes are not route or
optical display evidence.

The package manifest records its exact source commit and every payload hash.
The public release and package-validation receipt are maintained in the
repository; commercial IWADs, soundfonts, prepared music, local recordings,
tools and the research PDF are excluded from the ZIP.

## Extracted package verification

The Preview.6 archive was built from clean source commit
`0145d751a6f846114eaa6f243296086a3c71dccb`. Its 1,819,451-byte ZIP contains
569 manifest-pinned payload files; every extracted file hash and the adjacent
`SHA256SUMS.txt` entry match. The package prerequisite check passes against the
locally licensed Steam IWAD. The extracted package also passes all36 map-start
smokes (35 idle tics each) and all three five-view, 16-worker parity runs:
320,000 compared pixels per style, zero differences. The source-pinned
[package-validation receipt](../results/preview6-package-validation-20261002.json)
records the hashes and limits. These package checks still do not qualify
ordinary-input campaign completion, live pacing or original-framebuffer
fidelity.
