# Game-process audio capture

`src/ProcessAudioCapture.ps1` and `scripts/Record-ProcessAudio.ps1` now record a selected Windows process tree through WASAPI into stereo PCM16 WAV at 44.1 kHz. This is external recording instrumentation; the game does not load it. The first ten-check scope test passes on this machine, Windows build 26200 and PowerShell 7.6.5. Video/audio synchronization and actual game-load capture remain to be integrated and qualified. Existing game movies are still silent.

## Boundary and sources

Windows supports selecting a PID and including that process's descendants through [process-loopback activation parameters](https://learn.microsoft.com/en-us/windows/win32/api/audioclientactivationparams/ns-audioclientactivationparams-audioclient_activation_params). The structure documentation gives build 20348 as its minimum. The [activation function page](https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nf-mmdeviceapi-activateaudiointerfaceasync) currently says 20438 in its prose; that discrepancy is retained rather than silently resolved. The tested build exceeds both. This implementation requires a 64-bit process and reports actual API failures.

The implementation was written for this repository from documented Windows interfaces. Microsoft's [ApplicationLoopback sample](https://github.com/microsoft/Windows-classic-samples/blob/main/Samples/ApplicationLoopback/cpp/LoopbackCapture.cpp) was inspected for the activation, shared PCM format and event-driven capture sequence; its repository [MIT license](https://github.com/microsoft/Windows-classic-samples/blob/main/LICENSE) was checked. No sample implementation was copied. Interface identifiers and layouts were verified against Microsoft's published SDK headers. The compiled portion consists of COM interface/PInvoke declarations, typed method forwarding and the completion callback that transfers Windows' activation result to an event. That callback cannot assume the calling PowerShell runspace on the Windows worker thread. It contains no synthesis, mixing, packet processing or WAV encoding algorithm.

PowerShell selects the process, allocates the activation blob, opens the client, drains packets, copies bytes, handles silence flags, writes WAV and records timing. Include-tree selection is fixed: there is no endpoint-wide or exclude-target fallback. Target the owned simulation PID when integrating with the game, since that process owns the audio runspace. Selecting the Terminal process could include other tabs and is unsuitable for this scope.

## First evidence

`results/process-audio-capture-first.json` retains the complete capture packet report, source hashes and output WAV hash. Two owned sibling processes render distinct quiet tones via the existing waveOut device boundary. The selected process emits 350 Hz for two seconds, then silence; its sibling emits 700 Hz for six seconds. Both complete all 264,600 submitted frames and close. A third process captures only the selected PID's tree for seven seconds.

Independent half-second spectral windows find selected-tone amplitude 999.806 PCM units, sibling-frequency amplitude 0.001015 units during the selected tone, and RMS 0.480 units during selected silence while the sibling continues. The selected-tone RMS is 706.971 units. All ten assertions pass, including source inclusion, sibling suppression below one percent, silence, WAV frame accounting, device completion, target PID and cleanup. No discontinuity or timestamp-error flags occur in this run. These results establish digital capture scope on this fixture, not physical speaker audibility, absolute latency, game-load reliability or performance isolation. The two long soundtrack synthesis jobs overlap this test.

## Timing and failure semantics

Each packet retains flags, output-frame index, device frame position, capture QPC and observation QPC. Microsoft's [GetBuffer documentation](https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-iaudiocaptureclient-getbuffer) specifies that its QPC result is converted to 100-nanosecond units; it must not be compared directly with raw Stopwatch ticks. Silence-flagged packets become zero bytes. Other captured samples are copied unchanged. Packets are released before disk writing.

The current WAV concatenates packets. It does not conceal missing intervals by silently inserting samples; flags and positions must be checked before treating that file as a continuous video-aligned timeline. The recorder limits duration to 300 seconds, supports an explicit stop file and readiness file, and rejects existing destinations. Normal completion stops capture, releases COM objects/events and finalizes WAV lengths. An activation timeout preserves pending native arguments and callback storage until the finite capture process exits, avoiding use-after-free on the Windows callback thread. It is an explicit failure, not a usable capture.

A deeper audit rejects device-position continuity: all 698 returned device positions are zero. Capture QPC increases, but packet 1 has a 10 ms excess interval and packet 609 a 25.188 ms excess interval beyond the preceding packet's sample duration. Neither carries an API discontinuity flag. Cause is unclassified; absence of flags therefore does not establish a continuous timeline. The initial rejection is retained in `music-capture-milestone-validation.json`. The follow-up integrity audit explicitly reports `ContinuousTimelineQualified=false` alongside the gap records. Scope qualification remains valid; sample concatenation is not yet suitable for an accurately synchronized movie without addressing these intervals and validating the clock model.

## Reproduce

From the repository root, in PowerShell 7:

```powershell
./scripts/Test-ProcessAudioCapture.ps1 -Output local/new-capture-test.json
./scripts/Record-ProcessAudio.ps1 -TargetProcessId 12345 -Seconds 10 -OutputPrefix local/recordings/new-audio
```

Replace the example PID with the actual owned sound-producing process. The first command creates its own finite processes and assets; it does not need game WADs. Raw audio remains under ignored `local/`. Next connect the recorder to the simulation readiness handshake, establish video timestamp alignment, then record finite gameplay with music and effects. An audio-enabled movie must not be claimed before that integration and its checks pass.
