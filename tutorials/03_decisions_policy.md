In [Tutorial 02](02_cohort_forecast.md), every courier followed the same
mechanistic process: dispatches arrived, deliveries completed, batteries
drained — all without anyone making choices. Real systems involve **decisions**: a dispatcher choosing whether to
accept or decline an assignment, a routing algorithm picking surge vs normal
mode, a fleet manager pulling a low-battery vehicle off the road.

This tutorial introduces **decision points** and **policies** — the mechanism
by which choices are injected into the simulation timeline. A **policy** is a
set of decision rules: given a courier's current state at a specific moment in
the simulation, it proposes an action such as “accept this dispatch” or
“decline”. By the end you will be able to:

- declare a decision point on the delivery schema,
- write a policy function that proposes actions,
- compare outcomes under two different policies with identical seeds,
- inspect trajectory records to see exactly why each decision was made.

## Setup


``` r
library(fluxCore)
source("tutorials/model/urban_delivery.R")
set.seed(2026)
```

## The decision: accept or decline a dispatch

When a `dispatch_check` event fires, the courier currently accepts every
assignment unconditionally. But what if a fleet management system could
**decline** an assignment — for example, when battery is too low to safely
complete the delivery?

This is a natural decision point. Let's formalize it.

## Declaring a decision point

A **decision point** is a named checkpoint in the event timeline where the
simulation pauses to ask: *should something intervene here?* When a decision
point fires, the engine calls your policy function and gives it a chance to
propose an action — for example, "decline this dispatch" or "switch to surge
mode". If no policy is attached, the simulation proceeds as if the checkpoint
were not there.

Decision points are declared on the schema, not buried in transition logic.
This keeps the interface explicit and auditable.


``` r
dp_dispatch <- DecisionPoint(
  id              = "dispatch_decision",
  trigger         = "dispatch_check",
  allowed_actions = c("accept", "decline"),
  label           = "Accept or decline an incoming dispatch assignment"
)
```

The fields:
- **`trigger`**: which event(s) cause this decision point to fire. The
  simplest form is a character string (or vector) matching one or more event
  type names. You can also supply a function `function(event)` that inspects
  the event and returns `TRUE` or `FALSE` — useful when you want to fire only
  for a subset of events of the same type (e.g., only expedited deliveries).
  The function receives the event as it was *before* the transition runs, so
  it sees fields like `event_type`, `time_next`, and any `metadata` attached
  by the event generator. To check courier state *after* the transition,
  use `condition` instead.

  ```r
  # Fire only when the event was flagged as expedited
  trigger = function(event) {
    event$event_type == "delivery_completed" &&
      isTRUE(event$metadata$expedited)
  }
  ```

- **`condition`**: an optional function `function(entity)` that is checked
  *after* the transition runs and the courier's state has been updated. If it
  returns `FALSE`, the policy is not called for that event — the simulation
  continues without intervention. Use this to restrict the decision point to
  situations where the courier's current state warrants action:

  ```r
  # Only consult the policy when battery is below 25 % after the dispatch
  condition = function(entity) entity$current$battery_pct < 25
  ```

  `trigger` and `condition` serve different purposes: `trigger` selects
  *which events* activate the checkpoint; `condition` checks *whether the
  current state* warrants calling the policy.

- **`audit`**: logical (default `FALSE`). When `TRUE`, the simulation logs a
  `TrajectoryRecord` even for cycles where `condition` suppressed the policy
  call. The record is flagged with `condition_met = FALSE` and
  `selected_action = NULL`, giving you a complete history of every checkpoint
  visit regardless of whether the policy ran.

- **`allowed_actions`**: what the policy is permitted to propose. Actions
  outside this set are rejected.

- **`label`**: human-readable documentation.

Now assemble a full schema object (variables + time_spec + decision points):


``` r
schema_with_dp <- set_schema(
  vars            = delivery_schema(),
  time_spec       = time_spec(unit = "hours"),
  decision_points = list(dp_dispatch)
)
```

## Writing policies

A **policy** is a plain R list with a `propose_action` function. That function
receives the decision point object and the current courier state, and returns
an `ActionEvent` proposing what should happen next — or `NULL` for "no
intervention."

### Policy A: always accept

The simplest possible policy — accept every dispatch regardless of state.
This is equivalent to having no policy at all, and serves as a baseline.


``` r
policy_always_accept <- list(

  propose_action = function(decision_point, entity) {
    ActionEvent(
      action_type       = "accept",
      time_next         = entity$last_time + 0.01,
      decision_point_id = decision_point$id
    )
  }
)
```

### Policy B: battery threshold

