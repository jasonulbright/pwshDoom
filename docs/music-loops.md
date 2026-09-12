# Qualified cached music loops

The finite cache established exact output through E1M1's first restart. This work checks a reusable loop against the current PowerShell dry synthesizer's state, then supplies a bounded reader for a locally trusted qualification report. The subsequent [music integration](music-integration.md) connects qualified E1M1 playback to the host with an explicit catalog. Ordinary `-Sound` remains effects-only while the soundtrack is completed.

## State comparison

`MusicLoopState.ps1` serializes dictionaries in ordinal key order, retains array order and primitive types, and encodes floating-point values as their exact binary representation. It hashes the complete channel and voice state, including controller arrays, region/modulator/generator data, oscillator phase and step, envelope history, filter coefficients and delay samples, interpolated gains, control boundaries and voice ordering. Oscillator sample-array references must point to the shared bank; the bank hash identifies those immutable samples.

Normalization is deliberately restricted to the inspected dry single-group synthesizer:

- The timeline's absolute frame and score-cycle offsets translate together. The event index, frame offset within that cycle, finished/loop flags and 1,260-frame subblock phase remain material.
- Channel revision numbers become zero, and each voice retains its revision difference from its channel. A pending controller update therefore remains distinguishable.
- Voice note IDs become offsets from the synthesizer's next-note counter, preserving ordering/identity relationships. Note-partitioned workers are excluded because their ownership depends on sequence modulo worker count.
- Diagnostic counts for notes, peaks, clipping and effects sends are excluded after source inspection confirms that they do not drive synthesis. Configuration retains sample rate, voice cap, volume, dry mode and score/bank hashes.

Every other voice/channel field remains in the comparison. Unknown top-level synthesizer fields cause rejection. Paused, misaligned, non-dry, non-44.1-kHz or partitioned states are rejected. Qualification is tied to exact synthesis/normalizer source hashes and PowerShell version. These normalizations apply to the current algorithms; future changes require review. They are not a claim of state compatibility with another engine or of complete SF2 fidelity.

`Test-MusicLoopState.ps1` passes 23 synthetic checks. A short score has live release tails at its loop boundary; adjacent normalized states and the next entire float output match. One-bit changes to oscillator/filter/control values, changed envelope history, changed controller state and pending revisions alter the fingerprint. Changes to diagnostic counters do not. Snapshotting leaves the live state unchanged.

## Real qualification procedure

`Qualify-MusicLoop.ps1` renders three continuous periods. A period comprises enough complete score cycles to align with the existing 1,260-frame subblock grid. For E1M1 it is one 96-second cycle. The finite harness currently rejects three-period fixtures longer than 300 seconds.

The first period is the intro. The second is a candidate repeating segment. It qualifies only when the states at the ends of all three periods match, the entire second and third float64 files match, the canonical reference PCM remains exact, and sources remain unchanged. Files are written continuously from the synthesizer; voices and controllers are never reset to manufacture a match. E1M1 has 35 live voices at the first boundary, making a simple opening-file restart insufficient.

Repeated normalized state plus identical periodic inputs is the basis for subsequent reuse under the inspected deterministic model. Rendering the full third period independently checks the predicted next output; this is stronger than comparing a short seam. The fourth and later cached periods are justified by that recurrence, not claimed as independently synthesized references. Counter normalization also avoids relying on eventual diagnostic-counter overflow behavior in an impossibly long continuously synthesized run.

## Reader and mixing boundary

`MusicLoopReader.ps1` accepts a locally trusted successful report, verifies its structure, runtime/source identity and all three payload hashes, then keeps the intro and loop files open with write-sharing disabled. Reports are scientific receipts, not cryptographically authenticated certificates. A fabricated report is not proof of valid synthesis; synthetic reader tests explicitly label their fabricated receipt as test data.

The reader plays the intro once and maps later absolute frames into the qualified loop using integer remainder. It retains one decoded page of at most 25,200 stereo frames. Reads can cross page boundaries, the intro boundary and multiple loop boundaries. Pause emits silence without advancing the cursor. Corruption, inconsistent/unqualified reports, changed sources, invalid cursor positions and closed readers are rejected. Cleanup releases both file handles, including after a partially failed open.

