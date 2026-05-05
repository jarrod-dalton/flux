Tutorials 03 and 04 ran the delivery model forward from known starting states.
In practice, the starting states come from **operational data** — sensor logs,
transaction records, GPS pings — that must be cleaned, aligned, and split before
the model can consume them.

This tutorial introduces `fluxPrepare`: the package that transforms messy
real-world observations into the structured train/test/validation (TTV) format
that the forecast and validation tools expect. By the end you will be able to:

- generate a synthetic operational log for the delivery fleet,
- prepare observations and events into canonical format,
- split by entity (no data leakage),
- build a TTV event process (anchored intervals with outcomes),
- reconstruct agent state at a forecast anchor time.

## Load the model and data generator


``` r
source("tutorials/model/urban_delivery.R")
source("tutorials/model/urban_delivery_data.R")
```

## Generate synthetic operational data

`generate_delivery_log()` runs the delivery model under the hood to produce
a realistic fleet log — the kind of data you'd get from a production system:


``` r
set.seed(42)
ops <- generate_delivery_log(
  n_agents = 30,
  n_shifts = 8,
  params   = list(shift_length_hours = 8)
)
```

The result has four components:


``` r
str(ops, max.level = 1)
#> List of 4
#>  $ entities    :'data.frame':	30 obs. of  3 variables:
#>  $ observations:'data.frame':	3806 obs. of  3 variables:
#>  $ events      :'data.frame':	1360 obs. of  3 variables:
#>  $ followup    :'data.frame':	240 obs. of  4 variables:
```

- **`$entities`** — one row per agent: id, vehicle type, home zone.
- **`$observations`** — irregular battery readings (sensor pings).
- **`$events`** — delivery completion timestamps.
- **`$followup`** — shift-level follow-up windows.

Let's look at each:


``` r
head(ops$entities)
#>   entity_id vehicle_type home_zone
#> 1 agent_001          van  suburban
#> 2 agent_002          van  suburban
#> 3 agent_003        ebike     urban
#> 4 agent_004      scooter  suburban
#> 5 agent_005      scooter     urban
#> 6 agent_006      scooter  suburban
head(ops$observations)
#>   entity_id     time battery_pct
#> 1 agent_001 1.192576        96.9
#> 2 agent_001 1.361300        96.3
#> 3 agent_001 2.348991        91.2
#> 4 agent_001 2.592688        91.9
#> 5 agent_001 3.155528        91.3
#> 6 agent_001 5.755029        61.7
head(ops$events)
#>   entity_id     time         event_type
#> 1 agent_001 2.376843 delivery_completed
#> 2 agent_001 3.445999 delivery_completed
#> 3 agent_001 5.190126 delivery_completed
#> 4 agent_001 5.663729 delivery_completed
#> 5 agent_001 7.264171 delivery_completed
#> 6 agent_001 7.452949 delivery_completed
head(ops$followup)
#>   entity_id          shift_id followup_start followup_end
#> 1 agent_001 agent_001_shift_1              0            8
#> 2 agent_001 agent_001_shift_2             24           32
#> 3 agent_001 agent_001_shift_3             48           56
#> 4 agent_001 agent_001_shift_4             72           80
#> 5 agent_001 agent_001_shift_5             96          104
#> 6 agent_001 agent_001_shift_6            120          128
```

Notice that observations are in **long format** (entity_id × time × variable ×
value). This is the canonical shape `fluxPrepare` expects for continuous
measurements.

## Entity-level splits

The most important rule: **split by entity, not by time**. All shifts belonging
to one agent go into the same split. This prevents information leakage — a model
that has seen agent_003's Monday shift should not be evaluated on agent_003's
Tuesday shift.


``` r
splits <- generate_splits(ops$entities, train_frac = 0.6, test_frac = 0.2,
                          seed = 123)
head(splits)
#>   entity_id      split
#> 1 agent_001       test
#> 2 agent_002 validation
#> 3 agent_003      train
#> 4 agent_004       test
#> 5 agent_005      train
#> 6 agent_006 validation
table(splits$split)
#> 
#>       test      train validation 
#>          6         18          6
```

