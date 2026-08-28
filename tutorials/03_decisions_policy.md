In [Tutorial 02](02_cohort_forecast.md), couriers followed the same operational
rules: dispatch offers arrived, deliveries completed, and batteries drained.
Here we add choices. A dispatcher may accept or decline an offer, while a
safety rule may reduce a low-battery courier's load.

In flux, a **decision point** says when a policy may be consulted. The policy
may select an **action**, which enters the same irregular-time event calendar as
the model's other events. The action does not change the courier immediately.

By the end of this tutorial, you will be able to:

- declare an ordinary decision point and write its policy;
- distinguish policy selection, pending staging, event realization, and the
  action handler's state effect;
- control repeated offers when an earlier action is still pending;
- use two independent decisions that share a trigger; and
- coordinate several eligible decisions in one grouped policy consultation.

## Setup: a controlled extension of the delivery model


``` r
library(fluxCore)
source("tutorials/model/urban_delivery.R")
```

The stochastic delivery model is useful for forecasting, but fixed event times
make a new lifecycle easier to see. The helper below starts from
`delivery_bundle()` and changes only what this tutorial needs: dispatch offers
arrive at supplied times, each offer either opens or does not open an assignment,
and shift end remains a model event. The courier schema and delivery vocabulary
are unchanged.


``` r
controlled_delivery_bundle <- function(offer_times = 1,
                                       offer_open = TRUE,
                                       offered_payload_kg = 4,
                                       shift_end = 8) {
  bundle <- delivery_bundle(list(shift_length_hours = shift_end))
  offer_times <- sort(as.numeric(offer_times))

  bundle$propose_events <- function(entity, param_ctx = NULL,
                                    process_ids = NULL,
                                    current_proposals = NULL) {
    n_seen <- sum(entity$events$event_type == "dispatch_check", na.rm = TRUE)
    next_offer <- n_seen + 1L
    out <- list()

    if (next_offer <= length(offer_times) &&
        offer_times[[next_offer]] > entity$last_time) {
      out$dispatch <- list(
        time_next = offer_times[[next_offer]],
        event_type = "dispatch_check"
      )
    }

    out$end_shift <- list(
      time_next = shift_end,
      event_type = "end_shift"
    )

    if (is.null(process_ids)) return(out)
    out[intersect(as.character(process_ids), names(out))]
  }

  bundle$transition <- function(entity, event, param_ctx = NULL) {
    if (identical(event$event_type, "dispatch_check")) {
      if (isTRUE(offer_open)) {
        return(list(
          dispatch_mode = "assigned",
          payload_kg = offered_payload_kg
        ))
      }
      return(list(dispatch_mode = "idle", payload_kg = 0))
    }

    if (identical(event$event_type, "end_shift")) {
      return(list(dispatch_mode = "idle"))
    }

    NULL
  }

  bundle$stop <- function(entity, event, param_ctx = NULL) {
    identical(event$event_type, "end_shift")
  }

  bundle
}

fresh_courier <- function(id = "courier_A", battery_pct = 80) {
  Entity$new(
    id = id,
    init = list(
      battery_pct = battery_pct,
      route_zone = "urban",
      payload_kg = 0,
      dispatch_mode = "idle"
    ),
    schema = delivery_schema(),
    entity_type = "courier",
    time0 = 0
  )
}

dispatch_handlers <- list(
  confirm_dispatch = function(entity, event) {
    list(dispatch_mode = "in_transit")
  },
  decline_dispatch = function(entity, event) {
    list(dispatch_mode = "idle", payload_kg = 0)
  }
)
```

These are tutorial-local controls, not a second delivery model. Later you can
replace fixed offer times with the stochastic proposals from
`delivery_bundle()` without changing the decision contracts.

## One dispatch decision, from selection to effect

Suppose an offer arrives at hour 1. The transition marks the offer as assigned
and records its payload. At that checkpoint, the policy selects a decline action
for hour 1.5.


