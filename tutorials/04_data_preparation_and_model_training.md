Tutorials 01–03 ran the delivery model forward from known starting states.
In practice, the starting states come from **operational data** — sensor logs,
transaction records, GPS pings — that must be cleaned, aligned, and split before
the model can consume them. And the model parameters themselves are typically
**learned from data**, not hand-tuned.

This tutorial introduces `fluxPrepare`: the package that transforms messy
real-world observations into the structured train/test/validation (TTV) format
that the forecast and validation tools expect. We then fit two models from the
TTV datasets and wire them into a ModelBundle. By the end you will be able to:

- generate a synthetic operational log for the delivery fleet,
- prepare observations and events into canonical format,
- split by entity (no data leakage),
- build TTV datasets for event-process and state-transition models,
- join fleet-wide context (weather) to interval-level datasets,
- fit a parametric survival model and a linear regression from TTV data,
- wire fitted models into `propose_events()` and `transition()` closures.

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
3. **Build** (`build_ttv_event_process()`) — produce rows suitable for model
   training, with predictor reconstruction and entity-level
   train/test/validation splits.

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
  n_couriers = 100,
  n_shifts   = 8
)
```

The result has six tables:


``` r
str(ops, max.level = 1)
#> List of 6
#>  $ couriers:'data.frame':	100 obs. of  3 variables:
#>  $ battery :'data.frame':	9986 obs. of  3 variables:
#>  $ gps     :'data.frame':	14887 obs. of  5 variables:
#>  $ events  :'data.frame':	6004 obs. of  3 variables:
#>  $ shifts  :'data.frame':	800 obs. of  4 variables:
#>  $ weather :'data.frame':	201 obs. of  3 variables:
```

- **`$couriers`** — one row per courier: id, vehicle type, home zone.
- **`$battery`** — irregular battery readings (sensor pings per courier).
- **`$gps`** — GPS location pings (from the vehicle tracking system).
- **`$events`** — fleet events: `dispatch_check` and `delivery_completed`.
- **`$shifts`** — shift-level follow-up windows, with real `POSIXct` timestamps.
  Shift durations vary (4, 6, or 8 hours).
- **`$weather`** — fleet-wide hourly weather readings: temperature and
  precipitation type. These are not entity-level observations — they apply
  to the entire fleet and will be joined to TTV datasets later.

Let's look at each:


``` r
head(ops$couriers) |> kable()
```



|entity_id   |vehicle_type |home_zone |
|:-----------|:------------|:---------|
|courier_001 |van          |suburban  |
|courier_002 |van          |urban     |
|courier_003 |ebike        |urban     |
|courier_004 |scooter      |urban     |
|courier_005 |scooter      |rural     |
|courier_006 |scooter      |rural     |




``` r
head(ops$battery) |> kable(digits = 1)
```



|entity_id   |time                | battery_pct|
|:-----------|:-------------------|-----------:|
|courier_001 |2026-01-05 06:05:32 |        88.2|
|courier_001 |2026-01-05 06:17:42 |        88.6|
|courier_001 |2026-01-05 06:33:44 |        89.5|
|courier_001 |2026-01-05 06:46:09 |        89.1|
|courier_001 |2026-01-05 07:57:21 |        85.8|
|courier_001 |2026-01-05 08:14:02 |        85.1|




``` r
head(ops$gps) |> kable(digits = 2)
```



|vehicle_id  |ping_at             |   lat|    lon| speed_kmh|
|:-----------|:-------------------|-----:|------:|---------:|
|courier_001 |2026-01-05 06:13:00 | 41.43| -81.56|       7.8|
|courier_001 |2026-01-05 06:28:33 | 41.43| -81.54|      33.0|
|courier_001 |2026-01-05 06:33:38 | 41.42| -81.55|      22.8|
|courier_001 |2026-01-05 06:33:59 | 41.40| -81.56|       2.3|
|courier_001 |2026-01-05 06:36:01 | 41.41| -81.56|      18.7|
|courier_001 |2026-01-05 07:31:44 | 41.40| -81.56|       4.5|




``` r
head(ops$events) |> kable(digits = 2)
```



|entity_id   |time                |event_type         |
|:-----------|:-------------------|:------------------|
|courier_001 |2026-01-05 07:39:43 |dispatch_check     |
|courier_001 |2026-01-05 07:40:02 |dispatch_check     |
|courier_001 |2026-01-05 08:40:41 |delivery_completed |
|courier_001 |2026-01-05 09:40:08 |delivery_completed |
|courier_001 |2026-01-05 09:48:47 |dispatch_check     |
|courier_001 |2026-01-05 09:50:51 |delivery_completed |




``` r
table(ops$events$event_type)
#> 
#> delivery_completed     dispatch_check 
#>               3013               2991
```


``` r
head(ops$shifts) |> kable()
```



|entity_id   |shift_id            |shift_start         |shift_end           |
|:-----------|:-------------------|:-------------------|:-------------------|
|courier_001 |courier_001_shift_1 |2026-01-05 06:00:00 |2026-01-05 14:00:00 |
|courier_001 |courier_001_shift_2 |2026-01-06 02:00:00 |2026-01-06 06:00:00 |
|courier_001 |courier_001_shift_3 |2026-01-07 06:00:00 |2026-01-07 14:00:00 |
|courier_001 |courier_001_shift_4 |2026-01-08 06:00:00 |2026-01-08 14:00:00 |
|courier_001 |courier_001_shift_5 |2026-01-09 06:00:00 |2026-01-09 14:00:00 |
|courier_001 |courier_001_shift_6 |2026-01-09 20:00:00 |2026-01-10 02:00:00 |




``` r
head(ops$weather) |> kable(digits = 1)
```



|time                | temperature_c|precip_type |
|:-------------------|-------------:|:-----------|
|2026-01-05 06:00:00 |          -2.6|none        |
|2026-01-05 07:00:00 |          -2.2|none        |
|2026-01-05 08:00:00 |          -2.0|none        |
|2026-01-05 09:00:00 |          -0.6|none        |
|2026-01-05 10:00:00 |           0.2|none        |
|2026-01-05 11:00:00 |           1.5|none        |



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
table(splits$split)
#> 
#>       test      train validation 
#>         20         60         20
```