`Read-DoomAudioFrames` now accepts optional unquantized stereo music and an explicit music gain. It accumulates effects, adds music, then rounds/saturates the combined result once. Effects volume and music gain remain separate; the future host caller must apply shared master/mute controls consistently. Invalid music length or nonfinite samples are rejected before effect voices advance. Existing effects-only callers use the unchanged default path.

Actual worker prefetch, track selection, pause/menu/epoch transitions, save/load, full-track availability, device playback, recording and gameplay-load tests remain required. A successful offline loop is not evidence of acoustic timing or campaign completion.

## E1M1 result

`music-loop-e1m1-first.json` qualifies the second 96-second period for the pinned stock score/bank and current dry model. The three-period render takes 432.134 seconds including file writes, snapshots and reference-prefix PCM checks, excluding initial asset preparation. No other synthesis/test workload overlaps it; documentation work and ordinary system activity are uncontrolled.

All boundaries at 96, 192 and 288 seconds contain 35 live voices and have normalized state hash `0E6D546145CACE2EE20EB43451881B30F63351CF50F8B1CFEAEF33463C1F88AB`. The first period's float hash is `B2B9EF7E205C89DC3391F7C7D0DD8F5A7BFC354BC1CA1D119EBD4246778F033B`. The independently rendered second and third periods both have hash `4C068351C46CD40E5FF90DE7B79680C0C5CDA91F4BF59F0AB1947B10F7F12A86`. Each file contains 67,737,600 bytes; playback retains the first two files, while the third remains qualification evidence. All derived audio files stay under ignored `local/`.

The canonical first-98-second PCM remains exact. `music-loop-validation.json` passes 23 evidence checks and exercises four periods through the reader: the intro, the stored second period, another copy matching the independently synthesized third, and a fourth justified by state recurrence. It also passes the first 98 seconds through the combined effects mixer with no active effects; raw PCM hash `E5C7539145FD3005C0BEBF10EF96C7EA5851231B73AD97C65536CE62AC02F03B` still matches the original.

Reading/hashing all 384 seconds plus PCM conversion of the first 98 seconds takes 2.737 seconds in this unpaced audit. Its maximum block cost is 50.112 ms. Startup asset verification is outside this timer. This spike is longer than one 28.571 ms audio block, so prefetch/device buffering remains necessary; the aggregate figure is not a deadline claim.

The reader's fifteen synthetic tests pass, as do nine combined-mixer tests, the existing twenty-two effects tests and four volume tests. Those tests include cancellation of loud effects by opposite-polarity music before clipping, combined clipping counts, invalid-layer rejection before state advance, and unchanged effects-only behavior. No live terminal/device run occurred. Other tracks remain unqualified; one-shot opening music also needs its own end/tail handling rather than this looping reader.

## Reproduce

Use PowerShell 7.6.5 from `C:\projects\pwshDoom`, local assets and fresh output filenames:

```powershell
./scripts/Test-MusicLoopState.ps1 -Output local/loop-state.json
./scripts/Qualify-MusicLoop.ps1 -Output local/e1m1-loop.json
./scripts/Test-MusicLoopReader.ps1 -Output local/loop-reader.json
./scripts/Test-MusicEffectMix.ps1 -Output local/music-effect-mix.json
./scripts/Test-MusicLoopEvidence.ps1 -Output local/loop-evidence.json
```

The evidence audit uses the named retained unit reports and original canonical WAVs; it is scoped to E1M1. The qualifier accepts `-Wad`, `-SoundFont`, `-Track` and a matching `-ReferenceReport`. Its three-period duration bound and current qualification conditions can reject other tracks. A rejected or missing qualification must not be silently replaced with E1M1 music.

## Longer-score bound and current E1M1 identity