``` r
dispatch_response_dp <- DecisionPoint(
  id = "dispatch_response",
  trigger = "dispatch_check",
  allowed_actions = c("confirm_dispatch", "decline_dispatch"),
  action_handlers = dispatch_handlers,
  on_pending_action = "replace",
  label = "Respond to an open delivery offer"
)

dispatch_schema <- set_schema(
  vars = delivery_schema(),
  time_spec = time_spec(unit = "hours"),
  decision_points = list(dispatch_response_dp)
)

decline_policy <- function(decision_point, entity) {
  ActionEvent(
    action_type = "decline_dispatch",
    time_next = entity$last_time + 0.5,
    metadata = list(reason = "tutorial demonstration")
  )
}

dispatch_model <- load_model(
  schema = dispatch_schema,
  bundle = controlled_delivery_bundle(offer_times = 1),
  policy = decline_policy,
  trajectory = list(detail = "summary")
)
```

First stop immediately after the offer event. This lets us see the selected
future action before it has happened.


``` r
after_offer <- dispatch_model$run(
  fresh_courier("courier_after_offer"),
  max_events = 1
)

selected <- after_offer$trajectory_records[[1]]$selected_action

data.frame(
  offer_time = after_offer$trajectory_records[[1]]$t,
  state_after_offer = after_offer$entity$current$dispatch_mode,
  selected_action = selected$action_type,
  selected_for_time = selected$time_next,
  action_already_in_history = selected$action_type %in%
    after_offer$events$event_type
) |> kable()
```



| offer_time|state_after_offer |selected_action  | selected_for_time|action_already_in_history |
|----------:|:-----------------|:----------------|-----------------:|:-------------------------|
|          1|assigned          |decline_dispatch |               1.5|FALSE                     |



The policy has **selected** `decline_dispatch`. Core has validated and
**staged** it in the decision point's pending slot, where it can compete with
future model events. It is not yet in event history because selection is not
realization.

Now allow one more event to occur.


``` r
after_action <- dispatch_model$run(
  fresh_courier("courier_after_action"),
  max_events = 2,
  return_observations = TRUE
)

after_action$observations |>
  select(time, event_type, dispatch_mode, payload_kg) |>
  kable()
```



| time|event_type       |dispatch_mode | payload_kg|
|----:|:----------------|:-------------|----------:|
|  1.0|dispatch_check   |assigned      |          4|
|  1.5|decline_dispatch |idle          |          0|



The four ideas are distinct:

1. At hour 1, the policy **selects** `decline_dispatch`.
2. Core **stages** that future action in an engine-owned pending slot.
3. At hour 1.5, it wins timeline arbitration and is **realized** as an event.
4. Its handler takes **effect**, returning the courier to `idle` with no
   payload.

The trajectory row describes the decision at hour 1. Its `state_before` and
`state_after` bracket the triggering `dispatch_check` transition; they do not
bracket the later action handler.


``` r
trajectory_table(
  after_offer$trajectory_records,
  vars = c("dispatch_mode", "payload_kg")
) |> kable()
```



|run_id |entity_id           |  t|decision_point_id |grouped_decision_point_id |group_activation_id |trigger_event  |selected_action  |condition_met |dispatch_mode_before |dispatch_mode_after | payload_kg_before| payload_kg_after|
|:------|:-------------------|--:|:-----------------|:-------------------------|:-------------------|:--------------|:----------------|:-------------|:--------------------|:-------------------|-----------------:|----------------:|
|run_1  |courier_after_offer |  1|dispatch_response |NA                        |NA                  |dispatch_check |decline_dispatch |NA            |idle                 |assigned            |                 0|                4|



`selected_action` is therefore the policy's choice, not a promise that the
choice was retained or realized. Event history is the authoritative record of
what actually occurred. In this controlled one-decision example, the matching
action at hour 1.5 is unambiguous; more elaborate models may need richer
application-level identifiers for exact lineage.

## Conditions decide whether policy is consulted

A trigger answers “did an offer event occur?” A `condition` answers a separate
question using post-transition state: “does this courier require this decision
now?” Here the policy is consulted only when battery is below 25%.


