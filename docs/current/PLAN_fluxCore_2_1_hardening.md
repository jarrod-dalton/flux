# Plan — fluxCore 2.1 Contract Hardening and Completion

**Status:** Contract review complete; implementation has not started.  
**Created:** 2026-08-26  
**Target:** Complete the approved Core corrections, bounded grouped-decision extension,
documentation, ecosystem handoff, and release verification for fluxCore 2.1.  
**Historical parent:** [PLAN_fluxCore_issue11_action_lifecycle.md](./PLAN_fluxCore_issue11_action_lifecycle.md)  
**Current fluxCore source:** `dff6fd6` (`Version: 2.1.0`)  
**Current super-repo source:** `a72a524`

---

## Purpose

The issue-11 plan is a completed historical record of the action-store repair that landed in
fluxCore 2.1 source. This companion plan now records the completed contract review and the
focused implementation, documentation, ecosystem-handoff, and verification work approved
before 2.1 is considered release-ready.

This file is also the durable discussion ledger. Each proposed change must be discussed on
its own merits before it becomes implementation work. A verified defect is not, by itself,
approval for a broader API or architecture change.

## Guardrails

- Prefer the smallest change that restores an already intended contract.
- Do not add generalized capability without a demonstrated model need.
- Preserve the lifecycle established by issue 11: raw-event trigger, transition or action
  handler, post-transition eligibility, policy consultation, one selected action or `NULL`,
  and independent pending slots by decision-point id.
- Keep policy selection, pending acceptance, action realization, and action effect distinct.
- Preserve backward compatibility unless the existing behavior is invalid or scientifically
  unsafe and the change is explicitly approved here.
- Implement grouped decision points only through S3's staged gates and explicit exclusions;
  do not let issue #12 become a route to workflows, rollback, joint realization, or the
  deferred S1/S2 contracts.
- Keep the completed issue-11 phases intact. Corrections to earlier conclusions belong in
  this post-landing record rather than rewriting history.
- Work one approved item at a time. After implementation and focused verification, pause for
  review before committing or starting the next item.

## Decision states

- **Agreed:** contract direction has been discussed and approved; implementation may be
  planned narrowly.
- **Under discussion:** next decision being examined; no implementation authorization.
- **Queued:** verified or suspected concern awaiting its own discussion.
- **Deferred:** valid concern intentionally assigned to a later release or separate plan.
- **Rejected:** considered and deliberately not pursued, with rationale retained here.
- **Complete:** implementation, focused tests, documentation, and review are finished.

---

## Agreed contract decisions

### A1 — Preserve the v2.0 positional `DecisionPoint()` contract

**Reference point.** The released v2.0.0 signature placed `observation_fn` and `label` in
positions seven and eight. The current 2.1 source inserted `on_pending_action` ahead of
them.

**Problem.** A valid v2.0 positional call can now pass an observation function where
`on_pending_action` is expected and fail during argument matching. No in-repository caller
is currently known to be broken; this is public-API compatibility protection.

**Agreed contract.** Retain the v2.0 argument positions and append the new option:

```r
DecisionPoint(
  id,
  trigger,
  allowed_actions = NULL,
  action_handlers = NULL,
  condition = NULL,
  audit = FALSE,
  observation_fn = NULL,
  label = NULL,
  on_pending_action = c("warn", "replace", "keep", "error")
)
```

**Implementation boundary.** This is a formal-argument reorder plus compatibility tests and
generated documentation. It does not change pending-action behavior.

- [x] Restore the v2.0 positions and append `on_pending_action`.
- [x] Add a fully positional v2.0 regression test.
- [x] Confirm named 2.1 calls and the default `"warn"` remain unchanged.
- [x] Regenerate and inspect the public documentation.

### A2 — Treat `ActionEvent$decision_point_id` as provenance

**Original purpose.** The v2 design introduced `decision_point_id` so a timeline-native
action remains self-identifying after it leaves the policy call that produced it. The v2
plan describes the field as “which decision point produced this.” It also supports manual
construction, tests, serialization, and inspection outside policy dispatch.

**Problem.** During policy dispatch, Core owns the action under the firing decision point:
that id determines the pending slot, pending policy, and action-handler lookup. Current code
nevertheless accepts an explicitly different `ActionEvent$decision_point_id`, allowing the
object exposed through trajectory or `last_event` to contradict its actual owner.

The constructor documentation's suggestion that the id may be “overridden” was never backed
by engine ownership semantics. Cross-decision routing would require a separate design for
the target decision point's allowed actions, pending slot, and handler.

**Agreed contract during policy dispatch.**

- `decision_point_id = NULL`: fill it from the firing decision point.
- Explicit exact match: accept it unchanged.
- Explicit mismatch: fail clearly, naming both ids.

Outside policy dispatch, callers may still construct a self-described `ActionEvent` with any
valid id.

**Implementation boundary.** Add one ownership-integrity check to policy dispatch and
correct the misleading documentation. Do not add cross-decision routing.

- [x] Enforce fill, exact-match, and mismatch behavior.
- [x] Test all three paths and confirm handler/pending ownership remains unchanged.
- [x] Remove “override” language while retaining manual construction.

---

## Resolved contract discussions

### D1 — Pending-action merging remains independent in 2.1

**Status:** Agreed. No general two-pass pending resolver will be added to 2.1.

After one realized event activates several ordinary decision points, Core calls their
policies and merges the selected actions into separate pending slots. Those decisions remain
semantically independent: sharing a triggering event does not create a transaction among
them, and each decision point continues to apply its own `on_pending_action` rule.

Current merging is sequential. An earlier local pending-slot assignment can therefore occur
before a later decision point raises an `on_pending_action = "error"` conflict. This is not a
demonstrated 2.1 correctness defect:

- the pending store is local to `Engine$run()`, and the error prevents a successful result
  from returning or later realizing the earlier assignment;
- the triggering event and transition were already committed before policy dispatch, so a
  two-pass pending resolver would not roll them back; and
- warning timing and random-number consumption are distinct from pending-slot mutation.

For clarity, **selection** is a policy choosing an action, **staging** is placing the selected
action in that decision point's pending slot, **realization** is the engine later choosing it
as the next event, and **effect** is its handler updating entity state. D1 changes none of
these contracts.

The shallow pending-mode assertions remain a separate test-hardening item (Q1). They should
verify that `keep` realizes the earlier action, while `replace` and the default `warn` mode
realize the newer action; they do not require a batch transaction. The `error` path should
continue to prove that the second proposal aborts the run.

#### Planned follow-up on fluxCore issue #12

