![flux Ecosystem](./resources/images/header_logo.png)

[![Release](https://img.shields.io/github/v/release/jarrod-dalton/flux?display_name=tag)](https://github.com/jarrod-dalton/flux/releases)
[![fluxCore CRAN downloads](https://cranlogs.r-pkg.org/badges/grand-total/fluxCore)](https://CRAN.R-project.org/package=fluxCore)
[![Ecosystem Tests](https://img.shields.io/badge/tests-3_tiers-brightgreen)](./tests_ecosystem/README.md)
[![Language: R](https://img.shields.io/badge/language-R-276DC3?logo=r&logoColor=white)](https://www.r-project.org/)

`flux` is a modular R ecosystem for simulation modeling of probabilistic dynamic systems in irregular time.

This super-repo coordinates the package stack, ecosystem-level testing, and cross-repo releases.

---

### Latest coordinated release: v2.1.0

flux v2.1.0 hardens decision and action handling across the ecosystem, with
clearer pending-action behavior, fail-fast callbacks, consistent cohort run
identity, reproducible seeding, and stricter model-clock and parameter
contracts. It also adds grouped decision points, allowing related decisions to
share one policy consultation while their staged actions retain independent
timing.

See the [v2.1.0 release announcement](./docs/release_announcements/v2.1.0.md),
[Tutorial 03](./tutorials/03_decisions_policy.md) for decision/action lifecycles
and grouped decisions, or [Tutorial 01](./tutorials/01_core_engine_scaffold.md)
for the engine and parameter draws.

---

## Installation

The `flux` meta-package currently installs the latest source versions of the
core ecosystem packages from GitHub:

```r
install.packages("remotes")
remotes::install_github("jarrod-dalton/flux")
```

`fluxCore` is also available independently as a stable release from
[CRAN](https://CRAN.R-project.org/package=fluxCore):

```r
install.packages("fluxCore")
```

This meta-package installs:

- `fluxCore`
- `fluxPrepare`
- `fluxForecast`
- `fluxValidation`
- `fluxOrchestrate`

Reference/demo packages remain separate from meta-package installation:

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

- Release line: `v2.1.0`
- See the [GitHub releases page](https://github.com/jarrod-dalton/flux/releases) for full history.

## Book scaffold

- Bookdown scaffold for long-form ecosystem documentation lives in
  `docs/work_in_progress/book/`.
