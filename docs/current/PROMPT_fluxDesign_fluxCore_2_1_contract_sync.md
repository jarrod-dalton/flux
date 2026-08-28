# Prompt — synchronize fluxDesign with the final fluxCore 2.1 contracts

Use this prompt only after the fluxCore 2.1 hardening branch has been reviewed and its
final source commit has been recorded below. Work in the `fluxDesign` repository. Do not
modify fluxCore from this task.

## Authoritative source

- fluxCore version: `2.1.0` development source
- fluxCore commit: `b32a6ff` (`main`, after the S3d documentation checkpoint)
- flux super-repo plan:
  `docs/current/PLAN_fluxCore_2_1_hardening.md`
- fluxCore release notes: `subrepos/fluxCore/NEWS.md`, section `fluxCore 2.1.0`
- public decision/action explanation:
  `tutorials/03_decisions_policy.md`
- grouped-decision issue record:
  `https://github.com/jarrod-dalton/fluxCore/issues/12`
- fail-fast callback issue record:
  `https://github.com/jarrod-dalton/fluxCore/issues/13`
- primary Core regression evidence:
  - `tests/testthat/test_v2_skeleton.R`
  - `tests/testthat/test_v2_action_lifecycle.R`
  - `tests/testthat/test_entity_update_atomicity.R`
  - `tests/testthat/test_load_model_time_spec.R`
  - `tests/testthat/test_q5_q7_param_rng.R`
  - `tests/testthat/test_run_cohort_cluster.R`
  - `tests/testthat/test_callback_fail_fast.R`
  - `tests/testthat/test_trajectory_output_contract.R`
  - `tests/testthat/test_s3a_grouped_contract.R`
  - `tests/testthat/test_s3b_grouped_engine.R`
  - `tests/testthat/test_s3c_grouped_trajectory.R`

Treat the checked-out Core source and tests at the recorded commit as authoritative when
older fluxDesign prose, examples, fixtures, or assumptions disagree. Do not treat the CRAN
package as the source of truth until 2.1 is released.

## Objective

Bring fluxDesign's model-specification workflow, skills, prompts, generators, validators,
review surfaces, examples, and integration checks into explicit alignment with fluxCore
2.1. Preserve fluxDesign's stage-aware workflow and human signoff gates. Explain the new
contracts in domain-readable terms first; Engine internals are supporting detail, not the
primary teaching language.

This is a contract synchronization, not permission to redesign fluxDesign broadly.

## Begin with a repository inventory

Before editing, inspect and report the actual affected surfaces. At minimum reconcile these
known paths and their maintained mirrors:

- core workflow guidance:
  - `skills/flux-base/SKILL.md`
  - `skills/flux-designer/SKILL.md`
  - `skills/flux-coder/SKILL.md`
  - `skills/flux-auditor/SKILL.md`
- prompt sources and aliases:
  - `prompts/02_spec_extractor.prompt.md`
  - `prompts/fluxDesigner.prompt.md`
  - `prompts/03_codegen.prompt.md`
  - `prompts/fluxCoder.prompt.md`
  - `prompts/04_contract_check.prompt.md`
  - `prompts/fluxAuditor.prompt.md`
  - any `fluxDataPrep` guidance that states parameter/runtime contracts
- model-spec contract and validation:
  - `schema/model_spec_schema.json`
  - `factory/validate_model_spec.R`
  - `factory/model_spec_check_lib.R`
  - `factory/model_spec_lock_lib.R`
  - `factory/upgrade_model_spec_1_0_to_2_0.R`
  - the corresponding schema/validator copies under
    `tools/fluxModelSpec/inst/`
- review UI and workbook surfaces:
  - `tools/fluxModelSpec/app.R`
  - `tools/fluxModelSpec/inst/app/app.R`
  - `tools/fluxModelSpec/R/write_review_workbook.R`
  - `tools/fluxModelSpec/R/model_spec_review.R`
  - `tools/fluxModelSpec/R/model_spec_migration_review.R`
- code-generation/audit infrastructure:
  - `factory/flux_design_lib.R`
  - `factory/run_contract_scan.R`
  - `factory/nonstandard_runtime_review_lib.R`
- public explanation and review checklists:
  - `docs/COMPLETE_FLUX_DESIGN_GUIDE.md`
  - `docs/GLOSSARY.md`
  - `docs/review-guides/MODEL_SPEC_REVIEW.md`
  - `docs/review-guides/MODEL_CODE_REVIEW.md`
