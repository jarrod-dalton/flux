

``` r
## Maturity: draft
```

![plot of chunk figure-anchors-intervals](figure/figure-anchors-intervals-1.png)

``` r
ehr <- fluxASCVD:::ascvd_make_example_ehr(n_entities = 50, seed = 123)

```


Table: Patients (one row per entity)

| entity_id|index_date |sex |
|---------:|:----------|:---|
|         1|2019-02-19 |M   |
|         2|2019-04-08 |F   |



Table: Labs (LDL/HDL) for two example entities

| entity_id|obs_date   | ldl| hdl|
|---------:|:----------|---:|---:|
|         1|2019-08-02 | 138|  59|
|         1|2022-03-03 | 141|  71|
|         1|2024-04-03 | 131|  45|
|         2|2024-09-09 | 112|  60|
|         2|2027-02-06 | 113|  47|



Table: Vitals (SBP/DBP) for two example entities

| entity_id|obs_date   | sbp| dbp|
|---------:|:----------|---:|---:|
|         1|2019-05-05 | 138|  85|
|         1|2020-01-27 | 125|  88|
|         1|2021-01-21 | 131|  92|
|         1|2021-09-05 | 132|  89|
|         1|2022-07-03 | 123|  84|
|         2|2019-04-09 | 136|  90|
|         2|2020-05-11 | 124|  80|
|         2|2021-12-13 | 128|  86|
|         2|2023-11-30 | 135|  86|
|         2|2025-04-19 | 137|  92|
|         2|2026-06-29 | 116|  82|
|         2|2027-03-22 | 131|  88|



Table: Clinical events for two example entities

|    | entity_id|event_date |event           |
|:---|---------:|:----------|:---------------|
|116 |         1|2022-04-02 |death           |
|1   |         1|2023-04-04 |office_visit    |
|2   |         2|2021-03-04 |hospitalization |



Table: Medications for two example entities

| entity_id|start_date |medication    |
|---------:|:----------|:-------------|
|         1|2021-02-06 |statin        |
|         2|2019-04-27 |ace_inhibitor |
|         2|2021-10-08 |beta_blocker  |



``` r
ctx <- fluxCore::set_time_unit(
  ctx = list(),
  unit = "weeks"
)
#> Error: 'set_time_unit' is not an exported object from 'namespace:fluxCore'

example_ids <- head(ehr$entities$entity_id, 2)

```

``` r
library(fluxPrepare)

```

``` r
obs <- prepare_observations(
  tables = list(
    labs   = ehr$labs,
    vitals = ehr$vitals
  ),
  specs = list(
    labs = list(
      id_col   = "entity_id",
      time_col = "obs_date",
      vars     = c("ldl", "hdl"),
      group    = "labs"
    ),
    vitals = list(
      id_col   = "entity_id",
      time_col = "obs_date",
      vars     = c("sbp", "dbp"),
      group    = "vitals"
    )
  ),
  ctx = ctx
)
#> Error: object 'ctx' not found

obs |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(10) |>
  knitr::kable()
#> Error: object 'obs' not found
```

``` r
events <- prepare_events(
  events    = ehr$events,
  id_col    = "entity_id",
  time_col  = "event_date",
  type_col  = "event",
  ctx       = ctx
)
#> Error: object 'ctx' not found

events |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(10) |>
  knitr::kable()
#> Error: object 'events' not found
```

``` r
set.seed(1)

splits_raw <- data.frame(
  entity_id = ehr$entities$entity_id,
  split = sample(
    c("train", "test", "validation"),
    size = nrow(ehr$entities),
    replace = TRUE,
    prob = c(0.70, 0.15, 0.15)
  ),
  stringsAsFactors = FALSE
)

splits <- prepare_splits(splits_raw)

splits |>
  head(6) |>
  knitr::kable()
```



|entity_id |split |
|:---------|:-----|
|1         |train |
|2         |train |
|3         |train |
|4         |test  |
|5         |train |
|6         |test  |



