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
- reconstruct courier state at a forecast anchor time.

## Why preparation is its own step

The flux ecosystem is built around process-explicit, event-driven models. In
this framework we do not start with regression models applied directly to raw
operational tables. Instead, we explicitly define the processes by which entity
state evolves over time: events occur, state variables update in response, and
entities enter and exit follow-up.

This distinction matters because real operational data lives on **multiple
clocks simultaneously**. Battery readings arrive from irregular sensor pings.
Delivery completions happen at unpredictable times. Shift boundaries are
deterministic but vary per courier. Traditional tabular analyses often flatten
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
  occurrences, measurement arrivals, decision points, or shift starts. This keeps training data
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
  n_couriers = 30,
  n_shifts   = 8,
  params     = list(shift_length_hours = 8)
)
```

The result has five tables:


``` r
str(ops, max.level = 1)
#> List of 5
#>  $ couriers:'data.frame':	30 obs. of  3 variables:
#>  $ battery :'data.frame':	3842 obs. of  3 variables:
#>  $ gps     :'data.frame':	5676 obs. of  5 variables:
#>  $ events  :'data.frame':	1428 obs. of  3 variables:
#>  $ shifts  :'data.frame':	240 obs. of  4 variables:
```

- **`$couriers`** — one row per courier: id, vehicle type, home zone.
- **`$battery`** — irregular battery readings (sensor pings per courier).
- **`$gps`** — GPS location pings (from the vehicle tracking system).
- **`$events`** — delivery completion timestamps.
- **`$shifts`** — shift-level follow-up windows, with real `POSIXct` timestamps.

Let's look at each:


``` r
head(ops$couriers) |> kable()
```



|entity_id   |vehicle_type |home_zone |
|:-----------|:------------|:---------|
|courier_001 |van          |suburban  |
|courier_002 |van          |suburban  |
|courier_003 |ebike        |urban     |
|courier_004 |scooter      |suburban  |
|courier_005 |scooter      |urban     |
|courier_006 |scooter      |suburban  |




``` r
head(ops$battery) |> kable(digits = 1)
```



|entity_id   |time                | battery_pct|
|:-----------|:-------------------|-----------:|
|courier_001 |2026-01-05 07:11:33 |        96.9|
|courier_001 |2026-01-05 07:21:40 |        96.3|
|courier_001 |2026-01-05 08:20:56 |        91.2|
|courier_001 |2026-01-05 08:35:33 |        91.9|
|courier_001 |2026-01-05 09:09:19 |        91.3|
|courier_001 |2026-01-05 11:45:18 |        61.7|




``` r
head(ops$gps) |> kable(digits = 2)
```



|vehicle_id  |ping_at             |   lat|    lon| speed_kmh|
|:-----------|:-------------------|-----:|------:|---------:|
|courier_001 |2026-01-05 06:25:30 | 41.46| -81.54|      28.3|
|courier_001 |2026-01-05 06:34:40 | 41.45| -81.54|      16.6|
|courier_001 |2026-01-05 06:53:54 | 41.45| -81.53|       9.4|
|courier_001 |2026-01-05 07:01:51 | 41.45| -81.52|      19.3|
|courier_001 |2026-01-05 07:01:57 | 41.45| -81.53|      15.1|
|courier_001 |2026-01-05 07:03:59 | 41.45| -81.53|      22.7|




``` r
head(ops$events) |> kable(digits = 2)
```



|entity_id   |time                |event_type         |
|:-----------|:-------------------|:------------------|
|courier_001 |2026-01-05 08:22:36 |delivery_completed |
|courier_001 |2026-01-05 09:26:45 |delivery_completed |
|courier_001 |2026-01-05 11:11:24 |delivery_completed |
|courier_001 |2026-01-05 11:39:49 |delivery_completed |
|courier_001 |2026-01-05 13:15:51 |delivery_completed |
|courier_001 |2026-01-05 13:27:10 |delivery_completed |




``` r
head(ops$shifts) |> kable()
```



|entity_id   |shift_id            |shift_start         |shift_end           |
|:-----------|:-------------------|:-------------------|:-------------------|
|courier_001 |courier_001_shift_1 |2026-01-05 06:00:00 |2026-01-05 14:00:00 |
|courier_001 |courier_001_shift_2 |2026-01-06 06:00:00 |2026-01-06 14:00:00 |
|courier_001 |courier_001_shift_3 |2026-01-07 06:00:00 |2026-01-07 14:00:00 |
|courier_001 |courier_001_shift_4 |2026-01-08 06:00:00 |2026-01-08 14:00:00 |
|courier_001 |courier_001_shift_5 |2026-01-09 06:00:00 |2026-01-09 14:00:00 |
|courier_001 |courier_001_shift_6 |2026-01-10 06:00:00 |2026-01-10 14:00:00 |



Notice that `battery` and `gps` come from different systems and use different
column names: battery has `entity_id` and `time`, while GPS has `vehicle_id`
and `ping_at`. This is typical of real operational data — each source has its
own schema.

The `shifts` table uses real `POSIXct` timestamps — the kind of data you'd
get from a fleet management database. The `time_spec` we pass to fluxPrepare
will convert these to model time (hours from origin) automatically.

## Entity-level splits

The most important rule: **split by entity, not by time**. All shifts belonging
to one courier go into the same split. This prevents information leakage — a
model that has seen courier_003's Monday shift should not be evaluated on
courier_003's Tuesday shift.


``` r
splits <- generate_splits(ops$couriers, train_frac = 0.6, test_frac = 0.2,
                          seed = 123)
