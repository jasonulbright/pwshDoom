# TimGM bank provenance and revision distinction

Investigated 2026-09-12. The tested bank is now independently identified by an exact byte match in MuseScore's source history. It is not the later revision currently referenced by Debian's TimGM package.

| Variant | Bytes | SHA-256 |
| --- | ---: | --- |
| Current research bank; MuseScore `930dbaf23b8432d897c3127a0ad1be176f7f1ebe` | 5,994,284 | `82475B91A76DE15CB28A104707D3247BA932E228BADA3F47BBA63C6B31AAF7A1` |
| MuseScore `90c33ef9d87b3f5ff92efd3b07d89eb455fb1fef` | 5,969,788 | `C5378B62028C920CB11E4803327983FEE2F2CDFF5DC89C708E39DA417E51C854` |

Both primary-history files were downloaded under ignored `local/music-provenance/`. Their URLs and measured hashes are retained in `results/music-bank-provenance-musescore.json`. The active bank was not replaced. Existing synthesis and recordings retain their exact bank identity.

Debian's [versioned copyright record](https://metadata.ftp-master.debian.org/changelogs/main/t/timgm6mb-soundfont/timgm6mb-soundfont_1.3-5_copyright) identifies the SoundFont under GPL-2 and credits Tim Brechbill (2004) and David Bolton (2010). It links the later MuseScore commit and records earlier correspondence about sample provenance. Debian packaging has a separate license; it should not be conflated with the SoundFont's stated license.

The linked [MuseScore correction](https://github.com/musescore/musescore-old/commit/90c33ef9d87b3f5ff92efd3b07d89eb455fb1fef) changes the SoundFont and documents an Alto Sax note fix. Its parent is the exact file used in this study. This explains why treating every file named TimGM6mb as interchangeable would be wrong. The identified historical issue has not yet been reproduced acoustically here, and no claim is made about which Doom passages it affects.

The prior all-score region-coverage check found a region for every positive-velocity note event. That does not establish that every sample sounds correct. A release decision about retaining this user-supplied bank or qualifying the corrected revision must preserve that distinction. Replacing it requires fresh sound-output/loop qualification and bank-specific evidence; it cannot inherit the current catalogs' hashes or PCM results.

The adopted PowerShell project's GPLv2 attribution for the current bank is retained. The exact history match strengthens file provenance; Debian's stated terms above concern its documented revision. No SoundFont, samples or music payloads are added to Git, and redistribution/notice handling remains part of packaging qualification.