- fixtures and acceptance tests:
  - `evals/fixtures/fluxcore_2_1_lifecycle_integration.R`
  - `evals/run_golden_evals.R`
  - `tools/fluxModelSpec/tests/fixtures/fluxcore_2_1_decision_boundary.json`
  - `tools/fluxModelSpec/tests/testthat/test-fluxcore-2-1-decision-boundary.R`

Do not edit generated `*.Rcheck` trees. Determine which prompt/skill copies are canonical,
use fluxDesign's normal synchronization mechanism, and prove maintained aliases and
installed operational skill mirrors match their repository sources after the source edits
land. Do not hand-edit a cache as the only fix.

## Required fluxCore 2.1 contracts

### 1. One canonical model clock

- A complete schema and its bundle each expose a valid `time_spec`, and `load_model()`
  requires them to be semantically equal in unit, origin instant, origin class, and zone.
- Generated packages should define one canonical `model_time_spec` object and use it in
  both schema and bundle construction.
- A genuinely variables-only schema is a warned 2.1 compatibility input, not the preferred
  generated shape. A malformed full schema or mismatched clock is an error.
- Callbacks read `sim_ctx$time_spec`; do not teach obsolete `sim_ctx$time` access or infer
  units from an unrelated schema field.
- Variable-level units remain descriptive variable metadata and are not a replacement for
  the model clock.

Add generation and audit checks that catch missing, independently conflicting, or malformed
clock declarations before a scientific run.

### 2. Typed parameter contexts and stable draw identity

- Cohort `param_draws` and `bundle$sample_params(D)` use `list<ParamContext>` only. Bare
  parameter lists at that boundary are rejected.
- Callback code reads the payload from `param_ctx$params`.
- Preserve each positive integer-valued `draw_id`; execution may receive contexts from
  parallel workers out of arrival order, but Core sorts and maps by stable id rather than
  renumbering by arrival position.
- A direct run still receives a typed empty/default `ParamContext`, not `NULL`.
- Do not generate nested `param_ctx$params$params`, bare callback shims, or code that relies
  on result arrival order for identity.

Update generated fixtures and reviewer checks to use real `ParamContext()` objects even
when invoking callbacks directly.

### 3. Run identity and RNG ownership

- Cohort `run_id` is the batch-local join key carried consistently by the cohort index,
  run-list name, `SimContext`, and trajectory records. Stable entity/draw/simulation
  coordinates remain the cross-call replay identity.
- Each outer execution path owns seeding. An explicit cohort or streaming seed/runtime
  overrides a different Engine-stored seed; private inner Engine calls do not reseed.
- Generated callbacks and helpers must not call `set.seed()` or create competing RNG
  ownership. Continue to pass stochastic parameter uncertainty through `ParamContext`.
- Same seed does not imply causal alignment after two policies consume randomness
  differently. Do not generate that scientific claim without an explicit common-random-
  number or experimental design.

### 4. Decision/action lifecycle and provenance

Teach and audit the lifecycle in this order:

```text
trigger event matches
  -> event transition commits
  -> post-transition condition determines eligibility
  -> policy selects ActionEvent or intentional NULL
  -> pending rule resolves the selected action
  -> retained action competes on the event calendar
  -> realized ActionEvent enters event history
  -> action handler applies its sparse state effect
```

Keep these distinctions explicit:

- `selected_action` is policy-selection evidence recorded before pending resolution. It is
  not proof of staging, realization, or effect.
- `trajectory_table()` has no `action_taken` compatibility alias. Migrate generated code,
  reports, schemas, examples, and checks to `selected_action`; use entity event history as
  realization evidence.
- `ActionEvent$decision_point_id` is provenance during policy dispatch. Core fills `NULL`,
  accepts an exact owning-leaf match, and errors on a mismatch. It is not a cross-decision
  routing override.
- Preserve the released positional `DecisionPoint()` contract, but generated code should
  continue to name public arguments. `on_pending_action` is appended after
  `observation_fn` and `label`; Core's default is `"warn"`.
- Ordinary decision points sharing a trigger remain independent. Their policy calls,
  pending slots, warnings, errors, and later realization do not become one transaction.
- `Entity$update()` rejects an invalid state patch without mutating event history, clock,
  state, or state history. Do not add a broader rollback promise around arbitrary callback
  side effects.

Reconcile fluxDesign's current `on_pending_action` vocabulary with the actual Core values
`warn`, `replace`, `keep`, and `error`. If fluxDesign deliberately requires explicit modeler
review instead of accepting Core's default, represent that review state separately rather
than incorrectly omitting the runtime value `warn`.