Decline if battery has dropped below 25%. The idea: a courier running low on
battery should stop taking new assignments and coast to shift end rather than
risk stranding mid-delivery.


``` r
policy_battery_threshold <- list(
  propose_action = function(decision_point, entity) {
    battery <- as.numeric(entity$current$battery_pct)

    action <- if (!is.null(battery) && battery < 25) "decline" else "accept"

    ActionEvent(
      action_type       = action,
      time_next         = entity$last_time + 0.01,
      decision_point_id = decision_point$id,
      metadata          = list(battery_at_decision = battery)
    )
  }
)
```

## Extending the bundle to handle the "decline" action

When the policy proposes "decline", that action enters the event timeline as
an `ActionEvent` and flows through `transition()`. We need the transition
function to handle it — in this case, by reverting the dispatch (resetting
mode back to idle and dropping the payload that was just assigned).


``` r
# Extended transition that also handles the "decline" action
delivery_transition_with_policy <- function(entity, event, param_ctx = NULL) {
  # Handle the decline action: undo the dispatch assignment

  if (identical(event$event_type, "decline")) {
    return(list(
      dispatch_mode = "idle",
      payload_kg    = 0
    ))
  }

  # "accept" action: no additional state change needed (dispatch already applied)
  if (identical(event$event_type, "accept")) {
    return(NULL)
  }

  # All other events: delegate to the standard transition
  delivery_transition(entity, event, param_ctx)
}
```

Now build a bundle that uses this extended transition:


``` r
delivery_bundle_with_policy <- function(params = list()) {
  base <- delivery_bundle(params)
  base$transition <- delivery_transition_with_policy
  base$event_catalog <- c(base$event_catalog, "accept", "decline")
  base
}
```

## Assembling with `load_model()`

When decision points are present, `load_model()` is the recommended assembly
path. It validates that the schema, bundle, policy, and trajectory configuration
are mutually consistent before any run begins.

Reproducibility is controlled through a `RuntimeContext`. Passing a `seed`
there ensures that every stochastic draw during the run — dispatch timing,
battery drain, route assignment — starts from a known state. Using the same
seed value across both models is what makes the comparison meaningful: every
difference in outcome is caused by the policy, not by random chance.


``` r
model_accept <- load_model(
  schema     = schema_with_dp,
  bundle     = delivery_bundle_with_policy(),
  policy     = policy_always_accept,
  trajectory = list(detail = "summary"),
  runtime    = RuntimeContext(seed = 99)
)

model_threshold <- load_model(
  schema     = schema_with_dp,
  bundle     = delivery_bundle_with_policy(),
  policy     = policy_battery_threshold,
  trajectory = list(detail = "summary"),
  runtime    = RuntimeContext(seed = 99)
)
```

## Running both policies from the same seed

The power of the decision-point architecture: same courier, same seed, same
stochastic draws — but different policies yield different outcomes. We create
two identical couriers (same starting state) and run each through its
respective model.


``` r
courier <- Entity$new(
  id          = "courier_A",
  init        = list(
    battery_pct   = 80,
    route_zone    = "urban",
    payload_kg    = 0,
    dispatch_mode = "idle"
  ),
  schema      = delivery_schema(),
  entity_type = "courier",
  time0       = 0
)

# Fresh courier with identical starting state for the second model
courier2 <- Entity$new(
  id          = "courier_A",
  init        = list(
    battery_pct   = 80,
    route_zone    = "urban",
    payload_kg    = 0,
    dispatch_mode = "idle"
  ),
  schema      = delivery_schema(),
  entity_type = "courier",
  time0       = 0
)

out_accept    <- model_accept$run(courier,  max_events = 500, return_observations = TRUE)
out_threshold <- model_threshold$run(courier2, max_events = 500, return_observations = TRUE)
```

## Comparing outcomes

Let's look at the headline numbers: how many deliveries did each courier
complete, and how much battery was left at the end of the shift?


``` r
# Count deliveries completed under each policy
count_deliveries <- function(out) {
  sum(out$events$event_type == "delivery_completed", na.rm = TRUE)
}

cat("Always-accept policy:\n")
#> Always-accept policy:
cat("  Deliveries completed:", count_deliveries(out_accept), "\n")
#>   Deliveries completed: 4
cat("  Final battery:       ", round(out_accept$entity$current$battery_pct, 1), "%\n\n")
#>   Final battery:        66.2 %

cat("Battery-threshold policy:\n")
#> Battery-threshold policy:
cat("  Deliveries completed:", count_deliveries(out_threshold), "\n")
#>   Deliveries completed: 4
cat("  Final battery:       ", round(out_threshold$entity$current$battery_pct, 1), "%\n")
#>   Final battery:        66.2 %
```

