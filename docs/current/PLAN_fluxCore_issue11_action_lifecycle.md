# Implementation Plan — fluxCore #11: Action Proposal Lifecycle

**Issue:** https://github.com/jarrod-dalton/fluxCore/issues/11
**Target version:** fluxCore 2.1.0
**Status:** Complete.
**Started:** 2026-08-20

---

## Purpose

Issue #11 proposes two changes to fluxCore's action lifecycle. Investigation confirmed one
of them as a real bug, confirmed the other as a legitimate ergonomics enhancement, and
**discovered a third, more severe defect not in the issue** that affects the default
configuration.

This document is the durable record of the analysis and the staged work. It is written so
that work can be resumed cold, in a different environment, without re-deriving anything.

---

## Verified findings

All three were confirmed empirically on 2026-08-20 against fluxCore `main` at commit
`6cba830`, using `pkgload::load_all()` and a self-contained reproduction script.

### D1 — Realized action is never consumed (issue Part A) — **CONFIRMED BUG**

`Engine$run()`'s `step_once()` never removes the realized proposal from `proposals`. Under
`"ALL"` refresh the whole set is rebuilt, masking it. Under **selective** refresh only ids in
`refresh_ids` are mutated, so `.action.<dp_id>` persists at an unchanged `time_next` and is
re-picked indefinitely.

Observed output (selective refresh, action at `+0.1`, `max_events = 8`):

```
  j time event_type
1 0  0.0       init
2 1  1.0    trigger
3 2  1.1   schedule
4 3  1.1   schedule
5 4  1.1   schedule
6 5  1.1   schedule
7 6  1.1   schedule
8 7  1.1   schedule
9 8  1.1   schedule
```

The action replays until `max_events` halts the run.

**Why this is fluxCore's problem, not the model's:** the string `.action.` occurs in exactly
one place in the entire package (`R/engine.R`, in the `pid <- paste0(".action.", dp$id)`
line). It is undocumented, unexported, and dot-prefixed. A model author cannot retire it
without depending on an engine-private naming convention.

**Coverage:** zero. Every action/decision-point test in the suite uses
`refresh_rules = "ALL"`.

### D2 — Pending action destroyed by `"ALL"` refresh — **NOT IN ISSUE; MORE SEVERE**

The `"ALL"` branch performs `proposals <<- .call_propose_events(...)`, a full replacement.
Only `action_props` generated in the **current** step are merged back afterward. Therefore an
action proposed in an earlier step that has not yet realized is silently destroyed.

`refresh_rules` is optional and defaults to `"ALL"`, so **this is the default behavior**.

Observed output (default `"ALL"` refresh, action proposed at t=1 for t=6, `max_events = 8`):

```
  j time event_type
1 0    0       init
2 1    1    trigger
3 2    3       tick
4 3    5       tick
5 4    7       tick
6 5    9       tick
7 6   11       tick
8 7   13       tick
9 8   15       tick
```

The action scheduled for t=6 never appears. It was destroyed by the first refresh after it
was proposed. After the Phase 1 fix the same model yields `schedule` at t=6, between the
t=5 and t=8 ticks.

> **Methodology note.** The first attempt at this reproduction scheduled the action at t=31
> while `max_events = 8` only advanced the clock to t=15. The action was therefore beyond the
> run's horizon and its absence proved nothing. The delay was reduced so that the action is
> reachable, and the defect was then confirmed by a direct before/after comparison using
> `git stash` on `R/engine.R`. Any future re-verification must keep the scheduled action
> inside the reachable horizon.

This breaks issue #11's own motivating example — an action carrying `delay_days = 30`
evaporates before it can fire. It is invisible in the existing tests and tutorials only
because every action there uses a tiny offset (`last_time + 0.1`) that happens to fire before
the next event.

### D3 — Action `params` unreachable at proposal time (issue Part B) — **ENHANCEMENT**

`Entity$events` is a data.frame of only `j`, `time`, `event_type`. `ActionEvent$params`,
`metadata`, and `decision_point_id` are therefore unreachable from `propose_events()`.
`refresh_rules()` already receives `last_event`, so this is a genuine asymmetry within a
single handoff.

This is **not** a correctness bug — a workaround exists (a schema variable used purely as
transport). But that variable pollutes the schema, enters `entity$hist`, and appears in every
trajectory `state_before`/`state_after` while modelling nothing.

