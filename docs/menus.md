# Menus, pause and new games

Escape opens a menu with Resume Game, New Game, Save Game, Load Game, Controls and Quit. Arrows choose an item; Enter selects it; Escape goes back. New Game selects an available episode and difficulty, then asks before replacing the current game. Quit also defaults to No. P or the Pause key pauses; P, Enter or Escape resumes the paused screen. [Save/load](save-load.md) now has six slots, overwrite/load confirmation, progress/error screens and exact-save replay references. Automap and settings remain unfinished.

The menus use native WAD graphics and the adopted PowerShell `DrawScreen`, with a small new PowerShell controller suited to this host's separate simulation process. The inherited menu controller depends on another `Doom` wrapper and its video/input settings interfaces; it is retained in the attributed source but not silently presented as integrated.

Classic draws the complete 320×200 menu through its normal half-block encoder. Matrix and AnsiArt keep their 160×50 character grid and use block graphics for menus. A brightest-pixel reduction within each 2×2 source region preserves text against the black background; Matrix keeps green coloring. Custom text uses 2× WAD glyphs and checks its bounds after a recording review found the smaller instructions difficult to read. This is an intentional menu readability treatment, not a claim of lossless reduction. Their gameplay remains katakana/ASCII character art, and intermission/finale presentation is unchanged by this menu step. Undersized windows show a compact text menu so navigation and quit confirmation remain accessible while the game view cannot fit. Restoring a window redraws the current menu without resuming gameplay.

## Simulation and input boundaries

Opening a menu stops the host's active scheduling clock. The simulation consumes commands already issued, then acknowledges the menu request and publishes its pixels. The host issues no further gameplay commands while a menu or its request is pending. Static menus publish on change instead of continually redrawing. Closing the menu resumes the active clock only when the viewport also fits. The two holds can overlap; their wall durations are recorded separately and must not be added together as if disjoint.

Physical key-down state is retained for repeat debouncing. Gameplay keys held through a menu are masked until release, so holding P cannot repeatedly toggle pause and holding the selecting Enter cannot accidentally use a door after resuming. Eight synthetic native-key tests verify these cases and focus loss; the original reset failed three of them before correction. The original six input structure/state tests also pass. Physical keyboard play still requires observation.

A new-game selection is handled at the same command boundary. The simulation initializes the selected game, publishes a fresh world generation, and waits for the normal asset-reload acknowledgment from the persistent renderer processes. A menu revision accompanies snapshots/jobs so an older render cannot replace a more recent menu or resumed screen. The underlying game-state enum remains separate from the screen representation.

Input recording version 2 adds ordered `NewGame` control events between gameplay commands. Menu navigation and wall-clock pauses need not be replayed to reproduce the simulation; a new game does. Multiple control events can share a command boundary. Checkpoints at that boundary represent the state after its controls. Versions 1 and the original study route files remain supported. The reader bounds and validates control types, settings and ordering; unknown action types are rejected.

## Original menu milestone evidence

The first integrated Matrix probe paused at tic 34, then its menu encoder failed on PowerShell arithmetic/comma precedence in an array literal. The failure is retained in `results/menu-probe-game.json`. Parenthesizing the index expressions fixes it. Independent menu-encoder tests compare the selected colors against stable-sorted 2×2 brightness samples through the separate ANSI encoder.

The corrected host probe holds at tic 34 during pause, resumes, and holds at tic 69 throughout episode/difficulty navigation. Confirmation starts E2M1 at skill 3 with generation 2. Its version-2 recording includes one new-game control at boundary 69; replay consumes all 199 commands, including one completed during the original host's shutdown, and matches all three checkpoints. The original measured host count is 198; the simulation's final consumed log is 199. This difference remains explicit in the reports.

A seven-second resize overlap probe pauses at one second, shrinks to 98 rows at two, restores the window at three, and resumes at four. Issued and published tics both remain 34 through the resize. It consumes 139 measured tics in approximately four active seconds with one viewport pause. The normal 1,747-command E1M1/intermission/E1M2 regression also still matches all eight checkpoints.

