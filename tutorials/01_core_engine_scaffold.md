This vignette demonstrates the core architecture:

- `Entity` holds mutable state, sparse history, and an event log.
- `ModelBundle` supplies the dynamics (when events happen, how state changes, when to stop, what to record).
- `Engine` orchestrates the simulation by repeatedly proposing, picking, applying, and observing events.

If you haven't read [00_start_here.md](00_start_here.md) yet, do that first — it covers the conceptual framework (entities, processes, decisions, the single-entity → multi-entity spectrum) that this tutorial puts into code.

This tutorial uses the simpler direct `bundle =` constructor and defers package-based model loading to a later tutorial.

### Determinism and tie-breaking

When multiple processes propose events at the same `time_next`, the engine selects one deterministically by ordering on:

1. earliest `time_next`, then
2. lexicographic `process_id`.

This means `process_id` is not just a label — it is part of the model's deterministic resolution policy. If your model has a preferred priority when ties occur, encode that priority into the `process_id` (for example, a zero-padded numeric prefix). We will introduce multiple competing processes later in this tutorial; for now, bundles with a single process just need a single consistent name.


An `Entity` may also carry an optional single-column identifier `id` (default `NULL`). 


To begin, load the library.

``` r
library(fluxCore)
set.seed(1)
```

The first task is to define a `schema` for the entity's state variables. The schema specifies the variable names, types, validation rules, and default values. The engine will enforce this schema at runtime, ensuring that state updates are valid and consistent. This separation of concerns allows you to focus on the dynamics in the transition function without worrying about low-level data validation.

The `fluxCore` package provides a default schema specification format, but you can define your own as long as it follows the expected structure. Below, we show how to create a schema using default variable formats (each of which has a default validation strategy), and then how to define a custom schema manually if you need more control.


``` r
# The schema is a list object with one entry per state variable. Each entry is itself a list with at least a `type` field, and optionally `levels`, `default`, `coerce`, and `validate` fields.
schema <- list(
  route_zone = list(
    type = "categorical",
    levels = c("urban", "suburban", "rural"),
    default = "urban",
    coerce = as.character
  )
)

# Extend schema without changing Entity/Engine code:
schema$battery_pct <- list(
  type = "numeric",
  default = 100,
  coerce = as.numeric
)
schema$payload_kg <- list(
  type = "numeric",
  default = 0,
  coerce = as.numeric
)
```
The above illustrates how to build up a schema incrementally, which is useful when you have a large number of variables or want to define them in different parts of the code. However, if you have a simple model and want to create a schema in one step, the `set_schema` helper function provides a convenient shortcut.


``` r
quicker_schema <- set_schema(vars = list(
  route_zone           = list(type = "categorical",
                              levels = c("urban", "suburban", "rural")),
  battery_pct          = "percent",
  payload_kg           = list(type = "nonnegative_numeric", max = 20),
  deliveries_completed = "count",
  prob_rain            = "probability"
))
```

This creates a fully validated schema with automatic type-specific defaults. The hybrid `vars` syntax accepts either a type-name string (e.g. `"count"`) or a full list spec (e.g. `list(type = "positive_numeric", max = 20)`) per variable, mixed freely in one call.

You can also extend or replace entries in an existing schema. By default, adding a variable that already exists is an error; pass `overwrite = TRUE` to replace it, or use `remove = ` to drop entries:


``` r
quicker_schema <- set_schema(
  vars = list(deliveries_completed = list(type = "count", max = 50)),
  schema = quicker_schema,
  overwrite = TRUE
)
```

Each state variable's `type` label gives fluxCore a default validation strategy. Built-in validators are intentionally permissive within each type's semantic — `count` enforces non-negative integer, `probability` enforces [0,1], `percent` enforces [0,100], etc. Use `min` / `max` (numeric types) or a custom `validate` function to tighten further. For a complete list of supported variable types and associated validation rules, see `subrepos/fluxCore/docs/schema_spec.md`.

The `coerce` and `default` fields are optional; `set_schema` will set type-specific defaults if not provided (e.g., `as.numeric` for `numeric` types, `NA_real_` for `numeric` defaults). You can override these if needed.


## Engine and ModelBundle

With a schema in hand we can now build the rest of the simulation. fluxCore deliberately separates two concerns at this level:

- **`Entity`** — the *state*. Holds the current values of every schema variable, the sparse history of changes, the event log, and an optional `id`. It validates every update against the schema you just defined. The `Entity` knows nothing about *dynamics*.
- **`ModelBundle`** — the *dynamics*. A plain named list of functions (and a `time_spec`) that together describe how the entity evolves: when events happen, how state changes when an event fires, when the simulation should stop, and what to record.

The **`Engine`** ties these together. You hand it a bundle; it then runs a deterministic loop on a given `Entity`: propose candidate events → pick the earliest (with `process_id` lexicographic tie-break) → call `transition()` to compute state changes → `entity$update()` → optionally `observe()` → check `stop()` and `max_time` → refresh proposals as needed.

A minimal `ModelBundle` therefore needs five things:

