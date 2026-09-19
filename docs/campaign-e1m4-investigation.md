# E1M4 route development

Six finite HMP pistol-start candidates failed before the seventh completed and independently qualified the [normal route and E1M5 continuation](campaign-e1m4.md). No engine behavior was relaxed to help the driver. The measured route is `routes/e1m4-normal.json`; receipts retain each candidate's plan and source hashes.

| Candidate receipt (`results/e1m4-route-*.json`) | Completed updates | Outcome |
| --- | ---: | --- |
| first | 3,292 | Death in western maze before yellow key; ammunition exhausted. |
| second | 2,021 | Stalled by eastern window with 91 health: route attempted a 136-unit rise. |
| third | 3,347 | Death in western maze, last attacker `Sergeant` (pink demon); shells remained but no shotgun was owned. |
| fourth | 2,117 | Northern armor approach stalled below a 104-unit rim; actual dropped shotgun collected, 88 health and 19 shells remained. |
| fifth | 2,978 | Ordinary platform trigger/wait reached blue armor; later killed by an imp at central approach with 180 armor but no shotgun. |
| sixth | 6,535 | Actual dropped shotgun acquired, both keys obtained, 80 health/172 armor remained; exit approach stalled against a 64-unit ledge. |
| seventh | 6,161 | Completes normally with 77 health/168 armor/twelve shells after using the bridge switch and eastern staircase. Independent replay passes 176 samples, one acquisition check and continuation into E1M5. |

Raw map things must be filtered by skill and multiplayer flags. The eastern placed shotgun at (1312,800) has flags 1, so it is easy-only. The southwestern shotgun has flags 23, including multiplayer-only. Neither is available in this single-player HMP route. Walking through a shotgun enemy's initial position also does not guarantee collecting its dropped gun after it moves. Earlier planning assumed otherwise. Collecting actual dropped weapons through ordinary movement is a useful next driver improvement.

The static path planner also omits dynamic floor heights, lifts and key order. The second candidate's failed window and fourth candidate's armor rim demonstrate these limits. The fifth candidate crosses the actual northern raising-floor trigger, waits through ordinary commands, then crosses toward the armor. It never directly moves a sector or relocates the player. A direct blue-to-yellow path that approached a yellow door before obtaining the key was rejected before running.

The driver records sector/floor/special and final attacker, pins sources at startup, and distinguishes attempted commands from completed updates. Last attacker is only the most recent damage source and may be stale. Trace X/Y remains pre-update; other sampled state is post-update. The independent qualifier compares the new sector fields when available; the seventh candidate exercises those checks across all 176 samples. Optional dropped-weapon steering is bounded and logged, and the qualifier independently checks its exact acquisition command.

The prior ledger's third-candidate count of 3,333 was incorrect: its receipt records 3,347 completed updates. Likewise, E1M3's sixteenth failure logged the throwing command before `Game.Update`; 6,261 was attempted commands, not completed updates plus an unlogged throw. Historical raw receipts are preserved.