### 5. Callback failures are fail-fast

- An error thrown by a decision condition, `policy$propose_action()`,
  `policy$propose_plan()`, or an action handler stops the run with callback context.
- Do not say Core catches these errors and converts them into veto, no action, or no state
  patch.
- Intentional results remain explicit and callback-specific: a condition can return
  scalar `FALSE`; an ordinary policy can return `NULL`; an action handler can return `NULL`
  for a realized action with no state patch; a grouped policy must return a complete
  `DecisionPlan` and uses explicit member `NULL` entries.
- The triggering event/transition may already be committed when a later condition or policy
  throws. A failing action handler stops before that action event or effect is committed.
- Remove generated broad `tryCatch()` wrappers that turn a scientific callback failure into
  a plausible-looking simulation result. This does not prohibit contextual error wrapping,
  input/UI error handling, or a scientifically reviewed fallback implemented deliberately
  inside the callback.

Search specifically for the stale fail-soft statements currently present in
`docs/COMPLETE_FLUX_DESIGN_GUIDE.md`, `docs/review-guides/MODEL_CODE_REVIEW.md`, and the
code-generation/audit prompts.

### 6. Grouped decisions are a separate, bounded schema concept

fluxCore 2.1 adds:

```r
GroupedDecisionPoint(id, trigger, members, label = NULL)
DecisionPlan(selections, metadata = NULL)
set_schema(..., decision_points = leaves, decision_groups = groups)
```

Represent grouped declarations separately from canonical leaf decision points, just as
Core stores `schema$decision_groups` separately from `schema$decision_points`.

Required structural behavior:

- Group ids and leaf ids share a unique namespace.
- A group names at least two distinct canonical leaf ids in meaningful declaration order.
- Groups contain leaves only; no nested or dynamic groups.
- A group-only leaf explicitly has `trigger = NULL`; a leaf may instead retain a normal
  trigger and also be reusable through a group.
- A `NULL`-trigger leaf that belongs to no group is invalid.
- The group owns the shared trigger. During group activation, member triggers are not
  retested; member conditions use post-transition entity state.
- If the same raw event would activate one leaf both directly and through a group, or
  through two groups, Core errors before applying the transition.

Required policy behavior:

- Core computes the eligible leaves and passes the exact named list in group member order
  to one `policy$propose_plan()` call.
- No eligible leaves means no policy call.
- A `DecisionPlan` must name every and only eligible member exactly once. Each value is one
  valid `ActionEvent` or explicit `NULL`; bare `NULL` instead of a plan is invalid.
- `DecisionPlan$metadata` is optional named, opaque audit information. It does not affect
  execution and remains raw-only rather than becoming a `trajectory_table()` list-column.
- A policy may expose an explicit `propose_plan = per_member_plan(propose_action)` adapter
  when independent per-member logic is desired. Core has no implicit fallback for a missing
  `propose_plan()` method. Teach this as an advanced policy pattern, not as Engine magic.

Required staging/audit behavior:

- Core validates and preflights the complete plan, then performs one pending-store commit.
  `NULL` and `keep` may leave a member slot unchanged; `replace` changes it silently;
  `warn` changes it after one aggregate plan warning; `error` rejects the plan.
- An invalid member, error-mode conflict, or warning promoted to error changes none of that
  plan's pending slots. This is atomic plan acceptance/staging only.
- Selected actions still arbitrate and realize independently. Grouping does not create a
  composite action, joint effect, priority, workflow, or rollback boundary.
- Emit no synthetic parent trajectory row. Eligible leaves, explicit-`NULL` leaves, and
  opted-in veto rows carry `grouped_decision_point_id` and deterministic run-local
  `group_activation_id`. Ordinary rows contain `NA` for those flattened fields.

Use the final urban food-delivery Tutorial 03 progression as the teaching model: ordinary
selection first, repeated pending actions, independent shared triggers, then a grouped
dispatch-response/battery-safety consultation with healthy, low-battery, zero-eligible,
and explicit-`NULL` scenarios.

## Model-spec versioning and migration gate

The current model-spec schema declares version `2.0`, sets
`decision_points[].activation_events` to at least one item, has no
`decision_groups` field, and uses strict `additionalProperties` in relevant records. A
group-only leaf and grouped policy therefore cannot be added safely as an unversioned
informal convention.