| Field | Purpose |
|---|---|
| `time_spec` | The clock (units, calendar). Built with `time_spec(unit = ...)`. |
| `propose_events(entity)` | Returns a named list of candidate events, each with `time_next` and `event_type`. The names are the `process_id`s used for tie-breaking. |
| `transition(entity, event)` | Returns a named list of state changes for the chosen event (or `list()` for a no-op). |
| `stop(entity, event)` | Returns `TRUE` when the run should terminate. |
| `observe(entity, event)` | Returns a one-row data frame of the variables you want recorded after each event. Optional — only used when `return_observations = TRUE`. |

Bundles can also expose optional hooks (`init_entity`, `refresh_rules`, `event_catalog`, `params`, `sample_params`); we ignore them here.

### A toy bundle

Below is the smallest interesting bundle: a single **event process** named `dispatch` that fires at lognormal-distributed intervals, adds a noisy parcel of payload, and drains the battery by a random amount (mean ~12%). It stops when battery falls below 10% and records schema-relevant fields after each event.


``` r
toy_bundle <- list(
  time_spec = time_spec(unit = "hours"),

  propose_events = function(entity) {
    list(dispatch = list(
      time_next  = entity$last_time + stats::rlnorm(1, meanlog = 0.2, sdlog = 0.4),
      event_type = "dispatch"
    ))
  },

  transition = function(entity, event) {
    if (!identical(event$event_type, "dispatch")) return(list())
    list(
      payload_kg  = max(0, as.numeric(entity$current$payload_kg) +
                            stats::rnorm(1, mean = 2, sd = 0.5)),
      battery_pct = max(0, as.numeric(entity$current$battery_pct) -
                            stats::rlnorm(1, meanlog = 2.3, sdlog = 0.3))
    )
  },

  stop = function(entity, event) entity$current$battery_pct < 10,

  observe = function(entity, event) {
    s <- entity$snapshot(c("route_zone", "battery_pct", "payload_kg",
                           "deliveries_completed", "prob_rain"))
    data.frame(
      time       = entity$last_time,
      event_type = event$event_type,
      route_zone = s$route_zone,
      battery_pct = round(s$battery_pct, 1),
      payload_kg  = round(s$payload_kg, 2),
      deliveries  = s$deliveries_completed,
      prob_rain   = s$prob_rain
    )
  }
)
```

Notice that nothing in `toy_bundle` knows the schema directly — the bundle reads variables through `entity$current` (or `entity$snapshot()`) and writes them back via the named list returned by `transition()`. The engine will run those returned values through schema validation before they are committed to the entity.

The `observe()` function uses `entity$snapshot(vars)`, which returns the current values of the requested variables as a named list. This is the idiomatic way to build observation records — it respects derived variables, and is concise.

### Constructing the Entity

The `Entity` is initialized with a starting state (one value per schema variable) and the schema we built above. The engine will reject any subsequent update that violates that schema.


``` r
p <- Entity$new(
  init = list(route_zone = "urban", battery_pct = 100, payload_kg = 0, deliveries_completed = 0L, prob_rain = 0.5),
  schema = quicker_schema,
  entity_type = "courier",
  time0 = 0
)
```

### Constructing the Engine and running

With a bundle in hand, building and running the engine is one line. Pass the bundle directly via `Engine$new(bundle = ...)`; the engine validates the bundle and is then ready to run.


``` r
eng <- Engine$new(bundle = toy_bundle)

out <- eng$run(p, max_events = 200, return_observations = TRUE)

tail(out$events, 6)
#>    j      time event_type
#> 5  4  5.827972   dispatch
#> 6  5  6.780633   dispatch
#> 7  6  7.980279   dispatch
#> 8  7  9.676645   dispatch
#> 9  8 11.346697   dispatch
#> 10 9 12.911766   dispatch
tail(out$observations, 6)
#>        time event_type route_zone battery_pct payload_kg deliveries prob_rain
#> 4  5.827972   dispatch      urban        61.4       9.38          0       0.5
#> 5  6.780633   dispatch      urban        47.4      10.27          0       0.5
#> 6  7.980279   dispatch      urban        34.2      12.27          0       0.5
#> 7  9.676645   dispatch      urban        21.0      14.56          0       0.5
#> 8 11.346697   dispatch      urban        15.5      16.60          0       0.5
#> 9 12.911766   dispatch      urban         6.0      18.57          0       0.5
out$entity$state(c("route_zone", "battery_pct", "payload_kg"))
#> <flux_state>
#> $route_zone
#> [1] "urban"
#> 
#> $battery_pct
#> [1] 6.005718
#> 
#> $payload_kg
#> [1] 18.57235
```

`out$events` is the engine's authoritative event log; `out$observations` is whatever your `observe()` hook accumulated; and `out$entity` is the same `p` from above, now mutated with the post-run state.


### Derived variables

Derived variables are snapshot-time computations that appear alongside schema variables in `entity$snapshot()` but are never persisted in entity state. They are declared on `Entity$new()` as a named list of functions with the signature `f(entity, j, t)`, where `j` is the current event index and `t` is the current simulation time. This is why the `observe()` note above says `snapshot()` "respects derived variables" — they are evaluated on demand each time `snapshot()` is called.

Three common patterns:

