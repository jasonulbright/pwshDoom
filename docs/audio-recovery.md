# Audio recovery after producer stalls

The playback worker now rebuilds a two-packet reserve after observing an empty running device queue. A lone recovery packet is released after a 100 ms fallback measured from the first nonempty recovery batch observed by the worker. Recovery pauses/restarts the standard Windows waveOut device; it does not reset the device, discard packets, alter PCM, or synthesize replacement samples. Gameplay, synthesis and mixing remain PowerShell.

This fixes recovery behavior. It does not eliminate blocking simulation, screen drawing or map loading, and is not a claim of uninterrupted audio.

## Isolated recorded route

Three sequential Matrix trials replayed the same 1,747 commands and eight checkpoints with the three-track prepared music catalog. No other study synthesis, build or test ran during each capture. System activity and capture overhead were not controlled, and these single trials are not a statistical performance comparison.

| Trial | Active empty-queue observations | Packet numbers | Largest mix block, ms | Largest submission age, ms | Console writes | Wall seconds |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| Existing worker | 4 | 1558, 1674, 1678, 1680 | 68.296 | 312.899 | 3,041 | 52.414 |
| First recovery implementation | 2 | 1674, 1684 | 86.360 | 195.910 | 3,027 | 51.929 |
| Corrected recovery deadline | 3 | 1558, 1674, 1737 | 43.590 | 276.127 | 3,023 | 51.865 |

Every trial consumes all commands, matches all checkpoints, passes 36 recording-evidence checks and returns all 2,201,220 submitted audio frames. Submitted PCM has the identical SHA-256 `DB35F5D34C9206B8D47126FEF57070EB6D10BD0D3D3A302BC11269666288AD63` in all three. That proves submitted sample identity for this route, not timely playback or identical captured sound. Each also observes the empty queue after final packet 1746; the table excludes that shutdown observation explicitly.

The baseline has no early-game starvation. At sequence 1559, intermission entry takes 99.87 ms and snapshot publication 131.29 ms. At 1675, map construction takes 936.16 ms before the later renderer asset handoff. These measured costs can outlast the current four buffers of 1,260 frames each at 44,100 Hz, approximately 114 ms maximum coverage. They explain why a reserve policy alone cannot resolve transition gaps. One isolated trial does not prove previous early-game stalls were exclusively caused by concurrent preparation.

The corrected route records two reserve restarts: four queued packets after sequence 1562 and two after 1739. The reserve waits are 110.955 and 16.153 ms respectively. The 100 ms fallback is checked by the worker loop, not a hard real-time upper bound; filling/mixing and scheduling can delay a check. The map epoch reset clears the other recovery state, and final queue exhaustion remains pending shutdown. Consequently recovery-entry and restart counts need not match.

## Tests and retained failure

`Test-AudioRebuffer.ps1` sends seven distinct literal PCM packets through the actual device. It deliberately drains the queue, verifies holding one packet and restarting with two, then verifies release of a lone final packet. It independently constructs the expected sample sequence and requires exact PCM hash, all 8,820 frames returned, no canceled tail or stale packets, and clean closure.

The first implementation started its fallback at queue exhaustion. A new 180 ms producer-gap case failed: its timer expired before the first recovery packet arrived. That failure is retained in `results/audio-rebuffer-delayed-first.json`; the exact first worker is retained in `results/audio-rebuffer-first-worker.ps1.txt`. The corrected implementation starts the fallback only after observing queued recovery data. Both zero-gap and 180 ms-gap cases pass all seven checks in `audio-rebuffer-fixed.json` and `audio-rebuffer-delayed-fixed.json`.

The corrected worker also passes ten music/control/independent-PCM checks, six effects-runspace checks and four volume checks. These results are `music-audio-rebuffer-fixed.json`, `audio-runspace-rebuffer-fixed.json` and `audio-volume-rebuffer-fixed.json`. No music synthesis or prepared-loop source changed.

## Recordings and reproduction

Full game, recording, audio, merge and pre-run source receipts for `music-route-isolated-first`, `music-route-rebuffer-first` and `music-route-rebuffer-fixed` are copied byte-identically into `results/`. Raw audiovisual files remain in ignored `local/recordings/`, outside the Git backup. The corrected movie SHA-256 is `62F2CECFD133AEA4AD25E5C6C053DD371819399A012C9B8FDBA954AAB24DEB46`; its real-time transition excerpt is `music-route-rebuffer-fixed-transitions.mp4`, SHA-256 `3099D7BB0C6C13A4F9F09876487627818122F29294D534ADFAD329B573C47A83`.

The movie and excerpt decode successfully. Sampled intermission and E1M2 frames were visually inspected: block labels remain recognizable but low-contrast in Matrix, and gameplay retains katakana. This is not a human listening or physical speaker/display synchronization test.

Follow [campaign music](campaign-music.md) for the recorded route command and source snapshot requirements. Use fresh report paths:

```powershell
./scripts/Test-AudioRebuffer.ps1 -ProducerGapMilliseconds 180 -Output ./local/my-rebuffer.json
./scripts/Analyze-AudioRouteTiming.ps1 -GameReport ./local/recordings/my-music-route-game.json `
  -Output ./local/my-route-timing.json
```

The timing analyzer first requires six timing arrays and consumed audio packets to align one-to-one with all simulation tics. It retains windows around empty-queue observations, source/report hashes and separate timing summaries. Queue polling is not hardware telemetry; submission age is not acoustic latency, and console writes are not displayed FPS.

Next investigate map/UI work before audio packet publication. The current loading pause begins after `DoomGame.Update` has already constructed the new world, so it cannot cover that construction. Preserve the route and PCM evidence while addressing that boundary; broader campaign, uninterrupted playback and 35-tic/60-display qualification remain open.