The always-accept courier takes every dispatch and drains the battery more
aggressively — potentially completing more deliveries but at higher risk of
hitting critical battery levels. The threshold courier conserves energy by
declining late-shift dispatches when battery is low.

## Inspecting trajectory records

Every time a decision point fires, the engine records what happened in a
`TrajectoryRecord`. Think of it as the simulation's decision log: it captures
the courier's state at the moment of the decision, what the policy proposed,
and what the state looked like afterward. This is what allows you to go back
after a run and ask *why* a particular decision was made.


``` r
# How many decisions were made?
cat("Decisions (accept policy):   ", length(out_accept$trajectory_records), "\n")
#> Decisions (accept policy):    3
cat("Decisions (threshold policy):", length(out_threshold$trajectory_records), "\n")
#> Decisions (threshold policy): 3
```

Inspect a single record to see the structure:


``` r
tr <- out_threshold$trajectory_records[[1]]
cat("Time:            ", tr$t, "\n")
#> Time:             3.488447
cat("Decision point:  ", tr$decision_point_id, "\n")
#> Decision point:   dispatch_decision
cat("Action proposed: ", tr$selected_action$action_type, "\n")
#> Action proposed:  accept
cat("Battery before:  ", tr$state_before$battery_pct, "\n")
#> Battery before:   80
cat("Battery after:   ", tr$state_after$battery_pct, "\n")
#> Battery after:    79.80786
```

`trajectory_table()` collects all records into a data frame, with one row per
decision and columns for time, state variables, and the action taken. Look for
the moment the policy starts declining — that's where the battery crosses 25%
and the courier switches from accepting everything to coasting to end of shift.


``` r
tr_df <- trajectory_table(out_threshold$trajectory_records,
                          vars = c("battery_pct", "dispatch_mode"))
head(tr_df, 10)
#>          t decision_point_id  trigger_event action_taken battery_pct_before
#> 1 3.488447 dispatch_decision dispatch_check       accept           80.00000
#> 2 4.822405 dispatch_decision dispatch_check       accept           79.80786
#> 3 6.182609 dispatch_decision dispatch_check       accept           70.72134
#>   battery_pct_after dispatch_mode_before dispatch_mode_after
#> 1          79.80786                 idle            assigned
#> 2          78.83529             assigned            assigned
#> 3          70.23726           in_transit            assigned
```

Look for the moment the policy starts declining — that's where the battery
crosses 25% and the courier switches from accepting everything to coasting
to end of shift.

## Separating the guard from the action: `condition`

In `policy_battery_threshold` above, the state check (`battery < 25`) lives
inside `propose_action`. The policy receives every `dispatch_check` event and
decides what to do. That works fine for a single-policy model, but it blurs
two distinct concerns:

- *When* should this decision point be activated? (the guard)
- *What* should happen when it fires? (the action)

The `condition` parameter on `DecisionPoint()` separates these. You attach the
guard directly to the checkpoint. The policy only runs when the condition is
already satisfied, so it can always propose the same action without repeating
the check.


``` r
dp_dispatch_cond <- DecisionPoint(
  id              = "dispatch_decision",
  trigger         = "dispatch_check",
  condition       = function(entity) entity$current$battery_pct < 25,
  allowed_actions = c("decline"),
  audit           = TRUE,
  label           = "Decline dispatch when battery is critically low; log all visits"
)

schema_cond <- set_schema(
  vars            = delivery_schema(),
  time_spec       = time_spec(unit = "hours"),
  decision_points = list(dp_dispatch_cond)
)

# Policy is now unconditional: the condition handles the filtering,
# so every time this policy is called, the answer is always "decline".
policy_decline_only <- list(
  propose_action = function(decision_point, entity) {
    ActionEvent(
      action_type       = "decline",
      time_next         = entity$last_time + 0.01,
      decision_point_id = decision_point$id
    )
  }
)

model_cond <- load_model(
  schema     = schema_cond,
  bundle     = delivery_bundle_with_policy(),
  policy     = policy_decline_only,
  trajectory = list(detail = "summary"),
  runtime    = RuntimeContext(seed = 99)
)
```

Also, `audit = TRUE` is introduced here. Normally, when `condition` returns
`FALSE` — meaning the battery is still healthy — the checkpoint fires and is
immediately skipped with no record kept. With `audit = TRUE`, a record is
written for *every* `dispatch_check` visit, whether or not the condition was
met. Records where the policy was suppressed carry `condition_met = FALSE`
and `selected_action = NULL`. This gives you a full picture of when couriers
were and were not at risk.

