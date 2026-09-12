# Exact PowerShell music prefixes

The four/eight-worker paced synthesizers missed virtual playback deadlines. This implementation moves synthesis ahead of playback and stores its output under ignored `local/music-cache`. It is a finite-prefix foundation, outside the game host. It does not yet provide indefinitely looping campaign music.

## Representation and identity

Each immutable payload contains 25,200 stereo frames as little-endian float64 values: 403,200 bytes, or about 0.571 seconds at 44.1 kHz. Samples precede master volume and PCM saturation. Reusing the cache therefore retains headroom for later effects/music mixing and avoids baking a particular volume into the stored sound. The reader retains one decoded chunk plus the requested output block, rather than loading the complete track.

The SHA-256 cache key covers an ordered identity containing the exact MUS and bank hashes, synthesis/cache source hashes, PowerShell version, sample format/rate, dry effects mode, voice cap, subblock/chunk sizes and single-group policy. A different identity uses a different directory. Payload names contain the chunk index and SHA-256; the manifest validates sequential frame positions and the restricted hash spelling before deriving filenames. Reads check the exact payload length and hash. Cached data is derived from user-local assets and is not included in Git backup.

## Publication and recovery

A standard .NET file handle excludes concurrent writers for one key. The writer publishes each payload before atomically replacing the manifest within the same directory, flushing file contents first. Readers use a snapshot of the committed manifest. They cannot see an uncommitted payload as playable audio. Partial files and orphan payloads remain ignored; a later append may adopt an identical verified orphan. This is tested interrupted-publication recovery, not certification against power loss or every filesystem failure.

The builder can extend a prefix. It reconstructs the synthesizer from the beginning, verifies every already-committed chunk against the reconstruction, then appends new chunks. This avoids attempting to reconstruct envelopes, oscillator phase, controllers, filter history or release tails from PCM. It costs another synthesis pass over the existing prefix. Serialized state checkpoints are a possible later improvement, not an implemented feature.

Warm hits skip bank decoding and synthesis when enough chunks already exist. Actual reading still verifies chunk data. A reader throws at prefix exhaustion without advancing its frame; it never wraps to the opening or invents silence. Pause returns zeros without advancing the cached frame. Reopening obtains a newer manifest snapshot. Continuous background extension and host session/epoch controls remain to be integrated.

## Loop semantics

`Build-MusicCache.ps1` drives the existing single-group synthesizer continuously, preserving 1,260-frame subblocks and MUS event boundaries across score restarts. A 172-chunk E1M1 prefix extends beyond the score's 96-second end. It contains the actual next-cycle synthesis, including carried state and release tails. It does not claim that the first cycle, second cycle or any later cycle is safely repeatable.

Indefinite reuse needs a qualified periodic state boundary or another explicit continuation strategy. Matching a few repeated audio samples would be insufficient evidence of identical future synthesis state. First-use preparation, bounded background production, map transitions, save/load, pause, volume, effects integration and actual device output are release work still to do.

## Initial checks

`music-cache-unit-first.json` passes 22 checks: exact sample reads, pause/resume, cross-chunk copies, explicit exhaustion with unchanged cursor, writer exclusion, partial/orphan recovery, immutable reader snapshots, identity separation, corruption and truncation rejection. These use synthetic data and ordinary file APIs.

The first eight-second cold build commits fourteen chunks (5,644,800 payload bytes). Cache construction takes 5.393 seconds, including bank decoding, synthesis, validation and durable publication, after 0.351 seconds of identity/setup preparation. Reading and PCM conversion/hash take 0.095 seconds for all eight seconds, with a largest observed 1,260-frame block cost of 19.017 ms. The raw PCM SHA-256 is `5595EE0BD1295FC4DAAC5BC1CEB94AEA718777CE340D31421CEB00101BB0B313`, exactly matching the original reference payload. These unpaced offline observations do not establish physical playback deadlines or gameplay headroom.

The full extension (`music-cache-full-extension.json`) reconstructs and verifies all fourteen prior chunks, then commits 172 total chunks: 4,334,400 frames, 98.286 seconds and 69,350,400 payload bytes. Extension/build time is 148.463 seconds after 0.396-second identity/setup preparation. The entire 98-second canonical reference, including its score restart, remains exact: raw PCM SHA-256 `E5C7539145FD3005C0BEBF10EF96C7EA5851231B73AD97C65536CE62AC02F03B`. Cached reading/PCM conversion/hash takes 1.059 seconds for 3,430 blocks; maximum observed block cost is 19.948 ms. The extra final 0.286 seconds is stored but has no independent reference comparison in this run.

A fresh-process warm run (`music-cache-full-warm.json`) derives the identical key, finds all 172 chunks and skips synthesis. Identity/setup preparation takes 0.422 seconds; the empty build branch takes 0.000009 seconds. This is not the complete process startup time: script loading and engine bundle loading precede that timer. Its independently read full PCM is again exact. Reading/PCM/hash takes 1.354 seconds, with a largest observed block cost of 37.240 ms—longer than one 28.571 ms audio block. A prefetched playback buffer still needs actual paced/device testing despite the small aggregate cost. These are single observations with uncontrolled ordinary system activity, not a repeated benchmark.

`music-cache-validation.json` passes 391 evidence checks covering the current 22 synthetic tests, independent cold/extension/warm cache identity, complete reference PCM digests, every stored chunk hash/size, source identity and parses. No live terminal, audio device or concurrent game workload ran. All storage is local and derived assets remain excluded from Git.

## Reproduce

From `C:\projects\pwshDoom` with PowerShell 7 and fresh report paths:

```powershell
./scripts/Test-MusicCache.ps1 -Output local/cache-unit.json
./scripts/Build-MusicCache.ps1 -Output local/cache-opening.json -Chunks 14 -ReferenceReport results/music-e1m1-dry-first.json
./scripts/Build-MusicCache.ps1 -Output local/cache-full.json -Chunks 172 -ReferenceReport results/music-e1m1-dry-numeric-loop.json
./scripts/Build-MusicCache.ps1 -Output local/cache-warm.json -Chunks 172 -ReferenceReport results/music-e1m1-dry-numeric-loop.json
./scripts/Test-MusicCacheEvidence.ps1 -Output local/cache-evidence.json
```

The last call should find the existing prefix and skip synthesis. `-CacheRoot`, `-Wad`, `-SoundFont` and `-Track` select user-local storage/assets. The current finite builder caps requests at 525 chunks (300 seconds). The cache format allows at most 37,800 chunks (six hours), with a 16 MB manifest bound. These are bounds, not a recommendation to precompute six hours per track.
