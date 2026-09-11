# Music foundation

Music is not yet audible in the game. This milestone implements original PowerShell MUS decoding, sample scheduling and a structural SF2 instrument-bank reader. The existing `-Sound` option still plays effects only. No compiled synthesizer has been added.

## Decoder and timeline

`src/MusScore.ps1` decodes bounded MUS headers, instruments, note events, cached channel velocities, pitch bends, program/controllers and end markers. It retains MUS channel numbers, including percussion channel 15. Events carry absolute music ticks; the timeline maps them to output samples, preserves event order, freezes when paused and handles finite playback or looping. Events exactly on a block endpoint belong to the next block. Computing positions from total elapsed ticks avoids accumulating a rounded duration on every loop.

At 44.1 kHz, a 140 Hz music tick spans exactly 315 sample frames, and the effects worker's 1,260-frame block spans four music ticks. The decoder accepts scores up to six hours and rejects malformed bounds, truncated data, undefined event kinds and invalid controller identifiers. It does not yet implement MIDI-file import or a synthesizer's controller state.

Format behavior was checked against Chocolate Doom's [GPL-2.0-or-later MUS converter](https://github.com/chocolate-doom/chocolate-doom/blob/895f581c5d91497bdda0516612da803fe5843e28/src/mus2mid.c). The downloaded source remains in ignored `local/music-references/mus2mid-895f581.c`, SHA-256 `C20F0550C5B29AEE602C56844F6DFD65A8092B5FE82B3AF7A2DADB99ECE1AC4C`. Inspection caught a compatibility distinction: high program bits are masked, while out-of-range valued controllers are clamped. Independent tests cover both. No converter source body was copied into the PowerShell module.

## Actual IWAD and instrument bank

`results/music-iwad-inventory-program-mask.json` records the installed Ultimate Doom IWAD, SHA-256 `6FDF361847B46228CFEBD9F3AF09CD844282AC75F3EDBB61CA4CB27103CE2E7F`. All 32 `D_` lumps decode; every event in every full track matches the independent `tick * 315` sample projection. All 36 retained engine map references resolve. This records existing routing, not independent verification of the original game's map-to-music table. Intro, intermission, victory and bunny music are included.

The scores contain 52 distinct program values and 24 percussion keys. The maximum observed count of distinct depressed keys is 15, in `D_INTRO`; `D_E1M1` reaches ten. These are not synthesis voice counts: sustain, release tails and layered instruments can increase the work. The E1M1 score lasts 96 seconds. Decoder timings in the report are single offline startup measurements, not steady playback costs.

`src/SoundFontBank.ps1` reads the local bank's RIFF structure, signed 16-bit sample pool, preset/instrument/sample headers and generator/modulator tables. It validates container lengths, table widths, monotonic indices, terminal references and sample bounds. It explicitly rejects ROM samples and 24-bit extensions. This is a restricted structural reader; it does not claim general SoundFont compliance or validate effective sample addresses after applying generators. Format reference: E-mu/Creative's [SoundFont 2.04 specification, sections 3–7](https://musescore.org/sites/musescore.org/files/2023-01/sfspec24.pdf).

The local `TimGM6mb.sf2` has SHA-256 `82475B91A76DE15CB28A104707D3247BA932E228BADA3F47BBA63C6B31AAF7A1`. The accepted inventory is `results/music-bank-inventory-current.json`:

| Property | Observed value |
| --- | ---: |
| File bytes | 5,994,284 |
| Declared version | 2.01 |
| Presets, excluding terminal | 136 |
| Instruments, excluding terminal | 210 |
| Samples, excluding terminal | 520 |
| Sample frames in shared pool | 2,893,608 |
| Explicit instrument modulators, excluding terminal | 455 |

All samples declare mono type. Headers exist for all 52 observed melodic program numbers in bank zero and eight percussion presets in bank 128, including program zero. Note/velocity-zone coverage remains to be checked. The inventory retains generator IDs and sample rates to scope envelopes, loops, tuning, filters, LFOs and controller handling. Finding a preset header does not prove that it sounds correct.

ManagedDoomPowershell's retained README attributes this bank to Tim Brechbill under GPLv2 and carries `licenses/LICENSE_TimGM6mb.txt`. The bank's own inspected INFO metadata names TimGM6mb, EMU8000 and Awave Studio v8.5, without a copyright entry. Thus licensing attribution is presently upstream-reported; independent asset provenance still needs qualification before packaging. The bank and decoded samples remain ignored local assets.

## Evidence and preserved failures

- `music-mus-unit-program-explicit.json`: 25 named checks, including independent byte/event vectors, malformed scores, pause, finite end, block partition invariance and fractional-rate loop timing.
- `music-bank-unit-unsigned.json`: 21 named checks, including independent signed PCM/table values, odd chunk padding and malformed/unsupported structure rejection.
- The two accepted inventory reports cover actual local assets without committing scores or samples.
- `music-foundation-validation.json`: 28 evidence checks pin seven source files, verify their parses and accepted report freshness, and show the program-normalization correction leaves all actual IWAD event hashes unchanged.

The first MUS fixture called `CopyTo` before its byte-array cast; the first full inventory had PowerShell comma/multiplication precedence wrong; its next serializer rejected integer dictionary keys; and the first bank unit harness expressed unsigned maximum as signed hexadecimal `-1`. Original failed reports are retained. For the serializer failure, no report could be emitted: `music-iwad-inventory-serialization-failure.json` records the process error explicitly. These harness failures are separate from the corrected program-normalization behavior.

No live terminal run or device playback occurred in this milestone. There is consequently no new screen recording or music audibility claim.

## Next implementation

Resolve preset and instrument zones with global/local precedence and key/velocity selection. Then implement PowerShell sample playback, tuning, loop/release behavior, envelopes and the bank's necessary modulation/filter features. Measure real score polyphony and block cost before integrating with the effects worker. Remaining host work includes score changes, loops, pause, independent music volume, new-game/save/load restoration and cleanup. Compare against a pinned reference synthesis output with intentional differences declared; a pitched-sample demonstration alone will not qualify music fidelity.

The retained upstream `SilkMusic` path delegates to a compiled `DoomMusicBridge` and MeltySynth. It is an alternative/reference, not an allowed implementation under the user's PowerShell algorithm constraint. A new PowerShell OPL synthesizer using IWAD GENMIDI is another possible route, but operator emulation and fidelity/cost remain unmeasured. SF2 is the current implementation experiment because a local instrument bank is available; no performance superiority has been established.

Reproduce from PowerShell 7.4 or newer with fresh output paths:

```powershell
./scripts/Test-MusScore.ps1 -Output local/music-unit.json
./scripts/Test-SoundFontBank.ps1 -Output local/bank-unit.json
./scripts/Test-MusicInventory.ps1 -Output local/music-inventory.json -Wad 'C:\path\to\DOOM.WAD'
./scripts/Test-MusicBankInventory.ps1 -Output local/bank-inventory.json -MusicInventory local/music-inventory.json -SoundFont 'C:\path\to\TimGM6mb.sf2'
```

The bank inventory currently expects the 32-track Ultimate Doom fixture. The evidence audit uses the named retained reports; it does not run synthesis or gameplay.
