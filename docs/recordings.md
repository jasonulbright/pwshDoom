# Katakana and actual screen recordings

The next session build adds three recordings of E1M1 → intermission → E1M2 in Classic, Matrix and AnsiArt. See [campaign session recordings](campaign-session.md#actual-terminal-recordings) for the current results. The two E1M1-only captures below remain historical evidence for the earlier build. The exporter now also accepts successful full-session replays and checks visible duration against the wall clock, preserving map handoff pauses in the viewing copy.

The user requested Japanese characters in both art modes and screen recordings of the finished effects. The game now defaults to half-width katakana in Matrix and AnsiArt. ASCII remains selectable. Gameplay, rasterization, interpolation, and terminal character conversion still run in PowerShell.

## Glyphs and font

The shared alphabet definition is in `src/CharacterCodec.ps1`. Matrix uses 45 half-width katakana letters plus digits; AnsiArt uses a katakana brightness ramp and Japanese-shaped edge marks. Neither emits voiced combining sequences, full-width letters, emoji, or normalization that would change the allocated cell width. [Unicode's named characters](https://unicode.org/charts/nameslist/n_FF00.html) and [Unicode 17 width data](https://www.unicode.org/Public/17.0.0/ucd/EastAsianWidth.txt) document the selected range. The terminal grid stays 160×50, including the sampled block HUD.

MS Gothic is present on the test machine and is the default for the Japanese styles. At 12 pt in maximized Terminal it reports 430×85 cells, versus the earlier Cascadia Mono grid of 382×71. Individual live-console tests observed one-column advancement for all 61 distinct symbols in the combined alphabet/HUD probe. The regular startup uses a much cheaper aggregate check: 61 symbols must advance 61 columns. This checks cursor placement, while actual captured frames separately verify that visible Japanese characters appear. It does not certify every font or terminal.

```powershell
.\Start-Doom.ps1 -Style Matrix -Maximized
.\Start-Doom.ps1 -Style AnsiArt -Maximized
.\Start-Doom.ps1 -Style AnsiArt -GlyphSet Ascii
```

## Recording implementation

`scripts/Record-DoomReplay.ps1` launches one finite replay in an isolated Terminal process, selects that process's game window, and passes its actual window handle to FFmpeg's `gfxcapture` source. It records only that window, with no microphone or system audio. The game itself is still silent. A three-second optional post-report delay lets the recorder finalize cleanly; the default interactive launcher has no delay.

[FFmpeg documents `gfxcapture`](https://ffmpeg.org/ffmpeg-filters.html#gfxcapture) as Windows.Graphics.Capture producing D3D11 frames. We pass those frames to NVENC for external video encoding. The capture ceiling is 240 arrivals/sec; the MP4 is resampled to 60 FPS. This avoids imposing a second 60 Hz cap on compositor arrivals near the game's 60 Hz cadence, but it does not guarantee one unique game frame per video frame. Capture timestamps and encoder logs are retained, including duplication counts. Movie FPS is not a replacement for PresentMon or an optical/frame-identity experiment.

The external FFmpeg 9.0.1 essentials build came from Gyan's Windows builds linked by [FFmpeg's download page](https://ffmpeg.org/download.html). Its archive checksum was checked against the publisher's checksum. The GPLv3 binary remains in ignored `local/tools/`; it is not distributed with, or loaded by, the Doom engine. `results/recording-tool.json` records its origin. This external recorder may use GPU algorithms without changing the PowerShell game boundary.

The initial GDI `gdigrab` test encoded a valid MP4 but produced black window frames; it is retained as a failed probe. A first WGC attempt using `scale_d3d11` to NV12 failed to allocate an output texture (`80070057`). Passing captured D3D11 frames directly to NVENC succeeded and showed the actual terminal, katakana, scene, and HUD. These failures were not treated as successful demonstrations. OBS was detected but its settings were not changed and it was not launched.

```powershell
pwsh -NoProfile -File scripts/Record-DoomReplay.ps1 -Style Matrix -Maximized -OutputPrefix local/recordings/my-matrix-run
pwsh -NoProfile -File scripts/Record-DoomReplay.ps1 -Style AnsiArt -Maximized -OutputPrefix local/recordings/my-color-run
```

Run sequentially with no existing Terminal process for unambiguous window attribution. A fresh prefix is required. Pass `-Ffmpeg C:\path\ffmpeg.exe` if using another local build with `gfxcapture`/NVENC support. Each run retains the untrimmed MP4, FFmpeg log, game JSON and recording JSON. Hardware/font/display differences affect fit, capture support, and timing. Recorded-run timing must be identified separately from clean performance measurements. The earlier five PresentMon ASCII captures remain historical results, not katakana benchmarks.

## Completed recordings — 2026-09-10

Both captures complete the same E1M1 route with 1,560 simulation tics, five kills, 75 health, no error and no viewport pause. They ran sequentially with the same runtime source, with no other study benchmark or video export running concurrently. The two viewing copies are actual Terminal footage, not offline framebuffer animations. They are silent because game audio remains unimplemented.

| Style | Viewing copy under `local/recordings/` | Duration | Active simulation tics/sec | Completed console writes/sec |
|---|---|---:|---:|---:|
| Matrix / Katakana | `matrix-katakana.mp4` | 44.8 s | 34.918 | 60.009 |
| Color art / Katakana | `ansiart-katakana.mp4` | 45.0 s | 34.920 | 60.014 |

Both files are 1280×800 H.264/yuv420p at an encoded 60 FPS. Full decode counted 2,688 and 2,700 frames respectively. These frame counts include any capture/resampling duplicates; no new PresentMon result or unique displayed-frame-rate claim is made here. The game reports are [Matrix](../results/recorded-matrix-katakana-game.json) and [AnsiArt](../results/recorded-ansiart-katakana-game.json). Recording/export parameters, video hashes and inspection findings are in [the recording manifest](../results/katakana-recordings.json); [the source manifest](../results/katakana-sources.json) fixes the tested runtime bytes.

The original `*-katakana-full.mp4` files retain startup, window chrome, margins and the short return to the console. `scripts/Export-DoomRecording.ps1` makes separate viewing copies. On this machine the observed game rectangle is X=1080, Y=304, width=1280, height=800: 160×50 cells at 8×16 pixels, centered at column 135 / row 17, below 32 pixels of Terminal chrome. These coordinates are specific to this captured window and font, not universal crop defaults.

```powershell
pwsh -NoProfile -File scripts/Export-DoomRecording.ps1 -InputPrefix local/recordings/matrix-katakana-full -OutputFile local/recordings/my-matrix-view.mp4 -X 1080 -Y 304 -Width 1280 -Height 800
pwsh -NoProfile -File scripts/Export-DoomRecording.ps1 -InputPrefix local/recordings/ansiart-katakana-full -OutputFile local/recordings/my-color-view.mp4 -X 1080 -Y 304 -Width 1280 -Height 800
```

The exporter checks the original hash and successful stable-viewport game report, scans contrast at 10 Hz inside the inspected game rectangle, checks the detected duration against the game clock, then crops and trims. It keeps 0.1 s before the first high-contrast sample and 0.2 s after the last. Matrix retains original seconds 25.0–69.8; AnsiArt retains 24.0–69.0. The copy is a lossy H.264 re-encode with no scaling, speed change, added tint, sharpening or shader. Both copies were decoded end to end and inspected at 10, 23 and 43 seconds: visible Japanese characters, scene and HUD inside the crop, no missing-glyph squares or outside windows in those samples. Dark scenes and the green HUD still lose readability; sampled inspection does not certify every frame or human playability.

The updated codec passes 144 serial/partition cases across both styles and both alphabets, eight independent brightness/edge probes, six invalid-dimension guards and ten viewport cases. Each katakana style also passes five real worker views: 320,000 source pixels and 35 encoded strip comparisons. Classic's 24 ANSI round trips pass. [The final validation record](../results/katakana-validation.json) records source hashes, syntax checks, result hashes and process cleanup. The recording request is also retained in `AGENTS.md` for future live effect tests.