## `prepare_events()` — canonical event format

Raw event tables vary in column naming. `prepare_events()` standardizes them
into the format downstream tools expect: `entity_id`, `time`, `event_type`.


``` r
events_prep <- prepare_events(
  events    = ops$events,
  id_col    = "entity_id",
  time_col  = "time",
  type_col  = "event_type",
  time_spec = time_spec(unit = "hours"),
  sort      = TRUE
)

head(events_prep)
#>   entity_id     time         event_type source_table
#> 1 agent_001 2.376843 delivery_completed         <NA>
#> 2 agent_001 3.445999 delivery_completed         <NA>
#> 3 agent_001 5.190126 delivery_completed         <NA>
#> 4 agent_001 5.663729 delivery_completed         <NA>
#> 5 agent_001 7.264171 delivery_completed         <NA>
#> 6 agent_001 7.452949 delivery_completed         <NA>
nrow(events_prep)
#> [1] 1360
```

## `prepare_observations()` — canonical observation format

Observations require a **spec** that tells fluxPrepare how to interpret each
measurement source. The spec is a simple list identifying the id column, time
column, and which columns contain the measured variables:


``` r
battery_spec <- list(
  id_col   = "entity_id",
  time_col = "time",
  vars     = "battery_pct"
)

obs_prep <- prepare_observations(
  tables    = list(battery = ops$observations),
  specs     = list(battery = battery_spec),
  time_spec = time_spec(unit = "hours"),
  sort      = TRUE
)

head(obs_prep)
#>   entity_id     time   group battery_pct source_table
#> 1 agent_001 1.192576 battery        96.9      battery
#> 2 agent_001 1.361300 battery        96.3      battery
#> 3 agent_001 2.348991 battery        91.2      battery
#> 4 agent_001 2.592688 battery        91.9      battery
#> 5 agent_001 3.155528 battery        91.3      battery
#> 6 agent_001 5.755029 battery        61.7      battery
nrow(obs_prep)
#> [1] 3806
```

## `prepare_splits()` — validate the split table


``` r
splits_prep <- prepare_splits(
  df       = splits,
  id_col   = "entity_id",
  split_col = "split"
)

str(splits_prep)
#> Classes 'flux_splits' and 'data.frame':	30 obs. of  2 variables:
#>  $ entity_id: chr  "agent_001" "agent_002" "agent_003" "agent_004" ...
#>  $ split    : chr  "test" "validation" "train" "test" ...
#>  - attr(*, "allowed_splits")= chr [1:3] "train" "test" "validation"
```

This is a lightweight validation step: it checks that every entity has exactly
one split assignment and that split labels are from the allowed set
(train/test/validation).

## Building the TTV event process

The core analytical question for Tutorial 06 (validation) is: **given an agent's
state at time t₀, what is the probability of a delivery completion within the
next H hours?**

To answer this, we need anchored intervals: for each agent in the test set,
define a start time (t₀), a horizon (H), and record whether the event actually
happened. This is what `build_ttv_event_process()` constructs.

First, define a spec for the event process:


``` r
delivery_ep_spec <- spec_event_process(
  event_types = "delivery_completed",
  name        = "delivery_completion",
  t0_strategy = "followup_start"
)
```

Then build the TTV:


``` r
ttv <- build_ttv_event_process(
  events       = events_prep,
  observations = obs_prep,
  splits       = splits_prep,
  spec         = delivery_ep_spec,
  followup     = ops$followup,
  time_spec    = time_spec(unit = "hours")
)

str(ttv, max.level = 1)
#> 'data.frame':	30 obs. of  8 variables:
#>  $ entity_id     : chr  "agent_001" "agent_002" "agent_003" "agent_004" ...
#>  $ split         : chr  "test" "validation" "train" "test" ...
#>  $ t0            : num  0 0 0 0 0 0 0 0 0 0 ...
#>  $ t1            : num  2.377 0.742 1.338 3.288 0.761 ...
#>  $ deltat        : num  2.377 0.742 1.338 3.288 0.761 ...
#>  $ event_occurred: logi  TRUE TRUE TRUE TRUE TRUE TRUE ...
#>  $ event_type    : chr  "delivery_completed" "delivery_completed" "delivery_completed" "delivery_completed" ...
#>  $ censoring_time: num  8 8 8 8 8 8 8 8 8 8 ...
#>  - attr(*, "spec")=List of 13
#>   ..- attr(*, "class")= chr [1:2] "spec_event_process" "flux_spec"
#>  - attr(*, "metadata")=List of 4
```

