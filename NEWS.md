# flux ecosystem news

## 1.10.1

- **fluxCore patch**: `id_string` type removed; new `percent` type added; `set_schema()` rewritten with hybrid `vars` syntax and explicit `overwrite` / `remove` controls (replaces the previous `replace = ` / `add = ` flags). Supported type list is now 14 entries (correction to v1.10.0's "14 types" claim post `id_string` removal + `percent` addition).
- **fluxForecast patch**: `validate_forecast()` now delegates schema validation to `fluxCore::schema_validate()`, eliminating the duplicated type allow-list. Dependency floor bumped to `fluxCore (>= 1.10.1)`.
- **Super-repo cleanup**: `header_logo.png` moved to `resources/images/`; release and maintenance scripts moved to `resources/scripts/`. Vestigial top-level `reports/` directory removed.
- **Tutorial 01 refresh**: `set_schema()` example now demonstrates the hybrid syntax (categorical via levels list, percent, positive_numeric with `max`, count, probability) and uses the result variable name `quicker_schema`.

## 1.10.0

- **Expanded schema type system**: introduced 14 supported variable types (logical, binary, integer variants, numeric variants, probability, categorical, ordinal, string variants) with built-in validation strategies.
- **Streamlined schema authoring**: added `set_schema()` helper function for simplified variable registration with automatic type-specific defaults (`coerce` and `default` values).
- **Enhanced schema flexibility**: `default` and `coerce` fields are now optional; fluxCore automatically applies type-appropriate defaults when not specified.
- **Backward compatibility**: maintained "continuous" type alias mapping to "numeric" for existing code.
- **Updated documentation**: expanded schema specification docs and tutorial examples showcasing both manual and `set_schema()` workflows.
- **Ecosystem alignment**: updated fluxForecast type validation, fluxOrchestrate schemas, and test fixtures across subrepos to support new type system.

## 1.9.0

- Coordinated ecosystem release alignment to version 1.9.0 across the super-repo and package subrepos.
- fluxCore API hardening: removed implicit runtime defaults (no package-level default schema/bundle), made `PackageProvider` require explicit registry, and migrated internal defaults to test fixtures.
- Documentation cleanup: removed legacy constructor/default references, refreshed urban-delivery examples in core docs/tutorials, and aligned orchestration/model-template wording with optional lifecycle semantics.
- Cross-package test fixtures now avoid reaching into fluxCore internals for default schema helpers.

## 1.8.1

- Targeted patch release for two subrepos:
  - `fluxCore` 1.8.1: `refresh_rules` contract hardening with fail-fast
    validation, clearer errors, and added tests/docs.
  - `fluxModelTemplate` 1.8.1: runnable instructional scaffolds with expanded
    end-to-end template tests.
- No coordinated version bump across the full ecosystem in this patch.

## 1.8.0

- Added an installable root `flux` meta-package so users can install the core
  ecosystem with `remotes::install_github("jarrod-dalton/flux")`.
- Updated super-repo README install guidance and release line to `v1.8.0`.
- Coordinated ecosystem release alignment to `1.8.0` across subrepos and
  internal dependency floors.

## 1.7.0

- Coordinated ecosystem version alignment: all package subrepos are now at
  `1.7.0`.
- Package dependency floors were synchronized across subrepos to `>= 1.7.0`
  for flux-internal dependencies.
- Includes canonical-time contract work completed in recent package updates:
  `bundle$time_spec` is the primary runtime source of model time semantics,
  with runtime override paths removed from affected APIs.

## 1.5.1

- Reorganized package submodules under `subrepos/` and updated super-repo
  automation scripts to use the new paths.
- Archived legacy single-thread ChatGPT prompt corpus under
  `docs/archive/chatgpt_prompts/`.
- Added `docs/README.md` and `docs/current/AGENT_CONTEXT.md` to provide a clear
  current-vs-archive docs structure and session re-prime scaffold.
- Imported and integrated a bookdown scaffold under
  `docs/work_in_progress/book/`.
- Added `docs/work_in_progress/` convention for exploratory materials, including
  API drafts and pre-book content.
- Sunset the prototype `fluxCore/inst/plumber/sim_api.R` package-shipped API
  stub and moved it to `docs/work_in_progress/api/` pending formalized API
  scaffold design.
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