### Root cause unifying D1 and D2

Engine-owned action proposals live in the model's `proposals` dictionary, which is governed
by the model's refresh contract. Selective refresh **under-collects** them (D1); `"ALL"`
refresh **over-collects** them (D2). The fix is to separate ownership rather than
special-case the `.action.` prefix.

---

## Confirmed semantics (for documentation)

- **There is no queue.** A policy returns exactly one `ActionEvent` or `NULL` — never a list.
- **One slot per decision point,** keyed by decision point id. Several decision points can
  each hold one pending action simultaneously.
- **Same decision point re-proposing** while its previous action is still pending follows
  `on_pending_action`: the default warns and replaces, with explicit replace, keep, and error
  modes available.
- **Lifecycle order:** pick → trigger check (pre-transition, raw event) → `transition()` *or*
  `action_handler()` → `entity$update()` → condition check (post-transition) → policy →
  trajectory records → `observe()` → `stop()` → `max_time` → `refresh_rules()` →
  `propose_events()` → merge new actions.
- **State is always current** by the time `propose_events()` runs, so passing `changes` to it
  would be redundant.
- **An `action_handler` replaces `transition()`** for that event; it is not called in addition.

### Chained decision points — already supported

`ActionEvent()` sets `event_type = action_type`, and `fired_decision_points()` loops all
schema decision points with no exclusion for action events. A decision point whose `trigger`
names an action type therefore fires when that action realizes and can propose the next
action.

**This resolves the multi-action question.** Multi-step workflows are expressed by chaining
decision points, each confined to one action. Letting a policy return a list of actions is
**out of scope and deferred**.

Because `trigger` is evaluated pre-transition on the raw event, a predicate trigger on a
chained decision point can branch on the incoming `event$params` without touching state.

Sharp edges:
- **Event catalog gap.** Action types are auto-registered into the catalog only if some
  decision point declares an `action_handler` for them. A chained action with a `NULL`
  handler must be declared in `bundle$event_catalog` manually or the run errors.
- **Unbounded chains.** A ↔ B mutual triggering never terminates; `max_events` is the only
  backstop. `.validate_event_time()` permits `time == last_time`, so a zero-delay chain can
  spin at a single timestamp.
- **D2 dependency.** Chain steps with meaningful delays are destroyed before firing until D2
  is fixed.
- **Coverage:** zero. No existing test triggers a decision point from an action event.

---

## Blast radius

Negligible. `ActionEvent` and `action_handlers` appear **zero times** across fluxForecast,
fluxPrepare, fluxValidation, fluxOrchestrate, and fluxModelTemplate. All downstream
`propose_events()` implementations use explicit named formals, so formals-based injection of
`last_event` cannot affect them.

---

## Existing documentation defects found

- `tutorials/03_decisions_policy.md` (~L509): claims both `ActionEvent`s "enter a queue and
  **arbitration** picks the one with the earliest `time_next`." Wrong model — it is a slot
  map, and the later action is not discarded, it fires afterward. The statement is
  accidentally true today only because D2 destroys the other action.
- `tutorials/01_core_engine_scaffold.md` (~L478) already states the correct principle: *"The
  winning process must always be refreshed. Its proposal was just consumed; if it is not
  re-asked it will hold a stale `time_next`... and will keep winning indefinitely."* The
  engine simply fails to honor its own documented rule for the one process it owns.
- The flow diagram `tutorials/figure/engine-loop-decision-point.png` has eight correctness
  errors (enumerated in Phase 5b).

---

## Decisions taken

| Decision | Resolution |
|---|---|
| Scope | D1 + D2 + D3 |
| D1/D2 fix approach | Separate engine-owned `action_proposals` store, not `.action.` special-casing |
| Dot-prefixed ids | Must never surface to users; leading-dot namespace reserved |
| Multi-action per decision point | Out of scope — deferred; use chained decision points |
| Version | 2.1.0 |
| CRAN | Land on GitHub now; submission timing decided later |
| Docs/tutorials | In scope; must be jargon-free |

Also riding along in the eventual CRAN submission: commit `6cba830`, the DESCRIPTION
function-name removal requested by the CRAN admin.

---

## Out of scope

