# Intermittent recorder shutdown failure

September 19, 2026. This concerns the external FFmpeg recorder. A separate
candidate now tests a process-lifetime module pin; game code is unchanged.

## Evidence

The Classic second and AnsiArt third palette recordings complete gameplay,
then FFmpeg exits with `0xC0000005` after acknowledging the `q` shutdown command.
Scoped audio capture exits successfully. Classic third and Matrix third succeed
with the same binary, including full movie decoding and capture audits. Retain
every failed file/log; a successful game report does not prove successful media.

`results/capture-shutdown-windows-events-first.json` preserves Windows
Application Error events for the exact project recorder executable. Events at
12:51:42 and 12:55:25 local time name `graphicscapture.dll_unloaded`, version
`10.0.26100.9278`, exception `0xc0000005`, offset `0x1115c`. These coincide with
the failed recordings. This identifies an unloaded-module failure, but is not
a stack trace and does not prove the exact callback/release ordering.

## Source inspection

The local FFmpeg 9.0.1 `libavfilter/vsrc_gfxcapture_winrt.cpp` already loads
`graphicscapture.dll` into an owning module handle in `load_functions`. Its
comment identifies crashes when that library is freed during WinRT cleanup.
`gfxcapture_uninit` joins the WGC thread, releases D3D/buffer references, then
deletes the context owning the module handles. Session closure removes event
handlers, closes the session/frame pool, and requests asynchronous dispatcher
shutdown before WinRT teardown.

The existing lifetime mitigation and unloaded-module crash reports support
testing whether this DLL must remain loaded until recorder process exit. They
do not establish that context deletion is the offending release. Do not change
Doom's engine, scheduling or palette behavior to compensate for this failure.

## Candidate experiment

Preserve the current binary and patched source by hash before building a
separate candidate. Extend the external-recorder build recipe to pin the
already-loaded capture module using `GetModuleHandleExW` with
`GET_MODULE_HANDLE_EX_FLAG_PIN`. Identify the already-owned module by address
to avoid ambiguous same-name lookup. Fail explicitly if pinning fails; preserve
the original timestamp-origin diagnostic.

Microsoft documents that the
[PIN flag retains a module until process termination](https://learn.microsoft.com/en-us/windows/win32/api/libloaderapi/nf-libloaderapi-getmodulehandleexw),
regardless of subsequent `FreeLibrary` calls. This intentionally extends the
DLL lifetime within the recorder process; it is not a machine-wide setting.

After the user's explicit resume, run repeated finite shutdown tests against an
owned test window, preserving recordings and exit status. Cover explicit `q`
and target-window closure. Then complete the full AnsiArt
palette replay with independent checkpoints, source/media checks, full movie
decoding and resource cleanup. A single successful retry cannot establish an
intermittent fault fixed. If it recurs, obtain a scoped crash trace before
proposing another change.

The original binary/source remain intact. `results/capture-module-pin-preparation-first.json`
pins that baseline and the verified source archive. The build recipe accepts
`-SourceDirectory FFmpeg-n9.0.1-pinned -PinCaptureModule`; extract a fresh copy
of the archive into that immediate child of the prepared build root first.
It logs `PWSHDOOM_GFX_MODULE_PINNED=1` after successful address-based pinning,
and fails explicitly if the call fails. No system setting changes.

`results/capture-module-pin-build-first.json` records a successful117.645-second
build using the installed Visual Studio18.10 toolchain. Candidate SHA-256:
`A08B6F7EF84E0C5F04BA5236CAFB39E14226E475C44661950266B2D3146AB7D4`.
This differs from the earlier baseline toolchain, so binary comparisons cannot
attribute a behavior change solely to the pin.

`scripts/Test-CaptureShutdown.ps1` creates finite owned animated test windows,
alternating six explicit recorder quits and six target closures per binary.
Both the candidate and original binary pass all twelve trials, including
complete movie decoding and window cleanup. The candidate reports the pin in
all twelve runs. Receipts are `results/capture-pin-lifecycle-first.json` and
`results/capture-baseline-lifecycle-first.json`; media and logs stay local.
The short test does **not reproduce the historical failure**. This qualifies
the two shutdown paths on this bounded workload; it does not establish the
pin as a proven fix or rule out another lifetime defect.

The first full AnsiArt candidate recording succeeds and passes all55 integration
checks,52 checkpoints, full movie decoding and owned-resource cleanup. All five
sampled effect frames were visually inspected. The game sources are unchanged.

## Disposition

**Could not reproduce in follow-up trials; cause unconfirmed.** The original
failures remain real recorded evidence. The optional pin is an experimental
mitigation, not a proven fix and not a new game dependency. Do not spend further
release work trying to prove this external intermittent fault absent. Reopen
if it recurs during useful game recording. The user explicitly redirected work
toward game code after this recorder investigation grew beyond its value.
Continue campaign progression and concrete rendering defects; successful
recordings support that work without requiring general recorder certification.
