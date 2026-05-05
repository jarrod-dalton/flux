This tutorial shows how to go from a single-entity simulation (Tutorial 01) to
**cohort-level forecasting** across many independent entities. This is not an
agent-based model (ABM): couriers do not interact with each other here. A
future ABM tutorial will cover interacting entities and shared environments.

By the end you will be able to:
- build a heterogeneous cohort of couriers,
- run the cohort through an 8-hour shift,
- generate probabilistic forecasts of delivery events and battery state,
- summarize aggregate fleet outcomes (for example, total deliveries over the shift).

We use the urban food delivery model throughout. If you haven't worked through
[01_core_engine_scaffold.md](01_core_engine_scaffold.md), start there — it
covers the `Entity`, `ModelBundle`, and `Engine` concepts that this tutorial
builds on.

## Load the model

The delivery model lives in a plain R script. Sourcing it gives you
`delivery_bundle()`, `delivery_schema()`, and the individual callback functions.
No package install required.


``` r
source("tutorials/model/urban_delivery.R")
```

## Build a heterogeneous cohort

A **cohort** is just a named list of `Entity` objects. Each agent starts its
shift with a different battery level, home zone, and starting state — exactly
the kind of heterogeneity you see in a real fleet.

This is also where you can plug in a synthetic population generator if you have
one. For example, you might sample initial state from external population
distributions, then instantiate one `Entity` per sampled courier profile.


``` r
set.seed(2026)

n_couriers <- 50
shared_schema <- delivery_schema()

couriers <- lapply(seq_len(n_couriers), function(i) {
  Entity$new(
    id   = paste0("courier_", sprintf("%02d", i)),
    init = list(
      battery_pct   = runif(1, min = 50, max = 100),
      route_zone    = sample(c("urban", "suburban", "rural"), 1,
                             prob = c(0.55, 0.30, 0.15)),
      payload_kg    = 0,
      dispatch_mode = "idle"
    ),
    schema      = shared_schema,
    entity_type = "courier",
    time0       = 0
  )
})
names(couriers) <- sapply(couriers, function(e) e$id)
```

Quick sanity check — the fleet's starting battery distribution:


``` r
batteries <- map_dbl(couriers, ~ .x$current$battery_pct)
summary(batteries)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>   50.27   61.88   76.06   74.95   86.46   98.59
```

## Single-agent run

Before running the full cohort, let's step through one courier to see the shape
of the output. The `Engine` is constructed once from the bundle and then reused
for every courier.

`Entity` objects use R6 reference semantics: `eng$run()` mutates the entity
in-place, advancing its internal clock to the end of the shift. To keep the
`couriers` list pristine for the cohort run below, we create a fresh copy of
courier_01 just for this demo.


``` r
eng <- Engine$new(bundle = delivery_bundle())

courier_01_demo <- Entity$new(
  id          = "courier_01",
  init        = couriers[["courier_01"]]$current,
  schema      = shared_schema,
  entity_type = "courier",
  time0       = 0
)

out_single <- eng$run(courier_01_demo, max_events = 500, return_observations = TRUE)
```

The result contains:
- `$events` — the authoritative event log (one row per realized event)
- `$observations` — whatever the `observe()` hook emitted
- `$entity` — the same entity object, now mutated to post-run state


``` r
nrow(out_single$events)
#> [1] 13
knitr::kable(tail(out_single$observations, 5) |> tibble::rownames_to_column("obs"),
             digits = 3)
```



|obs |  time|event_type         |process_id |route_zone | battery_pct| payload_kg|dispatch_mode |
|:---|-----:|:------------------|:----------|:----------|-----------:|----------:|:-------------|
|8   | 5.364|dispatch_check     |dispatch   |suburban   |      57.306|      6.310|assigned      |
|9   | 5.717|delivery_completed |delivery   |suburban   |      48.676|      4.602|in_transit    |
|10  | 6.643|delivery_completed |delivery   |suburban   |      46.404|      3.028|in_transit    |
|11  | 7.182|delivery_completed |delivery   |suburban   |      45.524|      2.531|in_transit    |
|12  | 8.000|end_shift          |end_shift  |suburban   |      45.524|      2.531|idle          |



``` r
out_single$entity$state(c("battery_pct", "dispatch_mode"))
#> <flux_state>
#> $battery_pct
#> [1] 45.52351
#> 
#> $dispatch_mode
#> [1] "idle"
```