``` r
critical_battery_dp <- DecisionPoint(
  id = "critical_dispatch_response",
  trigger = "dispatch_check",
  condition = function(entity) entity$current$battery_pct < 25,
  allowed_actions = "decline_dispatch",
  action_handlers = list(
    decline_dispatch = dispatch_handlers$decline_dispatch
  ),
  audit = TRUE,
  on_pending_action = "replace"
)

critical_schema <- set_schema(
  vars = delivery_schema(),
  time_spec = time_spec(unit = "hours"),
  decision_points = list(critical_battery_dp)
)

critical_policy <- function(decision_point, entity) {
  ActionEvent("decline_dispatch", entity$last_time + 0.5)
}

critical_model <- load_model(
  schema = critical_schema,
  bundle = controlled_delivery_bundle(offer_times = 1),
  policy = critical_policy,
  trajectory = list(detail = "summary")
)

condition_run <- function(id, battery) {
  out <- critical_model$run(
    fresh_courier(id, battery_pct = battery),
    max_events = 1
  )
  tab <- trajectory_table(out$trajectory_records, vars = "battery_pct")
  tab$starting_battery <- battery
  tab
}

bind_rows(
  condition_run("healthy_battery", 80),
  condition_run("low_battery", 15)
) |>
  select(entity_id, starting_battery, condition_met, selected_action) |>
  kable()
```



|entity_id       | starting_battery|condition_met |selected_action  |
|:---------------|----------------:|:-------------|:----------------|
|healthy_battery |               80|FALSE         |NA               |
|low_battery     |               15|TRUE          |decline_dispatch |



With `audit = TRUE`, a vetoed visit still produces a trajectory row with
`condition_met = FALSE` and no selected action. Without audit, the healthy
visit would produce no decision row. An absent condition is simply treated as
eligible whenever the trigger fires.

## Repeated offers while an action is pending

Pending actions live separately from model proposals. A refresh can replace
the model's next dispatch proposal without erasing a policy action that is
still waiting.

This matters when two offers arrive at hours 1 and 2, while each policy call
selects a decline three hours later. The first and second selections are for
hours 4 and 5. A decision point can hold only one pending action, so
`on_pending_action` declares what the second selection means.

`warn` is the default mode. The examples spell out every mode so their intent
is visible in the code.


``` r
run_pending_mode <- function(mode) {
  selected_times <- numeric()
  warnings_seen <- character()
  run_error <- NULL

  dp <- DecisionPoint(
    id = "dispatch_response",
    trigger = "dispatch_check",
    allowed_actions = "decline_dispatch",
    action_handlers = list(
      decline_dispatch = dispatch_handlers$decline_dispatch
    ),
    on_pending_action = mode
  )

  schema <- set_schema(
    vars = delivery_schema(),
    time_spec = time_spec(unit = "hours"),
    decision_points = list(dp)
  )

  policy <- function(decision_point, entity) {
    action_time <- entity$last_time + 3
    selected_times <<- c(selected_times, action_time)
    ActionEvent("decline_dispatch", action_time)
  }

  model <- load_model(
    schema = schema,
    bundle = controlled_delivery_bundle(offer_times = c(1, 2)),
    policy = policy,
    trajectory = list(detail = "summary")
  )

  courier <- fresh_courier(paste0("courier_", mode))
  out <- tryCatch(
    withCallingHandlers(
      model$run(courier, max_events = 10),
      warning = function(w) {
        warnings_seen <<- c(warnings_seen, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      run_error <<- conditionMessage(e)
      NULL
    }
  )

  action_rows <- courier$events$event_type == "decline_dispatch"
  realized_time <- if (any(action_rows)) {
    courier$events$time[action_rows][[1]]
  } else {
    NA_real_
  }

  data.frame(
    mode = mode,
    selected_times = paste(selected_times, collapse = ", "),
    realized_time = realized_time,
    warnings = length(warnings_seen),
    errored = !is.null(run_error),
    last_committed_event = tail(courier$events$event_type, 1)
  )
}

bind_rows(lapply(
  c("keep", "replace", "warn", "error"),
  run_pending_mode
)) |> kable()
```



|mode    |selected_times | realized_time| warnings|errored |last_committed_event |
|:-------|:--------------|-------------:|--------:|:-------|:--------------------|
|keep    |4, 5           |             4|        0|FALSE   |end_shift            |
|replace |4, 5           |             5|        0|FALSE   |end_shift            |
|warn    |4, 5           |             5|        1|FALSE   |end_shift            |
|error   |4, 5           |            NA|        0|TRUE    |dispatch_check       |