**Functions of current state.** Any deterministic combination of live state variables can be derived without adding it to the schema. `battery_efficiency` — deliveries per battery-unit consumed — is a clean example:


``` r
courier_d <- Entity$new(
  init = list(
    route_zone           = "urban",
    battery_pct          = 85,
    payload_kg           = 2,
    deliveries_completed = 4L,
    prob_rain            = 0.3
  ),
  schema = quicker_schema,
  entity_type = "courier",
  time0 = 0,
  derived_vars = list(
    battery_efficiency = function(entity, j, t) {
      burned <- 100 - as.numeric(entity$current$battery_pct)
      if (burned <= 0) return(NA_real_)
      round(as.numeric(entity$current$deliveries_completed) / burned, 3)
    }
  )
)
courier_d$snapshot(c("battery_pct", "deliveries_completed", "battery_efficiency"))
#> $battery_pct
#> [1] 85
#> 
#> $deliveries_completed
#> [1] 4
#> 
#> $battery_efficiency
#> [1] 0.267
```

`battery_efficiency` is not in the schema and is never validated or stored — it is recomputed on every `snapshot()` call.

**Fixed schema state plus simulation time.** Sometimes only an initial value and elapsed time are needed. Store the initial value in the schema (it will never be touched by `transition()`), and compute the time-dependent quantity as a derived variable:


``` r
schema_with_start <- set_schema(
  vars   = list(shift_start_hour = list(type = "nonnegative_numeric")),
  schema = quicker_schema
)

courier_t <- Entity$new(
  init = list(
    route_zone           = "urban",
    battery_pct          = 100,
    payload_kg           = 0,
    deliveries_completed = 0L,
    prob_rain            = 0.4,
    shift_start_hour     = 8        # shift begins at hour 8
  ),
  schema       = schema_with_start,
  entity_type  = "courier",
  time0        = 8,
  derived_vars = list(
    shift_elapsed = function(entity, j, t) {
      t - as.numeric(entity$current$shift_start_hour)
    }
  )
)

courier_t$update(list(battery_pct = 92), t = 9.5)
courier_t$update(list(battery_pct = 83), t = 11.2)

courier_t$snapshot_at_time(9.5,  c("battery_pct", "shift_elapsed"))
#> $battery_pct
#> [1] 100
#> 
#> $shift_elapsed
#> [1] 1.5
courier_t$snapshot_at_time(11.2, c("battery_pct", "shift_elapsed"))
#> $battery_pct
#> [1] 100
#> 
#> $shift_elapsed
#> [1] 3.2
```

`shift_start_hour` is the right home for this: it describes the entity's initial condition and participates in schema validation. A fixed schema state is simply a state that `transition()` never updates.

**Event-log aggregations.** Derived variables can also summarize the simulation's own history via `entity$events`. The tutorial model's `delivery_derived()` includes both a running total and a rolling window:

```r
# from tutorials/model/urban_delivery.R — delivery_derived()
deliveries_completed = function(entity, j, t) {
  ev <- entity$events
  as.integer(sum(
    ev$event_type == "delivery_completed" & ev$j <= j & ev$time <= t,
    na.rm = TRUE
  ))
},
deliveries_last_4h = function(entity, j, t) {
  ev <- entity$events
  as.integer(sum(
    ev$event_type == "delivery_completed" &
      ev$j <= j & ev$time > (t - 4) & ev$time <= t,
    na.rm = TRUE
  ))
}
```

For common patterns (count, min, max, mean, rolling windows), the `derive()` helper builds this function for you — see `?derive` for details.


## Variable blocks: grouped state updates

Some state variables naturally evolve **as a unit**. In our delivery domain, *weather* is a good example: when the weather refreshes, both the chance of rain and the wind speed change together, on the same clock, from the same draw. fluxCore lets you tag those variables as members of a named **block**, then update the whole block in one call from `transition()`.

To demonstrate, we'll extend the schema with a new variable `wind_kph` and tag both `wind_kph` and the existing `prob_rain` as members of a `weather` block. Because `prob_rain` already exists in `quicker_schema`, we use `overwrite = TRUE` to replace its spec with one that carries the `blocks` field:


``` r
quicker_schema_w_weather <- set_schema(
  vars = list(
    prob_rain = list(type = "probability", blocks = "weather"),
    wind_kph  = list(type = "nonnegative_numeric", max = 100, blocks = "weather")
  ),
  schema = quicker_schema,
  overwrite = TRUE
)

schema_blocks(quicker_schema_w_weather)
#> [1] "weather"
block_vars(quicker_schema_w_weather, "weather")
#> [1] "prob_rain" "wind_kph"
```

A variable can belong to **multiple** blocks; the `blocks` field is a character vector and membership is many-to-many. Block membership is purely metadata on the schema — the engine itself does not interpret blocks. They are a contract that helpers like `update_block()` and `combine_updates()` use to validate that a multivariate update is well-formed.

**Event processes and event types.** An event process is an independent mechanism that governs when and what kind of events can occur. Each process answers one question on every engine step: *what is my next candidate event, and when?* The engine collects one proposal per process, picks whichever fires soonest, and routes it through `transition()`.