The `observations` table rows are numbered within the observation log (here obs
8–12 are the
last five), not matched to the events log which has 13
rows total. The final event should be `end_shift` — the model's terminal event.
The battery will be lower than it started, and the courier may have completed
several deliveries during the shift.

## Cohort simulation

`run_cohort()` runs the engine over every entity in the list, optionally with
multiple parameter draws (for uncertainty quantification) and multiple simulation
replicates per draw.


``` r
cohort_result <- run_cohort(
  eng,
  entities      = couriers,
  n_param_draws = 1,
  n_sims        = 30,
  max_events    = 500,
  seed          = 42
)
```

Here:
- `n_param_draws = 1` uses one parameter set (no parameter uncertainty yet),
- `n_sims = 30` runs 30 stochastic simulations per courier,
- `max_events = 500` caps events per run for safety,
- `seed = 42` makes the run reproducible.

The result is an indexed list of run outputs. `cohort_result$index` tells you
which courier/parameter-draw/simulation each slot corresponds to.

- `sim_id` is the simulation replicate number within a courier and parameter draw.
- `run_id` is the unique row key for each realized run.


``` r
knitr::kable(head(cohort_result$index))
```



|entity_id  | param_draw_id| sim_id|run_id |
|:----------|-------------:|------:|:------|
|courier_01 |             1|      1|run_1  |
|courier_01 |             1|      2|run_2  |
|courier_01 |             1|      3|run_3  |
|courier_01 |             1|      4|run_4  |
|courier_01 |             1|      5|run_5  |
|courier_01 |             1|      6|run_6  |



``` r

# Deliveries per courier per simulated shift
delivery_counts <- map_int(cohort_result$runs, ~ sum(.x$events$event_type == "delivery_completed"))
summary(delivery_counts)
#>    Min. 1st Qu.  Median    Mean 3rd Qu.    Max. 
#>   0.000   3.000   5.000   4.852   6.000  12.000
```

## Forecasting

`fluxForecast` is one major part of the ecosystem. It takes raw simulation
output and turns it into queryable probabilistic summaries of the future.

### `forecast()` — the entry point

`forecast()` wraps the cohort run into a forecast object that downstream
functions can query. It needs the engine, the entities, and the evaluation
times (the "horizon grid" at which we want predictions).


``` r
times <- seq(0, 8, by = 1)  # include baseline hour 0 for explicit start_time

fc <- forecast(
  engine   = eng,
  entities = couriers,
  times    = times,
  S        = 100,      # 100 simulation draws per courier
  vars     = "battery_pct",
  seed     = 42
)
#> Warning: Model schema omits 'alive'; deriving lifecycle status from
#> bundle$terminal_events.
```

`S` controls the number of forecast draws generated inside `forecast()`. It is
separate from `n_sims` in `run_cohort()`, which controlled the earlier example
run. They can be the same, but they do not need to be.

If you see the warning about missing `alive`, that is expected for this model.
`fluxForecast` then derives lifecycle status from terminal events, which keeps
time-to-event summaries such as `event_prob()` well-defined.

### `event_prob()` — probability of a delivery event

"What fraction of couriers complete at least one delivery by hour *t*,
averaged over simulation replicates?"

The correct estimator for a repeated-simulation cohort study averages
*within-simulation* proportions across replications, rather than pooling all
entity-run pairs into a single denominator. `by = "sim"` does exactly that:
for each of the 100 simulation draws it computes the fraction of the 50-courier
cohort who had the event by time *t*, then averages those 100 proportions.


``` r
ep <- event_prob(fc, event = "delivery_completed", times = times, by = "sim")
knitr::kable(head(ep$result), digits = 3)
```



| time| n_eligible| n_events| event_prob|  risk|
|----:|----------:|--------:|----------:|-----:|
|    0|         50|        0|      0.000| 0.000|
|    1|         50|       16|      0.316| 0.316|
|    2|         50|       31|      0.618| 0.618|
|    3|         50|       40|      0.801| 0.801|
|    4|         50|       45|      0.907| 0.907|
|    5|         50|       48|      0.956| 0.956|



`ep$result` columns: `time`, `n_eligible` (average couriers eligible per
simulation draw), `n_events` (average events per draw), and `event_prob`
(mean proportion across draws). The curve starts at 0 at hour 0 and
approaches 1 by hour 8.



