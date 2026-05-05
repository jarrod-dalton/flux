# Handoff Note: v2.0 Stage 3 (2026-05-03)

This note is for collaborators resuming work if the primary maintainer is offline or out of credits.

## Source of truth

- Plan: docs/current/v2.0_plan.md (v0.1.4)
- Context primer: docs/current/AGENT_CONTEXT.md
- Primary tracking issue: https://github.com/jarrod-dalton/flux/issues/1

## Current state summary

- Stage 2, 2A, and 2B are complete in fluxCore.
- Stage 3 is complete in fluxCore.
- Stage 3 hardening checkpoint is complete in fluxCore.
- Stage 3 tests include trajectory emission + JSON compatibility + serial/parallel parity checks (`mclapply` and `future`).
- Stage 4 implementation is intentionally paused pending detailed decomposition (4A/4B/4C...).

## Relevant branch / commits

- fluxCore branch: feature/v2-core-skeleton
- Prior Stage 3 implementation anchors: 24db36c (core), 8d95749 (docs/tests checkpoint)
- Current working state includes additional hardening edits not yet pinned in this note to a commit hash.

- flux super-repo main includes plan/context updates and submodule bump.

## What changed in Stage 3

- `load_model()` trajectory config normalization/validation (`detail = none|summary|full`, `summary_fn` validation).
- `Engine$run()` emits `trajectory_records` when trajectory logger is configured.
- Trajectory output is JSON-serializable (plain list records in output surface).
- Determinism parity test added for trajectory records across serial vs mclapply under fixed seed.
- fluxCore README now includes explicit trajectory output contract.

## Post-Stage-3 hardening checkpoint

- `Engine$run()` single-run path now applies RuntimeContext-compatible seed derivation.
- `run_cohort()` return docs explicitly describe `trajectory_records` in run payloads.
- Time helper docs clarify legacy `ctx` compatibility language in v2 context.
- Additional trajectory determinism guard added for serial vs `future` backend.

## Fast resume checklist

1. Ensure super-repo and submodule are up to date:
   - `cd /Users/daltonj/flux && git pull`
   - `cd subrepos/fluxCore && git checkout feature/v2-core-skeleton && git pull`
2. Run fluxCore test suite:
   - `cd /Users/daltonj/flux/subrepos/fluxCore`
   - `Rscript -e 'devtools::load_all("."); testthat::test_local(".")'`
3. Confirm expected baseline (as of this note):
   - `FAIL 0 | WARN 7 | SKIP 0 | PASS 326`
4. Review plan sections before new code:
   - Stage 3 section for closeout items
   - Stage 4 section + planning pause note

## Recommended next tasks

1. Stage 4 planning artifact:
   - Draft Stage 4A/4B/4C decomposition in docs/current/v2.0_plan.md.
   - Define package order, acceptance checks, and rollback criteria per sub-stage.
2. Stage 4 execution prep:
   - Confirm decomposition checkpoints have explicit tests and stop/go criteria.

## Notes on risk

- Biggest remaining migration risk is downstream callback/context transition from `ctx` conventions to formal typed contexts.
- Keep changes incremental and test-gated per package during Stage 4.
