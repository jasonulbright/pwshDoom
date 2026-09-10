# Experiment protocol

## Stages

1. **Inventory:** CPU, memory, display mode, GPU driver, OS, Terminal, exact PowerShell executable. Avoid claiming sustained hardware throughput from specifications.
2. **Headless encoding:** generate deterministic indexed images, encode using PowerShell, and record generation/encoding duration and bytes per frame. Do not include terminal output in these timings.
3. **Pre-encoded output:** replay already encoded changing frames in an actual Windows Terminal window. Measure write duration and completed-write rate with synchronized output on/off. Never label this displayed FPS.
4. **Presentation:** attempt independent process presentation telemetry. Record whether counters describe application presents or displayed presents. Do not use a screenshot to infer FPS, and do not silently substitute the task's embedded terminal for Windows Terminal.
5. **Visual verification:** inspect representative ANSI and Sixel frames; verify sizing, colors, and that updates replace rather than scroll the image.
6. **Integration direction:** compare total frame-generation cost with output cost; make a bounded recommendation based on measured evidence.

## Workloads and controls

Start with 160x100 and 320x200 logical pixels, a 16-color palette, coherent textured images, and a deliberately difficult high-entropy pattern. Treat the palette size as an experimental variable: real Doom has a 256-entry palette. A 16-color success is not a 256-color result.

Compare ANSI half-block and Sixel presentation on the same logical image. Report the character grid and image display size; do not imply equal physical size where they differ. Use a separate benchmark window, finite durations, warmed encoders, and per-frame timings. State whether encoding is performed live or replayed from memory.

Explicitly select the console output encoding to match emitted bytes, record the active and original code page, and restore the original encoding afterward. The first batch initially missed this requirement; its terminal runs were superseded and rerun using UTF-8. An environment assumption must not stand in for a measured precondition.

Use repeated measurements where practical. Interleave alternatives to reduce time/order effects. Capture screenshots outside measured runs. Record other visible activity as a possible confounder. Keep normal antivirus settings unchanged, even when upstream recommends disabling them.

The initial experiment is a terminal transport and encoding study, not a faithful Doom simulation benchmark. It measures no monster AI, physics, audio, WAD streaming, or complete campaign behavior.

## Metrics

- generation and encoding milliseconds/frame; median and p95;
- encoded UTF-8 bytes/frame and estimated bytes/second at target rates;
- completed writes/second and write-call duration;
- requested pacing versus observed loop pacing;
- independent presentation intervals if available;
- screenshot evidence of correctness, recorded separately from timing;
- exact parameters, executable version, timestamps, failures, and limitations.

Do not sum independently pipelined timings and call the reciprocal measured FPS. Use end-to-end measurement for end-to-end claims. No universal maximum is established by a small benchmark suite.
