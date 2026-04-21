# Progress and Work Plan

This document records the current state of the flux ecosystem and the intended sequence of near-horizon work.

It is the only document in the prompt corpus that is expected to change frequently.

All other documents define stable intent, contracts, and rules.

---

## Next Steps

### 1. ASCVD end-to-end demonstration of ecosystem capabilities

The goal of this workstream is not a minimal example. It is a staged, credible demonstration that the ecosystem can support realistic modeling workflows from data preparation through simulation, summarization, and validation, and ultimately into multi-model orchestration where appropriate.

This work should proceed in stages to avoid conflating infrastructure issues with model design issues.

---

#### 1.1 Catch fluxASCVD up to v1.3.0 infrastructure

ASCVD has now been modernized to align with v1.3.0 contracts and conventions (schema, time semantics, bundle interfaces), and was rebuilt conservatively to avoid relying on legacy assumptions.

Current status:
- ASCVD installs and tests cleanly under v1.3.0
- simulations run reproducibly using Core semantics
- Forecast summaries can be produced without contract violations
- legacy drift has been resolved explicitly (or removed) rather than patched around

Residual work is primarily demonstration-layer refinement (vignettes + documentation), not infrastructure alignment.

---

#### 1.2 Vignettes demonstrating major ecosystem workflows

After ASCVD is caught up to v1.3.0 infrastructure, expand the demonstration layer through targeted vignettes. These need not be a single large vignette; multiple focused vignettes are preferred.

Status update:
- Vignette 1 (model/schema) has been drafted and builds cleanly.
- Vignette 2 (Prepare / EHR analysis lens) has been drafted and now builds cleanly after corrections to follow-up and death-time handling.
- Vignette 3 (training event-rate models) is under active revision and is not yet satisfactory from a pedagogical standpoint.

Recent work surfaced important design and documentation issues:
- Prepare has now been extended to support event-process TTV construction with explicit time segmentation controls.
- ASCVD has been rewired to use Prepare’s event-process machinery rather than bespoke interval logic.
- However, current vignettes rely too heavily on helper functions that obscure how tables and model inputs are constructed.
- As a result, additional vignette refactoring is required so that mechanics are visible and intelligible to a general health services research audience.

Planned demonstration vignettes include, in no particular order:

- **Prepare as an EHR lens**
  - construction of observation tables
  - event-defined interval boundaries
  - time segmentation and meaningful-change rules
  - explicit attachment of covariates to interval start times

- **Training event-process models**
  - constant hazard and Poisson rate models
  - progression to cause-specific Cox or parametric alternatives
  - clear distinction between estimation-time segmentation and runtime refresh behavior

- **After that: Vignettes Demonstrating Forecast / Validation / Orchestrate**
  - use ASCVD as the anchor model
  - introduce a simple hospital episode model (training optional)
  - demonstrate orchestration logic governing what updates propagate to entity state
  - emphasize coordination mechanics rather than clinical realism

These vignettes should be explicit about analyst discipline, including the distinction between observations and state, time segmentation versus entity splits, avoidance of leakage, and consistency with Core time semantics.

---

#### 1.3 Ordered learning progression

The intended learning progression for demonstrations remains:

1. single-model construction  
2. single-model forecasting  
3. single-model validation  
4. multi-model orchestration  

Orchestration should not be treated as the default modeling approach. It is an advanced capability to be demonstrated once the single-model pipeline is coherent.

---

### 2. Template refresh (post-ASCVD)

After ASCVD is updated and the demonstrations expose real friction points, refresh fluxModelTemplate so new model authors inherit current best practice rather than legacy assumptions.

Success looks like:
- the template reflects v1.3.0 schema requirements and Core-owned schema helpers
- the template reflects v1.3.0 time semantics (`entity$last_time`, numeric model time)
- scaffolds remain ordered and well-commented to guide teams through model development
- the template is conservative but practically usable without violating ecosystem contracts

This work should be informed by lessons learned during the ASCVD demonstrations.

---

### 3. Interventions and policy optimization (design exploration)

The ecosystem is expected to eventually support counterfactual evaluation of alternative treatment decisions and policies.

A plausible future direction is to distinguish clinical decisions (interventions) from ordinary state variables and to introduce a new package focused on policy definition and evaluation.

This work must begin as a design exploration rather than an implementation task.

Success for the initial design phase looks like:
- a clear definition of what constitutes an intervention in this ecosystem
- a strategy for separating clinical decisions from state variables without weakening Core contracts
- a plan for safe reconstruction and evaluation of interventions
- a clear statement of whether Entity structure must change, and why
- an explicit re-test strategy across all ecosystem packages if Entity semantics are modified

Any change that modifies Entity structure or Core semantics must be approached conservatively and accompanied by ecosystem-wide testing.

---

### 4. Validation semantics deepening

After ASCVD demonstrations establish a coherent baseline, consider deepening Validation semantics and documentation.

Success looks like:
- clearer guidance on denominator construction and masking strategies
- explicit treatment of common eligibility and censoring patterns
- additional examples or utilities only where they reduce repeated user error without hiding semantics

---

## Completed Steps

### v1.3.0 coordinated ecosystem release

All seven packages were brought to version 1.3.0 and validated end-to-end.

Key outcomes:
- fluxPrepare is now part of the coordinated ecosystem release line
- schema validation and schema helper workflows are consolidated under Core ownership
- time semantics are consistent across packages, with calendar time supported only in data-facing contexts
- all packages install cleanly from GitHub
- all unit tests pass across the ecosystem

---

### ASCVD modernization and Prepare-driven refactor (substantial progress)

fluxASCVD has undergone a substantial refactor to align with evolving Core and Prepare capabilities.

Key outcomes:
- Core was extended with `Entity$meta` to support runtime bookkeeping (e.g., event refresh cadence) without polluting entity state.
- Prepare was extended to support event-process TTV construction with explicit time segmentation controls.
- ASCVD was rewired to use Prepare’s event-process machinery rather than bespoke interval logic.
- Slow event processes (e.g., major clinical events) now retain proposed event times across frequent state updates, with refresh triggered only by cadence or meaningful change.
- Follow-up and death handling were corrected so that death is consistently represented as a time, not a logical indicator.
- Covariates are now explicitly attached to interval start times (`t0`) for model training.

This work resolved several long-standing ambiguities around irregular observation times, semi-Markov dynamics, and runtime refresh behavior.

---

## Notes and watch-outs

- ASCVD vignettes require further refinement to improve pedagogical clarity.
- Helper functions should not obscure critical modeling steps in demonstrations.
- Orchestration remains an advanced capability and should be demonstrated only after the single-model pipeline is well understood.
- Any proposal that modifies Entity structure or Core semantics requires explicit design review and ecosystem-wide re-testing.