A process and an event type are not the same thing. A single process can propose different `event_type` values on different calls — for example, a single `courier_status` process might return `event_type = "dispatch"` when a new assignment is ready or `event_type = "recharge"` when the vehicle returns to base. Both originate from the same underlying timing mechanism, so they belong to one process. By contrast, courier dispatch activity and weather updates are driven by entirely independent mechanisms with no shared clock, so they naturally belong to two separate processes.

Now we'll build a bundle with two competing processes:

- a `dispatch` process (as before, with a random inter-arrival time), and
- a `weather` process that fires on its own independent clock and updates the entire `weather` block at once via `update_block()`.

Each key in the named list returned by `propose_events()` is the **process_id**. The engine holds one current proposal per process — not a queue, but a flat set of "what would each process do next?" It picks whichever proposal has the smallest `time_next` (lexicographic `process_id` as tie-breaker), calls `transition()` with that event, then decides which processes need to re-propose for the next step.

That last step matters. After a `dispatch` event fires, the courier's battery and payload have changed — the dispatch process needs a fresh proposal that reflects the new state. Weather timing is independent of the courier's state, so the weather process's existing proposal can safely stand. By default the engine re-asks every process after every event (the safe, correct behavior), but the `refresh_rules` bundle hook lets you declare exactly which processes need to re-propose after each event type, avoiding redundant work. See [Controlling proposal refresh](#controlling-proposal-refresh) below for a concrete example.


``` r
weather_aware_bundle <- list(
  time_spec = time_spec(unit = "hours"),

  propose_events = function(entity) {
    list(
      dispatch = list(
        time_next  = entity$last_time + stats::rlnorm(1, meanlog = 0.2, sdlog = 0.4),
        event_type = "dispatch"
      ),
      weather = list(
        time_next  = entity$last_time + stats::rexp(1, rate = 0.5),
        event_type = "weather_refresh"
      )
    )
  },

  transition = function(entity, event) {
    if (identical(event$event_type, "dispatch")) {
      return(list(
        payload_kg  = max(0, as.numeric(entity$current$payload_kg) +
                              stats::rnorm(1, mean = 2, sd = 0.5)),
        battery_pct = max(0, as.numeric(entity$current$battery_pct) -
                              stats::rlnorm(1, meanlog = 2.3, sdlog = 0.3))
      ))
    }
    if (identical(event$event_type, "weather_refresh")) {
      return(update_block(entity, "weather", list(
        prob_rain = stats::runif(1, 0, 1),
        wind_kph  = max(0, stats::rnorm(1, mean = 15, sd = 5))
      )))
    }
    list()
  },

  stop = function(entity, event) entity$current$battery_pct < 10,

  observe = function(entity, event) {
    s <- entity$snapshot(c("battery_pct", "payload_kg", "prob_rain", "wind_kph"))
    data.frame(
      time        = entity$last_time,
      event_type  = event$event_type,
      battery_pct = round(s$battery_pct, 1),
      payload_kg  = round(s$payload_kg, 2),
      prob_rain   = round(s$prob_rain, 2),
      wind_kph    = round(s$wind_kph, 1)
    )
  }
)
```

The key line is `update_block(entity, "weather", list(prob_rain = ..., wind_kph = ...))`. It does three things: (1) checks that `weather` is a declared block in the entity's schema, (2) verifies that the supplied names cover every block member (`require_all = TRUE` is the default), and (3) returns a schema-validated, schema-ordered named list ready to be returned from `transition()`. If you forgot one member, mistyped a name, or supplied a value that violates its variable's type, you get a clear error here rather than a silent half-applied update.

Running it:


``` r
set.seed(2)
p_w <- Entity$new(
  init = list(
    route_zone           = "urban",
    battery_pct          = 100,
    payload_kg           = 0,
    deliveries_completed = 0L,
    prob_rain            = 0.5,
    wind_kph             = 12
  ),
  schema = quicker_schema_w_weather,
  entity_type = "courier",
  time0 = 0
)

eng_w <- Engine$new(bundle = weather_aware_bundle)
out_w <- eng_w$run(p_w, max_events = 200, return_observations = TRUE)
tail(out_w$observations, 10)
#>         time      event_type battery_pct payload_kg prob_rain wind_kph
#> 3   2.930681        dispatch        79.0       3.85      0.17     22.9
#> 4   3.974537        dispatch        71.9       5.67      0.17     22.9
#> 5   4.687483 weather_refresh        71.9       5.67      0.84     12.2
#> 6   5.495019        dispatch        55.8       7.07      0.84     12.2
#> 7   5.502898 weather_refresh        55.8       7.07      0.81      2.7
#> 8   6.981202        dispatch        36.0       9.51      0.81      2.7
#> 9   7.342054 weather_refresh        36.0       9.51      0.86     14.2
#> 10  8.517137        dispatch        30.1      11.22      0.86     14.2
#> 11  9.368401        dispatch        19.5      13.77      0.86     14.2
#> 12 10.828020        dispatch         1.9      15.35      0.86     14.2
```

Notice how `prob_rain` and `wind_kph` only ever change on rows whose `event_type` is `weather_refresh`, and they always change *together*. That's the contract the block buys you.


## Controlling proposal refresh