splits |> kable()
```



|entity_id   |split      |
|:-----------|:----------|
|courier_001 |test       |
|courier_002 |validation |
|courier_003 |train      |
|courier_004 |test       |
|courier_005 |train      |
|courier_006 |validation |
|courier_007 |train      |
|courier_008 |train      |
|courier_009 |train      |
|courier_010 |train      |
|courier_011 |train      |
|courier_012 |validation |
|courier_013 |validation |
|courier_014 |train      |
|courier_015 |train      |
|courier_016 |validation |
|courier_017 |test       |
|courier_018 |train      |
|courier_019 |train      |
|courier_020 |train      |
|courier_021 |test       |
|courier_022 |train      |
|courier_023 |test       |
|courier_024 |train      |
|courier_025 |test       |
|courier_026 |train      |
|courier_027 |train      |
|courier_028 |train      |
|courier_029 |validation |
|courier_030 |train      |



If you bring your own split table, `prepare_splits()` validates it (unique
entities, valid labels, correct columns). Here we use `generate_splits()`, which
already produces a valid table, so we pass it directly to downstream functions.


``` r
splits_prep <- prepare_splits(splits)
str(splits_prep)
#> Classes 'flux_splits' and 'data.frame':	30 obs. of  2 variables:
#>  $ entity_id: chr  "courier_001" "courier_002" "courier_003" "courier_004" ...
#>  $ split    : chr  "test" "validation" "train" "test" ...
#>  - attr(*, "allowed_splits")= chr [1:3] "train" "test" "validation"
```

## `prepare_events()` — canonical event format

Raw event tables vary in column naming. `prepare_events()` standardizes them
into the format downstream tools expect: `entity_id`, `time`, `event_type`.

The `time_spec` tells fluxPrepare how to convert the `POSIXct` timestamps into
numeric model time. Here, `unit = "hours"` with `origin` set to the fleet's
first shift start — so model time 0 corresponds to the start of shift 1, and
the values come out as small, interpretable hours:


``` r
fleet_origin <- as.POSIXct("2026-01-05 06:00:00", tz = "UTC")
ts <- time_spec(unit = "hours", origin = fleet_origin)

events_prep <- prepare_events(
  events    = ops$events,
  id_col    = "entity_id",
  time_col  = "time",
  type_col  = "event_type",
  time_spec = ts,
  sort      = TRUE
)