Per the issue's own non-goals: `ActionSpec` / action-definition abstraction; changes to
action-handler state-patch semantics; direct proposal mutation by policy or handler code;
`action_kind` taxonomy.

Additionally excluded: generalizing proposal consumption to model-owned processes (the model
keeps that responsibility, per tutorial 01's stated principle); multi-action per decision
point; downstream package changes; CRAN submission.

---

## Staged work

### Phase 1 — Engine fix (D1 + D2)  ✅ COMPLETE

- [x] 1.1 Introduce an `action_proposals` store in `Engine$run()`, keyed by decision point
      id, that model refresh logic never reads or writes.
- [x] 1.2 Make `.pick_next_event()` arbitrate across the union of `proposals` and
      `action_proposals`, preserving the deterministic tie-break (time, then id).
- [x] 1.3 Carry an unambiguous marker on the picked event identifying it as engine-owned, so
      the action-handler lookup no longer depends on the `^\.action\.` string prefix.
      *Implemented as the `flux_source` / `flux_key` attributes, which are invisible to `$`
      access and therefore never surface in model code.*
- [x] 1.4 Retire a realized action from `action_proposals` before `refresh_rules()` is
      consulted. **Fixes D1.**
- [x] 1.5 Ensure `refresh_rules()` / `propose_events()` results only ever rewrite
      `proposals`, so pending actions survive both refresh modes. **Fixes D2.**
- [x] 1.6 Write newly proposed actions into `action_proposals` after refresh, preserving
      existing same-decision-point overwrite behavior.
- [x] 1.7 Preserve a user-facing identifier on realized action events for `refresh_rules()`
      and trajectory continuity, without leaking a dot-prefixed name. **Resolved:** a realized
      action carries **no** `process_id` at all. See "Action identity" below.

**Result.** `.action.` no longer appears anywhere in the package. Verified: D1 collapses from
7 replays to 1 realization; D2's action now fires at t=6 after surviving two intervening
events. Full suite run before and after the change produced byte-identical results — the
single `run_cohort_cluster` failure is a pre-existing PSOCK limitation (worker nodes cannot
see a `load_all`-ed package) and is unrelated.

**Follow-up resolved during implementation:** `dp_map` initially existed for reverse lookup
from synthetic process ids. Phase 2b gave it a new, explicit purpose: retrieving each
decision point's `on_pending_action` setting while pending actions are merged.

### Phase 2 — Namespace reservation  ✅ COMPLETE

- [x] 2.1 Reject process-id names matching `^\.` returned from `propose_events()`, with a
      clear error naming the offending id.
- [x] 2.2 Apply the same rejection to process ids returned from `refresh_rules()`.
- [x] 2.3 Confirm no existing fixture, test, or downstream model uses a dot-prefixed process
      id.
- [x] 2.4 Validate `DecisionPoint` id uniqueness in `load_model()`. The engine keys pending
      actions by decision point id, so duplicates would silently collapse into one slot.
      Pre-existing gap, surfaced by this work.

**Implementation.** A single shared helper, `.reject_reserved_process_ids(ids, source)`, is
called from both `.call_propose_events()` and `.call_refresh_rules()` after the
empty/missing check and before the duplicate check. The error names the offending id(s) and
states the rule.

**Verified.** Both callbacks reject `.action.dp` with the intended message; ordinary ids are
unaffected. Full suite output is identical to the Phase 1 baseline. A workspace-wide search
found no dot-prefixed process id in any subrepo or tutorial, so the reservation is not a
breaking change in practice.

### Phase 2b — Pending-action policy and termination reason  ✅ COMPLETE

Added after Phases 1–2, arising from open questions 1 and 4.

- [x] 2b.1 `DecisionPoint(on_pending_action = )` declares what happens when a policy proposes
      an action while that decision point's previous action is still pending:
      `"warn"` (default; replace and warn), `"replace"` (replace silently — the overt
      allowance), `"keep"` (discard the new proposal), `"error"` (stop). Declared on the
      `DecisionPoint` rather than the policy, matching `allowed_actions`, `action_handlers`,
      `condition`, and `audit`, and because superseding is a property of the decision point
      rather than of an individual proposal.
- [x] 2b.2 Engine honors the declared mode when merging new actions into `action_proposals`.
      Because the realized action is retired *before* refresh, a decision point re-proposing
      immediately after its own action fired is correctly **not** treated as a conflict — so
      the common pattern never warns.
- [x] 2b.3 `Engine$run()` output gains `stopped_by`: `"stop"`, `"max_time"`, `"max_events"`,
      or `"no_proposals"`. Previously the loop terminated silently on `max_events`, and
      `stop()` and `max_time` were indistinguishable internally (both returned `FALSE`).
- [x] 2b.4 Replaced the `utils::modifyList()` merge with an explicit loop. `utils` was not
      declared in `Imports`, so this also removes an undeclared dependency.

**Rejected:** general chain-cycle detection. Whether a chain terminates depends on evolving
state, so it is not decidable statically, and at runtime an infinite chain is
indistinguishable from a legitimately long simulation. `max_events` / `max_time` are the
correct backstops; `stopped_by` makes hitting them diagnosable, which addresses the whole
class of runaway conditions rather than one narrow case.

### Phase 3 — `last_event` plumbing (D3)  ✅ COMPLETE

- [x] 3.1 Add `last_event = NULL` to `.call_propose_events()`, injected via the existing
      formals guard (`if ("last_event" %in% fml)`).
- [x] 3.2 Leave `last_event` NULL for initial proposal generation.
- [x] 3.3 Pass the realized event from both the `"ALL"` and selective refresh branches.
- [x] 3.4 Confirm the realized event retains its `ActionEvent` class, `params`, `metadata`,
      and `decision_point_id` through `.pick_next_event()`.
- [x] 3.5 Verify `.validate_model_bundle()` does not constrain `propose_events()` formals.

**Verified.** `last_event` is NULL on the initial call and carries `event_type`,
`params$delay`, and `decision_point_id` on refresh. The motivating example works end to end:
an action carrying `params = list(delay = 30)` pushed the next proposal from t=4 to t=34 with
no transport state variable. A bundle not declaring `last_event` produced byte-identical
output to before the change.

**Bonus capability worth documenting:** initial generation and full `"ALL"` refresh were
previously indistinguishable — identical arguments, different situations. `last_event` now
disambiguates them.

| Call site | `process_ids` | `current_proposals` | `last_event` |
|---|---|---|---|
| Initial generation | `NULL` | `NULL` | `NULL` |
| Full `"ALL"` refresh | `NULL` | `NULL` | realized event |
| Selective refresh | the ids | full proposal set | realized event |

### Phase 4 — Tests  ✅ COMPLETE

New file: `subrepos/fluxCore/tests/testthat/test_v2_action_lifecycle.R` — 47 assertions.

- [x] 4.1 D1 regression — realized action appears exactly once under selective refresh.
- [x] 4.2 D2 regression — an action scheduled far in the future still fires after several
      intervening events under default `"ALL"` refresh.
- [x] 4.3 Action outcomes are identical under `"ALL"` and selective refresh.
- [x] 4.4 Two decision points firing on one event — both actions realize, in time order.
- [x] 4.5 Same decision point re-proposing before realization — covered by 4.13.
- [x] 4.6 Unrelated model proposals untouched during selective refresh.
- [x] 4.7 `last_event` is NULL on the initial call and fully populated (including `params`)
      on refresh.
- [x] 4.8 A parameterized action with a `NULL` handler reschedules a process from
      `last_event$params` alone, with no transport state variable.
- [x] 4.9 A `propose_events()` not declaring `last_event` runs unchanged.
- [x] 4.10 Dot-prefixed process ids error clearly from both callbacks.
- [x] 4.11 Chained decision points — a decision point triggering on an action type fires when
      that action realizes and proposes the next action.
- [x] 4.12 A chained action with a `NULL` handler and an undeclared `event_catalog` entry
      produces a clear error.
- [x] 4.13 `on_pending_action` — all four modes behave as declared; a decision point
      re-proposing after its own action fired does **not** warn.
- [x] 4.14 `stopped_by` reports each of `"stop"`, `"max_time"`, `"max_events"`,
      `"no_proposals"`.
- [x] 4.15 Duplicate `DecisionPoint` ids are rejected by `load_model()`.
- [x] 4.16 A realized action carries no `process_id`; a model process sharing a decision
      point's name does not collide.
- [x] 4.17 Full suite green with only the expected warnings and platform-dependent skips.

**Pre-patch verification (required by this plan).** The new file was run against the stashed,
unpatched `R/` directory. It produced 20+ failures, including every intended regression:
D1 (realized action retired), D2 under both refresh modes, refresh-strategy independence,
both decision points realizing, and the action-identity assertions — the last erroring with
`Event proposal for process_id '.action.mydp'`, confirming the leak the patch removes.
The regression tests are therefore known to detect the original defects rather than merely
passing.

**Notable finding.** Test 4.4 fails pre-patch: two decision points firing on one event did
*not* both realize, because `"ALL"` refresh destroyed the later action. This empirically
confirms that tutorial 03's "arbitration picks the one with the earliest `time_next`" claim
was accidentally true only because of D2 — see Phase 5a.5.

**Incidental fix made while writing tests.** `.validate_event()` reported action proposals as
`"Event proposal for process_id '<dp>'"`, which contradicts actions having no `process_id`.
It now takes a descriptive label and reports
`"Event proposal for the action from DecisionPoint('<id>')"`.

### Phase 5a — Tutorial 03 lifecycle corrections and provisional expansion

Current headings: Setup / The decision / Declaring a decision point / Writing policies (A, B)
/ Tweaking base model / Assembling / Running both / Comparing / Trajectory records / Using
condition / Multiple decision points per event cycle / Distribution / What records enable /
Summary.

- [x] 5a.1 Preserve the accepted canonical tutorial structure. Put the proposed complete,
      minimal decision → action → effect walkthrough in an explicitly provisional,
      unlinked companion tutorial instead.
- [x] 5a.2 The provisional companion layers the additional variations: repeated proposals
      and `on_pending_action`; alternative versus sequential decision points; a chained
      three-step workflow with the `event_catalog` and unbounded-chain sharp edges; and an
      action carrying `params` that reschedules a process without transport state.
- [x] 5a.3 The provisional companion states the lifecycle contract plainly and early: one
      action or none per policy call; one pending slot per decision point; independent slots
      across decision points; actions are ordinary events; pending actions are retained; and
      realized actions are retired automatically.
- [x] 5a.4 Replace the incorrect "enter a queue and arbitration picks the one with the
      earliest `time_next`" passage.
- [x] 5a.5 Re-verify the tiered-response example's narrative against actual output.
      **This required changing the example, not just the prose.** Post-fix both decision
      points' actions realize, so the emergency `decline` at `+0.001` was being undone by the
      routine `accept` at `+0.01` — the example had become a modeling bug. `dp_standard` now
      carries a complementary `condition` (`battery_pct >= 10`) so the two checkpoints are
      mutually exclusive. Verified empirically:
      without conditions the trace is `check, decline, accept`; with them it is
      `check, decline, check, decline`.
      The section now teaches the general rule: scheduling one action earlier does not cancel
      a later one, it only orders them — use `condition` when you want one response *instead
      of* another, and distinct offsets only when you want actions to *sequence*.
- [x] 5a.6 Do not document multi-action per decision point. The provisional chain continues
      to use one action per policy call.

### Phase 5b — Flow diagram  ✅ COMPLETE (as mermaid)

**Decision:** replaced the hand-authored PNG with an inline mermaid diagram rather than
re-authoring the image. Mermaid renders natively on GitHub, which is what
`render_for_github.R` targets, and the source now lives in the tutorial itself — so 5b.10 is
moot. No theme or colours applied, per user preference.

**Layout:** three horizontal bands rather than one long vertical chain, roughly 5 columns by
7 rows so it fits a laptop screen without scrolling. The banding also does pedagogical work:
band 1 is everything before the state changes, band 2 everything after — exactly the
distinction the old figure got wrong.

- [x] 5b.1 Trigger check moved ahead of `transition()` (pre-transition, raw event); only
      `condition` is post-transition.
- [x] 5b.2 `action_handler()` and `transition()` shown as alternatives.
- [x] 5b.3 Refresh is inside the loop; `propose_events()` no longer looks like one-time init.
- [x] 5b.4 `observe`/`stop` run on every event, not only when a decision point fires.
- [x] 5b.5 Audit path no longer flows into an ActionEvent.
- [x] 5b.6 Loop closes back to arbitration.
- [x] 5b.7 Terminal node added, labelled with `stopped_by`.
- [x] 5b.8 Both stores shown, plus retirement of the realized action.
- [x] 5b.9 Trajectory records shown on both the active and audit paths.
- [x] 5b.10 Moot — mermaid is its own source.

**Resolved:** the unreferenced PNG was deleted; the inline mermaid is the maintained source.

### Phase 5c — Tutorial 01 and rendering

- [x] 5c.1 Tutorial 01's two refresh principles now state that they govern the model's own
      processes only; policy-scheduled actions are engine-managed, never named in a refresh
      rule, and retired automatically. Also documents `last_event`, including the
      `NULL`-on-first-call idiom for telling initial setup apart from a mid-run refresh.
- [x] 5c.2 Re-render both tutorials to their `.md` counterparts via
      `tutorials/render_for_github.R`.
      Completed after committing, pushing, and installing fluxCore 2.1.0. The unchanged
      all-tutorial renderer completed successfully; the provisional companion was knitted
      separately with the same root and figure settings.

### Phase 6 — Metadata and landing

- [x] 6.1 `NEWS.md`: bug fix (replay under selective refresh); bug fix (pending action
      dropped under `"ALL"` — call out that this affected the default configuration); feature
      (optional `last_event`); note (leading-dot process ids now reserved).
- [x] 6.2 Bump `Version:` to 2.1.0 in `subrepos/fluxCore/DESCRIPTION`.
- [x] 6.3 Run `roxygen2::roxygenise()` if any roxygen blocks changed.
- [x] 6.4 `R CMD build` + `R CMD check --as-cran` clean.
- [x] 6.5 Commit on fluxCore `main`, push, update super-repo submodule pointer, push.
- [x] 6.6 Comment on issue #11 documenting the D2 discovery and the widened scope.
- [x] 6.7 Do **not** submit to CRAN yet.
- [x] 6.8 Ensure an initially empty proposal set returns
      `stopped_by = "no_proposals"`, with regression coverage.

---

## Action identity (resolves open question 2)

**A realized action has no `process_id`.** `process_id` is a model-process concept; an action
is not a model process. Assigning one to actions is the category error that produced
`.action.<dp_id>` in the first place. Actions are identified by `decision_point_id`, which
`ActionEvent()` already carries and the engine already auto-fills.

Consequently `is.null(event$process_id)` is a reliable marker that an event came from a
policy rather than a model process. Observed in the collision test, where a model process and
a decision point deliberately share the name `dp`:

```
refresh_rules saw process_id=dp    event_type=tick dp_id=NULL
refresh_rules saw process_id=NULL  event_type=act  dp_id=dp
```

**Prefix schemes were considered and rejected.** Auto-prefixing (`dispatch` → `EP.dispatch`)
reintroduces engine-invented names into user-visible fields — the leak Phase 1 removed — and
would require a translation layer so `refresh_rules()` could still return plain ids. A naming
convention (`EP_`/`AP_`) is unenforceable and pushes jargon onto model authors. Both add
vocabulary to solve a problem an existing field already solves.

Note that the collision was verified to be *functionally* harmless even before this change:
because `flux_source` is tracked separately from the id, retirement always targeted the
correct store. The defect was ambiguity in what the model could observe, not corruption.

---

## Relevant files

| File | Why |
|---|---|
| `subrepos/fluxCore/R/engine.R` | `Engine$run()` / `step_once()`, `.pick_next_event()`, `.call_propose_events()`, `.call_refresh_rules()`, `fired_decision_points()` |
| `subrepos/fluxCore/R/decision_points.R` | `ActionEvent()` (sets `event_type = action_type`, the chaining mechanism), `DecisionPoint()`, `dp_fires()` |
| `subrepos/fluxCore/R/Entity.R` | `update()` / `events`; confirms params are not retained in history |
| `subrepos/fluxCore/R/utils_internal.R` | `.validate_model_bundle()`, `.validate_event_time()` |
| `subrepos/fluxCore/tests/testthat/test_v2_stage2b.R` | Closest existing fixture to clone |
| `subrepos/fluxCore/DESCRIPTION`, `NEWS.md` | Version and changelog |
| `tutorials/src/01_core_engine_scaffold.Rmd` | Refresh principles |
| `tutorials/src/03_decisions_policy.Rmd` | Decision/action tutorial; diagram reference at L81 |
| `tutorials/figure/engine-loop-decision-point.png` | Removed; the corrected diagram is inline mermaid source |
| `tutorials/render_for_github.R` | Re-render step |

---

## Verification

1. Each regression test must fail against current `main` before the fix and pass after.
2. `devtools::test()` in `subrepos/fluxCore` — full suite green.
3. Re-run the reproduction script: `schedule` collapses from 7 rows to 1 (D1); the `+30`
   action fires under default refresh (D2).
4. A three-step chain (A → B → C) with meaningful delays completes — currently impossible
   because of D2.
5. `R CMD build` + `R CMD check --as-cran` with the local toolchain:
   `export PATH="$HOME/Library/TinyTeX/bin/universal-darwin:$PATH"`, RStudio's bundled
   pandoc, `~/.local/bin/tidy`. The prior "Insufficient package version" WARNING clears at
   2.1.0.
6. Re-render tutorials; confirm the tiered-response example's printed output matches the
   corrected narrative.
7. `tests_ecosystem/run_tier1_smoke.R` and `run_tier2_package_tests.R`.

---

## Open questions

1. ~~**Same-decision-point overwrite**~~ — **RESOLVED.** `DecisionPoint(on_pending_action = )`,
   default `"warn"`. See Phase 2b.
2. ~~**Realized action identifier**~~ — **RESOLVED.** Actions carry no `process_id`; they are
   identified by `decision_point_id`. See "Action identity" above.
3. ~~**Pending action visibility**~~ — **DEFERRED.** Pending actions stay fully invisible to
   model code for now. Revisit when a real domain model demands it.
4. ~~**Unbounded chains**~~ — **RESOLVED.** No cycle detection; `stopped_by` makes runaway
   termination diagnosable instead. See Phase 2b.

### Deferred to a future release

- **Pending-action visibility.** The motivating case is a policy that wants to know whether an
  intervention is already scheduled before proposing another. Note this is a **policy**
  concern, not a `propose_events()` one — so the natural surface is the policy signature or
  `observation_fn`, not the proposal callback. It also overlaps `on_pending_action`: a policy
  that can see pending actions could arbitrate for itself, so a future design should decide
  whether the declarative mode remains the primary mechanism or becomes a fallback. Do not
  build both without deciding which is authoritative.
- Multi-action per decision point (a policy returning a list of actions). Chained decision
  points cover the use case today.
- Per-proposal override of `on_pending_action` via an `ActionEvent` argument. Composes on top
  of the decision-point-level declaration if something ever demands it.
- Zero-time-advance chain detection (consecutive events at an identical timestamp). Cheap to
  add, but no demonstrated need.

---

## Reproduction script

Kept at `/tmp/flux_issue11_repro.R` during development. Regenerate with:

```r
suppressMessages(pkgload::load_all("subrepos/fluxCore", quiet = TRUE))

mk <- function(refresh_fn, action_delay) {
  schema <- list(
    variables = list(
      triggered = list(type = "binary", levels = c("0", "1"), default = FALSE,
                       coerce = as.logical,
                       validate = function(x) length(x) == 1L && is.logical(x))
    ),
    time_spec = time_spec(unit = "years"),
    event_catalog = c("trigger", "tick", "schedule"),
    decision_points = list(
      DecisionPoint(id = "dp", trigger = "trigger", allowed_actions = "schedule")
    )
  )
  bundle <- list(
    time_spec = time_spec(unit = "years"),
    event_catalog = c("trigger", "tick", "schedule"),
    propose_events = function(entity, process_ids = NULL, current_proposals = NULL) {
      all <- list(
        trigger_process = list(
          time_next = if (isTRUE(entity$current$triggered)) 1e6 else 1.0,
          event_type = "trigger"
        ),
        tick_process = list(time_next = entity$last_time + 2, event_type = "tick")
      )
      if (is.null(process_ids)) return(all)
      all[intersect(names(all), process_ids)]
    },
    transition = function(entity, event) {
      if (identical(event$event_type, "trigger")) return(list(triggered = TRUE))
      list()
    },
    stop = function(entity, event) FALSE,
    refresh_rules = refresh_fn
  )
  policy <- list(
    propose_action = function(decision_point, entity, sim_ctx, param_ctx) {
      ActionEvent("schedule", time_next = entity$last_time + action_delay,
                  params = list(delay_days = 30))
    }
  )
  engine <- load_model(schema = schema, bundle = bundle, policy = policy)
  engine$run(entity = Entity$new(schema = schema$variables), max_events = 8)
}

# D1: selective refresh, action at +0.1 -> expect exactly one "schedule"
mk(function(entity, last_event, changes) {
  if (identical(last_event$event_type, "schedule")) "tick_process" else "ALL"
}, 0.1)$events

# D2: default "ALL" refresh, action at +30 -> expect "schedule" to fire
mk(function(entity, last_event, changes) "ALL", 30)$events
```

---

## Progress log

| Date | Entry |
|---|---|
| 2026-08-20 | Analysis complete. D1, D2, D3 verified; D1 and D2 reproduced empirically against `main` @ `6cba830`. Plan approved. Phase 1 started. |
| 2026-08-20 | First D2 reproduction found to be invalid (action scheduled beyond the run horizon). Rebuilt and re-confirmed by before/after `git stash` comparison. |
| 2026-08-20 | **Phase 1 complete.** `action_proposals` is now a first-class engine-owned store. D1 and D2 both fixed and verified. Baseline and post-patch test runs identical — no regressions. Not yet committed. |
| 2026-08-20 | **Phase 2 complete.** Leading-dot process ids reserved via `.reject_reserved_process_ids()`, enforced in both `propose_events()` and `refresh_rules()`. Suite output unchanged from baseline. Not yet committed. |
| 2026-08-20 | Open question 2 resolved: realized actions carry no `process_id`; `decision_point_id` identifies them. Prefix schemes (EP*/AP*) considered and rejected. `DecisionPoint` id uniqueness now validated in `load_model()`. Suite unchanged from baseline. |
| 2026-08-20 | **Phase 2b complete.** `on_pending_action` added to `DecisionPoint` (resolves open question 1); `stopped_by` added to run output (resolves open question 4). All four modes and all four termination reasons verified. Suite unchanged from baseline. |
| 2026-08-20 | **Phase 3 complete.** `last_event` injected into `propose_events()` via the formals guard. Motivating example verified end to end with no transport state variable; undeclared bundles unaffected. Suite unchanged from baseline. Not yet committed. |
| 2026-08-20 | **Phase 4 complete.** `test_v2_action_lifecycle.R` added (47 assertions). Confirmed to produce 20+ failures against the unpatched `R/`, including every intended regression. Full suite green apart from the pre-existing cluster failure. `.validate_event()` message corrected for actions. Not yet committed. |
| 2026-08-20 | **Phase 5b + 5c.1 complete.** PNG flow diagram replaced with a corrected three-band mermaid diagram. Tutorial 03's queue passage rewritten and its tiered-response example fixed (complementary `condition`s) after verifying the old example would now undo its own override. Tutorial 01 refresh principles scoped to model-owned processes. Re-render still pending. |
| 2026-08-20 | **Canonical Tutorial 03 accepted; provisional expansion drafted.** The canonical structure was preserved, its remaining arbitration summary corrected, and its existing superseding behavior declared explicitly. A separate unlinked source/rendered pair holds the larger lifecycle walkthrough for later review. |
| 2026-08-20 | **Phase 6.1–6.4 and 6.8 complete.** Version and NEWS finalized, generated documentation updated, full tests green, README example executed successfully, and `R CMD check --as-cran` completed with `Status: OK`. fluxCore commit `96798db` was pushed and installed as version 2.1.0 before tutorial rendering. |
| 2026-08-20 | **Tutorial and ecosystem verification complete.** The unchanged all-tutorial renderer completed, the provisional companion knitted separately, canonical Tutorial 03 rendered without warnings, and ecosystem tiers 1 and 2 passed. A documentation-only README follow-up was pushed as `dff6fd6`; the preserved `.DS_Store` change remains uncommitted. |
| 2026-08-20 | **Issue #11 updated.** Posted a lifecycle-only summary covering the widened defect scope, implementation, and verification; no CRAN submission was made. |
| 2026-08-20 | **Phase 6 complete.** The super-repository landing includes the updated fluxCore pointer, canonical tutorial renders, the unlinked provisional source/rendered pair, and silent housekeeping cleanup. |
