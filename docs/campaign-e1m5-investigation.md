# E1M5 investigation

2026-09-19. The qualified E1M4 replay reaches E1M5 and runs 71 destination tics with carried inventory. E1M5 itself has no completed route yet. Its earlier map smoke pass is not completion evidence.

A read-only export of the installed Ultimate Doom IWAD is retained under ignored `local/e1m5-plan.json` and `.png`. Initial geometry and map things identify these planning anchors; all route feasibility still requires ordinary-input validation:

| Anchor | Position / constraint |
| --- | --- |
| Player start | (-224, -624) |
| Green armor near start | (-416, -160), map flags 7 |
| Placed shotgun available on HMP | (288, 352), flags 7; the one at (864, 288) is easy-only, flags 1 |
| Blue key | (192, 1040), flags 7 |
| Yellow key | (688, 800), flags 7 |
| Normal exit switch | Line 409/type 11, between (-320, 2496) and (-256, 2496) |

Do not repeat the planar-height mistakes from E1M4. The central sector 72 has initial floor -24 and damaging special 7; the blue-key room's sector 130 has floor 56 and its western threshold sector 142 has floor 80. A planar shortcut across that threshold is not evidence of a walkable approach. The geometry shows northern steps and an eastern shotgun-room approach that need to be considered when planning. Door/key order, moving floors and enemy positions remain part of actual route validation.

E1M5 music preparation revalidated all six existing tracks and passed its independent eight-second opening render (`results/music-e1m5-preparation-opening.json`). The continuous three-period qualification covers 492 audio seconds and is still running on original preparation handle 68091. Its intended seven-track catalog is `local/music-prepared-seven.json`; it must not be treated as available before successful atomic publication. Keep all pinned synthesis sources unchanged, and defer live recordings/performance measurements while synthesis runs. Functional unpaced route work may continue, with no timing claim.
