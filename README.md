# flux Ecosystem Super-Repo

`flux` is a modular R ecosystem for simulation modeling of probabilistic dynamic systems in irregular time.

This super-repo coordinates the package stack, ecosystem-level testing, and cross-repo releases.

## Why flux

- Event-driven architecture with explicit state transitions
- Irregular-time workflows for realistic longitudinal simulation
- Separation of concerns across preparation, simulation, forecasting, validation, and orchestration
- Reproducible, testable package ecosystem with shared contracts

## What lives here

- Release orchestration script: `release_1_5_0.sh`
- Cross-package integration test harness: `tests_ecosystem/`
- Shared docs/notes for the ecosystem: `docs/`
- Git submodules for package repos:
  - `fluxCore`
  - `fluxPrepare`
  - `fluxForecast`
  - `fluxValidation`
  - `fluxOrchestrate`
  - `fluxASCVD`
  - `fluxModelTemplate`

## Ecosystem map

- `fluxCore`: simulation engine and entity/state/event contracts
- `fluxPrepare`: train/test/validation data preparation pipelines
- `fluxForecast`: simulation execution wrappers and summary estimators
- `fluxValidation`: apples-to-apples prediction vs observed evaluation
- `fluxOrchestrate`: multi-process event arbitration over shared timelines
- `fluxASCVD`: concrete reference model package
- `fluxModelTemplate`: scaffold for new flux-compatible model packages

## Clone

```bash
git clone --recurse-submodules <this-repo-url>
```

If already cloned without submodules:

```bash
git submodule update --init --recursive
```

## Common commands

```bash
make ecosystem-tier1
make ecosystem-tier2
make ecosystem-tier3
make ecosystem-all
make release-dry
```

## Release line

- Current ecosystem release: `v1.5.0`