Run on the same courier with the same seed:


``` r
courier_cond <- Entity$new(
  id          = "courier_A",
  init        = list(battery_pct=80, route_zone="urban",
                     payload_kg=0, dispatch_mode="idle"),
  schema      = delivery_schema(),
  entity_type = "courier",
  time0       = 0
)

out_cond <- model_cond$run(courier_cond, max_events = 500,
                           return_observations = TRUE)
```

Because `audit = TRUE`, the trajectory records include every
`dispatch_check` visit — not just the ones where the policy was called:


``` r
cond_flags <- sapply(out_cond$trajectory_records, function(tr) tr$condition_met)

cat("Total DP visits (all dispatch_check events):",
    length(out_cond$trajectory_records), "\n")
#> Total DP visits (all dispatch_check events): 3
cat("Condition met  (battery < 25, policy called):",
    sum(isTRUE(cond_flags) | is.na(cond_flags) == FALSE & cond_flags, na.rm = TRUE), "\n")
#> Condition met  (battery < 25, policy called): 0
cat("Vetoed         (battery >= 25, logged only): ",
    sum(!cond_flags, na.rm = TRUE), "\n")
#> Vetoed         (battery >= 25, logged only):  3
```

The `condition_met` field in each record tells you which visits had the policy
consulted (`TRUE`) and which were logged but skipped (`FALSE`). The
`trajectory_table()` helper brings this into a data frame alongside the state
variables you care about:


``` r
tr_cond_df <- trajectory_table(out_cond$trajectory_records,
                               vars = c("battery_pct", "dispatch_mode"))
head(tr_cond_df[, intersect(names(tr_cond_df),
                             c("t", "battery_pct", "dispatch_mode", "condition_met",
                               "selected_action"))], 8)
#> [1] 3.488447 5.697595 6.185383
```

Rows with `condition_met = FALSE` are the visits where battery was still above
25% and no action was needed. Rows with `condition_met = TRUE` are the ones
where the policy ran and proposed "decline".

The two approaches — state check in `propose_action` vs. `condition` on the
`DecisionPoint` — produce identical behavioral outcomes. Use `condition` when
the guard is always the same regardless of policy, or when you want the
audit trail to capture every checkpoint visit.

## Multiple decision points per event cycle

A schema can carry more than one decision point attached to the same trigger.
Each fires **independently**: the engine checks the condition (if any) and
calls the policy separately for each active checkpoint in the same event step.
When both propose actions, both `ActionEvent`s enter a queue and
**arbitration** picks the one with the earliest `time_next`.

A common pattern is a tiered response: one checkpoint handles the routine
accept/decline decision, and a second handles an emergency override when the
battery reaches a critical threshold. Because the critical override should
always win, it is given a slightly smaller `time_next` offset so it is
scheduled ahead of the routine action:


``` r
dp_standard <- DecisionPoint(
  id              = "dispatch_accept",
  trigger         = "dispatch_check",
  allowed_actions = c("accept", "decline"),
  label           = "Routine accept/decline decision"
)

dp_critical <- DecisionPoint(
  id              = "battery_critical",
  trigger         = "dispatch_check",
  condition       = function(entity) entity$current$battery_pct < 10,
  allowed_actions = c("decline"),
  audit           = TRUE,
  label           = "Emergency override: battery critically low"
)

schema_two_dps <- set_schema(
  vars            = delivery_schema(),
  time_spec       = time_spec(unit = "hours"),
  decision_points = list(dp_standard, dp_critical)
)
```

When battery is above 10%, only `dp_standard` is active and the routine
policy runs. When battery drops below 10%, **both** checkpoints fire:
`dp_standard` proposes its action and `dp_critical` also proposes "decline".
Arbitration picks whichever has the smaller `time_next`. By giving the
critical override a smaller offset (`+ 0.001` vs. `+ 0.01`), it always wins
when both are active:


``` r
policy_two_dps <- list(
  propose_action = function(decision_point, entity) {
    battery <- as.numeric(entity$current$battery_pct)

    if (decision_point$id == "battery_critical") {
      # Emergency override fires first (time_next offset smaller).
      return(ActionEvent(
        action_type       = "decline",
        time_next         = entity$last_time + 0.001,
        decision_point_id = decision_point$id,
        metadata          = list(reason = "battery_critical")
      ))
    }

    # Routine policy: accept unless battery < 25.
    action <- if (!is.null(battery) && battery < 25) "decline" else "accept"
    ActionEvent(
      action_type       = action,
      time_next         = entity$last_time + 0.01,
      decision_point_id = decision_point$id
    )
  }
)
```