The result is a single data frame with a `split` column indicating which rows
belong to train, test, or validation.


``` r
ttv_train <- ttv[ttv$split == "train", ]
ttv_test  <- ttv[ttv$split == "test", ]
head(ttv_test)
#>    entity_id split t0        t1    deltat event_occurred         event_type
#> 1  agent_001  test  0 2.3768432 2.3768432           TRUE delivery_completed
#> 4  agent_004  test  0 3.2884482 3.2884482           TRUE delivery_completed
#> 17 agent_017  test  0 2.3255248 2.3255248           TRUE delivery_completed
#> 21 agent_021  test  0 2.3429078 2.3429078           TRUE delivery_completed
#> 23 agent_023  test  0 0.7654377 0.7654377           TRUE delivery_completed
#> 25 agent_025  test  0 0.8656996 0.8656996           TRUE delivery_completed
#>    censoring_time
#> 1               8
#> 4               8
#> 17              8
#> 21              8
#> 23              8
#> 25              8
nrow(ttv_train)
#> [1] 18
nrow(ttv_test)
#> [1] 6
```

Each row is one entity × one interval: `entity_id`, `t0` (anchor time),
`t1` (first event time or censoring), `deltat` (time to event/censoring),
`event_occurred` (TRUE if the event happened), and `censoring_time`.

## Reconstructing state at t₀

To forecast from t₀, the model needs to know the agent's state *at that moment*.
`reconstruct_state_at()` looks backward through the observation history and
recovers the most recent measurement of each variable prior to t₀.


``` r
state_at_t0 <- reconstruct_state_at(
  anchors      = ttv_test[, c("entity_id", "t0")],
  observations = obs_prep,
  vars         = "battery_pct",
  id_col       = "entity_id",
  time_col     = "t0",
  time_spec    = time_spec(unit = "hours")
)

head(state_at_t0)
#>   entity_id t0 battery_pct .time_battery_pct .prov_battery_pct
#> 1 agent_001  0          NA                NA           missing
#> 2 agent_004  0          NA                NA           missing
#> 3 agent_017  0          NA                NA           missing
#> 4 agent_021  0          NA                NA           missing
#> 5 agent_023  0          NA                NA           missing
#> 6 agent_025  0          NA                NA           missing
```

Each row tells you: "for entity X at anchor time t₀, the last observed
battery_pct was Y." This is the starting state you feed to the Engine in
Tutorial 06 when running forecasts from the test set.

## Putting it together

The preparation pipeline flow:

```
Raw ops log
  ├── prepare_events()        → canonical events
  ├── prepare_observations()  → canonical obs
  ├── generate_splits()       → entity-level splits
  │
  └── build_ttv_event_process()  → anchored intervals + outcomes
        └── reconstruct_state_at() → starting state per interval
```

Everything downstream — forecasting, validation — consumes these outputs.
The preparation step is where you catch data quality issues (missing
observations, impossible values, follow-up gaps) before they corrupt your
predictions.

## Summary

| Function | Purpose |
|----------|---------|
| `generate_delivery_log()` | Synthetic data generator (uses the delivery model) |
| `generate_splits()` | Entity-level train/test/validation split |
| `prepare_events()` | Standardize event table columns |
| `prepare_observations()` | Standardize observation tables with specs |
| `prepare_splits()` | Validate split assignments |
| `spec_event_process()` | Define the event process to model |
| `build_ttv_event_process()` | Anchored intervals with outcomes, split by TTV |
| `reconstruct_state_at()` | Recover state at each anchor time from history |

**Next:** [06_validation.md](06_validation.md) — forecast from the test-set
baselines and compare predicted vs observed outcomes using `fluxValidation`.
