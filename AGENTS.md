# Working in this study

This is a feasibility investigation, not a commitment to ship a Doom port.

- Update `docs/ledger.md` as findings, failures, decisions, and corrections occur.
- Keep author reports, source inspection, measured behavior, and hypotheses distinct.
- Preserve raw results and exact parameters. Never call completed console writes displayed FPS.
- Use the user's requested root `C:\projects\pwshDoom`.
- Keep WADs, extracted images, external source, and downloaded tools in ignored `local/`.
- Do not adopt external code without checking its license. A runtime adapter may inspect/test a user-local source file while leaving it outside this repository.
- Keep experiments finite. Clean up only resources created by the study; preserve the user's Terminal profiles and default settings.
- Do not change security settings for performance. Record access limitations rather than obscuring them.
- Pure PowerShell here means game/encoder algorithms written in PowerShell using standard .NET APIs. Any compiled custom helper must be identified separately.
- Run codec correctness checks when modifying encoding, and appropriate targeted benchmarks when making performance claims.
