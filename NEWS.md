# flux ecosystem news

## 1.5.1

- Reorganized package submodules under `subrepos/` and updated super-repo
  automation scripts to use the new paths.
- Archived legacy single-thread ChatGPT prompt corpus under
  `docs/archive/chatgpt_prompts/`.
- Added `docs/README.md` and `docs/current/AGENT_CONTEXT.md` to provide a clear
  current-vs-archive docs structure and session re-prime scaffold.
- Imported and integrated a bookdown scaffold under `docs/book/`.
- Clarified book scaffold messaging:
  - title now `Book Planned`
  - subtitle now blank
  - preface and book README explicitly state this is planned work with scaffold
    content in place.

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
- Reorganized package submodules under `subrepos/` to reduce root-level clutter
  and limit future migration burden.