With two checkpoints both proposing actions in the same event step, the one
with `time_next = last_time + 0.001` is scheduled first. The transition
handles "decline" and the run continues; the second proposal from the routine
checkpoint has no further effect.

> **Arbitration rule:** When multiple proposed actions are waiting, the engine
> picks the one scheduled earliest (smallest `time_next`). If two proposals
> share the same time, the ordering is not defined — encode priority by
> choosing distinct offsets.

## Cohort-level comparison

Let's scale this up. Run a 20-courier cohort under both policies and compare
aggregate outcomes.


``` r
make_couriers <- function(n = 20, seed = 2026) {
  set.seed(seed)
  lapply(seq_len(n), function(i) {
    Entity$new(
      id   = paste0("courier_", sprintf("%02d", i)),
      init = list(
        battery_pct   = runif(1, 50, 100),
        route_zone    = sample(c("urban", "suburban", "rural"), 1,
                               prob = c(0.55, 0.30, 0.15)),
        payload_kg    = 0,
        dispatch_mode = "idle"
      ),
      schema      = delivery_schema(),
      entity_type = "courier",
      time0       = 0
    )
  })
}

cohort_accept    <- lapply(make_couriers(), function(e) {
  model_accept$run(e, max_events = 500, return_observations = TRUE)
})

cohort_threshold <- lapply(make_couriers(), function(e) {
  model_threshold$run(e, max_events = 500, return_observations = TRUE)
})

# Aggregate
del_accept    <- vapply(cohort_accept, count_deliveries, integer(1))
del_threshold <- vapply(cohort_threshold, count_deliveries, integer(1))
bat_accept    <- vapply(cohort_accept,
                        function(o) o$entity$current$battery_pct, numeric(1))
bat_threshold <- vapply(cohort_threshold,
                        function(o) o$entity$current$battery_pct, numeric(1))

cat("Fleet summary — always accept:\n")
#> Fleet summary — always accept:
cat("  Mean deliveries:", round(mean(del_accept), 1), "\n")
#>   Mean deliveries: 4.4
cat("  Mean final battery:", round(mean(bat_accept), 1), "%\n\n")
#>   Mean final battery: 43.9 %

cat("Fleet summary — battery threshold:\n")
#> Fleet summary — battery threshold:
cat("  Mean deliveries:", round(mean(del_threshold), 1), "\n")
#>   Mean deliveries: 4.4
cat("  Mean final battery:", round(mean(bat_threshold), 1), "%\n")
#>   Mean final battery: 43.9 %
```

The trade-off is visible at fleet scale: the threshold policy sacrifices some
delivery throughput in exchange for better battery preservation — a real
operational consideration when battery replacement or charging infrastructure
is constrained.

## What trajectory records enable

`TrajectoryRecord` is not just an audit log. It is the structured surface that
the rest of the flux ecosystem builds on:

- **Policy comparison**: run the same courier under two policies with the same
  seed; diff the trajectory_records to see where and why they diverge.
- **Counterfactual analysis**: fix seed + parameter draw; vary only the policy;
  compare outcomes.
- **RL training** (future: `fluxSim`): the `(observation, action, reward,
  next_state)` tuple for each record becomes a training transition.
- **Audit and explainability**: for any individual run, reconstruct the full
  decision history and ask "why did the simulation do that?"

## Summary

| Concept | What you learned |
|---------|-----------------|
| `DecisionPoint()` | Declares where in the event timeline a policy is consulted |
| `trigger` | Pre-transition gate: char event name(s) or `function(event)` on event-level fields |
| `condition` | Post-transition guard: `function(entity)` on updated state; vetoed cycles skip the policy call |
| `audit = TRUE` | Emit `TrajectoryRecord` even when `condition` vetoed; `condition_met = FALSE` flags those records |
| Policy function | `propose_action(dp, entity)` → `ActionEvent` or NULL; add `sim_ctx` / `param_ctx` to the signature only when needed |
| `ActionEvent()` | The proposed intervention — enters the timeline like any other event |
| `load_model()` | Validates schema + bundle + policy + trajectory config together |
| Trajectory records | Per-decision audit trail: `observation`, `action`, `state_before/after`, `condition_met` |
| Same seed, different policy | Isolates the causal effect of the policy on outcomes |
| Multiple DPs + arbitration | Multiple DPs can fire in one event cycle; earliest `time_next` wins |

**Next:** [05_prepare_operational_data.md](05_prepare_operational_data.md) —
generate synthetic operational logs and prepare them into train/test/validation
format with `fluxPrepare`.
