Tutorials 01–03 ran the delivery model forward from known starting states.
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

## Why preparation is its own step

The flux ecosystem is built around process-explicit, event-driven models. In
this framework we do not start with regression models applied directly to raw
operational tables. Instead, we explicitly define the processes by which entity
state evolves over time: events occur, state variables update in response, and
entities enter and exit follow-up.

This distinction matters because real operational data lives on **multiple
clocks simultaneously**. Battery readings arrive from irregular sensor pings.
Delivery completions happen at unpredictable times. Shift boundaries are
deterministic but vary per agent. Traditional tabular analyses often flatten
this complexity by imposing an implicit time grid or silently carrying forward
stale values — choices that encode assumptions whether or not we acknowledge
them.

The flux approach makes time, events, and state *explicit*, and surfaces
modeling assumptions rather than burying them. Preparation is where those
assumptions are specified.

### Core concepts

- **Anchors** are the time points at which entity state is reconstructed.
  Rather than imposing a regular grid (e.g., hourly snapshots), anchors can be
  defined at clinically or operationally meaningful moments — event
  occurrences, measurement arrivals, or shift starts. This keeps training data
  aligned with the structure the simulation enforces.

- **Intervals** are the spans between consecutive anchors. Each interval has a
  start anchor, an end anchor, a duration, and zero or more events occurring
  within it. Rows in a TTV dataset are defined at the interval level:
  covariates represent state at the start, outcomes represent events within or
  at the end.

- **As-of state** means that at each anchor, entity state is reconstructed
  using only data available *as of that time*, subject to explicit recency and
  validity rules (`lookback`, `staleness`). This avoids leaking future
  information into training rows.

- **Follow-up ≠ alive.** An agent may be alive but no longer observed (e.g.,
  went off-shift, left the fleet). After follow-up ends, state is undefined.
  This distinction is essential for correct denominators in both model
  development and downstream validation.

### The Prepare workflow: standardize → segment → build

The `fluxPrepare` pipeline has three stages:

1. **Standardize** (`prepare_events()`, `prepare_observations()`) — convert
   heterogeneous raw tables into a consistent internal format with a shared
   time scale.
2. **Segment** (`spec_event_process()` + segmentation helpers) — define how
   follow-up is divided into start–stop intervals. Segmentation means: "when
   meaningful new information arrives, start a new interval."
3. **Build** (`build_ttv_event_process()`, `reconstruct_state_at()`) — produce
   rows suitable for model training, with entity-level train/test/validation
   splits.

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
head(ops$entities) |> kable()
```



|entity_id |vehicle_type |home_zone |
|:---------|:------------|:---------|
|agent_001 |van          |suburban  |
|agent_002 |van          |suburban  |
|agent_003 |ebike        |urban     |
|agent_004 |scooter      |suburban  |
|agent_005 |scooter      |urban     |
|agent_006 |scooter      |suburban  |




``` r
head(ops$observations) |> kable(digits = 2)
```



|entity_id | time| battery_pct|
|:---------|----:|-----------:|
|agent_001 | 1.19|        96.9|
|agent_001 | 1.36|        96.3|
|agent_001 | 2.35|        91.2|
|agent_001 | 2.59|        91.9|
|agent_001 | 3.16|        91.3|
|agent_001 | 5.76|        61.7|




``` r
head(ops$events) |> kable(digits = 2)
```



|entity_id | time|event_type         |
|:---------|----:|:------------------|
|agent_001 | 2.38|delivery_completed |
|agent_001 | 3.45|delivery_completed |
|agent_001 | 5.19|delivery_completed |
|agent_001 | 5.66|delivery_completed |
|agent_001 | 7.26|delivery_completed |
|agent_001 | 7.45|delivery_completed |




``` r
head(ops$followup) |> kable(digits = 2)
```



|entity_id |shift_id          | followup_start| followup_end|
|:---------|:-----------------|--------------:|------------:|
|agent_001 |agent_001_shift_1 |              0|            8|
|agent_001 |agent_001_shift_2 |             24|           32|
|agent_001 |agent_001_shift_3 |             48|           56|
|agent_001 |agent_001_shift_4 |             72|           80|
|agent_001 |agent_001_shift_5 |             96|          104|
|agent_001 |agent_001_shift_6 |            120|          128|



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
head(splits) |> kable()
```



