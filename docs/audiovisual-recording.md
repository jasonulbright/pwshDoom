# Actual game-window recording with scoped audio

Classic, Matrix and color-art now have actual eight-second gameplay recordings with game-process audio. The game, rasterizer, terminal encoder and audio mixer remain PowerShell. Windows Graphics Capture, WASAPI process loopback, the existing audio-device ABI and external FFmpeg handle devices/capture/encoding. This is a recording milestone, not full soundtrack, campaign or 60-display-update qualification.

## Clock and startup contract

The host publishes an owned simulation PID and waits at an optional finite startup gate. The recorder starts video, reads that readiness file, opens process-tree audio capture for that simulation PID, and releases the gate only after audio is ready. The first simulation clock starts after the gate. A timeout fails through normal owned-resource cleanup. Preexisting Terminal windows are excluded; no user Terminal profiles are changed.

Microsoft documents [WGC SystemRelativeTime](https://learn.microsoft.com/en-us/uwp/api/windows.graphics.capture.direct3d11captureframe.systemrelativetime?view=winrt-26100) as the compositor-render QPC timestamp. [WASAPI GetBuffer](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudiocaptureclient-getbuffer) returns QPC converted to 100 ns. The inspected [FFmpeg 9.0.1 capture source](https://raw.githubusercontent.com/FFmpeg/FFmpeg/n9.0.1/libavfilter/vsrc_gfxcapture_winrt.cpp) copies SystemRelativeTime into frame PTS, then subtracts its first PTS. Our external diagnostic build logs that original value once, immediately before the existing subtraction:

```text
PWSHDOOM_GFX_ORIGIN_QPC100NS=<original first frame time>
```

This supplies a common clock without estimating the WGC origin from process launch or wall time. The source change adds only the log and braces around the existing assignment. Capture/rendering algorithms are unchanged. The diagnostic binary is not a game dependency.

`CaptureTimeline.ps1` places each unchanged PCM packet at its QPC-derived 44,100 Hz sample position relative to that origin. Gaps become explicit, reported zero-filled intervals; capture-boundary trimming is reported. One-sample rounding overlap can be adjusted and reported; larger overlap, timestamp-error flags, nonmonotonic timestamps, inconsistent counts and changed WAV hashes fail. The three retained WGC fixtures need no overlap adjustment, and their zero-filled gaps lie outside the observed gameplay interval. Missing samples are not reconstructed by inserting silence: the gap remains a capture limitation.

`Merge-DoomCaptureAudio.ps1` rejects near-entirely black footage, writes a separate timestamp-placed WAV, and muxes AAC with copied H.264 packets. It verifies every video PTS/DTS, frame count and compressed packet hash. It omits `-shortest`, which dropped four tail frames in an earlier trial. MP4 final-duration metadata can normalize; it is retained separately rather than equated with changed video frames. Successful clock placement does not measure physical screen/speaker latency.

## Measured recordings

All three run the same eight-second E1M1 route prefix with qualified E1M1 music and effects. Each finishes 279 simulation/audio packets and returns all 351,540 submitted audio frames. The only reported audio starvation observations occur after final packet 278 during shutdown. Instrumentation and the intermission synthesis job overlap these runs; they are not clean performance trials.

| Style | Full movie under `local/recordings/` | Recorded size | Video frames including startup | Console writes during game |
| --- | --- | --- | --- | --- |
| Matrix | `music-matrix-wgc-merged.mp4` | 1472×1006 | 2,373 | 432 |
| Color-art | `music-color-wgc-first-av.mp4` | 1472×1006 | 2,409 | 389 |
| Classic | `music-classic-wgc-first-av.mp4` | 2912×1452 | 2,553 | 410 |

Console writes are not distinct displayed updates; recording at 60 fps does not prove the game presents 60 distinct frames/sec. Sampled frames were visually inspected and show the actual scene/HUD in each mode. Classic includes substantial margins and does not qualify 1080p fit. Six-second viewing copies are `music-matrix-wgc-play.mp4`, `music-color-wgc-play.mp4` and `music-classic-wgc-play.mp4`; originals remain intact. Full movies and clips completely decode with picture and audio streams. Nonzero digital game audio is verified; no human-listening or microphone measurement is claimed.

Full movie SHA-256 values:

```text
Matrix  8388C9BD69DAF5DD1AC53AB6A8799D4620BE6C920FE32191B3083F6F999EC046
Color   1E2792CF6BD88D83C79FA544278C33638313E6B642BF11A8A3ECC2CA2B8A04EA
Classic 17CE6B2701AE44671E779DCA0E1930BC21E64703C4602A5063EE8A6A8EDF5335
```

`results/audiovisual-validation-fixed.json` passes 88 checks. It independently derives the entire placed PCM buffer from raw packets/QPC, checks original media hashes and process ownership, decodes all movies/clips, and retains byte-identical portable game/capture/audio/merge receipts as `results/av-*.json`. Thirteen synthetic timeline checks and ten fresh inclusion/isolation/device checks support the implementation. Local media, commercial assets and binaries remain outside Git backup.

## Failures retained

- GDI captured 42.8 seconds of black despite successful gameplay/audio. Both an extracted frame and blackdetect reject it. GDI's [av_gettime timestamp before BitBlt](https://raw.githubusercontent.com/FFmpeg/FFmpeg/n9.0.1/libavdevice/gdigrab.c) and precise UTC/QPC anchor experiment therefore do not establish a usable game capture path. Clock tests remain useful bounded unit/scope evidence, not a visual success.
- `-shortest` removed four final video frames. Removing it preserved packets; an overly strict container-duration equality assertion then failed on ten 1/15,360-second ticks of final-duration normalization. Both versions and failure receipts remain.
- Native GNU Make/Git Bash quoting broke generated inline AWK dependency commands. Moving the same expression into a file resolved the build. Failed build logs remain local.
- The first WGC merge failed on `.Sum` for an empty black-interval list under strict mode. The fixed empty-list handling recovered the retained inputs. Matrix's original recorder error remains explicit; the later successful merge does not rewrite its history.
- The first independent evidence audit used `[decimal].5`, parsed as property access under strict mode. `[decimal]0.5` fixes the test; `audiovisual-validation-first.json` retains the failure.

## Build the external diagnostic recorder

The tested host has Windows build 26200, Visual Studio 2026 Community 18.9.3 with MSVC 14.51.36231/Windows SDK, Git Bash and NVIDIA NVENC. This is a machine-specific recipe, not yet a portable installer. See FFmpeg's [MSVC platform instructions](https://ffmpeg.org/platform.html). No downloaded executables or assets are shipped in the repository.

Prepare these pinned archives under ignored `local/tools/capture-build/`, inspecting their licenses and checking SHA-256 before extraction:

| Archive / primary source | SHA-256 | Inspected license |
| --- | --- | --- |
| [FFmpeg n9.0.1](https://github.com/FFmpeg/FFmpeg/archive/refs/tags/n9.0.1.tar.gz), saved as `ffmpeg-n9.0.1.tar.gz` | `195D54BEBE1A27F84D77F4B989D193466F305B355DA92292766A69F16880B18A` | LGPL 2.1+ for this minimal configuration |
| [GNU Make 4.4.1](https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz) | `DD16FB1D67BFAB79A72F5E8390735C49E3E8E70B4945A15AB1F81DDB78658FB3` | GPL 3+ |
| [NVIDIA codec headers n13.0.19.0](https://github.com/FFmpeg/nv-codec-headers/archive/refs/tags/n13.0.19.0.tar.gz) | `86D15D1A7C0AC73A0EAFDFC57BEBFEBA7DA8264595BF531CF4D8DB1C22940116` | MIT-style NVIDIA header license |
| [pkgconf 3.0.1.post0](https://pypi.org/project/pkgconf/3.0.1.post0/), `pkgconf-3.0.1.post0-py3-none-win_amd64.whl` | `5C38B651F49A32FB117AAACA5951853452AED3834D3B7126135C831D92E055DA` | MIT |

Extract FFmpeg and headers with their archive directory names. Build GNU Make in an x64 Visual Studio developer command prompt with `build_w32.bat --without-guile`; expected result is `make-4.4.1/WinRel/gnumake.exe`. Extract the wheel as a ZIP into `pkgconf-wheel/`, preserving its hidden `.bin` directory; expected executable is `pkgconf-wheel/pkgconf/.bin/pkgconf.exe`. No Python package installation is required. An attempted MSI administrative extraction was blocked before execution; portable extraction completed the prerequisite instead.

From PowerShell 7 at the repository root:

```powershell
./scripts/Build-CaptureFfmpeg.ps1 -Output local/new-recorder-build.json
```

The script verifies prerequisite paths, applies the guarded timestamp diagnostic, prepares pkg-config/dependency files and invokes MSVC configure plus four-job GNU Make in child processes. It does not download prerequisites or change system PATH. Its explicit configure list builds gfxcapture, H.264 NVENC and minimal media components; the standard full FFmpeg build remains necessary for black detection, muxing and validation.

The actual recording binary under `local/tools/capture-build/FFmpeg-n9.0.1/ffmpeg.exe` has SHA `BD59EE9D861A9531AC289A8D9C0A02B8166A215A47D882605E372845324A1863`. A fresh-source repeat using the checked-in recipe under `local/tools/capture-recipe/` succeeds in 118.610 seconds; `results/capture-recorder-recipe-first.json` pins that separate binary and recipe. Both patched capture source files have SHA `D18C8858CB504E9630BC16A0154E2FED48A0A750269C11997614F1286A2E07E6`. Binary hashes differ; bit-for-bit reproducible compilation is not claimed. Only the first binary was used for the three live recordings.

## Record a finite run

Use fresh output paths and a valid local music catalog with its qualified payloads. Example using the installed assets and prepared tools:

```powershell
./scripts/Record-DoomReplay.ps1 -Style Matrix -Seconds 8 -ExpectedExit Duration `
  -CaptureAudio -MusicCatalog ./local/music-catalog-e1m1.json `
  -Ffmpeg ./local/tools/capture-build/FFmpeg-n9.0.1/ffmpeg.exe `
  -MediaFfmpeg ./local/tools/ffmpeg/ffmpeg-9.0.1-essentials_build/bin/ffmpeg.exe `
  -OutputPrefix ./local/recordings/new-matrix-audio
```

Use `AnsiArt` or `Classic` for the other styles. GraphicsCapture is the default backend. The final `-av.mp4` contains audio; raw `.mp4`, scoped WAV, packet metadata, original clock and errors are retained separately. Qualified music is optional; `-CaptureAudio` alone enables effects. An incomplete music catalog must not be used for a route that selects unavailable tracks. This milestone adds no map completion.