If you bring your own split table, `prepare_splits()` validates it (unique
entities, valid labels, correct columns). Here we use `generate_splits()`, which
already produces a valid table, so we pass it directly to downstream functions.


``` r
splits_prep <- prepare_splits(splits)
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
|courier_001 | 1.66|dispatch_check     |NA           |
|courier_001 | 1.67|dispatch_check     |NA           |
|courier_001 | 2.68|delivery_completed |NA           |
|courier_001 | 3.67|delivery_completed |NA           |
|courier_001 | 3.81|dispatch_check     |NA           |
|courier_001 | 3.85|delivery_completed |NA           |



``` r
cat("Total rows:", nrow(events_prep), "\n")
#> Total rows: 6004
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
|courier_001 | 0.09|battery |        88.2|    NA|     NA|        NA|battery      |
|courier_001 | 0.22|gps     |          NA| 41.43| -81.56|       7.8|gps          |
|courier_001 | 0.30|battery |        88.6|    NA|     NA|        NA|battery      |
|courier_001 | 0.48|gps     |          NA| 41.43| -81.54|      33.0|gps          |
|courier_001 | 0.56|gps     |          NA| 41.42| -81.55|      22.8|gps          |
|courier_001 | 0.56|battery |        89.5|    NA|     NA|        NA|battery      |
|courier_001 | 0.57|gps     |          NA| 41.40| -81.56|       2.3|gps          |
|courier_001 | 0.60|gps     |          NA| 41.41| -81.56|      18.7|gps          |
|courier_001 | 0.77|battery |        89.1|    NA|     NA|        NA|battery      |
|courier_001 | 1.53|gps     |          NA| 41.40| -81.56|       4.5|gps          |