### Battery state over time

**Across 50 couriers (simulation run 1):** fleet heterogeneity — couriers diverge
because they start with different batteries and receive different assignments.
We pull gridded values from `draws()` at integer hours.


``` r
dr_all <- draws(fc, var = "battery_pct", times = times, start_time = 0) |>
  left_join(fc$run_index |> select(run_id, entity_tag, sim_id), by = "run_id") |>
  filter(time < 8)   # hour 8: all couriers have ended shift (no observations)
```


``` r
dr_all |>
  filter(sim_id == 1) |>
  mutate(hour = factor(time)) |>
  ggplot(aes(x = value, y = hour, fill = hour)) +
  geom_violin(show.legend = FALSE, colour = NA, alpha = 0.8) +
  geom_boxplot(width = 0.15, outlier.shape = NA, show.legend = FALSE, colour = "grey30") +
  labs(x = "Battery (%)", y = "Hour",
       title = "Battery distribution across 50 couriers (single simulation run)") +
  theme_minimal()
```

![plot of chunk battery-across-couriers](figure/battery-across-couriers-1.png)

**Across 100 simulation runs (courier\_01):** stochastic spread in a single
courier's battery. Different draws diverge because battery drain is sampled from
an exponential at each event. `draws()` snapshots each run at integer hours via
LOCF and returns one row per (run, hour), giving us 100 draws × 8 hours = 800
rows — enough to show a proper distribution at each hour.


``` r
dr_c01 <- draws(fc, var = "battery_pct", times = 0:7, start_time = 0) |>
  left_join(fc$run_index |> select(run_id, entity_tag), by = "run_id") |>
  filter(entity_tag == "courier_01")

dr_c01 |>
  mutate(hour = factor(time)) |>
  ggplot(aes(x = value, y = hour, fill = hour)) +
  geom_violin(show.legend = FALSE, colour = NA, alpha = 0.8) +
  geom_boxplot(width = 0.15, outlier.shape = NA, show.legend = FALSE, colour = "grey30") +
  labs(x = "Battery (%)", y = "Hour",
       title = "Battery distribution for courier_01 across 100 forecast draws") +
  theme_minimal()
```

![plot of chunk battery-across-sims](figure/battery-across-sims-1.png)

## Varying model parameters

One of the design goals of the bundle architecture is that you can swap
parameters without changing any other code. Let's compare the default dispatch
rate against a slower fleet:


``` r
# Default: dispatch_rate_base = 0.7
eng_slow <- Engine$new(bundle = delivery_bundle(
  params = list(dispatch_rate_base = 0.3)
))

fc_slow <- forecast(
  engine   = eng_slow,
  entities = couriers,
  times    = times,
  S        = 100,
  vars     = "battery_pct",
  seed     = 42
)

ep_slow <- event_prob(fc_slow, event = "delivery_completed", times = times)
```

Compare mean fleet-wide delivery probability at hour 4:


``` r
cat("Default dispatch rate — P(delivery by hour 4):",
  round(ep$result$event_prob[ep$result$time == 4], 3), "\n")
#> Default dispatch rate — P(delivery by hour 4): 0.907
cat("Slow dispatch rate   — P(delivery by hour 4):",
  round(ep_slow$result$event_prob[ep_slow$result$time == 4], 3), "\n")
#> Slow dispatch rate   — P(delivery by hour 4): 0.754
```

The slower dispatch rate produces a flatter event probability curve — agents
receive fewer assignments, so fewer deliveries are completed by any given hour.
This is exactly the kind of "what if" scenario that fleet operators care about:
if demand drops (lower dispatch rate), how does delivery throughput change?

## Summary

| Concept | What you learned |
|---------|-----------------|
| `Entity` cohort | A named list of couriers (independent entities) with heterogeneous starting state |
| `run_cohort()` | Batch simulation with parameter draws and replicates |
| `forecast()` | Wraps cohort output into a queryable forecast object |
| `event_prob()` | Probability of a named event by time *t* |
| `state_summary()` | Distribution of a state variable at each time point |
| `draws()` | Raw per-draw trajectories for detailed inspection |
| Parameter variation | Swap `delivery_bundle(params = ...)` to test scenarios |

**Next:** [03_decisions_policy.md](03_decisions_policy.md) — add decision points
and policies to the model, compare agent outcomes under different dispatch
strategies.
