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
- Engine = Schema (portable, data-only) + ModelBundle (language-native) + optional runtime components.
- `ctx` replaced by formal typed contexts in v2.0.0 (`SimContext`, `ParamContext`, `RuntimeContext`, `EnvironmentContext`).

## Current strategic themes

- v2.0.0 planning is the primary current focus:
  - Full architecture plan at `docs/current/v2.0_plan.md` (v0.1.4).
  - Stage 0 (red-flag discovery) complete; Stage 1 (contract freeze) complete; Stage 2 core implementation complete through 2A/2B (RNG normalization + policy scaffolding).
  - Action/policy integration as first-class event stream.
  - `ctx` replaced by formal typed contexts (`SimContext`, `ParamContext`, `RuntimeContext`, `EnvironmentContext`).
  - No user-facing `ctx` back-compat in v2.0.0 (fail fast on `ctx`-style usage).
  - `load_model()` replaces `ModelProvider` as the recommended assembly entry point.
  - Trajectory logging for audit and RL compatibility via `TrajectoryRecord`.
  - Tracking: flux issue #1 (v2.0 planning), flux issue #4 (Python portability).

## Current release state

- All 5 production packages and the flux super-repo are at **v1.11.0**. All GitHub releases are published (non-draft, non-prerelease).
  - fluxCore v1.11.0 → tag `v1.11.0` → commit `9814f14`
  - fluxForecast v1.11.0 → tag `v1.11.0` → commit `e37abc2`
  - fluxPrepare v1.11.0 → tag `v1.11.0` → commit `6e37baf`
  - fluxValidation v1.11.0 → tag `v1.11.0` → commit `4e79264`
  - fluxOrchestrate v1.11.0 → tag `v1.11.0` → commit `c363c51`
  - flux (super-repo) v1.11.0 → commit `35a00b7`
- Non-production repos (fluxASCVD, fluxModelTemplate) not included in coordinated release.
- v1.11.0 headline changes:
  - Ecosystem-wide inline roxygen migration (flux#10 closed).
  - fluxOrchestrate: hospital entity init failure fixed (fluxOrchestrate#1 closed).
  - fluxForecast: `state_summary()` type dispatch extended to full numeric type family (fluxForecast#2 closed).
  - fluxCore: full type taxonomy including `logical`, `binary`, `integer`, `count`, `nonnegative_integer`, `positive_integer`, `numeric`, `nonnegative_numeric`, `positive_numeric`, `probability`, `percent`, `categorical`, `ordinal`, `string`, `nonempty_string`.
- Open issues after v1.11.0:
  - `flux#1`: v2.0.0 planning — Stage 2A/2B complete; Stage 3 complete in `fluxCore` (`feature/v2-core-skeleton` @ `8d95749`); Stage 4 decomposition planning is current
  - `flux#4`: Python portability red-flag scan — Stage 0 complete, informing v2.0 design
  - `flux#7`: plumber API scaffold — not yet started

## Next active work

- **Stage 4 decomposition planning** (`flux#1`): produce a detailed Stage 4 plan (4A/4B/4C...) before downstream package migration begins.
- Stage 4 code migration is paused until decomposition checkpoints and package order are approved.
- Stage 2 delivered in `fluxCore` includes: typed context/runtime integration in `run_cohort()`, v2-mode `ctx` fail-fast for cohort path, policy dispatch at schema decision points, and deterministic Stage 2A/2B test coverage.
- `flux#7` (plumber API scaffold) is open but not scheduled.

## Collaboration norms

- Update docs and tests when changing scripts or contracts.
- Keep super-repo automation path-stable (`Makefile`, `tests_ecosystem`, release scripts).
- For path-sensitive changes, validate with `make ecosystem-all`.
