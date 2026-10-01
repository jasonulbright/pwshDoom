# Pickup, key-lock and automap notices

Development after Preview.4 restores the game messages that the terminal host previously omitted. Gameplay already sets `Player.Message` and a 140-tic lifetime for pickups, locked doors and some automap actions. The host now presents that state alongside the exact rendered snapshot, rather than reading a newer message over an older scene.

The simulation sanitizes notices to printable ASCII, uppercases them, and bounds the payload to 512 bytes. Its PowerShell drawing code uses the original `STCFN` glyphs from the user's IWAD, clips at 320 pixels, and caches the 320×8 indexed bitmap until the text changes. Text, remaining tics and bitmap travel in the same seqlock-protected snapshot. The message lasts four seconds of simulation time; pause and session screens do not consume gameplay tics.

Classic draws the band through its half-block codec. A black band covers the top eight source-image rows while a notice is active, using the base palette even when the world is flashing. Matrix and AnsiArt use their larger terminal font for complete letter shapes, with bright green or red text on black. This avoids reducing seven-pixel IWAD letters to four pixels; it is an intentional typography approximation in the character modes. The next regular frame restores the scene when the message expires. The full 320×200 scene is still rendered, and gameplay, rasterization and encoding stay in PowerShell.

The [48-check bitmap receipt](../results/player-messages-bitmap-20260929.json) covers all three key-lock handlers, an actual E1M2 red locked door, an actual armor pickup, sanitization/clipping, all visual modes, output ordering, atomic saved-notice restoration and worker-driven expiry. It does not test the final host import: the first live Classic route exposed that missing dependency, and `Invoke-Doom.ps1` now imports `TerminalCodec.ps1` explicitly. Its failed run remains in `local/candidate-pacing-classic-max-r1`.

The rejected first typography used one terminal row and was visibly too small in Classic. Those prototype recordings remain in `local/recordings/candidate-notices-*`. The `candidate-bitmap-*-r1` recordings restored the original font in all modes, but Matrix was dim. The `candidate-bitmap-*-r2` recordings brightened Matrix; visual inspection still rejected its reduced letter shapes. Both rounds retain 350-command/eleven-checkpoint runs, original media/audio and audit receipts. Current typography uses the original font only in Classic and the terminal font in the character styles; the final recording prefixes are `candidate-readable-*-r1`. Save fixtures qualify these specific effects and saved-state behavior, not campaign navigation, acoustic quality or clean benchmark performance. Original silent footage, captured audio, replay inputs and clock-placement metadata remain beside the combined movies.

The final [focused receipt](../results/player-notices-readable-20261001.json)
passes fifty checks. The [live receipt](../results/player-notices-live-readable-20261001.json)
passes 24 grouped assertions, including an independent comparison of every
observed world/automap notice's text and timer, all eleven game checkpoints per
style, every submitted audio frame returned, and preserved media timestamps.
Sampled final Matrix and AnsiArt images show complete bright terminal-font
letters. These are visual samples and digital audio captures; physical monitor
readability and acoustic review remain separate human checks.