The modes make the modeler's intent explicit:

- `keep` retains the hour-4 action and discards the new hour-5 selection;
- `replace` silently stages the hour-5 selection instead;
- `warn` stages the replacement and reports it; and
- `error` stops rather than choosing between them.

Notice that `keep` still realizes the first action even though the model's
dispatch proposal was refreshed after both offers. Also notice that the
`error` row ends on the second `dispatch_check`: that trigger event and its
transition had already occurred before the pending conflict was discovered.
flux reports the failure, but does not pretend that earlier simulation work
never happened.

## Two ordinary decisions can share one trigger

Now give a low-battery courier two distinct questions at the same
`dispatch_check`:

- should the offer be confirmed? and
- should the payload be reduced for safety?

These remain **ordinary** decision points. Each condition is checked, each
policy call is separate, and each decision owns its own pending slot.


``` r
ordinary_dispatch_response <- DecisionPoint(
  id = "dispatch_response",
  trigger = "dispatch_check",
  condition = function(entity) entity$current$dispatch_mode == "assigned",
  allowed_actions = "confirm_dispatch",
  action_handlers = list(
    confirm_dispatch = dispatch_handlers$confirm_dispatch
  ),
  on_pending_action = "replace"
)

ordinary_battery_safety <- DecisionPoint(
  id = "battery_safety",
  trigger = "dispatch_check",
  condition = function(entity) {
    entity$current$dispatch_mode == "assigned" &&
      entity$current$battery_pct < 30
  },
  allowed_actions = "shed_payload",
  action_handlers = list(
    shed_payload = function(entity, event) {
      list(payload_kg = entity$current$payload_kg / 2)
    }
  ),
  on_pending_action = "replace"
)

ordinary_shared_schema <- set_schema(
  vars = delivery_schema(),
  time_spec = time_spec(unit = "hours"),
  decision_points = list(
    ordinary_dispatch_response,
    ordinary_battery_safety
  )
)

ordinary_shared_policy <- function(decision_point, entity) {
  if (identical(decision_point$id, "battery_safety")) {
    return(ActionEvent("shed_payload", entity$last_time + 0.25))
  }
  ActionEvent("confirm_dispatch", entity$last_time + 0.5)
}

ordinary_shared_model <- load_model(
  schema = ordinary_shared_schema,
  bundle = controlled_delivery_bundle(offer_times = 1),
  policy = ordinary_shared_policy,
  trajectory = list(detail = "summary")
)

ordinary_shared_out <- ordinary_shared_model$run(
  fresh_courier("courier_two_ordinary", battery_pct = 15),
  max_events = 10,
  return_observations = TRUE
)

trajectory_table(ordinary_shared_out$trajectory_records) |>
  select(t, decision_point_id, condition_met, selected_action) |>
  kable()
```



|  t|decision_point_id |condition_met |selected_action  |
|--:|:-----------------|:-------------|:----------------|
|  1|dispatch_response |TRUE          |confirm_dispatch |
|  1|battery_safety    |TRUE          |shed_payload     |



Both actions later enter event history. Their times order their realization;
neither action cancels the other.


``` r
ordinary_shared_out$observations |>
  filter(event_type %in% c("shed_payload", "confirm_dispatch")) |>
  select(time, event_type, dispatch_mode, payload_kg, battery_pct) |>
  kable()
```



| time|event_type       |dispatch_mode | payload_kg| battery_pct|
|----:|:----------------|:-------------|----------:|-----------:|
| 1.25|shed_payload     |assigned      |          2|          15|
| 1.50|confirm_dispatch |in_transit    |          2|          15|



This pattern is appropriate when the questions truly are independent. A
slightly earlier action time is sequencing, not priority: it does not make a
later pending action disappear.

## Grouped decisions coordinate one policy consultation

Sometimes those two questions must be answered together. A grouped decision
point owns the shared trigger and refers to ordinary leaf decision points that
retain their conditions, allowed actions, handlers, audit settings, and pending
slots.

