# Superseded terminal measurements

These are the original 2026-09-10 terminal runs. A same-profile post-run probe reported code page 437, while the harness sent UTF-8 bytes for ANSI half-block characters. The harness did not explicitly set the console output code page. Consequently the ANSI results cannot support claims about correctly decoded terminal images.

Retained as investigation history, not favorable comparison data. Sixel payloads are ASCII, but the full batches were rerun after fixing the encoding precondition. Use the corrected parent-directory reports with `OutputCodePage: 65001` for current findings. Headless results outside this directory were unaffected.