``` r
cat("Total rows:", nrow(obs_prep), "\n")
#> Total rows: 24873
cat("Sources:   ", paste(unique(obs_prep$source_table), collapse = ", "), "\n")
#> Sources:    battery, gps
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

## Event-process TTV → `delivery_mod`

The basic flux model loop is:

1. **Generate the next event** — draw from a time-to-event model.
2. **Check for decisions** — if the event is a decision point, take action.
3. **Update entity state** — advance the entity to the event time and update the values of its state variables.
4. **Check state-triggered decisions** — if the new state triggers a rule, act.
5. Go back to (1).

flux supports multiple, concurrent event processes — a courier might
simultaneously be waiting for its next delivery and its next battery reading.
Each process needs a probabilistic model that answers: *given the entity's
current state, when does the next event happen?*

The `spec_event_process()` and `build_ttv_event_process()` functions in
`fluxPrepare` exist to ease the process of training these probabilistic
time-to-event models. They transform raw operational data into the
interval-censored format that survival models expect. When you specify
`predictor_vars` in the spec, the builder reconstructs covariate values at
each interval's t₀ automatically — no separate reconstruction step needed.

### Defining the event-process spec

The question for the delivery process: **given a courier's state at time t₀,
what is the probability of a delivery completion within the next H hours?**

To answer this, we need anchored intervals: for each courier, define a start
time (t₀), a horizon (H), and record whether the event actually happened. This
is what `build_ttv_event_process()` constructs.

First, define a spec for the event process. The `split_on_groups = "battery"`
argument tells the builder to segment follow-up at battery observation times —
creating a new interval each time a fresh battery reading arrives. This produces
richer training data with time-varying covariates.

The `predictor_vars` argument tells the builder to reconstruct `battery_pct` at
each interval's t₀ using `reconstruct_state_at()` internally. Setting
`row_policy = "drop_incomplete"` drops intervals where reconstruction returns
`NA` (e.g., the first interval before any battery reading arrives):


``` r
delivery_ep_spec <- spec_event_process(
  event_types     = "delivery_completed",
  name            = "delivery_completion",
  t0_strategy     = "followup_start",
  fu_start_col    = "shift_start",
  fu_end_col      = "shift_end",
  split_on_groups = "battery",
  predictor_vars  = "battery_pct",
  row_policy      = "drop_incomplete"
)
```

### Building the event-process TTV

The follow-up table defines each entity's observation window. We collapse the
per-shift records into a single window per entity — earliest shift start to
latest shift end:


``` r
entity_followup <- ops$shifts |>
  group_by(entity_id) |>
  summarise(shift_start = min(shift_start),
            shift_end   = max(shift_end),
            .groups     = "drop") |>
  as.data.frame()

head(entity_followup) |> kable()
```



|entity_id   |shift_start         |shift_end           |
|:-----------|:-------------------|:-------------------|
|courier_001 |2026-01-05 06:00:00 |2026-01-11 06:00:00 |
|courier_002 |2026-01-05 06:00:00 |2026-01-12 14:00:00 |
|courier_003 |2026-01-05 06:00:00 |2026-01-11 14:00:00 |
|courier_004 |2026-01-05 06:00:00 |2026-01-11 22:00:00 |
|courier_005 |2026-01-05 06:00:00 |2026-01-11 22:00:00 |
|courier_006 |2026-01-05 06:00:00 |2026-01-11 14:00:00 |



Now build the TTV:


``` r
delivery_mod <- build_ttv_event_process(
  events       = events_prep,
  observations = obs_prep,
  splits       = splits_prep,
  spec         = delivery_ep_spec,
  followup     = entity_followup,
  time_spec    = ts
)