Here the leaves are **group-only**, so their direct trigger is explicitly
`NULL`. The group `post_dispatch_review` fires on `dispatch_check`.


``` r
group_dispatch_response <- DecisionPoint(
  id = "dispatch_response",
  trigger = NULL,
  condition = function(entity) entity$current$dispatch_mode == "assigned",
  allowed_actions = c("confirm_dispatch", "decline_dispatch"),
  action_handlers = dispatch_handlers,
  audit = TRUE,
  on_pending_action = "replace"
)

group_battery_safety <- DecisionPoint(
  id = "battery_safety",
  trigger = NULL,
  condition = function(entity) {
    entity$current$dispatch_mode == "assigned" &&
      entity$current$battery_pct < 30
  },
  allowed_actions = "shed_payload",
  action_handlers = list(
    shed_payload = function(entity, event) {
      list(payload_kg = entity$current$payload_kg / 2)
    }
  ),
  audit = TRUE,
  on_pending_action = "replace"
)

post_dispatch_review <- GroupedDecisionPoint(
  id = "post_dispatch_review",
  trigger = "dispatch_check",
  members = c("dispatch_response", "battery_safety"),
  label = "Coordinate offer response and battery safety"
)

grouped_delivery_schema <- set_schema(
  vars = delivery_schema(),
  time_spec = time_spec(unit = "hours"),
  decision_points = list(
    group_dispatch_response,
    group_battery_safety
  ),
  decision_groups = list(post_dispatch_review)
)
```

The lifecycle is intentionally narrow:

1. `dispatch_check` fires the group.
2. The delivery transition is applied once.
3. Core evaluates member conditions on that post-transition courier state.
4. If at least one member is eligible, Core supplies the exact named list to
   one `policy$propose_plan()` call.
5. The policy returns one complete `DecisionPlan`, naming every eligible member
   with an `ActionEvent` or explicit `NULL`.
6. Core preflights every selection and pending-mode outcome, then commits the
   resolved pending store once. `NULL` and `keep` can leave a member's slot
   unchanged; newly staged or replaced actions later arbitrate and realize
   independently.

The function below runs controlled scientific scenarios and records exactly
what the policy received. In the fourth scenario, the policy deliberately
selects no new battery-safety action.


