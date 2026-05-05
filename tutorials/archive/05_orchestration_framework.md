## What orchestration means in the flux ecosystem

In **fluxCore**, a simulation run advances by repeatedly:

1. asking a *bundle* to **propose** candidate next events (a "menu" of options),
2. selecting the **single** next event globally (earliest time; deterministic tie-break by `process_id`),
3. applying the selected event via `transition()` which returns state updates.

A *proposal* is **not** an event that has happened. It is a candidate event that *could* happen next,
including its proposed time and payload (what the event is and anything needed to apply it).

Orchestration extends this to multiple sub-models (bundles) that share a single entity state and a
single timeline, while keeping the Core engine unchanged.

## Policy-driven orchestration

`orchestrated_bundle()` wraps a list of sub-model bundles and uses `policy` callbacks to control:

- **Eligibility gating**: which models are allowed to propose events right now
- **Deterministic precedence**: if two proposals occur at the same time, which should win
- **Cross-model payloads**: after an event happens, what additional shared state updates should occur
- **Stop semantics**: how to decide when the overall run should stop

### Eligibility gating (lock-out)

If an entity is hospitalized, you may want to avoid evaluating proposals from an outpatient chronic
disease model. Use:

- `policy$eligible_models(entity, ctx)` to return only the hospital model while inpatient.

This both (a) prevents irrelevant event competition and (b) saves computation, because ineligible
models are not called.

### Precedence without changing the Core engine

The Core engine breaks same-time ties by sorting on `process_id`. Orchestration leverages this by
encoding a numeric priority into the `process_id`:

- `priority_pid(priority, model_id, sub_pid)`

Lower `priority` values sort earlier and therefore win ties deterministically.

## Sparse proposals (efficiency)

Sub-models can propose events *sparsely*:

- **Option A** (proposal caching): reuse `current_proposals` when still valid
- **Option B** (state cursors): store "next scheduled time" in entity state (e.g., `next_followup_time`)

Orchestration is compatible with both. In practice:
- gating (eligibility) is the biggest win during episodes (e.g., inpatient stays),
- cursors are excellent for routine schedules (clinic follow-ups).

## Toy hospitalization model

This package provides `hospital_toy_bundle()` as a minimal episode model:

- proposes `admit` when outpatient
- proposes `discharge` when inpatient
- flips `care_mode` and `in_hospital` on transitions

It is intentionally simple and useful for unit tests and demonstrations.


``` r
library(fluxCore)
library(fluxOrchestrate)

hosp <- hospital_toy_bundle()

# A placeholder chronic model bundle (your real use case would be fluxASCVD)
chronic <- list(
  name = "chronic",
  schema = list(),
  propose_events = function(entity, ctx=NULL, process_ids=NULL, current_proposals=NULL) {
    list(routine = list(event_type="clinic_visit", time_next = entity$as_list("time")$time + 0.5))
  },
  transition = function(entity, event, ctx=NULL) list(),
  stop = function(entity, event=NULL, ctx=NULL) FALSE
)

bundle <- orchestrated_bundle(
  models = list(hosp = hosp, chronic = chronic),
  policy = list(
    eligible_models = function(entity, ctx=NULL) {
      mode <- entity$as_list("care_mode")$care_mode
      if (mode == "inpatient") return("hosp")
      c("hosp","chronic")
    },
    event_priority = function(proposal, entity, ctx=NULL) {
      if (proposal$event_type %in% c("admit","discharge")) return(10L)
      200L
    }
  )
)
```

## Patterns for outpatient scheduling during hospitalization

A common design choice is what happens to a scheduled outpatient clinic visit during an inpatient stay.

- **Pattern 1 (pause/resume)**: preserve the next scheduled outpatient follow-up and simply avoid
  evaluating outpatient proposals while inpatient. Upon discharge, outpatient scheduling resumes.
- **Pattern 3 (teachable advanced)**: add a *separate* post-discharge follow-up process (e.g., a 1-week
  visit) that activates only after discharge, while leaving the routine schedule unchanged.

The flux ecosystem typically demonstrates Pattern 1 first to teach the core orchestration mechanics,
and then introduces Pattern 3 to show clean, explicit multi-process scheduling.
