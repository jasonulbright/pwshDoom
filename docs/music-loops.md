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

By default, `Qualify-MusicLoop.ps1` renders three continuous periods. A period comprises enough complete score cycles to align with the existing 1,260-frame subblock grid. The finite harness limits total qualification to 3,600 audio seconds, and the playback reader limits any period to 1,200 seconds. The optional complete-state proof below renders two periods; it makes a narrower explicit recurrence inference and does not claim a third independently matched PCM period.

The first period is the intro. The second is a candidate repeating segment. It qualifies only when the states at the ends of all three periods match, the entire second and third float64 files match, the canonical reference PCM remains exact, and sources remain unchanged. Files are written continuously from the synthesizer; voices and controllers are never reset to manufacture a match. E1M1 has 35 live voices at the first boundary, making a simple opening-file restart insufficient.

Repeated normalized state plus identical periodic inputs is the basis for subsequent reuse under the inspected deterministic model. Rendering the full third period independently checks the predicted next output; this is stronger than comparing a short seam. The fourth and later cached periods are justified by that recurrence, not claimed as independently synthesized references. Counter normalization also avoids relying on eventual diagnostic-counter overflow behavior in an impossibly long continuously synthesized run.

### Two-period complete-state proof

The optional `-StateRecurrenceProof` path renders the intro and one complete
candidate loop, then requires the exact normalized synthesis state at the end
of both periods to match. The snapshot includes every recognized
future-driving channel, voice, oscillator, envelope, filter, gain and timeline
field; unknown synthesizer fields reject qualification. Identical score/event
phase, immutable bank and full state imply deterministic recurrence, so the
loop period can be reused without separately synthesizing a third copy. The
canonical opening PCM and unchanged source/runtime checks remain mandatory.

This is an explicit inference from the complete-state invariant: the report
does **not** claim a third independently rendered output hash. It reduces new
track synthesis and payload writing from three periods to two, while retaining
the existing three-period mode for stronger empirical output recurrence and
backward-compatible reports. Both report types identify their evidence mode;
the reader validates the matching layout and keeps only intro/loop payloads
open for playback. Existing three-period catalogs remain accepted unchanged.

For example, a new track can use the shorter proof with:

```powershell
./scripts/Prepare-DoomMusic.ps1 -Tracks D_E2M1 `
  -OutputDirectory ./local/music-preparation-episode2 `
  -Catalog ./local/music-prepared-episodes1-2.json `
  -ExistingCatalog ./local/music-prepared-episode1.json `
  -Output ./local/music-preparation-episode2.json `
  -StateRecurrenceProof
