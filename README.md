![flux Ecosystem](./resources/images/header_logo.png)

[![Release](https://img.shields.io/github/v/release/jarrod-dalton/flux?display_name=tag)](https://github.com/jarrod-dalton/flux/releases)
[![r-universe](https://jarrod-dalton.r-universe.dev/badges/flux)](https://jarrod-dalton.r-universe.dev/flux)
[![Ecosystem Tests](https://img.shields.io/badge/tests-3_tiers-brightgreen)](./tests_ecosystem/README.md)
[![Language: R](https://img.shields.io/badge/language-R-276DC3?logo=r&logoColor=white)](https://www.r-project.org/)

`flux` is a modular R ecosystem for simulation modeling of probabilistic dynamic systems in irregular time.

This super-repo coordinates the package stack, ecosystem-level testing, and cross-repo releases.

---

### What's new in v2.0.0

flux v2.0.0 makes decisions a formal part of how models are written. You declare a **decision point** on your schema — a checkpoint where the engine pauses, asks a policy function what to do, and logs the full record of what was observed, proposed, and realized. That log is your decision audit trail. You can pull it out as a data frame at the end of any run.

Parameter uncertainty is cleaner too. Your bundle declares a single function that draws `n` parameter sets, and the engine handles the crossing — every entity runs under every draw, fully tracked. No bespoke scaffolding.

The old freeform `ctx` argument is gone, replaced by typed objects (`ParamContext`, `SimContext`, `RuntimeContext`) that make callback contracts explicit. And `load_model()` provides a validated assembly step for wiring schema, bundle, policy, and runtime config together safely.

For full details, see the [v2.0.0 release announcement](./docs/release_announcements/v2.0.0.md) — or jump straight into [Tutorial 01](./tutorials/01_core_engine_scaffold.md) (which covers the engine, parameter draws, and refresh rules) and [Tutorial 03](./tutorials/03_decisions_policy.md) (decisions and policy).

---

## One-Line Install (Core Stack)

Install the core flux ecosystem packages in one step:

```r
# Latest stable release (recommended):
install.packages("flux", repos = "https://jarrod-dalton.r-universe.dev")

# Pre-release install from source code:
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

- Release line: `v2.0.0`
- See the [GitHub releases page](https://github.com/jarrod-dalton/flux/releases) for full history.

## Book scaffold

- Bookdown scaffold for long-form ecosystem documentation lives in
  `docs/work_in_progress/book/`.