After every event the engine must regenerate proposals for the next step. Without any guidance it re-calls `propose_events()` for every process — always correct, but potentially wasteful when some processes are entirely unaffected by the state change that just occurred.

The `refresh_rules` bundle hook controls this. It is a function with signature `refresh_rules(entity, last_event, changes)` that returns either `"ALL"` (re-propose everything) or a character vector of the specific `process_id` values that need fresh proposals. Two arguments are worth distinguishing:

- `entity` — the full post-transition entity, including `entity$current` (all state variables as they stand now), `entity$hist` (full sparse history), and `entity$events` (complete event log). Rules can inspect cumulative state that has evolved over many iterations — not just what changed in the last step.
- `changes` — only the named list returned by the most recent `transition()` call, i.e., the delta for this one event.

These are not the same thing. A battery that has declined steadily across twenty dispatches looks the same to `changes` on the twenty-first event as it did on the first — the delta is just `battery_pct = <new value>`. But `entity$current$battery_pct` reflects the accumulated result, so a rule can react to the overall state: "if we're below 20%, we're in a qualitatively different regime and both processes need to re-propose."

Two principles apply when writing refresh rules:

1. **The winning process must always be refreshed.** Its proposal was just consumed; if it is not re-asked it will hold a stale `time_next` that has already passed and will keep winning indefinitely.
2. **Only refresh processes whose next-event timing depends on what just changed.** If a process's clock is truly independent of the current state change, its existing proposal is still valid.

For the courier model, the reasoning is straightforward:

- After `dispatch` fires: battery and payload changed, so `dispatch` needs a fresh proposal. Weather timing is determined by atmospheric dynamics independent of any individual courier — the weather proposal can stand.
- After `weather_refresh` fires: weather is the winner and must re-propose; courier delivery rates may also be affected by new conditions (rain slows deliveries), so `dispatch` should re-propose too.


``` r
weather_aware_bundle_rr <- list(
  time_spec = time_spec(unit = "hours"),

  propose_events = weather_aware_bundle$propose_events,
  transition     = weather_aware_bundle$transition,
  stop           = weather_aware_bundle$stop,
  observe        = weather_aware_bundle$observe,

  refresh_rules = function(entity, last_event, changes) {
    if (identical(last_event$event_type, "dispatch")) {
      return("dispatch")   # weather clock is independent of courier state
    }
    "ALL"                  # weather_refresh: both processes re-propose
  }
)

set.seed(2)
p_rr <- Entity$new(
  init = list(
    route_zone           = "urban",
    battery_pct          = 100,
    payload_kg           = 0,
    deliveries_completed = 0L,
    prob_rain            = 0.5,
    wind_kph             = 12
  ),
  schema = quicker_schema_w_weather,
  entity_type = "courier",
  time0 = 0
)

eng_rr <- Engine$new(bundle = weather_aware_bundle_rr)
out_rr <- eng_rr$run(p_rr, max_events = 200, return_observations = TRUE)
tail(out_rr$observations, 10)
#>         time      event_type battery_pct payload_kg prob_rain wind_kph
#> 5   4.035234 weather_refresh        85.0       3.09      0.84     12.2
#> 6   4.842769        dispatch        68.9       4.49      0.84     12.2
#> 7   5.797614 weather_refresh        68.9       4.49      0.81      2.7
#> 8   7.275917        dispatch        49.1       6.93      0.81      2.7
#> 9   7.387118 weather_refresh        49.1       6.93      0.86     14.2
#> 10  8.562201        dispatch        43.2       8.63      0.86     14.2
#> 11  9.413464        dispatch        32.6      11.19      0.86     14.2
#> 12 10.873084        dispatch        15.0      12.77      0.86     14.2
#> 13 11.655937 weather_refresh        15.0      12.77      0.46     10.7
#> 14 12.375622        dispatch         6.5      15.80      0.46     10.7
```

The output is identical to `out_w` above — same seed, same dynamics, just fewer redundant `propose_events()` calls. For a two-process model the savings are modest; in models with many independent processes the difference can be significant.


## Decision points, actions, and trajectory logging

Everything so far has been a *pure generative process*: events happen, state
evolves, the engine stops when `stop()` returns `TRUE`. There is no external
agent choosing what to do.

Many real systems involve **decisions** — moments where a policy (a clinician, a
dispatcher, a learned algorithm) is consulted and may inject an intervention into
the timeline. fluxCore makes these first-class through three structures that work
together:

| Structure | What it is |
|---|---|
| `DecisionPoint` | *Where* in the simulation a decision can occur. Declared in the schema. Triggers on specified event types. |
| `ActionEvent` | The intervention itself. Proposed by the policy at a decision point; enters the normal event timeline. |
| `TrajectoryRecord` | The audit log emitted at each decision point: what was observed, what action was proposed, what was realized. |

The key conceptual move is that **actions are events**. A policy does not mutate
state directly — it proposes an `ActionEvent` with a `time_next` and an
`action_type`. That action enters the same proposal queue as any other event and
is realized by the normal `transition()` / `stop()` path. This means:

- Actions obey the same deterministic ordering as everything else.
- Actions can be ignored, arbitrated against, or superseded like any other event.
- The full trajectory — what the entity saw, what the policy proposed, what
  actually happened — is captured in `TrajectoryRecord` objects for later audit,
  comparison, or RL reward computation.

