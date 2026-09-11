# Doom made of characters

Implemented 2026-09-10 as optional display modes over the existing PowerShell engine. This is an E1M1 prototype with the same campaign, audio, menu, and fidelity limitations as Classic. It is not a new engine or a GPU shader.

## Play

```powershell
Set-Location C:\projects\pwshDoom
.\Start-Doom.ps1 -Style Matrix
.\Start-Doom.ps1 -Style AnsiArt
.\Start-Doom.ps1 -Style Classic
```

Choose one command. Add `-Maximized` for a maximized window, or `-Replay .\results\e1m1-route.json -Seconds 90` for the finite input-only demonstration. The replay requires the matching Ultimate Doom IWAD and default skill/episode/map. WAD discovery and controls are shared with Classic. Style and alphabet selection currently happen at launch.

The character modes now default to `-GlyphSet Katakana`, using half-width Japanese characters and MS Gothic. `-GlyphSet Ascii` restores the first prototype's alphabet and Cascadia Mono. `-FontFace` overrides the choice; the selected font must be installed. The HUD remains half blocks in both alphabets. [Recordings and capture findings](recordings.md) cover the Japanese version.

| Style | Terminal cells | Default font | Representation |
| --- | --- | --- | --- |
| Classic (default) | 320 × 100 | 6 pt | Two independently colored source pixels per upper-half block |
| AnsiArt | 160 × 50 | 12 pt | Full-color brightness/edge characters; block HUD |
| Matrix | 160 × 50 | 12 pt | Green image-dependent code, falling bright leaders; green block HUD |

All three render a 320×200 source framebuffer. The character modes intentionally reduce image detail: each character summarizes a 2×4 source-pixel region. They are not lossless 320×200 presentations. The HUD is also downsampled, retaining two colors per cell rather than turning numbers into letters. `-Diagnostics` needs two extra rows. Explicit `-FontSize` overrides the default; `-Here` uses the existing tab/font. The actual image aspect depends on font cell dimensions, as it does in Classic. No 1080p hardware qualification is implied by the smaller grid.