``` r
fu_obs <- obs |>
  dplyr::group_by(entity_id) |>
  dplyr::summarize(t_obs_min = min(time), .groups = "drop")
#> Error: object 'obs' not found

fu_evt <- events |>
  dplyr::group_by(entity_id) |>
  dplyr::summarize(t_evt_min = min(time), .groups = "drop")
#> Error: object 'events' not found

fu_death <- events |>
  dplyr::filter(event_type == "death") |>
  dplyr::group_by(entity_id) |>
  dplyr::summarize(death_time = min(time), .groups = "drop")
#> Error: object 'events' not found

followup <- splits |>
  dplyr::select(entity_id) |>
  dplyr::left_join(fu_obs, by = "entity_id") |>
  dplyr::left_join(fu_evt, by = "entity_id") |>
  dplyr::mutate(
    followup_start = pmin(t_obs_min, t_evt_min, na.rm = TRUE),
    followup_end   = followup_start + (9 * 52)
  ) |>
  dplyr::left_join(fu_death, by = "entity_id") |>
  dplyr::select(entity_id, followup_start, followup_end, death_time)
#> Error: object 'fu_obs' not found

followup |>
  dplyr::filter(entity_id %in% example_ids) |>
  knitr::kable()
#> Error: object 'followup' not found
```

``` r
event_settings <- spec_event_process(
  event_types     = c("MI", "stroke", "death"),
  split_on_groups = "vitals",
  segment_on_vars = "sbp",
  segment_rules   = segment_bins(sbp = c(-Inf, 120, 140, Inf)),
  candidate_times = "groups_or_vars",
  t0_strategy     = "followup_start",
  death_col       = "death_time"
)

event_settings
#> $task
#> [1] "event_process"
#> 
#> $name
#> NULL
#> 
#> $event_types
#> [1] "MI"     "stroke" "death" 
#> 
#> $split_on_groups
#> [1] "vitals"
#> 
#> $segment_on_vars
#> [1] "sbp"
#> 
#> $segment_rules
#> $bins
#> $bins$sbp
#> [1] -Inf  120  140  Inf
#> 
#> 
#> attr(,"class")
#> [1] "segment_rules"
#> 
#> $candidate_times
#> [1] "groups_or_vars"
#> 
#> $min_dt
#> [1] 0
#> 
#> $t0_strategy
#> [1] "followup_start"
#> 
#> $fixed_t0
#> [1] 0
#> 
#> $fu_start_col
#> [1] "followup_start"
#> 
#> $fu_end_col
#> [1] "followup_end"
#> 
#> $death_col
#> [1] "death_time"
#> 
#> attr(,"class")
#> [1] "spec_event_process" "flux_spec"
```

``` r
ttv_major <- build_ttv_event_process(
  events       = events,
  observations = obs,
  splits       = splits,
  spec         = event_settings,
  followup     = followup,
  ctx          = ctx
)
#> Error: object 'events' not found

ttv_major |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(12) |>
  knitr::kable()
#> Error: object 'ttv_major' not found
```

``` r
anchors <- ttv_major |>
  dplyr::select(entity_id, t0)
#> Error: object 'ttv_major' not found

state_t0 <- reconstruct_state_at(
  anchors      = anchors,
  observations = obs,
  vars         = c("sbp", "dbp", "ldl", "hdl"),
  lookback     = 52,
  staleness    = 52
)
#> Error: anchors must be a data.frame.

ttv_major_cov <- ttv_major |>
  dplyr::left_join(
    state_t0 |>
      dplyr::select(entity_id, t0, sbp, dbp, ldl, hdl),
    by = c("entity_id", "t0")
  )
#> Error: object 'ttv_major' not found

ttv_major_cov |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(8) |>
  knitr::kable()
#> Error: object 'ttv_major_cov' not found
```

``` r
ttv_bp <- build_ttv_state(
  observations   = obs,
  splits         = splits,
  outcome_group  = "vitals",
  outcome_vars   = c("sbp", "dbp"),
  predictor_vars = c("sbp", "dbp", "ldl", "hdl"),
  followup       = followup,
  death_col      = "death_time",
  lookback       = 52,    ### these are defined in the 
  staleness      = 52,    ### model's time_unit (weeks)
  row_policy     = "drop_incomplete"
)
#> Error: object 'obs' not found

ttv_bp |>
  dplyr::filter(entity_id %in% example_ids) |>
  head(10) |>
  knitr::kable()
#> Error: object 'ttv_bp' not found
```