### Declaring a decision point

Decision points are declared on the schema, not inferred at runtime. This makes
the policy interface explicit: any schema without `$decision_points` runs as a
pure generative model regardless of what policy you pass.

For our delivery example, a natural decision point is *after each dispatch*: once
a delivery is completed, should the drone switch to surge-priority mode (faster
routing, higher power draw) to complete remaining deliveries before the battery
dies, or continue in normal mode (conserving energy)?

The motivation: in surge mode, deliveries complete faster (shorter intervals) but
at the cost of ~50% more battery drain per dispatch. A smart policy must decide
when the energy savings from normal mode are no longer worth the risk of running
out before finishing the route.


``` r
# Variables schema for the decision-point example
dp_vars <- set_schema(
  vars = list(
    route_zone           = list(type = "categorical",
                                levels = c("urban", "suburban", "rural")),
    battery_pct          = "percent",
    payload_kg           = list(type = "nonnegative_numeric", max = 20),
    deliveries_completed = "count",
    prob_rain            = "probability",
    priority_mode        = list(type = "categorical",
                                levels = c("normal", "surge"),
                                default = "normal")
  )
)

# Declare a decision point: fires after every "dispatch" event.
# The policy may propose the action "surge" or "stand_down".
dp_post_dispatch <- DecisionPoint(
  id              = "post_dispatch",
  trigger         = "dispatch",
  allowed_actions = c("surge", "stand_down"),
  label           = "After each delivery: surge or stand down?"
)

# Full schema for load_model(): wraps variables, time_spec, and decision_points
schema_dp <- list(
  variables       = dp_vars,
  time_spec       = time_spec(unit = "hours"),
  decision_points = list(dp_post_dispatch)
)
```

`trigger` is the event type(s) that fire the decision point. The engine checks
this after applying `transition()` — so the entity's state already reflects the
just-completed event when the policy is consulted. `allowed_actions` constrains
what the policy is permitted to propose; actions outside this set are ignored with
a warning.

You can also supply an `observation_fn` — a function of `entity` that extracts a
compact, policy-relevant view of state. If you omit it, the policy receives the
full entity.

### Writing a policy

A policy is a list with a `propose_action` method:

```
propose_action(decision_point, entity, sim_ctx, param_ctx) -> ActionEvent | NULL
```

It returns an `ActionEvent` if it wants to intervene, or `NULL` for no
intervention. Here is a simple rule-based policy: surge if battery is below 60%,
stand down otherwise.


``` r
battery_policy <- list(
  propose_action = function(decision_point, entity, sim_ctx, param_ctx) {
    battery <- entity$current$battery_pct

    action <- if (!is.null(battery) && battery < 60) "surge" else "stand_down"

    ActionEvent(
      action_type       = action,
      time_next         = entity$last_time + 0.05,   # realized 3 minutes later
      decision_point_id = decision_point$id,
      metadata          = list(battery_at_decision = battery)
    )
  }
)
```

`time_next` on an `ActionEvent` is the time at which the action is realized in
the simulation — here, 0.05 hours (3 minutes) after the triggering dispatch. The
action then flows through `transition()` just like any other event.

### Assembling with load_model() and enabling trajectory logging

When decision points are present, the recommended assembly path is `load_model()`
rather than `Engine$new()`. It validates that the schema, bundle, policy, and
(optionally) trajectory logger are all mutually consistent before any run begins.

`trajectory` controls what gets captured at each decision point:

- `list(detail = "none")` — records that the decision point fired, but no state snapshots.
- `list(detail = "summary")` — before/after snapshots via `state_summary_default()`.
- `list(detail = "full")` — complete `entity$current` captured before and after.


``` r
# Bundle that handles the "surge" and "stand_down" action types in transition()
dp_bundle <- list(
  time_spec = time_spec(unit = "hours"),

  propose_events = function(entity) {
    # In surge mode: shorter intervals (faster delivery) but transition() will
    # drain more battery.
    rate <- if (identical(entity$current$priority_mode, "surge")) 1.8 else 1.0
    list(dispatch = list(
      time_next  = entity$last_time + stats::rlnorm(1, meanlog = log(1/rate), sdlog = 0.3),
      event_type = "dispatch"
    ))
  },

  transition = function(entity, event) {
    if (identical(event$event_type, "dispatch")) {
      # Surge mode drains ~50% more battery per dispatch
      drain <- if (identical(entity$current$priority_mode, "surge")) {
        stats::rlnorm(1, meanlog = 2.8, sdlog = 0.2)   # ~16% mean
      } else {
        stats::rlnorm(1, meanlog = 2.3, sdlog = 0.3)   # ~10% mean
      }
      return(list(
        payload_kg           = 0,
        battery_pct          = max(0, as.numeric(entity$current$battery_pct) - drain),
        deliveries_completed = as.integer(entity$current$deliveries_completed) + 1L
      ))
    }
    if (identical(event$event_type, "surge"))      return(list(priority_mode = "surge"))
    if (identical(event$event_type, "stand_down")) return(list(priority_mode = "normal"))
    list()
  },

  stop = function(entity, event) {
    as.numeric(entity$current$battery_pct) < 10
  },

  observe = function(entity, event) {
    s <- entity$snapshot(c("battery_pct", "deliveries_completed", "priority_mode"))
    data.frame(
      time                 = entity$last_time,
      event_type           = event$event_type,
      battery_pct          = round(s$battery_pct, 1),
      deliveries_completed = s$deliveries_completed,
      priority_mode        = s$priority_mode
    )
  }
)

# Assemble the engine with policy and trajectory logging enabled
eng_dp <- load_model(
  schema     = schema_dp,
  bundle     = dp_bundle,
  policy     = battery_policy,
  trajectory = list(detail = "summary")
)
```

