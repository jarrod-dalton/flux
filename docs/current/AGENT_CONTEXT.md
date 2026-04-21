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
- `release_1_5_0.sh`: coordinated release helper

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

## Collaboration norms

- Update docs and tests when changing scripts or contracts.
- Keep super-repo automation path-stable (`Makefile`, `tests_ecosystem`, release scripts).
- For path-sensitive changes, validate with `make ecosystem-all`.
