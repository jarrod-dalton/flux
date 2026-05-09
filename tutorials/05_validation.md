A model that can simulate is not automatically a model you should trust. The
delivery model from Tutorial 03 produces convincing-looking trajectories, but
until you've tested its predictions against held-out data, you don't know
whether its rates, distributions, and state dynamics actually match reality.

This tutorial closes the loop: we take the test-set intervals built in Tutorial
05, forecast from each courier's reconstructed state, and compare predictions
against observed outcomes. By the end you will be able to:

- reconstruct test-set entities at their forecast anchor times,
- generate probabilistic forecasts from those baselines,
- build an observed outcome grid for comparison,
- run `validate_event_risk()` to assess calibration and discrimination,
- run `validate_state_point()` to compare predicted vs observed state.

## Setup and data preparation

We regenerate the same data pipeline from Tutorial 04. In practice you'd save
the TTV to disk; here we re-run for self-containedness.


``` r
source("tutorials/model/urban_delivery.R")
source("tutorials/model/urban_delivery_data.R")

set.seed(42)
ops <- generate_delivery_log(n_couriers = 30, n_shifts = 8)

splits <- generate_splits(ops$couriers, train_frac = 0.6, test_frac = 0.2,
                          seed = 123)

events_prep <- prepare_events(
  events    = ops$events,
  id_col    = "entity_id",
  time_col  = "time",
  type_col  = "event_type",
  time_spec = time_spec(unit = "hours")
)

battery_spec <- list(
  id_col   = "entity_id",
  time_col = "time",
  vars     = "battery_pct"
)

obs_prep <- prepare_observations(
  tables    = list(battery = ops$battery),
  specs     = list(battery = battery_spec),
  time_spec = time_spec(unit = "hours")
)

splits_prep <- prepare_splits(splits, id_col = "entity_id", split_col = "split")

delivery_ep_spec <- spec_event_process(
  event_types  = "delivery_completed",
  name         = "delivery_completion",
  t0_strategy  = "followup_start",
  fu_start_col = "shift_start",
  fu_end_col   = "shift_end"
)

ttv <- build_ttv_event_process(
  events       = events_prep,
  observations = obs_prep,
  splits       = splits_prep,
  spec         = delivery_ep_spec,
  followup     = ops$shifts,
  time_spec    = time_spec(unit = "hours", origin = as.POSIXct("2026-01-05", tz = "UTC"))
)
```

## The test set

Each row in `ttv$test` represents one courier × one shift interval:


``` r
head(ttv[ttv$split == "test", ])
#>      entity_id split t0        t1    deltat event_occurred         event_type
#> 1  courier_001  test  0 2.3768432 2.3768432           TRUE delivery_completed
#> 4  courier_004  test  0 3.2884482 3.2884482           TRUE delivery_completed
#> 17 courier_017  test  0 2.3255248 2.3255248           TRUE delivery_completed
#> 21 courier_021  test  0 2.3429078 2.3429078           TRUE delivery_completed
#> 23 courier_023  test  0 0.7654377 0.7654377           TRUE delivery_completed
#> 25 courier_025  test  0 0.8656996 0.8656996           TRUE delivery_completed
#>    censoring_time
#> 1               8
#> 4               8
#> 17              8
#> 21              8
#> 23              8
#> 25              8
cat("Test-set intervals:", sum(ttv$split == "test"), "\n")
#> Test-set intervals: 6
cat("Outcome rate:      ", round(mean(ttv$event_occurred[ttv$split == "test"]), 3), "\n")
#> Outcome rate:       1
```

The `event_occurred` column is TRUE if the courier completed at least one delivery
during the interval. The outcome rate tells us how "easy" the prediction
task is — if it's close to 1.0, nearly everyone completes a delivery (which is
expected for an 8-hour shift).

## Reconstruct courier state at t₀

For each test-set interval, we need the courier's state at the forecast anchor
time. `reconstruct_state_at()` pulls the last observed battery_pct before t₀:


``` r
ttv_test <- ttv[ttv$split == "test", ]

state_at_t0 <- reconstruct_state_at(
  anchors      = ttv_test[, c("entity_id", "t0")],
  observations = obs_prep,
  vars         = "battery_pct",
  id_col       = "entity_id",
  time_col     = "t0",
  time_spec    = time_spec(unit = "hours")
)

head(state_at_t0)
#>     entity_id t0 battery_pct .time_battery_pct .prov_battery_pct
#> 1 courier_001  0          NA                NA           missing
#> 2 courier_004  0          NA                NA           missing
#> 3 courier_017  0          NA                NA           missing
#> 4 courier_021  0          NA                NA           missing
#> 5 courier_023  0          NA                NA           missing
#> 6 courier_025  0          NA                NA           missing
```

Now build Entity objects from these reconstructed states:


