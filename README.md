# flux Ecosystem Super-Repo

Top-level coordination repo for the flux package ecosystem.

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