|entity_id |split      |
|:---------|:----------|
|agent_001 |test       |
|agent_002 |validation |
|agent_003 |train      |
|agent_004 |test       |
|agent_005 |train      |
|agent_006 |validation |




``` r
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

head(events_prep) |> kable(digits = 2)
```



|entity_id | time|event_type         |source_table |
|:---------|----:|:------------------|:------------|
|agent_001 | 2.38|delivery_completed |NA           |
|agent_001 | 3.45|delivery_completed |NA           |
|agent_001 | 5.19|delivery_completed |NA           |
|agent_001 | 5.66|delivery_completed |NA           |
|agent_001 | 7.26|delivery_completed |NA           |
|agent_001 | 7.45|delivery_completed |NA           |



``` r
cat("Total rows:", nrow(events_prep), "\n")
#> Total rows: 1360
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

head(obs_prep) |> kable(digits = 2)
```



|entity_id | time|group   | battery_pct|source_table |
|:---------|----:|:-------|-----------:|:------------|
|agent_001 | 1.19|battery |        96.9|battery      |
|agent_001 | 1.36|battery |        96.3|battery      |
|agent_001 | 2.35|battery |        91.2|battery      |
|agent_001 | 2.59|battery |        91.9|battery      |
|agent_001 | 3.16|battery |        91.3|battery      |
|agent_001 | 5.76|battery |        61.7|battery      |



``` r
cat("Total rows:", nrow(obs_prep), "\n")
#> Total rows: 3806
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

The core analytical question for Tutorial 05 (validation) is: **given an agent's
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
head(ttv_test) |> kable(digits = 2)
```



|   |entity_id |split | t0|   t1| deltat|event_occurred |event_type         | censoring_time|
|:--|:---------|:-----|--:|----:|------:|:--------------|:------------------|--------------:|
|1  |agent_001 |test  |  0| 2.38|   2.38|TRUE           |delivery_completed |              8|
|4  |agent_004 |test  |  0| 3.29|   3.29|TRUE           |delivery_completed |              8|
|17 |agent_017 |test  |  0| 2.33|   2.33|TRUE           |delivery_completed |              8|
|21 |agent_021 |test  |  0| 2.34|   2.34|TRUE           |delivery_completed |              8|
|23 |agent_023 |test  |  0| 0.77|   0.77|TRUE           |delivery_completed |              8|
|25 |agent_025 |test  |  0| 0.87|   0.87|TRUE           |delivery_completed |              8|



``` r
cat("Train rows:", nrow(ttv_train), "\n")
#> Train rows: 18
cat("Test rows: ", nrow(ttv_test), "\n")
#> Test rows:  6
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

head(state_at_t0) |> kable(digits = 2)
```



|entity_id | t0|battery_pct | .time_battery_pct|.prov_battery_pct |
|:---------|--:|:-----------|-----------------:|:-----------------|
|agent_001 |  0|NA          |                NA|missing           |
|agent_004 |  0|NA          |                NA|missing           |
|agent_017 |  0|NA          |                NA|missing           |
|agent_021 |  0|NA          |                NA|missing           |
|agent_023 |  0|NA          |                NA|missing           |
|agent_025 |  0|NA          |                NA|missing           |



Each row tells you: "for entity X at anchor time t₀, the last observed
battery_pct was Y." This is the starting state you feed to the Engine in
Tutorial 05 when running forecasts from the test set.

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

**Next:** [05_validation.md](05_validation.md) — forecast from the test-set
baselines and compare predicted vs observed outcomes using `fluxValidation`.