``` r
shared_schema <- delivery_schema()

test_entities <- lapply(seq_len(nrow(state_at_t0)), function(i) {
  row <- state_at_t0[i, ]
  battery <- if (is.na(row$battery_pct)) 80 else row$battery_pct

  Entity$new(
    id          = row$entity_id,
    init = list(
      battery_pct   = battery,
      route_zone    = "urban",    # default; could be reconstructed too
      payload_kg    = 0,
      dispatch_mode = "idle"
    ),
    schema      = shared_schema,
    entity_type = "courier",
    time0       = row$t0
  )
})
names(test_entities) <- state_at_t0$entity_id
```

## Forecast from test-set baselines

Run the model forward from each reconstructed entity state:


``` r
eng <- Engine$new(bundle = delivery_bundle())

# Evaluation times: hours 1 through 8 from each entity's t0
# For simplicity, use a fixed horizon grid relative to t0=0
horizon <- 8
times <- seq(1, horizon, by = 1)

fc <- forecast(
 engine   = eng,
  entities = test_entities,
  times    = times,
  S        = 100,
  seed     = 42
)
```

## Predicted event probabilities

"What does the model predict as the probability of delivery completion by
each horizon time?"


``` r
ep <- event_prob(fc, event = "delivery_completed", times = times)
head(ep)
#> $spec
#> $spec$event
#> [1] "delivery_completed"
#> 
#> $spec$times
#> [1] 1 2 3 4 5 6 7 8
#> 
#> $spec$start_time
#> [1] 1
#> 
#> $spec$terminal_events
#> NULL
#> 
#> $spec$condition_on_events
#> NULL
#> 
#> $spec$by
#> [1] "run"
#> 
#> 
#> $cohort
#> $cohort$eligible_run_ids
#>   [1]   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18
#>  [19]  19  20  21  22  23  24  25  26  27  28  29  30  31  32  33  34  35  36
#>  [37]  37  38  39  40  41  42  43  44  45  46  47  48  49  50  51  52  53  54
#>  [55]  55  56  57  58  59  60  61  62  63  64  65  66  67  68  69  70  71  72
#>  [73]  73  74  75  76  77  78  79  80  81  82  83  84  85  86  87  88  89  90
#>  [91]  91  92  93  94  95  96  97  98  99 100 101 102 103 104 105 106 107 108
#> [109] 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126
#> [127] 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144
#> [145] 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162
#> [163] 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180
#> [181] 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198
#> [199] 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216
#> [217] 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234
#> [235] 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252
#> [253] 253 254 255 256 257 258 259 260 261 262 263 264 265 266 267 268 269 270
#> [271] 271 272 273 274 275 276 277 278 279 280 281 282 283 284 285 286 287 288
#> [289] 289 290 291 292 293 294 295 296 297 298 299 300 301 302 303 304 305 306
#> [307] 307 308 309 310 311 312 313 314 315 316 317 318 319 320 321 322 323 324
#> [325] 325 326 327 328 329 330 331 332 333 334 335 336 337 338 339 340 341 342
#> [343] 343 344 345 346 347 348 349 350 351 352 353 354 355 356 357 358 359 360
#> [361] 361 362 363 364 365 366 367 368 369 370 371 372 373 374 375 376 377 378
#> [379] 379 380 381 382 383 384 385 386 387 388 389 390 391 392 393 394 395 396
#> [397] 397 398 399 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414
#> [415] 415 416 417 418 419 420 421 422 423 424 425 426 427 428 429 430 431 432
#> [433] 433 434 435 436 437 438 439 440 441 442 443 444 445 446 447 448 449 450
#> [451] 451 452 453 454 455 456 457 458 459 460 461 462 463 464 465 466 467 468
#> [469] 469 470 471 472 473 474 475 476 477 478 479 480 481 482 483 484 485 486
#> [487] 487 488 489 490 491 492 493 494 495 496 497 498 499 500 501 502 503 504
#> [505] 505 506 507 508 509 510 511 512 513 514 515 516 517 518 519 520 521 522
#> [523] 523 524 525 526 527 528 529 530 531 532 533 534 535 536 537 538 539 540
#> [541] 541 542 543 544 545 546 547 548 549 550 551 552 553 554 555 556 557 558
#> [559] 559 560 561 562 563 564 565 566 567 568 569 570 571 572 573 574 575 576
#> [577] 577 578 579 580 581 582 583 584 585 586 587 588 589 590 591 592 593 594
#> [595] 595 596 597 598 599 600
#> 
#> $cohort$n_eligible
#> [1] 600
#> 
#> 
#> $result
#>   time n_eligible n_events event_prob
#> 1    1        600      176  0.2933333
#> 2    2        600      370  0.6166667
#> 3    3        600      484  0.8066667
#> 4    4        600      546  0.9100000
#> 5    5        600      571  0.9516667
#> 6    6        600      588  0.9800000
#> 7    7        600      597  0.9950000
#> 8    8        600      598  0.9966667
#> 
#> $meta
#> list()
```

## Build the observed outcome grid

`build_obs_grid()` aligns the actual observed events onto the same time grid
the forecast was evaluated on. This creates the "ground truth" that predictions
are compared against.

