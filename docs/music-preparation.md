# Preparing a local music catalog

`scripts/Prepare-DoomMusic.ps1` replaces manual opening-render, continuous-loop qualification and catalog editing. Gameplay and all synthesis/mixing algorithms stay PowerShell. This command prepares exactly the requested dry looping tracks from a user-supplied IWAD and soundfont; it does not provide assets, certify the full soundtrack, or implement one-shot music.

From PowerShell 7.6.5 in the repository root, with the existing local assets:

```powershell
./scripts/Prepare-DoomMusic.ps1 -Tracks D_E1M1,D_INTER,D_E1M2 `
  -OutputDirectory ./local/music-preparation `
  -Catalog ./local/my-route-music.json -Output ./local/my-preparation-report.json
./Start-Doom.ps1 -Style Matrix -MusicCatalog ./local/my-route-music.json
```

Supply `-Wad` and `-SoundFont` for other locations. The default soundfont path points to the existing local upstream checkout; packaging and bank distribution remain unfinished. Preparation can take substantially longer than playing the resulting score. The finite qualifier synthesizes three complete aligned periods, streams stereo float64 files and keeps the third as independent recurrence evidence. See [loop qualification](music-loops.md) for the actual model, storage, period bounds and limitations. A soundtrack-wide estimate or performance guarantee has not been established.

Use fresh catalog and run-report paths. `-ExistingCatalog` can supply already-qualified reports; these undergo full payload, source/runtime, IWAD-score and soundfont verification before reuse. The command preflights every requested music lump before synthesizing any track. A selected report with changed assets or stale source fails explicitly rather than silently substituting music.

New tracks are prepared sequentially. Each receives an eight-second opening reference from the original dry renderer, followed by the continuous grouped qualifier. The real playback reader must open and validate the resulting files before the track is accepted. A successful receipt is copied to `<OutputDirectory>/<track>/qualified.json`. The final catalog is published atomically only when every requested track succeeds and source/asset identities remain unchanged. An empty or partially prepared catalog is never presented as the requested result.

If a batch fails or is interrupted, retain its directory. Re-run with that same directory and fresh catalog/run-report filenames. Previously completed per-track receipts are revalidated and reused; incomplete attempt directories stay intact, and the interrupted track receives a fresh attempt. Resume operates at completed-track boundaries, not arbitrary mid-synthesizer sample positions. The command uses an exclusive open `prepare.lock` handle; a leftover filename alone cannot block a new owner after the previous process exits. Never edit the pinned synthesis sources while a batch is active.

The first reuse run verifies E1M1 and E1M2 against their actual large payloads and publishes the two-track catalog. Seven control checks pass in `results/music-preparation-controls-first.json`: real existing-catalog reuse, real same-directory resume, catalog/report overwrite protection, missing WAD lump rejection, wrong-bank rejection, a live competing owner, and released-lock recovery. The test's repeated overwrite attempt retains the original report bytes; its second console log replaces the test's first same-named console log, so the result/report hashes rather than that log establish the initial success. The first script parse also caught a variable immediately followed by a colon; it was fixed before the first successful run.

E1M3's actual new-synthesis path now succeeds under `local/music-preparation-e1m3/`. It independently renders all 816 audio seconds, qualifies recurring state/output with an exact opening reference, verifies the payload through the real reader and publishes its catalog. The portable receipt is `results/music-preparation-e1m3-first.json`; six further actual reader checks pass. This validates the new-track path for E1M3, not every soundtrack entry.

A subsequently published four-track catalog includes E1M1, INTER, E1M2 and E1M3. The observed preparation/revalidation takes 19.844 seconds including bundle loading and full payload checks. A warmed four-second headless host then opens the catalog within the existing startup deadline, runs 139 commands, matches the available replay checkpoint and closes audio. This is not a cold-cache or full-soundtrack startup guarantee.

On 2026-09-12, D_E1M4 completes three independently synthesized aligned periods. Its repeating period is 30,105,180 frames (682.657 seconds, four score cycles), with 27 live voices and normalized state hash `7A236BCB6F2D61649666A232F5C5001C88EB40D649F51ACE18920EB4983DF325`. Both subsequent float64 periods have SHA-256 `A9C26FBC231F3FDA34927C294C3059DF17077DE8238FCF30F9E7C86DC126C4F1`. Rendering/writing/snapshotting takes 2,011.332 seconds on this run; this is offline preparation, not live mixing cost. The opening PCM matches its independently rendered eight-second reference, and six actual long-track reader checks pass. Portable receipts are `music-loop-e1m4-prepared.json`, `music-e1m4-preparation-opening.json` and `music-loop-e1m4-reader.json` under results/.

A separate reuse-only invocation validates all five completed tracks and atomically publishes `local/music-prepared-five.json`; its receipt is `results/music-preparation-five.json`. The six-track batch continues preparing D_E1M9 on its original process handle. Its requested six-track catalog is not published until that entire batch succeeds. E1M4 full-host playback and E1M9 qualification are still pending; no soundtrack-wide, acoustic or campaign completion claim follows from the fifth prepared loop.