The host centers the selected grid and pauses when it does not fit. The same active game clock drives code animation; a resize pause does not accumulate animation time. The katakana alphabet uses characters from U+FF61–U+FF9D, whose width property is half-width in [Unicode's width data](https://www.unicode.org/Public/17.0.0/ucd/EastAsianWidth.txt). It excludes voiced marks and full-width kana and is not compatibility-normalized. A live startup probe checks the complete alphabet's cursor advance before gameplay; individual glyph widths were also tested during development. Human playability and font preference still need feedback.

## What the PowerShell code does

The unchanged BSP renderer draws walls, floors, sprites, weapon, and HUD into indexed pixels. `src/CharacterCodec.ps1` then reads eight source samples per character. It does not modify that framebuffer or the simulation state.

AnsiArt uses perceptual luminance weights, a gamma-adjusted density ramp, and dominant brightness gradients for horizontal/vertical edge glyphs. Its color comes from the brightest sampled source palette entry, with a foreground gain and dim background. This favors small bright features; it is a stylistic choice rather than a photometric reconstruction.

Matrix maps mean luminance into an expanded green contrast curve. Code characters derive from a fixed spatial hash. Sparse columns carry moving bright heads and eight-cell fades; only cells under the moving code change their symbol with time. Darkness limits the brightness of rain. There is no random whole-screen reshuffle, geometry tracking, motion-vector input, or previous-frame persistence. The rain is a deterministic screen-space pattern. That is simpler to partition and keeps moving scene content from leaving a long ghost image, but it can still compete with small enemies.

The bottom 32 source rows use sampled half blocks. AnsiArt preserves the sampled palette colors; Matrix transforms them to green. The HUD receives no rain. It loses fine detail at 160 columns, so this is a readability compromise rather than an exact HUD reconstruction.

Sixteen persistent PowerShell rendering processes remain the default. Character strips align to two source columns, including with uneven worker counts. Each worker gets the same animation time and uses absolute image coordinates. The host carries that time at shared-memory offset 72; it is not inferred from worker completion order. The existing snapshot protocol, 35 Hz simulation scheduling, input path, and frame pipeline are shared.

No custom compiled encoder or shader is used. .NET supplies standard collections, UTF-8 conversion, copying, synchronization, and transport. Terminal renders the resulting text. The optional offline preview script uses GDI+ to paint already-encoded cells for inspection; it is not a game display backend or a screenshot of Windows Terminal.

## Measured results: initial ASCII version

These five historical captures belong to the ASCII prototype committed as `033b82a`; they are not measurements of the later katakana/font change. They used the same source revision, user IWAD, input route, 16 workers, and maximized Terminal. Character modes used their 12-pt default; Classic used 6 pt, all in Cascadia Mono. Actual grids were 382×71 and 688×151 respectively. Hardware/runtime match the existing study: Core Ultra 7 265K, RTX 4070 Ti SUPER, 32 GiB DDR5-7200, 3440×1440 at 165 Hz, PowerShell 7.6.5, Windows Terminal 1.24.11911.0. These are exploratory observations on one desktop, not a controlled claim that one encoder is intrinsically faster: output representation, glyph shapes, cell sizes, and physical image size differ.

| Run, in capture order | Writes/sec | Simulation tics/sec | Display transitions/sec | Dropped submissions | Display gap p95 / max, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Matrix 1 | 60.008 | 34.904 | 58.593 | 2 | 24.254 / 66.648 |
| AnsiArt 1 | 60.001 | 34.913 | 56.582 | 128 | 24.267 / 612.121 |
| Classic control | 60.009 | 34.918 | 59.765 | 3 | 24.278 / 66.673 |
| AnsiArt 2 | 60.014 | 34.920 | 57.518 | 101 | 18.265 / 1078.798 |
| Matrix 2 | 60.000 | 34.925 | 59.738 | 3 | 18.272 / 60.607 |

Every run completed the same 1,560-tic ordinary-input route with five kills, 75 health, and no error or viewport pause. The character modes keep the simulation schedule, and Matrix approaches Classic's displayed rate in its second run. They do **not** establish a steady 60 displayed frames/sec. AnsiArt has large early presentation gaps in both observations. Matrix's first run also has fewer Terminal submissions than completed writes. The responsible stage has not been isolated; assigning the gaps to the PowerShell encoder, Terminal, focus, or the compositor would be premature.

Character encoding fits within the current pipeline's measured stage budget: the per-frame slowest worker's encode-time p95 was 3.31–3.40 ms for Matrix and 4.45–4.86 ms for AnsiArt, versus 3.74 ms in Classic. These are worker-stage measurements, not total frame time; rendering/output overlap, and the maxima of separate stages cannot be added as if they were serial. Smaller output cells do not automatically imply cheaper glyph processing or smoother presentation. Worker plus simulation working sets remain approximately 3.3 GiB, excluding the host and Terminal.

Raw prefixes are `results/presentmon-matrix-prototype-*`, `presentmon-ansiart-prototype-*`, `presentmon-character-classic-control-*`, `presentmon-ansiart-repeat-*`, and `presentmon-matrix-repeat-*`. Every prefix retains capture metadata, game report, CSV, and analysis. [The comparison](../results/character-presentation-comparison.json) records these values, timing distributions, drop locations, exact input hashes, and the [source manifest](../results/character-sources.json). Regenerate it with `scripts/Analyze-CharacterPresentation.ps1`. The full first-to-last-write window is retained; large early gaps are not excluded to improve the headline.

**Visual status:** inspected offline views of the lit tic-350 room and dark tic-700 corridor. The code pattern reveals the larger scene shapes, but dark surfaces and small enemies lose detail, and small HUD labels are degraded by sampling. This remains a first playable aesthetic prototype. Human keyboard play and temporal readability still need feedback. The next display work is contrast/readability tuning and isolating the observed presentation gaps; the main release roadmap still starts with campaign progression.

## Verification and reproduction

```powershell
pwsh -NoProfile -File scripts/Test-CharacterCodec.ps1
pwsh -NoProfile -File scripts/Test-AnsiStrips.ps1
pwsh -NoProfile -File scripts/Test-RenderPartitions.ps1 -Style Matrix -Report local/matrix-partitions.json
pwsh -NoProfile -File scripts/Test-RenderPartitions.ps1 -Style AnsiArt -Report local/ansiart-partitions.json
pwsh -NoProfile -File scripts/Test-Viewport.ps1 -Style Matrix -OutputPrefix local/matrix-viewport
```

The character test independently decodes terminal control sequences and checks coverage, color ranges, duplicate writes, bounds, strip equivalence, source immutability, deterministic animation, stable HUD, and green dominance. It now runs 144 cases across both alphabets. Black, white, and two edge probes have hand-defined expected glyphs in each alphabet. It does not establish perceptual readability or prove cell width in every terminal. Add `-GlyphSet Katakana` to the worker partition tests to check the Japanese alphabet through real processes.

Actual worker tests compare five headings and seven uneven strips with a serial 320×200 reference image. Character bytes must also match encoding that reference at the requested origin and animation time. This checks the transport, strip boundaries, and style selection together. It is not vanilla renderer equivalence.

`scripts/Save-StylePreview.ps1` reads an ignored real-game capture plus `local/palette.bin`, encodes both styles, and creates local PNG/ANSI files. Its frame is user-WAD-derived and stays out of Git. It shows the actual glyph/color decisions in an offline font rendering, not measured Terminal output.

Live captures use the existing PresentMon service harness with a fresh output prefix:

```powershell
pwsh -NoProfile -File scripts/Measure-PresentMonGame.ps1 -Style Matrix -Maximized -OutputPrefix local/matrix-run
pwsh -NoProfile -File scripts/Analyze-PresentMonGame.ps1 -Prefix local/matrix-run
```

The harness requires no pre-existing Terminal process to attribute events unambiguously. Captures must run sequentially, without other study workloads. Game writes, simulation tics, and PresentMon display transitions are separate quantities. Source hashes, raw results, exact launch options, and the full write window are retained; display timing does not identify unique Doom framebuffer contents or measure keyboard-to-screen latency.

## Alternatives

Plain green half blocks would preserve much more pixel detail and require only a palette transform, but would not expose readable letters. Classic already uses truecolor ANSI; the difference here is the glyph representation, not enabling ANSI for the first time.

A Terminal HLSL effect could add glow, scanlines, or its own character conversion to the terminal texture. Microsoft's [shader sample](https://github.com/microsoft/terminal/blob/main/samples/PixelShaders/README.md) documents that route. It would execute the effect on the GPU and would need to be identified separately from these PowerShell algorithms. No shader was installed or benchmarked for this prototype.

Applying a similar effect to other games is a separate project. A framework such as [ReShade](https://github.com/crosire/reshade) offers game post-processing integration; per-game compatibility and performance would require tests. Neither that route nor this encoder makes arbitrary games run inside PowerShell. The reusable part here is an image-to-character conversion concept, while a general capture/input/audio/display integration remains additional work.