head(events_prep) |> kable(digits = 2)
```



|entity_id   | time|event_type         |source_table |
|:-----------|----:|:------------------|:------------|
|courier_001 | 2.38|delivery_completed |NA           |
|courier_001 | 3.45|delivery_completed |NA           |
|courier_001 | 5.19|delivery_completed |NA           |
|courier_001 | 5.66|delivery_completed |NA           |
|courier_001 | 7.26|delivery_completed |NA           |
|courier_001 | 7.45|delivery_completed |NA           |



``` r
cat("Total rows:", nrow(events_prep), "\n")
#> Total rows: 1428
```

The `time` column is now numeric hours from `origin`. If we had omitted the
`origin`, fluxPrepare would default to the Unix epoch (`1970-01-01`), and times
would appear as ~491,000 — correct but unintuitive. Passing a domain-appropriate
origin keeps the numbers readable and aligned with the model's internal clock.

The `source_table` column is `NA` here because we passed a single data frame.
If you pass a named list of event tables (e.g., deliveries from one system and
cancellations from another), each row records which source it came from.

## `prepare_observations()` — canonical observation format

Observations follow the same time conversion, but add a second concept: **specs**.
Our fleet has two observation sources — battery readings and GPS pings — both
per-courier, but from different tracking systems with different column names:

| Source | ID column | Time column | Measurement columns |
|--------|-----------|-------------|---------------------|
| `battery` | `entity_id` | `time` | `battery_pct` |
| `gps` | `vehicle_id` | `ping_at` | `lat`, `lon`, `speed_kmh` |

A **spec** is a small list that tells `prepare_observations()` how to map each
source's columns into the canonical format (`entity_id`, `time`, variables):


``` r
battery_spec <- list(
  id_col   = "entity_id",
  time_col = "time",
  vars     = "battery_pct"
)

gps_spec <- list(
  id_col   = "vehicle_id",
  time_col = "ping_at",
  vars     = c("lat", "lon", "speed_kmh")
)
```

Pass both tables and their specs together. `prepare_observations()` renames
each source's columns to canonical form, converts `POSIXct` → numeric model
time, and row-binds everything. Variables that don't exist in a given source
get `NA` (battery rows have no `lat`; GPS rows have no `battery_pct`):


``` r
obs_prep <- prepare_observations(
  tables    = list(battery = ops$battery, gps = ops$gps),
  specs     = list(battery = battery_spec, gps = gps_spec),
  time_spec = ts,
  sort      = TRUE
)

# One courier's combined timeline: battery + GPS interleaved
obs_prep[obs_prep$entity_id == "courier_001", ] |> head(10) |> kable(digits = 2)
```



|entity_id   | time|group   | battery_pct|   lat|    lon| speed_kmh|source_table |
|:-----------|----:|:-------|-----------:|-----:|------:|---------:|:------------|
|courier_001 | 0.43|gps     |          NA| 41.46| -81.54|      28.3|gps          |
|courier_001 | 0.58|gps     |          NA| 41.45| -81.54|      16.6|gps          |
|courier_001 | 0.90|gps     |          NA| 41.45| -81.53|       9.4|gps          |
|courier_001 | 1.03|gps     |          NA| 41.45| -81.52|      19.3|gps          |
|courier_001 | 1.03|gps     |          NA| 41.45| -81.53|      15.1|gps          |
|courier_001 | 1.07|gps     |          NA| 41.45| -81.53|      22.7|gps          |
|courier_001 | 1.19|battery |        96.9|    NA|     NA|        NA|battery      |
|courier_001 | 1.26|gps     |          NA| 41.45| -81.52|      29.5|gps          |
|courier_001 | 1.36|battery |        96.3|    NA|     NA|        NA|battery      |
|courier_001 | 1.56|gps     |          NA| 41.45| -81.52|      10.1|gps          |



``` r
cat("Total rows:", nrow(obs_prep), "\n")
#> Total rows: 9518
cat("Sources:   ", paste(unique(obs_prep$source_table), collapse = ", "), "\n")
#> Sources:    gps, battery
```

The output is sorted by `entity_id` then `time`, so battery and GPS records for
the same courier are interleaved chronologically. The `source_table` column
tracks provenance — you can always filter back to a single source if needed.

## Two kinds of TTV dataset

The preparation pipeline can build two kinds of train/test/validation datasets,
depending on the modelling question:

| Builder | Question | Anchors from |
|---------|----------|--------------|
| `build_ttv_event_process()` | Will a specific event happen within the next H hours? | Follow-up windows + events |
| `build_ttv_state()` | What will the next observed state look like? | Consecutive observation times |

Both produce interval tables with `t0`, `t1`, `deltat`, and a split label.
The difference is where the intervals come from and what the outcome column
represents.

## Event-process TTV

The question for Tutorial 05 (validation) is: **given a courier's
state at time t₀, what is the probability of a delivery completion within the
next H hours?**

To answer this, we need anchored intervals: for each courier in the test set,
define a start time (t₀), a horizon (H), and record whether the event actually
happened. This is what `build_ttv_event_process()` constructs.

First, define a spec for the event process:


``` r
delivery_ep_spec <- spec_event_process(
  event_types  = "delivery_completed",
  name         = "delivery_completion",
  t0_strategy  = "followup_start",
  fu_start_col = "shift_start",
  fu_end_col   = "shift_end"
)
```

Then build the TTV:


``` r
ttv <- build_ttv_event_process(
  events       = events_prep,
  observations = obs_prep,
  splits       = splits_prep,
  spec         = delivery_ep_spec,
  followup     = ops$shifts,
  time_spec    = ts
)