```

The three-period path remains the default until a batch explicitly selects the
state proof. Runtime savings are expected to track the one-third reduction in
rendered periods; verify actual wall time separately for each workload.

## Reader and mixing boundary

`MusicLoopReader.ps1` accepts a locally trusted successful report, verifies its structure, PowerShell major/minor line, synthesis-source identity and every payload hash, then keeps the intro and loop files open with write-sharing disabled. The report retains its exact qualification patch version. Reports are scientific receipts, not cryptographically authenticated certificates. A fabricated report is not proof of valid synthesis; synthetic reader tests explicitly label their fabricated receipt as test data.

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

## Two-period complete-state recurrence proof (September 27)

The optional `-StateRecurrenceProof` mode is now exercised against real IWAD scores. The original three-period method remains the default and retains its independent following-period PCM comparison. In the new mode the state serializer must recognize every synthesizer field; an unknown field type or synthesizer field rejects qualification. At the aligned boundary, the normalized state includes channels, voices, oscillators, envelopes, filters, modulators, score/event phase, playback configuration, and immutable bank/score identity. Absolute cycle/frame and diagnostic identifiers that cannot affect future samples are normalized while their future-driving relationships are retained. Under this pinned deterministic single-group dry model, equal complete normalized state plus the same score phase and immutable assets implies the next generated period repeats. This is a model-based recurrence inference, not an empirical third-period PCM comparison.

The current-source E1M1 qualification completed in 314.031 seconds of render/write/snapshot time. Its 4,233,600-frame (96-second) period starts and ends at normalized state `0E6D546145CACE2EE20EB43451881B30F63351CF50F8B1CFEAEF33463C1F88AB`, with 35 voices. Two periods (192 audio seconds) were rendered, and the separately rendered canonical opening PCM remained exact at SHA-256 `E5C7539145FD3005C0BEBF10EF96C7EA5851231B73AD97C65536CE62AC02F03B`. The existing three-period E1M1 receipts and default mode remain unchanged. The reader accepts either report layout and still opens/retains the exact verified period files required for intro and loop playback. The state-proof evidence suite passes 23 checks; reader compatibility passes 17, including rejection above its 1,200-second bound; actual simulation/mixer and device-worker checks are recorded separately.

The first Episode 2 map score, D_E2M1, also qualifies. Its period is 26,894,700 frames (609.857 seconds), aligned across four score cycles. Two periods (1,219.714 audio seconds) were rendered in 1,320.515 seconds of loop render/write/snapshot time; complete state repeats with 12 voices and SHA-256 `BBD41D41F1D2C43F7BB0DEFB4BCD0D2790644EE864561DC1F5932DBEB261413E`. The independent eight-second opening PCM matches exactly at `5912DBE8F0D9E23475854BFE3A6DF2F6016E17E15A31902BA1926D5B1479E2DC`. Actual reader/mixer checks pass all six checks. The waveOut worker submits PCM matching its independent offline schedule and closes the device cleanly across all ten checks; that verifies submitted data and worker/device handling, not what a listener hears or end-to-end gameplay timing. This D_E2M1 receipt predates the later 1,200-second preflight guard; its 609.857-second period is below that bound, and that guard does not change synthesis or normalization.

### D_E2M2 recurrence and game-start integration (September 27)

D_E2M2 qualifies at 6,703,200 frames (608 seconds, one score cycle). Two
continuous periods cover 1,216 audio seconds; the start and end each have 11
voices and the complete normalized synthesis state matches at
`59A1A22DE2725F04338DBA39D7F4F59D9087176E8BED60CFE5D3F92759C56BF4`.
The independently rendered eight-second opening matches exactly at
`6F592E378D8DF90993F9285AF362D309E94151E5A95F2DD9247B08AA9DEB0316`.
Six actual long-reader/mixer checks pass, including the exact reusable loop
seam (`3F8F0BABD3965672DC36DD89C4DF573D9583F8B5E0530625557F9CA677C5D015`).
This two-period result infers next-period recurrence from equal complete
normalized state; it does not compare a third independent output period.
Loop rendering, writing and snapshots took 510.113 seconds; full preparation
took 525.2 seconds.

A headless two-second E2M2 game integration selected `D_E2M2`, submitted
86,940 music frames, returned 85,680 completed frames, and reported an upper
bound of 1,260 queued frames canceled during shutdown. The audio device closed
without a worker error. This verifies catalog loading, map-to-track selection,
short playback startup and clean shutdown, not audible quality, full-map
playback, or campaign continuity. The local
`local/music-prepared-episode1-e2m1-e2m2-state-proof-20260927.json` catalog
covers the eleven Episode 1 tracks plus D_E2M1 and D_E2M2; its report paths
and music payloads remain ignored local files. Receipts: [preparation](../results/music-preparation-e2m2-state-proof-20260927.json),
[six-check reader/mixer qualification](../results/music-track-qualification-e2m2-state-proof-20260927.json),
[13-track catalog revalidation](../results/music-catalog-revalidation-e1-e2-20260927.json),
and the local [headless integration report](../local/episode2m2-music-integration-20260927.json).

### PowerShell patch-version compatibility (September 27)

Jason's first terminal launch exposed an exact-patch comparison in both the
loop and finite one-shot readers: the current catalog was qualified on 7.6.5,
while his installed `pwsh` resolves to 7.6.6. The readers now accept the same
major/minor version line and retain the existing source and payload-hash
checks. Under the real 7.6.6 launcher, the loop-reader suite passes 21 checks,
the saved E1M1/D_INTRO playback suite passes 17, and the recurrence/reader/
mixer evidence suite passes 23. A two-second headless E1M1 integration run
opened all eleven Episode 1 catalog reports, submitted 86,940 music frames,
advanced 69 tics and closed waveOut without error. A cold-start bound was
raised from 30 to 60 seconds after the first launch reached the former limit.
The [runtime receipt](../results/episode1-startup-runtime-compat-20260927.json)
links the 7.6.6 checks and hashes the ignored session reports. This does not
qualify a human playthrough, audible quality or campaign-long audio.

Portable receipts: E1M1 qualification and actual-reader/mixer audit ([qualification](../results/music-loop-e1m1-state-proof-20260927.json), [prior 23-check evidence audit](../results/music-loop-evidence-state-proof-final-20260927.json), [six-check actual-track reader test](../results/music-track-qualification-e1m1-state-proof-current-20260927.json), [prior 17-check simulation playback test](../results/music-playback-e1m1-state-proof-current-20260927.json), [10-check waveOut worker test](../results/music-audio-worker-e1m1-state-proof-current-20260927.json)); D_E2M1 qualification and preparation ([loop report](../results/music-loop-d-e2m1-state-recurrence-20260927.json), [preparation report](../results/music-preparation-episode2-e2m1-state-proof-20260927.json), [opening reference](../results/music-d-e2m1-opening-reference-state-proof-20260927.json), [six-check actual-track reader test](../results/music-track-qualification-d-e2m1-state-proof-20260927.json), [10-check waveOut worker test](../results/music-audio-worker-d-e2m1-state-proof-20260927.json)). The current [7.6.6 loop-reader suite](../results/music-loop-reader-runtime-compat-7.6.6-r2-20260927.json), [17-check playback test](../results/music-playback-runtime-compat-20260927.json), [23-check recurrence/reader/mixer audit](../results/music-loop-evidence-state-proof-runtime-compat-7.6.6-r2-20260927.json), and [full-start receipt](../results/episode1-startup-runtime-compat-20260927.json) qualify the patch-version update path. The synthetic [reader compatibility smoke](../results/music-loop-reader-period-limit-20260927.json) passes 17 checks, including legacy receipts and rejection above the reader's 1,200-second limit. The earlier `episodes1-2-state-proof` catalog contains only D_E2M1; the current 13-entry E1/E2M1/E2M2 catalog is described above. Catalog paths and large intro/loop payloads remain ignored under `local/`. Both real Episode 2 qualifications use the pinned Ultimate Doom IWAD and soundfont recorded in their receipts. Neither score qualification establishes original-synth fidelity, acoustic quality, complete campaign audio, or a 35/60 gameplay guarantee.

## Intermission continuous recurrence

`music-loop-inter-first.json` qualifies the stock D_INTER score at a 35,520,660-frame aligned period (805.457 seconds, four original cycles). All three boundaries have ten live voices and state `82C3B623331343525501F216ECEA726CFD33BB65D896C1B0EE1BA1266E97A9B9`. Complete second/third files match SHA `CC8D23E90098758FC3FE22C22275B89504303A55ECF07FF307321CF1BFF2BE73`, each 568,330,560 bytes. The independent eight-second opening PCM hash remains `3E5C985530423907A1DDA1D839F08B7B79ECBF0648C226D4072CC4AE9498EFCA`; source identity stays fixed. The 4,505.390-second elapsed render overlaps other synthesis, builds and recordings, so it does not qualify standalone rendering performance.

`music-inter-reader-first.json` passes the same six actual long-file tests used for E1M2, including exact opening PCM and the reusable seam against the independently rendered following period. The finite preparation command now verifies all three session tracks and publishes their local catalog; host transition playback is tested separately. No soundtrack-wide or perceptual-fidelity conclusion follows from these exact recurrence results.

## E1M3 prepared end to end

`music-loop-e1m3-prepared.json` preserves the successful qualification produced by the new preparation command. The period is 11,995,200 frames / 272 seconds, with three periods totaling 816 seconds. All boundaries have 31 voices and state `666EDE7B8AE847BFE081843E6CF22A5750FA5B03B288F82DC782F0958EC6E5DE`. The second/third float files match `2023A8A7F910D93391EAE82EC706443B62F8C007EDED22E0403728275E473D00`, each 191,923,200 bytes. Opening PCM remains `AF5C3E2B379798D8CFDFEE9C60AB0342D87989E335DBA6B917E5C6A38FC05A00`. No source drift occurs. The 1,152.693-second synthesis/write/snapshot time overlaps the campaign recordings and is not a standalone performance benchmark. Six actual E1M3 reader checks also pass. No E1M3 map completion is claimed.
