# Preview.4 release scope

September 29, 2026. The user requested a new release whenever at least 35 commits accumulate since the previous release; 80 commits followed Preview.3 before this preparation. This packages the current PowerShell implementation as a playable community preview. Ultimate Doom acceptance gates remain open.

## Capabilities

Classic renders a 320×200 source image as truecolor half-blocks. Matrix and color art use 160×50 character cells, with katakana or ASCII. All share gameplay and rendering. Menus select four episodes and five skills; pause, six save slots, confirmed overwrite/load, automap, input preferences and audio volume/mute are implemented. Save reconstruction validates version, IWAD, schema, graph checksum and bounded values before replacing a session.

PowerShell decodes/mixes effects, synthesizes MUS/SF2 music offline, and mixes qualified prepared streams during play. Standard Windows waveOut supplies device playback. Users supply the IWAD, soundfont and optional prepared catalog; the ZIP includes none of them.

## Changes from Preview.3

The output clock continues active audio across short simulation-packet gaps. Normal unpaused exit drains submitted device buffers for a bounded interval. Music readers open in bounded runspaces; runtime compatibility accepts the same major/minor PowerShell release. Rendering caches sector-plane data, actor projections and packed BSP geometry, improves fixed-point flat sampling, and reuses same-map assets. Stationary automap discovery is reused only when its relevant view/world key matches. Experimental Classic Ansi256 reduces bytes using an approximate palette; truecolor remains default.

See the [changelog](../CHANGELOG.md), [audio evidence](audio.md), [renderer findings](rendering-fidelity.md), [performance measurements](performance.md), and [automap analysis](automap-discovery-performance.md). Rejected experiments remain in the ledger.

## Validation and limits

Fresh release checks and package hashes are recorded in `results/preview4-validation-20260929.json` in the source repository. The ZIP omits large research results; use the repository receipt for raw-report fingerprints. Packaged preflight and an actual-device startup are checked from an extracted archive before publication.

Map-start smoke, controller transitions and boss fixtures differ from ordinary-input completion. E1M1–E1M4 have historical independently qualified normal routes; current E1M3 checkpoints are stale and its driver has stalled without a reproduced product defect. The complete human Episode 1 route, other episodes, secret routes and ordinary boss victories remain open. This release adds no map completion claim.

The 35-tic/60-display goals are unqualified. Prior isolated renderer and music-reader speedups are not whole-game improvements. One loaded E3M6 run reached 30.932 active tics/sec, and one bounded E1M1 sample reached 59.67 terminal updates/sec; these are different workloads and neither proves 60 distinct displayed frames/sec. Audio queue continuity is not acoustic quality or latency. Original-executable pixel/demo parity, physical keyboard play, the 1080p/DPI matrix and a second hardware configuration remain open.

A full Ultimate Doom release candidate requires the [roadmap gates](roadmap.md). Doom II, MyHouse, multiplayer and general PWAD compatibility remain later scopes. The [article draft](article-draft.md) compares architectural alternatives without claiming unmeasured competitor rankings.