The current fixtures cover 70 menu/navigation/encoder/compact-layout checks and 19 native screens. Seven uneven workers in each style verify menu/screen transport and map reload: 576,000 pixels and 63 encoded strips across the three styles. The existing character codec passes 144 cases; the basic ANSI/Sixel checks pass. The replay format passes 42 checks, including rejection of negative control boundaries. These are functional checks, not clean FPS measurements or physical keyboard observations.

An initial color-art screen capture failed during external FFmpeg shutdown although the game completed. Windows Application Error logged exception `0xc0000005` in `graphicscapture.dll_unloaded`; see [the retained event](../results/menu-ffmpeg-crash-events.json) and [failed-capture metadata](../results/menu-recording-failure.json). This points toward native capture teardown, but does not establish its root cause. The failed recording is not accepted as verified footage.

Aggregate write rates from menu demonstrations are unsuitable for gameplay performance comparisons: menu writes are counted while their wall holds are excluded from the active clock. The wall rate remains an overall output rate including static-menu idle time. Later pacing work must separate gameplay and UI windows. None of the menu tests certifies 60 displayed gameplay frames per second.

## Actual Terminal recordings

The final three finite tests open menus, choose E2M1 at skill 4, resume gameplay, pause/resume, show controls, cancel quit once, then confirm quit. They use the recorded schedule in [menu-demo-schedule.json](../results/menu-demo-schedule.json) and the existing scripted game inputs. This is UI/session evidence, not an E2M1 completion route or a physical keyboard playtest.

| Viewing copy under `local/recordings/` | Duration | Fully decoded movie frames | Crop |
| --- | ---: | ---: | --- |
| `menu-verified-classic.mp4` | 18.9 s | 1,134 | 1600×902 |
| `menu-verified-matrix.mp4` | 19.2 s | 1,152 | 1280×800 |
| `menu-verified-ansiart.mp4` | 19.9 s | 1,194 | 1280×800 |

The `-full.mp4` originals are actual Windows.Graphics.Capture footage. Viewing copies remove startup/console return and fixed margins, retain the handoff, and make no speed change, rescaling or added effect. Classic includes one alignment pixel above and below the 1600×900 game crop. H.264 re-encoding is lossy; 60 CFR includes duplicate frames and static menus. These clips have no audio. Exact hashes, capture/export arguments, and source references are in [menu-recordings.json](../results/menu-recordings.json).

Six samples per style at viewing seconds 1.8, 4.8, 8.4, 10.2, 12.8 and 14.2 show gameplay, main menus, skill or confirmation screens, pause guidance and controls. Enlarged instructions fit and are readable in these samples. Matrix remains fairly dim; brightness and physical playability remain tuning/qualification work. Sampling does not certify every movie frame.

The final Classic capture records 122 consumed commands and one new-game control. A separate headless host replays that file against unchanged source and matches all three checkpoints. [menu-validation.json](../results/menu-validation.json) verifies 226 frozen source hashes, 74 script/bundle parses, six original/viewing video hashes and zero remaining owned game/recorder processes. Save/load, settings, automap, audio, wider campaign qualification and final pacing/fidelity remain on the release roadmap.

The first menu request takes 713 / 698 / 604 ms to acknowledge in those Classic / Matrix / AnsiArt runs, including queued-command drain and lazy menu-graphics initialization. This is a responsiveness issue for later tuning, not measured key-to-display latency. The new-game asset holds take 0.906 / 0.967 / 0.947 seconds and remain in wall reports and footage.

## Save-menu follow-up

Six save slots, default-no overwrite/load decisions, version warnings and busy/error screens are now integrated. The [save/load findings](save-load.md) describe their implementation, 39 menu fixtures, host/replay checks and three newer live recordings. The current main menu adds Save Game and Load Game; older menu evidence above retains its original layout. Save-menu footage exposes a timestamp display bug corrected afterward and a transient incomplete Matrix footer that remains a presentation finding. Automap/settings and physical-play qualification are still ahead.