str(ttv, max.level = 1)
#> 'data.frame':	30 obs. of  8 variables:
#>  $ entity_id     : chr  "courier_001" "courier_002" "courier_003" "courier_004" ...
#>  $ split         : chr  "test" "validation" "train" "test" ...
#>  $ t0            : num  0 0 0 0 0 0 0 0 0 0 ...
#>  $ t1            : num  2.377 0.843 2.447 1.131 1.911 ...
#>  $ deltat        : num  2.377 0.843 2.447 1.131 1.911 ...
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
ttv_test |> kable(digits = 2)
```



|   |entity_id   |split | t0|   t1| deltat|event_occurred |event_type         | censoring_time|
|:--|:-----------|:-----|--:|----:|------:|:--------------|:------------------|--------------:|
|1  |courier_001 |test  |  0| 2.38|   2.38|TRUE           |delivery_completed |              8|
|4  |courier_004 |test  |  0| 1.13|   1.13|TRUE           |delivery_completed |              8|
|17 |courier_017 |test  |  0| 0.69|   0.69|TRUE           |delivery_completed |              8|
|21 |courier_021 |test  |  0| 1.33|   1.33|TRUE           |delivery_completed |              8|
|23 |courier_023 |test  |  0| 3.03|   3.03|TRUE           |delivery_completed |              8|
|25 |courier_025 |test  |  0| 1.05|   1.05|TRUE           |delivery_completed |              8|



Each row is one entity × one follow-up interval. Notice how consecutive rows
for the same courier chain together: the first row's `t1` becomes the next
row's `t0`. Columns: `entity_id`, `t0` (anchor time), `t1` (first event
time or censoring), `deltat` (time to event/censoring), `event_occurred`,
and `censoring_time`.

## Reconstructing state at t₀

To forecast from t₀, the model needs to know the courier's state *at that moment*.
`reconstruct_state_at()` looks backward through the observation history and
recovers the most recent measurement of each variable prior to t₀.


``` r
state_at_t0 <- reconstruct_state_at(
  anchors      = ttv_test,
  observations = obs_prep,
  vars         = "battery_pct",
  time_spec    = ts
)

head(state_at_t0) |> kable(digits = 2)
```



|entity_id   | t0|battery_pct | .time_battery_pct|.prov_battery_pct |
|:-----------|--:|:-----------|-----------------:|:-----------------|
|courier_001 |  0|NA          |                NA|missing           |
|courier_004 |  0|NA          |                NA|missing           |
|courier_017 |  0|NA          |                NA|missing           |
|courier_021 |  0|NA          |                NA|missing           |
|courier_023 |  0|NA          |                NA|missing           |
|courier_025 |  0|NA          |                NA|missing           |



Each row tells you: "for courier X at anchor time t₀, the last observed
battery_pct was Y." This is the starting state you feed to the Engine in
Tutorial 05 when running forecasts from the test set.

## State-transition TTV

Sometimes the question isn't "did an event happen?" but "what does the next
measurement look like?" — for example, predicting the next battery reading
from the current one. `build_ttv_state()` builds intervals from consecutive
observation times in a chosen group, reconstructs predictors at t₀, and
attaches the outcome values observed at t₁.


``` r
ttv_state <- build_ttv_state(
  observations    = obs_prep,
  splits          = splits_prep,
  outcome_group   = "battery",
  outcome_vars    = "battery_pct",
  predictor_vars  = "battery_pct",
  followup        = ops$shifts,
  fu_start_col    = "shift_start",
  fu_end_col      = "shift_end",
  time_spec       = ts
)

