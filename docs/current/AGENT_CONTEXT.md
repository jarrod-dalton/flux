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
- `tutorials/`: active tutorials (`00_start_here.md`, `01_core_engine_scaffold.md`, `02_prepare_ttv.md`)
- `tutorials/archive/`: archived tutorials 03–08 (stale/underdeveloped; to be rebuilt for v2)
- `tutorials/src/`: Rmd/R sources for active tutorials

## Design priorities

- Keep core architecture event-driven and deterministic.
- Preserve low barrier to entry with progressive advanced capability.
- Prefer explicit contracts over hidden coupling.
- Engine = Schema (portable, data-only) + ModelBundle (language-native) + optional runtime components.
- `ctx` fully removed in v2.0.0. Formal typed contexts: `SimContext`, `ParamContext`, `RuntimeContext`, `EnvironmentContext`.
- `Engine$new(bundle=)` and `load_model()` are the sole Engine construction paths. `ModelProvider`/`provider=` removed.

## Current stage

**Ecosystem hardening — pre-v2.0.0 release**

All architecture stages (0–6) complete. See `docs/archive/plans/v2.0_plan.md` (v0.2.2) for full history.

Remaining before v2.0.0 tag:
- **Stage 4C** (fluxOrchestrate): test-only `ctx` → `sim_ctx`/`param_ctx` callback migration (source already clean)
- **Ecosystem hardening**: Tier 3 ASCVD demo tests; fluxCore warn→error for legacy `ctx` formals; D/P/A coverage in fluxASCVD
- **v2.0.0 tag + release announcement**

flux#4 (Python portability) closed — all red-flag findings resolved.
flux#1 (v2.0 planning) pending final hardening pass and v2.0.0 tag.
flux#11 (fluxSim) is the first post-release work item.

## Current test baselines (2026-05-05)

| Package | Result |
|---------|--------|
| fluxCore (`feature/v2-core-skeleton`) | FAIL 0 \| WARN 3 \| SKIP 2 \| PASS 337 |
| fluxPrepare | FAIL 0 \| WARN 0 \| SKIP 4 \| PASS 150 |
| fluxForecast | FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 59 |
| fluxValidation | FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 48 |
| fluxOrchestrate | FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 42 |
| fluxModelTemplate | FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 31 |
| Tier 1 smoke | PASS |
| Tier 2 (all packages) | PASS |

## Branch state

- `fluxCore`: `feature/v2-core-skeleton` (not yet merged to main; v2.0 release will merge)
- All other packages: `main`

## Key open issues

- `flux#1`: v2.0.0 planning — Stage 4C + hardening remain; #11 referenced for post-release
- `flux#7`: plumber API scaffold — not yet scheduled
- `flux#11`: fluxSim design proposal — first post-v2.0.0 work item

## Collaboration norms

- Update docs and tests when changing scripts or contracts.
- Keep super-repo automation path-stable (`Makefile`, `tests_ecosystem`, release scripts).
- For path-sensitive changes, validate with `make ecosystem-all`.