``` r
run_grouped_delivery <- function(label, offer_open, battery_pct,
                                 safety_selection = TRUE) {
  policy_trace <- new.env(parent = emptyenv())
  policy_trace$calls <- 0L
  policy_trace$eligible_ids <- character()
  policy_trace$plan <- NULL

  policy <- list(
    propose_plan = function(grouped_decision_point,
                            eligible_decision_points,
                            entity,
                            sim_ctx,
                            param_ctx) {
      policy_trace$calls <- policy_trace$calls + 1L
      policy_trace$eligible_ids <- names(eligible_decision_points)

      selections <- setNames(
        vector("list", length(eligible_decision_points)),
        names(eligible_decision_points)
      )

      if ("dispatch_response" %in% names(selections)) {
        selections["dispatch_response"] <- list(ActionEvent(
          "confirm_dispatch",
          entity$last_time + 0.5
        ))
      }

      if ("battery_safety" %in% names(selections)) {
        if (isTRUE(safety_selection)) {
          selections["battery_safety"] <- list(ActionEvent(
            "shed_payload",
            entity$last_time + 0.25
          ))
        } else {
          # Single-bracket replacement preserves an explicit NULL list entry.
          selections["battery_safety"] <- list(NULL)
        }
      }

      plan <- DecisionPlan(
        selections = selections,
        metadata = list(strategy = "post-dispatch review v1")
      )
      policy_trace$plan <- plan
      plan
    }
  )

  model <- load_model(
    schema = grouped_delivery_schema,
    bundle = controlled_delivery_bundle(
      offer_times = 1,
      offer_open = offer_open
    ),
    policy = policy,
    trajectory = list(detail = "summary")
  )

  out <- model$run(
    fresh_courier(paste0("courier_", label), battery_pct = battery_pct),
    max_events = 10,
    return_observations = TRUE
  )

  records <- out$trajectory_records
  by_member <- setNames(records, vapply(
    records,
    function(record) record$decision_point_id,
    character(1)
  ))

  condition_value <- function(member_id) {
    isTRUE(by_member[[member_id]]$condition_met)
  }

  selection_text <- if (is.null(policy_trace$plan)) {
    "(policy skipped)"
  } else {
    paste(vapply(names(policy_trace$plan$selections), function(member_id) {
      selected <- policy_trace$plan$selections[[member_id]]
      value <- if (is.null(selected)) "NULL" else selected$action_type
      paste0(member_id, " = ", value)
    }, character(1)), collapse = "; ")
  }

  summary <- data.frame(
    scenario = label,
    trigger = "dispatch_check @ 1",
    post_transition_offer = if (offer_open) "open" else "none",
    post_transition_battery = battery_pct,
    dispatch_response_condition = condition_value("dispatch_response"),
    battery_safety_condition = condition_value("battery_safety"),
    eligible_ids = if (policy_trace$calls == 0L) {
      "(none; policy skipped)"
    } else {
      paste(policy_trace$eligible_ids, collapse = ", ")
    },
    policy_calls = policy_trace$calls,
    selections = selection_text,
    stringsAsFactors = FALSE
  )

  list(summary = summary, out = out, policy_trace = policy_trace)
}

grouped_runs <- list(
  open_healthy = run_grouped_delivery(
    "open_healthy", offer_open = TRUE, battery_pct = 80
  ),
  open_low = run_grouped_delivery(
    "open_low", offer_open = TRUE, battery_pct = 15
  ),
  no_offer_healthy = run_grouped_delivery(
    "no_offer_healthy", offer_open = FALSE, battery_pct = 80
  ),
  open_low_explicit_null = run_grouped_delivery(
    "open_low_explicit_null", offer_open = TRUE, battery_pct = 15,
    safety_selection = FALSE
  )
)

grouped_summary <- bind_rows(lapply(grouped_runs, `[[`, "summary"))

grouped_summary |>
  transmute(
    scenario,
    trigger,
    post_transition_state = paste0(
      "offer = ", post_transition_offer,
      "; battery = ", post_transition_battery
    ),
    condition_results = paste0(
      "dispatch_response = ", dispatch_response_condition,
      "; battery_safety = ", battery_safety_condition
    ),
    eligible_ids
  ) |>
  kable()
```



|scenario               |trigger            |post_transition_state      |condition_results                                 |eligible_ids                      |
|:----------------------|:------------------|:--------------------------|:-------------------------------------------------|:---------------------------------|
|open_healthy           |dispatch_check @ 1 |offer = open; battery = 80 |dispatch_response = TRUE; battery_safety = FALSE  |dispatch_response                 |
|open_low               |dispatch_check @ 1 |offer = open; battery = 15 |dispatch_response = TRUE; battery_safety = TRUE   |dispatch_response, battery_safety |
|no_offer_healthy       |dispatch_check @ 1 |offer = none; battery = 80 |dispatch_response = FALSE; battery_safety = FALSE |(none; policy skipped)            |
|open_low_explicit_null |dispatch_check @ 1 |offer = open; battery = 15 |dispatch_response = TRUE; battery_safety = TRUE   |dispatch_response, battery_safety |



``` r

grouped_summary |>
  select(scenario, policy_calls, selections) |>
  kable()
```



|scenario               | policy_calls|selections                                                          |
|:----------------------|------------:|:-------------------------------------------------------------------|
|open_healthy           |            1|dispatch_response = confirm_dispatch                                |
|open_low               |            1|dispatch_response = confirm_dispatch; battery_safety = shed_payload |
|no_offer_healthy       |            0|(policy skipped)                                                    |
|open_low_explicit_null |            1|dispatch_response = confirm_dispatch; battery_safety = NULL         |



The policy never decides eligibility. Core supplies the eligible leaf objects,
in the group's declared member order. In the three main scenarios:

- an open offer with healthy battery makes only `dispatch_response` eligible;
- an open offer with low battery makes both leaves eligible, so one plan must
  answer both questions; and
- no open offer with healthy battery makes neither leaf eligible, so Core does
  not call `propose_plan()`.

The explicit-`NULL` variant still names `battery_safety` in a complete plan. It
means “this eligible question was considered, but no new action was selected.”
It is different from omitting the member, which makes a grouped plan invalid.

### One activation, visible in raw and tabular records

The low-battery activation emits one leaf row per eligible member. Raw records
retain both the group identity and one deterministic run-local activation id.
They also retain the plan's opaque audit metadata.


``` r
low_records <- grouped_runs$open_low$out$trajectory_records

data.frame(
  decision_point_id = vapply(low_records, `[[`, character(1),
                             "decision_point_id"),
  grouped_decision_point_id = vapply(low_records, `[[`, character(1),
                                     "grouped_decision_point_id"),
  group_activation_id = vapply(low_records, `[[`, character(1),
                               "group_activation_id"),
  plan_strategy = vapply(low_records, function(record) {
    record$decision_plan_metadata$strategy
  }, character(1))
) |> kable()
```



|decision_point_id |grouped_decision_point_id |group_activation_id |plan_strategy           |
|:-----------------|:-------------------------|:-------------------|:-----------------------|
|dispatch_response |post_dispatch_review      |group_activation_1  |post-dispatch review v1 |
|battery_safety    |post_dispatch_review      |group_activation_1  |post-dispatch review v1 |



`trajectory_table()` exposes the two compact identity columns, while arbitrary
plan metadata remains in raw records.


``` r
trajectory_table(low_records) |>
  select(decision_point_id, grouped_decision_point_id,
         group_activation_id, condition_met, selected_action) |>
  kable()
```



|decision_point_id |grouped_decision_point_id |group_activation_id |condition_met |selected_action  |
|:-----------------|:-------------------------|:-------------------|:-------------|:----------------|
|dispatch_response |post_dispatch_review      |group_activation_1  |TRUE          |confirm_dispatch |
|battery_safety    |post_dispatch_review      |group_activation_1  |TRUE          |shed_payload     |



The id connects the leaf rows to this one firing; it is not a durable cross-run
identifier. Audited ineligible members share the activation id too. That is why
the zero-eligible scenario can be audited without inventing a synthetic parent
row.

### Coordinated selection is not joint realization

In this low-battery run, both selections resolved to new pending actions in the
plan's one commit. They remain separate actions on the event calendar.


``` r
grouped_runs$open_low$out$observations |>
  filter(event_type %in% c("shed_payload", "confirm_dispatch")) |>
  select(time, event_type, dispatch_mode, payload_kg, battery_pct) |>
  kable()
```



| time|event_type       |dispatch_mode | payload_kg| battery_pct|
|----:|:----------------|:-------------|----------:|-----------:|
| 1.25|shed_payload     |assigned      |          2|          15|
| 1.50|confirm_dispatch |in_transit    |          2|          15|



At hour 1.25, `shed_payload` halves the four-kilogram offer. At hour 1.5,
`confirm_dispatch` moves the courier into transit. A **composite action** would
instead be one action event with one handler that applies both state changes at
one realization time. A grouped plan coordinates policy selection, complete
preflight, and one pending-store commit. Some resolved slots may remain
unchanged because of explicit `NULL` or `keep`; later action realization and
effects are not atomic.

The explicit-`NULL` run makes this boundary especially visible: both questions
were eligible and recorded under one activation, but only
`confirm_dispatch` entered event history.


``` r
null_out <- grouped_runs$open_low_explicit_null$out

list(
  decisions = trajectory_table(null_out$trajectory_records) |>
    select(decision_point_id, condition_met, selected_action),
  realized_actions = null_out$events |>
    filter(event_type %in% c("shed_payload", "confirm_dispatch")) |>
    select(time, event_type)
)
#> $decisions
#>   decision_point_id condition_met  selected_action
#> 1 dispatch_response          TRUE confirm_dispatch
#> 2    battery_safety          TRUE             <NA>
#>
#> $realized_actions
#>   time       event_type
#> 1  1.5 confirm_dispatch
```

## Advanced contract notes

Most applied policies need only the patterns above. The following boundaries
matter when you build reusable policy tooling or diagnose a failed run.

### Independent selection inside an explicit grouped adapter

A group always requires `policy$propose_plan()`; Core does not silently fall
back to ordinary calls. If joint reasoning is unnecessary, policy code can
make that choice explicit with a small adapter. Applied to the delivery leaves,
the pattern is:


``` r
per_member_plan <- function(propose_action) {
  function(grouped_decision_point, eligible_decision_points,
           entity, sim_ctx, param_ctx) {
    selections <- lapply(eligible_decision_points, function(decision_point) {
      propose_action(decision_point, entity, sim_ctx, param_ctx)
    })
    DecisionPlan(selections)
  }
}

delivery_policy <- list(
  propose_plan = per_member_plan(delivery_leaf_policy)
)
```

The named eligible list determines the complete plan shape, and the adapter
calls leaves in that declared order. Complete preflight and one grouped
pending-store commit still happen after it returns, with each leaf's pending
mode determining whether its slot changes.

### Provenance, diagnostics, and partial progress

- `ActionEvent(decision_point_id = NULL)` is the usual policy return. Core fills
  the firing leaf id as provenance. An explicitly supplied exact match is
  accepted; a mismatch errors rather than redirecting the action.
- Intentional outcomes are callback-specific: a condition may return `FALSE`;
  an ordinary policy may return `NULL`; and an action handler may return `NULL`
  to realize the action with no state patch. A grouped policy must instead
  return a complete `DecisionPlan`, using explicit `NULL` member entries as
  needed; `propose_plan()` itself never returns `NULL`.
- Thrown condition, policy, and action-handler errors stop the run with callback
  context. If a domain-specific fallback is scientifically justified, catch the
  error inside that callback and deliberately return the appropriate valid
  result above.
- An ordinary non-`ActionEvent` or disallowed action type is warned about and
  ignored. Provenance conflicts and thrown callbacks error. Grouped plan
  validation is stricter still: one invalid member rejects the complete plan
  before any of that plan's pending slots change.
- The triggering event and transition occur before post-transition conditions,
  policy calls, and pending-conflict checks. A later failure does not roll them
  back, nor does it roll back earlier independent ordinary or grouped work.
- A grouped `warn` replacement produces one plan-level warning naming all
  affected members. If warnings are promoted to errors, the plan has not yet
  changed any pending slot.

### Reproducibility is not automatic causal alignment

A `RuntimeContext(seed = ...)` can replay a configured direct run, and cohort
execution assigns reproducible streams at its outer boundary. Two policies can
nevertheless consume random numbers differently after their behavior diverges.
Using the same seed does not by itself keep every later draw paired, nor does it
turn a policy comparison into a causal estimate. Design explicit common-random-
number or experimental comparisons when that scientific claim matters.

## Summary

| Concept | Practical meaning |
|---|---|
| `DecisionPoint()` | Declares a leaf decision, including its trigger or explicit group-only `NULL`, condition, allowed actions, handlers, audit choice, and pending mode |
| Policy selection | The policy chooses an `ActionEvent` or, for an ordinary decision, intentionally returns `NULL` |
| Pending resolution | Core applies the leaf's pending mode; the resulting retained or newly staged action occupies at most one engine-owned slot and survives model-proposal refreshes |
| Realization and effect | The pending action must first win timeline arbitration; event history records realization and its handler applies the state patch |
| `condition` and `audit` | Eligibility uses post-transition state; audit optionally records vetoed visits |
| Shared ordinary trigger | Several leaves may fire independently from one event, with separate policy calls and pending slots |
| `GroupedDecisionPoint()` | One shared trigger coordinates eligibility across referenced leaves and opens one plan consultation |
| `DecisionPlan()` | A complete named answer for every eligible leaf; each value is an `ActionEvent` or explicit `NULL` |
| Group identity | `grouped_decision_point_id` and run-local `group_activation_id` connect leaf audit rows from one firing |
| Grouped atomicity | Complete preflight precedes one pending-store commit; `NULL` or `keep` may leave slots unchanged, and later action realization and effects remain independent |

**Next:** [04_data_preparation_and_model_training.md](04_data_preparation_and_model_training.md) —
generate synthetic operational logs and prepare them into train/test/validation
format with `fluxPrepare`.
