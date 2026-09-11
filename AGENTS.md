# Working in this study

The user approved implementation on 2026-09-10 and then requested a complete game and a substantial scientific/entertainment write-up. E1M1 is the baseline; follow `docs/roadmap.md` for the release milestones, acceptance criteria, current scope, and next work. Retain the feasibility record and distinguish implemented behavior from verified compatibility.

- Update `docs/ledger.md` as findings, failures, decisions, and corrections occur.
- Keep author reports, source inspection, measured behavior, and hypotheses distinct.
- Preserve raw results and exact parameters. Never call completed console writes displayed FPS.
- Use the user's requested root `C:\projects\pwshDoom`.
- Keep WADs, extracted images, original downloaded source checkouts, and downloaded tools in ignored `local/`. An explicitly attributed, licensed source subset adopted for the implementation may live under `src/`; preserve notices and record modifications.
- Do not adopt external code without checking its license. A runtime adapter may inspect/test a user-local source file while leaving it outside this repository.
- Keep experiments finite. Clean up only resources created by the study; preserve the user's Terminal profiles and default settings.
- The user requested screen recordings of live effect test runs. Keep actual window-capture footage and per-run metadata under ignored `local/recordings`; publish only portable findings/hashes to the repo. Label recorded runs separately from clean performance measurements. Retain original footage when making trimmed/cropped viewing copies.
- Do not change security settings for performance. Record access limitations rather than obscuring them.
- Pure PowerShell here means game/encoder algorithms written in PowerShell using standard .NET APIs. Any compiled custom helper must be identified separately.
- Run codec correctness checks when modifying encoding, and appropriate targeted benchmarks when making performance claims.
- The user clarified that both engine and rendering algorithms must stay in PowerShell. Do not meet the 320x200/60 FPS target by substituting a C/C# engine, custom compiled renderer/encoder, or GPU rendering shader. Standard .NET data structures, bulk copying, synchronization, and IPC primitives are allowed within the study's existing definition.