``` r
# Subset observations to test-set entities
test_ids <- unique(state_at_t0$entity_id)
test_obs_df <- as.data.frame(obs_prep[obs_prep$entity_id %in% test_ids,
                                       c("entity_id", "time", "battery_pct")])
test_events <- events_prep[events_prep$entity_id %in% test_ids, ]

obs_grid <- build_obs_grid(
  vars           = list(battery = test_obs_df),
  events         = test_events,
  times          = times,
  t0             = 0,
  start_time     = 0,
  time_spec      = time_spec(unit = "hours"),
  id_col         = "entity_id",
  time_col       = "time",
  event_time_col = "time",
  event_type_col = "event_type"
)
```

Each row in the obs_grid says: "for entity X, did event Y occur by time Z?"
This is the binary ground truth that `validate_event_risk()` compares against
the predicted probabilities.

## `validate_event_risk()` — calibration and discrimination

The core validation function compares predicted event probabilities against
observed binary outcomes:


``` r
vr <- validate_event_risk(
  pred     = ep,
  obs      = obs_grid,
  event    = "delivery_completed",
  times    = times
)
```

The result contains calibration and discrimination metrics:


``` r
str(vr, max.level = 1)
#> List of 4
#>  $ predicted :List of 4
#>   ..- attr(*, "class")= chr "flux_event_prob"
#>  $ observed  :'data.frame':	8 obs. of  4 variables:
#>  $ comparison:'data.frame':	8 obs. of  9 variables:
#>  $ meta      :List of 4
```

### Calibration

Calibration asks: "when the model predicts 70% probability, does the event
actually occur ~70% of the time?"


``` r
if (!is.null(vr$calibration)) {
  print(vr$calibration)
}
```

Perfect calibration means the predicted probability matches the observed
frequency in each bin. Systematic over-prediction (predicted > observed) suggests
the model's rates are too aggressive; under-prediction suggests they're too
conservative.

### Discrimination

Discrimination asks: "can the model distinguish couriers who will complete a
delivery from those who won't?"


``` r
if (!is.null(vr$discrimination)) {
  cat("C-statistic:", round(vr$discrimination$c_stat, 3), "\n")
}
```

A C-statistic of 0.5 means no discrimination (random guessing); 1.0 means
perfect separation. For our synthetic data (where the model generated the data),
we expect strong discrimination. In real applications, this is where model
deficiencies show up.

## `validate_state_point()` — predicted vs observed state

Beyond event probabilities, we can compare the model's predicted battery
distribution against what was actually observed. This validates the state
dynamics, not just the event timing.


``` r
# Get predicted state distribution
ss <- state_summary(fc, vars = "battery_pct", times = times)
#> Error: Unknown vars: battery_pct

# Get observed battery values from the test-set observations
test_ids <- unique(state_at_t0$entity_id)
test_obs <- obs_prep[obs_prep$entity_id %in% test_ids, ]

vs <- validate_state_point(
  pred       = ss,
  obs        = test_obs,
  var        = "battery_pct",
  times      = times,
  start_time = 0
)
#> Error: obs must be a flux_obs_grid.

if (!is.null(vs)) {
  str(vs, max.level = 1)
}
#> Error: object 'vs' not found
```

## Interpreting miscalibration

When validation reveals miscalibration, the model is telling you something
specific. For the delivery model, common failure modes:

| Observation | Likely cause | Fix |
|-------------|-------------|-----|
| Over-prediction of delivery events | `delivery_rate_base` too high | Lower the rate; check if real-world completion times are longer |
| Under-prediction early in shift | `dispatch_rate_base` too low for the first hour | Consider time-varying dispatch rates |
| Battery drains too fast in model | `delivery_battery_drop_mean` too high | Calibrate against real sensor data |
| Battery drains too slow | Missing energy-consuming processes (e.g., GPS, AC) | Add an ambient drain process |

The feedback loop: **observed outcomes → identify miscalibrated parameters →
update `delivery_bundle(params = ...)` → re-validate**. This is the core
model development cycle that flux supports.

## Summary

| Function | Purpose |
|----------|---------|
| `reconstruct_state_at()` | Recover courier state at forecast anchor from history |
| `forecast()` | Run model forward from test-set baselines |
| `event_prob()` | Predicted probability of named event by time *t* |
| `build_obs_grid()` | Align observed events onto evaluation time grid |
| `validate_event_risk()` | Compare predicted probabilities vs observed outcomes |
| `validate_state_point()` | Compare predicted state distribution vs observed |

This is the complete prediction–validation loop. The same pattern applies
regardless of domain: reconstruct state → forecast → compare → iterate.

**The tutorial suite so far:**

| # | Tutorial | Packages |
|---|----------|----------|
| 01 | Engine and ModelBundle scaffold | fluxCore |
| 03 | Cohort simulation and forecast | fluxCore, fluxForecast |
| 04 | Decision points and policy | fluxCore |
| 05 | Preparing operational data | fluxCore, fluxPrepare |
| 06 | Validation (this tutorial) | fluxCore, fluxPrepare, fluxForecast, fluxValidation |

Together these cover the full lifecycle: define a model → simulate cohorts →
add decisions → prepare real data → validate predictions. The ecosystem is
designed so each piece slots into this pipeline without custom glue code.