- [x] Review and approve the clarification below before grouped-decision implementation.
- [x] Posted the approved clarification to
      [fluxCore issue #12](https://github.com/jarrod-dalton/fluxCore/issues/12) on
      2026-08-27.
- [x] Embed a minimal grouped-plan code example. It is intentionally contract-level R rather
      than executable fluxCore syntax while the grouped constructors and return types remain
      proposed.

Approved issue comment (reviewed and posted 2026-08-27):

> Follow-up from the fluxCore 2.1 action-lifecycle hardening review. We reviewed issue #12 alongside the existing ordinary decision-point contract and reached the following proposed implementation boundaries.
>
> ### Ordinary versus grouped decisions
>
> Ordinary decision points activated by the same event remain independent. Sharing a trigger does not create a transaction, and each ordinary decision point retains its own `on_pending_action` behavior.
>
> A `GroupedDecisionPoint` is different: one group activation determines an eligible subset of its declared members and requests one complete `DecisionPlan`. That returned plan creates an all-or-none pending-slot staging boundary.
>
> ### Schema and activation
>
> Grouped decision points should be stored separately:
>
> ```r
> set_schema(
>   ...,
>   decision_points = leaves,
>   decision_groups = groups
> )
> ```
>
> `schema$decision_points` remains the collection of canonical leaf decisions that own conditions, allowed actions, handlers, audit settings, and pending slots. `schema$decision_groups` contains trigger-bearing `GroupedDecisionPoint` declarations that reference leaf IDs.
>
> A leaf may use explicit `trigger = NULL` when it is group-only, or retain a normal trigger when it can also fire independently. During grouped activation, the group trigger opens the consultation; member triggers are not retested. Post-transition member conditions determine eligibility.
>
> If one raw event would activate the same leaf directly and through a group, or through two fired groups, Core should error before applying the transition or mutating the Entity. Otherwise, Core applies the event transition once, evaluates all activated conditions before any policy callback, and then begins policy dispatch.
>
> If no group member is eligible, `propose_plan()` is not called.
>
> ### Policy and plan completeness
>
> The grouped callback is:
>
> ```r
> policy$propose_plan(
>   grouped_decision_point,
>   eligible_decision_points,
>   entity,
>   sim_ctx,
>   param_ctx
> )
> ```
>
> `eligible_decision_points` is a named list constructed by Core. The returned `DecisionPlan$selections` must name every eligible member exactly once and no ineligible member. Each value must be one `ActionEvent` or explicit `NULL`.
>
> Explicit `NULL` means “this eligible decision was considered, but no new action was selected.” An intentional all-no-action result is therefore a complete plan containing `NULL` for every eligible member; returning bare `NULL` instead of a `DecisionPlan` is invalid.
>
> Missing `propose_plan()`, malformed plans, missing or extra selections, invalid actions, disallowed action types, and conflicting `decision_point_id` provenance should error rather than warn and silently drop part of the plan.
>
> Policies that want independent per-member choice logic can explicitly implement `propose_plan()` as an adapter around `propose_action()`. Core should not infer that fallback from a missing method or add a group-level dispatch mode.
>
> ### Complete-plan staging
>
> Before mutating any member pending slot, Core should validate the complete plan and determine every pending-action outcome:
>
> - `NULL` leaves any existing pending action unchanged.
> - `keep` validly retains the existing action and discards the new selection.
> - `replace` stages the new action silently.
> - `warn` stages the new action and queues a replacement warning.
> - `error` rejects the complete plan.
>
> If any member is invalid or produces an `error` conflict, no member pending slot changes and no replacement warning is emitted.
>
> For an otherwise accepted plan, all `warn` conflicts should be summarized in one plan-level warning emitted before the single commit. If that warning is promoted to an error, the pending slots still remain unchanged.
>
> ### Urban-delivery contract example
>
> This is proposed contract-level syntax, not yet an executable reprex. Once the feature exists, it should become a regression test and a progressive Tutorial 03 example using the shared urban food-delivery model.
>
> ```r
> dispatch_response <- DecisionPoint(
>   id = "dispatch_response",
>   trigger = NULL,
>   condition = function(entity) {
>     identical(entity$current$dispatch_mode, "assigned")
>   },
>   allowed_actions = c("accept_dispatch", "decline_dispatch"),
>   on_pending_action = "warn"
> )
>
> battery_safety <- DecisionPoint(
>   id = "battery_safety",
>   trigger = NULL,
>   condition = function(entity) {
>     entity$current$battery_pct < 20
>   },
>   allowed_actions = c("continue_shift", "return_to_depot"),
>   on_pending_action = "error"
> )
>
> post_dispatch_review <- GroupedDecisionPoint(
>   id = "post_dispatch_review",
>   trigger = "dispatch_check",
>   members = c("dispatch_response", "battery_safety")
> )
>
> policy <- list(
>   propose_plan = function(grouped_decision_point,
>                           eligible_decision_points,
>                           entity,
>                           sim_ctx,
>                           param_ctx) {
>     ids <- names(eligible_decision_points)
>
>     selections <- lapply(ids, function(id) {
>       switch(
>         id,
>         dispatch_response = ActionEvent(
>           "decline_dispatch",
>           time_next = entity$last_time + 0.25
>         ),
>         battery_safety = ActionEvent(
>           "return_to_depot",
>           time_next = entity$last_time + 0.10
>         )
>       )
>     })
>     names(selections) <- ids
>
>     DecisionPlan(
>       selections = selections,
>       metadata = list(strategy = "battery_first")
>     )
>   }
> )
> ```
>
> Suppose both members are eligible and the pending store already contains:
>
> ```text
> dispatch_response: accept_dispatch at t = 6, mode = "warn"
> battery_safety:    return_to_depot at t = 8, mode = "error"
> ```
>
> The new plan would replace the dispatch action and warn, but the battery member rejects its replacement. Complete-plan preflight therefore rejects the plan:
>
> ```text
> plan accepted:    no
> pending slots:    unchanged
> warnings emitted: none
> ```
>
> This is atomic plan staging, not atomic realization. It does not roll back an already valid triggering transition, create priority among member actions, or guarantee that selected actions realize together. Constituent actions continue through ordinary timeline arbitration and realize independently.
>
> ### Audit identity
>
> Emit no synthetic parent trajectory row. Eligible members receive ordinary leaf records, including explicit `NULL` selections. Ineligible members receive `condition_met = FALSE` records only when their leaf declares `audit = TRUE`.
>
> Every emitted row from one group firing should share:
>
> - `grouped_decision_point_id`, identifying the schema declaration; and
> - a deterministic run-local `group_activation_id`, identifying that firing.
>
> An activation ID is more accurate than a plan ID because a group may fire with no eligible members and therefore produce no plan. Optional `DecisionPlan$metadata` is opaque audit information: retain it in raw grouped trajectory records when logging is enabled, but do not add an arbitrary metadata list-column to `trajectory_table()`.
>
> Broader proposal-to-realization lineage, nested groups, multiple actions per leaf, cancellation, cross-group transactions, joint realization, rollback, sequencing, priority, and workflows remain outside this issue.

### Q1 — Prove the observable outcome of each pending-action mode

**Status:** Agreed as test-only hardening. No runtime change is authorized unless a stronger
test exposes a failure, which must return for separate discussion.

The current `.al_pending_model()` fixture schedules every action five time units after its
trigger but ends after four events. Its tests therefore observe warning, silence, or error
behavior without allowing an action to realize. In particular, the tests named for `keep`
and `replace` do not yet prove which proposal remains in the pending slot.

Replace that open-ended fixture with a deterministic two-trigger scenario: the first trigger
at t = 1 proposes an action for t = 6; the second at t = 2 proposes one for t = 7; after the
second trigger, the model supplies no further process event. Assert the complete observable
contract:

| Mode | Diagnostic | Realized action |
|---|---|---|
| default `"warn"` | exactly one replacement warning | exactly once at t = 7 |
| `"replace"` | silent | exactly once at t = 7 |
| `"keep"` | silent | exactly once at t = 6 |
| `"error"` | error on the second proposal | no successful run result |

The focused Core fixture should remain minimal and deterministic. Tutorial 03 must translate
the behavior into the shared urban food-delivery model rather than copying the abstract unit
fixture into scientist-facing documentation.

- [x] Rework the pending-mode fixture so exactly two proposals compete and the retained
      action has an opportunity to realize.
- [x] Assert warning/error behavior, exactly one realized action for successful runs, and
      its expected event time for default `"warn"`, `"replace"`, and `"keep"`.
- [x] Run the focused action-lifecycle tests without modifying runtime code; if an assertion
      fails, stop and reopen the contract discussion before changing the engine.

### Q2 — Name policy selection accurately in trajectory output

**Status:** Agreed. Make a focused, explicitly documented output-schema correction in 2.1;
do not add proposal-to-realization lineage here.

Core constructs a `TrajectoryRecord` during the decision-point firing, before the selected
action is merged with any action already pending for that decision point. Therefore
`selected_action` records the valid `ActionEvent` selected by the policy at that decision;
it does not prove that the action was staged, retained, realized, or applied. Event history
remains the evidence that an action actually realized.

This distinction is observable under `on_pending_action = "keep"`: a later decision record
can contain a newly selected action that is then discarded while the earlier pending action
eventually realizes. The current `TrajectoryRecord()` documentation incorrectly calls
`selected_action` realized, and `trajectory_table()` exposes the same policy selection under
the misleading column name `action_taken`.

**Agreed correction.** Keep the canonical record field `selected_action` and rename the
flattened `trajectory_table()` column from `action_taken` to `selected_action`. Apply the
same schema to empty results. Do not return a duplicate legacy alias or add a permanent
column-naming option. This is a deliberate breaking correction to a released convenience
output: no maintained downstream package uses `action_taken`, known adoption is currently
small, and retaining scientifically misleading terminology would be worse than a clearly
announced migration.

**Implementation boundary.** Do not change when trajectory records are emitted, redefine
`realized_event` (the trigger event), alter `proposed_actions`, or add staging dispositions,
action ids, or later realization links. Those larger lineage questions remain S2.

- [x] Correct `TrajectoryRecord()` source documentation to define `selected_action` as the
      policy selection recorded before pending-action resolution; regenerate its Rd file.
- [x] Rename `trajectory_table()` output to `selected_action` for both populated and empty
      results; update its tests and generated documentation.
- [x] Add a focused `keep` regression in which the later policy selection differs from the
      action that event history shows actually realized.
- [ ] Update Tutorials 01 and 03 to use `selected_action` and teach readers to consult event
      history for realization; retain the urban food-delivery continuity constraint.
- [ ] Add a prominent fluxCore 2.1 NEWS migration note (`action_taken` ->
      `selected_action`) without rewriting the historical v2.0 plan or release notes.

### Tutorial 03 — progressive decisions-and-actions explanation

**Status:** Agreed documentation requirement; detailed editing follows the focused runtime
and test decisions it must explain.

Curate the current provisional Tutorial 03 expansion
(`tutorials/src/03_decisions_policy_provisional.Rmd`) for ordinary scientists who are
comfortable with R but should not need engine-internals vocabulary. The final tutorial must
build concepts progressively rather than opening with lifecycle edge cases:

**Model-continuity constraint.** Every example must use the urban food-delivery model
established across the flux tutorial sequence and implemented in
`tutorials/model/urban_delivery.R`. Tutorial 03 may add decision points, policies, controlled
parameters, or clearly explained tutorial-local adaptations to that model, but it must not
switch to a standalone toy schema or parallel delivery model. Reuse the established courier
state and event vocabulary so readers experience decisions and actions as the next layer of
the same model.

1. one small, controlled urban-delivery decision-to-action cycle and its scientific
   interpretation;
2. the distinction among policy selection, pending-slot staging, event realization, and
   action effect, introduced in plain terms before using those labels heavily;
3. why a pending action can outlive model-proposal refreshes;
4. repeated proposals from one decision point and the observable behavior of each
   `on_pending_action` mode;
5. multiple ordinary decision points, including a shared trigger, while making their
   pending slots and decisions visibly independent; and
6. advanced provenance, rejection, warning, and failure cases, including the boundary
   between ordinary decisions and the future grouped-plan contract in issue #12.

Examples should expose the relevant event times and entity state, not merely report that a
run completed. Each nuanced example should be backed by a focused test or share the same
fixture and expected behavior as one. Illustrative grouped-decision code must remain clearly
labeled as proposed until issue #12 is implemented.

The current provisional draft's isolated `cycle_vars`/`cycle_bundle` opening does not meet
the continuity constraint and must be recast using the shared urban-delivery model. Any
tutorial-local wrapper around `delivery_bundle()` must be introduced as a visible incremental
change, with its scientific reason explained, rather than as a second hidden implementation.

- [ ] Decide during documentation review whether Tutorial 03 retains its current
      `03_decisions_policy` filename or is renamed to reflect decisions and actions; do not
      rename it implicitly during semantic edits.
- [ ] Replace the provisional tutorial only after its examples render from current source
      without hidden errors and its terminology matches the finalized contracts.

---

## Resolved contract discussions (continued)

### Q3 — Failed entity updates leave a phantom committed event

**Status:** Agreed. The repair is approved for narrow implementation inside
`Entity$update()`; no GitHub issue has yet been posted and no source change has started.

**Agreed contract.** If patch shape checking, coercion, or validation rejects an update,
`events`, `last_j`, `last_time`, `current`, and `hist` must all remain identical to their
pre-call values. Successful updates, including `changes = NULL`, retain their current
observable behavior: exactly one event is appended and the event index and clock advance
exactly once.

`Entity$update()` validates the proposed time and event type, then appends the event and
advances `last_j` and `last_time` before `.apply_changes()` validates the state patch. If the
patch is invalid, the method errors after partially mutating the R6 object. `current` and
`hist` remain unchanged because `.apply_changes()` never returns, but the entity records an
event whose transition was rejected.

This is externally observable both through direct `Entity$update()` calls and when an Engine
transition or action handler supplies an invalid patch. Because the caller-owned Entity is a
reference object, catching the error does not restore it. A retry can therefore begin after
the phantom event time, and derived variables that inspect event history can count an event
whose state effect never committed.

**Implementation boundary.** Keep the repair inside `Entity$update()` so direct calls,
Engine transitions, and action handlers inherit the same Entity guarantee. Validate time
and type, compute the complete candidate state/history with `.apply_changes()`, and construct
the candidate event table before assigning any of the five coupled fields. Do not add a
deep-copy transaction framework or a separate validate-then-apply pass. This contract does
not promise general Engine rollback, RNG rollback, reversal of callback or external mutable
side effects, or recovery from interrupts or resource exhaustion during final assignment.

**Performance boundary.** Candidate-then-commit performs the same coercion, validation,
history extension, and event-table append as the current successful path. Exploratory
benchmarks over 1,000--3,000 updates and schemas ranging from 20 to 500 variables measured
the candidate path at approximately 0.98--1.01 times current elapsed runtime. Its meaningful
tradeoff is transient peak memory: the old and candidate event tables can coexist briefly
while candidate state/history is retained. Benchmark sparse, wide-patch, and long-history
cases before merging and stop for review if a consistent material regression appears.
Repeated event-table `rbind()` growth is a separate scaling concern and is not part of Q3.

- [x] Implement candidate-then-commit ordering without deep-copying the Entity or adding a
      second patch-validation pass.
- [x] Prove complete non-mutation for invalid single-field and later-failing multi-field
      patches, plus malformed, unnamed, duplicate-name, unknown-variable, coercion-error,
      and validation-error patches.
- [x] Confirm successful multi-field and `changes = NULL` updates retain their existing
      event, clock, state, and history behavior.
- [x] Add one Engine integration regression showing that a rejected transition patch leaves
      no phantom event on the caller-owned Entity.
- [x] Compare current and candidate successful paths across sparse, wide-patch, and
      long-history workloads; record the benchmark shape and result before merging.

#### Draft fluxCore issue

**Proposed title:** `Entity$update() advances event history and clock before rejecting an invalid state patch`

- [ ] Review and post the issue below. This checkbox is not authorization to post without
      that review.

> ### Summary
>
> `Entity$update()` mutates the event log, event index, and clock before validating and
> applying `changes`. If patch validation fails, the method errors but leaves a phantom
> committed event on the caller-owned Entity while state and state history remain unchanged.
>
> Confirmed against fluxCore 2.1.0 source at `dff6fd6` with R 4.5.3.
>
> ### Minimal reprex
>
> ```r
> library(fluxCore)
>
> schema <- set_schema(vars = list(
>   x = list(type = "nonnegative_integer", default = 1L)
> ))
>
> entity <- Entity$new(schema = schema)
> before <- list(
>   last_j = entity$last_j,
>   last_time = entity$last_time,
>   events = entity$events,
>   current = entity$current,
>   hist = entity$hist
> )
>
> error_message <- tryCatch(
>   {
>     entity$update(
>       time = 5,
>       event_type = "invalid_update",
>       changes = list(x = -1L)
>     )
>     NA_character_
>   },
>   error = conditionMessage
> )
>
> error_message
> #> [1] "Value for 'x' must be a non-negative integer."
>
> c(last_j = entity$last_j, last_time = entity$last_time)
> #>    last_j last_time
> #>         1         5
>
> entity$events
> #>   j time     event_type
> #> 1 0    0           init
> #> 2 1    5 invalid_update
>
> entity$current$x
> #> [1] 1
> entity$hist$x$j
> #> [1] 0
>
> identical(entity$current, before$current)
> #> [1] TRUE
> identical(entity$hist, before$hist)
> #> [1] TRUE
> ```
>
> ### Expected contract
>
> A rejected update should leave `events`, `last_j`, `last_time`, `current`, and `hist`
> unchanged. Event time/type validation and the complete state patch should succeed before
> any of those public fields is committed. Successful updates, including events with
> `changes = NULL`, should retain their current behavior.
>
> ### Current ordering
>
> In `R/Entity.R`, `update()` appends the event and advances `last_j`/`last_time`, then calls
> `.apply_changes()`. Patch-shape checks, unknown-variable checks, coercion, and value
> validation therefore occur after the event mutation.
>
> ### Why this matters
>
> The Entity is an R6 reference object, so the partial mutation remains visible after a
> caller catches an Engine or direct-update error. Retrying from that Entity starts from the
> rejected event time, and event-derived quantities can include an event whose state patch
> never committed.
>
> A narrow repair should make `Entity$update()` atomic with respect to its five coupled
> fields. It need not introduce general Engine transactions, callback recovery, or rollback
> of RNG use, external side effects, mutable objects owned outside the Entity, interrupts,
> or resource failures.
>
> ### Acceptance checks
>
> - An invalid single-field value leaves all five Entity-owned fields identical to their
>   pre-call values.
> - A multi-field patch with an earlier valid value and a later invalid value commits neither
>   field and appends no event.
> - Malformed, unnamed, duplicate-name, unknown-variable, and coercion-error patches do not
>   advance the Entity.
> - Successful multi-field and `changes = NULL` updates still append exactly one event and
>   advance the index and clock exactly once.
> - One Engine integration test confirms that an invalid transition patch does not leave a
>   phantom event on the caller-owned Entity.

### Q4 — Enforce one model clock across schema and bundle

**Status:** Agreed. The schema/bundle agreement and variables-only compatibility contracts
are approved for focused implementation.

The current v2 assembly path can hold two conflicting time specifications. `load_model()`
prefers `schema$time_spec` but assigns that value only to the unused private
`engine$.time_spec`; `Engine$new()` assigns `bundle$time_spec` to public
`engine$time_spec`, which is what `Engine$run()`, `SimContext`, `run_cohort()`, and
downstream forecasting actually consume. A schema declared in hours and a bundle declared
in days therefore loads successfully, retains hours in the unused shadow, and runs in days.

**Agreed model contract.** A model loaded from a full schema and ModelBundle has one
canonical time specification represented in both components:

- `schema$time_spec` is the declarative frame of reference for time-valued state and derived
  model semantics, decision timing, review, and portable model-contract inspection;
- `bundle$time_spec` is the runtime carrier used by event scheduling and callback contexts;
- the two representations must be semantically equal, with no precedence or automatic
  conversion when they disagree; and
- `engine$time_spec` is the sole assembled runtime value propagated to every `SimContext`
  and cohort/downstream consumer.

This retains a meaningful role for schema time. A quantity such as
`hours_since_last_dispatch` can only be interpreted relative to the model clock, even though
current fluxCore derived-variable functions are registered separately on the Entity rather
than stored as first-class schema entries. The model clock does not, by itself, define every
derived variable's output unit; richer variable-level unit metadata is outside Q4.

**Assembly boundary.** `load_model()` must compare schema and bundle values with semantic
time-spec equality, not R object identity. Separately constructed specifications with the
same unit, origin, origin class, and zone are valid. Any mismatch must fail before Engine
construction or callback execution and identify both declarations. Core must not choose one,
convert event times or rates, or warn and continue.

Direct `Engine$new(bundle = ...)` remains a lower-level bundle-only path and continues to
take its clock from `bundle$time_spec`. The unused `engine$.time_spec` must not remain an
independent source of truth; remove it if the compatibility review confirms no external
contract, or keep it temporarily only as an identical internal alias.

**Variables-only compatibility.** In 2.1, `load_model()` continues accepting a genuinely
variables-only schema with no `schema$time_spec`. It uses `bundle$time_spec` and emits a
targeted migration warning that the complete loaded-model contract requires schema time.
This is a compatibility path toward requiring a full schema in the next breaking release,
not a permanent second assembly contract.

A list with a `$variables` field represents the full-schema shape. If that shape omits
`$time_spec`, `load_model()` must error rather than warn and fall back. A full schema whose
time conflicts with the bundle also errors. Variables-only schemas remain warning-free for
`Entity$new()`, and direct `Engine$new(bundle = ...)` remains bundle-only and warning-free.

- [x] Add an assembly regression proving that independently constructed but semantically
      equal schema and bundle time specifications are accepted.
- [x] Reject mismatched unit, origin instant, origin class, or zone before any callback runs.
- [ ] Confirm `engine$time_spec`, single-run and cohort `sim_ctx$time_spec`, and downstream
      consumers all observe the one accepted runtime value.
- [x] Preserve direct `Engine$new(bundle = ...)` behavior.
- [x] Accept a genuinely variables-only `load_model()` schema with the bundle clock and one
      targeted migration warning; test its message and resolved runtime value.
- [x] Reject a full-schema shape that omits `$time_spec` rather than applying the fallback.
- [x] Confirm variables-only `Entity$new()` and direct `Engine$new(bundle = ...)` do not emit
      the `load_model()` migration warning.
- [x] Correct documentation that describes schema precedence, bundle-only precedence, or
      nonexistent `entity$time_spec` callback access; teach one shared model declaration.
- [x] Keep variable-level units, general bundle composition, and cross-unit conversion out
      of Q4.

#### Draft fluxCore issue

**Proposed title:** `load_model() silently accepts conflicting schema and bundle time specifications`

- [ ] Review and post the issue below. This checkbox is not authorization to post without
      that review.

> ### Summary
>
> `load_model()` accepts a full schema and ModelBundle whose `time_spec` values conflict.
> The schema value is retained only in the unused private `engine$.time_spec`, while public
> `engine$time_spec` and callback `sim_ctx$time_spec` continue to use the bundle value. The
> resulting Engine therefore contains two declared model clocks and silently runs with one
> of them.
>
> Confirmed against fluxCore 2.1.0 source at `dff6fd6` with R 4.5.3.
>
> ### Minimal reprex
>
> ```r
> library(fluxCore)
>
> schema <- set_schema(
>   vars = list(x = list(type = "count", default = 0L)),
>   time_spec = time_spec(unit = "hours")
> )
>
> callback_time_spec <- NULL
> bundle <- list(
>   time_spec = time_spec(unit = "days"),
>   propose_events = function(entity, sim_ctx = NULL) {
>     callback_time_spec <<- sim_ctx$time_spec
>     list()
>   },
>   transition = function(entity, event) list(),
>   stop = function(entity, event) FALSE
> )
>
> engine <- load_model(schema = schema, bundle = bundle)
> out <- engine$run(
>   Entity$new(schema = schema$variables),
>   max_events = 1
> )
>
> c(
>   schema = schema$time_spec$unit,
>   bundle = bundle$time_spec$unit,
>   engine = engine$time_spec$unit,
>   private_engine = engine$.time_spec$unit,
>   callback = callback_time_spec$unit
> )
> #>         schema         bundle         engine private_engine       callback
> #>        "hours"         "days"         "days"       "hours"         "days"
> ```
>
> The run ends with `stopped_by = "no_proposals"`; the important point is that the
> conflicting model assembled and invoked a callback instead of failing before runtime.
>
> ### Expected contract
>
> A model loaded from a full schema and ModelBundle has one canonical time specification.
> The schema declaration supplies the declarative frame for state, derived-variable, and
> decision semantics; the bundle declaration carries that clock into scheduling and runtime
> contexts. Neither declaration overrides the other. They must be semantically equal, or
> `load_model()` must fail before constructing an Engine or invoking a callback.
>
> Equality should cover unit, origin instant, origin class, and zone without requiring R
> object identity. Separately constructed but equivalent `time_spec()` objects should be
> accepted.
>
> ### 2.1 compatibility boundary
>
> - A genuinely variables-only schema with no `schema$time_spec` remains accepted by
>   `load_model()` in 2.1, uses `bundle$time_spec`, and emits a targeted migration warning.
> - A full-schema shape containing `$variables` but omitting `$time_spec` is malformed and
>   errors rather than falling back.
> - `Entity$new(schema = variables)` remains valid and warning-free.
> - Direct `Engine$new(bundle = ...)` remains bundle-only and warning-free.
> - The unused private `engine$.time_spec` must not remain an independent clock.
>
> ### Why this matters
>
> Numeric event times, action delays, horizons, rates, rolling windows, and calendar-time
> conversions all depend on the model clock. Silently selecting one of two conflicting
> declarations can change scientific meaning without producing an execution error.
>
> ### Acceptance checks
>
> - Equivalent schema and bundle specifications are accepted and produce one runtime clock.
> - Unit, origin-instant, origin-class, and zone mismatches fail before callbacks run.
> - `engine$time_spec`, single-run and cohort `sim_ctx$time_spec`, and downstream consumers
>   observe the accepted clock.
> - The warned variables-only compatibility path and the malformed full-schema error are
>   tested separately.
> - Direct `Engine$new(bundle = ...)` behavior is unchanged.
>
> This issue does not add cross-unit conversion, variable-level unit metadata, or general
> bundle-composition rules.

### Q5 — Make `ParamContext` the cohort draw boundary and preserve stable draw ids

**Status:** Agreed. Repair the nested-context defect and make draw identity independent of
list position or parallel completion order. The active implementation remains localized to
cohort draw normalization, Engine context injection, and one fluxForecast adapter.

The documented parameter-draw contract is currently internally inconsistent.
`bundle$sample_params(D)` is documented and taught as returning `list<ParamContext>`, but
`run_cohort()` places each complete context in `.internal_ctx$params`. `Engine$run()` then
constructs a second `ParamContext` around that value. A callback therefore receives the
parameter realization at `param_ctx$params$params`, while the outer context loses the
original provenance and substitutes the cohort's positional draw number. Tutorial 01's
parameter-uncertainty example consequently passes `NULL` to `rlnorm(meanlog = ...)` and
errors.

**Agreed shape contract.** A cohort parameter draw is one complete `ParamContext`, not a
bare parameter list:

- an explicit `run_cohort(param_draws = ...)` value must be a list of exactly
  `n_param_draws` `ParamContext` objects;
- `bundle$sample_params(D)` must return the same typed shape;
- when neither source supplies draws, Core constructs `D` contexts from `bundle$params` or
  an empty parameter list, with ids `1:D`;
- Core passes the selected context into `Engine$run()` as a context, rather than through the
  raw-parameter slot, so every supported callback sees one non-nested context whose
  `draw_id`, `params`, and `provenance` are unchanged; and
- `batch$param_draws` returns the normalized typed contexts actually used by the runs.

Bare parameter lists will no longer be accepted by `run_cohort(param_draws = ...)`. This is
a deliberate contract correction rather than a warning/deprecation cycle: the documented
typed path is currently broken, known adoption is small, and silent shape guessing would
preserve two meanings for the same argument. `Engine$run_draw(params = ...)` remains a raw
parameter-payload API; it is not a collection-of-draws boundary. Direct `Engine$run()` also
continues constructing one context from `bundle$params` or an empty list, so callbacks do
not receive `param_ctx = NULL` merely because the run is not part of a cohort.

fluxForecast's public `forecast(param_sets = ...)` API may continue accepting bare parameter
payload lists. Its one call to `run_cohort()` will wrap those payloads as sequentially
identified `ParamContext` objects at the package boundary. The streaming forecast paths use
`Engine$run_draw(params = ...)` and therefore require no compatibility shim. Because the
adapter would be double-wrapped by fluxCore 2.0, the adapted fluxForecast release must raise
its fluxCore dependency floor to the corrected 2.1 version and be tested against that source
stack; the adapter must not be released independently against the older Core contract.

**Stable identity contract.** `ParamContext$draw_id` is authoritative identity, not the
element's position in a returned list:

- ids must be positive, unique integer values within a cohort, but need not be contiguous
  or arrive in ascending order;
- Core validates all contexts once, orders them canonically by `draw_id`, and builds a
  draw-id-to-storage-position mapping before constructing or dispatching runs;
- `n_param_draws` remains the number of contexts, not the largest id;
- the public cohort index contains the actual draw ids, and returned runs remain aligned
  with an entity -> ascending draw id -> simulation ordering;
- workers carry the context and its coordinates; results are associated through
  `(entity_id, param_draw_id, sim_id)`, never through worker completion order; and
- deterministic simulation seeds use the actual stable id. Replaying draw 42 alone must
  retain draw id 42 and the same per-run stream it had inside a larger cohort.

This permits a sampler to assign ids before distributing parameter-generation work and
return contexts in any completion order. Sampling itself still occurs before Core's
simulation dispatch. Making a sampler's own random-number generation independent of worker
schedule is the sampler's responsibility and is not added to Q5.

**Containment and cost boundary.** Validate, sort, and index the `D` contexts once at the
cohort boundary. Draw lookup during the `N * D * S` run grid must use the precomputed
position rather than scan the context list, and no validation or wrapping may be added to
the event loop. The work is therefore `O(D log D)` setup plus constant-time lookup per run,
not a per-event cost. Q5 may make the existing coordinate-seed calculation safe across the
accepted id range, but it must not change the seed algorithm's public coordinates or absorb
the RuntimeContext defect in Q7.

The deprecated Provider `sample_param_draws()` helpers should be audited for the same typed
return contract if they remain in 2.1, without reconnecting them to `run_cohort()` or
changing `load_model()`'s unused `param_source` field. Structured provenance, parameter
value-schema validation, callback-surface expansion (including `observe()`), and parameter
sampling RNG ownership remain separate questions.

- [ ] Harden `ParamContext()` to accept a positive, losslessly integer-valued scalar id and
      preserve the current `5.0` -> `5L` convenience without accepting truncation.
- [ ] Normalize all cohort draws once; reject a bare payload list, a single `ParamContext`
      passed as the outer collection, wrong length, non-context elements, invalid ids, and
      duplicate ids before callbacks or workers start.
- [ ] Sort contexts by stable id, build an explicit id/position mapping, use actual ids in
      the cohort index and seed coordinates, and return the canonical typed collection.
- [ ] Pass the selected context through the internal cohort/Engine boundary without
      rebuilding it or losing provenance; confirm proposal, transition, stop, policy, and
      action-handler callbacks see the same direct fields throughout a run.
- [ ] Construct typed `1:D` fallback contexts from `bundle$params` or `list()` when no
      sampling hook is supplied; require `bundle$sample_params(D)` to return typed contexts.
- [ ] Preserve `Engine$run_draw(params = ...)` and direct `Engine$run()` payload behavior,
      while documenting that direct callbacks receive a default `ParamContext`, not `NULL`.
- [ ] Adapt fluxForecast's single batch call by wrapping its public bare `param_sets` values
      as contexts; leave its streaming `run_draw()` paths unchanged, raise the fluxCore
      dependency floor to the corrected 2.1 release, and test the coordinated source stack.
- [ ] Prove out-of-order and non-contiguous ids, canonical return/index order, full-cohort
      versus subset replay, and identical serial/parallel results and run-index alignment.
- [ ] Add regression coverage for direct parameter access and provenance preservation, and
      render Tutorial 01's urban-delivery parameter example without hidden errors.
- [ ] Keep Q6 run identity, Q7 RuntimeContext seeding, provider reactivation, structured
      provenance, and new callback injection outside this implementation.

#### Draft fluxCore issue

**Proposed title:** `run_cohort() nests documented ParamContext draws and replaces their identity`

- [ ] Review and post the issue below. This checkbox is not authorization to post without
      that review.

> ### Summary
>
> `bundle$sample_params(D)` and `run_cohort(param_draws = ...)` are documented as producing
> or accepting a list of `ParamContext` objects. `run_cohort()` currently passes each whole
> object through the internal raw-parameter field, and `Engine$run()` wraps it in another
> `ParamContext`. Callbacks must therefore look under `param_ctx$params$params`, provenance
> is lost from the outer context, and the context's own draw id is replaced by list position.
>
> Confirmed against fluxCore 2.1.0 source at `dff6fd6` with R 4.5.3.
>
> ### Minimal reprex
>
> ```r
> library(fluxCore)
>
> schema <- set_schema(vars = list(
>   x = list(type = "nonnegative_integer", default = 0L)
> ))
>
> seen <- NULL
> bundle <- list(
>   time_spec = time_spec(unit = "days"),
>   sample_params = function(D) {
>     list(ParamContext(
>       draw_id = 42L,
>       params = list(rate = 0.25),
>       provenance = "posterior_row_42"
>     ))
>   },
>   propose_events = function(entity, param_ctx = NULL) {
>     seen <<- param_ctx
>     list(tick = list(time_next = 1, event_type = "tick"))
>   },
>   transition = function(entity, event, param_ctx = NULL) {
>     list(x = entity$current$x + 1L)
>   },
>   stop = function(entity, event, param_ctx = NULL) TRUE
> )
>
> batch <- run_cohort(
>   Engine$new(bundle = bundle),
>   entities = list(courier_1 = Entity$new(schema = schema)),
>   n_param_draws = 1,
>   n_sims = 1,
>   backend = "none"
> )
>
> c(
>   outer_draw_id = seen$draw_id,
>   inner_draw_id = seen$params$draw_id,
>   index_draw_id = batch$index$param_draw_id
> )
> #> outer_draw_id inner_draw_id index_draw_id
> #>             1            42             1
>
> seen$provenance
> #> NULL
> seen$params$provenance
> #> [1] "posterior_row_42"
>
> seen$params$rate
> #> NULL
> seen$params$params$rate
> #> [1] 0.25
> ```
>
> ### Expected contract
>
> A callback should receive the supplied `ParamContext` directly: `draw_id == 42L`,
> `params$rate == 0.25`, and `provenance == "posterior_row_42"`. The cohort index should use
> draw id 42 as well. A context's id is stable identity, not its list position, so unique
> positive ids may be non-contiguous and contexts may arrive out of order from a parallel
> sampler. Core should validate and canonicalize them before simulation dispatch.
>
> Explicit `run_cohort(param_draws = ...)` values and `bundle$sample_params(D)` should use
> one unambiguous `list<ParamContext>` shape. `Engine$run_draw(params = ...)` remains the
> separate public entry point for a raw parameter payload. fluxForecast can retain its bare
> `param_sets` API by wrapping those values at its one batch boundary.
>
> ### Acceptance checks
>
> - Callbacks receive one non-nested context with its id, direct parameter fields, and
>   provenance preserved.
> - Bare parameter lists and malformed or duplicate context ids fail before any run starts.
> - Out-of-order contexts with ids such as 42, 7, and 19 produce canonical index and return
>   order 7, 19, 42 without changing those ids.
> - Serial and parallel backends produce aligned results independent of completion order.
> - Replaying draw 42 alone uses the same draw identity and deterministic simulation stream.
> - Tutorial 01's urban-delivery parameter-uncertainty example runs successfully.
>
> This issue does not change parameter-sampling RNG ownership, add structured provenance,
> expand context injection to new callback types, or resolve the separate cohort run-id and
> RuntimeContext seed defects.

### Q6 — Propagate the cohort-owned run identity

**Status:** Agreed. Repair the missing cohort metadata propagation and retain the canonical
join fields in flattened trajectory output.

`run_cohort()` constructs a correctly aligned index with a unique `run_id` for every
`(entity_id, param_draw_id, sim_id)` row and later uses those ids as the names of
`batch$runs`. The per-entity worker passes the entity, draw, simulation, time, and parameter
metadata into `Engine$run()`, but omits the already assigned `run_id`. `Engine$run()` then
uses its direct-run fallback, `"run_1"`, to construct `SimContext` and every
`TrajectoryRecord`. A four-run cohort therefore has index and run-list ids `run_1` through
`run_4`, while all callbacks and decision records report `run_1`.

This violates two established v2 contracts: `SimContext$run_id` is documented as unique per
simulation run, and `run_id` is the canonical key for joining a run's standardized outputs.
It also means a policy or bundle callback that reads `sim_ctx$run_id` cannot distinguish
cohort runs even though Core has already assigned their identities.

**Agreed identity contract.** For a run created by `run_cohort()`, the id assigned in the
cohort index is authoritative within that batch. The following values must be identical:

- `batch$index$run_id[[i]]`;
- `names(batch$runs)[[i]]`;
- the `SimContext$run_id` supplied to every supported callback in that run; and
- `run_id` on every `TrajectoryRecord` emitted by that run.

The worker must carry the preassigned id into `Engine$run()`; neither the Engine nor the
result collector should reconstruct it from completion order. This preserves the existing
run/index alignment invariant across serial and parallel backends.

`run_id` remains a unique **batch-local join key**, not a durable scientific identity across
cohort reshaping. Adding or removing entities, draws, or simulations may renumber sequential
`run_*` labels. Reproducible simulation identity across such calls comes from the stable
`(entity_id, param_draw_id, sim_id)` coordinates agreed in Q5. Direct `Engine$run()` and
`Engine$run_draw()` remain single-run entry points and retain the existing `"run_1"`
fallback; Q6 does not add a public `run_id` argument to either method.

**Flattened trajectory contract.** `TrajectoryRecord` already stores `run_id` and
`entity_id`, but `trajectory_table()` currently discards both. Retain them as the first two
columns of populated and empty flattened output so the canonical join key survives the
convenience transformation. Together with Q2, the fixed base columns are:

```text
run_id, entity_id, t, decision_point_id, trigger_event,
selected_action, condition_met, <requested state columns>
```

This is one coordinated 2.1 output-schema correction: Q2 removes the misleading
`action_taken` name, and Q6 stops dropping record identity. No legacy alias or option is
added. `trajectory_table()` continues flattening the identifiers already stored on each
record; it does not choose between a list name and `Entity$id` or establish a new entity-id
authority contract.

**Implementation boundary.** The active runtime correction is one metadata field at the
cohort/Engine boundary. It does not alter run ordering, event scheduling, seeding,
trajectory emission timing, or parallel collection. There is no new per-event computation
beyond reading the already constructed `SimContext$run_id` as before.

- [x] Add the preassigned index `run_id` to each worker's internal run metadata before
      calling `Engine$run()`.
- [x] Assert exact equality among the index id, run-list name, callback `sim_ctx$run_id`,
      and every trajectory-record id for each cohort run.
- [x] Strengthen the existing serial/cluster, serial/mclapply, and serial/future alignment
      tests so trajectory signatures include `run_id` rather than accidentally ignoring it.
- [x] Add `run_id` and `entity_id` as the leading columns of populated and empty
      `trajectory_table()` output, alongside Q2's `selected_action` correction.
- [x] Document that cohort `run_id` is the batch-local join key while entity/draw/simulation
      coordinates carry cross-call replay identity.
- [x] Preserve direct `Engine$run()` and `Engine$run_draw()` fallback behavior and keep a
      caller-supplied direct-run id, entity-id authority, and Q7 seeding outside Q6.

#### Draft fluxCore issue

**Proposed title:** `run_cohort() assigns unique index ids but every SimContext and TrajectoryRecord uses run_1`

- [ ] Review and post the issue below. This checkbox is not authorization to post without
      that review.

> ### Summary
>
> `run_cohort()` assigns a unique `run_id` to every row of its index and uses those values
> as the names of `batch$runs`, but it does not pass the assigned id into `Engine$run()`.
> Every cohort run consequently falls back to `"run_1"` in its `SimContext` and
> `TrajectoryRecord` objects.
>
> Confirmed against fluxCore 2.1.0 source at `dff6fd6` with R 4.5.3.
>
> ### Minimal reprex
>
> ```r
> library(fluxCore)
>
> dispatch_dp <- DecisionPoint(
>   id = "dispatch_choice",
>   trigger = "DISPATCH",
>   allowed_actions = "ACCEPT"
> )
> schema <- set_schema(
>   vars = list(x = list(type = "nonnegative_integer", default = 0L)),
>   time_spec = time_spec(unit = "hours"),
>   decision_points = list(dispatch_dp)
> )
>
> callback_run_ids <- character()
> bundle <- list(
>   time_spec = time_spec(unit = "hours"),
>   event_catalog = c("DISPATCH", "ACCEPT"),
>   propose_events = function(entity) {
>     list(dispatch = list(
>       time_next = entity$last_time + 1,
>       event_type = "DISPATCH"
>     ))
>   },
>   transition = function(entity, event) list(),
>   stop = function(entity, event) identical(event$event_type, "ACCEPT")
> )
> policy <- list(
>   propose_action = function(decision_point, entity, sim_ctx, param_ctx) {
>     callback_run_ids <<- c(callback_run_ids, sim_ctx$run_id)
>     ActionEvent(
>       action_type = "ACCEPT",
>       time_next = entity$last_time + 0.1,
>       decision_point_id = decision_point$id
>     )
>   }
> )
>
> engine <- load_model(
>   schema = schema,
>   bundle = bundle,
>   policy = policy,
>   trajectory = list(detail = "none")
> )
> batch <- run_cohort(
>   engine,
>   entities = list(
>     courier_a = Entity$new(schema = schema$variables),
>     courier_b = Entity$new(schema = schema$variables)
>   ),
>   n_sims = 2,
>   backend = "none",
>   seed = 1
> )
>
> data.frame(
>   index_run_id = batch$index$run_id,
>   callback_run_id = callback_run_ids,
>   record_run_id = vapply(
>     batch$runs,
>     function(x) x$trajectory_records[[1]]$run_id,
>     character(1)
>   )
> )
> #>       index_run_id callback_run_id record_run_id
> #> run_1        run_1           run_1         run_1
> #> run_2        run_2           run_1         run_1
> #> run_3        run_3           run_1         run_1
> #> run_4        run_4           run_1         run_1
> ```
>
> ### Expected contract
>
> Each row should contain the same id three times: `run_1`, `run_2`, `run_3`, and
> `run_4`, respectively. The worker should pass the id already present on its index row into
> the Engine. Completion order must not assign or repair run identity.
>
> `trajectory_table()` should also retain each record's `run_id` and `entity_id` as its
> leading columns. Otherwise flattening the canonical audit record discards the join key
> needed to connect it to `batch$index`.
>
> ### Acceptance checks
>
> - Cohort index ids, run-list names, callback `SimContext` ids, and trajectory-record ids
>   match exactly for every run.
> - Serial and supported parallel backends retain the same identity and alignment.
> - Direct `Engine$run()` and `Engine$run_draw()` retain their existing `"run_1"` fallback.
> - Populated and empty `trajectory_table()` results include `run_id` and `entity_id`, plus
>   the Q2-corrected `selected_action` column.
>
> Cohort `run_id` is a batch-local join key. This issue does not make it a durable replay id,
> change the cohort ordering or seed contracts, add a public direct-run id argument, or
> resolve entity-list-name versus `Entity$id` authority.

### Q7 — Give each execution path one RNG owner

**Status:** Agreed. Prevent a configured Engine from reseeding work that a cohort or
lower-level run harness has already seeded. Keep the common API unchanged and keep RNG
ownership metadata private to Core.

The defect is two competing seed owners. `run_cohort()` correctly derives and sets a local
seed for every `(entity_id, param_draw_id, sim_id)` row. `Engine$run()` then sees the
`RuntimeContext` stored by `load_model()` and sets the seed again, using the stored
`replicate_id` or its default of 1. The second seed wins. For a fixed entity and parameter
draw, every nominal simulation replicate can therefore execute the same random stream.
An explicit cohort `seed` or `runtime` also fails to take precedence over the stored Engine
seed in practice.

The same ownership collision reaches `Engine$run_draw()`. fluxForecast's streaming paths
set a distinct seed for each stream before calling `run_draw()`, but a loaded Engine can
overwrite it. This can collapse streaming replicates just as it collapses cohort replicates.

**Agreed ownership contract.** The outermost execution entry point seeds a run at most once:

- direct `Engine$run()` may use the Engine's stored `RuntimeContext$seed`, with its direct-run
  `replicate_id` or the existing default of 1;
- `run_cohort()` owns all cohort RNG setup and uses the actual entity, stable Q5 draw id, and
  cohort `sim_id` coordinates;
- `Engine$run_draw()` is a lower-level harness entry point whose caller owns RNG setup; it
  marks its internal Engine call so a stored runtime cannot overwrite caller state; and
- `Engine$run()` honors a private harness-owned marker and does not seed again. This marker
  is never exposed as a user argument or callback field.

For `run_cohort()`, configuration precedence is:

1. an explicit `runtime = RuntimeContext(...)`, which continues to take precedence over
   the scalar controls as currently documented;
2. otherwise, non-`NULL` scalar `seed`, `backend`, and `n_workers` values supplied to
   `run_cohort()`; then
3. corresponding defaults from the Engine's stored RuntimeContext, when available.

An explicit cohort runtime with `seed = NULL` is the clear way to request unseeded execution
when a configured Engine stores a seed. This resolution occurs once at the cohort boundary;
the Engine's runtime object does not become a second seed owner.

`RuntimeContext$replicate_id` is a direct-run coordinate. In a cohort, `n_sims` creates the
replicate coordinates recorded as `sim_id`. A non-`NULL` `replicate_id` on a RuntimeContext
explicitly supplied to `run_cohort()` must error rather than be silently ignored or compete
with `sim_id`. A `replicate_id` stored for direct Engine use is not inherited into a cohort.
Q7 does not add arbitrary cohort simulation ids or define an offset interpretation.

**User-facing cost.** No new argument is required for `Engine$run()` or `run_cohort()`, and
there is no public RNG-owner flag. Ordinary unseeded calls remain valid; `seed = 123` remains
the simple reproducible cohort interface; a RuntimeContext remains an optional way to keep
seed/backend/worker settings together. fluxForecast users continue supplying only its
existing `seed` argument. The existing public `run_draw()` signature remains unchanged;
advanced direct callers may manage its RNG with ordinary R seed state, as its current tests
already do.

**Containment boundary.** Seed resolution and the ownership check occur once per run, not
per event. Q7 does not change the coordinate-to-seed algorithm, parameter-sampling RNG,
stable draw identity, or the known collision limitations of `.seed_for()`. Those are
separate decisions. Numerically different results are expected only where current execution
uses the wrong seed or collapses supposedly independent replicates.

- [ ] Resolve effective cohort seed/backend/worker settings once using the approved
      precedence, including stored Engine defaults when no higher-precedence value exists.
- [ ] Give cohort and `run_draw()` Engine calls an explicit private RNG-ownership marker and
      suppress only the Engine's second seed operation.
- [ ] Keep direct `Engine$run()` stored-RuntimeContext behavior unchanged.
- [ ] Reject a non-`NULL` `replicate_id` on a RuntimeContext explicitly supplied to
      `run_cohort()`; document `sim_id` as the cohort replicate coordinate.
- [ ] Prove that an explicit cohort seed/runtime overrides a different stored Engine seed,
      produces distinct simulation streams, and reproduces them on a repeat call.
- [ ] Prove parity across serial and supported parallel backends, using complete stochastic
      outputs rather than only event counts.
- [ ] Test inheritance from a stored Engine runtime and the explicit unseeded override.
- [ ] Add direct-run and `run_draw()` regressions showing respectively that stored-runtime
      seeding is preserved and caller-owned RNG state is not overwritten.
- [ ] Add fluxForecast batch plus both streaming-summary regressions using an Engine with a
      different stored seed; its public `seed` must control execution and replicates must not
      collapse.
- [ ] Correct RuntimeContext, `run_cohort()`, `run_draw()`, and tutorial documentation; add a
      NEWS note for seeded loaded-Engine results that change under the corrected ownership.
- [ ] Keep parameter-draw sampling, a new public seed-allocation API, arbitrary cohort
      `sim_id` values, and `.seed_for()` hash redesign outside Q7.

#### Draft fluxCore issue

**Proposed title:** `A loaded Engine can overwrite cohort seeds and collapse simulation replicates`

- [ ] Review and post the issue below. This checkbox is not authorization to post without
      that review.

> ### Summary
>
> `run_cohort()` sets a coordinate-specific seed for each entity, parameter draw, and
> simulation replicate. If the Engine was assembled with a seeded RuntimeContext,
> `Engine$run()` immediately reseeds from the stored runtime using `replicate_id` (default
> 1). The Engine seed overrides the cohort seed, so distinct `sim_id` rows can execute the
> same random stream. The same second-seed behavior can override caller-managed RNG around
> `Engine$run_draw()`.
>
> Confirmed against fluxCore 2.1.0 source at `dff6fd6` with R 4.5.3.
>
> ### Minimal reprex
>
> ```r
> library(fluxCore)
>
> schema <- set_schema(
>   vars = list(x = list(type = "nonnegative_integer", default = 0L)),
>   time_spec = time_spec(unit = "hours")
> )
> bundle <- list(
>   time_spec = time_spec(unit = "hours"),
>   propose_events = function(entity) {
>     list(delivery = list(
>       time_next = entity$last_time + runif(1),
>       event_type = "DELIVERY"
>     ))
>   },
>   transition = function(entity, event) {
>     list(x = entity$current$x + 1L)
>   },
>   stop = function(entity, event) TRUE
> )
>
> # Stored seed 500 should not override the explicit cohort seed 900.
> engine <- load_model(
>   schema = schema,
>   bundle = bundle,
>   runtime = RuntimeContext(seed = 500L)
> )
> batch <- run_cohort(
>   engine,
>   entities = list(
>     courier_1 = Entity$new(schema = schema$variables)
>   ),
>   n_sims = 4,
>   seed = 900L,
>   backend = "none"
> )
>
> data.frame(
>   sim_id = batch$index$sim_id,
>   delivery_time = vapply(
>     batch$runs,
>     function(x) x$events$time[[2]],
>     numeric(1)
>   )
> )
> #>       sim_id delivery_time
> #> run_1      1     0.4220496
> #> run_2      2     0.4220496
> #> run_3      3     0.4220496
> #> run_4      4     0.4220496
> ```
>
> ### Expected contract
>
> The four times should not collapse to one value. Repeating the cohort with seed 900 should
> reproduce each corresponding value, and serial and parallel backends should agree. The
> explicit cohort seed owns the run; the Engine must not reset it from stored seed 500.
>
> Seed ownership should be assigned once by the outer execution path. Direct `Engine$run()`
> may use its stored RuntimeContext. `run_cohort()` resolves and applies cohort settings.
> `run_draw()` must preserve RNG state established by its caller. The Engine receives a
> private ownership marker solely to avoid the second `set.seed()` call.
>
> ### Acceptance checks
>
> - Different cohort `sim_id` values receive distinct streams under a fixed seed and are
>   reproducible across repeat calls and supported backends.
> - Explicit cohort runtime/scalar settings take precedence over stored Engine defaults.
> - A stored Engine runtime can provide cohort defaults without reseeding inside the Engine.
> - Direct `Engine$run()` retains stored RuntimeContext seeding.
> - `run_draw()` does not overwrite caller-established RNG state.
> - fluxForecast batch and streaming functions honor their public seed when given a loaded
>   Engine with a different stored seed.
>
> This issue does not change parameter-sampling RNG, add a public RNG-owner flag, support
> arbitrary cohort simulation ids, or redesign the coordinate seed hash.

### Q8 — Fail fast when decision callbacks throw

**Status:** Agreed; filed as [fluxCore issue #13](https://github.com/jarrod-dalton/fluxCore/issues/13).
A thrown condition, policy, or action-handler error must terminate the run with callback
context. Intentional `FALSE` and `NULL` returns remain valid model outcomes. Track the
correction as a fluxCore bug because the current behavior can make a failed callback
indistinguishable from a successful decision.

Current Core behavior catches all three errors and assigns each one a legitimate model
meaning:

| Callback | Current fallback | Valid outcome it imitates |
|---|---|---|
| `DecisionPoint$condition` | warn, then use `FALSE` | the condition vetoed policy dispatch |
| `policy$propose_action()` | warn, then use `NULL` | the policy intentionally selected no action |
| `action_handler` | warn, then use `NULL` | the action realized successfully with no state change |

The last case is especially damaging to auditability: Core records the action event and
advances the Entity clock even though its handler failed. fluxForecast also wraps cohort
execution in `suppressWarnings()`, so these warnings may not reach its users.

**Agreed callback contract.** Core distinguishes an intentional callback result from a
thrown error:

- a condition must return exactly one non-missing logical value; `FALSE` remains an
  intentional veto, while an error or malformed result stops the run;
- a policy may intentionally return `NULL`, but a thrown error stops the run;
- an action handler may intentionally return `NULL` for a realized action with no state
  patch, but a thrown error stops before that action event or its state effect is committed;
- the propagated error identifies the callback kind and the relevant decision-point or
  action id, while retaining the underlying callback message; and
- Core does not add a global soft-failure mode. A domain model that genuinely wants a
  fallback catches its own error inside the callback and explicitly returns `FALSE` or
  `NULL`.

The condition and policy run after the triggering event's transition and
`Entity$update()`. Q8 therefore does not promise to roll that already committed trigger
event back when either callback fails. Q3 supplies atomicity for an individual Entity
update, not a transaction around an entire Engine step.

Malformed policy configuration, a non-`ActionEvent` policy result, a disallowed action,
`observation_fn` coercion, and trigger-predicate return shape are adjacent contracts, not
implicit parts of this bug fix. They require separate review rather than inheriting Q8's
answer without discussion.

- [x] Replace the condition catch-and-veto path with contextual error propagation and
      enforce a length-one, non-`NA` logical result.
- [x] Replace the policy catch-and-`NULL` path with contextual error propagation while
      preserving an explicitly returned `NULL`.
- [x] Replace the action-handler catch-and-`NULL` path with contextual error propagation
      while preserving an explicitly returned `NULL`.
- [x] Add one regression for each thrown callback error, including the Entity/event state
      visible after the error and the original error message.
- [x] Retain positive tests for intentional condition `FALSE`, policy `NULL`, and handler
      `NULL`, so fail-fast does not erase supported no-decision/no-effect behavior.
- [x] Add condition-shape tests for length zero, length greater than one, `NA`, and
      non-logical values.
- [ ] Confirm fluxForecast's warning suppression does not hide the newly propagated errors.
- [ ] Capture the callback-guidance changes and known affected fluxDesign surfaces in E1's
      final contract-sync prompt; generated model code should catch errors only when it
      intentionally defines a domain fallback. Do not edit the sibling repo as part of the
      focused Q8 Core implementation.
- [ ] Document the partial-progress boundary: trigger state can already be committed when a
      condition or policy fails, but a failing action handler does not realize its action.
- [x] Keep neighboring invalid-policy, disallowed-action, observation, and trigger-shape
      contracts outside Q8 pending their own review.

#### Filed fluxCore issue

**Title:** `Decision callback errors are downgraded to valid-looking model outcomes`

- [x] Filed as [fluxCore issue #13](https://github.com/jarrod-dalton/fluxCore/issues/13)
      on 2026-08-27 after review and action-time confirmation.

> ### Summary
>
> fluxCore currently catches errors thrown by all three decision callbacks and continues
> the run after assigning each error a valid model meaning:
>
> - a `DecisionPoint$condition` error becomes `FALSE`, so it looks like a policy veto;
> - a `policy$propose_action()` error becomes `NULL`, so it looks like an intentional
>   no-action choice; and
> - an `action_handler` error becomes `NULL`, after which the action event is committed and
>   looks like a successful no-effect action.
>
> These are correctness and auditability failures, not merely warning-quality problems.
> Downstream callers may also suppress Core warnings; fluxForecast currently does so around
> cohort execution.
>
> ### Reprex
>
> This uses the tutorial's urban food-delivery setting. A dispatch decision can accept an
> offer and increment the courier's accepted-delivery count.
>
> ```r
> library(fluxCore)
>
> make_case <- function(fail_at) {
>   dp <- DecisionPoint(
>     id = "dispatch_choice",
>     trigger = "DISPATCH",
>     allowed_actions = "ACCEPT",
>     action_handlers = list(ACCEPT = function(entity, event) {
>       if (identical(fail_at, "handler")) stop("handler exploded")
>       list(accepted = 1L)
>     }),
>     condition = function(entity) {
>       if (identical(fail_at, "condition")) stop("condition exploded")
>       TRUE
>     },
>     audit = TRUE,
>     on_pending_action = "error"
>   )
>
>   schema <- set_schema(
>     vars = list(
>       accepted = list(type = "nonnegative_integer", default = 0L)
>     ),
>     time_spec = time_spec(unit = "hours"),
>     decision_points = list(dp)
>   )
>
>   bundle <- list(
>     time_spec = time_spec(unit = "hours"),
>     event_catalog = c("DISPATCH", "ACCEPT"),
>     propose_events = function(entity) {
>       if (entity$last_time >= 1) return(list())
>       list(dispatch = list(time_next = 1, event_type = "DISPATCH"))
>     },
>     transition = function(entity, event) list(),
>     stop = function(entity, event) identical(event$event_type, "ACCEPT"),
>     refresh_rules = function(entity, last_event, changes) "ALL"
>   )
>
>   policy <- list(propose_action = function(decision_point, entity, sim_ctx, param_ctx) {
>     if (identical(fail_at, "policy")) stop("policy exploded")
>     ActionEvent("ACCEPT", time_next = entity$last_time + 0.25)
>   })
>
>   load_model(
>     schema,
>     bundle,
>     policy,
>     trajectory = list(detail = "none")
>   )$run(
>     Entity$new(schema = schema$variables),
>     max_events = 3
>   )
> }
>
> condition_case <- make_case("condition")
> # Warning: DecisionPoint('dispatch_choice') condition errored: condition exploded
> condition_case$trajectory_records[[1]]$condition_met
> #> [1] FALSE
>
> policy_case <- make_case("policy")
> # Warning: policy$propose_action() errored for dp 'dispatch_choice': policy exploded
> is.null(policy_case$trajectory_records[[1]]$selected_action)
> #> [1] TRUE
>
> handler_case <- make_case("handler")
> # Warning: action_handler errored for event_type 'ACCEPT': handler exploded
> handler_case$events$event_type
> #> [1] "init" "DISPATCH" "ACCEPT"
> handler_case$entity$current$accepted
> #> [1] 0
> ```
>
> Confirmed against fluxCore 2.1.0 source at `dff6fd6` with R 4.5.3. None of
> the three calls errors.
>
> ### Expected contract
>
> A callback exception must stop the run and propagate with enough context to identify the
> callback and decision point/action, while retaining the original error message.
> Intentional return values remain valid: condition `FALSE` means veto, policy `NULL` means
> no action, and handler `NULL` means a realized action with no state patch. A condition must
> return exactly one non-missing logical value.
>
> An action-handler exception occurs before `Entity$update()` for that action, so the failed
> action must not appear in event history or mutate state. A condition or policy exception
> occurs after the triggering event was already committed; this issue does not add whole-step
> rollback.
>
> ### Acceptance checks
>
> - Condition, policy, and action-handler exceptions each terminate execution with callback
>   identity and the underlying message.
> - Intentional condition `FALSE`, policy `NULL`, and handler `NULL` behavior remains
>   unchanged.
> - Conditions reject zero-length, multi-value, `NA`, and non-logical results.
> - A failed action handler does not commit the action event or its state patch.
> - Downstream warning suppression cannot convert the errors back into valid-looking runs.
> - fluxDesign callback-generation guidance is updated to match the fail-fast contract.
>
> This issue does not decide malformed policy configuration/results, disallowed actions,
> observation coercion, trigger-predicate shape, or general Engine-step rollback.

### Q9/Q10 — Verify the tutorial path and refresh the release-facing entry points together

**Status:** Agreed as one final documentation pass after the approved runtime contracts are
implemented. Keep Tutorial 01 changes local and corrective; preserve the accessible
introductions in both READMEs; and do not present 2.1 as released before the coordinated
release actually exists.

#### Q9 — Tutorial 01 correctness and render verification

The rendered Tutorial 01 contains five error blocks caused by two underlying failures:

1. Its schema declares `payload_kg <= 20`, but three local transition examples repeatedly
   add payload without respecting that capacity. A cohort run eventually proposes an
   invalid patch, after which the undefined `batch` produces a cascading error.
2. Its parameter example correctly returns `list<ParamContext>`, but the Q5 Core defect
   nests each context. The callbacks consequently read missing direct parameter fields,
   `rlnorm()` receives an invalid argument, and the undefined `batch_pd` produces two more
   cascading errors.

The first failure is a tutorial-model inconsistency. Retain the useful 20 kg schema bound,
cap the calculated payload at that declared capacity in all three local Tutorial 01
transitions, and explain the bound in ordinary language. Do not loosen the schema, change
the seed, or wait for a different stochastic path to hide the inconsistency.

The second failure belongs to Q5. Repair context pass-through in Core and then render the
tutorial unchanged in its public `ParamContext` shape; do not teach readers to unpack the
temporary `param_ctx$params$params` defect. Tutorial 01 must also stop saying a direct
Engine run receives `param_ctx = NULL`: under the approved contract it receives one typed
context with an empty/default parameter payload. Its fallback code should test for the
specific optional parameter field and use the documented constant when that field is
absent.

Tutorials 02–05 do not load objects or artifacts from Tutorial 01. They create fresh
objects and independently source the shared `tutorials/model/urban_delivery.R`; Tutorials
04–05 also source `urban_delivery_data.R`. Q9 therefore must not edit either shared model
file. The local Tutorial 01 capacity repair cannot alter later tutorial behavior. Core
contract changes such as Q5 can, so the final verification still renders the complete
canonical sequence.

The renderer currently inherits knitr's `error = TRUE` default, embeds unexpected errors
as output, and prints `Tutorial rendering complete.` with a successful exit status. Set
unexpected chunk errors to fatal and evaluate each source tutorial in a fresh environment.
There are no intentionally failing chunks in the canonical rendered sequence; any future
teaching example that intentionally displays an error must opt in locally and explain it.

- [x] Cap `payload_kg` at the declared 20 kg capacity in the base, weather-aware, and
      parameter-aware transitions in `tutorials/src/01_core_engine_scaffold.Rmd`; add only
      the short explanatory prose needed to make the schema/transition relationship clear.
- [ ] After Q5, retain direct `param_ctx$params` access, correct the direct-run explanation,
      and make field-level fallbacks work with an empty typed context.
- [x] Make unexpected knitr errors fatal in `tutorials/render_for_github.R` and give each
      input a fresh evaluation environment.
- [ ] Re-render all five canonical tutorials against the final source package stack; the
      command must exit nonzero on an unhandled error and must not leave `#> Error` blocks
      in published output.
- [ ] Confirm Tutorial 01's ordinary cohort has 8 runs, its parameter cohort has 24 runs,
      and returned draws are direct, non-nested `ParamContext` objects.
- [ ] Keep `tutorials/model/urban_delivery.R`, `urban_delivery_data.R`, the Tutorial 01
      structure, and unrelated prose outside Q9 unless the full render exposes a separately
      reviewed problem.

#### Q10 — Root README, fluxCore README, and local maintainer context

The original Q10 finding referred to the super-repo `README.md` and
`docs/current/AGENT_CONTEXT.md`. The fluxCore README should be reviewed in the same pass
because it is the package's public contract-facing entry point. `AGENT_CONTEXT.md`, by
contrast, is local session/maintainer context: it should not be linked from either README or
treated as release documentation.

The root README's version is not currently stale. The latest tagged GitHub releases for
both flux and fluxCore, and the current CRAN fluxCore package, are 2.0.0. Keep the latest
release paragraph brief and high-level while retaining the existing ecosystem
introduction, installation routes, Start Here links, package map, clone instructions, and
common commands. Before a coordinated 2.1 release, label 2.0.0 as the latest coordinated
release. At release time, update the heading, link, root DESCRIPTION/NEWS, and tag-facing
metadata together rather than advertising 2.1 early.

The fluxCore README should remain a plain-language orientation, not become a second copy of
the tutorials. Preserve its approachable opening, event-loop explanation, urban-delivery
example, sparse-update explanation, cohort overview, and scope boundaries. Make focused
contract corrections and point readers to the canonical tutorials for progressive detail:

- identify `load_model()` with a complete schema and matching bundle clock as the validated
  assembly path, while retaining `Engine$new(bundle = ...)` as the simpler bundle-only
  path;
- after Q5, teach that `sample_params(D)` returns typed `ParamContext` objects, callbacks
  read `param_ctx$params`, and a no-draw direct run still receives an empty/default typed
  context;
- after Q2/Q6, describe trajectory records in plain terms, use `selected_action`, include
  `condition_met` and identity fields, and avoid claiming that every veto produces a record
  when `audit = FALSE`;
- replace the misleading presentation of `compose_bundles()` as the formal policy API with
  a short introduction to `DecisionPoint`, `ActionEvent`, `load_model(policy = ...)`, and
  action handlers, followed by a Tutorial 03 link. De-emphasize low-level bundle composition
  until S1 is reviewed;
- remove the public code-map pointer to the internal/deprecated Provider scaffold; and
- label episodes as an optional modeling pattern rather than a Core API, and use the shared
  delivery setting instead of residual medical examples where a small wording change is
  sufficient.

`AGENT_CONTEXT.md` is currently tracked and linked from `docs/README.md`, which conflicts
with that local role. Remove the public pointer, add the file to the root ignore rules, and
stop tracking it while preserving the maintainer's local copy. No release-facing document
should depend on its contents.

- [ ] Tighten the root latest-release blurb without displacing its introductory content;
      keep the version synchronized with actual release metadata.
- [ ] Apply the focused fluxCore README contract corrections above without expanding it
      into a long decisions/actions tutorial.
- [ ] Remove the `AGENT_CONTEXT.md` pointer from `docs/README.md`, add the local context file
      to the root ignore rules, and untrack it without deleting the maintainer's local copy.
- [ ] Run every copied README example affected by the edits against the final source stack,
      validate local links, and search the public entry points for superseded names or
      contracts.
- [ ] Keep detailed per-fix release notes in NEWS/the release announcement rather than the
      README summary, and do not rewrite historical NEWS entries.

### S3 — Add grouped decision points as a bounded 2.1 extension

**Status:** Approved as a bounded, staged v2.1 extension; each implementation gate still
requires focused verification and review. This is justified by a real modeling gap—one
policy consultation sometimes needs to coordinate selections across several existing
decision points—not by the desire to add a headline feature. Defer S3 if implementation
expands into general workflows, rollback, joint action realization, or comprehensive action
lineage.

#### Agreed conceptual boundary

Retain the trigger-bearing concept proposed in fluxCore issue #12. A grouped decision point
can be described as firing because it owns the shared trigger and initiates the coordinated
consultation. Store grouped objects separately in `schema$decision_groups`, consistent with
other schema-level group declarations; keep `schema$decision_points` homogeneous as the
ordinary leaf decision points that own conditions, allowed actions, action handlers, audit
settings, and pending-action slots.

The intended lifecycle is:

```text
event occurs
  -> grouped decision point fires
  -> the event transition is applied once
  -> member decision conditions are evaluated
  -> eligible members are presented together to policy
  -> policy returns one coordinated DecisionPlan
  -> the complete plan is validated and staged under the member ids
  -> staged actions later arbitrate and realize independently
```

If no member is eligible after the transition, do not call the grouped policy. Atomicity is
limited to accepting and staging one returned plan: an invalid selection or rejected
pending-action conflict changes none of that plan's member pending slots. It does not roll
back the triggering event or transition, policy side effects or random-number use, another
independent group, or later action realization and effects. Grouping therefore coordinates
**selection**, not realization.

This contract does not alter D1. Ordinary decision points activated by the same event remain
independent and do not acquire an implicit transaction.

#### S3a — Constructor and schema contract

Start from the issue's public vocabulary:

```r
GroupedDecisionPoint(id, trigger, members, label = NULL)
DecisionPlan(selections, metadata = NULL)
set_schema(..., decision_points = leaves, decision_groups = groups)
```

Group `members` reference the ids of canonical objects in `schema$decision_points`; groups
do not embed or copy leaf definitions. Preserve `trigger` as the required second argument in
the existing `DecisionPoint()` positional contract, but permit an explicitly supplied
`trigger = NULL` for a group-only leaf. Omitting `trigger` remains an immediate constructor
error, while the full schema rejects a `NULL`-trigger leaf that is not referenced by at
least one group.

A leaf may instead retain a normal trigger and also belong to one or more groups. Its normal
trigger opens an ordinary `propose_action()` path. When a group fires, Core does not retest
each member's direct trigger: the group trigger has already opened the consultation, and the
member's post-transition `condition` determines eligibility for `propose_plan()`. Thus a
leaf can be direct-only, group-only, or intentionally reusable in both contexts without
duplicating its action contract.

If one raw event would activate the same leaf both directly and through a fired group, or
through two fired groups, Core errors before the event transition, `Entity$update()`, any
member condition, or any policy call. The conflict is already knowable from the fired raw
triggers and declared member sets, so Core must not commit state before reporting it,
silently assign precedence, or consult the same leaf twice. This early structural failure is
distinct from a condition, policy, or plan failure after a valid trigger transition.
Non-simultaneous reuse remains valid.

Group and leaf ids share one schema-wide namespace and must be globally unique. Each group
declares at least two distinct, non-empty leaf ids; member order is meaningful and is
preserved as the deterministic order presented to policy. Every member must resolve to an
object in `schema$decision_points`, and groups cannot contain other groups. A grouped object
must not itself acquire leaf-only action handlers, allowed actions, audit settings, or a
pending slot.

Constructors perform validation that is local to the object. `set_schema()` performs the
cross-object uniqueness, membership, and trigger-reference checks because it can see both
schema collections; `load_model()` repeats the essential cross-reference checks defensively
for manually assembled schemas.

- [x] Lock the structural contract: globally unique group/leaf ids, at least two distinct
      members, preserved declaration order, leaf-only references, and no nesting.
- [ ] Finalize constructor validation messages, print behavior, and positional tests without
      adding new semantic fields.
- [ ] Add `decision_groups` to the schema contract without changing the meaning or ordering
      of `decision_points`.
- [ ] Add constructor, schema, reference-resolution, serialization, and no-group backward-
      compatibility tests.
- [x] Lock trigger ownership: explicit `NULL` means group-only; a normal leaf trigger may
      coexist with group membership; grouped eligibility uses the leaf condition; and
      simultaneous activation of the same leaf is an error before policy dispatch.
- [x] Lock ambiguous-activation timing: detect overlap from raw fired triggers and declared
      members, then error before transition, Entity mutation, conditions, or policy calls.
- [ ] Test direct-only, group-only, dual-use non-simultaneous, unreferenced `NULL` trigger,
      and ambiguous simultaneous-activation cases.

#### S3b — Policy consultation and pending-slot staging

The grouped path calls one explicit policy method once with the grouped object and the
eligible leaves in declared member order:

```r
policy$propose_plan(
  grouped_decision_point,
  eligible_decision_points,
  entity,
  sim_ctx,
  param_ctx
)
```

`eligible_decision_points` is an Engine-constructed named list of canonical leaf objects,
not a second user declaration. After the group trigger matches and its event transition is
applied, a declared member is eligible when its post-transition `condition` is absent or
returns `TRUE`; `FALSE` excludes it from that consultation, and an error follows Q8's
fail-fast rule. The Engine skips `propose_plan()` when the resulting list is empty.

The returned plan must name every eligible member exactly once and no ineligible member,
with each selection being one valid `ActionEvent` or an explicit `NULL`. An omitted eligible
id is an incomplete plan; an extra or misspelled id is invalid; explicit `NULL` records the
intentional choice of no new action. Apply A2 provenance validation against the leaf
decision-point id.

The grouped path is strict. When `schema$decision_groups` is non-empty, `load_model()`
requires the supplied policy component to expose `propose_plan()`. A missing method, wrong
return class, malformed selection names, non-`ActionEvent`/non-`NULL` member value,
disallowed action, invalid event data, or conflicting provenance is an error with group and
member context. Core does not warn and silently drop part of a coordinated result. The
triggering event and transition remain committed under the established partial-progress
boundary, but the rejected plan mutates no pending slot, emits no accepted-plan replacement
warning, and produces no accepted-plan trajectory rows. An intentional all-no-action plan
contains an explicit `NULL` for every eligible member; returning `NULL` instead of a
`DecisionPlan` is invalid.

Do not add an Engine-wide fallback flag or a `GroupedDecisionPoint` dispatch mode. A policy
that wants independent per-member choices behind the shared grouped trigger supplies an
explicit policy-side adapter: its `propose_plan()` calls the ordinary selection function for
each eligible leaf in declared order and returns those named results in one complete
`DecisionPlan`. The working documentation notation is
`propose_plan = per_member_plan(propose_action)`; this describes an adapter pattern, not yet
authorization for another exported fluxCore helper. It keeps the schema policy-neutral,
retains atomic grouped staging/audit, and makes a missing joint-policy method detectable.
fluxDesign should learn to generate or explain this adapter pattern through E1.

`DecisionPlan$metadata` is an optional named list of compact, plan-level scientific or
policy provenance, such as a strategy label, joint score, or policy-version identifier. It
is distinct from action-handler inputs in `ActionEvent$params` and action-specific
provenance in `ActionEvent$metadata`. Core treats plan metadata as opaque: it cannot affect
eligibility, result validation, staging, arbitration, realization, or effects. Without
trajectory logging it is transient. With logging it remains available in raw grouped
trajectory records but is not flattened into `trajectory_table()` as an arbitrary
list-column.

For a valid raw activation set, apply the event transition once and then freeze eligibility
before any policy callback: evaluate all fired ordinary conditions in
`schema$decision_points` order, followed by every fired group's member conditions in group
declaration/member order. Each condition is evaluated exactly once for its activation path.
Only after that complete post-transition eligibility snapshot does policy dispatch begin.
This prevents an earlier policy callback or adapter from changing which later leaves are
eligible.

When one event activates disjoint ordinary and grouped paths, preserve the existing ordinary
`schema$decision_points` policy-dispatch order first, then process grouped consultations in
`schema$decision_groups` declaration order. Each group performs its own consultation,
preflight, warning, and commit; there is no cross-group or ordinary/group transaction. This
gives stochastic callbacks a documented deterministic order without adding a priority API.
If a later independent activation fails, the run fails, but Core does not roll back earlier
policy calls, random-number consumption, diagnostics, or local pending-slot work.

Complete-plan preflight must determine action validity and every member's pending-mode
outcome before mutating a pending slot. `NULL` means no new action for that member and does
not cancel an existing pending action. Resolve each non-`NULL` selection against that leaf's
existing pending slot as follows:

| Existing pending action | Member result | Plan-level meaning |
|---|---|---|
| no | stage the new selection | valid |
| yes, `keep` | retain the existing action; discard the new selection | valid |
| yes, `replace` | stage the new selection silently | valid |
| yes, `warn` | stage the new selection and queue a replacement warning | valid if warning handling permits |
| yes, `error` | reject the complete plan | invalid |

Thus “plan accepted” does not mean every newly selected action enters the pending store. A
modeler explicitly chose `keep`, so retaining the earlier action is a successful member
outcome. The trajectory still records the policy's new selection under Q2's meaning of
`selected_action`; it does not misreport that selection as staged or realized.

Preflight all members before emitting a replacement warning or committing the candidate
pending store. If any member has an invalid selection or an `error` conflict, reject the
plan, leave every member slot unchanged, and emit no replacement warning for changes that
were never applied. For an otherwise accepted plan, aggregate all `warn`-mode replacements
into one plan-level warning that identifies the affected member ids. Emit that warning
before the one commit so a warning promoted to an error also leaves every slot unchanged.

- [x] Post the reviewed D1 clarification and final minimal urban-delivery example to issue
      #12 before grouped Engine implementation begins.
- [x] Lock the grouped policy inputs and eligibility contract: the Engine passes the named,
      declared-order list of condition-eligible leaves; no eligible leaves means no call.
- [x] Lock plan completeness: selections name every eligible leaf exactly once, exclude
      ineligible leaves, and contain one `ActionEvent` or explicit `NULL` per entry.
- [x] Make grouped result validation fail fast: missing `propose_plan()`, `NULL` in place of
      a plan, malformed plans, invalid member actions, and provenance conflicts are errors,
      not warn-and-drop behavior.
- [x] Keep independent member selection explicit at the policy boundary through a
      `propose_plan()` adapter; add no schema dispatch mode or implicit Engine fallback.
- [x] Lock `DecisionPlan$metadata` as an optional named, opaque, audit-only list that is
      transient without logging, retained in raw grouped records when logging is enabled,
      and excluded from `trajectory_table()`.
- [ ] Finalize `DecisionPlan` constructor validation messages and print behavior without
      assigning execution semantics to metadata.
- [x] Lock pending outcomes: `NULL` preserves the slot; `keep` validly retains the earlier
      action; `replace` and `warn` select the new action; and `error` rejects the full plan.
- [x] Lock all-or-none mutation and diagnostics: preflight the full plan, emit no replacement
      warnings for a rejected plan, and commit only after accepted-plan warnings have not
      been promoted to errors.
- [x] Emit at most one pending-replacement warning per accepted plan, summarizing every
      affected `warn`-mode member id.
- [ ] Implement one-call consultation, condition evaluation, result validation, and a pure
      candidate/preflight step before committing pending-slot changes.
- [ ] Prove all-or-none staging for invalid plans, pending conflicts, and warnings promoted
      to errors; prove `NULL`, `keep`, `replace`, and `warn` behavior explicitly.
- [x] Lock mixed activation order: ordinary decision points first in their existing schema
      order, then groups in `decision_groups` order, with no cross-activation transaction.
- [x] Lock eligibility phasing: after one valid trigger transition, evaluate every activated
      ordinary/group member condition in canonical order before any policy dispatch.
- [ ] Prove that disjoint activations remain independent and deterministic in their agreed
      schema order, without introducing a global transaction.
- [ ] Prove conditions are evaluated exactly once in canonical order and that an earlier
      policy callback cannot alter a later activation's already-frozen eligibility.
- [ ] Add same-seed stochastic-plan coverage under the Q7 RNG-ownership contract.
- [ ] Test the explicit per-member adapter pattern, including declared-order calls, a valid
      all-`NULL` plan, one invalid member result, and full-plan staging behavior.

#### S3c — Trajectory and identity contract

S3 needs enough audit identity to show which leaf evaluations came from one firing without
requiring scientists to replay member conditions. Add two identities:

- `grouped_decision_point_id` identifies the static schema declaration; and
- `group_activation_id` is a deterministic, non-RNG identifier for this particular firing,
  unique within the run/entity.

Use activation rather than plan identity because a group can fire with no eligible members
and therefore produce no `DecisionPlan`. Each activation permits at most one policy call and
one returned plan, so a separate plan id would be redundant in the approved contract.

Emit no synthetic parent/group trajectory row. Emit one ordinary-style leaf row for every
eligible member, including an explicit `NULL` selection. An ineligible member produces a
`condition_met = FALSE` row only when that leaf declares `audit = TRUE`, preserving the
ordinary audit opt-in. All rows from the same firing share the group and activation ids,
including audited veto rows. When policy returns a plan, its opaque metadata is available
on all raw records from that activation; when no member is eligible, any audited veto rows
have `NULL` plan metadata. Ordinary decision records have no group/activation identity.

Expose the two compact identity fields in `trajectory_table()` while keeping arbitrary plan
metadata raw-only. This does not require a durable action/proposal id and must not claim an
exact selection-to-realization link; that larger problem remains S2. Current event history
can show the realized event type and time, but cannot always attribute an identical action
type to a particular earlier group activation.

- [x] Lock the audit row shape: eligible leaf rows including explicit `NULL`, opted-in veto
      rows, no parent row, and unchanged ordinary-decision behavior.
- [x] Replace redundant plan identity with static `grouped_decision_point_id` plus a
      deterministic run-local `group_activation_id` shared by every emitted row from the
      firing.
- [x] Keep opaque plan metadata out of flattened trajectory tables and out of all execution
      semantics.
- [ ] Add only the approved group/activation identity fields, preserving ordinary-record behavior
      and the Q2/Q6 output contracts.
- [ ] Test multiple constituent selections, explicit `NULL` selections, audited vetoes,
      zero-eligible activations, ordinary decisions, and stable run-local activation
      correlation.

#### S3d — Tutorial, release notes, and ecosystem verification

Tutorial 03 must first establish ordinary decision/action behavior using the shared urban
food-delivery model. Only then should it introduce a delivery event that fires one grouped
decision point, show the eligible constituent decisions passed to one policy call, and
contrast coordinated selection with a truly composite action and with independent
realization. Until the implementation lands, examples remain labeled as proposed.

Teach grouped eligibility as a visible scientific concept rather than an Engine-internals
aside. Use controlled delivery states and display a compact progression such as:

1. an open dispatch offer with a healthy battery: only the dispatch-response member is
   eligible;
2. an open offer with a low battery: dispatch response and battery safety are both eligible
   and one plan coordinates their selections; and
3. no open offer with a healthy battery: no member is eligible, so policy is not called.

For each scenario, show the group-triggering event, the relevant post-transition state, each
member condition result, the exact eligible ids supplied to policy, and the resulting named
selections. Include an explicit `NULL` only after ordinary action selection is familiar,
explaining it as “considered, but no new action selected.” Make clear that Core computes
eligibility; policy chooses among valid actions only for that eligible set. The example must
not require readers to understand pending-store implementation details before they can
understand the scientific behavior.

- [ ] Add the progressive grouped urban-delivery example to Tutorial 03 only after S3a–S3c
      are stable; do not front-load the tutorial with grouped edge cases.
- [ ] Explain ordinary shared triggers before grouped policy consultation, and relegate the
      explicit per-member plan-adapter pattern to an advanced note rather than presenting
      it as an implicit fallback.
- [ ] Document the additive API and its deliberately narrow atomicity/lineage boundary in
      fluxCore NEWS and reference documentation.
- [ ] Run focused grouped-decision tests, the complete pre-existing no-group suite, package
      check, all five tutorials with fatal errors, and the source-stack ecosystem battery.

**Explicitly outside S3:** S1 bundle composition changes; full S2 proposal-to-realization
lineage; multiple actions per leaf; cancellation semantics; nested or dynamic groups;
parent-owned conditions/actions/audit/pending rules; cross-group transactions; joint
realization/effects; sequencing, priority, barriers, workflows, and trigger-event rollback.

### E1 — Prepare the fluxDesign 2.1 contract-sync handoff prompt

**Status:** Agreed deliverable, intentionally authored only after the fluxCore 2.1 runtime,
documentation, and verification results are stable. The working artifact is
`docs/current/PROMPT_fluxDesign_fluxCore_2_1_contract_sync.md`; creating it later is part of
this plan, while applying it in the sibling fluxDesign repository is a separately reviewed
follow-up.

**Evidence.** fluxDesign skills, prompts, schemas, examples, review guidance, and generated
package behavior encode fluxCore contracts. The approved 2.1 work changes or clarifies
constructor compatibility, action provenance, callback failure semantics, canonical time,
parameter and run identity, RNG ownership, trajectory terminology, grouped-decision policy
dispatch, and audit output. Q8 already identified several concrete fluxDesign surfaces that
would otherwise generate stale fail-soft callback code. A partial or prematurely written
handoff could therefore cause contract-invalid generated models or teach deferred S1/S2
behavior as if it had landed.

The final prompt must give fluxDesign an evidence-backed migration brief rather than a copy
of this discussion log. It should:

1. identify the final fluxCore version/commit and link the authoritative NEWS, reference,
   tutorial, issue, and regression-test evidence;
2. distinguish required 2.1 contracts, intentional breaking corrections, compatibility
   behavior, and explicit non-goals/deferred S1–S2 work;
3. direct a repository-wide inventory of affected fluxDesign skills, installed skill copies,
   prompts, model-spec schemas, generators, validators, review checklists, examples, and
   tests before edits begin;
4. specify the required behavior for generated and reviewed models, including canonical
   clocks, typed parameter contexts, identity/RNG propagation, fail-fast callbacks,
   `selected_action`, ordinary versus grouped decisions, complete `DecisionPlan` results,
   and the explicit per-member adapter pattern;
5. require progressive, domain-readable guidance rather than exposing Engine internals as
   the primary explanation; and
6. define acceptance checks showing that updated skills generate and audit packages that
   install and run against the final fluxCore 2.1 source contract.

- [ ] After Core implementation and documentation stabilize, inventory the actual
      fluxDesign surfaces and replace generic categories above with verified paths/names.
- [ ] Author the standalone `.md` handoff prompt with concise source citations, exact
      required changes, exclusions, and acceptance checks.
- [ ] Review the prompt against the final Core diff, NEWS, Tutorial 03, package checks, and
      issue outcomes; remove provisional syntax and any contract that did not land.
- [ ] Obtain explicit review before using the prompt to change fluxDesign skills or other
      sibling-repository artifacts.

---

## Final scope inventory

Contract review is complete. Items marked agreed or approved are in the 2.1 execution scope;
S1 and S2 are deliberately deferred and must not enter through implementation drift.

| ID | Candidate | Evidence summary | State |
|---|---|---|---|
| D1 | Pending-action batch semantics | Ordinary decision points remain independent; partial local state cannot escape a failed run. | Agreed: no 2.1 runtime change; issue #12 clarification posted |
| Q1 | Pending-mode test depth | Existing tests stop before either competing action can realize. | Agreed: test-only hardening |
| Q2 | Trajectory terminology | Policy selection is recorded before pending resolution; `action_taken` incorrectly implies realization. | Agreed: direct rename and documentation correction |
| Q3 | Entity update atomicity | A rejected patch leaves a phantom event and advanced clock on the caller-owned Entity. | Agreed: narrow candidate-then-commit repair; issue draft prepared |
| Q4 | Canonical time authority | `load_model()` records schema time privately while callbacks use the bundle-owned public field. A mismatch runs silently in bundle units. Reproduced. | Agreed: one enforced clock plus warned variables-only fallback; issue draft prepared |
| Q5 | Parameter-draw shape and identity | Documented `ParamContext` draws are wrapped inside another context; original identity/provenance are displaced and the parameter tutorial errors. Reproduced. | Agreed: typed-only cohort boundary with stable, order-independent ids; issue draft prepared |
| Q6 | Cohort run identity | Cohort index and run-list ids vary, but callback contexts and trajectory records all default to `run_1`; flattening also drops the join key. Reproduced. | Agreed: propagate the batch id and retain identity columns; issue draft prepared |
| Q7 | RNG ownership | A seed stored on a loaded Engine overrides cohort and streaming seeds, collapsing nominally distinct replicates. Reproduced. | Agreed: one outer execution owner, private handoff marker, and no common-path API expansion; issue draft prepared |
| Q8 | Callback failure semantics | Condition, policy, and action-handler errors can become veto, no-action, or realized no-effect behavior through warnings. Reproduced. | Agreed: fail fast with callback context; [issue #13 filed](https://github.com/jarrod-dalton/fluxCore/issues/13) |
| Q9 | Tutorial verification | Tutorial 01 has one local capacity inconsistency plus the Q5 context defect; the renderer embeds both and exits successfully. | Agreed: narrow Tutorial 01 repair plus fatal, isolated full-sequence rendering |
| Q10 | Release-facing entry points | Root release metadata is currently accurate at 2.0.0, but its blurb can be tighter; fluxCore README contracts are stale and local maintainer context is mistakenly tracked/linked. | Agreed: combined final documentation pass; ignore/untrack local context |
| S1 | `compose_bundles()` v2 contract | The helper has broader callback and ownership drift than a safe issue-11 follow-up. | Deferred to a separate design |
| S2 | Full proposal-to-realization lineage | Would require new ids/disposition fields and a larger trajectory contract. | Deferred |
| S3 | Grouped decision points | A trigger-bearing group coordinates one policy plan across existing leaf decisions while actions realize independently. | Approved for bounded, staged v2.1 implementation |
| E1 | fluxDesign 2.1 contract-sync prompt | fluxDesign encodes Core contracts across skills, prompts, schemas, generators, examples, and audits; partial updates would generate stale models. | Agreed: author evidence-backed handoff after Core stabilizes |

## Agreed staging

Contract choices are closed. Implementation proceeds through the review gates below; a
failed regression or newly discovered contract conflict returns for discussion rather than
being resolved by silent scope expansion.

1. **Correctness contract review — complete:** all A/Q/S3/E1 boundaries are recorded; the
   inventory remains staged authorization rather than permission for an undifferentiated
   batch rewrite.
2. **Focused lifecycle corrections:** implement approved action/decision changes separately,
   with a failing-before/passing-after regression for each.
3. **Adjacent Core corrections:** implement only independently approved correctness fixes.
   S3 does not begin until at least A2, Q3, Q7, and Q8 pass their focused regressions.
4. **S3a — schema gate:** implement and review grouped constructors, schema storage, and
   validation without Engine behavior.
5. **S3b — Engine gate:** implement and review one-call plan selection and per-plan atomic
   pending-slot staging.
6. **S3c — audit gate:** implement and review only the approved group/activation trajectory
   identity, leaving broader S2 lineage deferred.
7. **Documentation:** complete S3d and Q9/Q10 after runtime semantics are stable; render
   against current source with unhandled errors made fatal.
8. **Core verification:** focused tests, full fluxCore tests, package check, tutorial renders,
   and source-stack ecosystem tests against the final candidate.
9. **E1 handoff artifact:** author and review the fluxDesign contract-sync prompt from the
   verified Core surface; do not prematurely edit the sibling repository from provisional
   design notes.
10. **Landing/release gate:** explicit review before commit/push/tag/CRAN or coordinated
    ecosystem-release actions, including the separately reviewed fluxDesign follow-up.

## Current verification baseline

- Focused issue-11 lifecycle test file: 47 passing assertions, 0 failures, 2 warnings.
- Full fluxCore test suite: 429 passes, 0 failures, 3 warnings, 3 skips.
- Tier 2 source-package battery: all six current subrepos pass.
- Tier 1 in the current local library is not a valid source-stack verdict because installed
  downstream packages remain at older versions.
- Super-repo and fluxCore worktrees were clean when this plan was created.

## Progress log

| Date | Entry |
|---|---|
| 2026-08-26 | Post-landing review completed. Confirmed the issue-11 engine repair is landed and the historical plan is complete. |
| 2026-08-26 | Agreed to preserve the v2.0 positional `DecisionPoint()` argument contract by appending `on_pending_action`. |
| 2026-08-26 | Agreed that `ActionEvent$decision_point_id` is origin provenance during policy dispatch: fill missing, accept matching, reject conflicting. |
| 2026-08-26 | Created this companion plan so remaining 2.1 questions can be discussed and resolved one at a time. |
| 2026-08-26 | Agreed that ordinary decision points retain independent pending-action semantics; no general two-pass resolver will be added to 2.1. Recorded a review-before-posting clarification for issue #12, where complete-plan prevalidation has a meaningful contract boundary. |
| 2026-08-26 | Required Tutorial 03 to develop every decisions/actions example as a progressive extension of the shared urban food-delivery tutorial model, not a standalone lifecycle toy. |
| 2026-08-26 | Approved Q1 as test-only hardening: two deterministic proposals, exact retained-action realization times, and no runtime edit unless the stronger regression exposes a separately reviewed defect. |
| 2026-08-26 | Defined `selected_action` as the policy selection recorded before pending resolution and approved the breaking `trajectory_table()` rename from `action_taken`, with no legacy alias; event history remains realization evidence. |
| 2026-08-26 | Reproduced Q3 against current source: an invalid state patch errors after advancing the Entity event log, index, and clock. Embedded a review-before-posting GitHub issue draft and reprex. |
| 2026-08-26 | Approved the narrow Q3 contract: `Entity$update()` will compute candidate state, history, and event data before committing any coupled field. No deep-copy transaction or general Engine rollback; successful-path performance is an explicit merge gate. |
| 2026-08-26 | Agreed that schema and bundle represent one model clock: schema time supplies declarative meaning, bundle time carries runtime scheduling, and `load_model()` must reject semantic disagreement rather than apply precedence. Left the variables-only schema compatibility case explicit for follow-up. |
| 2026-08-26 | Completed Q4 contract review: `load_model()` retains a warned variables-only fallback in 2.1, while incomplete or conflicting full schemas fail. `Entity$new()` and direct `Engine$new()` remain unaffected. |
| 2026-08-26 | Embedded a review-before-posting Q4 GitHub issue draft with a verified split-clock reprex and the agreed 2.1 acceptance boundary. |
| 2026-08-27 | Completed Q5 contract review: cohort draws are typed `ParamContext` objects, bare-list compatibility is removed from Core and localized in fluxForecast, and positive unique draw ids remain authoritative across ordering, parallel dispatch, indexing, replay, and deterministic simulation seeding. Embedded a review-before-posting issue draft and kept sampling RNG, run identity, and RuntimeContext seeding separate. |
| 2026-08-27 | Completed Q6 contract review: the cohort index id is authoritative within its batch and must match the run-list name, callback `SimContext`, and every trajectory record. `trajectory_table()` will retain `run_id` and `entity_id`; direct-run identity, entity-id authority, and Q7 seeding remain separate. Embedded a review-before-posting issue draft. |
| 2026-08-27 | Completed Q7 contract review: direct Engine runs, cohort runs, and lower-level run harnesses each have one RNG owner. Cohort settings override stored Engine defaults without a second seed; `run_draw()` preserves caller-managed RNG; no public ownership flag or common-path bookkeeping is added. Embedded a verified reprex and review-before-posting issue draft. |
| 2026-08-27 | Completed Q8 contract review: callback exceptions no longer masquerade as condition vetoes, intentional no-action choices, or realized no-effect actions. Preserved explicit `FALSE`/`NULL` outcomes, required scalar non-missing logical conditions, documented partial progress, and kept adjacent validation contracts separate. Verified a three-case urban-delivery reprex, recorded the fluxDesign documentation impact, and prepared an authorized GitHub bug report. |
| 2026-08-27 | Filed the reviewed Q8 bug report as [fluxCore issue #13](https://github.com/jarrod-dalton/fluxCore/issues/13), including the verified urban-delivery reprex, fail-fast contract, partial-progress boundary, acceptance checks, and explicit exclusions. |
| 2026-08-27 | Completed the combined Q9/Q10 review. Localized Tutorial 01's errors to a three-site payload-capacity inconsistency and the already-approved Q5 defect; confirmed later tutorials do not consume Tutorial 01 artifacts; and required fatal, isolated full-sequence rendering. Verified that 2.0.0 remains the current public release and added a focused fluxCore README contract refresh. |
| 2026-08-27 | Clarified that `AGENT_CONTEXT.md` should be untracked local maintainer context, not a README-linked or release-maintained document; Q10 will remove its public pointer, add an ignore rule, and preserve the local copy while untracking it. |
| 2026-08-27 | Promoted S3 to a conditional, staged v2.1 extension while leaving S1 and full S2 deferred. Agreed that a trigger-bearing grouped decision point lives in `schema$decision_groups`, coordinates one policy consultation across eligible leaf decisions, performs all-or-none plan staging, skips policy when no member is eligible, and does not make later action realization atomic. |
| 2026-08-27 | Locked S3 trigger ownership: `DecisionPoint()` keeps its required positional trigger argument but accepts explicit `NULL` for a referenced group-only leaf; normally triggered leaves may also be group members; a group consult uses member conditions rather than member triggers; and simultaneous direct/group or overlapping-group activation of one leaf errors before policy dispatch. |
| 2026-08-27 | Locked the remaining S3a structure: group and leaf ids are globally unique; a group references at least two distinct canonical leaves in preserved order; nesting is prohibited; `set_schema()` owns cross-object validation and `load_model()` repeats essential checks for manually assembled schemas. |
| 2026-08-27 | Locked the first S3b policy boundary: after one group trigger and transition, Core constructs the declared-order eligible-member list from leaf conditions, skips policy when it is empty, and otherwise requires a complete named `DecisionPlan` containing one `ActionEvent` or explicit `NULL` for every and only eligible leaf. Required Tutorial 03 to expose each step with controlled urban-delivery states for a general R-literate scientific audience. |
| 2026-08-27 | Retained optional `DecisionPlan$metadata` under a narrow audit contract: it is a compact named list of opaque plan-level provenance, never an execution input, transient when trajectory logging is off, available only in raw grouped records when logging is on, and absent from `trajectory_table()`. |
| 2026-08-27 | Locked grouped pending resolution: explicit `keep` is a successful plan outcome that retains the earlier action even though the new policy selection remains auditable; `replace`/`warn` stage the new selection; `NULL` leaves the slot alone; and any invalid or `error` member rejects the whole plan without slot mutation or misleading replacement warnings. |
| 2026-08-27 | Chose one aggregated pending-replacement warning per accepted grouped plan. It names all affected `warn`-mode members and is emitted after complete preflight but before the single commit, so warning promotion cannot leave partial slot mutation. |
| 2026-08-27 | Locked S3c audit identity and rows: each firing gets a deterministic run-local `group_activation_id` alongside its static `grouped_decision_point_id`; eligible and opted-in veto leaf rows share those ids; there is no parent row or redundant plan id; zero-eligible audited firings remain identifiable; and broader action lineage stays deferred to S2. |
| 2026-08-27 | Locked mixed activation order: ordinary decision points retain their existing schema order and dispatch before groups, groups dispatch in `decision_groups` order, and each activation retains its own staging boundary without a new priority API or global rollback. |
| 2026-08-27 | Kept grouped dispatch strict while supporting trigger-convenience use cases explicitly at the policy boundary: absent/malformed `DecisionPlan` results error; an intentional `propose_plan()` adapter may collect per-member `propose_action()` results into one complete plan; no Engine fallback flag or schema dispatch mode is added. |
| 2026-08-27 | Added E1, a required post-Core `.md` handoff prompt directing fluxDesign to synchronize its skills, prompts, schemas, generators, review behavior, examples, and tests with the final verified 2.1 contracts while excluding work that did not land. |
| 2026-08-27 | Closed the remaining S3 semantic review: ambiguous direct/group or overlapping-group activation is detected from raw triggers and errors before transition or Entity mutation; otherwise Core applies one transition, freezes all ordinary/group member eligibility in canonical condition order, and only then begins ordinary-first/group-second policy dispatch. |
| 2026-08-27 | Reviewed and posted the exact issue #12 clarification and urban-delivery contract example. The approved text remains embedded in this plan; the temporary standalone posting file was removed after successful posting. |
| 2026-08-27 | Closed the plan-design phase. All proposed contract findings were approved, deferred, or bounded; S3 was admitted through explicit gates; E1 records the later fluxDesign handoff; and the remaining unchecked items are execution, documentation, verification, and release work rather than unresolved design questions. |
| 2026-08-27 | Landed A1 (`afe7df1`), A2 (`3f29d61`), and Q1 (`eaaab13`) as separate tested fluxCore patches: positional compatibility restored, action provenance enforced, and all four pending modes observed through realization. |
| 2026-08-27 | Landed Q8 (`3b7009c`) with fail-fast condition, policy, and action-handler errors; 139 focused and adjacent assertions passed without warnings or failures. |
| 2026-08-27 | Landed Q3 (`8f6aa53`) with candidate-then-commit Entity updates; 184 focused/adjacent assertions passed (2 pre-existing skips). Alternating five-repetition benchmarks measured candidate/current elapsed ratios of 1.013 (20 variables, 3,000 sparse updates), 1.009 (500 variables, 1,000 full-width updates), and 0.996 (3,000-event prefill plus 1,000 sparse updates), so no material successful-path regression was observed. |
| 2026-08-27 | Landed Q4 (`a0fa3d1`) with semantic full-schema/bundle clock agreement, one warned variables-only compatibility path, no private shadow clock, and 128 focused/adjacent assertions passing. Downstream-consumer confirmation remains paired with the coordinated forecast pass. |
| 2026-08-27 | Landed Q2/Q6 (`d023993`) as one output-identity patch: cohort ids now reach callbacks and records, and flattened output starts with `run_id`, `entity_id` and uses `selected_action`. Focused serial/mclapply/future tests passed; after installing the same current source on PSOCK workers, the cluster regression passed 67 assertions. |
| 2026-08-27 | Completed the independent Q9 repairs: all three Tutorial 01 payload transitions honor the declared 20 kg bound, and the renderer now treats unexpected chunk errors as fatal while using a fresh evaluation environment per input. Final parameter-example edits and full-sequence rendering remain gated on Q5. |
