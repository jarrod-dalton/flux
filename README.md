# flux Ecosystem Super-Repo
[![Release](https://img.shields.io/github/v/release/jarrod-dalton/flux?display_name=tag)](https://github.com/jarrod-dalton/flux/releases)
[![Downloads](https://img.shields.io/github/downloads/jarrod-dalton/flux/total)](https://github.com/jarrod-dalton/flux/releases)
[![Ecosystem Tests](https://img.shields.io/badge/tests-3_tiers-brightgreen)](./tests_ecosystem/README.md)
[![Language: R](https://img.shields.io/badge/language-R-276DC3?logo=r&logoColor=white)](https://www.r-project.org/)

`flux` is a modular R ecosystem for simulation modeling of probabilistic dynamic systems in irregular time.

This super-repo coordinates the package stack, ecosystem-level testing, and cross-repo releases.

## One-Line Install (Core Stack)

Install the core flux ecosystem packages in one step:

```r
remotes::install_github("jarrod-dalton/flux")
```

This meta-package installs:

- `fluxCore`
- `fluxPrepare`
- `fluxForecast`
- `fluxValidation`
- `fluxOrchestrate`

Reference/demo packages remain separate:

- `fluxASCVD`
- `fluxModelTemplate`

## Start Here

- Canonical tutorials live in [`tutorials/`](./tutorials/)
- Beginner entry point: [`tutorials/00_start_here.md`](./tutorials/00_start_here.md)

## Why flux

- Event-driven architecture with explicit state transitions
- Irregular-time workflows for realistic longitudinal simulation
- Separation of concerns across preparation, simulation, forecasting, validation, and orchestration
- Reproducible, testable package ecosystem with shared contracts

## What lives here

- Release orchestration script: `scripts/release/release_ecosystem.sh`
- Cross-package integration test harness: `tests_ecosystem/`
- Shared docs/notes for the ecosystem: `docs/`
- Git submodules for package repos (under `subrepos/`):
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

- Current ecosystem release: `v1.8.0`

## Book scaffold

- Bookdown scaffold for long-form ecosystem documentation lives in
  `docs/work_in_progress/book/`.
