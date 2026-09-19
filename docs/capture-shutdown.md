# Intermittent recorder shutdown failure

September 19, 2026. This concerns the external FFmpeg recorder; no game code or
recorder binary changes in this diagnostic checkpoint.

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

## Next bounded experiment

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

After the pending Codex update, run repeated finite shutdown tests against an
owned test window, preserving recordings and exit status. Cover explicit `q`
and target-window closure as appropriate. Then complete the full AnsiArt
palette replay with independent checkpoints, source/media checks, full movie
decoding and resource cleanup. A single successful retry cannot establish an
intermittent fault fixed. If it recurs, obtain a scoped crash trace before
proposing another change.

The game palette milestone is backed up at `86b3c17`; AnsiArt audiovisual
qualification remains open. No new build or live recording starts while
awaiting confirmation that the user's update is finished.
