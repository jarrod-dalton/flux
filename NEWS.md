# flux ecosystem news

## 1.5.0

- Introduced a top-level `flux` super-repo with package submodules:
  `fluxCore`, `fluxPrepare`, `fluxForecast`, `fluxValidation`,
  `fluxOrchestrate`, `fluxASCVD`, and `fluxModelTemplate`.
- Added a root `Makefile` for standardized ecosystem test and release commands.
- Added `tests_ecosystem/` tiered cross-package harness with consolidated
  reporting via `run_all.R`.
- Improved Tier 1 and Tier 3 test output with explicit step-by-step pass/fail
  logging for better observability.
- Standardized report generation so each `make ecosystem-*` invocation produces
  one consolidated report file.
- Added report retention controls (`FLUX_MAX_REPORTS`, default 10) and a cleanup
  target (`make ecosystem-clean-reports`).
- Added maintainer migration helper script to sync submodule URLs after GitHub
  repository renames.