Before changing the schema, present one explicit versioning proposal for review. It must:

1. say whether grouped-decision representation is an additive model-spec version or a
   larger contract-version change, and justify the choice;
2. define an explicit upgrade path for valid 2.0 specifications;
3. preserve ordinary 2.0 decision semantics during migration;
4. ensure older validators/apps reject an unknown newer version rather than silently
   dropping `decision_groups`, group membership, group-only trigger intent, plan rules, or
   metadata intent;
5. synchronize the canonical schema, packaged schema, validator, app, workbook, locks,
   hashes/fingerprints, examples, and tests; and
6. block code generation when grouped fields are incomplete, ambiguous, or marked
   `NEEDS_REVIEW`.

Do not simply relax `additionalProperties`, overload `decision_points`, encode a group as a
synthetic action, or infer grouped semantics from several decisions sharing an activation
event. Ordinary shared triggers must remain representable as ordinary independent
decisions.

The review UI should let a scientist see, in plain terms:

- the event that opens the group consultation;
- its ordered leaf members;
- each leaf's post-transition eligibility meaning;
- whether the leaf is group-only or also directly triggered;
- the policy's complete-plan responsibility and intentional `NULL` option;
- each leaf's pending mode; and
- the fact that selected actions later realize independently.

## Code generation and audit acceptance

Add or revise fixtures so the workflow proves all of the following against the exact final
fluxCore source commit:

1. A generated package declares the same canonical `time_spec` in schema and bundle and
   rejects a deliberate mismatch.
2. `sample_params()` returns out-of-order/non-contiguous typed `ParamContext` ids; cohort
   output preserves canonical id mapping and callback payload access.
3. Cohort index, run names, callback `sim_ctx$run_id`, and trajectory `run_id` agree; serial
   and supported parallel paths remain aligned.
4. A thrown condition, ordinary policy, grouped policy, and action-handler error reaches the
   caller with context; intentional `FALSE`/ordinary `NULL`/handler `NULL`/explicit grouped
   member `NULL` remain valid.
5. Generated reports use `selected_action`, and a keep-mode case demonstrates why event
   history is required to prove realization.
6. `ActionEvent` provenance fill/match/mismatch behavior is checked.
7. One event can activate two ordinary decisions independently.
8. A group-only urban-delivery example calls `propose_plan()` once with the exact eligible
   ids, requires a complete plan, records shared activation identity, and shows constituent
   actions realizing at separate times.
9. Zero eligible members skip policy while audited veto rows, when requested, retain group
   activation identity.
10. A deliberate direct/group overlap fails before transition.
11. A malformed grouped plan and an error-mode pending conflict leave every member pending
    slot unchanged.
12. A generated package installs, passes its tests/check, and runs through fluxDesign's
    contract scan against the recorded Core commit.

Update existing lifecycle fixtures rather than creating a parallel, contradictory contract
suite. Keep checks deterministic and assert observable scientific/API behavior rather than
private Engine implementation names.

## Explicit non-goals

Do not introduce or teach any of the following as fluxCore 2.1 capability:

- generalized bundle/schema composition for decisions or groups (deferred S1);
- durable proposal-to-realization/action lineage beyond the landed fields (deferred S2);
- multiple selected actions per leaf or cancellation semantics;
- nested/dynamic groups or parent-owned leaf behavior;
- cross-group transactions, joint action realization/effects, barriers, workflows,
  sequencing, or priority APIs;
- trigger-event rollback, callback side-effect rollback, or RNG rollback;
- a Core-provided implicit per-member plan fallback; or
- automatic causal comparability from matching seeds.

Do not update release claims or say fluxCore 2.1 is published until its coordinated release
exists.

## Required work report and stopping points

Work in reviewable stages:

1. inventory and model-spec versioning proposal;
2. schema/validator/migration/app/workbook contract;
3. Designer extraction/review guidance;
4. Coder generation guidance and fixtures;
5. Auditor checks and fail-fast guidance;
6. documentation, aliases, installed-skill synchronization, and full acceptance battery.

After each stage, report:

- exact files changed;
- contract decisions made;
- tests run and their results;
- any source/alias or source/installed-skill drift;
- unresolved questions or blockers; and
- confirmation that S1/S2 and other non-goals did not enter the patch.

Stop for explicit review before choosing the model-spec version/migration shape, before
modifying installed skills, and before any release/tag/publication action. Do not conceal an
unsupported grouped field by dropping it, warning and continuing, or generating ordinary
independent decisions in its place.
