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
- `docs/current/`: active working docs and this file
- `docs/archive/plans/`: archived plan documents (`v2.0_plan.md` v0.2.2, Stage 3 handoff)
- `tutorials/`: active tutorials (`00_start_here.md`, `01_core_engine_scaffold.md`, `02_cohort_forecast.md`, `03_decisions_policy.md`, `04_data_preparation_and_model_training.md`, `05_validation.md`)
- `tutorials/archive/`: archived pre-v2 tutorial drafts
- `tutorials/src/`: Rmd/R sources for active tutorials

## Design priorities

- Keep core architecture event-driven and deterministic.
- Preserve low barrier to entry with progressive advanced capability.
- Prefer explicit contracts over hidden coupling.
- Engine = Schema (portable, data-only) + ModelBundle (language-native) + optional runtime components.
- `ctx` fully removed in v2.0.0. Formal typed contexts: `SimContext`, `ParamContext`, `RuntimeContext`, `EnvironmentContext`.
- `Engine$new(bundle=)` and `load_model()` are the sole Engine construction paths. `ModelProvider`/`provider=` removed.

## Current stage

**v2.0.0 release — ready to tag**

All architecture stages (0–6) complete. All hardening items resolved. See `docs/archive/plans/v2.0_plan.md` (v0.2.3) for full history.

flux#4 (Python portability) closed — all red-flag findings resolved.
flux#1 (v2.0 planning) ready to close after v2.0.0 tag.
flux#11 (fluxSim) and flux#7 (plumber API) are the first post-release work items.

## Current test baselines (2026-06-02)

| Package | Result |
|---------|--------|
| fluxCore | FAIL 0 \| WARN 0 \| SKIP 2 \| PASS 387 |
| fluxPrepare | FAIL 0 \| WARN 0 \| SKIP 4 \| PASS 150 |
| fluxForecast | FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 59 |
| fluxValidation | FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 48 |
| fluxOrchestrate | FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 42 |
| fluxModelTemplate | FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 31 |
| Tier 1 smoke | PASS |
| Tier 2 (all packages) | PASS |

## Branch state

- All packages: `main`
- `feature/v2-core-skeleton` in fluxCore: stale snapshot, scheduled for deletion after v2.0.0 tag (remote main already contains all v2 work)

## Key open issues

- `flux#1`: v2.0.0 planning — ready to close after v2.0.0 tag
- `flux#7`: plumber API scaffold — post-v2.0.0
- `flux#11`: fluxSim design and implementation — first post-v2.0.0 work item

## Backward compatibility policy

As of v2.0.0, the ecosystem treats public API surfaces as stable. **Assume backward compatibility is required** unless explicitly told otherwise.

- Do not remove or rename exported functions, arguments, or S3/R6 methods without a deprecation cycle.
- Deprecation pattern: emit a `lifecycle::deprecate_warn()` (or equivalent `.Deprecated()`) for at least one minor version before removing.
- Adding new arguments is fine; changing default behavior of existing arguments is a breaking change and must be versioned.
- Schema field names, event names, and context slot names that appear in user-authored model bundles are public API.
- Internal helpers (`.` prefix) and unexported symbols are exempt.
- When in doubt about whether a change is breaking, treat it as breaking.

## Collaboration norms

- Update docs and tests when changing scripts or contracts.
- Keep super-repo automation path-stable (`Makefile`, `tests_ecosystem`, release scripts).
- For path-sensitive changes, validate with `make ecosystem-all`.