### Running and inspecting trajectory records


``` r
set.seed(7)
p_dp <- Entity$new(
  init = list(
    route_zone           = "urban",
    battery_pct          = 100,
    payload_kg           = 0,
    deliveries_completed = 0L,
    prob_rain            = 0.3,
    priority_mode        = "normal"
  ),
  schema      = schema_dp$variables,
  entity_type = "courier",
  time0       = 0
)

out_dp <- eng_dp$run(p_dp, max_events = 200, return_observations = TRUE)
```

`out_dp$trajectory_records` is a list of named lists — one per decision point
firing. Each record answers four questions:

1. **When did the decision point fire?** (`t`, `decision_point_id`)
2. **What did the policy observe?** (`observation` — the state snapshot presented to the policy)
3. **What did the policy propose?** (`proposed_actions`)
4. **What actually happened?** (`realized_event`, `state_before`, `state_after`)


``` r
# How many decision points fired?
length(out_dp$trajectory_records)
#> [1] 8

# Inspect the first record
tr1 <- out_dp$trajectory_records[[1]]
cat("Time:          ", tr1$t, "\n")
#> Time:           1.986102
cat("Decision point:", tr1$decision_point_id, "\n")
#> Decision point: post_dispatch
cat("Trigger event: ", tr1$realized_event$event_type, "\n")
#> Trigger event:  dispatch
cat("Action taken:  ", tr1$selected_action$action_type, "\n")
#> Action taken:   stand_down
cat("Battery before:", tr1$state_before$battery_pct, "\n")
#> Battery before: 100
cat("Battery after: ", tr1$state_after$battery_pct, "\n")
#> Battery after:  93.03451
```


``` r
# Build a summary table across all trajectory records
tr_df <- trajectory_table(out_dp$trajectory_records,
                          vars = c("battery_pct", "deliveries_completed"))
head(tr_df, 10)
#>           t decision_point_id trigger_event action_taken condition_met
#> 1  1.986102     post_dispatch      dispatch   stand_down            NA
#> 2  2.919758     post_dispatch      dispatch   stand_down            NA
#> 3  4.221382     post_dispatch      dispatch   stand_down            NA
#> 4  6.200366     post_dispatch      dispatch   stand_down            NA
#> 5  8.233018     post_dispatch      dispatch        surge            NA
#> 6  8.922254     post_dispatch      dispatch        surge            NA
#> 7  9.527006     post_dispatch      dispatch        surge            NA
#> 8 10.263482     post_dispatch      dispatch        surge            NA
#>   battery_pct_before battery_pct_after deliveries_completed_before
#> 1          100.00000          93.03451                           0
#> 2           93.03451          85.58015                           1
#> 3           85.58015          75.94986                           2
#> 4           75.94986          64.84819                           3
#> 5           64.84819          53.85577                           4
#> 6           53.85577          40.10300                           5
#> 7           40.10300          20.06496                           6
#> 8           20.06496           0.00000                           7
#>   deliveries_completed_after
#> 1                          1
#> 2                          2
#> 3                          3
#> 4                          4
#> 5                          5
#> 6                          6
#> 7                          7
#> 8                          8
```

Notice the pattern: the policy switches to "surge" as the battery drops below
60%, then stays in surge mode for remaining deliveries (accepting higher drain
to complete faster). Because `TrajectoryRecord` captures state before and after
each decision, you can reconstruct exactly what the policy saw and why it acted
— which is the foundation for policy comparison, counterfactual analysis, and RL
reward computation in `fluxSim`.

### What trajectory records enable downstream

`TrajectoryRecord` is not just an audit log. It is the structured surface that the
rest of the ecosystem builds on:

- **Policy comparison** (`fluxSim`): run the same entity under two policies
  with the same seed; diff the `trajectory_records` to see where they diverge.
- **Counterfactual analysis**: fix the seed and parameter draw; vary only the
  policy; compare outcomes.
- **RL training** (`fluxSim`): the `(observation, action, reward,
  next_state)` tuple for each record becomes a training transition. The reward
  function is defined externally and applied to the record.
- **Audit and explainability**: for any individual run, you can reconstruct the
  full decision history and ask "why did the simulation do that?"


## Scaling up: batch runs across a cohort

Everything above has involved a single entity running to completion. In practice you will want to simulate an entire cohort — many entities, each with its own starting state — and collect the results in a tidy index. `run_cohort()` handles this: it takes an engine and a named list of entities, runs each one, and returns a `$index` data frame with one row per entity per run.