The finite group horizon now permits 158,760,000 frames (one hour at 44.1 kHz), and the reader permits periods up to 52,920,000 frames (twenty minutes). Stock MUS periods must align with the existing 1,260-frame scheduling grid. E1M2 therefore needs four 155.364-second cycles per period and three periods totaling 1,864.371 seconds; intermission needs four 201.364-second cycles per period, totaling 2,416.371 seconds. The old five-minute total limit excluded both. Storage remains streamed and reader pages remain bounded.

`music-loop-e1m1-hour-bound.json` requalifies E1M1 against the changed source identity. All three complete float hashes match the earlier run, as do the recurrent state and original 98-second PCM. Its 441.085-second render overlaps the two longer qualification jobs, so it is a correctness observation, not a paired performance comparison. Twenty-two group, twenty-three state and fifteen reader checks pass against these bounds. The first updated real-evidence audit rejects its stale named state-test report; the retained failure is `music-loop-evidence-hour-bound.json`. Explicit report parameters correct that selection, and `music-loop-evidence-hour-bound-current.json` passes all twenty-three checks with full four-period float and original PCM identity. Its maximum observed block cost remains 48.433 ms; no deadline claim follows from aggregate read speed.

## E1M2 continuous recurrence

`music-loop-e1m2-first.json` now qualifies E1M2. Its aligned period contains 27,406,260 frames (621.457 seconds), with four original score cycles. All three boundaries have 14 live voices and normalized state `F80B55073C21202481E89236461DCA33FDB0E3398F24FAC9B1B3D8AD4BADDB66`. Complete second/third files both hash to `89F9FA1444D4ACF67F427426404431C06C8086D24FBE55BAECEB4B81B0C9FEF7`, with 438,500,160 bytes each. Original opening eight-second PCM remains exact and sources do not drift. The 2,290.433-second wall time overlaps other work; it is not a performance comparison.

`music-e1m2-reader-first.json` passes six checks using the actual long files: qualification/score/bank identity, the expanded period bound, reference WAV identity, exact opening PCM through the game mixer, the reused boundary against independently synthesized following-period bytes, and handle closure. This qualifies the dry synthesis model and reader, not musical fidelity or E1M2 completion. Intermission subsequently qualifies all three periods; see below.

## Intermission continuous recurrence

`music-loop-inter-first.json` qualifies the stock D_INTER score at a 35,520,660-frame aligned period (805.457 seconds, four original cycles). All three boundaries have ten live voices and state `82C3B623331343525501F216ECEA726CFD33BB65D896C1B0EE1BA1266E97A9B9`. Complete second/third files match SHA `CC8D23E90098758FC3FE22C22275B89504303A55ECF07FF307321CF1BFF2BE73`, each 568,330,560 bytes. The independent eight-second opening PCM hash remains `3E5C985530423907A1DDA1D839F08B7B79ECBF0648C226D4072CC4AE9498EFCA`; source identity stays fixed. The 4,505.390-second elapsed render overlaps other synthesis, builds and recordings, so it does not qualify standalone rendering performance.

`music-inter-reader-first.json` passes the same six actual long-file tests used for E1M2, including exact opening PCM and the reusable seam against the independently rendered following period. The finite preparation command now verifies all three session tracks and publishes their local catalog; host transition playback is tested separately. No soundtrack-wide or perceptual-fidelity conclusion follows from these exact recurrence results.

## E1M3 prepared end to end

`music-loop-e1m3-prepared.json` preserves the successful qualification produced by the new preparation command. The period is 11,995,200 frames / 272 seconds, with three periods totaling 816 seconds. All boundaries have 31 voices and state `666EDE7B8AE847BFE081843E6CF22A5750FA5B03B288F82DC782F0958EC6E5DE`. The second/third float files match `2023A8A7F910D93391EAE82EC706443B62F8C007EDED22E0403728275E473D00`, each 191,923,200 bytes. Opening PCM remains `AF5C3E2B379798D8CFDFEE9C60AB0342D87989E335DBA6B917E5C6A38FC05A00`. No source drift occurs. The 1,152.693-second synthesis/write/snapshot time overlaps the campaign recordings and is not a standalone performance benchmark. Six actual E1M3 reader checks also pass. No E1M3 map completion is claimed.
