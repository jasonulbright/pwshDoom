# pwshDoom feasibility study

An investigation into running classic Doom logic in PowerShell 7 and presenting frames inside Windows Terminal. Started 2026-09-10. This repository contains research, reproducible experiments, and results; it is not yet a Doom port.

The objective is to find out what works on real hardware before choosing an engine or writing a large project plan. Existing PowerShell Doom work is acknowledged explicitly. A new combination of components is not automatically a first-of-its-kind achievement.

## Read the investigation

- [First findings](docs/findings-2026-09-10.md): measured outcomes, limitations, and the next useful experiment.
- [Ledger](docs/ledger.md): dated decisions, observations, corrections, and experiment outcomes.
- [Existing implementations](docs/existing-implementations.md): evidence and gaps in current offerings.
- [Terminal architecture](docs/terminal-architecture.md): the PowerShell/ConPTY/Terminal boundary and relevant features.
- [Experiment protocol](docs/experiment-protocol.md): measurements, controls, and interpretation.
- [Reproduction steps](docs/reproduce.md): run the finite benchmarks and clean up the study profile.
- `results/`: portable summaries and machine-readable measurements.
- `local/`: ignored machine-specific inventories, downloaded tools, external checkouts, and copyrighted test material.

## Rules of evidence

Use **measured**, **source-inspected**, **author-reported**, **hypothesis**, or **not tested** when recording a finding. A script's completed writes are not proof of displayed frames. A screenshot is not proof of frame rate. A working map is not proof of a complete Doom implementation.

Commercial WAD files remain user supplied. Do not commit game assets, extracted frames, downloaded binaries, or external source trees. Preserve upstream license terms before incorporating upstream code; inspection alone is not an adoption decision.

All experiments must be finite and write their results to disk. Keep security settings unchanged. Record failures and changes to the protocol, including environment interference.