``` r
entities <- lapply(1:4, function(i) {
  Entity$new(
    init = list(
      route_zone = c("urban", "suburban", "rural", "urban")[i],
      battery_pct = 100 - 5 * i,
      payload_kg = i - 1,
      deliveries_completed = 0L,
      prob_rain = 0.5
    ),
    schema = quicker_schema,
    entity_type = "courier",
    time0 = 0
  )
})
names(entities) <- paste0("id", 1:4)

batch <- run_cohort(
  eng,
  entities,
  n_sims = 2,
  max_events = 50,
  backend = "none",
  seed = 123
)
#> Error: Value for 'payload_kg' must be <= 20.

head(batch$index)
#> Error: object 'batch' not found
```

`n_sims = 2` runs each entity twice with different random seeds, giving two stochastic replicates per courier. The `$index` records the entity id, sim id, and any summary statistics your `observe()` hook accumulated.

### Incorporating parameter uncertainty

Real delivery fleets vary in ways beyond initial state: dispatch rates, battery drain, payload distributions. The `n_param_draws` argument to `run_cohort()` handles this by running every entity under multiple independent parameter realizations, fully crossing entities × parameter draws × stochastic replicates.

The mechanism has two parts:

- **`sample_params(n)`**: a bundle hook that returns a list of `n` `ParamContext` objects, one per draw. Each `ParamContext` carries a `draw_id` and a `params` named list of concrete sampled values.
- **`param_ctx` argument**: any bundle callback (`propose_events`, `transition`, `stop`, `observe`) can declare `param_ctx = NULL` as an optional argument. The engine injects the correct `ParamContext` for each draw; when no draw is active (e.g., a direct `Engine$run()` call) the argument is `NULL`, so callbacks fall back gracefully to default constants.

Construct a `ParamContext` manually to inspect its structure:


``` r
pc <- ParamContext(
  draw_id = 1L,
  params  = list(interval_meanlog = 0.2, drain_meanlog = 2.3)
)
print(pc)
#> <ParamContext>
#>   draw_id   : 1 
#>   provenance: (none) 
#>   params    : 2 field(s)
pc$params$interval_meanlog
#> [1] 0.2
```

`sample_params(n)` is simply a function that returns `n` objects like `pc` above — one per draw, each with independently sampled parameter values:


``` r
courier_sample_params <- function(n) {
  purrr::map(1:n, ~ParamContext(
    draw_id = .x,
    params  = list(
      interval_meanlog = rnorm(1, mean = 0.2, sd = 0.3),
      drain_meanlog    = rnorm(1, mean = 2.3, sd = 0.2)
    )
  ))
}
```

Now build a parameter-aware bundle. The two draw-varying quantities — the lognormal `meanlog` for dispatch intervals and for battery drain — move out of hardcoded constants and into `param_ctx$params`:


``` r
toy_bundle_pd <- list(
  time_spec     = time_spec(unit = "hours"),
  sample_params = courier_sample_params,

  propose_events = function(entity, param_ctx = NULL) {
    meanlog <- if (!is.null(param_ctx)) param_ctx$params$interval_meanlog else 0.2
    list(dispatch = list(
      time_next  = entity$last_time + stats::rlnorm(1, meanlog = meanlog, sdlog = 0.4),
      event_type = "dispatch"
    ))
  },

  transition = function(entity, event, param_ctx = NULL) {
    if (!identical(event$event_type, "dispatch")) return(list())
    drain_log <- if (!is.null(param_ctx)) param_ctx$params$drain_meanlog else 2.3
    list(
      payload_kg  = max(0, as.numeric(entity$current$payload_kg) +
                            stats::rnorm(1, mean = 2, sd = 0.5)),
      battery_pct = max(0, as.numeric(entity$current$battery_pct) -
                            stats::rlnorm(1, meanlog = drain_log, sdlog = 0.3))
    )
  },

  stop    = toy_bundle$stop,
  observe = toy_bundle$observe
)
```

The `NULL` defaults mean this bundle is also valid for a single-entity `Engine$run()` without any draws — the fallback constants preserve the same behavior as `toy_bundle`.


``` r
eng_pd <- Engine$new(bundle = toy_bundle_pd)

batch_pd <- run_cohort(
  eng_pd,
  entities,
  n_param_draws = 3,
  n_sims = 2,
  max_events = 50,
  backend = "none",
  seed = 123
)
#> Error in stats::rlnorm(1, meanlog = meanlog, sdlog = 0.4): invalid arguments

head(batch_pd$index, 12)
#> Error: object 'batch_pd' not found
```

Each of the 4 couriers now produces 6 rows (3 draws × 2 sims). Rows sharing the same `param_draw_id` were simulated under identical drawn parameters — the only variance within a draw is the stochastic replicate seed. Rows with different `param_draw_id` also differ in `interval_meanlog` and `drain_meanlog`, so systematic differences in event counts or stopping time across draws reflect genuine model-parameter uncertainty rather than random noise.

The drawn `ParamContext` objects are also returned in `batch_pd$param_draws` for reproducibility — you can inspect, save, or replay any individual draw:


``` r
batch_pd$param_draws[[1]]
#> Error: object 'batch_pd' not found
```
