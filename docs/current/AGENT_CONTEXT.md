# AGENT_CONTEXT

This file is the canonical quick-prime context for assistant sessions working in
the `flux` super-repo.

## Ecosystem purpose

`flux` is a modular R ecosystem for simulation modeling of probabilistic dynamic
systems in irregular time.

## Super-repo layout

- `subrepos/`: package submodules (`fluxCore`, `fluxPrepare`, `fluxForecast`,
  `fluxValidation`, `fluxOrchestrate`, `fluxASCVD`, `fluxModelTemplate`)
- `tests_ecosystem/`: cross-package integration harness
- `docs/`: current docs, archived prompt corpus, release announcements, and book scaffold
- `resources/scripts/release/release_ecosystem.sh`: coordinated release helper

## Design priorities

- Keep core architecture event-driven and deterministic.
- Preserve low barrier to entry with progressive advanced capability.
- Prefer explicit contracts over hidden coupling.
- Maintain backward compatibility when introducing new capability layers.

## Current strategic themes

- v2.0.0 planning focuses on:
  - action/policy integration as first-class event stream
  - context contract modernization beyond catch-all `ctx`
  - trajectory logging for audit and ABM/RL compatibility
- Super-repo organization and developer ergonomics improvements are ongoing.

## Current release state

- Ecosystem is released at `v1.10.2` (super-repo, fluxCore). fluxForecast remains at `v1.10.1`. The other 5 subrepos remain at `v1.10.0`; their dependency floors stay `(>= 1.10.0)`.
- v1.10.2 is a focused fluxCore patch addressing an API ergonomics issue surfaced during v1.10.1 tutorial polish:
  - fluxCore: new `Engine$new(bundle = ...)` shortcut for inline / in-memory bundles. Removes the `provider = list(load = function(...) bundle)` boilerplate that was the user's first encounter with fluxCore. Fully additive — `provider = ...` path unchanged.
  - Tutorial 01 renamed to "Engine and ModelBundle scaffold"; both call sites use the new shortcut.
- v1.10.1 was a coordinated patch tightening v1.10.0's headline schema features:
  - fluxCore: removed `id_string` type, added `percent` type, rewrote `set_schema()` with hybrid `vars` syntax (string OR list spec per element) and explicit `overwrite` / `remove` controls.
  - fluxForecast: `validate_forecast()` now delegates schema validation to `fluxCore::schema_validate()` (single source of truth; eliminated duplicated allow-list).
  - Super-repo: `header_logo.png` and release/maintenance scripts moved under `resources/`; vestigial top-level `reports/` removed.
- Release tags and GitHub releases for `v1.10.2` are published for: `flux`, `fluxCore`. fluxForecast and other subrepos remain at their existing `v1.10.1` / `v1.10.0` releases.
- Resolved issue closures after `v1.10.0`:
  - `flux#8` (refresh_rules/proposal contract hardening)
  - `flux#9` (broken tutorial code)
  - `fluxCore#1` (schema type doc mismatch)
  - `fluxCore#2` (init state validation hardening + low-friction validator presets) — closed after v1.10.2 + tutorial polish.

## Next active issue

No fluxCore-level work item is currently in flight. Open trackers (`flux#1`, `flux#4`, `flux#7`, `flux#10`) are forward-looking (v2 API/policy planning, Python interop scan, formal plumber API scaffold, ecosystem-wide roxygen migration) and do not have an immediate next-step plan attached to them.

## Collaboration norms

- Update docs and tests when changing scripts or contracts.
- Keep super-repo automation path-stable (`Makefile`, `tests_ecosystem`, release scripts).
- For path-sensitive changes, validate with `make ecosystem-all`.