cat("Rows:", nrow(delivery_mod), "\n")
#> Rows: 417
cat("Intervals per entity:", range(table(delivery_mod$entity_id)), "\n")
#> Intervals per entity: 1 20
```

Each row is one entity × one interval. The `split_on_groups = "battery"`
argument created multiple intervals per entity, segmented at battery
observation times. `event_occurred` is TRUE for the interval containing
the event, FALSE for all preceding intervals.

Because we specified `predictor_vars = "battery_pct"` in the spec, the builder
automatically reconstructed battery state at each interval's t₀. And because
we set `row_policy = "drop_incomplete"`, intervals before the first battery
reading (where reconstruction would return `NA`) were already removed:


``` r
cat("Rows:", nrow(delivery_mod), "\n")
#> Rows: 417
head(delivery_mod) |> kable(digits = 2)
```



|entity_id   |split      |   t0|   t1| deltat|event_occurred |event_type         | censoring_time| battery_pct|
|:-----------|:----------|----:|----:|------:|:--------------|:------------------|--------------:|-----------:|
|courier_001 |validation | 0.09| 0.30|   0.20|FALSE          |NA                 |            144|        88.2|
|courier_001 |validation | 0.30| 0.56|   0.27|FALSE          |NA                 |            144|        88.6|
|courier_001 |validation | 0.56| 0.77|   0.21|FALSE          |NA                 |            144|        89.5|
|courier_001 |validation | 0.77| 1.96|   1.19|FALSE          |NA                 |            144|        89.1|
|courier_001 |validation | 1.96| 2.23|   0.28|FALSE          |NA                 |            144|        85.8|
|courier_001 |validation | 2.23| 2.68|   0.44|TRUE           |delivery_completed |            144|        85.1|



## State-transition TTV → `battery_mod`

Step 3 of the model loop — *update entity state at the new event time* —
requires a model that predicts the next observed value of a state variable
given the current value and elapsed time. For battery level, the question is:
*given battery_pct at time t₀, what will it be at the next observation t₁?*

`build_ttv_state()` constructs intervals from consecutive observation times in
a chosen group, reconstructs predictors at t₀, and attaches the outcome values
observed at t₁:


``` r
battery_mod <- build_ttv_state(
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
```


``` r
head(battery_mod) |> kable(digits = 2)
```



|entity_id   |split      |   t0|   t1| deltat|censored |end_type | battery_pct| outcome_battery_pct|
|:-----------|:----------|----:|----:|------:|:--------|:--------|-----------:|-------------------:|
|courier_001 |validation | 0.09| 0.30|   0.20|FALSE    |observed |        88.2|                88.6|
|courier_001 |validation | 0.30| 0.56|   0.27|FALSE    |observed |        88.6|                89.5|
|courier_001 |validation | 0.56| 0.77|   0.21|FALSE    |observed |        89.5|                89.1|
|courier_001 |validation | 0.77| 1.96|   1.19|FALSE    |observed |        89.1|                85.8|
|courier_001 |validation | 1.96| 2.23|   0.28|FALSE    |observed |        85.8|                85.1|
|courier_001 |validation | 2.23| 2.75|   0.51|FALSE    |observed |        85.1|                86.5|



Each row is a consecutive battery → battery interval. `battery_pct` is the
predictor (value at t₀); `outcome_battery_pct` is the outcome (value at t₁).
Both `build_ttv_event_process()` and `build_ttv_state()` handle predictor
reconstruction internally when `predictor_vars` is specified in the spec.

## Joining fleet-wide context: weather

Not everything is entity-level observation data. Fleet-wide context like
weather applies to all couriers simultaneously and is joined to TTV intervals
based on timestamps, not through `prepare_observations()`.

We convert weather timestamps to model time, then use an inequality join to
attach the most recent weather reading at or before each interval's t₀:


``` r
weather_mod <- ops$weather |>
  mutate(weather_time = as.numeric(difftime(time, fleet_origin, units = "hours"))) |>
  select(weather_time, temperature_c, precip_type)
```

Before the join, the delivery TTV has only the event-process columns plus
battery state:


``` r
head(delivery_mod) |> kable(digits = 2)
```



|entity_id   |split      |   t0|   t1| deltat|event_occurred |event_type         | censoring_time| battery_pct|
|:-----------|:----------|----:|----:|------:|:--------------|:------------------|--------------:|-----------:|
|courier_001 |validation | 0.09| 0.30|   0.20|FALSE          |NA                 |            144|        88.2|
|courier_001 |validation | 0.30| 0.56|   0.27|FALSE          |NA                 |            144|        88.6|
|courier_001 |validation | 0.56| 0.77|   0.21|FALSE          |NA                 |            144|        89.5|
|courier_001 |validation | 0.77| 1.96|   1.19|FALSE          |NA                 |            144|        89.1|
|courier_001 |validation | 1.96| 2.23|   0.28|FALSE          |NA                 |            144|        85.8|
|courier_001 |validation | 2.23| 2.68|   0.44|TRUE           |delivery_completed |            144|        85.1|



Join weather to both datasets:


``` r
delivery_mod <- delivery_mod |>
  left_join(weather_mod, join_by(closest(t0 >= weather_time))) |>
  select(-weather_time) |>
  mutate(
    precip_rain = as.integer(precip_type == "rain"),
    precip_snow = as.integer(precip_type == "snow")
  )

battery_mod <- battery_mod |>
  left_join(weather_mod, join_by(closest(t0 >= weather_time))) |>
  select(-weather_time)
```

After the join, each row carries the weather conditions at its anchor time:


``` r
head(delivery_mod) |> kable(digits = 2)
```



|entity_id   |split      |   t0|   t1| deltat|event_occurred |event_type         | censoring_time| battery_pct| temperature_c|precip_type | precip_rain| precip_snow|
|:-----------|:----------|----:|----:|------:|:--------------|:------------------|--------------:|-----------:|-------------:|:-----------|-----------:|-----------:|
|courier_001 |validation | 0.09| 0.30|   0.20|FALSE          |NA                 |            144|        88.2|          -2.6|none        |           0|           0|
|courier_001 |validation | 0.30| 0.56|   0.27|FALSE          |NA                 |            144|        88.6|          -2.6|none        |           0|           0|
|courier_001 |validation | 0.56| 0.77|   0.21|FALSE          |NA                 |            144|        89.5|          -2.6|none        |           0|           0|
|courier_001 |validation | 0.77| 1.96|   1.19|FALSE          |NA                 |            144|        89.1|          -2.6|none        |           0|           0|
|courier_001 |validation | 1.96| 2.23|   0.28|FALSE          |NA                 |            144|        85.8|          -2.2|none        |           0|           0|
|courier_001 |validation | 2.23| 2.68|   0.44|TRUE           |delivery_completed |            144|        85.1|          -2.0|none        |           0|           0|




``` r
head(battery_mod) |> kable(digits = 2)
```



|entity_id   |split      |   t0|   t1| deltat|censored |end_type | battery_pct| outcome_battery_pct| temperature_c|precip_type |
|:-----------|:----------|----:|----:|------:|:--------|:--------|-----------:|-------------------:|-------------:|:-----------|
|courier_001 |validation | 0.09| 0.30|   0.20|FALSE    |observed |        88.2|                88.6|          -2.6|none        |
|courier_001 |validation | 0.30| 0.56|   0.27|FALSE    |observed |        88.6|                89.5|          -2.6|none        |
|courier_001 |validation | 0.56| 0.77|   0.21|FALSE    |observed |        89.5|                89.1|          -2.6|none        |
|courier_001 |validation | 0.77| 1.96|   1.19|FALSE    |observed |        89.1|                85.8|          -2.6|none        |
|courier_001 |validation | 1.96| 2.23|   0.28|FALSE    |observed |        85.8|                85.1|          -2.2|none        |
|courier_001 |validation | 2.23| 2.75|   0.51|FALSE    |observed |        85.1|                86.5|          -2.0|none        |



## Train / test split

Now that both datasets are fully assembled, split into train and test sets.
Because the `split` column was set at the entity level, this is a simple
subset — no repeated join code needed:


``` r
delivery_mod_train <- delivery_mod[delivery_mod$split == "train", ]
delivery_mod_test  <- delivery_mod[delivery_mod$split == "test", ]
cat("Delivery — train:", nrow(delivery_mod_train), " test:", nrow(delivery_mod_test), "\n")
#> Delivery — train: 232  test: 102

battery_mod_train <- battery_mod[battery_mod$split == "train", ]
battery_mod_test  <- battery_mod[battery_mod$split == "test", ]
cat("Battery  — train:", nrow(battery_mod_train), " test:", nrow(battery_mod_test), "\n")
#> Battery  — train: 744  test: 280
```

# Part 2: Model Training

With TTV datasets in hand, we can fit models directly from data rather than
hand-tuning parameters. We'll train two models:

1. A **parametric survival model** for time-to-delivery-completion.
2. A **linear regression** for battery state transition.

Then we **burgle** each fitted object down to its prediction-relevant
components, and wire the lightweight result into `propose_events()` and
`transition()` closures — the same interface the Engine expects.

## Survival model: time to delivery completion

An exponential survival model estimates the rate at which deliveries complete
as a function of covariates. We use `flexsurv::flexsurvreg()` rather than
`survival::survreg()` because `flexsurv` objects are directly supported by
`burgle()`.

The exponential distribution matches what the Engine uses internally
(`rexp(1, rate)` in `propose_events()`), so the fitted rate translates
directly to event proposals.


``` r
delivery_fit <- flexsurvreg(
  Surv(deltat, event_occurred) ~ battery_pct + temperature_c + precip_rain,
  data = delivery_mod_train,
  dist = "exponential"
)

delivery_fit
#> Call:
#> flexsurvreg(formula = Surv(deltat, event_occurred) ~ battery_pct + 
#>     temperature_c + precip_rain, data = delivery_mod_train, dist = "exponential")
#> 
#> Estimates: 
#>                data mean  est      L95%     U95%     se       exp(est)  L95%   
#> rate                NA     6.4790   0.4863  86.3153   8.5599       NA        NA
#> battery_pct    92.1073    -0.0369  -0.0609  -0.0129   0.0122   0.9638    0.9409
#> temperature_c  -2.4116    -0.3915  -0.9022   0.1192   0.2606   0.6760    0.4057
#> precip_rain     0.0474    -1.2799  -3.4237   0.8638   1.0937   0.2781    0.0326
#>                U95%   
#> rate                NA
#> battery_pct     0.9872
#> temperature_c   1.1266
#> precip_rain     2.3721
#> 
#> N = 232,  Events: 49,  Censored: 183
#> Total time at risk: 99.08358
#> Log-likelihood = -77.42814, df = 4
#> AIC = 162.8563
```

The coefficients are on the log-rate scale. Higher battery levels are
associated with faster deliveries (positive coefficient → higher rate).
Temperature and precipitation effects reflect the weather patterns embedded
in the data generator.

## Linear regression: battery state transition

A linear model predicting the next battery reading from the current one, plus
temperature and interval duration:


``` r
battery_fit <- lm(
  outcome_battery_pct ~ battery_pct + temperature_c + deltat + temperature_c:deltat,
  data = battery_mod_train
)

summary(battery_fit)
#> 
#> Call:
#> lm(formula = outcome_battery_pct ~ battery_pct + temperature_c + 
#>     deltat + temperature_c:deltat, data = battery_mod_train)
#> 
#> Residuals:
#>     Min      1Q  Median      3Q     Max 
#> -35.535  -0.148   1.068   2.354  12.372 
#> 
#> Coefficients:
#>                      Estimate Std. Error t value Pr(>|t|)    
#> (Intercept)           0.59931    0.91937   0.652    0.515    
#> battery_pct           0.98714    0.01300  75.913   <2e-16 ***
#> temperature_c        -0.01699    0.18878  -0.090    0.928    
#> deltat               -5.39325    0.63448  -8.500   <2e-16 ***
#> temperature_c:deltat  0.27136    0.30408   0.892    0.372    
#> ---
#> Signif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1
#> 
#> Residual standard error: 5.321 on 679 degrees of freedom
#>   (60 observations deleted due to missingness)
#> Multiple R-squared:  0.936,	Adjusted R-squared:  0.9357 
#> F-statistic:  2484 on 4 and 679 DF,  p-value: < 2.2e-16
```

The `temperature_c:deltat` interaction captures the key mechanism: colder
weather drains battery faster, and the effect accumulates over longer intervals.

## Stripping models with burgle

Fitted model objects in R carry baggage: the original training data, residuals,
QR decompositions, call environments. An `lm` fit on a few hundred rows
already weighs in at tens of kilobytes; a `flexsurvreg` object at hundreds.
None of that matters for prediction — you only need the coefficients and enough
structure to build a model matrix from new data.

The [burgle](https://github.com/ClevelandClinicQHS/burgle) package strips a
fitted model down to exactly what `predict()` needs and nothing more:


``` r
delivery_lean <- burgle(delivery_fit)
battery_lean  <- burgle(battery_fit)
```

How much did we save?


``` r
cat("delivery_fit:", format(object.size(delivery_fit), units = "auto"), "\n")
#> delivery_fit: 273.6 Kb
cat("delivery_lean:", format(object.size(delivery_lean), units = "auto"), "\n")
#> delivery_lean: 6.8 Kb
cat("\n")
cat("battery_fit:", format(object.size(battery_fit), units = "auto"), "\n")
#> battery_fit: 229.9 Kb
cat("battery_lean:", format(object.size(battery_lean), units = "auto"), "\n")
#> battery_lean: 3.4 Kb
```

The burgled objects are typically **~50× smaller**. They implement the same
`predict()` interface, so downstream code doesn't change:


``` r
# Verify burgled predictions match the original coefficients
nd_delivery <- delivery_mod_test[1:3, c("battery_pct", "temperature_c", "precip_rain")]
lp_lean <- as.numeric(predict(delivery_lean, newdata = nd_delivery, type = "lp"))

# Manual calculation from original coefficients (excluding intercept)
coefs <- coef(delivery_fit)
lp_manual <- as.numeric(as.matrix(nd_delivery) %*% coefs[names(nd_delivery)])

cat("Max prediction difference:", max(abs(lp_lean - lp_manual)), "\n")
#> Max prediction difference: 0
```

This matters for two reasons:

1. **Serialization** — when you save a `ModelBundle` to disk (e.g., for
   deployment or `fluxOrchestrate`), the burgled object serializes in kilobytes
   instead of megabytes.
2. **Memory at scale** — running 10,000 entities × 100 Monte Carlo draws means
   the model object is accessed millions of times. Smaller objects mean less
   pressure on R's garbage collector.

## Wiring models into a ModelBundle

In Tutorial 01, `propose_events()` and `transition()` were hand-coded. Here
we wire *burgled* models into the same interface. Each function is a closure
that captures the lean model object in its environment:

### propose_events: delivery rate from survival model

The burgled `flexsurvreg` object provides the covariate contribution via
`predict(type = "lp")`. To reconstruct the full rate, we also need the
baseline rate intercept from the original fit. We capture it once alongside the
lean model:


``` r
delivery_rate_intercept <- coef(delivery_fit)["rate"]
```


``` r
propose_delivery <- function(entity, param_ctx = NULL, process_ids = NULL,
                             current_proposals = NULL) {
  t_now <- entity$last_time
  s <- entity$as_list(c("battery_pct"))

  newdata <- data.frame(
    battery_pct   = as.numeric(s$battery_pct),
    temperature_c = 2,     # would come from weather context in production
    precip_rain   = 0L
  )

  # burgled flexsurvreg: predict(type="lp") returns covariate contribution
  # Rate = exp(rate_intercept + lp)
  lp <- as.numeric(predict(delivery_lean, newdata = newdata, type = "lp"))
  rate <- exp(delivery_rate_intercept + lp)

  list(
    delivery = list(
      time_next  = t_now + stats::rexp(1, rate = max(1e-6, rate)),
      event_type = "delivery_completed"
    )
  )
}
```

### transition: battery update from linear model


``` r
transition_battery <- function(entity, event, param_ctx = NULL) {
  s <- entity$as_list(c("battery_pct"))
  battery_now <- as.numeric(s$battery_pct)
  deltat <- entity$last_time - entity$events$time[max(1, nrow(entity$events) - 1)]

  newdata <- data.frame(
    battery_pct   = battery_now,
    temperature_c = 2,  # would come from weather context in production
    deltat        = max(0.01, as.numeric(deltat))
  )

  # burgled lm: predict() returns the same values as the original
  predicted <- as.numeric(predict(battery_lean, newdata = newdata))
  noisy <- predicted + stats::rnorm(1, 0, 0.5)

  list(battery_pct = max(0, min(100, noisy)))
}
```

These closures capture `delivery_lean` and `battery_lean` — not the full
fitted objects. The lean objects carry only coefficients and factor-level
metadata, so they serialize cleanly and consume minimal memory inside the
Engine's inner loop.

## Putting it together

The full pipeline from raw data to trained model:

```
Raw ops log (couriers, battery, gps, events, shifts, weather)
  ├── prepare_events()        → canonical events
  ├── prepare_observations()  → canonical obs
  ├── generate_splits()       → entity-level splits
  │
  ├── build_ttv_event_process()  → delivery_mod (event intervals + battery_pct)
  │     ├── left_join(weather)     → temperature, precip
  │     ├── flexsurvreg()          → delivery_fit
  │     └── burgle()               → delivery_lean → propose_delivery()
  │
  └── build_ttv_state()          → battery_mod (state intervals)
        ├── left_join(weather)     → temperature
        ├── lm()                   → battery_fit
        └── burgle()               → battery_lean → transition_battery()
```

## Summary

| Function | Purpose |
|----------|---------|
| `generate_delivery_log()` | Synthetic data generator (model + weather + variable shifts) |
| `generate_splits()` | Entity-level train/test/validation split |
| `prepare_events()` | Standardize event table columns |
| `prepare_observations()` | Standardize observation tables with specs |
| `spec_event_process()` | Define the event process to model |
| `build_ttv_event_process()` | Event intervals with outcomes and reconstructed predictors |
| `build_ttv_state()` | State-transition intervals with predictors + outcomes |
| `flexsurvreg()` / `lm()` | Fit models from TTV training data |
| `burgle()` | Strip fitted models to prediction-relevant components |

**Next:** [05_validation.md](05_validation.md) — forecast from the test-set
baselines and compare predicted vs observed outcomes using `fluxValidation`.