str(ttv_state, max.level = 1)
#> Classes 'flux_ttv_state' and 'data.frame':	480 obs. of  11 variables:
#>  $ entity_id        : chr  "courier_001" "courier_001" "courier_001" "courier_001" ...
#>  $ split            : chr  "test" "test" "test" "test" ...
#>  $ t0               : num  1.19 1.36 2.35 2.59 3.16 ...
#>  $ t1               : num  1.36 2.35 2.59 3.16 5.76 ...
#>  $ deltat           : num  0.169 0.988 0.244 0.563 2.6 ...
#>  $ censored         : logi  FALSE FALSE FALSE FALSE FALSE FALSE ...
#>  $ end_type         : chr  "observed" "observed" "observed" "observed" ...
#>  $ battery_pct      : num  96.9 96.3 91.2 91.9 91.3 61.7 61.6 60.9 61.8 61.4 ...
#>  $ .time_battery_pct: num  1.19 1.36 2.35 2.59 3.16 ...
#>  $ .prov_battery_pct: chr  "observed" "observed" "observed" "observed" ...
#>  $ battery_pct.1    : num  96.3 91.2 91.9 91.3 61.7 61.6 60.9 61.8 61.4 51.8 ...
#>  - attr(*, "spec")=List of 13
#>  - attr(*, "metadata")=List of 5
```


``` r
ttv_state_test <- ttv_state[ttv_state$split == "test", ]
head(ttv_state_test, 8) |> kable(digits = 2)
```



|entity_id   |split |   t0|   t1| deltat|censored |end_type | battery_pct| .time_battery_pct|.prov_battery_pct | battery_pct.1|
|:-----------|:-----|----:|----:|------:|:--------|:--------|-----------:|-----------------:|:-----------------|-------------:|
|courier_001 |test  | 1.19| 1.36|   0.17|FALSE    |observed |        96.9|              1.19|observed          |          96.3|
|courier_001 |test  | 1.36| 2.35|   0.99|FALSE    |observed |        96.3|              1.36|observed          |          91.2|
|courier_001 |test  | 2.35| 2.59|   0.24|FALSE    |observed |        91.2|              2.35|observed          |          91.9|
|courier_001 |test  | 2.59| 3.16|   0.56|FALSE    |observed |        91.9|              2.59|observed          |          91.3|
|courier_001 |test  | 3.16| 5.76|   2.60|FALSE    |observed |        91.3|              3.16|observed          |          61.7|
|courier_001 |test  | 5.76| 5.87|   0.11|FALSE    |observed |        61.7|              5.76|observed          |          61.6|
|courier_001 |test  | 5.87| 6.23|   0.36|FALSE    |observed |        61.6|              5.87|observed          |          60.9|
|courier_001 |test  | 6.23| 6.23|   0.00|FALSE    |observed |        60.9|              6.23|observed          |          61.8|



Each row is a consecutive battery → battery interval. The `battery_pct` column
is the predictor (value at t₀); the `outcome_battery_pct` column is the outcome
(value at t₁). Unlike the event-process TTV, there is no separate
`reconstruct_state_at()` call — `build_ttv_state()` does reconstruction
internally.

## Putting it together

The preparation pipeline flow:

```
Raw ops log
  ├── prepare_events()        → canonical events
  ├── prepare_observations()  → canonical obs
  ├── generate_splits()       → entity-level splits
  │
  ├── build_ttv_event_process()  → event intervals + outcomes
  │     └── reconstruct_state_at() → predictors at each t₀
  │
  └── build_ttv_state()          → state-transition intervals
                                    (predictors reconstructed internally)
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
| `spec_event_process()` | Define the event process to model |
| `build_ttv_event_process()` | Event intervals with outcomes, split by TTV |
| `build_ttv_state()` | State-transition intervals with predictors + outcomes |
| `reconstruct_state_at()` | Recover predictor state at each anchor time |

**Next:** [05_validation.md](05_validation.md) — forecast from the test-set
baselines and compare predicted vs observed outcomes using `fluxValidation`.
